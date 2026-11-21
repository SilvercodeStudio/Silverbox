import Foundation
import Testing

@testable import SilverboxCore

@Suite("Library loading")
struct LibraryLoaderTests {
    @Test func loadsSnapshot() throws {
        let snapshot = try FixtureLibrary.snapshot()
        #expect(snapshot.games.count == 4)
        #expect(snapshot.platforms.map(\.name) == ["MS-DOS", "MS-DOS Books"])
        #expect(snapshot.categories.map(\.name) == ["Computers", "Literature"])
        #expect(snapshot.playlists.count == 2)
        #expect(snapshot.game(id: FixtureLibrary.ultimaID)?.title == "Ultima V: Warriors of Destiny")
        #expect(snapshot.alternateNames[FixtureLibrary.ultimaID]?.count == 2)
        #expect(snapshot.additionalApplications[FixtureLibrary.ultimaID]?.first?.name == "eXoDOS Updater")
        #expect(snapshot.dosboxIndex.count == 7)
        #expect(snapshot.installedGamePaths == ["eXoDOS/ultima5"])
    }

    @Test func buildsSidebarTree() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let roots = snapshot.tree
        #expect(roots.map(\.title) == ["Computers", "Quality Freeware"])
        let computers = try #require(roots.first)
        #expect(computers.children.map(\.title) == ["Literature", "MS-DOS"])
        let msdos = try #require(computers.children.last)
        #expect(msdos.children.map(\.title) == ["eXoDOS Games with MT-32"])
        #expect(computers.platformNames.sorted() == ["MS-DOS", "MS-DOS Books"])
        // A rule for a platform that does not exist is ignored.
        #expect(snapshot.node(for: .platform("Ghost Platform")) == nil)
    }

    @Test func installedUsesFolderPresence() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let ultima = try #require(snapshot.game(id: FixtureLibrary.ultimaID))
        let tetris = try #require(snapshot.game(id: FixtureLibrary.tetrisID))
        #expect(snapshot.isInstalled(ultima))
        // The XML says installed, but the folder is missing.
        #expect(!snapshot.isInstalled(tetris))
    }

    @Test func mediaFolderUsesPlatformFolders() throws {
        let snapshot = try FixtureLibrary.snapshot()
        #expect(snapshot.mediaFolder(platform: "MS-DOS", mediaType: "Box - Front").lastPathComponent == "Box - Front")
        #expect(snapshot.mediaFolder(platform: "MS-DOS", mediaType: "Video").path.hasSuffix("Videos/MS-DOS"))
        #expect(snapshot.mediaFolder(platform: "Other", mediaType: "Disc").path.hasSuffix("Images/Other/Disc"))
    }
}

@Suite("Navigation history")
struct NavigationHistoryTests {
    @Test func goesBackAndForwardLikeABrowser() {
        var history = NavigationHistory<String>()
        #expect(!history.canGoBack { _ in true })
        #expect(history.goBack(from: "a") { _ in true } == nil)

        // a → b → c, then back twice and forward once.
        history.leave("a")
        history.leave("b")
        #expect(history.previous == "b")
        #expect(history.goBack(from: "c") { _ in true } == "b")
        #expect(history.goBack(from: "b") { _ in true } == "a")
        #expect(!history.canGoBack { _ in true })
        #expect(history.goForward(from: "a") { _ in true } == "b")
        #expect(history.backPlaces == ["a"])
        #expect(history.forwardPlaces == ["c"])

        // A new place from here drops what Forward had.
        history.leave("b")
        #expect(history.forwardPlaces.isEmpty)
        #expect(history.backPlaces == ["a", "b"])
    }

    @Test func passesOverPlacesThatAreGone() {
        var history = NavigationHistory<String>()
        for place in ["a", "gone", "b", "gone too"] { history.leave(place) }
        let exists: (String) -> Bool = { !$0.hasPrefix("gone") }
        #expect(history.goBack(from: "c", where: exists) == "b")
        #expect(history.goBack(from: "b", where: exists) == "a")
        #expect(history.backPlaces.isEmpty)
        #expect(history.forwardPlaces == ["c", "b"])
        // Only places that are gone are left: Back has nowhere to go, and the current place stays.
        var other = NavigationHistory<String>()
        other.leave("gone")
        #expect(!other.canGoBack(where: exists))
        #expect(other.goBack(from: "x", where: exists) == nil)
        #expect(other.forwardPlaces.isEmpty)
    }

