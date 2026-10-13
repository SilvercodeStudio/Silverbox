import SwiftUI
import eXoCore

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.displayName)") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .help) {
            Button("\(AppInfo.displayName) Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
            Link("eXo Project Website", destination: AboutPanel.projectURL)
        }

        CommandMenu("Game") {
            Button("Play") { if let game = model.selectedGame { model.play(game) } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedGame == nil)
            Button("Install…") { if let game = model.selectedGame { model.pendingInstall = game } }
                .disabled(model.selectedGame.map { !$0.isDOSGame || model.isInstalled($0) } ?? true)
            Button("Uninstall…") { if let game = model.selectedGame { model.pendingUninstall = game } }
                .disabled(model.selectedGame.map { !$0.isDOSGame || !model.isInstalled($0) } ?? true)
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
            Button(model.settings.inspectorShown ? "Hide Inspector" : "Show Inspector") {
                model.settings.inspectorShown.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Back to Library") { model.openedGameID = nil }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(model.openedGameID == nil)
        }

        CommandMenu("Music") {
            Button(model.music.isPlaying ? "Pause Menu Music" : "Play Menu Music") {
                if model.music.isPlaying {
                    model.music.pause()
                } else {
                    model.updateMusic()
                    model.music.resume()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!model.settings.musicEnabled)
            Toggle(
                "Menu Music",
                isOn: Binding(get: { model.settings.musicEnabled }, set: { model.settings.musicEnabled = $0 }))
        }
    }
}
