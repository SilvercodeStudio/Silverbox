import AppKit
import Foundation
import eXoCore

enum NavigationDirection {
    case up, down, left, right
}

/// A game's extras and manual, as cached for its context menu.
struct GameExtrasEntry {
    var extras: [GameExtra]
    var manual: URL?
}

/// Keyboard and controller navigation: moving the selection, playing,
/// going back, and stepping through the selected game's media.
extension AppModel {
    /// Games per row for arrow keys: the grid's columns, or 1 in the list.
    private var navigationColumns: Int {
        settings.viewMode == .grid ? max(1, gridColumns) : 1
    }

    private var selectedIndex: Int? {
        visibleGames.firstIndex { $0.id == selectedGameID }
    }

    func moveSelection(_ direction: NavigationDirection) {
        guard !visibleGames.isEmpty else { return }
        guard let index = selectedIndex else {
            selectedGameID = visibleGames.first?.id
            return
        }
        let columns = navigationColumns
        let last = visibleGames.count - 1
        var target: Int
        switch direction {
        case .left: target = index - 1
        case .right: target = index + 1
        case .up: target = index - columns
        case .down:
            target = index + columns
            // From the second-to-last row, step down into a shorter last row.
            if target > last, index / columns < last / columns { target = last }
        }
        guard visibleGames.indices.contains(target) else { return }
        selectedGameID = visibleGames[target].id
    }

    func moveSelectionByPage(forward: Bool) {
        guard !visibleGames.isEmpty else { return }
        let step = navigationColumns * 4
        let index = selectedIndex ?? 0
        let target = forward ? min(visibleGames.count - 1, index + step) : max(0, index - step)
        selectedGameID = visibleGames[target].id
    }

    func selectFirstGame() {
        selectedGameID = visibleGames.first?.id
    }

    func selectLastGame() {
        selectedGameID = visibleGames.last?.id
    }

    /// Return, or the controller's main button.
    func activateSelection() {
        if let game = selectedGame { play(game) }
    }

    /// Escape, or the controller's back button: closes what is open, in
    /// order. Returns false when there was nothing to close.
    @discardableResult
    func goBack() -> Bool {
        if quickLookURL != nil {
            quickLookURL = nil
            return true
        }
        if openedGameID != nil {
            openedGameID = nil
            return true
        }
        if !searchText.isEmpty {
            searchText = ""
            return true
        }
        return false
    }

    // MARK: - Media of the selected game

    /// Loads the gallery, manual and extras whenever the selection changes.
    func refreshSelectedMedia() {
        mediaTask?.cancel()
        galleryIndex = 0
        guard let game = selectedGame, let media = media(for: game) else {
            galleryItems = []
            selectedManual = nil
            selectedExtras = []
            return
        }
        mediaTask = Task { [weak self] in
            let items = await media.gallery(for: game)
            let manual = await media.manual(for: game)
            let extras = await media.extras(for: game)
            guard let self, !Task.isCancelled, self.selectedGameID == game.id else { return }
            self.galleryItems = items
            self.selectedManual = manual
            self.selectedExtras = extras
            self.extrasCache[game.id] = GameExtrasEntry(extras: extras, manual: manual)
        }
    }

    /// Loads a game's extras and manual into `extrasCache` ahead of its
    /// context menu, which cannot change once it is open. Called when the
    /// pointer enters a tile or row.
    func prefetchExtras(for game: Game) {
        guard extrasCache[game.id] == nil, !extrasTasks.contains(game.id), let media = media(for: game) else {
            return
        }
        extrasTasks.insert(game.id)
        Task { [weak self] in
            let extras = await media.extras(for: game)
            let manual = await media.manual(for: game)
            guard let self else { return }
            self.extrasTasks.remove(game.id)
            self.extrasCache[game.id] = GameExtrasEntry(extras: extras, manual: manual)
        }
    }

    func showNextMedia() {
        guard !galleryItems.isEmpty else { return }
        galleryIndex = (galleryIndex + 1) % galleryItems.count
    }

    func showPreviousMedia() {
        guard !galleryItems.isEmpty else { return }
        galleryIndex = (galleryIndex - 1 + galleryItems.count) % galleryItems.count
    }

    /// Space: Quick Look the image or video on show.
    func quickLookCurrentMedia() {
        guard galleryItems.indices.contains(galleryIndex) else { return }
        quickLookURL = galleryItems[galleryIndex].url
    }

    func quickLookManual() {
        guard let selectedManual else { return }
        quickLookURL = selectedManual
    }

    /// Cmd-Option-Y: Quick Look the first extra; the panel pages on from there.
    func quickLookExtras() {
        guard let first = selectedExtras.first else { return }
        quickLookURL = first.url
    }

    /// What the Quick Look panel can page through: the gallery, the manual,
    /// then the extras.
    var quickLookItems: [URL] {
        var urls = galleryItems.map(\.url)
        if let selectedManual { urls.append(selectedManual) }
        urls += selectedExtras.map(\.url)
        return urls
    }

    // MARK: - Window commands

    /// Cmd-F: puts the cursor in the search field.
    func focusSearch() {
        searchFocusRequest += 1
    }

    /// Cmd-Plus and Cmd-Minus: grows or shrinks the grid tiles.
    func zoomTiles(by delta: Double) {
        let range = AppSettings.tileSizeRange
        settings.tileSize = min(range.upperBound, max(range.lowerBound, settings.tileSize + delta))
    }

    func resetTileSize() {
        settings.tileSize = AppSettings.defaultTileSize
    }
}
