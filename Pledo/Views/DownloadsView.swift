import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if downloads.items.isEmpty {
                    EmptyStateView(title: "Keine Downloads", systemImage: "arrow.down.circle",
                                   message: "Wähle einen Film, eine Serie, Staffel, Episode oder Playlist zum Herunterladen.")
                } else {
                    list
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            openFilesApp()
                        } label: {
                            Label("In Dateien-App öffnen", systemImage: "folder")
                        }
                        Button(role: .destructive) {
                            downloads.cancelAll()
                        } label: {
                            Label("Alle abbrechen", systemImage: "xmark.circle")
                        }
                        Button(role: .destructive) {
                            downloads.clearHistory()
                        } label: {
                            Label("Verlauf leeren", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            let active = downloads.active
            let queued = downloads.queued
            let history = downloads.history
            if !active.isEmpty {
                Section("Aktiv") {
                    ForEach(active) { item in row(item) }
                }
            }
            if !queued.isEmpty {
                Section("Warteschlange (\(queued.count))") {
                    ForEach(queued) { item in row(item) }
                }
            }
            if !history.isEmpty {
                Section("Verlauf") {
                    ForEach(history) { item in row(item) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: DownloadItem) -> some View {
        DownloadRow(item: item, speed: downloads.speeds[item.id])
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if item.status == .running || item.status == .queued {
                    Button(role: .destructive) {
                        downloads.cancel(item.id)
                    } label: {
                        Label("Abbrechen", systemImage: "xmark")
                    }
                } else {
                    Button(role: .destructive) {
                        downloads.remove(item.id, deleteFile: false)
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                    if item.status != .finished {
                        Button {
                            downloads.retry(item.id)
                        } label: {
                            Label("Erneut", systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)
                    }
                }
            }
            .contextMenu {
                if item.status == .finished && downloads.fileExists(item) {
                    ShareLink(item: downloads.fileURL(for: item)) {
                        Label("Teilen / Öffnen in…", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        downloads.remove(item.id, deleteFile: true)
                    } label: {
                        Label("Datei löschen", systemImage: "trash")
                    }
                }
                if item.status == .failed || item.status == .cancelled {
                    Button {
                        downloads.retry(item.id)
                    } label: {
                        Label("Erneut versuchen", systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    private func openFilesApp() {
        let path = DownloadManager.documentsURL.path
        if let url = URL(string: "shareddocuments://" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)) {
            openURL(url)
        }
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let speed: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusIcon
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            Text(item.relativePath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.status == .running {
                ProgressView(value: item.progress)
                HStack {
                    Text("\(Format.bytes(item.downloadedBytes)) / \(Format.bytes(item.totalBytes))")
                    Spacer()
                    if let speed, speed > 0 {
                        Text(Format.speed(speed))
                        if item.totalBytes > item.downloadedBytes {
                            Text("· \(eta(speed))")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            if let m = item.message {
                Text(m).font(.caption).foregroundStyle(item.status == .failed ? Color.red : Color.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued: Image(systemName: "clock").foregroundStyle(.orange)
        case .running: Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch item.status {
        case .queued: return "Wartet · \(Format.bytes(item.totalBytes))"
        case .running: return ""
        case .finished:
            let when = item.finished.map { Format.relative($0) } ?? ""
            return "Fertig · \(Format.bytes(item.totalBytes)) · \(when)"
        case .failed: return "Fehlgeschlagen"
        case .cancelled: return "Abgebrochen"
        }
    }

    private func eta(_ speed: Double) -> String {
        let seconds = Int(Double(item.totalBytes - item.downloadedBytes) / speed)
        if seconds >= 3600 { return "\(seconds / 3600) h \((seconds % 3600) / 60) min" }
        if seconds >= 60 { return "\(seconds / 60) min" }
        return "\(seconds) s"
    }
}
