import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var touchLayout: TouchLayout

    @State private var showingClearGames = false
    @State private var showingClearKeys = false

    var body: some View {
        NavigationStack {
            List {
                touchSection
                dataSection
            }
            .navigationTitle("Settings")
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
}
