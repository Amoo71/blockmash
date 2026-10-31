import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: GameLibrary
    @AppStorage("engineRenderer") private var renderer = EngineConfig.RendererBackend.metal.rawValue
    @AppStorage("engineResolution") private var resolution = EngineConfig.ResolutionScale.native.rawValue
    @AppStorage("engineCPUAccuracy") private var cpuAccuracy = EngineConfig.CPUAccuracy.auto.rawValue
    @AppStorage("engineMemoryLayout") private var memoryLayout = EngineConfig.MemoryLayout.extended.rawValue
    @AppStorage("asyncShaders") private var asyncShaders = true
    @AppStorage("vsync") private var vsync = true
    @AppStorage("maxFPS") private var maxFPS = 60
    @AppStorage("dockedMode") private var dockedMode = false
    @AppStorage("useNCE") private var useNCE = true
    @State private var shaderCacheSize: Int64 = 0
    @State private var showingClearAlert = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                graphicsSection
                cpuSection
                performanceSection
                cacheSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task { await refreshCacheSize() }
            .alert("Clear Shader Cache?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        await ShaderCacheManager.shared.clearCache()
                        await refreshCacheSize()
                    }
                }
            } message: {
                Text("All cached shaders will be removed. Games will recompile shaders on next launch.")
            }
            .sheet(isPresented: $showingAbout) { aboutView }
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
            Toggle("Async Shader Compilation", isOn: $asyncShaders)
            Toggle("VSync", isOn: $vsync)
        }
    }

    private var cpuSection: some View {
        Section("CPU") {
            Picker("Accuracy", selection: $cpuAccuracy) {
                ForEach(EngineConfig.CPUAccuracy.allCases, id: \.rawValue) {
                    Text($0.rawValue).tag($0.rawValue)
                }
            }
            Picker("Memory Layout", selection: $memoryLayout) {
                ForEach(EngineConfig.MemoryLayout.allCases, id: \.rawValue) {
                    Text($0.rawValue).tag($0.rawValue)
                }
            }
            Toggle("NCE (Native Code Execution)", isOn: $useNCE)
        }
    }

    private var performanceSection: some View {
        Section("Performance") {
            Picker("Max FPS", selection: $maxFPS) {
                Text("30").tag(30)
                Text("60").tag(60)
                Text("120").tag(120)
            }
            Toggle("Docked Mode", isOn: $dockedMode)
        }
    }

    private var cacheSection: some View {
        Section("Shader Cache") {
            LabeledContent("Cache Size", value: ByteCountFormatter.string(fromByteCount: shaderCacheSize, countStyle: .file))
            Button(role: .destructive) {
                showingClearAlert = true
            } label: {
                Label("Clear Shader Cache", systemImage: "trash")
            }
        }
    }

    private var dataSection: some View {
        Section("Library") {
            LabeledContent("Games", value: "\(library.games.count)")
            LabeledContent("Total Size", value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))
            LabeledContent("Keys", value: library.keysImported ? "Imported" : "Missing")
        }
    }

    private var aboutSection: some View {
        Section {
            Button { showingAbout = true } label: {
                Label("About NXLauncher", systemImage: "info.circle")
            }
        }
    }

    private var aboutView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple)
                Text("NXLauncher")
                    .font(.largeTitle.bold())
                Text("BlockMash Hybrid Launcher v2.0.0")
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("Local NX game launcher for iOS")
                    Text("iPhone 16 Pro / A18 Pro / iOS 27")
                    Text("Metal GPU | NCE | Local Processing")
                }
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 16) {
                    deviceBadge(icon: "cpu", label: "A18 Pro")
                    deviceBadge(icon: "memorychip", label: "8 GB")
                    deviceBadge(icon: "gpu", label: "Metal 3")
                }
                .padding(.bottom, 32)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingAbout = false }
                }
            }
        }
    }

    private func deviceBadge(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.purple)
        .frame(width: 70, height: 60)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func refreshCacheSize() async {
        shaderCacheSize = await ShaderCacheManager.shared.cacheSize()
    }
}
