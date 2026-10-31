import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var showingFilePicker = false
    @State private var showingKeysPicker = false
    @State private var importedFileName: String?
    @State private var showingAlert = false
    @State private var alertMessage = ""

    private let gameType = UTType("com.blockmash.game-rom") ?? .data

    var body: some View {
        NavigationStack {
            List {
                Section {
                    keysStatusRow
                    Button {
                        showingKeysPicker = true
                    } label: {
                        Label("Import prod.keys", systemImage: "key.fill")
                    }
                } header: {
                    Text("Encryption Keys")
                } footer: {
                    Text("Required to read encrypted game files. Place your prod.keys file accessible via the Files app.")
                }

                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Import Game File", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text("Add Games")
                } footer: {
                    Text("Supported: NSP, NSZ, XCI, XCZ. Files stay in their original location.")
                }

                Section("Supported Formats") {
                    ForEach(GameFileType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundStyle(.purple)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(type.rawValue)
                                    .font(.body.bold())
                                Text(descriptionFor(type))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Storage") {
                    LabeledContent("Games in Library", value: "\(library.games.count)")
                    LabeledContent("Total Size", value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))
                }
            }
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [gameType, .data],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            .fileImporter(
                isPresented: $showingKeysPicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleKeysImport(result)
            }
            .alert("Import", isPresented: $showingAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var keysStatusRow: some View {
        HStack {
            Image(systemName: library.keysImported ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(library.keysImported ? .green : .red)
            Text(library.keysImported ? "prod.keys loaded" : "No keys imported")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var imported = 0
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                let ext = url.pathExtension.lowercased()
                guard let fileType = GameFileType.from(extension: ext) else { continue }

                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "[", with: "(")
                    .replacingOccurrences(of: "]", with: ")")

                let game = GameEntry(
                    title: name,
                    fileType: fileType,
                    fileSize: size,
                    filePath: url.path
                )
                library.addGame(game)
                imported += 1
            }
            alertMessage = imported > 0 ? "\(imported) game(s) imported." : "No supported files found."
            showingAlert = true

        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func handleKeysImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Could not access the selected file."
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("prod.keys")
            try? FileManager.default.removeItem(at: dest)

            do {
                try FileManager.default.copyItem(at: url, to: dest)
                library.setKeysImported(true)
                alertMessage = "prod.keys imported successfully."
            } catch {
                alertMessage = "Failed to import keys: \(error.localizedDescription)"
            }
            showingAlert = true

        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func descriptionFor(_ type: GameFileType) -> String {
        switch type {
        case .nsp: return "Nintendo Submission Package"
        case .nsz: return "Compressed NSP"
        case .xci: return "NX Game Card Image"
        case .xcz: return "Compressed XCI"
        }
    }
}
