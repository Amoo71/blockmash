import Foundation

// Gespeicherte Zustände eines Downloads – entspricht shared/types.ts in Plexo.

enum DownloadState: String, Codable, Sendable {
    case queued, probing, downloading, paused, completed, failed

    var label: String {
        switch self {
        case .queued: return "Warteschlange"
        case .probing: return "Verbinde…"
        case .downloading: return "Lädt"
        case .paused: return "Pausiert"
        case .completed: return "Fertig"
        case .failed: return "Fehler"
        }
    }

    var isActive: Bool { self == .probing || self == .downloading }
}

struct BlockState: Codable, Sendable {
    /// Byte-Offset in der Datei.
    var start: Int64
    /// Exklusives Ende; -1 = unbekannt (Server ohne Größenangabe).
    var end: Int64
    /// Zusammenhängend fertige Bytes ab `start` (die „Front“).
    var done: Int64 = 0
    /// Welches Netzwerk wie viele Bytes dieses Blocks geliefert hat.
    var byNetwork: [String: Int64] = [:]

    var length: Int64? { end >= 0 ? end - start : nil }
    var isComplete: Bool {
        guard let length else { return false }
        return done >= length
    }

    var dominantNetwork: NetworkKind? {
        byNetwork.max { $0.value < $1.value }.flatMap { NetworkKind(rawValue: $0.key) }
    }
}

struct DownloadRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    var url: String
    var finalURL: String?
    var fileName: String
    /// Vom Nutzer festgelegter Name – nicht durch den Server-Namen ersetzen.
    var nameLocked = false
    /// Relativ zu Documents, gesetzt sobald fertig.
    var relativePath: String?
    var totalBytes: Int64 = 0
    var supportsRanges = false
    var etag: String?
    var lastModified: String?
    var blocks: [BlockState] = []
    var state: DownloadState = .queued
    var error: String?
    var headers: [String: String] = [:]
    var networks: [NetworkKind]
    /// 0 = automatisch.
    var streams: Int = 0
    var bytesByNetwork: [String: Int64] = [:]
    var created = Date()
    var finished: Date?

    var downloadedBytes: Int64 { blocks.reduce(0) { $0 + $1.done } }

    var progress: Double {
        guard totalBytes > 0 else { return state == .completed ? 1 : 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    var partFileName: String { ".\(id.uuidString).plexo-part" }
}

/// Live-Werte, nicht gespeichert.
struct NetworkLive: Sendable {
    var speed: Double = 0
    var streams: Int = 0
    var bytes: Int64 = 0
    var failing = false
}

struct DownloadLive: Sendable {
    var speed: Double = 0
    var networks: [NetworkKind: NetworkLive] = [:]
    var activeBlocks: Set<Int> = []
    var message: String?
}
