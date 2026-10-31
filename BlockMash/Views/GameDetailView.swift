import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: GameLibrary
    let game: GameEntry

    var body: some View {
        List {
            Section {
                headerCard
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Details") {
                LabeledContent("File Type", value: game.fileType.rawValue)
                LabeledContent("Size", value: game.formattedSize)
                if !game.titleId.isEmpty {
                    LabeledContent("Title ID", value: game.titleId)
                }
                LabeledContent("Version", value: game.version)
                LabeledContent("Added", value: game.dateAdded.formatted(date: .abbreviated, time: .shortened))
                if let lastPlayed = game.lastPlayed {
                    LabeledContent("Last Played", value: lastPlayed.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if !game.updates.isEmpty {
                Section("Updates (\(game.updates.count))") {
                    ForEach(game.updates) { update in
                        HStack {
                            Label("v\(update.version)", systemImage: "arrow.up.circle")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: update.fileSize, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !game.dlc.isEmpty {
                Section("DLC (\(game.dlc.count))") {
                    ForEach(game.dlc) { dlc in
                        HStack {
                            Label(dlc.name, systemImage: "plus.circle")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: dlc.fileSize, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button {
                    library.markPlayed(game)
                } label: {
                    Label("Launch Game", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(true)
            } header: {
                Text("")
            } footer: {
                Text("Game launching requires the BlockMash engine. This feature is under development.")
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorForGame(game))
                    .frame(height: 160)
                VStack(spacing: 8) {
                    Text(String(game.title.prefix(2)).uppercased())
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                    Text(game.title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private func colorForGame(_ game: GameEntry) -> Color {
        let colors: [Color] = [.purple, .blue, .indigo, .pink, .orange, .teal]
        let hash = abs(game.title.hashValue)
        return colors[hash % colors.count]
    }
}
