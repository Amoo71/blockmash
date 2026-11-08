import SwiftUI
import SafariServices
import UIKit

struct PosterView: View {
    let url: URL?
    var width: CGFloat = 46
    var symbol = "film"

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
    }
}

struct DownloadStateBadge: View {
    @EnvironmentObject private var downloads: DownloadManager
    let mediaKey: String

    var body: some View {
        if let item = downloads.latestItem(forMediaKey: mediaKey) {
            switch item.status {
            case .queued:
                Image(systemName: "clock").foregroundStyle(.orange)
            case .running:
                ProgressRing(progress: item.progress)
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .cancelled:
                EmptyView()
            }
        }
    }
}

/// Download-Knopf; bei mehreren Versionen als Menü.
struct DownloadMenuButton: View {
    let files: [MediaFile]
    let onDefault: () -> Void
    let onFile: (MediaFile) -> Void

    var body: some View {
        if files.count > 1 {
            Menu {
                Button {
                    onDefault()
                } label: {
                    Label("Bevorzugte Version", systemImage: "star")
                }
                Divider()
                ForEach(files) { f in
                    Button(f.summary) { onFile(f) }
                }
            } label: {
                Image(systemName: "arrow.down.circle").font(.title3)
            }
        } else {
            Button(action: onDefault) {
                Image(systemName: "arrow.down.circle").font(.title3)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct MediaFileRow: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.openURL) private var openURL
    let file: MediaFile
    let serverId: String
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.resolutionLabel)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    Text(file.summary).font(.caption).foregroundStyle(.secondary)
                }
                if !file.fileName.isEmpty {
                    Text(file.fileName).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let d = Format.duration(ms: file.duration) { Text(d) }
                    if let b = file.bitrate { Text("\(b) kbit/s") }
                    if let fr = file.videoFrameRate { Text(fr) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            if let url = store.directDownloadURL(serverId: serverId, file: file) {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Direktlink kopieren", systemImage: "doc.on.doc")
                }
                Button {
                    openURL(url)
                } label: {
                    Label("Im Browser öffnen", systemImage: "safari")
                }
            }
        }
    }
}

struct LibraryFilterMenu: View {
    @EnvironmentObject private var store: LibraryStore
    let libraries: [PlexLibrary]
    @Binding var selection: String

    var body: some View {
        Menu {
            Picker("Bibliothek", selection: $selection) {
                Text("Alle Bibliotheken").tag("")
                ForEach(libraries) { lib in
                    Text(label(for: lib)).tag(lib.id)
                }
            }
        } label: {
            Image(systemName: selection.isEmpty
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func label(for lib: PlexLibrary) -> String {
        if store.servers.count > 1, let s = store.server(id: lib.serverId) { return "\(lib.name) (\(s.name))" }
        return lib.name
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