    @Test func keepsTheNewestPlacesAndNoDoubles() {
        var history = NavigationHistory<Int>(limit: 3)
        for place in [1, 2, 2, 3, 4, 5] { history.leave(place) }
        #expect(history.backPlaces == [3, 4, 5])
    }
}

@Suite("Choosing a library folder")
struct LibraryFolderChoiceTests {
    @Test func takesTheCollectionAroundAFolderInsideIt() {
        let root = FixtureLibrary.rootURL.standardizedFileURL
        #expect(LibraryFolderChoice.resolve(root) == .library(root))
        #expect(LibraryFolderChoice.resolve(root.appendingPathComponent("eXo")) == .corrected(root))
        #expect(LibraryFolderChoice.resolve(root.appendingPathComponent("Data/Platforms")) == .corrected(root))
        #expect(LibraryFolderChoice.resolve(root.appendingPathComponent("eXo/eXoDOS")) == .corrected(root))
        // A library inside another one is taken as it is.
        let console = root.appendingPathComponent("ConsoleLibrary")
        #expect(LibraryFolderChoice.resolve(console) == .library(console))
    }

    @Test func takesTheOneCollectionInsideAFolder() throws {
        let parent = try FixtureLibrary.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        #expect(LibraryFolderChoice.resolve(parent) == .notALibrary)

        func makeLibrary(_ name: String) throws -> URL {
            let library = parent.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(
                at: library.appendingPathComponent("Data/Platforms"), withIntermediateDirectories: true)
            try "<LaunchBox/>".write(
                to: library.appendingPathComponent("Data/Platforms.xml"), atomically: true, encoding: .utf8)
            return library.standardizedFileURL
        }
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent("Other"), withIntermediateDirectories: true)
        let first = try makeLibrary("eXoDOS")
        #expect(LibraryFolderChoice.resolve(parent) == .corrected(first))
        #expect(LibraryFolderChoice.resolve(parent).url == first)

        let second = try makeLibrary("eXoIF")
        #expect(LibraryFolderChoice.resolve(parent) == .several([first, second]))
        #expect(LibraryFolderChoice.resolve(parent).url == nil)
        // The folder beside them belongs to neither.
        #expect(LibraryFolderChoice.resolve(parent.appendingPathComponent("Other")) == .notALibrary)
    }
}

