import Foundation
import Testing

@testable import eXoCore

/// Matching the same game across collections and packs.
@Suite("Other versions")
struct GameVersionTests {
    static func game(
        _ title: String, folder: String, platform: String, developer: String?, publisher: String? = nil,
        launcher: String? = nil
    ) -> Game {
        Game(
            id: "\(platform)-\(title)", title: title, platform: platform,
            applicationPath: launcher ?? "\(folder)\\\(title).bat", developer: developer, publisher: publisher,
            rootFolder: folder)
    }

    static func snapshot(_ name: String, _ games: [Game]) -> LibrarySnapshot {
        LibrarySnapshot(
            root: LibraryRoot(url: URL(fileURLWithPath: "/nonexistent/\(name)", isDirectory: true)), games: games,
            platforms: [], categories: [], platformFolders: [], playlists: [], parents: [], alternateNames: [],
            additionalApplications: [], installedGamePaths: [])
    }

    @Test func ignoresArticlesPunctuationAndBracketedNotes() {
        let key = GameVersionIndex.titleKey("A Mind Forever Voyaging")
        #expect(key == "mind forever voyaging")
        #expect(GameVersionIndex.titleKey("Mind Forever Voyaging (DOS)") == key)
        #expect(GameVersionIndex.titleKey("Pepper's Adventures in Time") == "peppers adventures in time")
        #expect(
            GameVersionIndex.titleKey("Time & Magik: The Trilogy")
                == GameVersionIndex.titleKey("Time and Magik: The Trilogy"))
        #expect(GameVersionIndex.titleKey("Dopplegänger") == GameVersionIndex.titleKey("Doppleganger"))
        #expect(GameVersionIndex.titleKey("Fiery Darts ][") == "fiery darts ii")
        #expect(GameVersionIndex.nameWords("Level 9 Computing, Ltd.") == ["level"])
        #expect(GameVersionIndex.nameWords("Freeware").isEmpty)
    }

    @Test func linksTheSameGameAcrossPacks() {
        let scummVM = Self.game(
            "A Mind Forever Voyaging", folder: "eXo\\eXoScummVM\\!ScummVM\\Mind Forever Voyaging, A (DOS)",
            platform: "ScummVM", developer: "Infocom, Inc.")
        let interactiveFiction = Self.game(
            "A Mind Forever Voyaging", folder: "eXo\\eXoIF\\!IF\\Mind Forever Voyaging (1985)",
            platform: "Interactive Fiction", developer: "Infocom, Inc.", publisher: "Infocom, Inc.")
        let deadline = Self.game(
            "Deadline", folder: "eXo\\eXoIF\\!IF\\Deadline (1982)", platform: "Interactive Fiction",
            developer: "Infocom, Inc.")
        // Same title, different game.
        let demo = Self.game(
            "Deadline", folder: "eXo\\eXoDemoScn\\!demoscn\\deadline", platform: "eXoDemoScene", developer: "Purple")
        // A magazine is not a version of the game.
        let magazine = Self.game(
            "A Mind Forever Voyaging", folder: "eXo\\Magazines", platform: "IF Magazines",
            developer: "Infocom, Inc.", launcher: "eXo\\Magazines\\amfv.pdf")
        let library = Library(snapshots: [
            Self.snapshot("scummvm", [scummVM]),
            Self.snapshot("if", [interactiveFiction, deadline, magazine]),
            Self.snapshot("demoscene", [demo]),
        ])
        let index = GameVersionIndex(library: library)
        let stamped = { (game: Game) in library.games.first { $0.title == game.title && $0.platform == game.platform }!
        }

        #expect(index.otherVersions(of: stamped(scummVM), in: library).map(\.platform) == ["Interactive Fiction"])
        #expect(index.otherVersions(of: stamped(interactiveFiction), in: library).map(\.platform) == ["ScummVM"])
        #expect(index.otherVersions(of: stamped(deadline), in: library).isEmpty)
        #expect(GameVersionIndex.source(of: stamped(scummVM)) == "eXoScummVM")
    }
}
