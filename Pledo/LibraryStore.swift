import Foundation
import SwiftUI

// Lokaler Metadaten-Cache + Sync – entspricht SyncService, LoginService und der Datenbank in pledo.

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var account: PlexAccount?
    @Published private(set) var servers: [PlexServer] = []
    @Published private(set) var libraries: [PlexLibrary] = []
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var shows: [TvShow] = []
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    @Published var syncStatus = ""
    @Published var lastError: String?

    private var episodesByShow: [String: [Episode]] = [:]
    private var movieIndex: [String: Movie] = [:]
    private var episodeIndex: [String: Episode] = [:]
    private var showIndex: [String: TvShow] = [:]

    let client = PlexClient.shared
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Pledo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        load()
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) else { return }
        account = cache.account
        servers = cache.servers
        libraries = cache.libraries
        movies = cache.movies
        shows = cache.shows
        episodes = cache.episodes
        playlists = cache.playlists
        lastSync = cache.lastSync
        rebuildIndexes()
    }

    func save() {
        let cache = LibraryCache(account: account, servers: servers, libraries: libraries, movies: movies,
                                 shows: shows, episodes: episodes, playlists: playlists, lastSync: lastSync)
        let url = fileURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func rebuildIndexes() {
        var byShow: [String: [Episode]] = [:]
        for e in episodes { byShow[e.showId, default: []].append(e) }
        for (k, v) in byShow {
            byShow[k] = v.sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
        }
        episodesByShow = byShow
        movieIndex = Dictionary(movies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        episodeIndex = Dictionary(episodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        showIndex = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Abfragen

    func server(id: String) -> PlexServer? { servers.first { $0.id == id } }
    func library(id: String) -> PlexLibrary? { libraries.first { $0.id == id } }
    func movie(id: String) -> Movie? { movieIndex[id] }
    func episode(id: String) -> Episode? { episodeIndex[id] }
    func show(id: String) -> TvShow? { showIndex[id] }
    func episodes(forShow show: TvShow) -> [Episode] { episodesByShow[show.id] ?? [] }

    func playlistItems(_ playlist: Playlist) -> (movies: [Movie], episodes: [Episode]) {
        var m: [Movie] = []
        var e: [Episode] = []
        for rk in playlist.items {
            let id = "\(playlist.serverId)/\(rk)"
            if let movie = movieIndex[id] { m.append(movie) } else if let ep = episodeIndex[id] { e.append(ep) }
        }
        return (m, e)
    }

    func thumbURL(serverId: String, thumb: String?, width: Int = 240, height: Int = 360) -> URL? {
        guard let s = server(id: serverId) else { return nil }
        return client.thumbURL(base: s.lastKnownUri, thumb: thumb, token: s.accessToken, width: width, height: height)
    }

    func directDownloadURL(serverId: String, file: MediaFile) -> URL? {
        guard let s = server(id: serverId), let base = s.lastKnownUri else { return nil }
        return try? client.downloadURL(base: base, partKey: file.downloadUri, token: s.accessToken)
    }

    func updateServerUri(serverId: String, uri: String?) {
        guard let i = servers.firstIndex(where: { $0.id == serverId }) else { return }
        if let uri { servers[i].lastKnownUri = uri }
        servers[i].isOnline = uri != nil
        servers[i].lastChecked = Date()
        save()
    }

    // MARK: - Konto

    func login(token: String) async throws {
        let acc = try await client.account(token: token)
        account = acc
        save()
        Task { await self.sync(full: true) }
    }

    func logout() {
        account = nil
        servers = []
        libraries = []
        movies = []
        shows = []
        episodes = []
        playlists = []
        lastSync = nil
        lastError = nil
        rebuildIndexes()
        save()
    }

    func clearCache() {
        libraries = []
        movies = []
        shows = []
        episodes = []
        playlists = []
        lastSync = nil
        rebuildIndexes()
        save()
    }

    func onLaunch() async {
        guard account != nil else { return }
        if lastSync == nil {
            await sync(full: true)
        } else if Prefs.syncOnLaunch {
            await sync(full: false)
        }
    }

    // MARK: - Sync

    /// full = false: nur Server & Verbindungen aktualisieren (wie der periodische Sync in pledo).
    func sync(full: Bool) async {
        guard let account, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            syncStatus = ""
        }
        do {
            syncStatus = "Lade Serverliste von plex.tv…"
            var fetched = try await client.servers(token: account.authToken)
            let previous = Dictionary(servers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            syncStatus = "Prüfe Verbindungen zu \(fetched.count) Server(n)…"
            let c = client
            let uris: [String: String] = await withTaskGroup(of: (String, String?).self) { group in
                for s in fetched {
                    group.addTask {
                        let uri = await c.fastestConnection(for: s)
                        return (s.id, uri)
                    }
                }
                var result: [String: String] = [:]
                for await (id, uri) in group {
                    if let uri { result[id] = uri }
                }
                return result
            }
            for i in fetched.indices {
                let uri = uris[fetched[i].id]
                fetched[i].lastKnownUri = uri ?? previous[fetched[i].id]?.lastKnownUri
                fetched[i].isOnline = uri != nil
                fetched[i].lastChecked = Date()
            }
            fetched.sort { ($0.owned ? 0 : 1, $0.name.lowercased()) < ($1.owned ? 0 : 1, $1.name.lowercased()) }
            servers = fetched

            guard full else {
                save()
                return
            }

            var newLibraries: [PlexLibrary] = []
            var newMovies: [Movie] = []
            var newShows: [TvShow] = []
            var newEpisodes: [Episode] = []
            var newPlaylists: [Playlist] = []
            var syncedServers = Set<String>()
            var errors: [String] = []

            for server in fetched where server.isOnline {
                guard let uri = server.lastKnownUri else { continue }
                do {
                    syncStatus = "\(server.name): Bibliotheken…"
                    let libs = try await client.libraries(server: server, uri: uri)
                    var sLibs: [PlexLibrary] = []
                    var sMovies: [Movie] = []
                    var sShows: [TvShow] = []
                    var sEpisodes: [Episode] = []
                    for lib in libs {
                        let label = "\(server.name) · \(lib.name)"
                        switch lib.type {
                        case "movie":
                            sMovies += try await client.movies(library: lib, server: server, uri: uri) { done, total in
                                Task { @MainActor in self.syncStatus = "\(label): \(done)/\(total) Filme" }
                            }
                        case "show":
                            sShows += try await client.shows(library: lib, server: server, uri: uri) { done, total in
                                Task { @MainActor in self.syncStatus = "\(label): \(done)/\(total) Serien" }
                            }
                            sEpisodes += try await client.episodes(library: lib, server: server, uri: uri) { done, total in
                                Task { @MainActor in self.syncStatus = "\(label): \(done)/\(total) Episoden" }
                            }
                        default:
                            continue
                        }
                        sLibs.append(lib)
                    }
                    syncStatus = "\(server.name): Playlists…"
                    let pls = (try? await client.playlists(server: server, uri: uri)) ?? []
                    newLibraries += sLibs
                    newMovies += sMovies
                    newShows += sShows
                    newEpisodes += sEpisodes
                    newPlaylists += pls
                    syncedServers.insert(server.id)
                } catch {
                    errors.append("\(server.name): \(error.localizedDescription)")
                }
            }

            // Daten von Servern behalten, die gerade offline sind, aber noch freigegeben sind.
            let known = Set(fetched.map(\.id))
            func keep(_ serverId: String) -> Bool { known.contains(serverId) && !syncedServers.contains(serverId) }
            newLibraries += libraries.filter { keep($0.serverId) }
            newMovies += movies.filter { keep($0.serverId) }
            newShows += shows.filter { keep($0.serverId) }
            newEpisodes += episodes.filter { keep($0.serverId) }
            newPlaylists += playlists.filter { keep($0.serverId) }

            syncStatus = "Sortiere…"
            libraries = newLibraries
            movies = newMovies.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            shows = newShows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            episodes = newEpisodes
            playlists = newPlaylists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            lastSync = Date()
            rebuildIndexes()
            if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
