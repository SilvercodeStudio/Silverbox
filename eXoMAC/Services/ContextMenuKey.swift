import AppKit

/// Control-Return, the macOS key for a context menu, on the game grid.
///
/// AppKit shows the focused view's menu for the point under its
/// `selectionAnchorRect`. SwiftUI's grid does not report one, so AppKit
/// uses the middle of the grid and shows the menu of whatever tile is
/// there. Here the key is caught first and turned into a right-click on
/// the selected tile, so its own context menu opens beside it. Elsewhere
/// (the list, the sidebar, text fields) the key keeps its usual behaviour.
@MainActor
enum ContextMenuKey {
    private weak static var model: AppModel?
    private static var monitor: Any?

    static func install(for model: AppModel) {
        self.model = model
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    /// Opens the selected tile's menu for Control-Return while the grid has
    /// focus. Returns false when the key is not handled here.
    static func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76,
            event.modifierFlags.intersection([.command, .option, .shift, .control]) == .control,
            let model, model.gridFocused, let window = event.window ?? NSApp.keyWindow
        else { return false }
        if let point = selectedTileCenter(in: window) {
            rightClick(at: point, in: window)
        } else if model.selectedGameID != nil {
            // The tile is scrolled out of view: bring it in, then try once more.
            model.revealSelectionRequest += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let point = selectedTileCenter(in: window) { rightClick(at: point, in: window) }
            }
        }
        return true
    }

    /// The middle of the selected tile in window coordinates, when the tile
    /// is inside the visible part of the grid.
    private static func selectedTileCenter(in window: NSWindow) -> NSPoint? {
        guard let model, let tile = model.selectedTileFrame, tile.id == model.selectedGameID,
            let grid = model.gridFrame, let content = window.contentView
        else { return nil }
        let center = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
        guard grid.contains(center) else { return nil }
        // SwiftUI's global space has its origin at the top left of the content view.
        let local = content.isFlipped ? center : CGPoint(x: center.x, y: content.bounds.height - center.y)
        return content.convert(local, to: nil)
    }

    private static func rightClick(at point: NSPoint, in window: NSWindow) {
        guard
            let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)
        else { return }
        window.sendEvent(event)
    }
}
