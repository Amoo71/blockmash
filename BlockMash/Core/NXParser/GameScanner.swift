import Foundation

struct ScanResult {
    let title: String
    let titleId: String
    let version: String
    let fileType: GameFileType
    let fileSize: Int64
    let ncaCount: Int
    let contentType: ContentType

    enum ContentType: String {
        case base = "Base Game"
        case update = "Update"
        case dlc = "DLC"
    }
}

actor GameScanner {
    static let shared = GameScanner()

    func scan(url: URL) async throws -> ScanResult {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        guard let fileType = GameFileType.from(extension: url.pathExtension) else {
            throw ScanError.unsupportedFormat(url.pathExtension)
        }
        let fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        let entryNames: [String]
        switch fileType {
        case .nsp, .nsz:
            entryNames = try PFS0Parser.parseFromFile(url: url).entries.map(\.name)
        case .xci, .xcz:
            let header = try XCIParser.parseHeader(url: url)
            entryNames = XCIParser.securePartition(from: header)?.files.map(\.name) ?? []
        }

        let fileName = url.lastPathComponent
        let titleId = Self.titleId(fileName: fileName, entryNames: entryNames)
        return ScanResult(
            title: Self.cleanTitle(url.deletingPathExtension().lastPathComponent),
            titleId: titleId,
            version: Self.version(fileName: fileName),
            fileType: fileType,
            fileSize: fileSize,
            ncaCount: entryNames.filter(NCAInfo.isNCAName).count,
            contentType: Self.classify(titleId)
        )
    }

    /// Title ID from a "[0100…]" tag in the file name, else from a ticket (rights ID = title ID + key generation).
    static func titleId(fileName: String, entryNames: [String]) -> String {
        if let match = fileName.firstMatch(of: /\[([0-9A-Fa-f]{16})\]/) {
            return String(match.1).lowercased()
        }
        for name in entryNames where name.lowercased().hasSuffix(".tik") {
            let hex = name.prefix(16)
            if hex.count == 16, hex.allSatisfy(\.isHexDigit) {
                return hex.lowercased()
            }
        }
        return ""
    }

    static func version(fileName: String) -> String {
        if let match = fileName.firstMatch(of: /\[v(\d+)\]/) {
            return String(match.1)
        }
        return "0"
    }

    /// Base titles end in 0x000 (low 13 bits clear), updates are base + 0x800, DLC is base + 0x1000 + index.
    static func classify(_ titleId: String) -> ScanResult.ContentType {
        guard let value = UInt64(titleId, radix: 16) else { return .base }
        let low = value & 0x1FFF
        if low == 0x800 { return .update }
        if low > 0x1000 { return .dlc }
        return .base
    }

    static func baseTitleId(_ titleId: String) -> String? {
        guard let value = UInt64(titleId, radix: 16) else { return nil }
        return String(format: "%016llx", value & ~UInt64(0x1FFF))
    }

    static func cleanTitle(_ name: String) -> String {
        let stripped = name
            .replacing(/\[[^\]]*\]/, with: "")
            .replacing(/\([^)]*\)/, with: "")
            .replacingOccurrences(of: "_", with: " ")
        let clean = stripped.split(separator: " ").joined(separator: " ")
        return clean.isEmpty ? name : clean
    }
}

enum ScanError: Error, LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        }
    }
}
