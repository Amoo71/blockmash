import SwiftUI

struct MoviesView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var search = ""
    @State private var libraryFilter = ""

    private var movieLibraries: [PlexLibrary] { store.libraries.filter { $0.type == "movie" } }

    private var filtered: [Movie] {
        store.movies.filter { m in
            (libraryFilter.isEmpty || m.libraryId == libraryFilter)
                && (search.isEmpty || m.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.movies.isEmpty {
                    EmptyStateView(title: "Keine Filme", systemImage: "film",
                                   message: store.account == nil
                                       ? "Melde dich unter „Übersicht“ mit deinem Plex-Konto an."
                                       : "Starte unter „Übersicht“ einen vollständigen Sync.")
                } else {
                    List(filtered) { movie in
                        NavigationLink(value: movie) { MovieRow(movie: movie) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Filme")
            .searchable(text: $search, prompt: "Filme durchsuchen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    LibraryFilterMenu(libraries: movieLibraries, selection: $libraryFilter)
                }
            }
            .mediaDestinations()
        }
    }
}

struct MovieRow: View {
    @EnvironmentObject private var store: LibraryStore
    let movie: Movie

    private var subtitle: String {
        var parts: [String] = []
        if let y = movie.year { parts.append(String(y)) }
        if store.servers.count > 1, let s = store.server(id: movie.serverId) { parts.append(s.name) }
        if movie.mediaFiles.count > 1 { parts.append("\(movie.mediaFiles.count) Versionen") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: store.thumbURL(serverId: movie.serverId, thumb: movie.thumb, width: 120, height: 180))
            VStack(alignment: .leading, spacing: 3) {
                Text(movie.title).font(.headline).lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let f = movie.mediaFiles.first {
                    Text(f.shortSummary).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            DownloadStateBadge(mediaKey: movie.id)
        }
    }
}

struct MovieDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    let movie: Movie

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    PosterView(url: store.thumbURL(serverId: movie.serverId, thumb: movie.thumb, width: 300, height: 450),
                               width: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(movie.title).font(.title3.bold())
                        if let y = movie.year { Text(String(y)).foregroundStyle(.secondary) }
                        if let s = store.server(id: movie.serverId) {
                            Label(s.name, systemImage: "server.rack").font(.caption)
                        }
                        if let l = store.library(id: movie.libraryId) {
                            Label(l.name, systemImage: "books.vertical").font(.caption)
                        }
                        DownloadStateBadge(mediaKey: movie.id)
                    }
                }
                if let summary = movie.summary, !summary.isEmpty {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    downloads.enqueue(movie: movie, file: nil)
                } label: {
                    Label("Herunterladen", systemImage: "arrow.down.circle.fill")
                }
                if let item = downloads.latestItem(forMediaKey: movie.id) {
                    DownloadInlineStatus(item: item)
                }
            } footer: {
                Text("Lädt die bevorzugte Version (siehe Einstellungen).")
            }
            Section("Versionen (\(movie.mediaFiles.count))") {
                ForEach(movie.mediaFiles) { file in
                    MediaFileRow(file: file, serverId: movie.serverId) {
                        downloads.enqueue(movie: movie, file: file)
                    }
                }
            }
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DownloadInlineStatus: View {
    let item: DownloadItem

    var body: some View {
        switch item.status {
        case .queued:
            Label("In der Warteschlange", systemImage: "clock").foregroundStyle(.orange)
        case .running:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: item.progress)
                Text("\(Format.bytes(item.downloadedBytes)) von \(Format.bytes(item.totalBytes))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        case .finished:
            Label("Heruntergeladen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label(item.message ?? "Fehlgeschlagen", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Label("Abgebrochen", systemImage: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}
