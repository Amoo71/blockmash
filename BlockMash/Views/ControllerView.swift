import SwiftUI
import GameController

struct ControllerView: View {
    @EnvironmentObject var controllerManager: ControllerManager
    @State private var showingMapping = false

    var body: some View {
        NavigationStack {
            List {
                connectedSection
                virtualSection
                buttonTestSection
                mappingSection
            }
            .navigationTitle("Controller")
        }
    }

    private var connectedSection: some View {
        Section {
            if controllerManager.connectedControllers.isEmpty {
                HStack {
                    Image(systemName: "gamecontroller")
                        .foregroundStyle(.secondary)
                    Text("No controller connected")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(controllerManager.connectedControllers, id: \.vendorName) { controller in
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(controller.vendorName ?? "Controller")
                                .font(.body.bold())
                            if let battery = controller.battery {
                                Text("Battery: \(batteryLabel(battery))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Button {
                controllerManager.refreshControllers()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Physical Controllers")
        } footer: {
            Text("Connect a Bluetooth controller (DualSense, Xbox, Pro Controller, etc.) via iOS Settings.")
        }
    }

    private var virtualSection: some View {
        Section {
            Toggle("On-Screen Controller", isOn: Binding(
                get: { controllerManager.isVirtualControllerActive },
                set: { newValue in
                    if newValue {
                        controllerManager.startVirtualController()
                    } else {
                        controllerManager.stopVirtualController()
                    }
                }
            ))
        } header: {
            Text("Virtual Controller")
        } footer: {
            Text("Shows touch controls on screen when no physical controller is connected.")
        }
    }

    private var buttonTestSection: some View {
        Section("Button Test") {
            let state = controllerManager.buttonState
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()),
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 8) {
                ButtonIndicator(label: "A", active: state.a, color: .green)
                ButtonIndicator(label: "B", active: state.b, color: .red)
                ButtonIndicator(label: "X", active: state.x, color: .blue)
                ButtonIndicator(label: "Y", active: state.y, color: .yellow)
                ButtonIndicator(label: "L", active: state.l, color: .gray)
                ButtonIndicator(label: "R", active: state.r, color: .gray)
                ButtonIndicator(label: "ZL", active: state.zl, color: .gray)
                ButtonIndicator(label: "ZR", active: state.zr, color: .gray)
            }
            .padding(.vertical, 4)

            HStack {
                VStack {
                    Text("L Stick")
                        .font(.caption2)
                    Text(String(format: "%.1f, %.1f", state.leftStick.x, state.leftStick.y))
                        .font(.caption.monospaced())
                }
                Spacer()
                VStack {
                    Text("R Stick")
                        .font(.caption2)
                    Text(String(format: "%.1f, %.1f", state.rightStick.x, state.rightStick.y))
                        .font(.caption.monospaced())
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private var mappingSection: some View {
        Section("Button Mapping") {
            Toggle("Swap A/B (Nintendo layout)", isOn: $controllerManager.swapAB)
        }
    }

    private func batteryLabel(_ battery: GCDeviceBattery) -> String {
        let pct = Int(battery.batteryLevel * 100)
        let state: String
        switch battery.batteryState {
        case .charging: state = ", charging"
        case .full: state = ", full"
        default: state = ""
        }
        return "\(pct)%\(state)"
    }
}

struct ButtonIndicator: View {
    let label: String
    let active: Bool
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .frame(width: 40, height: 40)
            .background(active ? color : Color(.systemGray5))
            .foregroundStyle(active ? .white : .secondary)
            .clipShape(Circle())
    }
}
