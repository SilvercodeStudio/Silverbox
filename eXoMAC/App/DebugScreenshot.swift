#if DEBUG
import AppKit
import Foundation

/// Debug aid: launch with `-screenshotPath /tmp/shot.png [-screenshotDelay 8]`
/// to render the main window to a PNG after the library loads, then quit.
/// Rendering is done from the view hierarchy, so it needs no screen
/// recording permission.
enum DebugScreenshot {
    private static var scheduled = false

    static func scheduleIfRequested() {
        guard !scheduled, let path = UserDefaults.standard.string(forKey: "screenshotPath"), !path.isEmpty else { return }
        scheduled = true
        let configured = UserDefaults.standard.double(forKey: "screenshotDelay")
        let delay = configured > 0 ? configured : 8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("screenshot: no visible window\n".utf8))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            FileHandle.standardError.write(Data("screenshot: wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("screenshot: \(error)\n".utf8))
        }
    }
}
#endif
