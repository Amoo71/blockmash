import Foundation

struct ScanResult {
    let title: String
    let titleId: String
    let version: String
    let fileType: GameFileType
    let fileSize: Int64
    let ncaCount: Int
    let hasProgramNCA: Bool
    let hasControlNCA: Bool
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
        let ext = url.pathExtension.lowercased()

        guard url.startAccessingSecurityScopedResource() else {
            throw ScanError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0

        switch ext {
        case "nsp", "nsz":
            return try scanNSP(url: url, fileSize: fileSize, compressed: ext == "nsz")
        case "xci", "xcz":
            return try scanXCI(url: url, fileSize: fileSize, compressed: ext == "xcz")
        default:
            throw ScanError.unsupportedFormat(ext)
        }
    }

    private func scanNSP(url: URL, fileSize: Int64, compressed: Bool) throws -> ScanResult {
        let header = try PFS0Parser.parseFromFile(url: url)
        let ncas = PFS0Parser.ncaEntries(from: header)
        let titleId = ncas.compactMap(\.titleId).first ?? titleIdFromFilename(url)
        let contentType = classifyContent(titleId: titleId)
        let fileType: GameFileType = compressed ? .nsz : .nsp

        return ScanResult(
            title: cleanTitle(url.deletingPathExtension().lastPathComponent),
            titleId: titleId,
            version: "0",
            fileType: fileType,
            fileSize: fileSize,
            ncaCount: ncas.count,
            hasProgramNCA: ncas.contains { $0.contentType == .program },
            hasControlNCA: ncas.contains { $0.contentType == .control },
            contentType: contentType
        )
    }

    private func scanXCI(url: URL, fileSize: Int64, compressed: Bool) throws -> ScanResult {
        let header = try XCIParser.parseHeader(url: url)
        let secure = XCIParser.securePartition(from: header)
        let ncaFiles = secure.map { XCIParser.ncaFiles(from: $0) } ?? []
        let fileType: GameFileType = compressed ? .xcz : .xci

        let titleId = ncaFiles.compactMap { entry -> String? in
            let hex = entry.name.prefix(32).filter { $0.isHexDigit }
            return hex.count >= 16 ? String(hex.prefix(16)).lowercased() : nil
        }.first ?? titleIdFromFilename(url)

        return ScanResult(
            title: cleanTitle(url.deletingPathExtension().lastPathComponent),
            titleId: titleId,
            version: "0",
            fileType: fileType,
            fileSize: fileSize,
            ncaCount: ncaFiles.count,
            hasProgramNCA: true,
            hasControlNCA: true,
            contentType: .base
        )
    }

    private func titleIdFromFilename(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let pattern = /\[([0-9A-Fa-f]{16})\]/
        if let match = name.firstMatch(of: pattern) {
            return String(match.1).lowercased()
        }
        return ""
    }

    private func classifyContent(titleId: String) -> ScanResult.ContentType {
        guard titleId.count == 16 else { return .base }
        let suffix = String(titleId.suffix(4))
        if suffix == "0800" { return .update }
        let lastDigit = Int(suffix, radix: 16) ?? 0
        if lastDigit > 0 && suffix != "0000" && suffix != "0800" { return .dlc }
        return .base
    }

    private func cleanTitle(_ name: String) -> String {
        var clean = name
        let patterns = [/\[[^\]]*\]/, /\([^)]*\)/]
        for pattern in patterns {
            clean = clean.replacing(pattern, with: "")
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ScanError: Error, LocalizedError {
    case accessDenied
    case unsupportedFormat(String)
    case corruptFile

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Cannot access file"
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        case .corruptFile: return "File appears to be corrupt"
        }
    }
}
