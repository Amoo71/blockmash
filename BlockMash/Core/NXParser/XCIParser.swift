import Foundation

struct XCIHeader {
    let signature: Data
    let cartSize: UInt8
    let headerVersion: UInt8
    let flags: UInt8
    let packageId: UInt64
    let validDataEndAddress: UInt64
    let rootPartitionOffset: UInt64
    let rootPartitionSize: UInt64
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
    let hashedRegionSize: UInt32
}

enum XCIError: Error, LocalizedError {
    case invalidHeader
    case truncated
    case noSecurePartition

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Not a valid XCI game card image"
        case .truncated: return "XCI file is truncated"
        case .noSecurePartition: return "No secure partition found in XCI"
        }
    }
}

struct XCIParser {
    static let headerMagic = "HEAD"
    static let hfs0Magic: UInt32 = 0x30534648 // "HFS0"
    static let xciHeaderSize = 0x200
    static let gameCardCertOffset = 0x7000
    static let rootPartitionOffset: UInt64 = 0xF000

    static func parseHeader(url: URL) throws -> XCIHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: xciHeaderSize)
        guard headerData.count >= xciHeaderSize else { throw XCIError.truncated }

        let magic = String(data: headerData.subdata(in: 0x100..<0x104), encoding: .ascii)
        guard magic == headerMagic else { throw XCIError.invalidHeader }

        let cartSize = headerData[0x10D]
        let headerVersion = headerData[0x104]
        let flags = headerData[0x10C]
        let packageId = headerData.withUnsafeBytes { $0.load(fromByteOffset: 0x110, as: UInt64.self) }
        let validDataEndAddress = headerData.withUnsafeBytes { $0.load(fromByteOffset: 0x118, as: UInt64.self) }

        handle.seek(toFileOffset: rootPartitionOffset)
        let rootData = handle.readData(ofLength: 0x200)
        let partitions = try parseHFS0Entries(data: rootData, baseOffset: rootPartitionOffset)

        var parsedPartitions: [XCIPartition] = []
        for partition in partitions {
            let absOffset = rootPartitionOffset + partition.offset
            handle.seek(toFileOffset: absOffset)
            let partData = handle.readData(ofLength: min(0x10000, Int(partition.size)))
            let files = (try? parseHFS0Entries(data: partData, baseOffset: absOffset)) ?? []
            parsedPartitions.append(XCIPartition(
                name: partition.name,
                offset: absOffset,
                size: partition.size,
                files: files
            ))
        }

        return XCIHeader(
            signature: headerData.subdata(in: 0..<0x100),
            cartSize: cartSize,
            headerVersion: headerVersion,
            flags: flags,
            packageId: packageId,
            validDataEndAddress: validDataEndAddress,
            rootPartitionOffset: rootPartitionOffset,
            rootPartitionSize: UInt64(rootData.count),
            partitions: parsedPartitions
        )
    }

    private static func parseHFS0Entries(data: Data, baseOffset: UInt64) throws -> [HFS0Entry] {
        guard data.count >= 16 else { return [] }
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == hfs0Magic else { return [] }

        let fileCount = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let stringTableSize = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

        let entrySize = 0x40
        let entriesStart = 16
        let stringTableStart = entriesStart + Int(fileCount) * entrySize

        guard data.count >= stringTableStart + Int(stringTableSize) else { return [] }

        var entries: [HFS0Entry] = []
        let dataRegionStart = UInt64(stringTableStart + Int(stringTableSize))

        for i in 0..<Int(fileCount) {
            let off = entriesStart + i * entrySize
            let fileOffset = data.withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt64.self) }
            let fileSize = data.withUnsafeBytes { $0.load(fromByteOffset: off + 8, as: UInt64.self) }
            let strOffset = data.withUnsafeBytes { $0.load(fromByteOffset: off + 16, as: UInt32.self) }
            let hashedSize = data.withUnsafeBytes { $0.load(fromByteOffset: off + 20, as: UInt32.self) }

            let nameStart = stringTableStart + Int(strOffset)
            var name = ""
            if nameStart < data.count {
                if let end = data[nameStart...].firstIndex(of: 0) {
                    name = String(data: data[nameStart..<end], encoding: .utf8) ?? ""
                }
            }

            entries.append(HFS0Entry(
                name: name,
                offset: dataRegionStart + fileOffset,
                size: fileSize,
                hashedRegionSize: hashedSize
            ))
        }

        return entries
    }

    static func securePartition(from header: XCIHeader) -> XCIPartition? {
        header.partitions.first { $0.name.lowercased() == "secure" }
    }

    static func ncaFiles(from partition: XCIPartition) -> [HFS0Entry] {
        partition.files.filter { $0.name.hasSuffix(".nca") }
    }

    static var cartSizeLabel: [UInt8: String] {
        [
            0xFA: "1 GB",
            0xF8: "2 GB",
            0xF0: "4 GB",
            0xE0: "8 GB",
            0xE1: "16 GB",
            0xE2: "32 GB"
        ]
    }
}
