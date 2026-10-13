import AppKit
import Foundation
import eXoCore

enum NavigationDirection {
    case up, down, left, right
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

    /// Loads the gallery and manual whenever the selection changes.
    func refreshSelectedMedia() {
        mediaTask?.cancel()
        galleryIndex = 0
        guard let game = selectedGame, let media = media(for: game) else {
            galleryItems = []
            selectedManual = nil
            return
        }
        mediaTask = Task { [weak self] in
            let items = await media.gallery(for: game)
            let manual = await media.manual(for: game)
            guard let self, !Task.isCancelled, self.selectedGameID == game.id else { return }
            self.galleryItems = items
            self.selectedManual = manual
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

    /// What the Quick Look panel can page through: the gallery, then the manual.
    var quickLookItems: [URL] {
        var urls = galleryItems.map(\.url)
        if let selectedManual { urls.append(selectedManual) }
        return urls
    }
}
