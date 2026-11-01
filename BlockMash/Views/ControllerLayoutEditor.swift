import SwiftUI

struct ControllerLayoutEditor: View {
    @EnvironmentObject var layout: TouchLayout
    @EnvironmentObject var controllerManager: ControllerManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: TouchButtonID?

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            // Preview grid
            gridBackground
                .ignoresSafeArea()

            // Live buttons (editable)
            TouchOverlayView(
                layout: layout,
                controllerManager: controllerManager,
                editable: true,
                selectedID: $selectedID
            )
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if let id = selectedID, let cfg = layout.config(for: id) {
                    buttonInspector(for: cfg)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .statusBarHidden()
        .onDisappear { layout.save() }
    }

    private var gridBackground: some View {
        GeometryReader { geo in
            Path { p in
                let step = min(geo.size.width, geo.size.height) / 20
                for x in stride(from: 0.0, through: geo.size.width, by: step) {
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for y in stride(from: 0.0, through: geo.size.height, by: step) {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(.green.opacity(0.9))
                    .clipShape(Capsule())
            }

            Spacer()

            Menu {
                Button("Reset to default", role: .destructive) {
                    layout.resetToDefault()
                    selectedID = nil
                }
                ForEach(TouchButtonID.allCases) { id in
                    if let bind = layout.binding(for: id) {
                        Button {
                            bind.wrappedValue.enabled.toggle()
                            layout.save()
                        } label: {
                            Label(
                                "\(bind.wrappedValue.enabled ? "Hide" : "Show") \(id.label)",
                                systemImage: bind.wrappedValue.enabled ? "eye.slash" : "eye"
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
        }
        .padding()
    }

    @ViewBuilder
    private func buttonInspector(for cfg: TouchButtonConfig) -> some View {
        if let bind = layout.binding(for: cfg.id) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(cfg.id.label)
                        .font(.title2.bold())
                    Spacer()
                    Toggle("Enabled", isOn: bind.enabled)
                        .onChange(of: bind.wrappedValue.enabled) { _, _ in layout.save() }
                }

                row(icon: "arrow.up.left.and.arrow.down.right", label: "Size") {
                    Slider(value: bind.size, in: 28...180, step: 1)
                        .onChange(of: bind.wrappedValue.size) { _, _ in layout.save() }
                    Text("\(Int(bind.wrappedValue.size))")
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }

                row(icon: "circle.lefthalf.filled", label: "Opacity") {
                    Slider(value: bind.opacity, in: 0.1...1.0)
                        .onChange(of: bind.wrappedValue.opacity) { _, _ in layout.save() }
                    Text("\(Int(bind.wrappedValue.opacity * 100))%")
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }

                Divider().overlay(Color.white.opacity(0.2))

                HStack(spacing: 12) {
                    Image(systemName: "square.3.layers.3d")
                        .foregroundStyle(.secondary)
                    Text("All buttons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $layout.overallOpacity, in: 0.1...1.0)
                        .onChange(of: layout.overallOpacity) { _, _ in layout.save() }
                    Text("\(Int(layout.overallOpacity * 100))%")
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }
                .padding(.top, 4)

                HStack {
                    Spacer()
                    Text("Drag the \(cfg.id.label) button to move")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func row<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .frame(width: 70, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
