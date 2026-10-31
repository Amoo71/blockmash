import Foundation

struct PFS0Header {
    static let magic: UInt32 = 0x30534650 // "PFS0"
    let fileCount: UInt32
    let stringTableSize: UInt32
    let entries: [PFS0Entry]
    let stringTable: Data
}

struct PFS0Entry {
    let dataOffset: UInt64
    let dataSize: UInt64
    let stringTableOffset: UInt32
    var name: String = ""
}

enum PFS0Error: Error, LocalizedError {
    case invalidMagic
    case truncatedHeader
    case invalidStringTable
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidMagic: return "Not a valid PFS0/NSP archive"
        case .truncatedHeader: return "Archive header is truncated"
        case .invalidStringTable: return "Invalid string table in archive"
        case .fileNotFound(let name): return "File not found: \(name)"
        }
    }
}

struct PFS0Parser {
    static let headerSize = 16
    static let entrySize = 24

    static func parse(data: Data) throws -> PFS0Header {
        guard data.count >= headerSize else { throw PFS0Error.truncatedHeader }

        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == PFS0Header.magic else { throw PFS0Error.invalidMagic }

        let fileCount = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let stringTableSize = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

        let entriesEnd = headerSize + Int(fileCount) * entrySize
        guard data.count >= entriesEnd + Int(stringTableSize) else { throw PFS0Error.truncatedHeader }

        var entries: [PFS0Entry] = []
        for i in 0..<Int(fileCount) {
            let offset = headerSize + i * entrySize
            let dataOffset = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt64.self) }
            let dataSize = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: UInt64.self) }
            let strOffset = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 16, as: UInt32.self) }
            entries.append(PFS0Entry(dataOffset: dataOffset, dataSize: dataSize, stringTableOffset: strOffset))
        }

        let stringTableStart = entriesEnd
        let stringTable = data.subdata(in: stringTableStart..<(stringTableStart + Int(stringTableSize)))

        for i in 0..<entries.count {
            let strStart = Int(entries[i].stringTableOffset)
            if let end = stringTable[strStart...].firstIndex(of: 0) {
                entries[i].name = String(data: stringTable[strStart..<end], encoding: .utf8) ?? ""
            }
        }

        let dataRegionStart = UInt64(entriesEnd + Int(stringTableSize))
        for i in 0..<entries.count {
            entries[i] = PFS0Entry(
                dataOffset: entries[i].dataOffset + dataRegionStart,
                dataSize: entries[i].dataSize,
                stringTableOffset: entries[i].stringTableOffset,
                name: entries[i].name
            )
        }

        return PFS0Header(
            fileCount: fileCount,
            stringTableSize: stringTableSize,
            entries: entries,
            stringTable: stringTable
        )
    }

    static func parseFromFile(url: URL) throws -> PFS0Header {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        let headerData = handle.readData(ofLength: headerSize)
        guard headerData.count >= headerSize else { throw PFS0Error.truncatedHeader }

        let fileCount = headerData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let stringTableSize = headerData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

        let remaining = Int(fileCount) * entrySize + Int(stringTableSize)
        let restData = handle.readData(ofLength: remaining)
        let fullHeader = headerData + restData
        return try parse(data: fullHeader)
    }

    static func ncaEntries(from header: PFS0Header) -> [NCAInfo] {
        header.entries.compactMap { entry in
            guard entry.name.hasSuffix(".nca") || entry.name.hasSuffix(".cnmt.nca") else { return nil }
            return NCAInfo(
                name: entry.name,
                offset: entry.dataOffset,
                size: entry.dataSize,
                titleId: extractTitleId(from: entry.name),
                isMeta: entry.name.contains(".cnmt")
            )
        }
    }

    private static func extractTitleId(from name: String) -> String? {
        let hex = name.prefix(32).filter { $0.isHexDigit }
        return hex.count >= 16 ? String(hex.prefix(16)).lowercased() : nil
    }
}

struct NCAInfo {
    let name: String
    let offset: UInt64
    let size: UInt64
    let titleId: String?
    let isMeta: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var contentType: NCAContentType {
        if isMeta { return .meta }
        if name.contains("000") { return .program }
        if name.contains("001") { return .data }
        if name.contains("002") { return .control }
        return .unknown
    }
}

enum NCAContentType: String {
    case program = "Program"
    case data = "Data"
    case control = "Control"
    case meta = "Meta"
    case unknown = "Unknown"
}
