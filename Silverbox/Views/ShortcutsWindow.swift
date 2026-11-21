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

    struct KeyGroup: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    /// A controller button under its PlayStation and its Xbox name.
    struct ControllerButton: Identifiable {
        let playStation: String
        let xbox: String
        let action: String
        var id: String { playStation }

        /// The connected controller's name for the button, or both names.
        func keys(_ names: GamepadInput.ButtonNames) -> String {
            switch names {
            case .playStation: playStation
            case .xbox: xbox
            case .both: playStation == xbox ? xbox : "\(playStation) / \(xbox)"
            }
        }
    }

    static let keyboard: [KeyGroup] = [
        KeyGroup(
            title: "Browsing",
            entries: [
                Entry(keys: "↑ ↓ ← →", action: "Move between games"),
                Entry(keys: "Home, End", action: "First or last game"),
                Entry(keys: "Page Up, Page Down", action: "Jump four rows"),
                Entry(keys: "⌘F", action: "Search games"),
                Entry(keys: "⌘↑", action: "Back to the library from a game page"),
                Entry(keys: "⌘[ ⌘]", action: "Back and Forward (also ⌘← ⌘→)"),
                Entry(keys: "Esc", action: "Close the panel or page; clear the search"),
            ]),
        KeyGroup(
            title: "Game",
            entries: [
                Entry(keys: "↩", action: "Play, or Install"),
                Entry(keys: "⌘↩", action: "Play"),
                Entry(keys: "⇧⌘↩", action: "Configure…"),
                Entry(keys: "⌘↓", action: "Open the game page"),
                Entry(keys: "⌘I", action: "Edit game info"),
                Entry(keys: "⌘D", action: "Add to or remove from Favorites"),
                Entry(keys: "⌘⌫", action: "Uninstall…"),
                Entry(keys: "⇧⌘R", action: "Show the game in the Finder"),
                Entry(keys: "⌃↩", action: "Open the game's context menu"),
            ]),
        KeyGroup(
            title: "Media",
            entries: [
                Entry(keys: "⌥← ⌥→", action: "Previous or next image"),
                Entry(keys: "Space, ⌘Y", action: "Quick Look the image or video"),
                Entry(keys: "⇧⌘Y", action: "Quick Look the manual"),
                Entry(keys: "⌥⌘Y", action: "Quick Look the extras"),
            ]),
        KeyGroup(
            title: "Music",
            entries: [
                Entry(keys: "⇧⌘P", action: "Pause or play the music or album"),
                Entry(keys: "⌥⌘← ⌥⌘→", action: "Previous or next album track"),
                Entry(keys: "⌘.", action: "Stop the album"),
            ]),
        KeyGroup(
            title: "View",
            entries: [
                Entry(keys: "⌘1 ⌘2", action: "Grid or list"),
                Entry(keys: "⌘+ ⌘− ⌘0", action: "Larger, smaller or default tiles"),
                Entry(keys: "⌥⌘I", action: "Show or hide the inspector"),
                Entry(keys: "⌘R", action: "Rescan the library"),
                Entry(keys: "⌘/", action: "This window"),
            ]),
    ]

    static let controller: [ControllerButton] = [
        ControllerButton(playStation: "D-pad, left stick", xbox: "D-pad, left stick", action: "Move between games"),
        ControllerButton(playStation: "✕", xbox: "A", action: "Play, or a dialog's default button"),
        ControllerButton(playStation: "○", xbox: "B", action: "Back: close the panel, page or dialog"),
        ControllerButton(playStation: "□", xbox: "X", action: "Quick Look the image or video"),
        ControllerButton(playStation: "△", xbox: "Y", action: "Open the game page, or come back"),
        ControllerButton(playStation: "L1 R1", xbox: "LB RB", action: "Previous or next image"),
        ControllerButton(playStation: "L2 R2", xbox: "LT RT", action: "Page up or down"),
        ControllerButton(playStation: "Options", xbox: "Menu", action: "Configure…"),
        ControllerButton(playStation: "Create", xbox: "View", action: "Add to or remove from Favorites"),
        ControllerButton(
            playStation: "D-pad in Quick Look", xbox: "D-pad in Quick Look",
            action: "Page through images, manual and extras"),
    ]
}

/// A compact, dismissable card of the shortcuts, grouped by what they act
/// on: Return, Escape, Cmd-/ again or the controller's back button closes
/// it. The controller's buttons have the names of the one that is connected.
struct ShortcutsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let groups = ShortcutReference.keyboard
        let names = model.gamepad.buttonNames
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 28) {
                column(groups.prefix(2).map { ($0.title, $0.entries) })
                column(groups.dropFirst(2).map { ($0.title, $0.entries) })
                column([
                    (
                        "Controller",
                        ShortcutReference.controller.map {
                            ShortcutReference.Entry(keys: $0.keys(names), action: $0.action)
                        }
                    )
                ])
            }
            HStack {
                Text("The full story is in Help › Keyboard and Controller.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                // Escape, and with it the controller's back button, closes the window too.
                Button("Close") { dismissWindow(id: "shortcuts") }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
                Button("Done") { dismissWindow(id: "shortcuts") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .fixedSize()
        .background(Theme.window)
        .withoutInitialFocus()
        .onAppear { model.shortcutsShown = true }
        .onDisappear { model.shortcutsShown = false }
    }

    /// One column of titled groups, in one grid so that the keys line up from group to group. A row
    /// stays on one line, so the column is as wide as its longest.
    private func column(_ groups: [(title: String, entries: [ShortcutReference.Entry])]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(Array(groups.enumerated()), id: \.element.title) { offset, group in
                GridRow {
                    Text(group.title)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.top, offset == 0 ? 0 : 12)
                        .padding(.bottom, 3)
                        .gridCellColumns(2)
                }
                ForEach(group.entries) { entry in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(entry.keys)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 4))
                        Text(entry.action)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}
