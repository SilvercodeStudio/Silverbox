import Foundation
import SilverboxCore

/// A place the library window showed: a section of the sidebar, with its
/// search, the game selected there and the game page that was open.
nonisolated struct NavigationPlace: Equatable, Sendable {
    var scope: LibraryScope
    var searchText: String
    var openedGameID: String?
    var selectedGameID: String?
}

/// Back and Forward, as in a browser. A new place begins when the sidebar's
/// section changes, a game page opens or closes, a search starts or ends,
/// or a jump selects another game (Other Versions). Moving the selection in
/// the grid makes no entry; the place remembers the game selected when it
/// was left, and Back selects it again.
extension AppModel {
    var canNavigateBack: Bool { history.canGoBack(where: placeExists) }
    var canNavigateForward: Bool { history.canGoForward(where: placeExists) }

    /// What the window shows now, with some of it as it was a moment ago:
    /// a property's observer gives its old value, to name the place left.
    func place(
        scope: LibraryScope? = nil, searchText: String? = nil, openedGameID: String?? = nil
    ) -> NavigationPlace {
        NavigationPlace(
            scope: scope ?? self.scope, searchText: searchText ?? self.searchText,
            openedGameID: openedGameID ?? self.openedGameID, selectedGameID: selectedGameID)
    }

    /// Records a place that was just left, unless it is part of a larger
    /// step or of a move in the history.
    func leftPlace(_ place: NavigationPlace) {
        guard navigationDepth == 0 else { return }
        history.leave(place)
    }

    /// Runs a step that changes several things (the section and the page,
    /// or the search, the section and the selection) as one place left. A
    /// step that only selects another game counts too: it is a jump.
    func navigate(_ change: () -> Void) {
        guard navigationDepth == 0 else {
            change()
            return
        }
        let origin = place()
        navigationDepth += 1
        change()
        navigationDepth -= 1
        if place() != origin { leftPlace(origin) }
    }

    /// Shows the place before this one. A section or a game that is gone
    /// since (a collection removed) is passed over.
    func navigateBack() {
        if let destination = history.goBack(from: place(), where: placeExists) { show(destination) }
    }

    func navigateForward() {
        if let destination = history.goForward(from: place(), where: placeExists) { show(destination) }
    }

    private func show(_ destination: NavigationPlace) {
        navigationDepth += 1
        defer { navigationDepth -= 1 }
        quickLookURL = nil
        // Only what differs: each of these reads the whole library again.
        let listChanges = scope != destination.scope || searchText != destination.searchText
        if searchText != destination.searchText { searchText = destination.searchText }
        if scope != destination.scope {
            scope = destination.scope
        } else if listChanges {
            // The scope's own refresh has the search already; without it, do not wait for the search's.
            refreshVisibleGames()
        }
        openedGameID = destination.openedGameID
        if let id = destination.openedGameID ?? destination.selectedGameID, library?.game(id: id) != nil {
            selectedGameID = id
        }
        // After the grid has laid out the place's games.
        Task { @MainActor in self.revealSelectionRequest += 1 }
    }

    private func placeExists(_ place: NavigationPlace) -> Bool {
        guard let library else { return false }
        if let id = place.openedGameID, library.game(id: id) == nil { return false }
        switch place.scope {
        case .all, .favorites, .eXoFavorites, .installed, .recentlyPlayed: return true
        case .pack(let pack): return library.packs.contains(pack)
        case .node(let collectionID, let ref): return library.node(collectionID: collectionID, ref: ref) != nil
        }
    }

    /// Back to the library from a game page: Escape, Command-Up, the
    /// controller's back button. When the page was opened from this very
    /// list, that is Back, so Forward opens the page again; otherwise the
    /// page closes as a new step.
    func closeGamePage() {
        guard openedGameID != nil else { return }
        if let last = history.previous, last.openedGameID == nil, last.scope == scope,
            last.searchText == searchText, placeExists(last)
        {
            navigateBack()
        } else {
            openedGameID = nil
        }
    }
}
