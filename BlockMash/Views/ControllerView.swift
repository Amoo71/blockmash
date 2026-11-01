import SwiftUI
import GameController

struct ControllerView: View {
    @EnvironmentObject var controllerManager: ControllerManager
    @EnvironmentObject var touchLayout: TouchLayout
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingEditor = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "dpad.fill")
                                .font(.title)
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Edit Touch Controller")
                                    .font(.body.bold())
                                Text("Drag • resize • opacity per button")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Buttons appear during gameplay when no physical controller is connected.")
                }

                Section("Physical Controllers") {
                    if controllerManager.connectedControllers.isEmpty {
                        HStack {
                            Image(systemName: "gamecontroller")
                                .foregroundStyle(.secondary)
                            Text("None connected")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(controllerManager.connectedControllers, id: \.vendorName) { c in
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                    .foregroundStyle(.green)
                                Text(c.vendorName ?? "Controller")
                                Spacer()
                                if let battery = c.battery {
                                    Text(batteryLabel(battery))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button {
                        controllerManager.refreshControllers()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                Section("Mapping") {
                    Toggle("Swap A/B (Nintendo layout)", isOn: $controllerManager.swapAB)
                }
            }
            .navigationTitle("Controller")
            .fullScreenCover(isPresented: $showingEditor) {
                ControllerLayoutEditor()
                    .environmentObject(touchLayout)
                    .environmentObject(controllerManager)
            }
        }
    }

    private func batteryLabel(_ b: GCDeviceBattery) -> String {
        "\(Int(b.batteryLevel * 100))%"
    }
}
