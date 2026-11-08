import Foundation
import ZIPFoundation

// Dateioperationen (laufen im Hintergrund): Auflisten, Ordner, Umbenennen, Löschen,
// Verschieben/Kopieren, ZIP erstellen/entpacken, RAR entpacken.

enum ArchiveKind {
    case zip
    case rar

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "zip", "cbz": self = .zip
        case "rar", "cbr": self = .rar
        default: return nil
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?

    var id: URL { url }
    var archiveKind: ArchiveKind? { isDirectory ? nil : ArchiveKind(url: url) }

    var icon: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "zip", "rar", "7z", "tar", "gz", "cbz", "cbr": return "doc.zipper"
        case "mkv", "mp4", "m4v", "mov", "avi", "wmv", "ts", "webm", "mpg", "mpeg": return "film"
        case "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus": return "music.note"
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff": return "photo"
        case "pdf": return "doc.richtext"
        case "srt", "sub", "ass", "ssa", "vtt", "txt", "nfo", "log", "md": return "doc.text"
        case "ipa": return "app.badge"
        default: return "doc"
        }
    }
}

enum FileOpsError: LocalizedError {
    case cancelled
    case needPassword(URL)
    case badPassword(URL)
    case rar(Int32)
    case invalidDestination
    case invalidName

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Abgebrochen"
        case .needPassword: return "Das Archiv ist passwortgeschützt."
        case .badPassword: return "Falsches Passwort."
        case .rar(let code): return "RAR-Archiv konnte nicht entpackt werden (Fehler \(code))."
        case .invalidDestination: return "Ein Ordner kann nicht in sich selbst verschoben werden."
        case .invalidName: return "Ungültiger Name."
        }
    }
}

/// Fortschritt & Abbruch für eine laufende Operation (threadsicher).
final class OperationReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var cancelHook: (() -> Void)?
    private var lastReport = Date.distantPast
    var onUpdate: ((Double?, String?) -> Void)?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let hook = cancelHook
        lock.unlock()
        hook?()
    }

    func setCancelHook(_ hook: (() -> Void)?) {
        lock.lock()
        cancelHook = hook
        let c = cancelled
        lock.unlock()
        if c { hook?() }
    }

    func report(_ progress: Double?, _ detail: String?, force: Bool = false) {
        let now = Date()
        lock.lock()
        let should = force || now.timeIntervalSince(lastReport) >= 0.15
        if should { lastReport = now }
        let handler = onUpdate
        lock.unlock()
        if should { handler?(progress, detail) }
    }

    func checkCancelled() throws {
        if isCancelled { throw FileOpsError.cancelled }
    }
}

private final class RarContext {
    let reporter: OperationReporter
    init(_ reporter: OperationReporter) { self.reporter = reporter }
}

enum FileOps {
    static let fm = FileManager.default

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func list(_ dir: URL) throws -> [FileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let items = urls.map { url -> FileItem in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return FileItem(url: url, name: url.lastPathComponent, isDirectory: v?.isDirectory ?? false,
                            size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate)
        }
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." || name.contains("/") { throw FileOpsError.invalidName }
        return name
    }

    static func uniqueURL(in dir: URL, name: String, directory: Bool = false) -> URL {
        var candidate = dir.appendingPathComponent(name)
        if !exists(candidate) { return candidate }
        let ns = name as NSString
        let ext = directory ? "" : ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        for i in 2...100_000 {
            let n = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = dir.appendingPathComponent(n)
            if !exists(candidate) { return candidate }
        }
        return candidate
    }

