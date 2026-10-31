import SwiftUI

@main
struct BlockMashApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}
