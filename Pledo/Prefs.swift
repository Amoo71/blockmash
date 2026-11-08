import Foundation

// Einstellungen – entspricht SettingsService / SettingsConstants in pledo.

enum MovieTemplate: Int, CaseIterable, Identifiable {
    case fileName = 0
    case movieDirectory = 1

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fileName: return "Dateiname vom Server"
        case .movieDirectory: return "Filmordner + Dateiname"
        }
    }
}

enum EpisodeTemplate: Int, CaseIterable, Identifiable {
    case seriesAndSeason = 0
    case seriesOnly = 1

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .seriesAndSeason: return "Serie/Staffel/Dateiname"
        case .seriesOnly: return "Serie/Dateiname"
        }
    }
}

struct PrefOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

enum Prefs {
    static let moviesFolderKey = "moviesFolder"
    static let showsFolderKey = "showsFolder"
    static let movieTemplateKey = "movieTemplate"
    static let episodeTemplateKey = "episodeTemplate"
    static let preferredResolutionKey = "preferredResolution"
    static let preferredVideoCodecKey = "preferredVideoCodec"
    static let keepAwakeKey = "keepAwake"
    static let syncOnLaunchKey = "syncOnLaunch"

    static let defaultMoviesFolder = "Filme"
    static let defaultShowsFolder = "Serien"

    static let resolutions: [PrefOption] = [
        PrefOption(value: "", label: "Keine Präferenz"), PrefOption(value: "4k", label: "4K"), PrefOption(value: "1080", label: "1080p"), PrefOption(value: "720", label: "720p"),
        PrefOption(value: "576", label: "576p"), PrefOption(value: "480", label: "480p"), PrefOption(value: "sd", label: "SD")
    ]

    static let videoCodecs: [PrefOption] = [
        PrefOption(value: "", label: "Keine Präferenz"), PrefOption(value: "hevc", label: "HEVC (H.265)"), PrefOption(value: "h264", label: "H.264"), PrefOption(value: "av1", label: "AV1"),
        PrefOption(value: "vc1", label: "VC-1"), PrefOption(value: "mpeg4", label: "MPEG-4"), PrefOption(value: "mpeg2video", label: "MPEG-2")
    ]

    private static var d: UserDefaults { .standard }

    static var moviesFolder: String { d.string(forKey: moviesFolderKey) ?? defaultMoviesFolder }
    static var showsFolder: String { d.string(forKey: showsFolderKey) ?? defaultShowsFolder }
    static var movieTemplate: MovieTemplate { MovieTemplate(rawValue: d.integer(forKey: movieTemplateKey)) ?? .fileName }
    static var episodeTemplate: EpisodeTemplate {
        EpisodeTemplate(rawValue: d.integer(forKey: episodeTemplateKey)) ?? .seriesAndSeason
    }
    static var preferredResolution: String { d.string(forKey: preferredResolutionKey) ?? "" }
    static var preferredVideoCodec: String { d.string(forKey: preferredVideoCodecKey) ?? "" }
    static var keepAwake: Bool { d.object(forKey: keepAwakeKey) as? Bool ?? true }
    static var syncOnLaunch: Bool { d.object(forKey: syncOnLaunchKey) as? Bool ?? true }
}
