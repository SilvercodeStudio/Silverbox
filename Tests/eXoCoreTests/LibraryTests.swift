import Foundation
import Testing

@testable import eXoCore

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
        #expect(query.games(in: .favorites).map(\.launchBoxID) == [FixtureLibrary.ultimaID])
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
            dosboxIndex: DOSBoxIndex(), installedGamePaths: [])
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
