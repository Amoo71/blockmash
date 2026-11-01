import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var activePicker: PickerKind?

    enum PickerKind: Identifiable {
        case games, keys
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            List {
                if AppFolders.isLiveContainer { pickerTip }
                keysSection
                gamesSection
                if !library.importLog.isEmpty { activitySection }
            }
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.scanAppFolder(manual: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $activePicker) { kind in
                DocumentPicker(
                    types: kind == .games ? [UTType("com.blockmash.game-rom") ?? .data, .data] : [.data],
                    allowsMultiple: kind == .games,
                    onPick: { urls in
                        activePicker = nil
                        switch kind {
                        case .games:
                            library.importPickedGames(urls)
                        case .keys:
                            if let url = urls.first { library.importKeys(from: url) }
                        }
                    },
                    onCancel: { activePicker = nil }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var pickerTip: some View {
        Section {
            Label {
                Text("If **Open** in the file picker does nothing: in LiveContainer long-press BlockMash → Settings → turn on **Fix File Picker**. Paste and the Games folder below always work.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var keysSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: library.keysImported ? "checkmark.shield.fill" : "xmark.shield")
                    .font(.title2)
                    .foregroundStyle(library.keysImported ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.keysImported ? "prod.keys loaded" : "prod.keys missing")
                        .font(.body.bold())
                    if let summary = library.keySummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                activePicker = .keys
            } label: {
                Label("Choose File…", systemImage: "folder")
            }
            Button {
                library.pasteKeys()
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("Keys")
        } footer: {
            Text("To paste: in the Files app long-press prod.keys → Copy, then tap Paste here.")
        }
    }

    private var gamesSection: some View {
        Section {
            Button {
                activePicker = .games
            } label: {
                Label("Choose Files…", systemImage: "folder")
            }
            Button {
                library.pasteGames()
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
            Button {
                openGamesFolder()
            } label: {
                Label("Open Games Folder in Files", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("Games")
        } footer: {
            Text("Best for big files: in the Files app move your games (and prod.keys) into \(AppFolders.gamesFolderHint). They're added automatically when you come back.")
        }
    }

    private var activitySection: some View {
        Section {
            ForEach(library.importLog.reversed()) { line in
                HStack(alignment: .top, spacing: 10) {
                    icon(for: line.kind)
                        .frame(width: 20)
                    Text(line.text)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            HStack {
                Text("Activity")
                Spacer()
                Button("Clear") { library.clearLog() }
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func icon(for kind: ImportLogLine.Kind) -> some View {
        switch kind {
        case .info: Image(systemName: "info.circle").foregroundStyle(.blue)
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .progress: Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        }
    }

    private func openGamesFolder() {
        AppFolders.ensureFolders()
        guard let url = AppFolders.gamesFolderFilesURL else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    library.log(.info, "Couldn't open Files automatically. Go to \(AppFolders.gamesFolderHint)")
                }
            }
        }
    }
}
