#if DEBUG
    import SilverboxCore
    import AppKit
    import Foundation

    /// Debug aid: launch with `-screenshotPath /tmp/shot.png [-screenshotDelay 8]`
    /// to render the main window to a PNG after the library loads, then quit.
    /// Rendering is done from the view hierarchy, so it needs no screen
    /// recording permission. `-keyPresses "down down space"` presses keys
    /// after the delay, also without a screenshot path, and `-windowSize
    /// 1320x840` gives the main window that size: both for the site's
    /// screenshot scenes (`make site-shots`), which the user captures with
    /// the window's own frame and corners.
    enum DebugScreenshot {
        private static var scheduled = false

        static func scheduleIfRequested(model: AppModel) {
            guard !scheduled else { return }
            scheduled = true
            resizeMainWindowIfRequested()
            navigateIfRequested(model: model)
            let path = UserDefaults.standard.string(forKey: "screenshotPath") ?? ""
            // `-keyPresses "down down space"` presses keys first, to test navigation.
            let presses = (UserDefaults.standard.string(forKey: "keyPresses") ?? "")
                .split(separator: " ").compactMap { KeyPress.Key.parse(String($0)) }
            guard !path.isEmpty || !presses.isEmpty else { return }
            let configured = UserDefaults.standard.double(forKey: "screenshotDelay")
            let delay = configured > 0 ? configured : 8
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
                guard !path.isEmpty else { return }
                scrollIfRequested()
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

        /// `-navigate "back forward up"`: moves in the window's history after the delay, a step
        /// every 0.4 seconds: Back, Forward, and `up` for Back to Library. Menu shortcuts do not
        /// reach an app that is not in front, so `-keyPresses` cannot do this.
        private static func navigateIfRequested(model: AppModel) {
            let steps = (UserDefaults.standard.string(forKey: "navigate") ?? "").split(separator: " ")
            guard !steps.isEmpty else { return }
            let configured = UserDefaults.standard.double(forKey: "screenshotDelay")
            for (offset, step) in steps.enumerated() {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + (configured > 0 ? configured : 8) + 0.4 * Double(offset)
                ) {
                    switch step {
                    case "back": model.navigateBack()
                    case "forward": model.navigateForward()
                    case "up": model.closeGamePage()
                    default: break
                    }
                }
            }
        }

        /// `-windowSize 1320x840`: the main window's size in points, centered on its screen. It
        /// waits a moment, so the window has its restored frame first. The main window is the
        /// largest one at that time.
        private static func resizeMainWindowIfRequested() {
            let parts = (UserDefaults.standard.string(forKey: "windowSize") ?? "").split(separator: "x")
            guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard
                    let window = NSApp.windows.filter({ $0.isVisible && !($0 is NSPanel) })
                        .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
                else { return }
                window.setContentSize(NSSize(width: width, height: height))
                window.center()
            }
        }

        /// `-screenshotScroll 0.5`: scrolls the largest scroll view of each window but the main
        /// one that far down (1 is the end), to show the lower part of a long Settings tab.
        private static func scrollIfRequested() {
            let fraction = UserDefaults.standard.double(forKey: "screenshotScroll")
            guard fraction > 0 else { return }
            for window in NSApp.windows.dropFirst() where window.isVisible {
                guard let content = window.contentView,
                    let scroll = scrollViews(in: content).max(by: { $0.frame.height < $1.frame.height }),
                    let document = scroll.documentView
                else { continue }
                let range = max(0, document.frame.height - scroll.contentView.bounds.height)
                let y = document.isFlipped ? range * fraction : range * (1 - fraction)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
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
