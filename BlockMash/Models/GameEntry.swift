import Foundation

struct GameEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var titleId: String
    var version: String
    var fileType: GameFileType
    var fileSize: Int64
    var filePath: String
    var bookmark: Data?
    var dateAdded: Date
    var lastPlayed: Date?
    var playTime: TimeInterval
    var updates: [GameUpdate]
    var dlc: [GameDLC]
    var ncaCount: Int
    var hasProgramNCA: Bool
    var hasControlNCA: Bool

    init(
        title: String,
        titleId: String = "",
        version: String = "1.0.0",
        fileType: GameFileType,
        fileSize: Int64,
        filePath: String,
        bookmark: Data? = nil,
        ncaCount: Int = 0,
        hasProgramNCA: Bool = false,
        hasControlNCA: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.titleId = titleId
        self.version = version
        self.fileType = fileType
        self.fileSize = fileSize
        self.filePath = filePath
        self.bookmark = bookmark
        self.dateAdded = Date()
        self.lastPlayed = nil
        self.playTime = 0
        self.updates = []
        self.dlc = []
        self.ncaCount = ncaCount
        self.hasProgramNCA = hasProgramNCA
        self.hasControlNCA = hasControlNCA
    }

    /// Finds the game file: stored path, then bookmark, then the app's Games folder.
    /// When `needsStop` is true the caller must call `stopAccessingSecurityScopedResource()`.
    func resolveURL() -> (url: URL, needsStop: Bool)? {
        if Self.isRegularFile(filePath) {
            return (URL(fileURLWithPath: filePath), false)
        }
        if let data = bookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                let ok = url.startAccessingSecurityScopedResource()
                if Self.isRegularFile(url.path) { return (url, ok) }
                if ok { url.stopAccessingSecurityScopedResource() }
            }
        }
        let name = (filePath as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        for dir in [AppFolders.games, AppFolders.documents] {
            let candidate = dir.appendingPathComponent(name)
            if Self.isRegularFile(candidate.path) { return (candidate, false) }
        }
        return nil
    }

    private static func isRegularFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedPlayTime: String {
        if playTime < 60 { return "< 1 min" }
        let hours = Int(playTime) / 3600
        let minutes = (Int(playTime) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes) min"
    }

    var isLaunchable: Bool {
        hasProgramNCA && fileExists
    }

    var fileExists: Bool {
        guard let resolved = resolveURL() else { return false }
        if resolved.needsStop { resolved.url.stopAccessingSecurityScopedResource() }
        return true
    }
}

enum GameFileType: String, Codable, CaseIterable {
    case nsp = "NSP"
    case nsz = "NSZ"
    case xci = "XCI"
    case xcz = "XCZ"

    var icon: String {
        switch self {
        case .nsp, .nsz: return "doc.zipper"
        case .xci, .xcz: return "sdcard"
        }
    }

    static func from(extension ext: String) -> GameFileType? {
        switch ext.lowercased() {
        case "nsp": return .nsp
        case "nsz": return .nsz
        case "xci": return .xci
        case "xcz": return .xcz
        default: return nil
        }
    }
}

struct GameUpdate: Identifiable, Codable, Hashable {
    let id: UUID
    var version: String
    var filePath: String
    var fileSize: Int64

    init(version: String, filePath: String, fileSize: Int64) {
        self.id = UUID()
        self.version = version
        self.filePath = filePath
        self.fileSize = fileSize
    }
}

struct GameDLC: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var titleId: String
    var filePath: String
    var fileSize: Int64

    init(name: String, titleId: String, filePath: String, fileSize: Int64) {
        self.id = UUID()
        self.name = name
        self.titleId = titleId
        self.filePath = filePath
        self.fileSize = fileSize
    }
}
