import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: GameLibrary
    @AppStorage("shaderCacheEnabled") private var shaderCacheEnabled = true
    @AppStorage("autoUpdate") private var autoUpdate = true
    @AppStorage("selectedRenderer") private var selectedRenderer = "Metal"
    @State private var showingResetAlert = false
    @State private var showingAbout = false

    private let renderers = ["Metal", "Vulkan (MoltenVK)"]

    var body: some View {
        NavigationStack {
            List {
                Section("Engine") {
                    Picker("Renderer", selection: $selectedRenderer) {
                        ForEach(renderers, id: \.self) { Text($0) }
                    }
                    Toggle("Shader Cache", isOn: $shaderCacheEnabled)
                    Toggle("Auto-check for Updates", isOn: $autoUpdate)
                }

                Section("Storage") {
                    LabeledContent("Games", value: "\(library.games.count)")
                    LabeledContent("Library Size", value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))
                    LabeledContent("Keys Status", value: library.keysImported ? "Imported" : "Missing")
                }

                Section("Data") {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Clear Shader Cache", systemImage: "trash")
                    }
                }

                Section {
                    Button {
                        showingAbout = true
                    } label: {
                        Label("About BlockMash", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Clear Shader Cache?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {}
            } message: {
                Text("This will remove all cached shaders. Games may take longer to load the next time.")
            }
            .sheet(isPresented: $showingAbout) {
                aboutView
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

                Text("BlockMash")
                    .font(.largeTitle.bold())

                Text("Hybrid Launcher v1.0.0")
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Local game library for iOS.")
                    Text("Import, manage, and launch your games.")
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Spacer()

                Text("Built with SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingAbout = false }
                }
            }
        }
    }
}
