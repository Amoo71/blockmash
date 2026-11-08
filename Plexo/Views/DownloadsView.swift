import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var networks: NetworkMonitor
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var removeTarget: DownloadRecord?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SpeedHeader()
                }
                if downloads.records.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle.dotted").font(.system(size: 40)).foregroundStyle(.secondary)
                            Text("Noch keine Downloads").font(.headline)
                            Text("Tippe auf +, füge einen Link ein oder lade über den Browser-Tab. Plexo verteilt die Datei auf WLAN und Mobilfunk gleichzeitig.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section {
                        ForEach(downloads.records) { r in
                            NavigationLink(value: r.id) {
                                DownloadRow(record: r, live: downloads.live[r.id])
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeTarget = r
                                } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                                actionButton(r)
                            }
                            .contextMenu {
                                actionButton(r)
                                if let url = downloads.fileURL(r), r.state == .completed {
                                    ShareLink(item: url) { Label("Teilen / Öffnen in…", systemImage: "square.and.arrow.up") }
                                }
                                Button {
                                    UIPasteboard.general.string = r.url
                                } label: {
                                    Label("Link kopieren", systemImage: "link")
                                }
                                Button(role: .destructive) {
                                    removeTarget = r
                                } label: {
                                    Label("Entfernen…", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plexo")
            .navigationDestination(for: UUID.self) { DownloadDetailView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            downloads.pauseAll()
                        } label: {
                            Label("Alle pausieren", systemImage: "pause.circle")
                        }
                        Button {
                            downloads.resumeAll()
                        } label: {
                            Label("Alle fortsetzen", systemImage: "play.circle")
                        }
                        Button(role: .destructive) {
                            downloads.removeCompleted()
                        } label: {
                            Label("Fertige aus Liste entfernen", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddDownloadSheet(initialLinks: nil, headers: [:], fileName: nil) {}
                    .environmentObject(downloads)
                    .environmentObject(networks)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(downloads)
                    .environmentObject(networks)
            }
            .confirmationDialog(removeTarget?.fileName ?? "", isPresented: Binding(
                get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }), titleVisibility: .visible) {
                if let r = removeTarget {
                    Button("Aus Liste entfernen") { downloads.remove(r.id, deleteFile: false) }
                    if r.state == .completed {
                        Button("Entfernen und Datei löschen", role: .destructive) { downloads.remove(r.id, deleteFile: true) }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ r: DownloadRecord) -> some View {
        switch r.state {
        case .queued, .probing, .downloading:
            Button {
                downloads.pause(r.id)
            } label: {
                Label("Pausieren", systemImage: "pause.fill")
            }
            .tint(.orange)
        case .paused:
            Button {
                downloads.resume(r.id)
            } label: {
                Label("Fortsetzen", systemImage: "play.fill")
            }
            .tint(.green)
        case .failed:
            Button {
                downloads.retry(r.id)
            } label: {
                Label("Erneut", systemImage: "arrow.clockwise")
            }
            .tint(.blue)
        case .completed:
            EmptyView()
        }
    }
}

/// Gesamtgeschwindigkeit, aufgeteilt nach Netzwerk.
struct SpeedHeader: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var networks: NetworkMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.speed(downloads.totalSpeed))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text("\(downloads.activeCount) aktiv").font(.caption).foregroundStyle(.secondary)
            }
            SpeedBar(kinds: networks.visibleKinds, speeds: networks.speeds)
            HStack(spacing: 14) {
                ForEach(networks.visibleKinds) { kind in
                    HStack(spacing: 5) {
                        Image(systemName: kind.symbol)
                            .foregroundStyle(networks.isUsable(kind) ? networks.color(kind) : Color.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(networks.name(kind)).font(.caption2).foregroundStyle(.secondary)
                            Text(networks.isAvailable(kind) ? Format.speed(networks.speeds[kind] ?? 0) : "offline")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SpeedBar: View {
    @EnvironmentObject private var networks: NetworkMonitor
    let kinds: [NetworkKind]
    let speeds: [NetworkKind: Double]

    var body: some View {
        let active = kinds.filter { (speeds[$0] ?? 0) > 0 }
        let total = active.reduce(0) { $0 + (speeds[$1] ?? 0) }
        GeometryReader { geo in
            HStack(spacing: 2) {
                if total <= 0 {
                    Capsule().fill(Color.secondary.opacity(0.2))
                } else {
                    ForEach(active) { kind in
                        Capsule()
                            .fill(networks.color(kind))
                            .frame(width: max(4, geo.size.width * (speeds[kind] ?? 0) / total - 2))
                    }
                }
            }
        }
        .frame(height: 8)
    }
}

struct DownloadRow: View {
    @EnvironmentObject private var networks: NetworkMonitor
    let record: DownloadRecord
    let live: DownloadLive?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(record.fileName).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            if record.state == .downloading || record.state == .paused || record.state == .probing {
                ProgressView(value: record.progress)
                    .tint(record.state == .paused ? Color.secondary : Color(hex: "#7C5CFF"))
            }
            HStack(spacing: 6) {
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                Spacer()
                if let live, record.state == .downloading {
                    ForEach(NetworkKind.allCases.filter { (live.networks[$0]?.streams ?? 0) > 0 }) { kind in
                        HStack(spacing: 2) {
                            Image(systemName: kind.symbol).font(.caption2)
                            Text("\(live.networks[kind]?.streams ?? 0)").font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(networks.color(kind))
                    }
                }
            }
            if let error = record.error, record.state == .failed {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            } else if let msg = live?.message {
                Text(msg).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch record.state {
        case .queued: return "clock"
        case .probing: return "antenna.radiowaves.left.and.right"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch record.state {
        case .queued, .paused: return .secondary
        case .probing, .downloading: return Color(hex: "#7C5CFF")
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var detail: String {
        let total = record.totalBytes
        switch record.state {
        case .downloading:
            let speed = live?.speed ?? 0
            var parts = [Format.speed(speed), "\(Format.bytes(record.downloadedBytes)) / \(total > 0 ? Format.bytes(total) : "?")"]
            if let eta = Format.eta(remaining: total - record.downloadedBytes, speed: speed) { parts.append(eta) }
            return parts.joined(separator: " · ")
        case .completed:
            let when = record.finished.map { Format.relative($0) } ?? ""
            return "\(Format.bytes(total)) · \(when)"
        case .paused:
            return "Pausiert · \(Format.bytes(record.downloadedBytes)) / \(total > 0 ? Format.bytes(total) : "?")"
        default:
            return record.state.label
        }
    }
}
