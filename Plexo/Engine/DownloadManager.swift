import Foundation
import UIKit
import UserNotifications

// Warteschlange und Verwaltung aller Downloads – entspricht downloadManager.ts in Plexo.

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

    @Published private(set) var records: [DownloadRecord] = []
    @Published private(set) var live: [UUID: DownloadLive] = [:]
    @Published private(set) var totalSpeed: Double = 0

    private var jobs: [UUID: DownloadJob] = [:]
    private var probing: Set<UUID> = []
    private var pendingUsage: [NetworkKind: Int64] = [:]
    private var lastSave = Date.distantPast
    private var timer: Timer?
    private let storeURL = AppPaths.support.appendingPathComponent("downloads.json")
    private var monitor: NetworkMonitor { NetworkMonitor.shared }

    private init() {
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = decoded.map { r in
                var r = r
                if r.state.isActive { r.state = .queued }
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
    var keepAwake: Bool { defaults.object(forKey: Self.keepAwakeKey) as? Bool ?? true }
    var notify: Bool { defaults.object(forKey: Self.notifyKey) as? Bool ?? true }
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
        downloadFolder.appendingPathComponent(r.partFileName)
    }

    // MARK: - Hinzufügen

    func add(links: [String], headers: [String: String] = [:], networks: [NetworkKind]? = nil,
             streams: Int? = nil, fileName: String? = nil) -> Int {
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
        let running = records.filter { $0.state.isActive }.count
        var free = maxConcurrent - running
        guard free > 0 else { return }
        for r in records.reversed() where r.state == .queued {
            if free <= 0 { break }
            free -= 1
            start(r.id)
        }
        updateIdleTimer()
    }

    private func start(_ id: UUID) {
        guard var r = record(id) else { return }
        r.state = .probing
        r.error = nil
        update(r)
        probing.insert(id)
        Task {
            do {
                guard let link = URL(string: r.url) else { throw HTTPError.invalidURL }
                let probe = try await Probe.run(url: link, headers: r.headers)
                guard var current = self.record(id), current.state == .probing else {
                    self.probing.remove(id)
                    return
                }
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
                    try? FileManager.default.removeItem(at: self.partURL(current))
                }
                self.probing.remove(id)
                try self.launch(current, url: probe.finalURL)
            } catch {
                self.probing.remove(id)
                guard var failed = self.record(id), failed.state == .probing else { return }
                failed.state = .failed
                failed.error = error.localizedDescription
                self.update(failed)
                self.save(force: true)
                self.schedule()
            }
        }
    }

    private func launch(_ record: DownloadRecord, url: URL) throws {
        var r = record
        let path = partURL(r).path
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        if fd < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if r.supportsRanges && r.totalBytes > 0 {
            var st = stat()
            if fstat(fd, &st) == 0 && st.st_size < r.totalBytes { ftruncate(fd, off_t(r.totalBytes)) }
        }
        r.state = .downloading
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
            guard r.state == .downloading else { return }
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
            let dest = FileOps.uniqueURL(in: downloadFolder, name: r.fileName)
            do {
                try FileManager.default.moveItem(at: partURL(r), to: dest)
                r.relativePath = folderName + "/" + dest.lastPathComponent
                r.fileName = dest.lastPathComponent
                r.state = .completed
                r.finished = Date()
                notifyFinished(r)
            } catch {
                r.state = .failed
                r.error = "Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
            update(r)
            save(force: true)
            FilesStore.shared.refresh()
            schedule()
        case .failed(let message, let blocks, let byNet):
            jobs[id] = nil
            live[id] = nil
            r.blocks = blocks
            r.bytesByNetwork = byNet
            r.state = .failed
            r.error = message
            update(r)
            save(force: true)
            schedule()
        }
    }

    private func everySecond() {
        var speeds: [NetworkKind: Double] = [:]
        for l in live.values {
            for (k, n) in l.networks { speeds[k, default: 0] += n.speed }
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
            if let job = jobs.removeValue(forKey: id) {
                live[id] = nil
                Task {
                    let result = await job.stop()
                    if var current = self.record(id) {
                        current.blocks = result.blocks
                        current.bytesByNetwork = result.bytesByNetwork
                        self.update(current)
                        self.save(force: true)
                    }
                }
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
        guard let r = record(id) else { return }
        let job = jobs.removeValue(forKey: id)
        live[id] = nil
        records.removeAll { $0.id == id }
        let part = partURL(r)
        let file = fileURL(r)
        Task {
            if let job { _ = await job.stop() }
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
        guard var r = record(id), URL(string: link.trimmingCharacters(in: .whitespaces)) != nil else { return }
        if let job = jobs.removeValue(forKey: id) {
            live[id] = nil
            Task { _ = await job.stop() }
        }
        r.url = link.trimmingCharacters(in: .whitespaces)
        r.finalURL = nil
        r.etag = nil
        r.state = .queued
        r.error = nil
        update(r)
        save(force: true)
        schedule()
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

    func resumeOnLaunch() {
        applyLimits()
        schedule()
    }

    func updateIdleTimer() {
        let busy = records.contains { $0.state.isActive }
        UIApplication.shared.isIdleTimerDisabled = keepAwake && busy
    }

    private func requestNotificationPermission() {
        guard notify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
