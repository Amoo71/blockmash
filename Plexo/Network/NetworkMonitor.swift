import Foundation
import Network
import SwiftUI

// Netzwerke des iPhones – entspricht network/interfaces.ts + limits.ts in Plexo.
// Auf iOS gibt es WLAN, Mobilfunk und (per USB-Adapter) Ethernet. Jede Verbindung wird über
// NWParameters.requiredInterfaceType fest an eines davon gebunden.

enum NetworkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case wifi
    case cellular
    case ethernet

    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .wifi: return "WLAN"
        case .cellular: return "Mobilfunk"
        case .ethernet: return "Ethernet"
        }
    }

    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        }
    }

    var interfaceType: NWInterface.InterfaceType {
        switch self {
        case .wifi: return .wifi
        case .cellular: return .cellular
        case .ethernet: return .wiredEthernet
        }
    }

    var defaultColorHex: String {
        switch self {
        case .wifi: return "#3B82F6"
        case .cellular: return "#F59E0B"
        case .ethernet: return "#10B981"
        }
    }
}

enum LimitPeriod: String, Codable, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "pro Tag"
        case .week: return "pro Woche"
        case .month: return "pro Monat"
        }
    }
}

struct NetworkSettings: Codable, Equatable {
    var enabled = true
    var name: String?
    var colorHex: String?
    /// Bytes pro Sekunde, 0 = unbegrenzt.
    var speedLimit: Int64 = 0
    /// Datenvolumen pro Zeitraum in Bytes, 0 = kein Limit.
    var dataCap: Int64 = 0
    var capPeriod: LimitPeriod = .month
    var usedBytes: Int64 = 0
    var periodStart = Date()
}

enum NetworkStatus {
    case on, off, offline, limit

    var label: String {
        switch self {
        case .on: return "Verbunden"
        case .off: return "Ausgeschaltet"
        case .offline: return "Nicht verfügbar"
        case .limit: return "Datenlimit erreicht"
        }
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    static let palette = ["#3B82F6", "#F59E0B", "#10B981", "#EF4444", "#8B5CF6", "#EC4899", "#14B8A6", "#F97316"]
    static let historyLength = 60

    @Published private(set) var available: [NetworkKind: Bool] = [:]
    @Published private(set) var interfaceNames: [NetworkKind: String] = [:]
    @Published private(set) var settings: [NetworkKind: NetworkSettings] = [:]
    @Published private(set) var speeds: [NetworkKind: Double] = [:]
    @Published private(set) var history: [NetworkKind: [Double]] = [:]
    /// Netzwerk, über das iOS gerade standardmäßig lädt (Hintergrund-Downloads).
    @Published private(set) var primary: NetworkKind?

    private var monitors: [NWPathMonitor] = []
    private let queue = DispatchQueue(label: "plexo.netmon")
    private let settingsKey = "networkSettings"
    private var lastSave = Date.distantPast

    private init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: NetworkSettings].self, from: data) {
            for (k, v) in decoded {
                if let kind = NetworkKind(rawValue: k) { settings[kind] = v }
            }
        }
        for kind in NetworkKind.allCases {
            if settings[kind] == nil { settings[kind] = NetworkSettings() }
            history[kind] = Array(repeating: 0, count: Self.historyLength)
            let monitor = NWPathMonitor(requiredInterfaceType: kind.interfaceType)
            monitor.pathUpdateHandler = { [weak self] path in
                let ok = path.status == .satisfied
                let name = path.availableInterfaces.first { $0.type == kind.interfaceType }?.name
                Task { @MainActor in
                    self?.available[kind] = ok
                    self?.interfaceNames[kind] = name
                }
            }
            monitor.start(queue: queue)
            monitors.append(monitor)
        }
        let general = NWPathMonitor()
        general.pathUpdateHandler = { [weak self] path in
            var kind: NetworkKind?
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) {
                    kind = .wifi
                } else if path.usesInterfaceType(.wiredEthernet) {
                    kind = .ethernet
                } else if path.usesInterfaceType(.cellular) {
                    kind = .cellular
                }
            }
            let result = kind
            Task { @MainActor in self?.primary = result }
        }
        general.start(queue: queue)
        monitors.append(general)
        rollPeriods()
    }

    // MARK: - Anzeige

    func name(_ kind: NetworkKind) -> String {
        let n = settings[kind]?.name ?? ""
        return n.isEmpty ? kind.defaultName : n
    }

    func color(_ kind: NetworkKind) -> Color {
        Color(hex: settings[kind]?.colorHex ?? kind.defaultColorHex)
    }

    func isAvailable(_ kind: NetworkKind) -> Bool { available[kind] ?? false }

    func isOverCap(_ kind: NetworkKind) -> Bool {
        guard let s = settings[kind], s.dataCap > 0 else { return false }
        return s.usedBytes >= s.dataCap
    }

    /// Darf gerade für Downloads genutzt werden (verfügbar, eingeschaltet, Limit nicht erreicht).
    func isUsable(_ kind: NetworkKind) -> Bool {
        isAvailable(kind) && (settings[kind]?.enabled ?? true) && !isOverCap(kind)
    }

    func status(_ kind: NetworkKind) -> NetworkStatus {
        if !isAvailable(kind) { return .offline }
        if !(settings[kind]?.enabled ?? true) { return .off }
        if isOverCap(kind) { return .limit }
        return .on
    }

    var visibleKinds: [NetworkKind] {
        NetworkKind.allCases.filter { $0 != .ethernet || isAvailable($0) }
    }

    // MARK: - Einstellungen

    func update(_ kind: NetworkKind, _ change: (inout NetworkSettings) -> Void) {
        var s = settings[kind] ?? NetworkSettings()
        change(&s)
        settings[kind] = s
        persist(force: true)
    }

    func resetUsage(_ kind: NetworkKind) {
        update(kind) {
            $0.usedBytes = 0
            $0.periodStart = Date()
        }
    }

    private func persist(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) > 5 else { return }
        lastSave = now
        var dict: [String: NetworkSettings] = [:]
        for (k, v) in settings { dict[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func rollPeriods() {
        let cal = Calendar.current
        let now = Date()
        for kind in NetworkKind.allCases {
            guard var s = settings[kind] else { continue }
            let component: Calendar.Component
            switch s.capPeriod {
            case .day: component = .day
            case .week: component = .weekOfYear
            case .month: component = .month
            }
            if !cal.isDate(s.periodStart, equalTo: now, toGranularity: component) {
                s.usedBytes = 0
                s.periodStart = now
                settings[kind] = s
            }
        }
    }

    // MARK: - Live-Werte (vom DownloadManager jede Sekunde gemeldet)

    func record(speeds newSpeeds: [NetworkKind: Double], usage: [NetworkKind: Int64]) {
        rollPeriods()
        for (kind, bytes) in usage where bytes > 0 {
            settings[kind]?.usedBytes += bytes
        }
        speeds = newSpeeds
        for kind in NetworkKind.allCases {
            var h = history[kind] ?? []
            h.append(newSpeeds[kind] ?? 0)
            if h.count > Self.historyLength { h.removeFirst(h.count - Self.historyLength) }
            history[kind] = h
        }
        persist()
    }
}
