import SwiftUI
import UIKit

/// Live in-game touch overlay. Renders configurable buttons on top of a game.
/// Writes button states back to the shared ControllerManager so game code can react.
struct TouchOverlayView: View {
    @ObservedObject var layout: TouchLayout
    @ObservedObject var controllerManager: ControllerManager
    let editable: Bool

    @Binding var selectedID: TouchButtonID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(layout.buttons) { cfg in
                    if cfg.enabled {
                        buttonView(cfg: cfg, in: geo.size)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buttonView(cfg: TouchButtonConfig, in size: CGSize) -> some View {
        let center = CGPoint(x: cfg.relX * size.width, y: cfg.relY * size.height)
        let totalOpacity = cfg.opacity * layout.overallOpacity
        let selected = selectedID == cfg.id

        Group {
            if cfg.id.isStick {
                StickButton(cfg: cfg, totalOpacity: totalOpacity, selected: selected && editable) { vector in
                    updateStick(cfg.id, value: vector)
                }
            } else if cfg.id.isDpad {
                FaceButton(cfg: cfg, totalOpacity: totalOpacity, selected: selected && editable) { pressed in
                    updateDpad(cfg.id, pressed: pressed)
                }
            } else {
                FaceButton(cfg: cfg, totalOpacity: totalOpacity, selected: selected && editable) { pressed in
                    updateFace(cfg.id, pressed: pressed)
                }
            }
        }
        .position(center)
        .onTapGesture {
            if editable { selectedID = cfg.id }
        }
        .gesture(editable ? dragGesture(for: cfg, in: size) : nil)
    }

    private func dragGesture(for cfg: TouchButtonConfig, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard let binding = layout.binding(for: cfg.id) else { return }
                let newX = min(max(0.03, value.location.x / size.width), 0.97)
                let newY = min(max(0.03, value.location.y / size.height), 0.97)
                binding.wrappedValue.relX = newX
                binding.wrappedValue.relY = newY
                selectedID = cfg.id
            }
            .onEnded { _ in layout.save() }
    }

    // Dispatch button state updates (in-game mode only)
    private func updateFace(_ id: TouchButtonID, pressed: Bool) {
        guard !editable else { return }
        controllerManager.applyTouch(id: id, pressed: pressed)
    }

    private func updateDpad(_ id: TouchButtonID, pressed: Bool) {
        guard !editable else { return }
        controllerManager.applyTouch(id: id, pressed: pressed)
    }

    private func updateStick(_ id: TouchButtonID, value: SIMD2<Float>) {
        guard !editable else { return }
        controllerManager.applyStick(id: id, value: value)
    }
}

/// Round-ish single-press button.
struct FaceButton: View {
    let cfg: TouchButtonConfig
    let totalOpacity: Double
    let selected: Bool
    let onPressChange: (Bool) -> Void

    @State private var pressed = false

    var body: some View {
        let base = TouchButtonConfig.normalizedColor(from: cfg.id.tintHex)
        ZStack {
            Circle()
                .fill(base.opacity(pressed ? 0.85 : 0.35))
                .overlay(
                    Circle()
                        .stroke(selected ? Color.yellow : base.opacity(0.9), lineWidth: selected ? 3 : 1.5)
                )
            Text(cfg.id.label)
                .font(.system(size: cfg.size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: cfg.size, height: cfg.size)
        .opacity(totalOpacity)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        onPressChange(true)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in
                    pressed = false
                    onPressChange(false)
                }
        )
    }
}

/// Draggable analog thumb-stick.
struct StickButton: View {
    let cfg: TouchButtonConfig
    let totalOpacity: Double
    let selected: Bool
    let onChange: (SIMD2<Float>) -> Void

    @State private var thumbOffset: CGSize = .zero
    @State private var dragging = false

    var body: some View {
        let base = TouchButtonConfig.normalizedColor(from: cfg.id.tintHex)
        let radius = cfg.size / 2
        let thumbSize = cfg.size * 0.45

        ZStack {
            Circle()
                .fill(base.opacity(0.2))
                .overlay(
                    Circle()
                        .stroke(selected ? Color.yellow : base.opacity(0.6), lineWidth: selected ? 3 : 1.5)
                )
                .frame(width: cfg.size, height: cfg.size)

            Circle()
                .fill(base.opacity(0.7))
                .frame(width: thumbSize, height: thumbSize)
                .offset(thumbOffset)
        }
        .opacity(totalOpacity)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragging = true
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let dist = sqrt(dx * dx + dy * dy)
                    let maxDist = radius - thumbSize / 2
                    if dist > maxDist {
                        let scale = maxDist / dist
                        thumbOffset = CGSize(width: dx * scale, height: dy * scale)
                    } else {
                        thumbOffset = CGSize(width: dx, height: dy)
                    }
                    onChange(SIMD2(
                        Float(thumbOffset.width / maxDist),
                        Float(-thumbOffset.height / maxDist)
                    ))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        thumbOffset = .zero
                    }
                    dragging = false
                    onChange(.zero)
                }
        )
    }
}
