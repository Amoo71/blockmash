import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var touchLayout: TouchLayout
    @AppStorage("engineRenderer") private var renderer = EngineConfig.RendererBackend.metal.rawValue
    @AppStorage("engineResolution") private var resolution = EngineConfig.ResolutionScale.native.rawValue
    @AppStorage("engineCPUAccuracy") private var cpuAccuracy = EngineConfig.CPUAccuracy.auto.rawValue
    @AppStorage("engineMemoryLayout") private var memoryLayout = EngineConfig.MemoryLayout.extended.rawValue
    @AppStorage("vsync") private var vsync = true
    @AppStorage("maxFPS") private var maxFPS = 60
    @AppStorage("dockedMode") private var dockedMode = false
    @AppStorage("useNCE") private var useNCE = true

    @State private var shaderCacheSize: Int64 = 0
    @State private var showingClearShaders = false
    @State private var showingClearGames = false
    @State private var showingClearKeys = false

    var body: some View {
        NavigationStack {
            List {
                graphicsSection
                performanceSection
                touchSection
                dataSection
            }
            .navigationTitle("Settings")
            .task { await refreshCacheSize() }
            .alert("Clear shader cache?", isPresented: $showingClearShaders) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        await ShaderCacheManager.shared.clearCache()
                        await refreshCacheSize()
                    }
                }
            }
            .alert("Remove all games?", isPresented: $showingClearGames) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { library.removeAllGames() }
            } message: {
                Text("Clears the library index. Original files on your device are not deleted.")
            }
            .alert("Delete prod.keys?", isPresented: $showingClearKeys) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { library.clearKeys() }
            }
        }
    }

    private var graphicsSection: some View {
        Section("Graphics") {
            Picker("Renderer", selection: $renderer) {
                ForEach(EngineConfig.RendererBackend.allCases, id: \.rawValue) {
                    Text($0.rawValue).tag($0.rawValue)
                }
            }
            Picker("Resolution", selection: $resolution) {
                ForEach(EngineConfig.ResolutionScale.allCases, id: \.rawValue) {
                    Text($0.rawValue).tag($0.rawValue)
                }
            }
            Toggle("VSync", isOn: $vsync)
        }
    }

    private var performanceSection: some View {
        Section("Performance") {
            Picker("Target FPS", selection: $maxFPS) {
                Text("30").tag(30)
                Text("60").tag(60)
                Text("120").tag(120)
            }
            Picker("CPU", selection: $cpuAccuracy) {
                ForEach(EngineConfig.CPUAccuracy.allCases, id: \.rawValue) {
                    Text($0.rawValue).tag($0.rawValue)
                }
            }
            Toggle("NCE", isOn: $useNCE)
            Toggle("Docked mode", isOn: $dockedMode)
        }
    }

    private var touchSection: some View {
        Section("Touch Overlay") {
            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                Text("Overall opacity")
                Spacer()
                Text("\(Int(touchLayout.overallOpacity * 100))%")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $touchLayout.overallOpacity, in: 0.1...1.0)
                .onChange(of: touchLayout.overallOpacity) { _, _ in touchLayout.save() }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Games", value: "\(library.games.count)")
            LabeledContent("Keys", value: library.keysImported ? "Imported" : "Missing")
            LabeledContent("Shader cache", value: ByteCountFormatter.string(fromByteCount: shaderCacheSize, countStyle: .file))

            Button(role: .destructive) {
                showingClearShaders = true
            } label: {
                Label("Clear shader cache", systemImage: "trash")
            }
            Button(role: .destructive) {
                showingClearGames = true
            } label: {
                Label("Remove all games", systemImage: "trash")
            }
            .disabled(library.games.isEmpty)
            Button(role: .destructive) {
                showingClearKeys = true
            } label: {
                Label("Delete prod.keys", systemImage: "key.slash")
            }
            .disabled(!library.keysImported)
        }
    }

    private func refreshCacheSize() async {
        shaderCacheSize = await ShaderCacheManager.shared.cacheSize()
    }
}
