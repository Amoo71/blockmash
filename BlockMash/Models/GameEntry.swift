import Foundation

struct GameEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var titleId: String
    var version: String
    var fileType: GameFileType
    var fileSize: Int64
    var filePath: String
    var dateAdded: Date
    var lastPlayed: Date?
    var updates: [GameUpdate]
    var dlc: [GameDLC]

    init(
        title: String,
        titleId: String = "",
        version: String = "1.0.0",
        fileType: GameFileType,
        fileSize: Int64,
        filePath: String
    ) {
        self.id = UUID()
        self.title = title
        self.titleId = titleId
        self.version = version
        self.fileType = fileType
        self.fileSize = fileSize
        self.filePath = filePath
        self.dateAdded = Date()
        self.lastPlayed = nil
        self.updates = []
        self.dlc = []
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
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
