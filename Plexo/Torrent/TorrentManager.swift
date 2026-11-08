import Foundation
import UIKit
import UserNotifications

// Torrents & Magnet-Links über libtorrent (wie Plexo: Peers werden auf alle ausgewählten
// Netzwerke verteilt – libtorrent „outgoing_interfaces“, z. B. en0 = WLAN, pdp_ip0 = Mobilfunk).

struct TorrentItem: Identifiable, Equatable {
    let id: String
    var name: String
    var savePath: String
    var error: String
    var state: Int
    var paused: Bool
    var hasMetadata: Bool
    var finished: Bool
    var progress: Double
    var totalWanted: Int64
    var wantedDone: Int64
    var totalSize: Int64
    var downloaded: Int64
    var uploaded: Int64
    var downRate: Int
    var upRate: Int
    var peers: Int
    var seeds: Int

    var stateLabel: String {
        if !error.isEmpty { return "Fehler" }
        if paused { return finished ? "Fertig" : "Pausiert" }
        switch state {
        case 0, 5: return "Prüft Dateien"
        case 1: return "Lädt Metadaten…"
        case 3: return "Fertig"
        case 4: return "Seedet"
        default: return "Lädt"
        }
    }

    var displayName: String { name.isEmpty ? "Magnet \(id.prefix(8))…" : name }
}

struct TorrentFile: Identifiable {
    let index: Int
    let path: String
    let size: Int64
    let done: Int64
    let priority: Int
    var id: Int { index }
}

struct InterfaceStat {
    var peers = 0
    var down = 0
    var up = 0
}

private func cString<T>(_ tuple: T) -> String {
    var t = tuple
    return withUnsafeBytes(of: &t) { raw -> String in
        guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
        return String(cString: base)
    }
}

/// Besitzt die libtorrent-Session; alle Aufrufe laufen über eine serielle Queue.
final class TorrentEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "plexo.torrent", qos: .userInitiated)
    private var session: UnsafeMutableRawPointer?
    let stateDir: URL

    init() {
        stateDir = AppPaths.support.appendingPathComponent("torrents", isDirectory: true)
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }

    func start(interfaces: String, down: Int32, up: Int32) {
        queue.async {
            guard self.session == nil else { return }
            self.session = plx_session_create(self.stateDir.path, interfaces, down, up)
            if let s = self.session { _ = plx_load_saved(s) }
        }
    }

    func run<T>(_ body: @escaping (UnsafeMutableRawPointer) -> T) async -> T? {
        await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            queue.async {
                guard let s = self.session else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: body(s))
            }
        }
    }
}

@MainActor
final class TorrentManager: ObservableObject {
    static let shared = TorrentManager()

    nonisolated static let seedKey = "torrentSeedAfterFinish"
    nonisolated static let uploadLimitKey = "torrentUploadLimit"

    @Published private(set) var items: [TorrentItem] = []
    @Published private(set) var interfaceStats: [NetworkKind: InterfaceStat] = [:]
    @Published var lastError: String?

    private let engine = TorrentEngine()
    private var timer: Timer?
    private var appliedInterfaces: String?
    private var appliedLimits: (Int32, Int32)?
    private var lastDownloaded: [String: Int64] = [:]
    private var started = false

    private var monitor: NetworkMonitor { NetworkMonitor.shared }

