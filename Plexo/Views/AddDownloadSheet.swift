import SwiftUI
import UIKit

// „Neuer Download“ – entspricht NewDownloadDialog.tsx in Plexo.

struct AddDownloadSheet: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var networks: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    let initialLinks: String?
    let headers: [String: String]
    let fileName: String?
    let onAdded: () -> Void

    @State private var links = ""
    @State private var name = ""
    @State private var selected: Set<NetworkKind> = []
    @State private var streams = 0
    @State private var turbo = true
    @State private var didLoad = false

    private var parsedLinks: [String] {
        links.split(whereSeparator: { $0.isNewline || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $links)
                        .frame(minHeight: 90)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        if let s = UIPasteboard.general.string { links = s }
                    } label: {
                        Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Links")
                } footer: {
                    Text(parsedLinks.count > 1 ? "\(parsedLinks.count) Links erkannt – einer pro Zeile." : "Direkte Download-Links (http/https). Mehrere Links: einer pro Zeile.")
                }

                if parsedLinks.count <= 1 {
                    Section("Dateiname (optional)") {
                        TextField("Automatisch vom Server", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    ForEach(networks.visibleKinds) { kind in
                        Toggle(isOn: Binding(get: { selected.contains(kind) },
                                             set: { on in if on { selected.insert(kind) } else { selected.remove(kind) } })) {
                            HStack(spacing: 10) {
                                Image(systemName: kind.symbol)
                                    .foregroundStyle(networks.color(kind))
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(networks.name(kind))
                                    Text(networks.status(kind).label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Netzwerke kombinieren")
                } footer: {
                    Text("Jedes Netzwerk lädt eigene Teile der Datei. Mehr Tempo gibt es nur, wenn jedes Netzwerk seine eigene Internetverbindung hat (z. B. WLAN + Mobilfunk). Netzwerke lassen sich auch während des Downloads an- und ausschalten.")
                }

                Section {
                    Toggle(isOn: $turbo) {
                        VStack(alignment: .leading) {
                            Text("Turbo: Netzwerke kombinieren")
                            Text(turbo ? "Im Vordergrund über alle Netzwerke, im Hintergrund automatisch weiter über iOS"
                                       : "Nur Hintergrund-Modus – iOS lädt stabil weiter, auch bei gesperrtem Bildschirm")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Streams pro Netzwerk", selection: $streams) {
                        Text("Automatisch").tag(0)
                        ForEach([1, 2, 4, 8, 16], id: \.self) { n in Text("\(n)").tag(n) }
                    }
                } footer: {
                    Text("Automatisch startet mit 4 Verbindungen pro Netzwerk und verdoppelt bis 16, solange der Server mitmacht.")
                }
            }
            .navigationTitle("Neuer Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Laden") {
                        let count = downloads.add(links: parsedLinks, headers: headers,
                                                  networks: NetworkKind.allCases.filter { selected.contains($0) },
                                                  streams: streams, fileName: name, turbo: turbo)
                        if count > 0 {
                            onAdded()
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(parsedLinks.isEmpty || selected.isEmpty)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                streams = downloads.defaultStreams
                turbo = downloads.turboDefault
                selected = Set(NetworkKind.allCases.filter { networks.settings[$0]?.enabled ?? true })
                if let initialLinks {
                    links = initialLinks
                } else if let clip = UIPasteboard.general.string,
                          clip.lowercased().hasPrefix("http"), clip.count < 4000 {
                    links = clip
                }
                if let fileName { name = fileName }
            }
        }
    }
}
