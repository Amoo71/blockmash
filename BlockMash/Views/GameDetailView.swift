import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: GameLibrary
    @StateObject private var launcher = GameLauncher()
    let game: GameEntry

    init(game: GameEntry) {
        self.game = game
    }

    var body: some View {
        List {
            headerSection
            launchSection
            detailsSection
            if !game.updates.isEmpty { updatesSection }
            if !game.dlc.isEmpty { dlcSection }
            ncaSection
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorForGame(game))
                        .frame(height: 140)
                    VStack(spacing: 6) {
                        Text(String(game.title.prefix(2)).uppercased())
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                        Text(game.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var launchSection: some View {
        Section {
            switch launcher.state {
            case .idle:
                Button {
                    Task { await launcher.prepareLaunch(game: game) }
                } label: {
                    Label("Prepare Launch", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!game.fileExists)

            case .scanning, .verifyingKeys, .loadingNCAs:
                HStack {
                    ProgressView()
                    Text(stateDescription)
                        .foregroundStyle(.secondary)
                }

            case .compilingShaders(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compiling shaders...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .tint(.purple)
                }

            case .ready:
                Button {
                    launcher.launch()
                    library.markPlayed(game)
                } label: {
                    Label("Launch Game", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .running:
                VStack(spacing: 8) {
                    HStack {
                        Label("Running", systemImage: "play.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("\(Int(launcher.fps)) FPS")
                            .font(.caption.monospaced())
                    }
                    Button(role: .destructive) {
                        launcher.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }

            case .error(let msg):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await launcher.prepareLaunch(game: game) }
                    }
                }
            }
        } footer: {
            if !game.fileExists {
                Text("Game file not found. The original file may have been moved or deleted.")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("File Type", value: game.fileType.rawValue)
            LabeledContent("Size", value: game.formattedSize)
            if !game.titleId.isEmpty {
                LabeledContent("Title ID") {
                    Text(game.titleId).font(.caption.monospaced())
                }
            }
            LabeledContent("Version", value: game.version)
            LabeledContent("Added", value: game.dateAdded.formatted(date: .abbreviated, time: .shortened))
            if let lastPlayed = game.lastPlayed {
                LabeledContent("Last Played", value: lastPlayed.formatted(date: .abbreviated, time: .shortened))
            }
            if game.playTime > 0 {
                LabeledContent("Play Time", value: game.formattedPlayTime)
            }
        }
    }

    private var updatesSection: some View {
        Section("Updates (\(game.updates.count))") {
            ForEach(game.updates) { update in
                HStack {
                    Label("v\(update.version)", systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: update.fileSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    private var dlcSection: some View {
        Section("DLC (\(game.dlc.count))") {
            ForEach(game.dlc) { dlc in
                HStack {
                    Label(dlc.name, systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: dlc.fileSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    private var ncaSection: some View {
        Section("NCA Info") {
            LabeledContent("NCA Count", value: "\(game.ncaCount)")
            HStack {
                Text("Program NCA")
                Spacer()
                Image(systemName: game.hasProgramNCA ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(game.hasProgramNCA ? .green : .red)
            }
            HStack {
                Text("Control NCA")
                Spacer()
                Image(systemName: game.hasControlNCA ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(game.hasControlNCA ? .green : .red)
            }
        }
    }

    private var stateDescription: String {
        switch launcher.state {
        case .scanning: return "Scanning game file..."
        case .verifyingKeys: return "Verifying encryption keys..."
        case .loadingNCAs: return "Loading NCAs..."
        default: return ""
        }
    }

    private func colorForGame(_ game: GameEntry) -> Color {
        let colors: [Color] = [.purple, .blue, .indigo, .pink, .orange, .teal]
        let hash = abs(game.title.hashValue)
        return colors[hash % colors.count]
    }
}
