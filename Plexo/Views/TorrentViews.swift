import SwiftUI

struct TorrentRef: Hashable {
    let id: String
}

struct TorrentRow: View {
    let item: TorrentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(item.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            if !(item.finished && item.paused) {
                ProgressView(value: item.progress)
                    .tint(item.paused ? Color.secondary : Color(hex: "#10B981"))
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            if !item.error.isEmpty {
                Text(item.error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        if !item.error.isEmpty { return "exclamationmark.triangle.fill" }
        if item.finished { return "checkmark.circle.fill" }
        if item.paused { return "pause.circle.fill" }
        return "arrow.triangle.branch"
    }

    private var color: Color {
        if !item.error.isEmpty { return .red }
        if item.finished { return .green }
        if item.paused { return .secondary }
        return Color(hex: "#10B981")
    }

    private var detail: String {
        var parts = [item.stateLabel]
        if !item.hasMetadata {
            parts.append("\(item.peers) Peers")
        } else {
            parts.append("\(Format.bytes(item.wantedDone)) / \(Format.bytes(item.totalWanted))")
            if !item.paused && !item.finished {
                parts.append("↓ \(Format.speed(Double(item.downRate)))")
                parts.append("\(item.peers) Peers")
                if let eta = Format.eta(remaining: item.totalWanted - item.wantedDone, speed: Double(item.downRate)) {
                    parts.append(eta)
                }
            }
            if item.upRate > 0 { parts.append("↑ \(Format.speed(Double(item.upRate)))") }
        }
        return parts.joined(separator: " · ")
    }
}

struct TorrentDetailView: View {
    @EnvironmentObject private var torrents: TorrentManager
    @EnvironmentObject private var networks: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var files: [TorrentFile] = []
    @State private var sequential = false
    @State private var confirmRemove = false

    var body: some View {
        if let item = torrents.items.first(where: { $0.id == id }) {
            content(item)
        } else {
            EmptyStateView(title: "Entfernt", systemImage: "trash", message: "Dieser Torrent existiert nicht mehr.")
        }
    }

    private func content(_ item: TorrentItem) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.displayName).font(.headline).textSelection(.enabled)
                    ProgressView(value: item.progress).tint(Color(hex: "#10B981"))
                    HStack {
                        Text("\(Int(item.progress * 100)) %").font(.title2.bold()).monospacedDigit()
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("↓ \(Format.speed(Double(item.downRate)))").font(.headline).monospacedDigit()
                            Text("↑ \(Format.speed(Double(item.upRate)))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(item.stateLabel) · \(item.peers) Peers (\(item.seeds) Seeds)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !item.error.isEmpty {
                        Text(item.error).font(.caption).foregroundStyle(.red)
                    }
                }
                HStack(spacing: 12) {
                    if item.paused {
                        Button {
                            torrents.resume(id)
                        } label: {
                            Label(item.finished ? "Seeden" : "Fortsetzen", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            torrents.pause(id)
                        } label: {
                            Label("Pausieren", systemImage: "pause.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        torrents.reannounce(id)
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section {
                ForEach(networks.visibleKinds) { kind in
                    let st = torrents.interfaceStats[kind] ?? InterfaceStat()
                    HStack {
                        Image(systemName: kind.symbol).foregroundStyle(networks.color(kind)).frame(width: 26)
                        Text(networks.name(kind))
                        Spacer()
                        Text("\(st.peers) Peers · ↓ \(Format.speed(Double(st.down)))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            } header: {
                Text("Netzwerke (alle Torrents)")
            } footer: {
                Text("Neue Peers werden reihum über alle eingeschalteten Netzwerke verbunden. Netzwerke schaltest du im Tab „Netzwerke“ an und aus.")
            }

            if item.hasMetadata {
                Section {
                    Toggle("Der Reihe nach laden (für Vorschau)", isOn: $sequential)
                        .onChange(of: sequential) { on in torrents.setSequential(id, on) }
                    Button("Daten prüfen") { torrents.recheck(id) }
                }

                Section("Dateien (\(files.count))") {
                    ForEach(files) { f in
                        TorrentFileRow(file: f) { on in
                            torrents.setFilePriority(id, index: f.index, priority: on ? 4 : 0)
                            Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                files = await torrents.files(id)
                            }
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        ProgressView()
                        Text("Metadaten werden von Peers geladen …").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Details") {
                LabeledContent("Info-Hash") {
                    Text(id).font(.caption2.monospaced()).textSelection(.enabled)
                }
                LabeledContent("Gesamt", value: Format.bytes(item.totalSize))
                LabeledContent("Hochgeladen", value: Format.bytes(item.uploaded))
                LabeledContent("Speicherort", value: item.savePath.replacingOccurrences(of: AppPaths.documents.path, with: "Plexo"))
            }
        }
        .navigationTitle(item.stateLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.hasMetadata) {
            files = await torrents.files(id)
        }
        .refreshable { files = await torrents.files(id) }
        .confirmationDialog("Torrent entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Nur aus Liste entfernen") {
                torrents.remove(id, deleteFiles: false)
                dismiss()
            }
            Button("Entfernen und Dateien löschen", role: .destructive) {
                torrents.remove(id, deleteFiles: true)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

struct TorrentFileRow: View {
    let file: TorrentFile
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text((file.path as NSString).lastPathComponent).font(.subheadline).lineLimit(2)
                Text("\(Format.bytes(file.done)) / \(Format.bytes(file.size))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if file.size > 0 && file.priority > 0 {
                    ProgressView(value: min(1, Double(file.done) / Double(file.size)))
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { file.priority > 0 }, set: { onToggle($0) }))
                .labelsHidden()
        }
    }
}
