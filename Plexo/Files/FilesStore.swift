import Foundation
import SwiftUI

struct LinkedFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var bookmark: Data
}

struct FileOperationState {
    var title: String
    var detail: String = ""
    var progress: Double?
}

struct PasswordRequest: Identifiable {
    let id = UUID()
    let archive: URL
    let wrongPassword: Bool
}

@MainActor
final class FilesStore: ObservableObject {
    static let shared = FilesStore()

    @Published private(set) var linkedFolders: [LinkedFolder] = []
    @Published private(set) var operation: FileOperationState?
    @Published var lastError: String?
    @Published var passwordRequest: PasswordRequest?
    @Published private(set) var refreshToken = UUID()

    private var resolved: [UUID: URL] = [:]
    private var reporter: OperationReporter?
    private let defaultsKey = "linkedFolders"

    var documentsURL: URL { AppPaths.documents }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let folders = try? JSONDecoder().decode([LinkedFolder].self, from: data) {
            linkedFolders = folders
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(linkedFolders) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func refresh() { refreshToken = UUID() }

    // MARK: - Verknüpfte Ordner (Zugriff auf Dateien des iPhones)

    func url(for folder: LinkedFolder) -> URL? {
        if let url = resolved[folder.id] { return url }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        resolved[folder.id] = url
        return url
    }

    func linkFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            let folder = LinkedFolder(name: url.lastPathComponent, bookmark: data)
            linkedFolders.append(folder)
            resolved[folder.id] = url
            saveFolders()
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            lastError = "Ordner konnte nicht verknüpft werden: \(error.localizedDescription)"
        }
    }

    func removeLinkedFolders(at offsets: IndexSet) {
        for i in offsets {
            let f = linkedFolders[i]
            resolved[f.id]?.stopAccessingSecurityScopedResource()
            resolved[f.id] = nil
        }
        linkedFolders.remove(atOffsets: offsets)
        saveFolders()
    }

    // MARK: - Schnelle Operationen

    func createFolder(in dir: URL, name: String) {
        do {
            _ = try FileOps.createFolder(in: dir, name: name)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rename(_ url: URL, to name: String) {
        do {
            _ = try FileOps.rename(url, to: name)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Hintergrund-Operationen

    var isBusy: Bool { operation != nil }

    func cancelOperation() {
        reporter?.cancel()
    }

    private func perform(_ title: String, _ work: @escaping (OperationReporter) throws -> Void) {
        guard operation == nil else {
            lastError = "Es läuft bereits ein Vorgang. Bitte warten oder abbrechen."
            return
        }
        let r = OperationReporter()
        r.onUpdate = { [weak self] progress, detail in
            Task { @MainActor in
                guard let self, self.operation != nil else { return }
                self.operation?.progress = progress
                if let detail { self.operation?.detail = detail }
            }
        }
        reporter = r
        operation = FileOperationState(title: title)
        Task.detached(priority: .userInitiated) {
            var failure: Error?
            do {
                try work(r)
            } catch {
                failure = error
            }
            let err = failure
            await MainActor.run { self.finish(err) }
        }
    }

    private func finish(_ error: Error?) {
        operation = nil
        reporter = nil
        refresh()
        guard let error else { return }
        if let e = error as? FileOpsError {
            switch e {
            case .cancelled:
                return
            case .needPassword(let url):
                passwordRequest = PasswordRequest(archive: url, wrongPassword: false)
                return
            case .badPassword(let url):
                passwordRequest = PasswordRequest(archive: url, wrongPassword: true)
                return
            default:
                break
            }
        }
        lastError = error.localizedDescription
    }

    func delete(_ urls: [URL]) {
        perform("Löschen") { r in try FileOps.delete(urls, reporter: r) }
    }

    func transfer(_ urls: [URL], to dir: URL, copy: Bool) {
        perform(copy ? "Kopieren" : "Verschieben") { r in
            try FileOps.transfer(urls, to: dir, copy: copy, reporter: r)
        }
    }

    func importFiles(_ urls: [URL], into dir: URL) {
        perform("Importieren") { r in try FileOps.importFiles(urls, into: dir, reporter: r) }
    }

    func compress(_ urls: [URL], in dir: URL) {
        guard let first = urls.first else { return }
        let baseName = urls.count == 1
            ? (FileOps.isDirectory(first) ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent)
            : "Archiv"
        let dest = FileOps.uniqueURL(in: dir, name: baseName + ".zip")
        perform("ZIP erstellen") { r in try FileOps.zip(urls, to: dest, reporter: r) }
    }

    func extract(_ archive: URL, password: String? = nil) {
        guard let kind = ArchiveKind(url: archive) else {
            lastError = "Dieses Format wird nicht unterstützt (ZIP und RAR sind möglich)."
            return
        }
        let dest = FileOps.extractDestination(for: archive)
        perform("Entpacken") { r in
            switch kind {
            case .zip: try FileOps.unzip(archive, to: dest, reporter: r)
            case .rar: try FileOps.unrar(archive, to: dest, password: password, reporter: r)
            }
        }
    }
}
