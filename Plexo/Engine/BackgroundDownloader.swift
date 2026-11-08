import Foundation

// Hintergrund-Engine: Background-URLSession. iOS lädt die Teile selbst weiter – auch wenn die App
// im Hintergrund ist, der Bildschirm gesperrt ist oder das System die App beendet hat.
// Jedes Teil (Segment) ist eine eigene Range-Anfrage; Abbrüche werden mit Resume-Daten fortgesetzt.

struct BGFile: Sendable {
    let url: URL
    let status: Int
    let suggestedName: String?
    let contentRange: String?

    var rangeStart: Int64? {
        guard let cr = contentRange?.lowercased(), let r = cr.range(of: "bytes ") else { return nil }
        let rest = cr[r.upperBound...]
        guard let dash = rest.firstIndex(of: "-") else { return nil }
        return Int64(rest[..<dash].trimmingCharacters(in: .whitespaces))
    }
}

final class BackgroundDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundDownloader()

    private let lock = NSLock()
    private var finished: [UUID: BGFile] = [:]
    private var lastProgress: [Int: Date] = [:]
    private var completionHandler: (() -> Void)?

    let segmentDir: URL
    private let resumeDir: URL

    override init() {
        segmentDir = AppPaths.support.appendingPathComponent("segments", isDirectory: true)
        resumeDir = AppPaths.support.appendingPathComponent("resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: segmentDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)
        super.init()
    }

    lazy var session: URLSession = {
        let id = (Bundle.main.bundleIdentifier ?? "io.github.plexo.ios") + ".background-downloads"
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func setCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        completionHandler = handler
        lock.unlock()
        _ = session
    }

    func segmentFile(_ segment: UUID) -> URL {
        segmentDir.appendingPathComponent("\(segment.uuidString).seg")
    }

    // MARK: - Resume-Daten

    private func resumeFile(_ segment: UUID) -> URL {
        resumeDir.appendingPathComponent("\(segment.uuidString).resume")
    }

    func hasResumeData(_ segment: UUID) -> Bool {
        FileManager.default.fileExists(atPath: resumeFile(segment).path)
    }

    func dropResumeData(_ segment: UUID) {
        try? FileManager.default.removeItem(at: resumeFile(segment))
    }

    private func saveResume(_ data: Data, _ segment: UUID) {
        try? data.write(to: resumeFile(segment), options: .atomic)
    }

    // MARK: - Steuerung

    func start(download: UUID, segment: Segment, url: URL, headers: [String: String], allowCellular: Bool) {
        var task: URLSessionDownloadTask?
        let rf = resumeFile(segment.id)
        if let data = try? Data(contentsOf: rf) {
            try? FileManager.default.removeItem(at: rf)
            task = session.downloadTask(withResumeData: data)
        }
        if task == nil {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
            var hasUA = false
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
                if k.lowercased() == "user-agent" { hasUA = true }
                if k.lowercased() == "cookie" { request.httpShouldHandleCookies = false }
            }
            if !hasUA { request.setValue(HTTPConnection.userAgent, forHTTPHeaderField: "User-Agent") }
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if segment.ranged {
                let start = segment.start + 0
                if segment.end >= 0 {
                    request.setValue("bytes=\(start)-\(segment.end - 1)", forHTTPHeaderField: "Range")
                } else {
                    request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
                }
            }
            request.allowsCellularAccess = allowCellular
            task = session.downloadTask(with: request)
        }
        guard let task else { return }
        task.taskDescription = "\(download.uuidString)|\(segment.id.uuidString)"
        if let len = segment.length { task.countOfBytesClientExpectsToReceive = len }
        task.resume()
    }

    /// Bricht alle Teile eines Downloads ab; mit keepResume werden Resume-Daten gesichert (Pause).
    func cancel(download: UUID, keepResume: Bool) async {
        let tasks = await session.allTasks
        for t in tasks where t.taskDescription?.hasPrefix(download.uuidString) == true {
            if keepResume, let dt = t as? URLSessionDownloadTask, let ids = Self.ids(t) {
                if let data = await dt.cancelByProducingResumeData() {
                    saveResume(data, ids.segment)
                }
            } else {
                t.cancel()
            }
        }
    }

    /// Segmente, die gerade in der Session laufen (z. B. nach einem Neustart der App).
    func runningSegments() async -> Set<UUID> {
        let tasks = await session.allTasks
        return Set(tasks.compactMap { t -> UUID? in
            guard t.state == .running || t.state == .suspended else { return nil }
            return Self.ids(t)?.segment
        })
    }

    static func ids(_ task: URLSessionTask) -> (download: UUID, segment: UUID)? {
        guard let parts = task.taskDescription?.split(separator: "|"), parts.count == 2,
              let d = UUID(uuidString: String(parts[0])), let s = UUID(uuidString: String(parts[1])) else { return nil }
        return (d, s)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let ids = Self.ids(downloadTask) else { return }
        let now = Date()
        lock.lock()
        let last = lastProgress[downloadTask.taskIdentifier] ?? .distantPast
        let report = now.timeIntervalSince(last) >= 0.5
        if report { lastProgress[downloadTask.taskIdentifier] = now }
        lock.unlock()
        guard report else { return }
        Task { @MainActor in
            DownloadManager.shared.bgProgress(ids.download, ids.segment, totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let ids = Self.ids(downloadTask) else { return }
        let http = downloadTask.response as? HTTPURLResponse
        let dest = segmentFile(ids.segment)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            return
        }
        let file = BGFile(url: dest, status: http?.statusCode ?? 0, suggestedName: http?.suggestedFilename,
                          contentRange: http?.value(forHTTPHeaderField: "Content-Range"))
        lock.lock()
        finished[ids.segment] = file
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ids = Self.ids(task) else { return }
        lock.lock()
        let file = finished.removeValue(forKey: ids.segment)
        lastProgress[task.taskIdentifier] = nil
        lock.unlock()
        var message: String?
        var cancelled = false
        if let error {
            let ns = error as NSError
            if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                saveResume(data, ids.segment)
            }
            cancelled = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
            message = error.localizedDescription
        }
        Task { @MainActor in
            DownloadManager.shared.bgCompleted(ids.download, ids.segment, file: error == nil ? file : nil,
                                               error: message, cancelled: cancelled)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let handler = self.completionHandler
            self.completionHandler = nil
            self.lock.unlock()
            handler?()
        }
    }

    // MARK: - Zusammenfügen

    /// Kopiert eine Teil-Datei an ihre Position in der Zieldatei.
    static func merge(_ file: URL, into part: URL, at offset: Int64) throws {
        let fd = open(part.path, O_RDWR | O_CREAT, 0o644)
        if fd < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        var position = offset
        while true {
            let chunk = try reader.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try DownloadJob.write(fd: fd, data: chunk, at: position)
            position += Int64(chunk.count)
        }
        fsync(fd)
    }
}
