import AppKit
import SwiftUI

/// Back and Forward from the mouse and the arrow keys, in the library
/// window: mouse buttons 4 and 5, and Command-Left and Command-Right
/// (Command-[ and Command-] are menu shortcuts). The view only finds the
/// window; a monitor takes the events meant for it. Typing keeps
/// Command-Left and Command-Right, which move the caret in the search field.
struct HistoryKeys: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView { KeyView(model: model) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class KeyView: NSView {
        private let model: AppModel
        private var monitor: Any?

        init(model: AppModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
            }
        }

        /// True when the event moved in the history, and so is used up. A
        /// sheet over the window is another window, and keeps its events.
        private func handle(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, model.hasGamesToBrowse else { return false }
            // Buttons 4 and 5 of a mouse are numbered 3 and 4, from 0.
            if event.type == .otherMouseDown {
                switch event.buttonNumber {
                case 3 where model.canNavigateBack: model.navigateBack()
                case 4 where model.canNavigateForward: model.navigateForward()
                default: return false
                }
                return true
            }
            guard
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
                    == .command,
                !(window.firstResponder is NSText)
            else { return false }
            switch event.keyCode {
            case 123 where model.canNavigateBack: model.navigateBack()
            case 124 where model.canNavigateForward: model.navigateForward()
            default: return false
            }
            return true
        }
    }
}
