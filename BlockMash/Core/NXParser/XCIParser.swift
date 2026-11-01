import Foundation

struct XCIHeader {
    let cartSize: UInt8
    let packageId: UInt64
    let partitions: [XCIPartition]
}

struct XCIPartition {
    let name: String
    let offset: UInt64
    let size: UInt64
    let files: [HFS0Entry]
}

struct HFS0Entry {
    let name: String
    let offset: UInt64
    let size: UInt64
}

enum XCIError: Error, LocalizedError {
    case invalidHeader
    case truncated

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Not a valid XCI/XCZ file"
        case .truncated: return "File is truncated or corrupt"
        }
    }
}

struct XCIParser {
    static let headerMagic: [UInt8] = Array("HEAD".utf8)
    static let hfs0Magic: UInt32 = 0x30534648 // "HFS0"
    static let headerSize = 0x200
    static let defaultRootOffset: UInt64 = 0xF000
    static let partitionReadLimit: UInt64 = 0x10000

    static func parseHeader(url: URL) throws -> XCIHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let header = [UInt8](try handle.read(upToCount: headerSize) ?? Data())
        guard header.count >= headerSize else { throw XCIError.truncated }
        guard Array(header[0x100..<0x104]) == headerMagic else { throw XCIError.invalidHeader }

        // 0x130 holds the root HFS0 offset; almost always 0xF000.
        let storedRoot = header.readLE(UInt64.self, at: 0x130)
        let rootOffset = (storedRoot > 0 && storedRoot < 0x1000000) ? storedRoot : defaultRootOffset

        try handle.seek(toOffset: rootOffset)
        let root = parseHFS0([UInt8](try handle.read(upToCount: 0x200) ?? Data()))

        var partitions: [XCIPartition] = []
        for partition in root {
            let (absOffset, overflow) = rootOffset.addingReportingOverflow(partition.offset)
            guard !overflow, absOffset < (UInt64(1) << 62) else { continue }
            try handle.seek(toOffset: absOffset)
            let data = try handle.read(upToCount: Int(min(partition.size, partitionReadLimit))) ?? Data()
            partitions.append(XCIPartition(
                name: partition.name,
                offset: absOffset,
                size: partition.size,
                files: parseHFS0([UInt8](data))
            ))
        }

        return XCIHeader(
            cartSize: header[0x10D],
            packageId: header.readLE(UInt64.self, at: 0x110),
            partitions: partitions
        )
    }

    private static func parseHFS0(_ bytes: [UInt8]) -> [HFS0Entry] {
        guard bytes.count >= 16, bytes.readLE(UInt32.self, at: 0) == hfs0Magic else { return [] }
        let fileCount = Int(bytes.readLE(UInt32.self, at: 4))
        let stringTableSize = Int(bytes.readLE(UInt32.self, at: 8))
        guard fileCount <= 4096 else { return [] }

        let entrySize = 0x40
        let stringTableStart = 16 + fileCount * entrySize
        let stringTableEnd = stringTableStart + stringTableSize
        guard bytes.count >= stringTableStart else { return [] }

        let dataStart = UInt64(stringTableEnd)
        return (0..<fileCount).map { (i: Int) -> HFS0Entry in
            let off = 16 + i * entrySize
            let nameOffset = Int(bytes.readLE(UInt32.self, at: off + 16))
            return HFS0Entry(
                name: bytes.cString(from: stringTableStart + nameOffset, limit: stringTableEnd),
                offset: dataStart &+ bytes.readLE(UInt64.self, at: off),
                size: bytes.readLE(UInt64.self, at: off + 8)
            )
        }
    }

    static func securePartition(from header: XCIHeader) -> XCIPartition? {
        header.partitions.first { $0.name.lowercased() == "secure" }
    }

    static func ncaFiles(from partition: XCIPartition) -> [HFS0Entry] {
        partition.files.filter { NCAInfo.isNCAName($0.name) }
    }
}
