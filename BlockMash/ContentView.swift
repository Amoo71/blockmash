import SwiftUI

struct ContentView: View {
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
    }
}
