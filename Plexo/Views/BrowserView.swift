import SwiftUI
import WebKit

// Browser-Integration – entspricht der Browser-Erweiterung von Plexo:
// Downloads im eingebauten Browser abfangen (mit Cookies der Sitzung) und an Plexo übergeben.

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var address = ""
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isLoading = false

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                Task { @MainActor in self?.progress = wv.estimatedProgress }
            },
            webView.observe(\.url) { [weak self] wv, _ in
                Task { @MainActor in self?.address = wv.url?.absoluteString ?? "" }
            },
            webView.observe(\.title) { [weak self] wv, _ in
                Task { @MainActor in self?.title = wv.title ?? "" }
            },
            webView.observe(\.canGoBack) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoForward = wv.canGoForward }
            },
            webView.observe(\.isLoading) { [weak self] wv, _ in
                Task { @MainActor in self?.isLoading = wv.isLoading }
            }
        ]
        load("https://www.google.com")
    }

    func load(_ input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") {
            if text.contains(".") && !text.contains(" ") {
                text = "https://" + text
            } else {
                let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
                text = "https://www.google.com/search?q=\(q)"
            }
        }
        if let url = URL(string: text) { webView.load(URLRequest(url: url)) }
    }

    /// Cookies + Referer + User-Agent der aktuellen Sitzung für einen Link.
    func sessionHeaders(for url: URL) async -> [String: String] {
        var headers: [String: String] = [:]
        let cookies = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        let host = url.host?.lowercased() ?? ""
        let matching = cookies.filter { c in
            let domain = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
        if !matching.isEmpty {
            headers["Cookie"] = matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        if let page = webView.url?.absoluteString { headers["Referer"] = page }
        if let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
            headers["User-Agent"] = ua
        }
        return headers
    }

    func offer(_ url: URL, suggestedName: String?) {
        Task {
            let headers = await sessionHeaders(for: url)
            AddRequest.shared.offer(link: url.absoluteString, headers: headers, fileName: suggestedName)
        }
    }

    // MARK: - Downloads abfangen

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        if let url = response.url,
           response.mimeType == "application/x-bittorrent" || url.pathExtension.lowercased() == "torrent" {
            decisionHandler(.cancel)
            Task {
                let headers = await sessionHeaders(for: url)
                TorrentManager.shared.addTorrentURL(url, headers: headers)
            }
            return
        }
        let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let isAttachment = disposition.contains("attachment")
        if let url = response.url, navigationResponse.isForMainFrame || isAttachment,
           isAttachment || !navigationResponse.canShowMIMEType {
            decisionHandler(.cancel)
            offer(url, suggestedName: response.suggestedFilename)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme?.lowercased() == "magnet" {
            decisionHandler(.cancel)
            AddRequest.shared.offer(link: url.absoluteString, headers: [:], fileName: nil)
            return
        }
        if navigationAction.shouldPerformDownload, let url = navigationAction.request.url {
            decisionHandler(.cancel)
            offer(url, suggestedName: nil)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Links mit target=_blank im selben Fenster öffnen.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggested in
            let plexo = UIAction(title: "Mit Plexo laden", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
                self?.offer(url, suggestedName: nil)
            }
            var items: [UIMenuElement] = [plexo]
            items.append(contentsOf: suggested)
            return UIMenu(children: items)
        }
        completionHandler(config)
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @State private var editing = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: model.address.hasPrefix("https") ? "lock.fill" : "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Suchen oder Adresse eingeben", text: $editing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { model.load(editing) }
                if model.isLoading {
                    Button {
                        model.webView.stopLoading()
                    } label: {
                        Image(systemName: "xmark")
                    }
                } else {
                    Button {
                        model.webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if model.isLoading {
                ProgressView(value: model.progress).progressViewStyle(.linear).frame(height: 2)
            } else {
                Divider()
            }

            WebViewContainer(webView: model.webView)

            HStack {
                Button {
                    model.webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                Spacer()
                Button {
                    model.webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                Spacer()
                Button {
                    if let url = model.webView.url { model.offer(url, suggestedName: nil) }
                } label: {
                    Label("Diese Seite laden", systemImage: "arrow.down.circle")
                        .labelStyle(.iconOnly)
                }
                Spacer()
                Button {
                    model.load("https://www.google.com")
                } label: {
                    Image(systemName: "house")
                }
            }
            .font(.title3)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .onChange(of: model.address) { newValue in
            if !focused { editing = newValue }
        }
    }
}
