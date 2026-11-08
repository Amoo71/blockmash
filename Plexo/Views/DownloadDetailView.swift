import SwiftUI
import Charts

// Detailansicht – entspricht DownloadingScreen.tsx / CompleteScreen.tsx in Plexo:
// Fortschritt, Netzwerke einzeln an/aus, Geschwindigkeit pro Netzwerk, Blockgitter.

struct DownloadDetailView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var networks: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    @State private var showReplace = false
    @State private var newLink = ""
    @State private var confirmRemove = false

    var body: some View {
        if let r = downloads.record(id) {
            content(r, live: downloads.live[id])
        } else {
            EmptyStateView(title: "Entfernt", systemImage: "trash", message: "Dieser Download existiert nicht mehr.")
        }
    }

    private func content(_ r: DownloadRecord, live: DownloadLive?) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(r.fileName).font(.headline).textSelection(.enabled)
                    ProgressView(value: r.progress)
                        .tint(Color(hex: "#7C5CFF"))
                    HStack {
                        Text("\(Int(r.progress * 100)) %").font(.title2.bold()).monospacedDigit()
                        Spacer()
                        VStack(alignment: .trailing) {
                            if r.state == .downloading {
                                Text(Format.speed(live?.speed ?? 0)).font(.headline).monospacedDigit()
                                if let eta = Format.eta(remaining: r.totalBytes - r.downloadedBytes, speed: live?.speed ?? 0) {
                                    Text("noch \(eta)").font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(r.state.label).font(.headline)
                            }
                        }
                    }
                    Text("\(Format.bytes(r.downloadedBytes)) von \(r.totalBytes > 0 ? Format.bytes(r.totalBytes) : "unbekannt")")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    if let error = r.error, r.state == .failed {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if let msg = live?.message {
                        Text(msg).font(.caption).foregroundStyle(.orange)
                    }
                    if r.state != .completed && r.totalBytes > 0 && !r.supportsRanges {
                        Label("Server unterstützt keine Teil-Downloads – nur ein Netzwerk, keine Fortsetzung.",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                actions(r)
            }

            Section {
                ForEach(networks.visibleKinds) { kind in
                    NetworkLiveRow(kind: kind, record: r, live: live?.networks[kind])
                }
            } header: {
                Text("Netzwerke")
            } footer: {
                if r.state == .downloading {
                    Text("Schalte Netzwerke jederzeit an oder aus – laufende Teile werden auf die übrigen verteilt.")
                }
            }

            if r.state == .downloading {
                Section("Geschwindigkeit (alle Downloads, 60 s)") {
                    ThroughputChart()
                        .frame(height: 140)
                }
            }

            if r.blocks.count > 1 {
                Section {
                    BlockGrid(blocks: r.blocks, active: live?.activeBlocks ?? [])
                        .padding(.vertical, 4)
                } header: {
                    Text("Blöcke (\(r.blocks.filter(\.isComplete).count)/\(r.blocks.count))")
                } footer: {
                    Text("Jedes Feld ist ein Teil der Datei, gefärbt nach dem Netzwerk, das ihn geladen hat.")
                }
            }

            Section("Details") {
                LabeledContent("Link") {
                    Text(r.url).font(.caption).lineLimit(3).textSelection(.enabled)
                }
                if let f = r.finalURL, f != r.url {
                    LabeledContent("Ziel nach Weiterleitung") {
                        Text(f).font(.caption).lineLimit(3).textSelection(.enabled)
                    }
                }
                LabeledContent("Teil-Downloads", value: r.supportsRanges ? "Ja" : "Nein")
                LabeledContent("Streams", value: r.streams == 0 ? "Automatisch" : "\(r.streams) pro Netzwerk")
                LabeledContent("Hinzugefügt", value: r.created.formatted(date: .abbreviated, time: .shortened))
                if let path = r.relativePath {
                    LabeledContent("Gespeichert", value: path)
                }
            }
        }
        .navigationTitle(r.state.label)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Link ersetzen", isPresented: $showReplace) {
            TextField("Neuer Link", text: $newLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Ersetzen") { downloads.replaceLink(r.id, with: newLink) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Für abgelaufene Links: Der bisherige Fortschritt bleibt erhalten, wenn die Datei gleich groß ist.")
        }
        .confirmationDialog("Download entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Aus Liste entfernen") {
                downloads.remove(r.id, deleteFile: false)
                dismiss()
            }
            if r.state == .completed {
                Button("Entfernen und Datei löschen", role: .destructive) {
                    downloads.remove(r.id, deleteFile: true)
                    dismiss()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func actions(_ r: DownloadRecord) -> some View {
        HStack(spacing: 12) {
            switch r.state {
            case .queued, .probing, .downloading:
                Button {
                    downloads.pause(r.id)
                } label: {
                    Label("Pausieren", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .paused:
                Button {
                    downloads.resume(r.id)
                } label: {
                    Label("Fortsetzen", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            case .failed:
                Button {
                    downloads.retry(r.id)
                } label: {
                    Label("Erneut", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            case .completed:
                if let url = downloads.fileURL(r) {
                    ShareLink(item: url) {
                        Label("Öffnen in…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if r.state != .completed {
                Button {
                    newLink = r.url
                    showReplace = true
                } label: {
                    Image(systemName: "link.badge.plus")
                }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
    }
}

struct NetworkLiveRow: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var networks: NetworkMonitor
    let kind: NetworkKind
    let record: DownloadRecord
    let live: NetworkLive?

    var body: some View {
        let on = record.networks.contains(kind)
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .foregroundStyle(on ? networks.color(kind) : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(networks.name(kind)).font(.subheadline.weight(.semibold))
                Text(subtitle(on: on)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if record.state != .completed {
                Toggle("", isOn: Binding(get: { on }, set: { downloads.setNetwork(record.id, kind, enabled: $0) }))
                    .labelsHidden()
                    .tint(networks.color(kind))
            }
        }
    }

    private func subtitle(on: Bool) -> String {
        let bytes = record.bytesByNetwork[kind.rawValue] ?? 0
        var parts: [String] = []
        if record.state == .downloading, on {
            if !networks.isAvailable(kind) {
                parts.append("nicht verfügbar")
            } else if networks.isOverCap(kind) {
                parts.append("Datenlimit erreicht")
            } else if live?.failing == true {
                parts.append("Fehler")
            } else {
                parts.append(Format.speed(live?.speed ?? 0))
                parts.append("\(live?.streams ?? 0) Streams")
            }
        } else if !on {
            parts.append("aus")
        }
        parts.append(Format.bytes(bytes) + " geladen")
        return parts.joined(separator: " · ")
    }
}

/// Live-Diagramm der letzten 60 Sekunden pro Netzwerk.
struct ThroughputChart: View {
    @EnvironmentObject private var networks: NetworkMonitor

    private struct Point: Identifiable {
        let id: String
        let second: Int
        let speed: Double
        let network: String
    }

    var body: some View {
        let points: [Point] = networks.visibleKinds.flatMap { kind -> [Point] in
            let h = networks.history[kind] ?? []
            return h.enumerated().map { i, v in
                Point(id: "\(kind.rawValue)-\(i)", second: i - h.count + 1, speed: v / 1_048_576, network: networks.name(kind))
            }
        }
        Chart(points) { p in
            AreaMark(x: .value("Sekunde", p.second), y: .value("MB/s", p.speed))
                .foregroundStyle(by: .value("Netzwerk", p.network))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(domain: networks.visibleKinds.map { networks.name($0) },
                                   range: networks.visibleKinds.map { networks.color($0) })
        .chartXAxis(.hidden)
        .chartYAxisLabel("MB/s")
    }
}

/// Blockgitter – entspricht BlockGrid.tsx in Plexo.
struct BlockGrid: View {
    @EnvironmentObject private var networks: NetworkMonitor
    let blocks: [BlockState]
    let active: Set<Int>

    var body: some View {
        let maxCells = 400
        let group = max(1, Int((Double(blocks.count) / Double(maxCells)).rounded(.up)))
        let cells = stride(from: 0, to: blocks.count, by: group).map { start -> (Color, Double) in
            let slice = blocks[start..<min(start + group, blocks.count)]
            let isActive = (start..<min(start + group, blocks.count)).contains { active.contains($0) }
            let done = slice.reduce(Int64(0)) { $0 + $1.done }
            let length = slice.reduce(Int64(0)) { $0 + ($1.length ?? 0) }
            var byNet: [String: Int64] = [:]
            for b in slice { for (k, v) in b.byNetwork { byNet[k, default: 0] += v } }
            let kind = byNet.max { $0.value < $1.value }.flatMap { NetworkKind(rawValue: $0.key) }
            let fraction = length > 0 ? Double(done) / Double(length) : 0
            if fraction >= 1, let kind { return (networks.color(kind), 1) }
            if isActive, let kind { return (networks.color(kind), 0.35 + fraction * 0.5) }
            if isActive { return (Color.accentColor, 0.35) }
            return (Color.secondary, fraction > 0 ? 0.35 : 0.15)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 20), spacing: 2) {
            ForEach(cells.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cells[i].0.opacity(cells[i].1))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
