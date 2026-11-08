import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DownloadManager.maxConcurrentKey) private var maxConcurrent = 3
    @AppStorage(DownloadManager.defaultStreamsKey) private var defaultStreams = 0
    @AppStorage(DownloadManager.globalLimitKey) private var globalLimit = 0
    @AppStorage(DownloadManager.slowModeKey) private var slowMode = false
    @AppStorage(DownloadManager.slowModeLimitKey) private var slowLimit = 512 * 1024
    @AppStorage(DownloadManager.keepAwakeKey) private var keepAwake = false
    @AppStorage(DownloadManager.bgPartsKey) private var bgParts = 6
    @AppStorage(DownloadManager.turboDefaultKey) private var turboDefault = true
    @AppStorage(DownloadManager.notifyKey) private var notify = true
    @AppStorage(DownloadManager.folderKey) private var folder = "Downloads"
    @AppStorage(TorrentManager.seedKey) private var seed = false
    @AppStorage(TorrentManager.uploadLimitKey) private var uploadLimit = 200 * 1024

    private static let speedOptions: [Int] = [0, 256 * 1024, 512 * 1024, 1 << 20, 2 << 20, 5 << 20, 10 << 20, 20 << 20, 50 << 20, 100 << 20]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Gleichzeitige Downloads: \(maxConcurrent)", value: $maxConcurrent, in: 1...8)
                    Picker("Streams pro Netzwerk", selection: $defaultStreams) {
                        Text("Automatisch").tag(0)
                        ForEach([1, 2, 4, 8, 16], id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    Toggle("Turbo standardmäßig an", isOn: $turboDefault)
                    Stepper("Hintergrund-Teile: \(bgParts)", value: $bgParts, in: 1...16)
                } header: {
                    Text("Warteschlange & Engines")
                } footer: {
                    Text("Turbo kombiniert WLAN + Mobilfunk, solange Plexo offen ist. Im Hintergrund übernimmt iOS: die Datei wird in parallele Teile zerlegt und läuft auch bei gesperrtem Bildschirm oder geschlossener App weiter.")
                }

                Section {
                    Picker("Gesamtlimit", selection: $globalLimit) {
                        ForEach(Self.speedOptions, id: \.self) { v in
                            Text(v == 0 ? "Unbegrenzt" : Format.speed(Double(v))).tag(v)
                        }
                    }
                    Toggle("Langsam-Modus", isOn: $slowMode)
                    if slowMode {
                        Picker("Langsam-Modus Tempo", selection: $slowLimit) {
                            ForEach(Self.speedOptions.filter { $0 > 0 }, id: \.self) { v in
                                Text(Format.speed(Double(v))).tag(v)
                            }
                        }
                    }
                } header: {
                    Text("Bandbreite")
                } footer: {
                    Text("Langsam-Modus lässt Bandbreite für Anrufe und Streaming übrig. Limits pro Netzwerk und Datenvolumen findest du im Tab „Netzwerke“.")
                }

                Section {
                    LabeledContent("Ordner") {
                        TextField("Downloads", text: $folder)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    Toggle("Bildschirm während Downloads anlassen", isOn: $keepAwake)
                    Toggle("Mitteilung, wenn fertig", isOn: $notify)
                } header: {
                    Text("Allgemein")
                } footer: {
                    Text("Downloads laufen im Hintergrund weiter. Nur wenn du Plexo im App-Umschalter wegwischst, stoppt iOS sie – beim nächsten Öffnen geht es an derselben Stelle weiter.")
                }

                Section {
                    Toggle("Nach Abschluss weiter seeden", isOn: $seed)
                    Picker("Upload-Limit", selection: $uploadLimit) {
                        ForEach(Self.speedOptions, id: \.self) { v in
                            Text(v == 0 ? "Unbegrenzt" : Format.speed(Double(v))).tag(v)
                        }
                    }
                } header: {
                    Text("Torrents")
                } footer: {
                    Text("Torrents laufen, solange Plexo geöffnet ist (iOS erlaubt Torrent-Verbindungen nicht im Hintergrund). Fortschritt bleibt erhalten und geht beim nächsten Öffnen weiter.")
                }

                Section("Info") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Link("Original: anmolkapil/plexo", destination: URL(string: "https://github.com/anmolkapil/plexo")!)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        downloads.applyLimits()
                        downloads.updateIdleTimer()
                        dismiss()
                    }
                }
            }
            .onChange(of: slowMode) { _ in downloads.applyLimits() }
            .onChange(of: globalLimit) { _ in downloads.applyLimits() }
        }
    }
}
