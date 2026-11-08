import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        Group {
            if store.playlists.isEmpty {
                EmptyStateView(title: "Keine Playlists", systemImage: "music.note.list",
                               message: "Auf den synchronisierten Servern wurden keine Video-Playlists gefunden.")
            } else {
                List(store.playlists) { playlist in
                    NavigationLink(value: playlist) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name).font(.headline)
                            Text(subtitle(playlist)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Playlists")
    }

    private func subtitle(_ p: Playlist) -> String {
        var s = "\(p.items.count) Einträge"
        if let server = store.server(id: p.serverId) { s += " · \(server.name)" }
        return s
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    let playlist: Playlist

    var body: some View {
        let content = store.playlistItems(playlist)
        List {
            Section {
                Button {
                    downloads.enqueue(playlist: playlist)
                } label: {
                    Label("Gesamte Playlist herunterladen", systemImage: "arrow.down.circle.fill")
                }
                .disabled(content.movies.isEmpty && content.episodes.isEmpty)
            } footer: {
                if content.movies.count + content.episodes.count < playlist.items.count {
                    Text("Einige Einträge sind nicht im lokalen Cache (z. B. Musik oder nicht synchronisierte Bibliotheken).")
                }
            }
            if !content.movies.isEmpty {
                Section("Filme") {
                    ForEach(content.movies) { movie in
                        NavigationLink(value: movie) { MovieRow(movie: movie) }
                    }
                }
            }
            if !content.episodes.isEmpty {
                Section("Episoden") {
                    ForEach(content.episodes) { ep in
                        EpisodeRow(episode: ep, showShowTitle: true)
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var query = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let active = q.count >= 2
        let movies = active ? Array(store.movies.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(50)) : []
        let shows = active ? Array(store.shows.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(50)) : []
        let episodes = active ? Array(store.episodes.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(50)) : []
        List {
            if !active {
                Text("Mindestens zwei Zeichen eingeben.").foregroundStyle(.secondary)
            } else if movies.isEmpty && shows.isEmpty && episodes.isEmpty {
                Text("Keine Treffer für „\(q)“.").foregroundStyle(.secondary)
            }
            if !movies.isEmpty {
                Section("Filme") {
                    ForEach(movies) { m in NavigationLink(value: m) { MovieRow(movie: m) } }
                }
            }
            if !shows.isEmpty {
                Section("Serien") {
                    ForEach(shows) { s in NavigationLink(value: s) { ShowRow(show: s) } }
                }
            }
            if !episodes.isEmpty {
                Section("Episoden") {
                    ForEach(episodes) { e in EpisodeRow(episode: e, showShowTitle: true) }
                }
            }
        }
        .navigationTitle("Suche")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Filme, Serien, Episoden")
    }
}
