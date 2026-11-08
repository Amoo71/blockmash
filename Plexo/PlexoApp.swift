import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Hintergrund-Session sofort wieder verbinden, damit iOS fertige Teile zustellen kann.
        _ = BackgroundDownloader.shared.session
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackgroundDownloader.shared.setCompletionHandler(completionHandler)
        _ = DownloadManager.shared
    }
}

@main
struct PlexoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var networks = NetworkMonitor.shared
    @StateObject private var files = FilesStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(downloads)
                .environmentObject(networks)
                .environmentObject(files)
                .task { downloads.resumeOnLaunch() }
                .onOpenURL { url in AddRequest.shared.handle(url) }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: downloads.enterBackground()
            case .active: downloads.enterForeground()
            default: break
            }
        }
    }
}

/// Links, die von außen kommen (plexo://add?url=… oder geteilte http-Links).
@MainActor
final class AddRequest: ObservableObject {
    static let shared = AddRequest()
    @Published var pending: PendingAdd?

    struct PendingAdd: Identifiable {
        let id = UUID()
        let links: [String]
        let headers: [String: String]
        let fileName: String?
    }

    func handle(_ url: URL) {
        if url.scheme?.lowercased() == "plexo",
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let link = comps.queryItems?.first(where: { $0.name == "url" })?.value {
            pending = PendingAdd(links: [link], headers: [:], fileName: nil)
        } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            pending = PendingAdd(links: [url.absoluteString], headers: [:], fileName: nil)
        }
    }

    func offer(link: String, headers: [String: String], fileName: String?) {
        pending = PendingAdd(links: [link], headers: headers, fileName: fileName)
    }
}

struct RootView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var networks: NetworkMonitor
    @StateObject private var addRequest = AddRequest.shared
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .badge(downloads.activeCount)
                .tag(0)
            BrowserView()
                .tabItem { Label("Browser", systemImage: "safari") }
                .tag(1)
            NetworksView()
                .tabItem { Label("Netzwerke", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(2)
            FilesView()
                .tabItem { Label("Dateien", systemImage: "folder") }
                .tag(3)
        }
        .tint(Color(hex: "#7C5CFF"))
        .sheet(item: $addRequest.pending) { req in
            AddDownloadSheet(initialLinks: req.links.joined(separator: "\n"), headers: req.headers,
                             fileName: req.fileName) {
                tab = 0
            }
            .environmentObject(downloads)
            .environmentObject(networks)
        }
    }
}
