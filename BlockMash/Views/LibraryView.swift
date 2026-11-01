import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var searchText = ""
    @State private var showingSortPicker = false

    var filteredGames: [GameEntry] {
        let sorted = library.sortedGames
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty {
                    emptyState
                } else {
                    gameList
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $library.sortOrder) {
                            ForEach(GameLibrary.SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    statsLabel
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Games Yet")
                .font(.title2.bold())
            Text("Import games from the Import tab\nto build your library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var gameList: some View {
        List {
            ForEach(filteredGames) { game in
                NavigationLink(value: game) {
                    GameRowView(game: game)
                }
            }
            .onDelete { offsets in
                let gamesToDelete = offsets.map { filteredGames[$0] }
                for game in gamesToDelete {
                    library.removeGame(game)
                }
            }
        }
        .navigationDestination(for: GameEntry.self) { game in
            GameDetailView(game: game)
        }
    }

    private var statsLabel: some View {
        Text("\(library.games.count) games")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct GameRowView: View {
    let game: GameEntry

    var body: some View {
        let missing = !game.fileExists
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorForGame(game))
                    .frame(width: 56, height: 56)
                Text(String(game.title.prefix(2)).uppercased())
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(game.title)
                        .font(.body.bold())
                        .lineLimit(1)
                    if missing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    Label(game.fileType.rawValue, systemImage: game.fileType.icon)
                    Text(game.formattedSize)
                    if missing {
                        Text("File missing")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !game.updates.isEmpty || !game.dlc.isEmpty {
                VStack(spacing: 2) {
                    if !game.updates.isEmpty {
                        Label("\(game.updates.count)", systemImage: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if !game.dlc.isEmpty {
                        Label("\(game.dlc.count)", systemImage: "plus.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func colorForGame(_ game: GameEntry) -> Color {
        let colors: [Color] = [.purple, .blue, .indigo, .pink, .orange, .teal]
        let hash = abs(game.title.hashValue)
        return colors[hash % colors.count]
    }
}
