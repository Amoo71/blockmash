import Foundation

struct EngineConfig: Codable {
    var renderer: RendererBackend = .metal
    var resolution: ResolutionScale = .native
    var cpuAccuracy: CPUAccuracy = .auto
    var memoryLayout: MemoryLayout = .extended
    var shaderBackend: ShaderBackend = .metalCompiled
    var asyncShaders: Bool = true
    var vsync: Bool = true
    var maxFPS: Int = 60
    var docked: Bool = false
    var useNCE: Bool = true
    var regionCode: RegionCode = .europe

    enum RendererBackend: String, Codable, CaseIterable {
        case metal = "Metal"
        case moltenvk = "Vulkan (MoltenVK)"
    }

    enum ResolutionScale: String, Codable, CaseIterable {
        case half = "0.5x (360p)"
        case native = "1x (720p)"
        case x2 = "2x (1440p)"
    }

    enum CPUAccuracy: String, Codable, CaseIterable {
        case auto = "Auto"
        case accurate = "Accurate"
        case unsafe = "Unsafe (Faster)"
    }

    enum MemoryLayout: String, Codable, CaseIterable {
        case standard = "4 GB (Standard)"
        case extended = "6 GB (Extended)"
    }

    enum ShaderBackend: String, Codable, CaseIterable {
        case metalCompiled = "Metal (Pre-compiled)"
        case metalRuntime = "Metal (Runtime)"
    }

    enum RegionCode: String, Codable, CaseIterable {
        case japan = "Japan"
        case usa = "USA"
        case europe = "Europe"
    }

    static func forDevice() -> EngineConfig {
        var config = EngineConfig()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        if totalMemory >= 8 * 1024 * 1024 * 1024 {
            config.memoryLayout = .extended
            config.resolution = .native
        } else {
            config.memoryLayout = .standard
            config.resolution = .half
        }
        return config
    }
}

struct PerGameConfig: Codable, Identifiable {
    var id: String { titleId }
    let titleId: String
    var engineOverrides: EngineConfig?
    var controllerMapping: ControllerMapping?
    var notes: String = ""

    struct ControllerMapping: Codable {
        var swapAB: Bool = false
        var swapXY: Bool = false
        var motionEnabled: Bool = true
        var touchEnabled: Bool = true
        var stickDeadzone: Float = 0.1
    }
}

class GameConfigStore: ObservableObject {
    @Published var configs: [String: PerGameConfig] = [:]
    private let storeKey = "blockmash_game_configs"

    init() { load() }

    func config(for titleId: String) -> PerGameConfig {
        configs[titleId] ?? PerGameConfig(titleId: titleId)
    }

    func save(config: PerGameConfig) {
        configs[config.titleId] = config
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([String: PerGameConfig].self, from: data) else { return }
        configs = decoded
    }
}
