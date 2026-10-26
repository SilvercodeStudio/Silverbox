import AppKit

/// A progress bar on the Dock tile while something long runs, so the user
/// can switch away and still see how far it has come.
enum DockProgress {
    private static let view = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    static func update(fraction: Double) {
        let tile = NSApplication.shared.dockTile
        view.fraction = min(max(fraction, 0), 1)
        if tile.contentView !== view { tile.contentView = view }
        tile.display()
    }

    static func clear() {
        let tile = NSApplication.shared.dockTile
        guard tile.contentView != nil else { return }
        tile.contentView = nil
        tile.display()
    }
}

/// The app icon with a thin bar along its bottom edge.
private final class DockProgressView: NSView {
    var fraction = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApplication.shared.applicationIconImage.draw(in: bounds)
        let inset = bounds.width * 0.14
        let height = bounds.height * 0.07
        let track = NSRect(x: inset, y: bounds.height * 0.06, width: bounds.width - inset * 2, height: height)
        let radius = height / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        var fill = track.insetBy(dx: 1.5, dy: 1.5)
        fill.size.width = max(fill.height, fill.width * fraction)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
    }
}
