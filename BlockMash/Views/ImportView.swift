import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var activePicker: PickerKind?
    @State private var statusLines: [StatusLine] = []
    @State private var isWorking = false

    private let gameType = UTType("com.blockmash.game-rom") ?? .data

    enum PickerKind: Identifiable {
        case games, keys
        var id: Self { self }
    }

    struct StatusLine: Identifiable {
        let id = UUID()
        let kind: Kind
        let text: String
        enum Kind { case info, success, error, progress }
    }

    var body: some View {
        NavigationStack {
            List {
                keysSection
                importSection
                if !statusLines.isEmpty { statusSection }
            }
            .navigationTitle("Import")
            .sheet(item: $activePicker) { kind in
                DocumentPicker(
                    types: types(for: kind),
                    allowsMultiple: kind == .games,
                    onPick: { urls in
                        activePicker = nil
                        switch kind {
                        case .games: processGames(urls)
                        case .keys: processKeys(urls)
                        }
                    },
                    onCancel: {
                        activePicker = nil
                        log(.info, "Picker cancelled")
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func types(for kind: PickerKind) -> [UTType] {
        switch kind {
        case .games: return [gameType, .data]
        case .keys: return [.data]
        }
    }

    private var statusSection: some View {
        Section {
            ForEach(statusLines.reversed()) { line in
                HStack(alignment: .top, spacing: 10) {
                    icon(for: line.kind).frame(width: 20)
                    Text(line.text)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !statusLines.isEmpty && !isWorking {
                Button("Clear log") {
                    withAnimation { statusLines = [] }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Status")
                Spacer()
                if isWorking { ProgressView().scaleEffect(0.8) }
            }
        }
    }

    @ViewBuilder
    private func icon(for kind: StatusLine.Kind) -> some View {
        switch kind {
        case .info: Image(systemName: "info.circle").foregroundStyle(.blue)
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .progress: ProgressView().scaleEffect(0.6)
        }
    }

    private var keysSection: some View {
        Section {
            HStack {
                Image(systemName: library.keysImported ? "checkmark.shield.fill" : "xmark.shield")
                    .foregroundStyle(library.keysImported ? .green : .red)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.keysImported ? "prod.keys loaded" : "Keys required")
                        .font(.body.bold())
                    if let keyStore = KeyStore.loadFromDocuments() {
                        Text("\(keyStore.keyCount) keys (\(keyStore.titleKeyCount) title, \(keyStore.keyAreaKeyCount) area)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Button {
                activePicker = .keys
            } label: {
                Label("Import prod.keys", systemImage: "key.fill")
            }
            .disabled(isWorking)
        } header: {
            Text("Encryption Keys")
        } footer: {
            Text("Required to decrypt game files. Your keys stay on-device.")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                activePicker = .games
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading) {
                        Text("Import Game Files")
                            .font(.body.bold())
                        Text("NSP, NSZ, XCI, XCZ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isWorking)
        } header: {
            Text("Add Games")
        } footer: {
            Text("Files are scanned for metadata. Originals stay in place.")
        }
    }

    private func log(_ kind: StatusLine.Kind, _ text: String) {
        statusLines.append(StatusLine(kind: kind, text: text))
    }

    private func processGames(_ urls: [URL]) {
        log(.info, "Picked \(urls.count) file(s)")
        isWorking = true
        Task { @MainActor in
            var imported = 0
            for url in urls {
                log(.progress, "Scanning \(url.lastPathComponent)…")
                do {
                    let _ = try await library.importFile(url: url)
                    imported += 1
                    log(.success, "Imported \(url.lastPathComponent)")
                } catch {
                    log(.error, "\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            log(.success, "Done — \(imported)/\(urls.count) imported")
            isWorking = false
        }
    }

    private func processKeys(_ urls: [URL]) {
        guard let url = urls.first else {
            log(.error, "No file was selected")
            return
        }
        log(.info, "Picked keys: \(url.lastPathComponent)")
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }

            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            log(.progress, "Access: \(hasAccess)")

            let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("prod.keys")
            try? FileManager.default.removeItem(at: dest)

            do {
                let data = try Data(contentsOf: url)
                try data.write(to: dest)
                log(.success, "Copied \(data.count) bytes to Documents/prod.keys")

                let keyStore = try KeyStore.load(from: dest)
                library.setKeysImported(true)
                log(.success, "Loaded \(keyStore.keyCount) keys (\(keyStore.titleKeyCount) title, \(keyStore.keyAreaKeyCount) area)")
            } catch {
                log(.error, "Failed: \(error.localizedDescription)")
            }
        }
    }
}
