import AppKit

/// Synthesizes a key press and sends it to the key window, so a game
/// controller drives the same handlers as the keyboard: the grid's arrow
/// keys, a sheet's default button, the Quick Look panel.
enum KeyPress {
    struct Key: Equatable {
        let code: UInt16
        let characters: String
        /// Flags a real press of this key carries, such as `.function` for arrows.
        var flags: NSEvent.ModifierFlags = []

        static let up = Key(functionKey: NSUpArrowFunctionKey, code: 126, flags: [.function, .numericPad])
        static let down = Key(functionKey: NSDownArrowFunctionKey, code: 125, flags: [.function, .numericPad])
        static let left = Key(functionKey: NSLeftArrowFunctionKey, code: 123, flags: [.function, .numericPad])
        static let right = Key(functionKey: NSRightArrowFunctionKey, code: 124, flags: [.function, .numericPad])
        static let home = Key(functionKey: NSHomeFunctionKey, code: 115, flags: .function)
        static let end = Key(functionKey: NSEndFunctionKey, code: 119, flags: .function)
        static let pageUp = Key(functionKey: NSPageUpFunctionKey, code: 116, flags: .function)
        static let pageDown = Key(functionKey: NSPageDownFunctionKey, code: 121, flags: .function)
        static let `return` = Key(code: 36, characters: "\r")
        static let escape = Key(code: 53, characters: "\u{1B}")
        static let space = Key(code: 49, characters: " ")
        static let d = Key(code: 2, characters: "d")
        static let y = Key(code: 16, characters: "y")
        static let one = Key(code: 18, characters: "1")
        static let two = Key(code: 19, characters: "2")

        init(code: UInt16, characters: String) {
            self.code = code
            self.characters = characters
        }

        init(functionKey: Int, code: UInt16, flags: NSEvent.ModifierFlags) {
            self.init(code: code, characters: String(Character(UnicodeScalar(UInt32(functionKey))!)))
            self.flags = flags
        }

        /// Names accepted by the `-keyPresses` debug argument, such as
        /// `down`, `opt-right` or `cmd-y`.
        static func parse(_ token: String) -> (Key, NSEvent.ModifierFlags)? {
            var modifiers: NSEvent.ModifierFlags = []
            var parts = token.lowercased().split(separator: "-").map(String.init)
            guard let name = parts.popLast() else { return nil }
            for part in parts {
                switch part {
                case "cmd", "command": modifiers.insert(.command)
                case "opt", "option", "alt": modifiers.insert(.option)
                case "shift": modifiers.insert(.shift)
                case "ctrl", "control": modifiers.insert(.control)
                default: return nil
                }
            }
            let keys: [String: Key] = [
                "up": .up, "down": .down, "left": .left, "right": .right, "home": .home, "end": .end,
                "pageup": .pageUp, "pagedown": .pageDown, "return": .return, "enter": .return, "escape": .escape,
                "esc": .escape, "space": .space, "d": .d, "y": .y, "1": .one, "2": .two,
            ]
            return keys[name].map { ($0, modifiers) }
        }
    }

    /// Sends a key down and key up to the key window. Nothing happens while
    /// another app is in front, unless `force` is set, which the debug
    /// harness uses to drive the main window from a script.
    static func send(_ key: Key, modifiers: NSEvent.ModifierFlags = [], force: Bool = false) {
        let target =
            force ? (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }) : NSApp.keyWindow
        guard force || NSApp.isActive, let window = target else { return }
        if force, !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers.union(key.flags),
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: key.characters, charactersIgnoringModifiers: key.characters, isARepeat: false,
                    keyCode: key.code)
            else { continue }
            // An inactive app (the debug harness) skips menu matching, so do it here.
            if force, !NSApp.isActive, type == .keyDown, !modifiers.isDisjoint(with: [.command, .option]),
                NSApp.mainMenu?.performKeyEquivalent(with: event) == true
            {
                continue
            }
            // Event monitors only see queued events, so Control-Return is checked here.
            if type == .keyDown, ContextMenuKey.handle(event) { continue }
            // Through the app, so menu key equivalents are matched as well.
            NSApp.sendEvent(event)
        }
    }
}
