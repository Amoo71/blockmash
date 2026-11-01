import Foundation
import SwiftUI

enum TouchButtonID: String, Codable, CaseIterable, Identifiable {
    case a, b, x, y
    case l, r, zl, zr
    case plus, minus, home
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case leftStick, rightStick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .l: return "L"
        case .r: return "R"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .plus: return "+"
        case .minus: return "–"
        case .home: return "⌂"
        case .dpadUp: return "▲"
        case .dpadDown: return "▼"
        case .dpadLeft: return "◀"
        case .dpadRight: return "▶"
        case .leftStick: return "L-Stick"
        case .rightStick: return "R-Stick"
        }
    }

    var tintHex: UInt32 {
        switch self {
        case .a: return 0xff5555      // red
        case .b: return 0xffcc33      // yellow
        case .x: return 0x3399ff      // blue
        case .y: return 0x33cc66      // green
        case .l, .zl, .r, .zr: return 0x888899
        case .plus, .minus, .home: return 0xaaaaaa
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return 0xcccccc
        case .leftStick, .rightStick: return 0xdddddd
        }
    }

    var isStick: Bool { self == .leftStick || self == .rightStick }
    var isDpad: Bool {
        switch self {
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return true
        default: return false
        }
    }
}

/// Normalized relative position (0..1 within the screen's safe bounds).
struct TouchButtonConfig: Codable, Identifiable, Equatable {
    let id: TouchButtonID
    var relX: Double
    var relY: Double
    var size: Double     // in points (base diameter)
    var opacity: Double  // 0..1
    var enabled: Bool

    static func normalizedColor(from hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

@MainActor
class TouchLayout: ObservableObject {
    @Published var buttons: [TouchButtonConfig]
    @Published var overallOpacity: Double = 0.75

    private let key = "blockmash_touch_layout_v1"
    private let opacityKey = "blockmash_touch_overall_opacity"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TouchButtonConfig].self, from: data) {
            self.buttons = decoded
        } else {
            self.buttons = TouchLayout.defaultLayout()
        }
        if let o = UserDefaults.standard.object(forKey: opacityKey) as? Double {
            self.overallOpacity = o
        }
    }

    func binding(for id: TouchButtonID) -> Binding<TouchButtonConfig>? {
        guard let idx = buttons.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.buttons[idx] },
            set: { self.buttons[idx] = $0 }
        )
    }

    func config(for id: TouchButtonID) -> TouchButtonConfig? {
        buttons.first { $0.id == id }
    }

    func save() {
        if let data = try? JSONEncoder().encode(buttons) {
            UserDefaults.standard.set(data, forKey: key)
        }
        UserDefaults.standard.set(overallOpacity, forKey: opacityKey)
    }

    func resetToDefault() {
        buttons = TouchLayout.defaultLayout()
        overallOpacity = 0.75
        save()
    }

    static func defaultLayout() -> [TouchButtonConfig] {
        // Default landscape layout for iPhone 16 Pro.
        // Face buttons (right side, Switch layout: X top, Y left, A right, B bottom)
        let faceSize = 56.0
        let faceCX = 0.86
        let faceCY = 0.65
        let faceR = 0.075

        // D-pad (left side)
        let dpadSize = 46.0
        let dpadCX = 0.14
        let dpadCY = 0.65
        let dpadR = 0.065

        // Sticks
        let stickSize = 110.0

        return [
            // Face buttons (Nintendo Switch: X top, Y left, A right, B bottom)
            TouchButtonConfig(id: .x, relX: faceCX, relY: faceCY - faceR, size: faceSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .y, relX: faceCX - faceR * 1.5, relY: faceCY, size: faceSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .a, relX: faceCX + faceR * 1.5, relY: faceCY, size: faceSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .b, relX: faceCX, relY: faceCY + faceR, size: faceSize, opacity: 1, enabled: true),

            // D-pad
            TouchButtonConfig(id: .dpadUp, relX: dpadCX, relY: dpadCY - dpadR, size: dpadSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .dpadLeft, relX: dpadCX - dpadR * 1.5, relY: dpadCY, size: dpadSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .dpadRight, relX: dpadCX + dpadR * 1.5, relY: dpadCY, size: dpadSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .dpadDown, relX: dpadCX, relY: dpadCY + dpadR, size: dpadSize, opacity: 1, enabled: true),

            // Sticks
            TouchButtonConfig(id: .leftStick, relX: 0.12, relY: 0.32, size: stickSize, opacity: 1, enabled: true),
            TouchButtonConfig(id: .rightStick, relX: 0.88, relY: 0.32, size: stickSize, opacity: 1, enabled: true),

            // Shoulders / triggers
            TouchButtonConfig(id: .l, relX: 0.12, relY: 0.09, size: 60, opacity: 1, enabled: true),
            TouchButtonConfig(id: .r, relX: 0.88, relY: 0.09, size: 60, opacity: 1, enabled: true),
            TouchButtonConfig(id: .zl, relX: 0.22, relY: 0.09, size: 50, opacity: 1, enabled: true),
            TouchButtonConfig(id: .zr, relX: 0.78, relY: 0.09, size: 50, opacity: 1, enabled: true),

            // System buttons
            TouchButtonConfig(id: .minus, relX: 0.38, relY: 0.09, size: 36, opacity: 1, enabled: true),
            TouchButtonConfig(id: .plus, relX: 0.62, relY: 0.09, size: 36, opacity: 1, enabled: true),
            TouchButtonConfig(id: .home, relX: 0.5, relY: 0.95, size: 32, opacity: 1, enabled: false),
        ]
    }
}