    var seedAfterFinish: Bool { UserDefaults.standard.bool(forKey: Self.seedKey) }
    var uploadLimit: Int32 {
        Int32(UserDefaults.standard.object(forKey: Self.uploadLimitKey) as? Int ?? 200 * 1024)
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let ifs = interfaceString()
        appliedInterfaces = ifs
        engine.start(interfaces: ifs, down: downloadLimit(), up: uploadLimit)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in TorrentManager.shared.tick() }
        }
    }

    var activeCount: Int { items.filter { !$0.paused && !$0.finished }.count }
    var totalDownRate: Double { Double(items.reduce(0) { $0 + $1.downRate }) }

    // MARK: - Netzwerke

    /// Ausgewählte, nutzbare Netzwerke als libtorrent-Interfaces (en0,pdp_ip0,…).
    private func interfaceString() -> String {
        var names: [String] = []
        for kind in NetworkKind.allCases where monitor.isUsable(kind) {
            if let name = monitor.interfaceNames[kind] {
                names.append(name)
            } else if kind == .cellular {
                names.append("pdp_ip0")
            } else if kind == .wifi {
                names.append("en0")
            }
        }
        return names.count >= 1 ? names.joined(separator: ",") : ""
    }

    private func kind(forInterface name: String) -> NetworkKind? {
        for (kind, iface) in monitor.interfaceNames where iface == name { return kind }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name == "en0" { return .wifi }
        if name.hasPrefix("en") { return .ethernet }
        return nil
    }

    private func downloadLimit() -> Int32 {
        let d = UserDefaults.standard
        if d.bool(forKey: DownloadManager.slowModeKey) {
            return Int32(d.object(forKey: DownloadManager.slowModeLimitKey) as? Int ?? 512 * 1024)
        }
        return Int32(d.integer(forKey: DownloadManager.globalLimitKey))
    }

    // MARK: - Hinzufügen

    func addMagnet(_ link: String) {
        start()
        let save = DownloadManager.shared.downloadFolder.path
        Task {
            let result: (Int32, String)? = await engine.run { s in
                var id = [CChar](repeating: 0, count: 72)
                var err = [CChar](repeating: 0, count: 256)
                let rc = plx_add_magnet(s, link, save, &id, &err, 256)
                return (rc, rc == 0 ? String(cString: id) : String(cString: err))
            }
            self.handleAdd(result)
        }
    }

    func addTorrentFile(_ url: URL) {
        start()
        let save = DownloadManager.shared.downloadFolder.path
        let scoped = url.startAccessingSecurityScopedResource()
        let local = engine.stateDir.appendingPathComponent("import-\(UUID().uuidString).torrent")
        do {
            try FileManager.default.copyItem(at: url, to: local)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            lastError = "Torrent-Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            return
        }
        if scoped { url.stopAccessingSecurityScopedResource() }
        Task {
            let result: (Int32, String)? = await engine.run { s in
                var id = [CChar](repeating: 0, count: 72)
                var err = [CChar](repeating: 0, count: 256)
                let rc = plx_add_file(s, local.path, save, &id, &err, 256)
                return (rc, rc == 0 ? String(cString: id) : String(cString: err))
            }
            try? FileManager.default.removeItem(at: local)
            self.handleAdd(result)
        }
    }

    /// .torrent-Datei aus dem Netz laden (mit Cookies der Browser-Sitzung) und hinzufügen.
    func addTorrentURL(_ url: URL, headers: [String: String]) {
        start()
        Task {
            do {
                var request = URLRequest(url: url)
                for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw HTTPError.status(http.statusCode)
                }
                let local = engine.stateDir.appendingPathComponent("dl-\(UUID().uuidString).torrent")
                try data.write(to: local)
                addTorrentFile(local)
            } catch {
                lastError = "Torrent-Datei konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    private func handleAdd(_ result: (Int32, String)?) {
        guard let result else {
            lastError = "Torrent-Engine nicht bereit"
            return
        }
        if result.0 != 0 {
            lastError = result.1
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            tick()
        }
    }

    // MARK: - Aktionen

    func pause(_ id: String) { Task { _ = await engine.run { plx_pause($0, id) }; tick() } }
    func resume(_ id: String) { Task { _ = await engine.run { plx_resume($0, id) }; tick() } }
    func recheck(_ id: String) { Task { _ = await engine.run { plx_force_recheck($0, id) } } }
    func reannounce(_ id: String) { Task { _ = await engine.run { plx_force_reannounce($0, id) } } }
    func setSequential(_ id: String, _ on: Bool) { Task { _ = await engine.run { plx_set_sequential($0, id, on ? 1 : 0) } } }

    func remove(_ id: String, deleteFiles: Bool) {
        items.removeAll { $0.id == id }
        Task {
            _ = await engine.run { plx_remove($0, id, deleteFiles ? 1 : 0) }
            FilesStore.shared.refresh()
        }
    }

    func pauseAll() { for i in items where !i.paused { pause(i.id) } }
    func resumeAll() { for i in items where i.paused { resume(i.id) } }

    func files(_ id: String) async -> [TorrentFile] {
        await engine.run { s -> [TorrentFile] in
            let count = Int(plx_file_count(s, id))
            var result: [TorrentFile] = []
            var path = [CChar](repeating: 0, count: 2048)
            for i in 0..<count {
                var size: Int64 = 0
                var done: Int64 = 0
                var prio: Int32 = 0
                if plx_file_info(s, id, Int32(i), &path, 2048, &size, &done, &prio) == 0 {
                    result.append(TorrentFile(index: i, path: String(cString: path), size: size, done: done,
                                              priority: Int(prio)))
                }
            }
            return result
        } ?? []
    }

    func setFilePriority(_ id: String, index: Int, priority: Int) {
        Task { _ = await engine.run { plx_set_file_priority($0, id, Int32(index), Int32(priority)) } }
    }

    // MARK: - Takt

    func enterBackground() {
        Task { _ = await engine.run { s in plx_save_all(s) } }
    }

    private func tick() {
        guard started else { return }
        let ifs = interfaceString()
        let limits = (downloadLimit(), uploadLimit)
        if ifs != appliedInterfaces || appliedLimits.map({ $0 != limits }) ?? true {
            appliedInterfaces = ifs
            appliedLimits = limits
            Task { _ = await engine.run { plx_session_apply($0, ifs, limits.0, limits.1, 0) } }
        }
        let seed = seedAfterFinish
        Task {
            let snapshot = await engine.run { s -> ([TorrentItem], [String], [(String, Int32, Int32, Int32)]) in
                var finished = [CChar](repeating: 0, count: 72 * 32)
                let nf = Int(plx_pump(s, &finished, 32))
                var ids: [String] = []
                for i in 0..<nf {
                    ids.append(finished.withUnsafeBufferPointer { buf in
                        String(cString: buf.baseAddress! + i * 72)
                    })
                }
                var buf = [plx_status](repeating: plx_status(), count: 256)
                let n = Int(buf.withUnsafeMutableBufferPointer { plx_status_all(s, $0.baseAddress, 256) })
                var list: [TorrentItem] = []
                for i in 0..<n {
                    let st = buf[i]
                    list.append(TorrentItem(id: cString(st.id), name: cString(st.name), savePath: cString(st.savePath),
                                            error: cString(st.error), state: Int(st.state), paused: st.paused != 0,
                                            hasMetadata: st.hasMetadata != 0, finished: st.finished != 0,
                                            progress: Double(st.progress), totalWanted: st.totalWanted,
                                            wantedDone: st.totalWantedDone, totalSize: st.totalSize,
                                            downloaded: st.allTimeDownload, uploaded: st.allTimeUpload,
                                            downRate: Int(st.downRate), upRate: Int(st.upRate),
                                            peers: Int(st.peers), seeds: Int(st.seeds)))
                }
                var stats = [plx_iface_stat](repeating: plx_iface_stat(), count: 16)
                let ns = Int(stats.withUnsafeMutableBufferPointer { plx_iface_stats(s, $0.baseAddress, 16) })
                var ifaceList: [(String, Int32, Int32, Int32)] = []
                for i in 0..<ns {
                    let st = stats[i]
                    ifaceList.append((cString(st.interfaceName), st.peers, st.downRate, st.upRate))
                }
                return (list, ids, ifaceList)
            }
            guard let snapshot else { return }
            self.apply(snapshot.0, finished: snapshot.1, interfaces: snapshot.2, seed: seed)
        }
    }

    private func apply(_ list: [TorrentItem], finished: [String], interfaces: [(String, Int32, Int32, Int32)], seed: Bool) {
        let sorted = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if sorted != items { items = sorted }
        var stats: [NetworkKind: InterfaceStat] = [:]
        for (name, peers, down, up) in interfaces {
            guard let kind = kind(forInterface: name) else { continue }
            stats[kind, default: InterfaceStat()].peers += Int(peers)
            stats[kind, default: InterfaceStat()].down += Int(down)
            stats[kind, default: InterfaceStat()].up += Int(up)
        }
        interfaceStats = stats
        for id in finished {
            if let item = list.first(where: { $0.id == id }) {
                notifyFinished(item)
                if !seed { pause(id) }
            }
            FilesStore.shared.refresh()
        }
    }

    /// Torrent-Tempo pro Netzwerk für Diagramm und Datenvolumen (vom DownloadManager abgefragt).
    func speedsByNetwork() -> [NetworkKind: Double] {
        var result: [NetworkKind: Double] = [:]
        for (k, s) in interfaceStats { result[k] = Double(s.down + s.up) }
        return result
    }

    private func notifyFinished(_ item: TorrentItem) {
        let content = UNMutableNotificationContent()
        content.title = "Torrent fertig"
        content.body = "\(item.displayName) (\(Format.bytes(item.totalWanted)))"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
    }
}
