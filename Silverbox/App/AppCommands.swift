import SwiftUI
import SilverboxCore

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var pauseTitle: String {
        if model.album.isActive { return model.album.isPlaying ? "Pause Album" : "Play Album" }
        return model.music.isPlaying ? "Pause Menu Music" : "Play Menu Music"
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.displayName)") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .help) {
            Button("\(AppInfo.displayName) Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
            Button("Keyboard Shortcuts") {
                if model.shortcutsShown { dismissWindow(id: "shortcuts") } else { openWindow(id: "shortcuts") }
            }
            .keyboardShortcut("/", modifiers: .command)
            Divider()
            Link("\(AppInfo.displayName) Website", destination: AppInfo.websiteURL)
            Link("eXo Project Website", destination: AboutPanel.projectURL)
        }
        // Before the standard Find submenu, so Cmd-F reaches the search field.
        CommandGroup(before: .textEditing) {
            Button("Search Games") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Game") {
            Button("Play") { if let game = model.selectedGame { model.play(game) } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedGame == nil)
            Button("Install…") { if let game = model.selectedGame { model.pendingInstall = game } }
                .disabled(model.selectedGame.map { !$0.isEXoGame || model.isInstalled($0) } ?? true)
            Button("Uninstall…") { if let game = model.selectedGame { model.pendingUninstall = game } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedGame.map { !$0.isEXoGame || !model.isInstalled($0) } ?? true)
            Button("Configure…") { if let game = model.selectedGame { model.configure(game) } }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.selectedGame == nil)
            Divider()
            Button("Open Game Page") { model.openedGameID = model.selectedGameID }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(model.selectedGame == nil)
            Button("Edit Game Info…") { model.pendingInfoGame = model.selectedGame }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(model.selectedGame == nil)
            Button(model.selectedGame.map(model.isFavorite) == true ? "Remove from Favorites" : "Add to Favorites") {
                if let game = model.selectedGame { model.toggleFavorite(game) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(model.selectedGame == nil)
            Divider()
            Button("Previous Image") { model.showPreviousMedia() }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(model.galleryItems.count < 2)
            Button("Next Image") { model.showNextMedia() }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(model.galleryItems.count < 2)
            Button("Quick Look Media") { model.quickLookCurrentMedia() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(model.galleryItems.isEmpty)
            Button("Quick Look Manual") { model.quickLookManual() }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(model.selectedManual == nil)
            Button("Quick Look Extras") { model.quickLookExtras() }
                .keyboardShortcut("y", modifiers: [.command, .option])
                .disabled(model.selectedExtras.isEmpty)
            Divider()
            Button("Show in Finder") { if let game = model.selectedGame { model.revealInFinder(game) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedGame == nil)
        }

        CommandMenu("Library") {
            Button("Rescan Library") { model.reloadLibrary(clearMediaCache: true) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.collections.isEmpty)
            Divider()
            Button("Show as Grid") { model.settings.viewMode = .grid }.keyboardShortcut("1", modifiers: .command)
            Button("Show as List") { model.settings.viewMode = .list }.keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("Larger Tiles") { model.zoomTiles(by: 20) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(model.settings.viewMode != .grid)
            Button("Smaller Tiles") { model.zoomTiles(by: -20) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model.settings.viewMode != .grid)
            Button("Default Tile Size") { model.resetTileSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model.settings.viewMode != .grid)
            Divider()
            Button(model.settings.inspectorShown ? "Hide Inspector" : "Show Inspector") {
                model.settings.inspectorShown.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Back to Library") { model.openedGameID = nil }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(model.openedGameID == nil)
        }

        CommandMenu("Music") {
            Button(pauseTitle) {
                if model.album.isActive {
                    model.album.togglePlayPause()
                } else if model.music.isPlaying {
                    model.music.pause()
                } else {
                    model.updateMusic()
                    model.music.resume()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!model.settings.musicEnabled && !model.album.isActive)
            Button("Previous Track") { model.album.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.album.isActive)
            Button("Next Track") { model.album.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.album.isActive)
            Button("Stop Album") { model.stopAlbum() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.album.isActive)
            Divider()
            Toggle(
                "Menu Music",
                isOn: Binding(get: { model.settings.musicEnabled }, set: { model.settings.musicEnabled = $0 }))
            Toggle(
                "Play in Background",
                isOn: Binding(
                    get: { model.settings.musicInBackground }, set: { model.settings.musicInBackground = $0 })
            )
            .disabled(!model.settings.musicEnabled)
        }
    }
}
