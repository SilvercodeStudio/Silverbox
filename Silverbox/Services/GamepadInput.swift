import AppKit
import GameController
import Observation

/// Lets a game controller browse the library. Every button becomes the key
/// press it stands for, so the grid, the list, sheets and the Quick Look
/// panel react exactly as they do to the keyboard. Input is only read while
/// this app is in front, so a running game keeps the controller to itself.
@Observable
final class GamepadInput {
    /// Names of the controllers connected right now, for Settings.
    private(set) var controllerNames: [String] = []

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var repeatTask: Task<Void, Never>?
    @ObservationIgnored private var heldDirection: KeyPress.Key?

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshControllers() }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshControllers() }
            },
        ]
        refreshControllers()
    }

    private func refreshControllers() {
        let controllers = GCController.controllers()
        controllerNames = controllers.map { $0.vendorName ?? "Game controller" }
        for controller in controllers {
            attach(controller)
        }
    }

    private func attach(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main

        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in self?.direction(x: x, y: y) }
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in self?.direction(x: x, y: y) }
        }
        press(gamepad.buttonA) { KeyPress.send(.return) }
        press(gamepad.buttonB) { KeyPress.send(.escape) }
        press(gamepad.buttonX) { KeyPress.send(.space) }
        press(gamepad.buttonY) { [weak self] in
            // Open the game page, or come back from it.
            KeyPress.send(self?.model?.openedGameID == nil ? .down : .up, modifiers: .command)
        }
        press(gamepad.leftShoulder) { KeyPress.send(.left, modifiers: .option) }
        press(gamepad.rightShoulder) { KeyPress.send(.right, modifiers: .option) }
        press(gamepad.leftTrigger) { KeyPress.send(.pageUp) }
        press(gamepad.rightTrigger) { KeyPress.send(.pageDown) }
        press(gamepad.buttonMenu) { KeyPress.send(.return, modifiers: [.command, .shift]) }
        press(gamepad.buttonOptions) { KeyPress.send(.d, modifiers: .command) }
    }

    private func press(_ button: GCControllerButtonInput?, action: @escaping @MainActor () -> Void) {
        button?.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in action() }
        }
    }

    /// The D-pad or stick moved: press the arrow once, then repeat while held.
    private func direction(x: Float, y: Float) {
        let key: KeyPress.Key?
        if abs(x) < 0.5, abs(y) < 0.5 {
            key = nil
        } else if abs(x) > abs(y) {
            key = x > 0 ? .right : .left
        } else {
            key = y > 0 ? .up : .down
        }
        guard key != heldDirection else { return }
        heldDirection = key
        repeatTask?.cancel()
        guard let key else { return }
        KeyPress.send(key)
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            while !Task.isCancelled, self?.heldDirection == key {
                KeyPress.send(key)
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }
}