    static func createFolder(in dir: URL, name: String) throws -> URL {
        let url = uniqueURL(in: dir, name: try validName(name), directory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func rename(_ url: URL, to name: String) throws -> URL {
        let newName = try validName(name)
        if newName == url.lastPathComponent { return url }
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        if exists(dest) && dest.path.lowercased() != url.path.lowercased() {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.moveItem(at: url, to: dest)
        return dest
    }

    static func delete(_ urls: [URL], reporter: OperationReporter) throws {
        for (i, url) in urls.enumerated() {
            try reporter.checkCancelled()
            reporter.report(Double(i) / Double(max(1, urls.count)), url.lastPathComponent)
            try fm.removeItem(at: url)
        }
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func transfer(_ urls: [URL], to dir: URL, copy: Bool, reporter: OperationReporter) throws {
        let destPath = resolvedPath(dir)
        for (i, url) in urls.enumerated() {
            try reporter.checkCancelled()
            let srcPath = resolvedPath(url)
            if destPath == srcPath || destPath.hasPrefix(srcPath + "/") { throw FileOpsError.invalidDestination }
            if !copy && resolvedPath(url.deletingLastPathComponent()) == destPath { continue }
            reporter.report(Double(i) / Double(max(1, urls.count)), url.lastPathComponent, force: true)
            let dest = uniqueURL(in: dir, name: url.lastPathComponent, directory: isDirectory(url))
            if copy {
                try fm.copyItem(at: url, to: dest)
            } else {
                do {
                    try fm.moveItem(at: url, to: dest)
                } catch {
                    // Zwischen verschiedenen Speicherorten: kopieren + löschen
                    try fm.copyItem(at: url, to: dest)
                    try fm.removeItem(at: url)
                }
            }
        }
    }

    static func importFiles(_ urls: [URL], into dir: URL, reporter: OperationReporter) throws {
        for (i, url) in urls.enumerated() {
            try reporter.checkCancelled()
            reporter.report(Double(i) / Double(max(1, urls.count)), url.lastPathComponent, force: true)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dest = uniqueURL(in: dir, name: url.lastPathComponent, directory: isDirectory(url))
            try fm.copyItem(at: url, to: dest)
        }
    }

    // MARK: - ZIP

    static func zip(_ urls: [URL], to dest: URL, reporter: OperationReporter) throws {
        var entries: [(path: String, base: URL)] = []
        for url in urls {
            let base = url.deletingLastPathComponent()
            entries.append((url.lastPathComponent, base))
            if isDirectory(url), let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                let rootPath = resolvedPath(url)
                for case let sub as URL in en {
                    let subPath = resolvedPath(sub)
                    guard subPath.hasPrefix(rootPath + "/") else { continue }
                    let rel = String(subPath.dropFirst(rootPath.count + 1))
                    entries.append((url.lastPathComponent + "/" + rel, base))
                }
            }
        }
        do {
            let archive = try Archive(url: dest, accessMode: .create, pathEncoding: nil)
            for (i, entry) in entries.enumerated() {
                try reporter.checkCancelled()
                reporter.report(Double(i) / Double(max(1, entries.count)), entry.path)
                try archive.addEntry(with: entry.path, relativeTo: entry.base, compressionMethod: .deflate)
            }
        } catch {
            try? fm.removeItem(at: dest)
            throw reporter.isCancelled ? FileOpsError.cancelled : error
        }
    }

    static func unzip(_ url: URL, to dest: URL, reporter: OperationReporter) throws {
        let progress = Progress()
        reporter.setCancelHook { progress.cancel() }
        let observation = progress.observe(\.fractionCompleted) { p, _ in
            reporter.report(p.fractionCompleted, nil)
        }
        defer {
            observation.invalidate()
            reporter.setCancelHook(nil)
        }
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try fm.unzipItem(at: url, to: dest, progress: progress)
        } catch {
            try? fm.removeItem(at: dest)
            throw reporter.isCancelled ? FileOpsError.cancelled : error
        }
    }

    // MARK: - RAR

    static func unrar(_ url: URL, to dest: URL, password: String?, reporter: OperationReporter) throws {
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let context = Unmanaged.passRetained(RarContext(reporter))
        defer { context.release() }
        let callback: pledo_rar_progress_cb = { ctx, processed, total, name in
            guard let ctx else { return 1 }
            let c = Unmanaged<RarContext>.fromOpaque(ctx).takeUnretainedValue()
            if c.reporter.isCancelled { return 0 }
            let fileName = name.map { String(cString: $0) }
            c.reporter.report(total > 0 ? Double(processed) / Double(total) : nil, fileName)
            return 1
        }
        var code: Int32 = 0
        let result: Int32
        if let password, !password.isEmpty {
            result = pledo_rar_extract(url.path, dest.path, password, callback, context.toOpaque(), &code)
        } else {
            result = pledo_rar_extract(url.path, dest.path, nil, callback, context.toOpaque(), &code)
        }
        if result == PLEDO_RAR_OK { return }
        try? fm.removeItem(at: dest)
        switch result {
        case PLEDO_RAR_CANCELLED: throw FileOpsError.cancelled
        case PLEDO_RAR_NEED_PASSWORD: throw FileOpsError.needPassword(url)
        case PLEDO_RAR_BAD_PASSWORD: throw FileOpsError.badPassword(url)
        default: throw FileOpsError.rar(code)
        }
    }

    /// Zielordner zum Entpacken: Archivname ohne Endung (und ohne .partN).
    static func extractDestination(for archive: URL) -> URL {
        var name = archive.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) {
            name.removeSubrange(range)
        }
        if name.isEmpty { name = "Entpackt" }
        return uniqueURL(in: archive.deletingLastPathComponent(), name: name, directory: true)
    }
}
