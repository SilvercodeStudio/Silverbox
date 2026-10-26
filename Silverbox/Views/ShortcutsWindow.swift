import SwiftUI
import SilverboxCore

/// The keyboard and controller maps, as shown by the Keyboard Shortcuts
/// window (Help › Keyboard Shortcuts, Cmd-/). Help page 07 has the same maps
/// in prose; keep both in step with `AppCommands` and `GamepadInput`.
enum ShortcutReference {
    struct Entry: Identifiable {
        let keys: String
        let action: String
        var id: String { keys }
    }

    static let keyboard: [Entry] = [
        Entry(keys: "↑ ↓ ← →", action: "Move between games"),
        Entry(keys: "Home, End", action: "First or last game"),
        Entry(keys: "Page Up, Page Down", action: "Jump four rows"),
        Entry(keys: "↩", action: "Play, or Install"),
        Entry(keys: "⌃↩", action: "Open the game's context menu"),
        Entry(keys: "⌥← ⌥→", action: "Previous or next image"),
        Entry(keys: "Space, ⌘Y", action: "Quick Look the current image or video"),
        Entry(keys: "⇧⌘Y", action: "Quick Look the manual"),
        Entry(keys: "⌥⌘Y", action: "Quick Look the extras"),
        Entry(keys: "⌘↓ ⌘↑", action: "Open the game page, and back"),
        Entry(keys: "⌘F", action: "Search games"),
        Entry(keys: "⌘D", action: "Add to or remove from Favorites"),
        Entry(keys: "⌘↩", action: "Play"),
        Entry(keys: "⇧⌘↩", action: "Configure…"),
        Entry(keys: "⌘I", action: "Edit game info"),
        Entry(keys: "⌘⌫", action: "Uninstall…"),
        Entry(keys: "⇧⌘R", action: "Show the game in the Finder"),
        Entry(keys: "⌘R", action: "Rescan the library"),
        Entry(keys: "⌘+ ⌘− ⌘0", action: "Larger, smaller or default tiles"),
        Entry(keys: "⌘1 ⌘2", action: "Grid or list"),
        Entry(keys: "⌥⌘I", action: "Show or hide the inspector"),
        Entry(keys: "⇧⌘P", action: "Pause or play the music or album"),
        Entry(keys: "⌥⌘← ⌥⌘→", action: "Previous or next album track"),
        Entry(keys: "⌘.", action: "Stop the album"),
        Entry(keys: "Esc", action: "Close the panel or page; clear the search"),
        Entry(keys: "⌘/", action: "This window"),
    ]

    static let controller: [Entry] = [
        Entry(keys: "D-pad, left stick", action: "Move between games; hold to repeat"),
        Entry(keys: "✕ / A", action: "Play, or the default button of a dialog"),
        Entry(keys: "○ / B", action: "Back: close the panel, page or dialog"),
        Entry(keys: "□ / X", action: "Quick Look the current image or video"),
        Entry(keys: "△ / Y", action: "Open the game page, or come back"),
        Entry(keys: "L1 R1 / LB RB", action: "Previous or next image"),
        Entry(keys: "L2 R2 / LT RT", action: "Page up or down"),
        Entry(keys: "Options / Menu", action: "Configure…"),
        Entry(keys: "Create / View", action: "Add to or remove from Favorites"),
        Entry(keys: "D-pad in Quick Look", action: "Page through images, manual and extras"),
    ]
}

/// A compact, dismissable card of the shortcuts: Escape, Cmd-/ again or the
/// controller's back button closes it.
struct ShortcutsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 32) {
                column("Keyboard", ShortcutReference.keyboard)
                column("Controller", ShortcutReference.controller)
            }
            HStack {
                Text("The full story is in Help › Keyboard and Controller.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Done") { dismissWindow(id: "shortcuts") }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 800)
        .background(Theme.window)
        .onAppear { model.shortcutsShown = true }
        .onDisappear { model.shortcutsShown = false }
    }

    private func column(_ title: String, _ entries: [ShortcutReference.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(entries) { entry in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(entry.keys)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 4))
                        Text(entry.action)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
