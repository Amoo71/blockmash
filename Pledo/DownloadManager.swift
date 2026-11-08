import Foundation
import UIKit

// Download-Warteschlange – entspricht DownloadService in pledo
// (sequentiell, 5 Wiederholungen mit exponentiellem Backoff, Verbindungswechsel bei Fehlern).

enum DownloadStatus: String, Codable, Sendable {
    case queued, running, finished, failed, cancelled
}

struct DownloadItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var subtitle: String?
    var elementType: ElementType
    var mediaKey: String
    var serverId: String
    var partKey: String
    var relativePath: String
    var totalBytes: Int64
    var downloadedBytes: Int64 = 0
    var status: DownloadStatus = .queued
    var message: String?
    var added = Date()
    var started: Date?
    var finished: Date?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var speeds: [UUID: Double] = [:]

    private var worker: Task<Void, Never>?
    private var activeRunner: DownloadRunner?
    private var cancelRequested: Set<UUID> = []
    private var speedSamples: [UUID: (time: Date, bytes: Int64)] = [:]
    private var lastSave = Date.distantPast
    private let storeURL: URL

    private var store: LibraryStore { LibraryStore.shared }

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Pledo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("downloads.json")
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = decoded.map { item in
                var i = item
                if i.status == .running {
                    i.status = .queued
                    i.message = "Fortgesetzt nach Neustart"
                }
                return i
            }
        }
    }

    // MARK: - Abfragen

    var active: [DownloadItem] { items.filter { $0.status == .running } }
    var queued: [DownloadItem] { items.filter { $0.status == .queued } }
    var history: [DownloadItem] {
        items.filter { $0.status == .finished || $0.status == .failed || $0.status == .cancelled }
            .sorted { ($0.finished ?? $0.added) > ($1.finished ?? $1.added) }
    }
    var pendingCount: Int { items.filter { $0.status == .queued || $0.status == .running }.count }

    func latestItem(forMediaKey key: String) -> DownloadItem? {
        items.last { $0.mediaKey == key }
    }

    func fileURL(for item: DownloadItem) -> URL {
        Self.documentsURL.appendingPathComponent(item.relativePath)
    }

    func fileExists(_ item: DownloadItem) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: item).path)
    }

    // MARK: - Einreihen

    func enqueue(movie: Movie, file: MediaFile?) {
        guard let f = file ?? Self.selectFile(movie.mediaFiles) else { return }
        add(DownloadItem(name: movie.displayTitle, subtitle: f.summary, elementType: .movie, mediaKey: movie.id,
                         serverId: movie.serverId, partKey: f.downloadUri,
                         relativePath: Self.moviePath(movie, f), totalBytes: f.totalBytes))
    }

    func enqueue(episode: Episode, file: MediaFile?) {
        guard let f = file ?? Self.selectFile(episode.mediaFiles) else { return }
        add(DownloadItem(name: "\(episode.showTitle) – \(episode.code) – \(episode.title)", subtitle: f.summary,
                         elementType: .episode, mediaKey: episode.id, serverId: episode.serverId,
                         partKey: f.downloadUri, relativePath: Self.episodePath(episode, f), totalBytes: f.totalBytes))
    }

    func enqueue(show: TvShow, season: Int? = nil) {
        for ep in store.episodes(forShow: show) where season == nil || ep.seasonNumber == season {
            enqueue(episode: ep, file: nil)
        }
    }

    func enqueue(playlist: Playlist) {
        let content = store.playlistItems(playlist)
        for m in content.movies { enqueue(movie: m, file: nil) }
        for e in content.episodes { enqueue(episode: e, file: nil) }
    }

    private func add(_ item: DownloadItem) {
        let duplicate = items.contains { other in
            guard other.mediaKey == item.mediaKey, other.partKey == item.partKey else { return false }
            switch other.status {
            case .queued, .running: return true
            case .finished: return fileExists(other)
            default: return false
            }
        }
        if duplicate { return }
        items.append(item)
        save()
        startQueueIfNeeded()
    }

    // MARK: - Steuerung

    func resumePendingDownloads() {
        startQueueIfNeeded()
    }

    func cancel(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item.status {
        case .queued:
            update(id) {
                $0.status = .cancelled
                $0.finished = Date()
            }
            save()
        case .running:
            cancelRequested.insert(id)
            activeRunner?.cancel()
        default:
            break
        }
    }

    func cancelAll() {
        for item in items where item.status == .queued || item.status == .running { cancel(item.id) }
    }

    func retry(_ id: UUID) {
        update(id) {
            $0.status = .queued
            $0.message = nil
            $0.downloadedBytes = 0
            $0.finished = nil
            $0.started = nil
        }
        save()
        startQueueIfNeeded()
    }

    func remove(_ id: UUID, deleteFile: Bool) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.status == .running || item.status == .queued { return }
        if deleteFile { try? FileManager.default.removeItem(at: fileURL(for: item)) }
        items.removeAll { $0.id == id }
        save()
    }

    func clearHistory() {
        items.removeAll { $0.status == .finished || $0.status == .failed || $0.status == .cancelled }
        save()
    }

    // MARK: - Warteschlange

    private func startQueueIfNeeded() {
        guard worker == nil, items.contains(where: { $0.status == .queued }) else { return }
        worker = Task { [weak self] in
            await self?.runQueue()
        }
        updateIdleTimer()
    }

    private func runQueue() async {
        while let next = items.first(where: { $0.status == .queued }) {
            await download(next.id)
        }
        worker = nil
        updateIdleTimer()
    }

    func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = Prefs.keepAwake && worker != nil
    }

    private func download(_ id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard let server = store.server(id: item.serverId) else {
            finish(id, .failed, "Server ist nicht mehr verfügbar")
            return
        }
        update(id) {
            $0.status = .running
            $0.started = Date()
            $0.message = nil
            $0.downloadedBytes = 0
        }

        var resumeData: Data?
        var attempt = 0
        var base = server.lastKnownUri

        while !cancelRequested.contains(id) {
            if base == nil {
                update(id) { $0.message = "Suche Verbindung zu \(server.name)…" }
                base = await store.client.fastestConnection(for: server)
                store.updateServerUri(serverId: server.id, uri: base)
            }
            guard let baseUri = base,
                  let url = try? store.client.downloadURL(base: baseUri, partKey: item.partKey,
                                                          token: server.accessToken) else {
                finish(id, .failed, PlexError.serverUnreachable(server.name).localizedDescription)
                return
            }
            var request = URLRequest(url: url)
            for (k, v) in store.client.headers(token: server.accessToken) where k != "Accept" {
                request.setValue(v, forHTTPHeaderField: k)
            }

            let runner = DownloadRunner()
            activeRunner = runner
            let result: Result<URL, Error>
            do {
                let tmp = try await runner.run(request: request, resumeData: resumeData) { [weak self] written, expected in
                    Task { @MainActor in self?.progress(id, written, expected) }
                }
                result = .success(tmp)
            } catch {
                result = .failure(error)
            }
            activeRunner = nil

            switch result {
            case .success(let tmp):
                do {
                    try moveIntoPlace(tmp, item)
                    finish(id, .finished, nil)
                } catch {
                    try? FileManager.default.removeItem(at: tmp)
                    finish(id, .failed, "Datei konnte nicht gespeichert werden: \(error.localizedDescription)")
                }
                return
            case .failure(let error):
                if cancelRequested.contains(id) { break }
                attempt += 1
                resumeData = runner.resumeData
                if attempt > 5 {
                    finish(id, .failed, error.localizedDescription)
                    return
                }
                let delay = pow(2.0, Double(attempt))
                update(id) {
                    $0.message = "\(error.localizedDescription) – neuer Versuch \(attempt)/5 in \(Int(delay)) s"
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if cancelRequested.contains(id) { break }
                // Wie pledo: bei Fehlern andere Verbindung zum Server probieren.
                if let newBase = await store.client.fastestConnection(for: server) {
                    if newBase != base { resumeData = nil }
                    base = newBase
                    store.updateServerUri(serverId: server.id, uri: newBase)
                }
            }
        }
        cancelRequested.remove(id)
        finish(id, .cancelled, nil)
    }

    private func progress(_ id: UUID, _ written: Int64, _ expected: Int64) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status == .running else { return }
        let now = Date()
        if let last = speedSamples[id] {
            let dt = now.timeIntervalSince(last.time)
            if dt >= 1 {
                let current = Double(written - last.bytes) / dt
                let previous = speeds[id] ?? current
                speeds[id] = max(0, previous * 0.6 + current * 0.4)
                speedSamples[id] = (now, written)
            }
        } else {
            speedSamples[id] = (now, written)
        }
        items[i].downloadedBytes = written
        if expected > 0 { items[i].totalBytes = expected }
        if items[i].message != nil { items[i].message = nil }
        if now.timeIntervalSince(lastSave) > 15 { save() }
    }

    private func moveIntoPlace(_ tmp: URL, _ item: DownloadItem) throws {
        let dest = fileURL(for: item)
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tmp, to: dest)
    }

    private func finish(_ id: UUID, _ status: DownloadStatus, _ message: String?) {
        update(id) {
            $0.status = status
            $0.message = message
            $0.finished = Date()
            if status == .finished { $0.downloadedBytes = max($0.downloadedBytes, $0.totalBytes) }
        }
        speeds[id] = nil
        speedSamples[id] = nil
        save()
    }

    private func update(_ id: UUID, _ change: (inout DownloadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    private func save() {
        lastSave = Date()
        let snapshot = items
        let url = storeURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Dateiauswahl & Pfade (SelectMediaFile / GetFilePath in pledo)

    nonisolated static func selectFile(_ files: [MediaFile]) -> MediaFile? {
        var selection = files
        let res = Prefs.preferredResolution
        if !res.isEmpty {
            let inner = selection.filter { ($0.videoResolution ?? "").caseInsensitiveCompare(res) == .orderedSame }
            if !inner.isEmpty { selection = inner }
        }
        let codec = Prefs.preferredVideoCodec
        if !codec.isEmpty {
            let inner = selection.filter { ($0.videoCodec ?? "").caseInsensitiveCompare(codec) == .orderedSame }
            if !inner.isEmpty { selection = inner }
        }
        return selection.first
    }

    nonisolated static func sanitize(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*")
        var r = ""
        r.unicodeScalars.append(contentsOf: s.unicodeScalars.filter {
            !invalid.contains($0) && !CharacterSet.controlCharacters.contains($0)
        })
        r = r.trimmingCharacters(in: .whitespacesAndNewlines)
        while r.hasSuffix(".") { r.removeLast() }
        return r.isEmpty ? "_" : r
    }

    nonisolated static func folder(_ raw: String, fallback: String) -> String {
        let parts = raw.split(separator: "/")
            .map { sanitize(String($0)) }
            .filter { $0 != "_" && $0 != ".." }
        return parts.isEmpty ? fallback : parts.joined(separator: "/")
    }

    nonisolated static func moviePath(_ movie: Movie, _ file: MediaFile) -> String {
        let fallback = "\(movie.displayTitle).\(file.container ?? "mkv")"
        let fileName = sanitize(file.fileName.isEmpty ? fallback : file.fileName)
        let root = folder(Prefs.moviesFolder, fallback: Prefs.defaultMoviesFolder)
        switch Prefs.movieTemplate {
        case .fileName:
            return "\(root)/\(fileName)"
        case .movieDirectory:
            return "\(root)/\(sanitize(movie.displayTitle))/\(fileName)"
        }
    }

    nonisolated static func episodePath(_ episode: Episode, _ file: MediaFile) -> String {
        let fallback = "\(episode.showTitle) - \(episode.code) - \(episode.title).\(file.container ?? "mkv")"
        let fileName = sanitize(file.fileName.isEmpty ? fallback : file.fileName)
        let root = folder(Prefs.showsFolder, fallback: Prefs.defaultShowsFolder)
        let show = sanitize(episode.showTitle)
        switch Prefs.episodeTemplate {
        case .seriesAndSeason:
            return "\(root)/\(show)/Season \(episode.seasonNumber)/\(fileName)"
        case .seriesOnly:
            return "\(root)/\(show)/\(fileName)"
        }
    }
}

/// Führt genau einen Download per URLSessionDownloadTask aus (mit Fortschritt und Resume-Daten).
final class DownloadRunner: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var progressHandler: ((Int64, Int64) -> Void)?
    private var lastReport = Date.distantPast
    private var finishedFile: URL?
    private var completionError: Error?
    private var cancelled = false
    private var _resumeData: Data?

    var resumeData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _resumeData
    }

    func run(request: URLRequest, resumeData: Data?,
             progress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        progressHandler = progress
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let task: URLSessionDownloadTask
                if let resumeData {
                    task = session.downloadTask(withResumeData: resumeData)
                } else {
                    task = session.downloadTask(with: request)
                }
                lock.lock()
                self.continuation = cont
                self.task = task
                let wasCancelled = cancelled
                lock.unlock()
                task.resume()
                if wasCancelled { task.cancel() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }

    private func complete(_ result: Result<URL, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        lock.lock()
        let shouldReport = now.timeIntervalSince(lastReport) >= 0.4
        if shouldReport { lastReport = now }
        let handler = progressHandler
        lock.unlock()
        if shouldReport { handler?(totalBytesWritten, totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            lock.lock()
            completionError = http.statusCode == 401 ? PlexError.unauthorized : PlexError.http(http.statusCode, nil)
            lock.unlock()
            return
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("pledo-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            lock.lock()
            finishedFile = dest
            lock.unlock()
        } catch {
            lock.lock()
            completionError = error
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            lock.lock()
            _resumeData = data
            lock.unlock()
            complete(.failure(error))
            return
        }
        lock.lock()
        let file = finishedFile
        let err = completionError
        lock.unlock()
        if let file {
            complete(.success(file))
        } else {
            complete(.failure(err ?? PlexError.invalidResponse))
        }
    }
}
