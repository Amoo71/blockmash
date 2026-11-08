import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct FolderLocation: Hashable {
    let url: URL
    let title: String
}

struct TransferRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    let copy: Bool
}

// MARK: - Startseite des Dateien-Tabs

struct FilesView: View {
    @EnvironmentObject private var files: FilesStore
    @State private var showFolderImporter = false
    @State private var password = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Auf diesem Gerät") {
                    NavigationLink(value: FolderLocation(url: files.documentsURL, title: "Plexo")) {
                        Label("Plexo-Ordner", systemImage: "iphone")
                    }
                }
                Section {
                    ForEach(files.linkedFolders) { folder in
                        if let url = files.url(for: folder) {
                            NavigationLink(value: FolderLocation(url: url, title: folder.name)) {
                                Label(folder.name, systemImage: "folder.fill.badge.person.crop")
                            }
                        } else {
                            Label("\(folder.name) (nicht verfügbar)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { files.removeLinkedFolders(at: $0) }
                    Button {
                        showFolderImporter = true
                    } label: {
                        Label("Ordner vom iPhone verknüpfen…", systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("Verknüpfte Ordner")
                } footer: {
                    Text("Wähle einen beliebigen Ordner aus der Dateien-App, z. B. „Auf meinem iPhone“ › Downloads, iCloud Drive oder einen USB-Stick. Plexo kann dort dann Dateien entpacken, verschieben, kopieren und löschen. Zum Entfernen nach links wischen.")
                }
            }
            .navigationTitle("Dateien")
            .navigationDestination(for: FolderLocation.self) { FolderView(location: $0) }
            .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): files.linkFolder(url)
                case .failure(let error): files.lastError = error.localizedDescription
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let op = files.operation {
                OperationBanner(state: op) { files.cancelOperation() }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .alert("Fehler", isPresented: Binding(get: { files.lastError != nil },
                                              set: { if !$0 { files.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(files.lastError ?? "")
        }
        .alert(files.passwordRequest?.wrongPassword == true ? "Falsches Passwort" : "Passwort erforderlich",
               isPresented: Binding(get: { files.passwordRequest != nil },
                                    set: { if !$0 { files.passwordRequest = nil } })) {
            SecureField("Passwort", text: $password)
            Button("Entpacken") {
                if let req = files.passwordRequest {
                    let pw = password
                    password = ""
                    files.passwordRequest = nil
                    files.extract(req.archive, password: pw)
                }
            }
            Button("Abbrechen", role: .cancel) { password = "" }
        } message: {
            Text(files.passwordRequest?.archive.lastPathComponent ?? "")
        }
    }
}

struct OperationBanner: View {
    let state: FileOperationState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(state.title).font(.subheadline.bold())
                    if let p = state.progress {
                        Text("\(Int(p * 100)) %").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if let p = state.progress {
                    ProgressView(value: min(1, max(0, p)))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                if !state.detail.isEmpty {
                    Text(state.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Button(role: .destructive, action: onCancel) {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
    }
}

// MARK: - Ordneransicht

struct FolderView: View {
    @EnvironmentObject private var files: FilesStore
    let location: FolderLocation

    @State private var items: [FileItem] = []
    @State private var loadError: String?
    @State private var selection = Set<URL>()
    @State private var editMode: EditMode = .inactive
    @State private var preview: URL?
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: FileItem?
    @State private var renameText = ""
    @State private var transfer: TransferRequest?
    @State private var pendingDelete: [URL] = []
    @State private var showImporter = false
    @State private var archiveToExtract: FileItem?

    private var isEditing: Bool { editMode.isEditing }
    private var selectedURLs: [URL] { items.map(\.url).filter { selection.contains($0) } }

    var body: some View {
        List(selection: $selection) {
            if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else if items.isEmpty {
                Text("Dieser Ordner ist leer.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                row(item)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .navigationTitle(location.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: files.refreshToken) { reload() }
        .refreshable { reload() }
        .quickLookPreview($preview)
        .alert("Neuer Ordner", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Erstellen") {
                files.createFolder(in: location.url, name: newFolderName)
                newFolderName = ""
            }
            Button("Abbrechen", role: .cancel) { newFolderName = "" }
        }
        .alert("Umbenennen", isPresented: Binding(get: { renameTarget != nil },
                                                 set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Umbenennen") {
                if let t = renameTarget { files.rename(t.url, to: renameText) }
                renameTarget = nil
            }
            Button("Abbrechen", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !pendingDelete.isEmpty },
                                                              set: { if !$0 { pendingDelete = [] } }),
                            titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                files.delete(pendingDelete)
                pendingDelete = []
                selection.removeAll()
                editMode = .inactive
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("Gelöschte Dateien können nicht wiederhergestellt werden.")
        }
        .confirmationDialog(archiveToExtract?.name ?? "", isPresented: Binding(get: { archiveToExtract != nil },
                                                                               set: { if !$0 { archiveToExtract = nil } }),
                            titleVisibility: .visible) {
            Button("Hier entpacken") {
                if let a = archiveToExtract { files.extract(a.url) }
                archiveToExtract = nil
            }
            Button("Abbrechen", role: .cancel) { archiveToExtract = nil }
        }
        .sheet(item: $transfer) { request in
            FolderPickerSheet(request: request) {
                selection.removeAll()
                editMode = .inactive
            }
            .environmentObject(files)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): files.importFiles(urls, into: location.url)
            case .failure(let error): files.lastError = error.localizedDescription
            }
        }
    }

    private var deleteTitle: String {
        pendingDelete.count == 1
            ? "„\(pendingDelete[0].lastPathComponent)“ löschen?"
            : "\(pendingDelete.count) Objekte löschen?"
    }

    private func reload() {
        do {
            items = try FileOps.list(location.url)
            loadError = nil
            selection = selection.filter { url in items.contains { $0.url == url } }
        } catch {
            items = []
            loadError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func row(_ item: FileItem) -> some View {
        Group {
            if item.isDirectory && !isEditing {
                NavigationLink(value: FolderLocation(url: item.url, title: item.name)) {
                    FileRow(item: item)
                }
            } else if !isEditing {
                Button {
                    if item.archiveKind != nil {
                        archiveToExtract = item
                    } else {
                        preview = item.url
                    }
                } label: {
                    FileRow(item: item)
                }
                .foregroundStyle(.primary)
            } else {
                FileRow(item: item)
            }
        }
        .contextMenu { contextMenu(item) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = [item.url]
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            Button {
                transfer = TransferRequest(urls: [item.url], copy: false)
            } label: {
                Label("Verschieben", systemImage: "folder")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func contextMenu(_ item: FileItem) -> some View {
        if !item.isDirectory {
            Button {
                preview = item.url
            } label: {
                Label("Vorschau", systemImage: "eye")
            }
        }
        ShareLink(item: item.url) {
            Label("Teilen / Öffnen in…", systemImage: "square.and.arrow.up")
        }
        if item.archiveKind != nil {
            Button {
                files.extract(item.url)
            } label: {
                Label("Hier entpacken", systemImage: "arrow.up.bin")
            }
        }
        Button {
            files.compress([item.url], in: location.url)
        } label: {
            Label("Als ZIP komprimieren", systemImage: "doc.zipper")
        }
        Divider()
        Button {
            renameText = item.name
            renameTarget = item
        } label: {
            Label("Umbenennen", systemImage: "pencil")
        }
        Button {
            transfer = TransferRequest(urls: [item.url], copy: false)
        } label: {
            Label("Verschieben…", systemImage: "folder")
        }
        Button {
            transfer = TransferRequest(urls: [item.url], copy: true)
        } label: {
            Label("Kopieren nach…", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive) {
            pendingDelete = [item.url]
        } label: {
            Label("Löschen", systemImage: "trash")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isEditing {
                Button("Fertig") {
                    editMode = .inactive
                    selection.removeAll()
                }
            } else {
                Menu {
                    Button {
                        showNewFolder = true
                    } label: {
                        Label("Neuer Ordner", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Dateien hierher importieren", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        editMode = .active
                    } label: {
                        Label("Auswählen", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if isEditing {
                let urls = selectedURLs
                Button {
                    selection = selection.count == items.count ? [] : Set(items.map(\.url))
                } label: {
                    Image(systemName: selection.count == items.count && !items.isEmpty
                          ? "checkmark.circle.fill" : "checkmark.circle")
                }
                Spacer()
                Button {
                    transfer = TransferRequest(urls: urls, copy: false)
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(urls.isEmpty)
                Button {
                    transfer = TransferRequest(urls: urls, copy: true)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(urls.isEmpty)
                Button {
                    files.compress(urls, in: location.url)
                    selection.removeAll()
                    editMode = .inactive
                } label: {
                    Image(systemName: "doc.zipper")
                }
                .disabled(urls.isEmpty)
                ShareLink(items: urls) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(urls.isEmpty)
                Button(role: .destructive) {
                    pendingDelete = urls
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(urls.isEmpty)
            }
        }
    }
}

struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        if !item.isDirectory { parts.append(Format.bytes(item.size)) }
        if let d = item.modified { parts.append(d.formatted(date: .abbreviated, time: .shortened)) }
        if item.isDirectory && parts.isEmpty { parts.append("Ordner") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Zielordner auswählen (Verschieben / Kopieren)

struct FolderPickerSheet: View {
    @EnvironmentObject private var files: FilesStore
    @Environment(\.dismiss) private var dismiss
    let request: TransferRequest
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Auf diesem Gerät") {
                    NavigationLink(value: FolderLocation(url: files.documentsURL, title: "Plexo")) {
                        Label("Plexo-Ordner", systemImage: "iphone")
                    }
                }
                if !files.linkedFolders.isEmpty {
                    Section("Verknüpfte Ordner") {
                        ForEach(files.linkedFolders) { folder in
                            if let url = files.url(for: folder) {
                                NavigationLink(value: FolderLocation(url: url, title: folder.name)) {
                                    Label(folder.name, systemImage: "folder.fill.badge.person.crop")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(request.copy ? "Kopieren nach…" : "Verschieben nach…")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FolderLocation.self) { location in
                PickerFolderList(location: location, request: request) {
                    files.transfer(request.urls, to: location.url, copy: request.copy)
                    onDone()
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

struct PickerFolderList: View {
    @EnvironmentObject private var files: FilesStore
    let location: FolderLocation
    let request: TransferRequest
    let onChoose: () -> Void

    @State private var folders: [FileItem] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            if folders.isEmpty {
                Text("Keine Unterordner").foregroundStyle(.secondary)
            }
            ForEach(folders) { folder in
                NavigationLink(value: FolderLocation(url: folder.url, title: folder.name)) {
                    Label(folder.name, systemImage: "folder.fill")
                }
            }
        }
        .navigationTitle(location.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: files.refreshToken) { load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(action: onChoose) {
                    Text(request.copy ? "Hierher kopieren" : "Hierher verschieben").bold()
                }
            }
        }
        .alert("Neuer Ordner", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Erstellen") {
                files.createFolder(in: location.url, name: newFolderName)
                newFolderName = ""
            }
            Button("Abbrechen", role: .cancel) { newFolderName = "" }
        }
    }

    private func load() {
        let moving = Set(request.urls.map { $0.standardizedFileURL.path })
        folders = ((try? FileOps.list(location.url)) ?? []).filter {
            $0.isDirectory && !moving.contains($0.url.standardizedFileURL.path)
        }
    }
}
