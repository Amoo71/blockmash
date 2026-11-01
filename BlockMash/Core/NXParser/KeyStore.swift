import Foundation

struct KeyStore {
    var keys: [String: Data] = [:]

    var headerKey: Data? { keys["header_key"] }
    var hasRequiredKeys: Bool { headerKey != nil }

    var keyCount: Int { keys.count }
    var titleKeyCount: Int { keys.filter { $0.key.hasPrefix("titlekek_") }.count }
    var keyAreaKeyCount: Int { keys.filter { $0.key.contains("key_area_key") }.count }

    static func load(from url: URL) throws -> KeyStore {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content)
    }

    static func loadFromDocuments() -> KeyStore? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let keysFile = docs.appendingPathComponent("prod.keys")
        guard FileManager.default.fileExists(atPath: keysFile.path) else { return nil }
        return try? load(from: keysFile)
    }

    static func parse(content: String) -> KeyStore {
        var store = KeyStore()
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()

            if let data = hexToData(value) {
                store.keys[key] = data
            }
        }

        return store
    }

    static func save(_ store: KeyStore, to url: URL) throws {
        var lines: [String] = []
        for (key, value) in store.keys.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key) = \(value.map { String(format: "%02x", $0) }.joined())")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func hexToData(_ hex: String) -> Data? {
        let clean = hex.replacingOccurrences(of: " ", with: "")
        guard clean.count % 2 == 0 else { return nil }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

enum KeyStoreError: Error, LocalizedError {
    case accessDenied
    case invalidFormat
    case missingRequiredKeys

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Cannot access key file"
        case .invalidFormat: return "Invalid key file format"
        case .missingRequiredKeys: return "Missing required encryption keys"
        }
    }
}
