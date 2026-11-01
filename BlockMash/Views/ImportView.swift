import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var showingFilePicker = false
    @State private var showingKeysPicker = false
    @State private var isScanning = false
    @State private var scanProgress: String = ""
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private let gameType = UTType("com.blockmash.game-rom") ?? .data

    var body: some View {
        NavigationStack {
            List {
                keysSection
                importSection
                if isScanning { scanningSection }
                formatsSection
                storageSection
            }
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [gameType, .data],
                allowsMultipleSelection: true
            ) { handleFileImport($0) }
            .fileImporter(
                isPresented: $showingKeysPicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { handleKeysImport($0) }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
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
                showingKeysPicker = true
            } label: {
                Label("Import prod.keys", systemImage: "key.fill")
            }
        } header: {
            Text("Encryption Keys")
        } footer: {
            Text("Required to decrypt and read game files. Your keys stay on-device.")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showingFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading) {
                        Text("Import Game Files")
                            .font(.body.bold())
                        Text("NSP, NSZ, XCI, XCZ from Files app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Add Games")
        } footer: {
            Text("Files are scanned to extract NCA structure and metadata. Originals stay in place.")
        }
    }

    private var scanningSection: some View {
        Section {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text(scanProgress)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formatsSection: some View {
        Section("Supported Formats") {
            ForEach(GameFileType.allCases, id: \.self) { type in
                HStack {
                    Image(systemName: type.icon)
                        .foregroundStyle(.purple)
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text(type.rawValue).font(.body.bold())
                        Text(descriptionFor(type))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var storageSection: some View {
        Section("Library Stats") {
            LabeledContent("Games", value: "\(library.games.count)")
            LabeledContent("Updates", value: "\(library.games.flatMap(\.updates).count)")
            LabeledContent("DLC", value: "\(library.games.flatMap(\.dlc).count)")
            LabeledContent("Total Size", value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            isScanning = true
            Task {
                var imported = 0
                var errors: [String] = []
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    scanProgress = "Scanning \(url.lastPathComponent)..."
                    do {
                        let _ = try await library.importFile(url: url)
                        imported += 1
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                isScanning = false
                alertTitle = "Import Complete"
                if errors.isEmpty {
                    alertMessage = "\(imported) file(s) imported and scanned."
                } else {
                    alertMessage = "\(imported) imported. \(errors.count) failed:\n\(errors.joined(separator: "\n"))"
                }
                showingAlert = true
            }
        case .failure(let error):
            alertTitle = "Import Failed"
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func handleKeysImport(_ result: Result<[URL], Error>) {
        var title = ""
        var message = ""

        switch result {
        case .success(let urls):
            if let url = urls.first {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

                let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("prod.keys")
                try? FileManager.default.removeItem(at: dest)

                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    let keyStore = try KeyStore.load(from: dest)
                    library.setKeysImported(true)
                    title = "Keys Imported"
                    message = "\(keyStore.keyCount) keys loaded (\(keyStore.titleKeyCount) title keys, \(keyStore.keyAreaKeyCount) key area keys)."
                } catch {
                    title = "Error"
                    message = "Failed: \(error.localizedDescription)\nFile: \(url.lastPathComponent)\nAccess: \(hasAccess)"
                }
            } else {
                title = "Error"
                message = "No file was selected."
            }
        case .failure(let error):
            title = "Error"
            message = error.localizedDescription
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.alertTitle = title
            self.alertMessage = message
            self.showingAlert = true
        }
    }

    private func descriptionFor(_ type: GameFileType) -> String {
        switch type {
        case .nsp: return "Nintendo Submission Package (eShop)"
        case .nsz: return "Compressed NSP (smaller download)"
        case .xci: return "NX Game Card Image (cartridge dump)"
        case .xcz: return "Compressed XCI"
        }
    }
}
