import Foundation

struct ShaderCacheEntry: Codable, Identifiable {
    var id: String { titleId + "_" + hash }
    let titleId: String
    let hash: String
    let shaderType: ShaderType
    let createdAt: Date
    let sizeBytes: Int64

    enum ShaderType: String, Codable {
        case vertex
        case fragment
        case compute
    }
}

actor ShaderCacheManager {
    static let shared = ShaderCacheManager()

    private var cacheDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ShaderCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func cacheDirectory(for titleId: String) -> URL {
        let dir = cacheDir.appendingPathComponent(titleId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func cacheSize() -> Int64 {
        directorySize(url: cacheDir)
    }

    func cacheSize(for titleId: String) -> Int64 {
        directorySize(url: cacheDir.appendingPathComponent(titleId))
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func clearCache(for titleId: String) {
        let dir = cacheDir.appendingPathComponent(titleId)
        try? FileManager.default.removeItem(at: dir)
    }

    func titleIdsWithCache() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil)) ?? []
        return contents.filter(\.hasDirectoryPath).map(\.lastPathComponent)
    }

    private func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
