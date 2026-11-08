import SwiftUI

// Netzwerke – entspricht NetworksMenu / NetworkEditPopover / LimitsDialog in Plexo:
// Status, Live-Tempo, umbenennen, Farbe, Speed-Limit, Datenvolumen.

struct NetworksView: View {
    @EnvironmentObject private var networks: NetworkMonitor
    @EnvironmentObject private var downloads: DownloadManager
    @State private var results: [NetworkKind: String] = [:]
    @State private var testing = false

    private func runTests() {
        testing = true
        results = [:]
        let kinds = networks.visibleKinds.filter { networks.isAvailable($0) || $0 == .cellular }
        Task {
            await withTaskGroup(of: (NetworkKind, String).self) { group in
                for kind in kinds {
                    group.addTask {
                        let text = await NetworkTester.run(kind)
                        return (kind, text)
                    }
                }
                for await (kind, text) in group {
                    results[kind] = text
                }
            }
            testing = false
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ThroughputChart()
                        .frame(height: 160)
                        .padding(.vertical, 6)
                } header: {
                    Text("Geschwindigkeit (60 s)")
                } footer: {
                    Text("Gesamt: \(Format.speed(downloads.totalSpeed))")
                }

                Section {
                    Button {
                        runTests()
                    } label: {
                        Label(testing ? "Teste…" : "Alle Netzwerke testen", systemImage: "speedometer")
                    }
                    .disabled(testing)
                    ForEach(NetworkKind.allCases.filter { results[$0] != nil }) { kind in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(networks.name(kind)).font(.caption.bold())
                            Text(results[kind] ?? "").font(.caption)
                        }
                    }
                } header: {
                    Text("Verbindungstest")
                } footer: {
                    Text("Lädt kurz über jedes Netzwerk einzeln. So siehst du, ob Mobilfunk neben WLAN wirklich nutzbar ist.")
                }

                Section {
                    ForEach(NetworkKind.allCases) { kind in
                        NavigationLink(value: kind) {
                            NetworkCard(kind: kind)
                        }
                    }
                } header: {
                    Text("Verbindungen")
                } footer: {
                    Text("Plexo bindet jede Verbindung fest an WLAN, Mobilfunk oder Ethernet (USB-Adapter) und lädt über alle gleichzeitig. Ausgeschaltete Netzwerke werden für neue Downloads nicht vorausgewählt und von laufenden nicht genutzt.")
                }
            }
            .navigationTitle("Netzwerke")
            .navigationDestination(for: NetworkKind.self) { NetworkEditView(kind: $0) }
        }
    }
}

struct NetworkCard: View {
    @EnvironmentObject private var networks: NetworkMonitor
    let kind: NetworkKind

    var body: some View {
        let s = networks.settings[kind] ?? NetworkSettings()
        let status = networks.status(kind)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(networks.color(kind).opacity(status == .on ? 0.2 : 0.08))
                Image(systemName: kind.symbol)
                    .foregroundStyle(status == .on ? networks.color(kind) : Color.secondary)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(networks.name(kind)).font(.headline)
                    if let iface = networks.interfaceNames[kind] {
                        Text(iface).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(statusLine(status, s)).font(.caption).foregroundStyle(status == .limit || status == .denied ? Color.red : Color.secondary)
                if s.dataCap > 0 {
                    ProgressView(value: min(1, Double(s.usedBytes) / Double(s.dataCap)))
                        .tint(networks.color(kind))
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { s.enabled }, set: { v in networks.update(kind) { $0.enabled = v } }))
                .labelsHidden()
                .tint(networks.color(kind))
        }
        .padding(.vertical, 4)
    }

    private func statusLine(_ status: NetworkStatus, _ s: NetworkSettings) -> String {
        var parts = [status.label]
        if status == .on { parts.append(Format.speed(networks.speeds[kind] ?? 0)) }
        if s.dataCap > 0 {
            parts.append("\(Format.bytes(s.usedBytes)) / \(Format.bytes(s.dataCap)) \(s.capPeriod.label)")
        } else if s.usedBytes > 0 {
            parts.append("\(Format.bytes(s.usedBytes)) genutzt")
        }
        if s.speedLimit > 0 { parts.append("max. \(Format.speed(Double(s.speedLimit)))") }
        return parts.joined(separator: " · ")
    }
}

struct NetworkEditView: View {
    @EnvironmentObject private var networks: NetworkMonitor
    @EnvironmentObject private var downloads: DownloadManager
    let kind: NetworkKind

    @State private var name = ""
    @State private var capGB = ""
    @State private var loaded = false

    static let speedOptions: [Int64] = [0, 256 * 1024, 512 * 1024, 1 << 20, 2 << 20, 5 << 20, 10 << 20, 20 << 20, 50 << 20]

    var body: some View {
        let s = networks.settings[kind] ?? NetworkSettings()
        Form {
            Section("Name & Farbe") {
                TextField(kind.defaultName, text: $name)
                    .onSubmit { networks.update(kind) { $0.name = name } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(NetworkMonitor.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary, lineWidth: (s.colorHex ?? kind.defaultColorHex) == hex ? 3 : 0))
                                .onTapGesture { networks.update(kind) { $0.colorHex = hex } }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Für Downloads nutzen", isOn: Binding(get: { s.enabled },
                                                             set: { v in networks.update(kind) { $0.enabled = v } }))
                LabeledContent("Status", value: networks.status(kind).label)
                if let iface = networks.interfaceNames[kind] {
                    LabeledContent("Schnittstelle", value: iface)
                }
            }

            Section {
                Picker("Geschwindigkeit", selection: Binding(get: { s.speedLimit },
                                                             set: { v in networks.update(kind) { $0.speedLimit = v }
                                                                 downloads.applyLimits() })) {
                    ForEach(Self.speedOptions, id: \.self) { v in
                        Text(v == 0 ? "Unbegrenzt" : Format.speed(Double(v))).tag(v)
                    }
                }
            } header: {
                Text("Speed-Limit")
            }

            Section {
                HStack {
                    TextField("Kein Limit", text: $capGB)
                        .keyboardType(.decimalPad)
                    Text("GB")
                }
                Picker("Zeitraum", selection: Binding(get: { s.capPeriod },
                                                      set: { v in networks.update(kind) { $0.capPeriod = v } })) {
                    ForEach(LimitPeriod.allCases) { p in Text(p.label).tag(p) }
                }
                Button("Limit speichern") { saveCap() }
                LabeledContent("Verbraucht", value: Format.bytes(s.usedBytes))
                Button("Zähler zurücksetzen", role: .destructive) { networks.resetUsage(kind) }
            } header: {
                Text("Datenvolumen")
            } footer: {
                Text("Ist das Volumen erreicht, nutzt Plexo dieses Netzwerk nicht mehr, bis der Zeitraum endet. Ideal für Mobilfunk. Gezählt werden nur Plexo-Downloads.")
            }
        }
        .navigationTitle(networks.name(kind))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = s.name ?? ""
            capGB = s.dataCap > 0 ? String(format: "%.1f", Double(s.dataCap) / 1_073_741_824) : ""
        }
        .onDisappear {
            networks.update(kind) { $0.name = name.trimmingCharacters(in: .whitespaces) }
        }
    }

    private func saveCap() {
        let value = Double(capGB.replacingOccurrences(of: ",", with: ".")) ?? 0
        networks.update(kind) { $0.dataCap = Int64(max(0, value) * 1_073_741_824) }
    }
}
