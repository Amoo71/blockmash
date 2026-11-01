import Foundation
import UniformTypeIdentifiers

enum AppFolders {
    static let gameExtensions: Set<String> = ["nsp", "nsz", "xci", "xcz"]

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var games: URL { documents.appendingPathComponent("Games", isDirectory: true) }
    static var keysFile: URL { documents.appendingPathComponent("prod.keys") }

    static func isGameFile(_ url: URL) -> Bool {
        isGameFileName(url.lastPathComponent)
    }

    static func isGameFileName(_ name: String) -> Bool {
        gameExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func ensureFolders() {
        try? FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
    }

    /// LiveContainer stores a guest app's data inside its own Documents folder.
    static var isLiveContainer: Bool {
        documents.pathComponents.filter { $0 == "Documents" }.count > 1
    }

    /// The Games folder as it appears in the Files app.
    static var gamesFolderHint: String {
        let parts = games.pathComponents
        guard let first = parts.firstIndex(of: "Documents"), parts.count - first > 2 else {
            return "BlockMash › Games"
        }
        let rel = parts[(first + 1)...].map { part -> String in
            part.count == 36 && part.contains("-") ? String(part.prefix(8)) + "…" : part
        }
        return (["LiveContainer"] + rel).joined(separator: " › ")
    }

    static var gamesFolderFilesURL: URL? {
        let path = games.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? games.path
        return URL(string: "shareddocuments://" + path)
    }

    /// First pasteboard representation that is real file data (not a URL to one).
    static func fileProviders(in providers: [NSItemProvider]) -> [(NSItemProvider, String)] {
        providers.compactMap { (provider: NSItemProvider) -> (NSItemProvider, String)? in
            let match = provider.registeredTypeIdentifiers.first { id in
                guard let type = UTType(id) else { return false }
                return type.conforms(to: .data) && !type.conforms(to: .url)
            }
            guard let match else { return nil }
            return (provider, match)
        }
    }

    /// Moves a temporary file handed over by the clipboard into the Games folder.
    static func adoptGameFile(at temp: URL, suggestedName: String?, typeIdentifier: String) throws -> URL {
        var candidates = [temp.lastPathComponent]
        if let suggestedName {
            candidates.append(suggestedName)
            if let ext = UTType(typeIdentifier)?.preferredFilenameExtension {
                candidates.append(suggestedName + "." + ext)
            }
        }
        guard let name = candidates.first(where: isGameFileName) else {
            throw ImportError.notAGame
        }

        let fm = FileManager.default
        try fm.createDirectory(at: games, withIntermediateDirectories: true)
        let dest = games.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        do {
            try fm.moveItem(at: temp, to: dest)
        } catch {
            try fm.copyItem(at: temp, to: dest)
        }
        return dest
    }
}

enum ImportError: LocalizedError {
    case notKeys
    case notAGame
    case clipboardUnreadable

    var errorDescription: String? {
        switch self {
        case .notKeys: return "That doesn't look like prod.keys — no keys found in it."
        case .notAGame: return "Not a game file (.nsp, .nsz, .xci, .xcz)."
        case .clipboardUnreadable: return "Couldn't read the clipboard."
        }
    }
}

extension Array where Element == UInt8 {
    /// Little-endian integer at `offset`; 0 when out of bounds.
    func readLE<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= count else { return 0 }
        var value: T = 0
        for i in 0..<size {
            value |= T(self[offset + i]) << (8 * i)
        }
        return value
    }

    /// NUL-terminated UTF-8 string starting at `start`, never reading past `limit`.
    func cString(from start: Int, limit: Int) -> String {
        let end = Swift.min(limit, count)
        guard start >= 0, start < end else { return "" }
        var stop = start
        while stop < end && self[stop] != 0 { stop += 1 }
        return String(decoding: self[start..<stop], as: UTF8.self)
    }
}
