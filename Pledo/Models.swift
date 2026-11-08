import Foundation

// Datenmodelle – angelehnt an die Modelle von pledo (Web/Models).

struct PlexAccount: Codable, Hashable, Sendable {
    var id: Int?
    var uuid: String?
    var username: String?
    var title: String?
    var email: String?
    var authToken: String

    var displayName: String { title ?? username ?? email ?? "Plex-Konto" }
}

struct ServerConnection: Codable, Hashable, Sendable {
    var uri: String
    var address: String
    var protocolName: String
    var port: Int
    var local: Bool
    var relay: Bool
    var ipv6: Bool
}

struct PlexServer: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var sourceTitle: String?
    var owned: Bool
    var accessToken: String
    var connections: [ServerConnection]
    var lastKnownUri: String?
    var isOnline: Bool = false
    var lastChecked: Date?

    var ownerLabel: String {
        if owned { return "Eigener Server" }
        if let sourceTitle, !sourceTitle.isEmpty { return "Geteilt von \(sourceTitle)" }
        return "Geteilter Server"
    }

    var connectionLabel: String {
        guard let uri = lastKnownUri else { return "Keine Verbindung" }
        if let c = connections.first(where: { $0.uri == uri }) {
            if c.relay { return "Relay" }
            return c.local ? "Lokal" : "Remote"
        }
        return "Direkt (HTTP)"
    }
}

struct PlexLibrary: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(serverId)/\(key)" }
    var key: String
    var uuid: String?
    var name: String
    var type: String
    var serverId: String
}

struct MediaFile: Codable, Identifiable, Hashable, Sendable {
    var id: String { downloadUri }
    var downloadUri: String
    var serverFilePath: String
    var totalBytes: Int64
    var duration: Int64?
    var bitrate: Int?
    var width: Int?
    var height: Int?
    var aspectRatio: Double?
    var audioChannels: Int?
    var audioCodec: String?
    var videoCodec: String?
    var videoResolution: String?
    var container: String?
    var videoFrameRate: String?
    var audioProfile: String?
    var videoProfile: String?

    var resolutionLabel: String {
        guard let r = videoResolution, !r.isEmpty else { return "?" }
        if Int(r) != nil { return r + "p" }
        return r.uppercased()
    }

    /// Dateiname, wie er auf dem Server liegt (Windows- und Unix-Pfade).
    var fileName: String {
        let normalized = serverFilePath.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/").last.map { String($0) } ?? ""
    }

    var shortSummary: String {
        var parts: [String] = [resolutionLabel]
        if let v = videoCodec, !v.isEmpty { parts.append(v.uppercased()) }
        if totalBytes > 0 { parts.append(Format.bytes(totalBytes)) }
        return parts.joined(separator: " · ")
    }

    var summary: String {
        var parts: [String] = [resolutionLabel]
        if let v = videoCodec, !v.isEmpty { parts.append(v.uppercased()) }
        if let a = audioCodec, !a.isEmpty {
            if let ch = audioChannels { parts.append("\(a.uppercased()) \(ch)ch") } else { parts.append(a.uppercased()) }
        }
        if let c = container, !c.isEmpty { parts.append(c.uppercased()) }
        if totalBytes > 0 { parts.append(Format.bytes(totalBytes)) }
        return parts.joined(separator: " · ")
    }
}

enum ElementType: String, Codable, Sendable {
    case movie
    case episode
}

struct Movie: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(serverId)/\(ratingKey)" }
    var ratingKey: String
    var key: String
    var title: String
    var year: Int?
    var summary: String?
    var thumb: String?
    var libraryId: String
    var serverId: String
    var mediaFiles: [MediaFile]

    var displayTitle: String {
        if let year { return "\(title) (\(year))" }
        return title
    }
}

struct TvShow: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(serverId)/\(ratingKey)" }
    var ratingKey: String
    var key: String
    var title: String
    var year: Int?
    var summary: String?
    var thumb: String?
    var libraryId: String
    var serverId: String
    var seasonCount: Int?
    var episodeCount: Int?
}

struct Episode: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(serverId)/\(ratingKey)" }
    var showId: String { "\(serverId)/\(showRatingKey)" }
    var ratingKey: String
    var key: String
    var title: String
    var year: Int?
    var thumb: String?
    var libraryId: String
    var serverId: String
    var showRatingKey: String
    var showTitle: String
    var seasonNumber: Int
    var episodeNumber: Int
    var mediaFiles: [MediaFile]

    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
}

struct Playlist: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(serverId)/\(ratingKey)" }
    var ratingKey: String
    var name: String
    var serverId: String
    var items: [String]
}

struct LibraryCache: Codable, Sendable {
    var account: PlexAccount?
    var servers: [PlexServer]
    var libraries: [PlexLibrary]
    var movies: [Movie]
    var shows: [TvShow]
    var episodes: [Episode]
    var playlists: [Playlist]
    var lastSync: Date?
}

enum Format {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(max(0, bytesPerSecond))) + "/s"
    }

    static func duration(ms: Int64?) -> String? {
        guard let ms, ms > 0 else { return nil }
        let minutes = ms / 60000
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
        return "\(minutes) min"
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
