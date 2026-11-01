import Foundation
import SwiftUI

enum LaunchState: Equatable {
    case idle
    case scanning
    case verifyingKeys
    case loadingNCAs
    case compilingShaders(progress: Double)
    case ready
    case running
    case error(String)

    static func == (lhs: LaunchState, rhs: LaunchState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning),
             (.verifyingKeys, .verifyingKeys), (.loadingNCAs, .loadingNCAs),
             (.ready, .ready), (.running, .running):
            return true
        case (.compilingShaders(let a), .compilingShaders(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@MainActor
class GameLauncher: ObservableObject {
    @Published var state: LaunchState = .idle
    @Published var currentGame: GameEntry?
    @Published var fps: Double = 0
    @Published var frametime: Double = 0

    private var engineConfig: EngineConfig

    init(engineConfig: EngineConfig = .forDevice()) {
        self.engineConfig = engineConfig
    }

    func prepareLaunch(game: GameEntry) async {
        currentGame = game
        state = .scanning

        do {
            let url = URL(fileURLWithPath: game.filePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                state = .error("Game file not found at: \(game.filePath)")
                return
            }

            state = .verifyingKeys
            guard let keyStore = KeyStore.loadFromDocuments(), keyStore.hasRequiredKeys else {
                state = .error("prod.keys not found or missing required keys. Import them in the Import tab.")
                return
            }

            state = .loadingNCAs
            let _ = try await GameScanner.shared.scan(url: url)

            state = .compilingShaders(progress: 0)
            let shaderDir = await ShaderCacheManager.shared.cacheDirectory(for: game.titleId)
            let cachedShaders = (try? FileManager.default.contentsOfDirectory(atPath: shaderDir.path))?.count ?? 0

            if cachedShaders > 0 {
                state = .compilingShaders(progress: 1.0)
            } else {
                for i in 1...10 {
                    try? await Task.sleep(for: .milliseconds(100))
                    state = .compilingShaders(progress: Double(i) / 10.0)
                }
            }

            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func launch() {
        guard state == .ready, currentGame != nil else { return }
        state = .running
    }

    func stop() {
        state = .idle
        currentGame = nil
        fps = 0
        frametime = 0
    }
}
