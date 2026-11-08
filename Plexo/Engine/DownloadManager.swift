import Foundation
import UIKit
import UserNotifications

// Warteschlange und Verwaltung aller Downloads – entspricht downloadManager.ts in Plexo.
//
// Zwei Engines:
// - Turbo: mehrere Netzwerke gleichzeitig (DownloadJob), nur solange die App im Vordergrund ist.
// - Hintergrund: Background-URLSession (BackgroundDownloader). iOS lädt weiter, auch wenn die App
//   im Hintergrund ist oder beendet wurde.
// Geht die App in den Hintergrund, werden laufende Turbo-Downloads automatisch an die
// Hintergrund-Engine übergeben (der bisherige Fortschritt bleibt erhalten).

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    nonisolated static let maxConcurrentKey = "maxConcurrentDownloads"
    nonisolated static let defaultStreamsKey = "defaultStreams"
    nonisolated static let globalLimitKey = "globalSpeedLimit"
    nonisolated static let slowModeKey = "slowMode"
    nonisolated static let slowModeLimitKey = "slowModeLimit"
    nonisolated static let keepAwakeKey = "keepAwake"
    nonisolated static let notifyKey = "notifyOnFinish"
    nonisolated static let folderKey = "downloadFolder"
    nonisolated static let bgPartsKey = "backgroundParts"
    nonisolated static let turboDefaultKey = "turboDefault"

    @Published private(set) var records: [DownloadRecord] = []
    @Published private(set) var live: [UUID: DownloadLive] = [:]
    @Published private(set) var totalSpeed: Double = 0
    @Published private(set) var isBackground = false

    private var jobs: [UUID: DownloadJob] = [:]
    private var pendingUsage: [NetworkKind: Int64] = [:]
    private var lastBytes: [UUID: Int64] = [:]
    private var bgSpeeds: [UUID: Double] = [:]
    private var merging: Set<UUID> = []
    private var lastSave = Date.distantPast
    private var timer: Timer?
    private var handoverTask: UIBackgroundTaskIdentifier = .invalid
    private let storeURL = AppPaths.support.appendingPathComponent("downloads.json")
    private let partsDir: URL
    private var monitor: NetworkMonitor { NetworkMonitor.shared }
    private var bg: BackgroundDownloader { BackgroundDownloader.shared }

    private init() {
        partsDir = AppPaths.support.appendingPathComponent("parts", isDirectory: true)
        try? FileManager.default.createDirectory(at: partsDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = decoded.map { r in
                var r = r
                // Hintergrund-Downloads laufen in der System-Session weiter, Turbo nicht.
                if r.state == .probing || (r.state == .downloading && r.engine == .turbo) { r.state = .queued }
                return r
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.everySecond() }
        }
    }

    // MARK: - Einstellungen

    private var defaults: UserDefaults { .standard }
    var maxConcurrent: Int { max(1, defaults.object(forKey: Self.maxConcurrentKey) as? Int ?? 3) }
    var defaultStreams: Int { defaults.integer(forKey: Self.defaultStreamsKey) }
    var keepAwake: Bool { defaults.object(forKey: Self.keepAwakeKey) as? Bool ?? false }
    var notify: Bool { defaults.object(forKey: Self.notifyKey) as? Bool ?? true }
    var backgroundParts: Int { max(1, min(16, defaults.object(forKey: Self.bgPartsKey) as? Int ?? 6)) }
    var turboDefault: Bool { defaults.object(forKey: Self.turboDefaultKey) as? Bool ?? true }
    var folderName: String {
        let f = (defaults.string(forKey: Self.folderKey) ?? "Downloads").trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? "Downloads" : f
    }

    var downloadFolder: URL {
        let url = AppPaths.documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func applyLimits() {
        let slow = defaults.bool(forKey: Self.slowModeKey)
        let slowLimit = (defaults.object(forKey: Self.slowModeLimitKey) as? Int).map(Int64.init) ?? 512 * 1024
        let global = slow ? slowLimit : Int64(defaults.integer(forKey: Self.globalLimitKey))
        var per: [NetworkKind: Int64] = [:]
        for k in NetworkKind.allCases { per[k] = monitor.settings[k]?.speedLimit ?? 0 }
        Task { await RateLimiter.shared.setLimits(global: global, perNetwork: per) }
    }

    // MARK: - Abfragen

    func record(_ id: UUID) -> DownloadRecord? { records.first { $0.id == id } }

    var activeCount: Int { records.filter { $0.state.isActive || $0.state == .queued }.count }

    func fileURL(_ r: DownloadRecord) -> URL? {
        guard let rel = r.relativePath else { return nil }
        return AppPaths.documents.appendingPathComponent(rel)
    }

    private func partURL(_ r: DownloadRecord) -> URL {
        partsDir.appendingPathComponent(r.partFileName)
    }

    /// Turbo ist möglich: mindestens zwei ausgewählte Netzwerke sind nutzbar und die App ist vorne.
    func canTurbo(_ r: DownloadRecord) -> Bool {
        !isBackground && r.networks.filter { monitor.isUsable($0) }.count >= 2
    }

    private var cellularAllowed: Bool {
        (monitor.settings[.cellular]?.enabled ?? true) && !monitor.isOverCap(.cellular)
    }

    // MARK: - Hinzufügen

    func add(links: [String], headers: [String: String] = [:], networks: [NetworkKind]? = nil,
             streams: Int? = nil, fileName: String? = nil, turbo: Bool? = nil) -> Int {
        let nets = networks ?? NetworkKind.allCases.filter { monitor.settings[$0]?.enabled ?? true }
        var added = 0
        for raw in links {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host != nil else { continue }
            var r = DownloadRecord(url: trimmed, fileName: Probe.sanitize(url.lastPathComponent), networks: nets)
            if links.count == 1, let fileName, !fileName.trimmingCharacters(in: .whitespaces).isEmpty {
                r.fileName = Probe.sanitize(fileName)
                r.nameLocked = true
            }
            r.headers.merge(headers) { _, new in new }
            r.streams = streams ?? defaultStreams
            r.turbo = turbo ?? turboDefault
            records.insert(r, at: 0)
            added += 1
        }
        if added > 0 {
            requestNotificationPermission()
            save(force: true)
            schedule()
        }
        return added
    }

    // MARK: - Warteschlange

    private func schedule() {
        let queued = records.reversed().filter { $0.state == .queued }
        if isBackground {
            // Im Hintergrund kann nur die System-Session laden: alles direkt übergeben.
            for r in queued { startInBackground(r.id) }
        } else {
            var free = maxConcurrent - records.filter { $0.state.isActive }.count
            for r in queued where free > 0 {
                free -= 1
                start(r.id)
            }
        }
        updateIdleTimer()
    }

    private func start(_ id: UUID) {
        guard var r = record(id) else { return }
        r.state = .probing
        r.error = nil
        update(r)
        Task {
            do {
                guard let link = URL(string: r.url) else { throw HTTPError.invalidURL }
                let probe = try await Probe.run(url: link, headers: r.headers)
                guard var current = self.record(id), current.state == .probing else { return }
                let sameFile = !current.blocks.isEmpty && current.totalBytes == probe.totalBytes
                    && (current.etag == nil || probe.etag == nil || current.etag == probe.etag)
                    && FileManager.default.fileExists(atPath: self.partURL(current).path)
                current.finalURL = probe.finalURL.absoluteString
                if !current.nameLocked { current.fileName = probe.fileName }
                if !sameFile {
                    current.totalBytes = probe.totalBytes
                    current.supportsRanges = probe.supportsRanges
                    current.etag = probe.etag
                    current.lastModified = probe.lastModified
                    current.bytesByNetwork = [:]
                    current.blocks = DownloadPlan.blocks(totalBytes: probe.totalBytes, splittable: probe.supportsRanges,
                                                         networkCount: max(1, current.networks.count))
                    self.discardSegments(&current)
                    try? FileManager.default.removeItem(at: self.partURL(current))
                }
                if current.turbo && self.canTurbo(current) {
                    self.discardSegments(&current)
                    try self.launchTurbo(current, url: probe.finalURL)
                } else {
                    self.launchBackground(current)
                }
            } catch {
                guard var failed = self.record(id), failed.state == .probing else { return }
                failed.state = .failed
                failed.error = error.localizedDescription
                self.update(failed)
                self.save(force: true)
                self.schedule()
            }
        }
    }

    /// Ohne Probe direkt an die Hintergrund-Session (App ist im Hintergrund).
    private func startInBackground(_ id: UUID) {
        guard var r = record(id), r.state == .queued else { return }
        if r.blocks.isEmpty {
            r.segments = r.segments.filter { !$0.ranged }
        }
        launchBackground(r)
    }

    private func discardSegments(_ r: inout DownloadRecord) {
        for s in r.segments {
            bg.dropResumeData(s.id)
            try? FileManager.default.removeItem(at: bg.segmentFile(s.id))
        }
        r.segments = []
    }

    // MARK: - Turbo-Engine

    private func launchTurbo(_ record: DownloadRecord, url: URL) throws {
        var r = record
        let fd = open(partURL(r).path, O_RDWR | O_CREAT, 0o644)
        if fd < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if r.supportsRanges && r.totalBytes > 0 {
            var st = stat()
            if fstat(fd, &st) == 0 && st.st_size < r.totalBytes { ftruncate(fd, off_t(r.totalBytes)) }
        }
        r.state = .downloading
        r.engine = .turbo
        update(r)
        let id = r.id
        let job = DownloadJob(record: r, url: url, fd: fd, enabled: Set(r.networks), usable: usableNetworks()) { event in
            Task { @MainActor in DownloadManager.shared.handle(id, event) }
        }
        jobs[id] = job
        live[id] = DownloadLive()
        Task { await job.start() }
        save(force: true)
    }

    private func usableNetworks() -> Set<NetworkKind> {
        Set(NetworkKind.allCases.filter { monitor.isUsable($0) })
    }

    private func handle(_ id: UUID, _ event: JobEvent) {
        guard var r = record(id) else { return }
        switch event {
        case .progress(let blocks, let byNet, let l, let usage):
            guard r.state == .downloading, r.engine == .turbo else { return }
            r.blocks = blocks
            r.bytesByNetwork = byNet
            update(r)
            live[id] = l
            for (k, v) in usage { pendingUsage[k, default: 0] += v }
        case .finished(let total, let blocks, let byNet):
            jobs[id] = nil
            live[id] = nil
            r.blocks = blocks
            r.bytesByNetwork = byNet
            r.totalBytes = total
            complete(r, file: partURL(r))
        case .failed(let message, let blocks, let byNet):
            jobs[id] = nil
            live[id] = nil
            r.blocks = blocks
            r.bytesByNetwork = byNet
            if isBackground {
                // Statt aufzugeben: an die Hintergrund-Session übergeben.
                r.engine = .background
                update(r)
                launchBackground(r)
                return
            }
            r.state = .failed
            r.error = message
            update(r)
            save(force: true)
            schedule()
        }
    }

    // MARK: - Hintergrund-Engine

    /// Teilt die noch fehlenden Blöcke in parallele Teile für die Background-URLSession.
    private func buildSegments(_ r: DownloadRecord) -> [Segment] {
        guard r.supportsRanges, r.totalBytes > 0, !r.blocks.isEmpty else {
            return [Segment(start: 0, end: -1, firstBlock: r.blocks.isEmpty ? -1 : 0,
                            lastBlock: r.blocks.count - 1, ranged: false)]
        }
        var runs: [[Int]] = []
        var current: [Int] = []
        for i in r.blocks.indices {
            if r.blocks[i].isComplete {
                if !current.isEmpty { runs.append(current) }
                current = []
            } else {
                current.append(i)
            }
        }
        if !current.isEmpty { runs.append(current) }
        while runs.count < backgroundParts,
              let idx = runs.indices.max(by: { runs[$0].count < runs[$1].count }), runs[idx].count > 1 {
            let run = runs.remove(at: idx)
            let mid = run.count / 2
            runs.insert(Array(run[mid...]), at: idx)
            runs.insert(Array(run[..<mid]), at: idx)
        }
        return runs.compactMap { run in
            guard let f = run.first, let l = run.last else { return nil }
            return Segment(start: r.blocks[f].start + r.blocks[f].done, end: r.blocks[l].end,
                           firstBlock: f, lastBlock: l, ranged: true)
        }
    }

    private func launchBackground(_ record: DownloadRecord) {
        var r = record
        r.engine = .background
        r.state = .downloading
        r.error = nil
        if r.segments.allSatisfy(\.done) {
            r.segments = buildSegments(r)
        }
        if r.segments.contains(where: \.ranged) {
            let path = partURL(r).path
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
        }
        update(r)
        save(force: true)
        let url = URL(string: r.finalURL ?? r.url) ?? URL(string: r.url)!
        let allowCell = cellularAllowed && r.networks.contains(.cellular)
        let snapshot = r
        Task {
            let running = await self.bg.runningSegments()
            for s in snapshot.segments where !s.done {
                if s.fileReady {
                    self.merge(snapshot.id, s.id)
                } else if !running.contains(s.id) {
                    self.bg.start(download: snapshot.id, segment: s, url: url, headers: snapshot.headers,
                                  allowCellular: allowCell)
                }
            }
            self.checkBackgroundDone(snapshot.id)
        }
    }

    func bgProgress(_ id: UUID, _ seg: UUID, _ written: Int64, _ expected: Int64) {
        guard var r = record(id), let i = r.segments.firstIndex(where: { $0.id == seg }), !r.segments[i].done else { return }
        r.segments[i].received = written
        if !r.segments[i].ranged && r.totalBytes <= 0 && expected > 0 { r.totalBytes = expected }
        update(r)
    }

    func bgCompleted(_ id: UUID, _ seg: UUID, file: BGFile?, error: String?, cancelled: Bool) {
        guard var r = record(id), let i = r.segments.firstIndex(where: { $0.id == seg }) else {
            if let file { try? FileManager.default.removeItem(at: file.url) }
            return
        }
        let segment = r.segments[i]
        if let file, error == nil {
            var valid = (200..<300).contains(file.status)
            if segment.ranged {
                valid = file.status == 206 && (file.rangeStart ?? segment.start) == segment.start
            }
            if valid {
                if !segment.ranged, !r.nameLocked, let name = file.suggestedName, !name.isEmpty, name != "Unknown",
                   r.blocks.isEmpty {
                    r.fileName = Probe.sanitize(name)
                }
                r.segments[i].fileReady = true
                update(r)
                save(force: true)
                merge(id, seg)
                return
            }
            try? FileManager.default.removeItem(at: file.url)
            if segment.ranged && file.status == 200 {
                // Server liefert plötzlich keine Teile mehr: komplett neu ohne Range.
                discardSegments(&r)
                r.supportsRanges = false
                r.blocks = DownloadPlan.blocks(totalBytes: r.totalBytes, splittable: false, networkCount: 1)
                update(r)
                if r.state == .downloading { launchBackground(r) }
                return
            }
        }
        guard r.state == .downloading, r.engine == .background else { return }
        if cancelled && !bg.hasResumeData(seg) && error == nil { return }
        r.segments[i].attempts += 1
        if r.segments[i].attempts > 10 {
            r.state = .failed
            r.error = (error ?? "Teil-Download fehlgeschlagen") + " – „Erneut“ setzt fort, „Link ersetzen“ hilft bei abgelaufenen Links."
            update(r)
            save(force: true)
            Task { await bg.cancel(download: id, keepResume: true) }
            schedule()
            return
        }
        update(r)
        save()
        let url = URL(string: r.finalURL ?? r.url) ?? URL(string: r.url)!
        bg.start(download: id, segment: r.segments[i], url: url, headers: r.headers,
                 allowCellular: cellularAllowed && r.networks.contains(.cellular))
    }

    private func merge(_ id: UUID, _ seg: UUID) {
        guard !merging.contains(seg), let r = record(id), let s = r.segments.first(where: { $0.id == seg }) else { return }
        let file = bg.segmentFile(seg)
        guard FileManager.default.fileExists(atPath: file.path) else {
            // Datei fehlt (z. B. aufgeräumt): Teil neu laden.
            if var cur = record(id), let i = cur.segments.firstIndex(where: { $0.id == seg }) {
                cur.segments[i].fileReady = false
                cur.segments[i].received = 0
                update(cur)
                if cur.state == .downloading { launchBackground(cur) }
            }
            return
        }
        merging.insert(seg)
        let part = partURL(r)
        let ranged = s.ranged
        let offset = s.start
        Task.detached(priority: .utility) {
            var failure: String?
            do {
                if ranged {
                    try BackgroundDownloader.merge(file, into: part, at: offset)
                    try? FileManager.default.removeItem(at: file)
                } else {
                    try? FileManager.default.removeItem(at: part)
                    try FileManager.default.moveItem(at: file, to: part)
                }
            } catch {
                failure = error.localizedDescription
            }
            let message = failure
            await MainActor.run { DownloadManager.shared.mergeFinished(id, seg, error: message) }
        }
    }

    private func mergeFinished(_ id: UUID, _ seg: UUID, error: String?) {
        merging.remove(seg)
        guard var r = record(id), let i = r.segments.firstIndex(where: { $0.id == seg }) else { return }
        if let error {
            r.state = .failed
            r.error = "Datei konnte nicht zusammengesetzt werden: \(error)"
            update(r)
            save(force: true)
            return
        }
        let s = r.segments[i]
        r.segments[i].done = true
        r.segments[i].fileReady = false
        if !s.ranged {
            let size = (try? FileManager.default.attributesOfItem(atPath: partURL(r).path)[.size] as? Int64) ?? nil
            if let size { r.totalBytes = size }
            r.blocks = [BlockState(start: 0, end: r.totalBytes, done: r.totalBytes)]
        } else if s.firstBlock >= 0 {
            for b in s.firstBlock...s.lastBlock where b < r.blocks.count {
                r.blocks[b].done = r.blocks[b].length ?? r.blocks[b].done
            }
        }
        if let kind = monitor.primary {
            r.bytesByNetwork[kind.rawValue, default: 0] += s.length ?? r.totalBytes
        }
        update(r)
        save(force: true)
        checkBackgroundDone(id)
    }

    private func checkBackgroundDone(_ id: UUID) {
        guard let r = record(id), r.engine == .background, r.state == .downloading,
              !r.segments.isEmpty, r.segments.allSatisfy(\.done) else { return }
        if r.blocks.allSatisfy(\.isComplete) {
            complete(r, file: partURL(r))
        } else {
            // Noch Lücken (z. B. nach Teilwechsel): fehlende Teile neu planen.
            var next = r
            next.segments = buildSegments(next)
            launchBackground(next)
        }
    }

    // MARK: - Abschluss

    private func complete(_ record: DownloadRecord, file: URL) {
        var r = record
        if r.totalBytes > 0 { truncate(file.path, off_t(r.totalBytes)) }
        let dest = FileOps.uniqueURL(in: downloadFolder, name: r.fileName)
        do {
            try FileManager.default.moveItem(at: file, to: dest)
            r.relativePath = folderName + "/" + dest.lastPathComponent
            r.fileName = dest.lastPathComponent
            r.state = .completed
            r.finished = Date()
            r.segments = []
            notifyFinished(r)
        } catch {
            r.state = .failed
            r.error = "Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
        live[r.id] = nil
        update(r)
        save(force: true)
        FilesStore.shared.refresh()
        schedule()
    }

    // MARK: - Takt

    private func everySecond() {
        var speeds: [NetworkKind: Double] = [:]
        for (id, l) in live where jobs[id] != nil {
            for (k, n) in l.networks { speeds[k, default: 0] += n.speed }
        }
        // Hintergrund-Downloads: Tempo aus dem Fortschritt, dem aktiven System-Netzwerk zugeordnet.
        let primary = monitor.primary
        for r in records where r.engine == .background && r.state == .downloading {
            let bytes = r.downloadedBytes
            let delta = max(0, bytes - (lastBytes[r.id] ?? bytes))
            lastBytes[r.id] = bytes
            let speed = (bgSpeeds[r.id] ?? Double(delta)) * 0.5 + Double(delta) * 0.5
            bgSpeeds[r.id] = speed
            var l = DownloadLive()
            l.speed = speed
            let parts = r.segments.filter { !$0.done }.count
            if let primary {
                l.networks[primary] = NetworkLive(speed: speed, streams: parts, bytes: r.bytesByNetwork[primary.rawValue] ?? 0)
                speeds[primary, default: 0] += speed
                pendingUsage[primary, default: 0] += delta
            }
            l.message = "Hintergrund-Modus · \(parts) Teile · lädt auch bei gesperrtem Bildschirm"
            live[r.id] = l
        }
        totalSpeed = speeds.values.reduce(0, +)
        monitor.record(speeds: speeds, usage: pendingUsage)
        pendingUsage = [:]
        let usable = usableNetworks()
        for job in jobs.values {
            Task { await job.setUsable(usable) }
        }
        applyLimits()
        save()
    }

    // MARK: - Vordergrund / Hintergrund

    func enterBackground() {
        guard !isBackground else { return }
        isBackground = true
        handoverTask = UIApplication.shared.beginBackgroundTask(withName: "plexo.handover") {
            Task { @MainActor in DownloadManager.shared.endHandover() }
        }
        let turboJobs = jobs
        jobs = [:]
        Task {
            for (id, job) in turboJobs {
                let result = await job.stop()
                guard var r = self.record(id), r.state == .downloading else { continue }
                r.blocks = result.blocks
                r.bytesByNetwork = result.bytesByNetwork
                r.segments = []
                self.live[id] = nil
                self.launchBackground(r)
            }
            self.schedule()
            self.save(force: true)
            self.endHandover()
        }
    }

    private func endHandover() {
        if handoverTask != .invalid {
            UIApplication.shared.endBackgroundTask(handoverTask)
            handoverTask = .invalid
        }
    }

    func enterForeground() {
        guard isBackground else { return }
        isBackground = false
        resumeBackgroundSegments()
        schedule()
    }

    /// Hintergrund-Download wieder auf Turbo (mehrere Netzwerke) umstellen.
    func switchToTurbo(_ id: UUID) {
        guard var r = record(id), r.engine == .background, r.state == .downloading, canTurbo(r) else { return }
        r.state = .queued
        r.turbo = true
        update(r)
        Task {
            await self.bg.cancel(download: id, keepResume: false)
            guard var cur = self.record(id) else { return }
            self.discardSegments(&cur)
            self.update(cur)
            self.schedule()
        }
    }

    // MARK: - Aktionen

    func pause(_ id: UUID) {
        guard var r = record(id) else { return }
        switch r.state {
        case .queued, .probing:
            r.state = .paused
            update(r)
        case .downloading:
            r.state = .paused
            update(r)
            live[id] = nil
            if let job = jobs.removeValue(forKey: id) {
                Task {
                    let result = await job.stop()
                    if var current = self.record(id) {
                        current.blocks = result.blocks
                        current.bytesByNetwork = result.bytesByNetwork
                        self.update(current)
                        self.save(force: true)
                    }
                }
            } else if r.engine == .background {
                Task { await self.bg.cancel(download: id, keepResume: true) }
            }
        default:
            return
        }
        save(force: true)
        schedule()
    }

    func resume(_ id: UUID) {
        guard var r = record(id), r.state == .paused || r.state == .failed else { return }
        r.state = .queued
        r.error = nil
        for i in r.segments.indices { r.segments[i].attempts = 0 }
        update(r)
        save(force: true)
        schedule()
    }

    func retry(_ id: UUID) { resume(id) }

    func pauseAll() {
        for r in records where r.state.isActive || r.state == .queued { pause(r.id) }
    }

    func resumeAll() {
        for r in records where r.state == .paused || r.state == .failed { resume(r.id) }
    }

    func remove(_ id: UUID, deleteFile: Bool) {
        guard var r = record(id) else { return }
        let job = jobs.removeValue(forKey: id)
        live[id] = nil
        records.removeAll { $0.id == id }
        let part = partURL(r)
        let file = fileURL(r)
        discardSegments(&r)
        Task {
            if let job { _ = await job.stop() }
            await self.bg.cancel(download: id, keepResume: false)
            try? FileManager.default.removeItem(at: part)
            if deleteFile, let file { try? FileManager.default.removeItem(at: file) }
            FilesStore.shared.refresh()
        }
        save(force: true)
        schedule()
    }

    func removeCompleted() {
        records.removeAll { $0.state == .completed }
        save(force: true)
    }

    /// Abgelaufenen Link ersetzen, Fortschritt bleibt erhalten, wenn die Datei gleich groß ist.
    func replaceLink(_ id: UUID, with link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        guard var r = record(id), URL(string: trimmed) != nil else { return }
        if let job = jobs.removeValue(forKey: id) {
            live[id] = nil
            Task { _ = await job.stop() }
        }
        r.url = trimmed
        r.finalURL = nil
        r.etag = nil
        r.state = .queued
        r.error = nil
        // Resume-Daten gehören zum alten Link.
        for s in r.segments { bg.dropResumeData(s.id) }
        for i in r.segments.indices {
            r.segments[i].attempts = 0
            if !r.segments[i].fileReady { r.segments[i].received = 0 }
        }
        update(r)
        Task {
            await self.bg.cancel(download: id, keepResume: false)
            self.save(force: true)
            self.schedule()
        }
    }

    func setNetwork(_ id: UUID, _ kind: NetworkKind, enabled: Bool) {
        guard var r = record(id) else { return }
        if enabled {
            if !r.networks.contains(kind) { r.networks.append(kind) }
        } else {
            r.networks.removeAll { $0 == kind }
        }
        update(r)
        save(force: true)
        if let job = jobs[id] {
            Task { await job.setEnabled(kind, enabled) }
        }
    }

    // MARK: - Start der App

    func resumeOnLaunch() {
        _ = bg.session
        applyLimits()
        resumeBackgroundSegments()
        schedule()
    }

    /// Hintergrund-Teile, die nicht mehr in der System-Session laufen, neu anstoßen.
    private func resumeBackgroundSegments() {
        Task {
            let running = await self.bg.runningSegments()
            for r in self.records where r.engine == .background && r.state == .downloading {
                let url = URL(string: r.finalURL ?? r.url) ?? URL(string: r.url)!
                for s in r.segments where !s.done {
                    if s.fileReady {
                        self.merge(r.id, s.id)
                    } else if !running.contains(s.id) {
                        self.bg.start(download: r.id, segment: s, url: url, headers: r.headers,
                                      allowCellular: self.cellularAllowed && r.networks.contains(.cellular))
                    }
                }
                self.checkBackgroundDone(r.id)
            }
        }
    }

    // MARK: - Intern

    private func update(_ r: DownloadRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r }
    }

    private func save(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) > 3 else { return }
        lastSave = now
        let snapshot = records
        let url = storeURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func updateIdleTimer() {
        let busy = records.contains { $0.state.isActive && $0.engine == .turbo }
        UIApplication.shared.isIdleTimerDisabled = keepAwake && busy && !isBackground
    }

    private func requestNotificationPermission() {
        guard notify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyFinished(_ r: DownloadRecord) {
        guard notify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download fertig"
        content.body = "\(r.fileName) (\(Format.bytes(r.totalBytes)))"
        content.sound = .default
        let request = UNNotificationRequest(identifier: r.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
