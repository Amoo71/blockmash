import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var library: GameLibrary
    @StateObject private var launcher = GameLauncher()
    @State private var showAdvanced = false
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
            advancedSection
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: isRunning) {
            GameRunningView(game: game, launcher: launcher) {
                launcher.stop()
            }
        }
    }

    private var isRunning: Binding<Bool> {
        Binding(
            get: { launcher.state == .running },
            set: { if !$0 { launcher.stop() } }
        )
    }

    private var headerSection: some View {
        Section {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorForGame(game))
                    .frame(height: 120)
                VStack(spacing: 4) {
                    Text(String(game.title.prefix(2)).uppercased())
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private var launchSection: some View {
        Section {
            switch launcher.state {
            case .idle:
                Button {
                    Task { await launcher.prepareLaunch(game: game) }
                } label: {
                    Label("Launch", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!game.fileExists)

            case .scanning, .verifyingKeys, .loadingNCAs:
                HStack {
                    ProgressView().padding(.trailing, 6)
                    Text(stateDescription).foregroundStyle(.secondary)
                }

            case .compilingShaders(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compiling shaders").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: progress).tint(.purple)
                }

            case .ready:
                Button {
                    launcher.launch()
                    library.markPlayed(game)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .running:
                HStack {
                    Label("Running — \(Int(launcher.fps)) FPS", systemImage: "play.fill")
                        .foregroundStyle(.green)
                    Spacer()
                }

            case .error(let msg):
                VStack(alignment: .leading, spacing: 6) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Button("Retry") {
                        Task { await launcher.prepareLaunch(game: game) }
                    }
                    .font(.caption)
                }
            }
        }
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
            if let lastPlayed = game.lastPlayed {
                LabeledContent("Last played", value: lastPlayed.formatted(.relative(presentation: .named)))
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

    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                LabeledContent("NCA count", value: "\(game.ncaCount)")
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
                LabeledContent("Added", value: game.dateAdded.formatted(date: .abbreviated, time: .omitted))
            } label: {
                Label("Advanced", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateDescription: String {
        switch launcher.state {
        case .scanning: return "Scanning"
        case .verifyingKeys: return "Verifying keys"
        case .loadingNCAs: return "Loading NCAs"
        default: return ""
        }
    }

    private func colorForGame(_ game: GameEntry) -> Color {
        let colors: [Color] = [.purple, .blue, .indigo, .pink, .orange, .teal, .mint, .cyan]
        let hash = abs(game.title.hashValue)
        return colors[hash % colors.count]
    }
}
