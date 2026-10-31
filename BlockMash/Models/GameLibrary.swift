import Foundation
import SwiftUI

@MainActor
class GameLibrary: ObservableObject {
    @Published var games: [GameEntry] = []
    @Published var keysImported = false
    @Published var sortOrder: SortOrder = .dateAdded

    private let gamesKey = "blockmash_games"
    private let keysKey = "blockmash_keys_imported"

    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case dateAdded = "Date Added"
        case lastPlayed = "Last Played"
        case fileSize = "Size"
    }

    init() {
        load()
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

    func addGame(_ game: GameEntry) {
        if let existing = games.firstIndex(where: { $0.titleId == game.titleId && !game.titleId.isEmpty }) {
            games[existing] = game
        } else {
            games.append(game)
        }
        save()
    }

    func importFile(url: URL) async throws -> GameEntry {
        let result = try await GameScanner.shared.scan(url: url)

        switch result.contentType {
        case .update:
            if let idx = games.firstIndex(where: { $0.titleId.prefix(13) == result.titleId.prefix(13) }) {
                let update = GameUpdate(
                    version: result.version,
                    filePath: url.path,
                    fileSize: result.fileSize
                )
                games[idx].updates.append(update)
                save()
                return games[idx]
            }
        case .dlc:
            if let idx = games.firstIndex(where: { $0.titleId.prefix(13) == result.titleId.prefix(13) }) {
                let dlc = GameDLC(
                    name: result.title,
                    titleId: result.titleId,
                    filePath: url.path,
                    fileSize: result.fileSize
                )
                games[idx].dlc.append(dlc)
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
            ncaCount: result.ncaCount,
            hasProgramNCA: result.hasProgramNCA,
            hasControlNCA: result.hasControlNCA
        )
        addGame(game)
        return game
    }

    func removeGame(_ game: GameEntry) {
        games.removeAll { $0.id == game.id }
        save()
    }

    func markPlayed(_ game: GameEntry) {
        if let idx = games.firstIndex(where: { $0.id == game.id }) {
            games[idx].lastPlayed = Date()
            save()
        }
    }

    func setKeysImported(_ imported: Bool) {
        keysImported = imported
        UserDefaults.standard.set(imported, forKey: keysKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: gamesKey)
        }
    }

    private func load() {
        keysImported = UserDefaults.standard.bool(forKey: keysKey)
        guard let data = UserDefaults.standard.data(forKey: gamesKey),
              let decoded = try? JSONDecoder().decode([GameEntry].self, from: data) else { return }
        games = decoded
    }
}
