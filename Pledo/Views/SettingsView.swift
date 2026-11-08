import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.moviesFolderKey) private var moviesFolder = Prefs.defaultMoviesFolder
    @AppStorage(Prefs.showsFolderKey) private var showsFolder = Prefs.defaultShowsFolder
    @AppStorage(Prefs.movieTemplateKey) private var movieTemplate = MovieTemplate.fileName.rawValue
    @AppStorage(Prefs.episodeTemplateKey) private var episodeTemplate = EpisodeTemplate.seriesAndSeason.rawValue
    @AppStorage(Prefs.preferredResolutionKey) private var preferredResolution = ""
    @AppStorage(Prefs.preferredVideoCodecKey) private var preferredVideoCodec = ""
    @AppStorage(Prefs.keepAwakeKey) private var keepAwake = true
    @AppStorage(Prefs.syncOnLaunchKey) private var syncOnLaunch = true

    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Filme") {
                        TextField("Filme", text: $moviesFolder)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Serien") {
                        TextField("Serien", text: $showsFolder)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Speicherort")
                } footer: {
                    Text("Ordner innerhalb des Dokumente-Ordners der App. Die Dateien findest du in der Dateien-App (bei LiveContainer unter „LiveContainer“ › Data).")
                }

                Section("Dateistruktur") {
                    Picker("Filme", selection: $movieTemplate) {
                        ForEach(MovieTemplate.allCases) { t in Text(t.label).tag(t.rawValue) }
                    }
                    Picker("Serien", selection: $episodeTemplate) {
                        ForEach(EpisodeTemplate.allCases) { t in Text(t.label).tag(t.rawValue) }
                    }
                }

                Section {
                    Picker("Auflösung", selection: $preferredResolution) {
                        ForEach(Prefs.resolutions) { r in Text(r.label).tag(r.value) }
                    }
                    Picker("Video-Codec", selection: $preferredVideoCodec) {
                        ForEach(Prefs.videoCodecs) { c in Text(c.label).tag(c.value) }
                    }
                } header: {
                    Text("Bevorzugte Version")
                } footer: {
                    Text("Wird genutzt, wenn ein Titel in mehreren Versionen vorliegt (z. B. bei Staffel- oder Playlist-Downloads).")
                }

                Section {
                    Toggle("Bildschirm während Downloads anlassen", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _ in downloads.updateIdleTimer() }
                    Toggle("Verbindungen beim Start prüfen", isOn: $syncOnLaunch)
                } header: {
                    Text("Verhalten")
                } footer: {
                    Text("iOS pausiert Downloads, sobald die App im Hintergrund ist. Lass Pledo im Vordergrund geöffnet, bis die Downloads fertig sind.")
                }

                Section("Konto & Daten") {
                    if let account = store.account {
                        LabeledContent("Angemeldet als", value: account.displayName)
                        Button("Metadaten-Cache leeren") { store.clearCache() }
                        Button("Abmelden", role: .destructive) { confirmLogout = true }
                    } else {
                        Text("Nicht angemeldet").foregroundStyle(.secondary)
                    }
                }

                Section("Info") {
                    LabeledContent("Version", value: store.client.appVersion)
                    LabeledContent("Client-ID") {
                        Text(store.client.clientIdentifier).font(.caption2).foregroundStyle(.secondary)
                    }
                    Link("Original-Projekt pledo (fxsth)", destination: URL(string: "https://github.com/fxsth/pledo")!)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Abmelden und alle Metadaten löschen?", isPresented: $confirmLogout,
                                titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) {
                    downloads.cancelAll()
                    store.logout()
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}
