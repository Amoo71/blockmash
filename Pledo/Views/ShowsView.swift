import SwiftUI

struct ShowsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var search = ""
    @State private var libraryFilter = ""

    private var showLibraries: [PlexLibrary] { store.libraries.filter { $0.type == "show" } }

    private var filtered: [TvShow] {
        store.shows.filter { s in
            (libraryFilter.isEmpty || s.libraryId == libraryFilter)
                && (search.isEmpty || s.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.shows.isEmpty {
                    EmptyStateView(title: "Keine Serien", systemImage: "tv",
                                   message: store.account == nil
                                       ? "Melde dich unter „Übersicht“ mit deinem Plex-Konto an."
                                       : "Starte unter „Übersicht“ einen vollständigen Sync.")
                } else {
                    List(filtered) { show in
                        NavigationLink(value: show) { ShowRow(show: show) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Serien")
            .searchable(text: $search, prompt: "Serien durchsuchen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    LibraryFilterMenu(libraries: showLibraries, selection: $libraryFilter)
                }
            }
            .mediaDestinations()
        }
    }
}

struct ShowRow: View {
    @EnvironmentObject private var store: LibraryStore
    let show: TvShow

    private var subtitle: String {
        var parts: [String] = []
        if let y = show.year { parts.append(String(y)) }
        let count = store.episodes(forShow: show).count
        parts.append("\(count) Episoden")
        if store.servers.count > 1, let s = store.server(id: show.serverId) { parts.append(s.name) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: store.thumbURL(serverId: show.serverId, thumb: show.thumb, width: 120, height: 180),
                       symbol: "tv")
            VStack(alignment: .leading, spacing: 3) {
                Text(show.title).font(.headline).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct SeasonGroup: Identifiable {
    let number: Int
    let episodes: [Episode]
    var id: Int { number }
    var title: String { number == 0 ? "Specials" : "Staffel \(number)" }
    var totalBytes: Int64 {
        episodes.reduce(0) { $0 + (DownloadManager.selectFile($1.mediaFiles)?.totalBytes ?? 0) }
    }
}

struct ShowDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    let show: TvShow
    @State private var confirmAll = false

    private var seasons: [SeasonGroup] {
        let grouped = Dictionary(grouping: store.episodes(forShow: show), by: \.seasonNumber)
        return grouped.keys.sorted().map { key in
            SeasonGroup(number: key, episodes: (grouped[key] ?? []).sorted { $0.episodeNumber < $1.episodeNumber })
        }
    }

    var body: some View {
        let groups = seasons
        let totalBytes = groups.reduce(Int64(0)) { $0 + $1.totalBytes }
        let episodeCount = groups.reduce(0) { $0 + $1.episodes.count }
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    PosterView(url: store.thumbURL(serverId: show.serverId, thumb: show.thumb, width: 300, height: 450),
                               width: 100, symbol: "tv")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(show.title).font(.title3.bold())
                        if let y = show.year { Text(String(y)).foregroundStyle(.secondary) }
                        Text("\(groups.count) Staffeln · \(episodeCount) Episoden")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("ca. \(Format.bytes(totalBytes))").font(.caption).foregroundStyle(.secondary)
                        if let s = store.server(id: show.serverId) {
                            Label(s.name, systemImage: "server.rack").font(.caption)
                        }
                    }
                }
                if let summary = show.summary, !summary.isEmpty {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    confirmAll = true
                } label: {
                    Label("Ganze Serie herunterladen", systemImage: "arrow.down.circle.fill")
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.episodes) { ep in
                        EpisodeRow(episode: ep)
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Button {
                            downloads.enqueue(show: show, season: group.number)
                        } label: {
                            Label("Staffel laden", systemImage: "arrow.down.circle")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderless)
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("\(episodeCount) Episoden (ca. \(Format.bytes(totalBytes))) herunterladen?",
                            isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Alle herunterladen") { downloads.enqueue(show: show) }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var downloads: DownloadManager
    let episode: Episode
    var showShowTitle = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if showShowTitle {
                    Text(episode.showTitle).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(episode.code) · \(episode.title)").font(.subheadline).lineLimit(2)
                if let f = episode.mediaFiles.first {
                    Text(f.shortSummary).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            DownloadStateBadge(mediaKey: episode.id)
            DownloadMenuButton(files: episode.mediaFiles,
                               onDefault: { downloads.enqueue(episode: episode, file: nil) },
                               onFile: { downloads.enqueue(episode: episode, file: $0) })
        }
    }
}
