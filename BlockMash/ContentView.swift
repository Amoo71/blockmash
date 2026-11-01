import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: GameLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "gamecontroller.fill")
                }
                .tag(0)

            ImportView()
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down.fill")
                }
                .tag(1)

            ControllerView()
                .tabItem {
                    Label("Controller", systemImage: "dpad.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.purple)
        .task { await library.scanAppFolder() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await library.scanAppFolder() }
            }
        }
        .onOpenURL { url in
            selectedTab = 1
            library.importOpened(url)
        }
    }
}
