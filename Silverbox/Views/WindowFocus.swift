import AppKit
import SwiftUI

/// Takes the keyboard focus off the first control when a window or a sheet
/// opens. With keyboard navigation on in System Settings, macOS gives the
/// first button or link a focus ring at once, which reads as a second
/// selection beside the default button. Tab still starts at the first
/// control.
private struct InitialFocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClearingView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class ClearingView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            clear(window)
            // The window picks its first control when it first becomes key, which can be later.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stopObserving()
                    if let window = self.window { self.clear(window) }
                }
            }
        }

        private func clear(_ window: NSWindow) {
            DispatchQueue.main.async { [weak window] in
                // A text field the user is to type in keeps the focus.
                guard let window, !(window.firstResponder is NSText) else { return }
                window.makeFirstResponder(nil)
            }
        }

        private func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}

extension View {
    /// Opens the window or sheet with no control in focus.
    func withoutInitialFocus() -> some View {
        background(InitialFocusClearer().frame(width: 0, height: 0))
    }

    /// A link in the accent colour, as the app's other actions are.
    func accentLink() -> some View {
        foregroundStyle(Theme.accent)
    }
}
