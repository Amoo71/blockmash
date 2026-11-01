import Foundation
import GameController
import Combine

struct NXButtonState {
    var a = false, b = false, x = false, y = false
    var l = false, r = false, zl = false, zr = false
    var plus = false, minus = false
    var dpadUp = false, dpadDown = false, dpadLeft = false, dpadRight = false
    var leftStick = SIMD2<Float>.zero
    var rightStick = SIMD2<Float>.zero
    var leftStickPress = false, rightStickPress = false
    var home = false, capture = false
}

@MainActor
class ControllerManager: ObservableObject {
    @Published var connectedControllers: [GCController] = []
    @Published var buttonState = NXButtonState()
    @Published var isVirtualControllerActive = false
    @Published var swapAB = false

    private var virtualController: GCVirtualController?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupNotifications()
        refreshControllers()
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.refreshControllers() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in self?.refreshControllers() }
            .store(in: &cancellables)
    }

    func refreshControllers() {
        connectedControllers = GCController.controllers()
        if let controller = connectedControllers.first {
            bindController(controller)
        }
    }

    private func bindController(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateState(from: gamepad)
            }
        }
    }

    private func updateState(from gamepad: GCExtendedGamepad) {
        var state = NXButtonState()

        if swapAB {
            state.a = gamepad.buttonB.isPressed
            state.b = gamepad.buttonA.isPressed
        } else {
            state.a = gamepad.buttonA.isPressed
            state.b = gamepad.buttonB.isPressed
        }

        state.x = gamepad.buttonX.isPressed
        state.y = gamepad.buttonY.isPressed
        state.l = gamepad.leftShoulder.isPressed
        state.r = gamepad.rightShoulder.isPressed
        state.zl = gamepad.leftTrigger.isPressed
        state.zr = gamepad.rightTrigger.isPressed

        state.plus = gamepad.buttonMenu.isPressed
        state.minus = gamepad.buttonOptions?.isPressed ?? false

        state.dpadUp = gamepad.dpad.up.isPressed
        state.dpadDown = gamepad.dpad.down.isPressed
        state.dpadLeft = gamepad.dpad.left.isPressed
        state.dpadRight = gamepad.dpad.right.isPressed

        state.leftStick = SIMD2(gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value)
        state.rightStick = SIMD2(gamepad.rightThumbstick.xAxis.value, gamepad.rightThumbstick.yAxis.value)

        state.leftStickPress = gamepad.leftThumbstickButton?.isPressed ?? false
        state.rightStickPress = gamepad.rightThumbstickButton?.isPressed ?? false

        if let home = gamepad.buttonHome { state.home = home.isPressed }

        buttonState = state
    }

    func startVirtualController() {
        let config = GCVirtualController.Configuration()
        config.elements = [
            GCInputLeftThumbstick, GCInputRightThumbstick,
            GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
            GCInputLeftShoulder, GCInputRightShoulder,
            GCInputLeftTrigger, GCInputRightTrigger
        ]

        let vc = GCVirtualController(configuration: config)
        vc.connect()
        virtualController = vc
        isVirtualControllerActive = true
    }

    func stopVirtualController() {
        virtualController?.disconnect()
        virtualController = nil
        isVirtualControllerActive = false
    }

    func applyTouch(id: TouchButtonID, pressed: Bool) {
        var state = buttonState
        switch id {
        case .a: swapAB ? (state.b = pressed) : (state.a = pressed)
        case .b: swapAB ? (state.a = pressed) : (state.b = pressed)
        case .x: state.x = pressed
        case .y: state.y = pressed
        case .l: state.l = pressed
        case .r: state.r = pressed
        case .zl: state.zl = pressed
        case .zr: state.zr = pressed
        case .plus: state.plus = pressed
        case .minus: state.minus = pressed
        case .home: state.home = pressed
        case .dpadUp: state.dpadUp = pressed
        case .dpadDown: state.dpadDown = pressed
        case .dpadLeft: state.dpadLeft = pressed
        case .dpadRight: state.dpadRight = pressed
        case .leftStick, .rightStick: break
        }
        buttonState = state
    }

    func applyStick(id: TouchButtonID, value: SIMD2<Float>) {
        var state = buttonState
        if id == .leftStick { state.leftStick = value }
        if id == .rightStick { state.rightStick = value }
        buttonState = state
    }
}
