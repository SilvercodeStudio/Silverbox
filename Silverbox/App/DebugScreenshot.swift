#if DEBUG
    import SilverboxCore
    import AppKit
    import Foundation

    /// Debug aid: launch with `-screenshotPath /tmp/shot.png [-screenshotDelay 8]`
    /// to render the main window to a PNG after the library loads, then quit.
    /// Rendering is done from the view hierarchy, so it needs no screen
    /// recording permission.
    enum DebugScreenshot {
        private static var scheduled = false

        static func scheduleIfRequested() {
            guard !scheduled, let path = UserDefaults.standard.string(forKey: "screenshotPath"), !path.isEmpty else {
                return
            }
            scheduled = true
            let configured = UserDefaults.standard.double(forKey: "screenshotDelay")
            let delay = configured > 0 ? configured : 8
            // `-keyPresses "down down space"` presses keys first, to test navigation.
            let presses = (UserDefaults.standard.string(forKey: "keyPresses") ?? "")
                .split(separator: " ").compactMap { KeyPress.Key.parse(String($0)) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.activate()
                for (offset, press) in presses.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(offset)) {
                        let window = NSApp.keyWindow ?? NSApp.mainWindow
                        let responder = window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
                        FileHandle.standardError.write(
                            Data(
                                "keypress: \(press.0.characters.unicodeScalars.first?.value ?? 0) active=\(NSApp.isActive) window=\(window?.title ?? "none") responder=\(responder)\n"
                                    .utf8))
                        KeyPress.send(press.0, modifiers: press.1, force: true)
                    }
                }
                // `-screenshotSettle 90` waits longer after the keys, for a job they start.
                let settle = UserDefaults.standard.double(forKey: "screenshotSettle")
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.25 * Double(presses.count) + (settle > 0 ? settle : 1.5)
                ) {
                    capture(to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            }
        }

        /// Renders every visible window: the first to `url`, the others (sheets,
        /// panels) to `<name>-2.png`, `<name>-3.png` and so on.
        static func capture(to url: URL) {
            let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil && $0.frame.width > 100 }
            guard !windows.isEmpty else {
                FileHandle.standardError.write(Data("screenshot: no visible window\n".utf8))
                return
            }
            for (offset, window) in windows.enumerated() {
                guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let target =
                    offset == 0
                    ? url
                    : url.deletingPathExtension().appendingPathExtension("\(offset + 1).png")
                do {
                    try data.write(to: target)
                    FileHandle.standardError.write(
                        Data(
                            "screenshot: wrote \(target.path) (\(rep.pixelsWide)x\(rep.pixelsHigh)) \(window.title)\n"
                                .utf8))
                } catch {
                    FileHandle.standardError.write(Data("screenshot: \(error)\n".utf8))
                }
            }
        }
    }
#endif
