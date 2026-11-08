import SwiftUI

@main
struct PledoApp: App {
    @StateObject private var store = LibraryStore.shared
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var files = FilesStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(downloads)
                .environmentObject(files)
                .task {
                    downloads.resumePendingDownloads()
                    await store.onLaunch()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Übersicht", systemImage: "house") }
            MoviesView()
                .tabItem { Label("Filme", systemImage: "film") }
            ShowsView()
                .tabItem { Label("Serien", systemImage: "tv") }
            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .badge(downloads.pendingCount)
            FilesView()
                .tabItem { Label("Dateien", systemImage: "folder") }
        }
        .tint(Color(red: 0.90, green: 0.63, blue: 0.05))
    }
}

extension View {
    func mediaDestinations() -> some View {
        self
            .navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
            .navigationDestination(for: TvShow.self) { ShowDetailView(show: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
    }
}
