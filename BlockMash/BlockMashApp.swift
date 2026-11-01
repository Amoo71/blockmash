import SwiftUI

@main
struct BlockMashApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var configStore = GameConfigStore()
    @StateObject private var controllerManager = ControllerManager()
    @StateObject private var touchLayout = TouchLayout()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(configStore)
                .environmentObject(controllerManager)
                .environmentObject(touchLayout)
                .preferredColorScheme(.dark)
        }
    }
}
