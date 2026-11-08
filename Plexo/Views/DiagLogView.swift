import SwiftUI
import UIKit

struct DiagLogView: View {
    @EnvironmentObject private var networks: NetworkMonitor
    @State private var lines: [String] = []

    private var header: String {
        var parts: [String] = []
        for kind in NetworkKind.allCases {
            let iface = networks.interfaceNames[kind] ?? "-"
            parts.append("\(kind.defaultName): \(networks.status(kind).label) (\(iface))")
        }
        parts.append("Standardroute: \(networks.primary.map { $0.defaultName } ?? "keine")")
        return parts.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section("Netzwerke jetzt") {
                Text(header).font(.caption.monospaced())
            }
            Section("Ereignisse (neueste oben)") {
                if lines.isEmpty {
                    Text("Noch keine Einträge – starte einen Download.").foregroundStyle(.secondary)
                }
                ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = header + "\n\n" + lines.joined(separator: "\n")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                Button {
                    DiagLog.clear()
                    lines = []
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                lines = DiagLog.all()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