@Suite("Library queries")
struct LibraryQueryTests {
    @Test func scopes() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let query = LibraryQuery(snapshot: snapshot)
        #expect(query.games(in: .all).count == 4)
        #expect(query.games(in: .node(collectionID: snapshot.collection.id, ref: .platform("MS-DOS"))).count == 3)
        #expect(query.games(in: .node(collectionID: snapshot.collection.id, ref: .category("Computers"))).count == 4)
        #expect(
            query.games(in: .node(collectionID: snapshot.collection.id, ref: .category("Literature"))).map(\.title) == [
                "Programmer's Guide to MS-DOS"
            ])
        // eXo marks Ultima V as a favorite: one of its picks, not the user's.
        #expect(query.games(in: .favorites).isEmpty)
        #expect(query.games(in: .eXoFavorites).map(\.launchBoxID) == [FixtureLibrary.ultimaID])
        #expect(
            query.games(in: .installed).map(\.launchBoxID) == [
                FixtureLibrary.ultimaID, "bbbbbbbb-0000-0000-0000-000000000001",
            ])
    }

    @Test func playlistsResolve() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let query = LibraryQuery(snapshot: snapshot)
        let mt32 = query.games(
            in: .node(collectionID: snapshot.collection.id, ref: .playlist("e64fb51c-ff5d-4fbe-919c-aa2249d78117")))
        #expect(Set(mt32.map(\.launchBoxID)) == [FixtureLibrary.ultimaID, FixtureLibrary.tetrisID])
        let explicit = query.games(
            in: .node(collectionID: snapshot.collection.id, ref: .playlist("11111111-2222-3333-4444-555555555555")))
        #expect(explicit.map(\.launchBoxID) == [FixtureLibrary.tetrisID])
    }

    @Test func searchPutsTheBestTitleMatchesFirst() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let query = LibraryQuery(snapshot: snapshot)
        // "in" is in Ultima's title ("Destiny"), and only in the developers of the two others ("Inc.").
        let found = query.sort(query.filter(query.games(in: .all), search: "in"), by: .title)
        #expect(found.map(\.title) == ["Jeopardy! (1987)", "Super Tetris", "Ultima V: Warriors of Destiny"])
        #expect(
            query.rankedBySearch(found, search: " IN ").map(\.title) == [
                "Ultima V: Warriors of Destiny", "Jeopardy! (1987)", "Super Tetris",
            ])
        // Every term must be in the title, and no search changes nothing.
        #expect(query.rankedBySearch(found, search: "in jeopardy").first?.title == "Jeopardy! (1987)")
        #expect(query.rankedBySearch(found, search: "  ") == found)
    }

    @Test func aWordOfTheTitleBeatsTheStartOfAWord() {
        func rank(_ title: String, _ search: String) -> LibraryQuery.SearchRank {
            LibraryQuery.searchRank(ofTitle: title, terms: search.split(separator: " ").map(String.init))
        }
        #expect(rank("Ultima V: Warriors of Destiny", "ultima") == .word)
        #expect(rank("Tony La Russa's Ultimate Baseball", "ultima") == .wordStart)
        #expect(rank("True Blood: The Karthanian Ultimatum", "ultima") == .wordStart)
        #expect(rank("The Penultimate Fantasy", "ultima") == .inTitle)
        #expect(rank("Afterlife", "ultima") == .elsewhere)
        // The worst term decides, and accents and case do not count.
        #expect(rank("Ultima V: Warriors of Destiny", "ultima warr") == .wordStart)
        #expect(rank("Ultima V: Warriors of Destiny", "ultima origin") == .elsewhere)
        #expect(rank("Pokémon Blue", "pokemon") == .word)
        #expect(LibraryQuery.SearchRank.word < .wordStart)
    }

    @Test func playlistTitlesDropTheWordsAboveThem() throws {
        func short(_ title: String, under ancestors: [String] = [], packs: [String] = ["eXoDOS", "eXoDemoScene"])
            -> String
        {
            LibraryNode(ref: .playlist("p"), title: title).sidebarTitle(under: ancestors, packs: packs)
        }
        #expect(short("eXoDOS Games with MT-32", under: ["Computers", "MS-DOS"]) == "MT-32")
        #expect(short("eXoDOS Games with MT-32", packs: []) == "eXoDOS Games with MT-32")
        #expect(short("eXoDOS 3dfx Games") == "3dfx Games")
        // A pack's name goes from the middle too; the title of a row above only from the start.
        #expect(short("Installed eXoDemoScene Demos") == "Installed Demos")
        #expect(short("Arcade Fighting Games", under: ["Arcade"]) == "Fighting Games")
        #expect(short("Best of Arcade", under: ["Arcade"]) == "Best of Arcade")
        #expect(short("Nintendo Entertainment System Hacks", under: ["Nintendo Entertainment System"]) == "Hacks")
        // A title that is the name alone, and a platform, stay whole.
        #expect(short("eXoDOS") == "eXoDOS")
        #expect(
            LibraryNode(ref: .platform("MS-DOS Books"), title: "MS-DOS Books")
                .sidebarTitle(under: ["MS-DOS"], packs: []) == "MS-DOS Books")

        let snapshot = try FixtureLibrary.snapshot()
        let titles = LibraryNode.sidebarTitles(in: snapshot.tree, packs: ["eXoDOS"])
        #expect(Array(titles.values) == ["MT-32"])
    }

    @Test func gamesAreNotTheBooksBesideThem() throws {
        let snapshot = try FixtureLibrary.snapshot()
        #expect(
            snapshot.games.filter(\.isGame).map(\.title).sorted() == [
                "Jeopardy! (1987)", "Super Tetris", "Ultima V: Warriors of Destiny",
            ])
    }

    @Test func searchMatchesAlternateNames() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let query = LibraryQuery(snapshot: snapshot)
        let all = query.games(in: .all)
        #expect(query.filter(all, search: "quintus").map(\.launchBoxID) == [FixtureLibrary.ultimaID])
        #expect(query.filter(all, search: "ULTIMA warriors").count == 1)
        #expect(query.filter(all, search: "sharedata").count == 1)
        #expect(query.filter(all, search: "   ").count == 4)
    }

    /// eXoDOS lists most alternate names twice; the copies are dropped.
    @Test func duplicateAlternateNamesAreDropped() {
        let names = [
            AlternateName(gameID: "g", name: "Ultima Underworld 1", region: "Origin release"),
            AlternateName(gameID: "g", name: "Ultima Underworld 1", region: "Origin release"),
            AlternateName(gameID: "g", name: "Ultima Underworld 1", region: "Japan"),
        ]
        let snapshot = LibrarySnapshot(
            root: LibraryRoot(url: URL(fileURLWithPath: "/lib")), games: [], platforms: [], categories: [],
            platformFolders: [], playlists: [], parents: [], alternateNames: names, additionalApplications: [],
            installedGamePaths: [])
        #expect(snapshot.alternateNames["g"]?.map(\.region) == ["Origin release", "Japan"])
    }

    @Test func sortsByTitleUsingSortTitle() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let query = LibraryQuery(snapshot: snapshot)
        let titles = query.sort(
            query.games(in: .node(collectionID: snapshot.collection.id, ref: .platform("MS-DOS"))), by: .title
        ).map(\.title)
        #expect(titles == ["Jeopardy! (1987)", "Super Tetris", "Ultima V: Warriors of Destiny"])
        let years = query.sort(
            query.games(in: .node(collectionID: snapshot.collection.id, ref: .platform("MS-DOS"))), by: .releaseYear
        ).map(\.releaseYear)
        #expect(years == [1987, 1988, 1991])
    }

    @Test func overlayChangesFavorites() throws {
        let snapshot = try FixtureLibrary.snapshot()
        var state = UserLibraryState()
        state.update(FixtureLibrary.tetrisID) { $0.favorite = true }
        state.update(FixtureLibrary.ultimaID) { $0.favorite = false }
        let favorites = LibraryQuery(snapshot: snapshot).games(in: .favorites, overlay: state)
        #expect(favorites.map(\.launchBoxID) == [FixtureLibrary.tetrisID])
        // Choosing one of eXo's picks makes it the user's favorite too.
        state.update(FixtureLibrary.ultimaID) { $0.favorite = true }
        #expect(LibraryQuery(snapshot: snapshot).games(in: .favorites, overlay: state).count == 2)
    }

    @Test func keepsLaunchBoxFavoritesOutsideTheEXoPacks() {
        // Outside the eXo packs, the XML flag is the user's own from LaunchBox.
        let rom = Game(
            id: "rom", title: "Sonic the Hedgehog", platform: "Sega Genesis",
            applicationPath: "Games\\Sega Genesis\\Sonic.zip", favorite: true)
        #expect(rom.isFavoriteByDefault)
        #expect(!rom.isEXoFavorite)
        #expect(UserLibraryState().isFavorite(rom))
    }
}

@Suite("User state")
struct UserStateTests {
    @Test func recordsPlayAndRoundTrips() throws {
        var state = UserLibraryState()
        state.recordPlay("g1", seconds: 90, endedAt: Date(timeIntervalSince1970: 1_700_000_000))
        state.recordPlay("g1", seconds: 30)
        #expect(state.state(for: "g1").playCount == 2)
        #expect(state.state(for: "g1").playTimeSeconds == 120)
        state.update("g2") { $0.favorite = true }
        state.update("g2") { $0.favorite = nil }
        #expect(state.games["g2"] == nil)

        let directory = try FixtureLibrary.scratchDirectory()
        let store = UserLibraryStateStore(url: directory.appendingPathComponent("state.json"))
        try store.save(state)
        let loaded = try store.load()
        #expect(loaded == state)
    }
}
