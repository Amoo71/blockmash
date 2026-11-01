import SwiftUI

struct GameDetailView: View {
    let game: GameEntry

    var body: some View {
        List {
            headerSection
            Section {
                Label("This app has no emulation core, so games can't run here.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            detailsSection
            if !game.updates.isEmpty { updatesSection }
            if !game.dlc.isEmpty { dlcSection }
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        Section {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorForGame(game))
                    .frame(height: 120)
                Text(String(game.title.prefix(2)).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private var detailsSection: some View {
        Section {
            LabeledContent("Format", value: game.fileType.rawValue)
            LabeledContent("Size", value: game.formattedSize)
            if !game.titleId.isEmpty {
                LabeledContent("Title ID") {
                    Text(game.titleId).font(.caption.monospaced())
                }
            }
            LabeledContent("Version", value: game.version)
            LabeledContent("NCA files", value: "\(game.ncaCount)")
            LabeledContent("Added", value: game.dateAdded.formatted(date: .abbreviated, time: .omitted))
            if !game.fileExists {
                Label("File not found — re-import it", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var updatesSection: some View {
        Section("Updates") {
            ForEach(game.updates) { update in
                HStack {
                    Label("v\(update.version)", systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: update.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dlcSection: some View {
        Section("DLC") {
            ForEach(game.dlc) { dlc in
                HStack {
                    Label(dlc.name, systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: dlc.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func colorForGame(_ game: GameEntry) -> Color {
        let colors: [Color] = [.purple, .blue, .indigo, .pink, .orange, .teal, .mint, .cyan]
        let hash = abs(game.title.hashValue)
        return colors[hash % colors.count]
    }
}
