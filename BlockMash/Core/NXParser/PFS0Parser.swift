import Foundation

struct PFS0Header {
    static let magic: UInt32 = 0x30534650 // "PFS0"
    let fileCount: UInt32
    let stringTableSize: UInt32
    let entries: [PFS0Entry]
}

struct PFS0Entry {
    let dataOffset: UInt64
    let dataSize: UInt64
    let name: String
}

enum PFS0Error: Error, LocalizedError {
    case invalidMagic
    case truncatedHeader

    var errorDescription: String? {
        switch self {
        case .invalidMagic: return "Not a valid NSP/NSZ file"
        case .truncatedHeader: return "File is truncated or corrupt"
        }
    }
}

struct PFS0Parser {
    static let headerSize = 16
    static let entrySize = 24
    static let maxFiles: UInt32 = 4096
    static let maxStringTable: UInt32 = 1 << 20

    static func parseFromFile(url: URL) throws -> PFS0Header {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let head = try handle.read(upToCount: headerSize) ?? Data()
        let (fileCount, stringTableSize) = try counts(in: [UInt8](head))
        let rest = try handle.read(upToCount: Int(fileCount) * entrySize + Int(stringTableSize)) ?? Data()
        return try parse(data: head + rest)
    }

    static func parse(data: Data) throws -> PFS0Header {
        let bytes = [UInt8](data)
        let (fileCount, stringTableSize) = try counts(in: bytes)
        let entriesEnd = headerSize + Int(fileCount) * entrySize
        let stringTableEnd = entriesEnd + Int(stringTableSize)
        guard bytes.count >= stringTableEnd else { throw PFS0Error.truncatedHeader }

        let dataRegionStart = UInt64(stringTableEnd)
        var entries: [PFS0Entry] = []
        entries.reserveCapacity(Int(fileCount))
        for i in 0..<Int(fileCount) {
            let off = headerSize + i * entrySize
            let nameOffset = Int(bytes.readLE(UInt32.self, at: off + 16))
            entries.append(PFS0Entry(
                dataOffset: dataRegionStart &+ bytes.readLE(UInt64.self, at: off),
                dataSize: bytes.readLE(UInt64.self, at: off + 8),
                name: bytes.cString(from: entriesEnd + nameOffset, limit: stringTableEnd)
            ))
        }
        return PFS0Header(fileCount: fileCount, stringTableSize: stringTableSize, entries: entries)
    }

    private static func counts(in bytes: [UInt8]) throws -> (UInt32, UInt32) {
        guard bytes.count >= headerSize else { throw PFS0Error.truncatedHeader }
        guard bytes.readLE(UInt32.self, at: 0) == PFS0Header.magic else { throw PFS0Error.invalidMagic }
        let fileCount = bytes.readLE(UInt32.self, at: 4)
        let stringTableSize = bytes.readLE(UInt32.self, at: 8)
        guard fileCount <= maxFiles, stringTableSize <= maxStringTable else { throw PFS0Error.truncatedHeader }
        return (fileCount, stringTableSize)
    }
}

enum NCAInfo {
    /// .ncz is the compressed NCA used inside NSZ/XCZ.
    static func isNCAName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".nca") || lower.hasSuffix(".ncz")
    }
}
