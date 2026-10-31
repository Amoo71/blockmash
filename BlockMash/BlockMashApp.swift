import SwiftUI

@main
struct BlockMashApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var configStore = GameConfigStore()
    @StateObject private var controllerManager = ControllerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(configStore)
                .environmentObject(controllerManager)
        }
    }
}
