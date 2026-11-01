import Foundation
import SwiftUI
import UIKit

struct ImportLogLine: Identifiable {
    enum Kind { case info, success, error, progress }
    let id = UUID()
    let kind: Kind
    let text: String
}

@MainActor
class GameLibrary: ObservableObject {
    @Published var games: [GameEntry] = []
    @Published var keysImported = false
    @Published var keySummary: String?
    @Published var sortOrder: SortOrder = .dateAdded
    @Published var importLog: [ImportLogLine] = []

    private let gamesKey = "blockmash_games"
    private var isScanningFolder = false
    private var failedFolderFiles: Set<String> = []

    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case dateAdded = "Date Added"
        case lastPlayed = "Last Played"
        case fileSize = "Size"
    }

    init() {
        load()
        AppFolders.ensureFolders()
        refreshKeysState()
    }

    var sortedGames: [GameEntry] {
        switch sortOrder {
        case .title:
            return games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded:
            return games.sorted { $0.dateAdded > $1.dateAdded }
        case .lastPlayed:
            return games.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .fileSize:
            return games.sorted { $0.fileSize > $1.fileSize }
        }
    }

    var totalSize: Int64 {
        games.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Activity log

    func log(_ kind: ImportLogLine.Kind, _ text: String) {
        importLog.append(ImportLogLine(kind: kind, text: text))
        if importLog.count > 200 {
            importLog.removeFirst(importLog.count - 200)
        }
    }

    func clearLog() {
        importLog.removeAll()
    }

    // MARK: - Games

    func addGame(_ game: GameEntry) {
        if let existing = games.firstIndex(where: { $0.titleId == game.titleId && !game.titleId.isEmpty }) {
            var merged = game
            merged.updates = games[existing].updates
            merged.dlc = games[existing].dlc
            merged.lastPlayed = games[existing].lastPlayed
            merged.playTime = games[existing].playTime
            games[existing] = merged
        } else {
            games.append(game)
        }
        save()
    }

    func importFile(url: URL) async throws -> GameEntry {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let result = try await GameScanner.shared.scan(url: url)
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let base = GameScanner.baseTitleId(result.titleId)
        let parentIndex = games.firstIndex { base != nil && GameScanner.baseTitleId($0.titleId) == base }

        switch result.contentType {
        case .update:
            if let idx = parentIndex {
                games[idx].updates.removeAll { $0.version == result.version }
                games[idx].updates.append(GameUpdate(version: result.version, filePath: url.path, fileSize: result.fileSize))
                save()
                return games[idx]
            }
        case .dlc:
            if let idx = parentIndex {
                games[idx].dlc.removeAll { $0.titleId == result.titleId }
                games[idx].dlc.append(GameDLC(name: result.title, titleId: result.titleId, filePath: url.path, fileSize: result.fileSize))
                save()
                return games[idx]
            }
        case .base:
            break
        }

        let game = GameEntry(
            title: result.title,
            titleId: result.titleId,
            version: result.version,
            fileType: result.fileType,
            fileSize: result.fileSize,
            filePath: url.path,
            bookmark: bookmark,
            ncaCount: result.ncaCount,
            hasProgramNCA: result.hasProgramNCA,
            hasControlNCA: result.hasControlNCA
        )
        addGame(game)
        return game
    }

    func importPickedGames(_ urls: [URL]) {
        log(.info, "Picked \(urls.count) file(s)")
        Task {
            for url in urls {
                await importGame(at: url)
            }
        }
    }

    func importOpened(_ url: URL) {
        if AppFolders.isGameFile(url) {
            importPickedGames([url])
        } else {
            importKeys(from: url)
        }
    }

    private func importGame(at url: URL) async {
        log(.progress, "Scanning \(url.lastPathComponent)…")
        do {
            _ = try await importFile(url: url)
            log(.success, "Imported \(url.lastPathComponent)")
        } catch {
            log(.error, "\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func pasteGames() {
        let matches = AppFolders.fileProviders(in: UIPasteboard.general.itemProviders)
        guard !matches.isEmpty else {
            log(.error, "Clipboard is empty. In Files, long-press a game → Copy, then tap Paste here.")
            return
        }
        for (provider, type) in matches {
            let name = provider.suggestedName ?? "file"
            log(.progress, "Copying \(name) into the app…")
            provider.loadFileRepresentation(forTypeIdentifier: type) { tempURL, error in
                // The temp file is deleted when this handler returns, so move it now.
                let result: Result<URL, Error>
                if let tempURL {
                    result = Result {
                        try AppFolders.adoptGameFile(at: tempURL, suggestedName: provider.suggestedName, typeIdentifier: type)
                    }
                } else {
                    result = .failure(error ?? ImportError.clipboardUnreadable)
                }
                Task { @MainActor in
                    switch result {
                    case .success(let dest):
                        await self.importGame(at: dest)
                    case .failure(let error):
                        self.log(.error, "\(name): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Imports games dropped into the app's Documents or Documents/Games folder via the Files app.
    func scanAppFolder(manual: Bool = false) async {
        guard !isScanningFolder else { return }
        isScanningFolder = true
        defer { isScanningFolder = false }

        if manual { failedFolderFiles.removeAll() }
        AppFolders.ensureFolders()
        adoptStrayKeys()
        refreshKeysState()

        let fm = FileManager.default
        var found: [URL] = []
        for dir in [AppFolders.documents, AppFolders.games] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
            found += items.filter(AppFolders.isGameFile)
        }

        let fresh = found.filter { !isKnown($0) && !failedFolderFiles.contains($0.lastPathComponent) }
        guard !fresh.isEmpty else {
            if manual { log(.info, "No new games in \(AppFolders.gamesFolderHint)") }
            return
        }

        log(.info, "Found \(fresh.count) new file(s) in the Games folder")
        for url in fresh {
            log(.progress, "Scanning \(url.lastPathComponent)…")
            do {
                _ = try await importFile(url: url)
                log(.success, "Imported \(url.lastPathComponent)")
            } catch {
                failedFolderFiles.insert(url.lastPathComponent)
                log(.error, "\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func isKnown(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
        let matches: (String, Int64) -> Bool = { path, fileSize in
            (path as NSString).lastPathComponent == name && fileSize == size
        }
        for game in games {
            if matches(game.filePath, game.fileSize) { return true }
            if game.updates.contains(where: { matches($0.filePath, $0.fileSize) }) { return true }
            if game.dlc.contains(where: { matches($0.filePath, $0.fileSize) }) { return true }
        }
        return false
    }

    func removeGame(_ game: GameEntry) {
        games.removeAll { $0.id == game.id }
        save()
    }

    func removeAllGames() {
        games = []
        save()
    }

    func markPlayed(_ game: GameEntry) {
        if let idx = games.firstIndex(where: { $0.id == game.id }) {
            games[idx].lastPlayed = Date()
            save()
        }
    }

    // MARK: - Keys

    func refreshKeysState() {
        let count = KeyStore.loadFromDocuments()?.keyCount ?? 0
        let imported = count > 0
        if keysImported != imported { keysImported = imported }
        let summary: String? = imported ? "\(count) keys" : nil
        if keySummary != summary { keySummary = summary }
    }

    func importKeys(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        log(.info, "Picked \(url.lastPathComponent)")
        do {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= 1_000_000 else { throw ImportError.notKeys }
            saveKeys(try Data(contentsOf: url))
        } catch {
            log(.error, error.localizedDescription)
        }
    }

    func pasteKeys() {
        guard let match = AppFolders.fileProviders(in: UIPasteboard.general.itemProviders).first else {
            log(.error, "Clipboard is empty. In Files, long-press prod.keys → Copy, then tap Paste here.")
            return
        }
        let (provider, type) = match
        log(.progress, "Reading clipboard…")
        provider.loadFileRepresentation(forTypeIdentifier: type) { tempURL, error in
            let result: Result<Data, Error>
            if let tempURL {
                let size = (try? tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 1_000_000 {
                    result = .failure(ImportError.notKeys)
                } else {
                    result = Result { try Data(contentsOf: tempURL) }
                }
            } else {
                result = .failure(error ?? ImportError.clipboardUnreadable)
            }
            Task { @MainActor in
                switch result {
                case .success(let data): self.saveKeys(data)
                case .failure(let error): self.log(.error, error.localizedDescription)
                }
            }
        }
    }

    private func saveKeys(_ data: Data) {
        let store = KeyStore.parse(content: String(decoding: data, as: UTF8.self))
        guard store.keyCount > 0 else {
            log(.error, ImportError.notKeys.localizedDescription)
            return
        }
        do {
            try data.write(to: AppFolders.keysFile, options: .atomic)
            refreshKeysState()
            log(.success, "prod.keys loaded — \(store.keyCount) keys")
        } catch {
            log(.error, "Couldn't save prod.keys: \(error.localizedDescription)")
        }
    }

    /// prod.keys dropped into the Games folder is moved next to it, where the app looks for it.
    private func adoptStrayKeys() {
        let fm = FileManager.default
        let stray = AppFolders.games.appendingPathComponent("prod.keys")
        guard fm.fileExists(atPath: stray.path) else { return }
        try? fm.removeItem(at: AppFolders.keysFile)
        if (try? fm.moveItem(at: stray, to: AppFolders.keysFile)) != nil {
            log(.success, "Found prod.keys in the Games folder")
        }
    }

    func clearKeys() {
        try? FileManager.default.removeItem(at: AppFolders.keysFile)
        refreshKeysState()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: gamesKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: gamesKey),
              let decoded = try? JSONDecoder().decode([GameEntry].self, from: data) else { return }
        games = decoded
    }
}
