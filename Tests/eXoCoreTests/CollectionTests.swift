import Foundation
import Testing
@testable import eXoCore

@Suite("Path substitutions")
struct PathSubstitutionTests {
    @Test func mapsAbsoluteAndRelativePrefixes() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/Volumes/LB"), substitutions: [
            PathSubstitution(windowsPrefix: "X:\\Emulation", macPath: "/Volumes/storage/Emulation"),
            PathSubstitution(windowsPrefix: "Games", macPath: "/Volumes/nas/Games"),
        ])
        #expect(root.url(forWindowsRelativePath: "X:\\Emulation\\PSX\\Game.chd").path == "/Volumes/storage/Emulation/PSX/Game.chd")
        #expect(root.url(forWindowsRelativePath: "x:\\emulation\\PSX\\Game.chd").path == "/Volumes/storage/Emulation/PSX/Game.chd")
        #expect(root.url(forWindowsRelativePath: "Games\\Sega Genesis\\Sonic.zip").path == "/Volumes/nas/Games/Sega Genesis/Sonic.zip")
        #expect(root.url(forWindowsRelativePath: "GamesX\\foo.zip").path == "/Volumes/LB/GamesX/foo.zip")
        #expect(root.url(forWindowsRelativePath: "..\\Emulation\\Amiga\\a.lha").path == "/Volumes/Emulation/Amiga/a.lha")
        #expect(root.url(forWindowsRelativePath: "Images\\MS-DOS\\x.png").path == "/Volumes/LB/Images/MS-DOS/x.png")
    }

    @Test func collectionRoundTripsThroughJSON() throws {
        let collection = LibraryCollection(name: "Consoles", rootPath: "/Volumes/LB",
                                           substitutions: [PathSubstitution(windowsPrefix: "Games", macPath: "/nas/Games")])
        let data = try JSONEncoder().encode(collection)
        let decoded = try JSONDecoder().decode(LibraryCollection.self, from: data)
        #expect(decoded == collection)
        let minimal = try JSONDecoder().decode(LibraryCollection.self, from: Data(#"{"rootPath":"/x"}"#.utf8))
        #expect(minimal.isEnabled && minimal.kind == .launchBox && minimal.substitutions.isEmpty)
    }
}

@Suite("Library aggregate")
struct LibraryAggregateTests {
    @Test func keepsTwoCopiesOfTheSameLibraryApart() throws {
        let first = try LibraryLoader(collection: LibraryCollection(name: "A", rootPath: FixtureLibrary.rootURL.path)).load()
        let second = try LibraryLoader(collection: LibraryCollection(name: "B", rootPath: FixtureLibrary.rootURL.path)).load()
        let library = Library(snapshots: [first, second])
        #expect(library.games.count == 8)
        #expect(Set(library.games.map(\.id)).count == 8, "composite ids must be unique")
        #expect(Set(library.games.map(\.launchBoxID)).count == 4)
        let ultimaA = try #require(first.game(id: FixtureLibrary.ultimaID))
        #expect(ultimaA.collectionID == first.collection.id)
        #expect(library.game(id: ultimaA.id)?.collectionID == first.collection.id)
        #expect(library.snapshot(for: ultimaA)?.collection.name == "A")
        #expect(library.alternateNames(for: ultimaA).count == 2)

        let query = LibraryQuery(library: library)
        #expect(query.games(in: .node(collectionID: second.collection.id, ref: .platform("MS-DOS"))).count == 3)
        #expect(query.games(in: .all).count == 8)
        #expect(query.filter(query.games(in: .all), search: "quintus").count == 2)
        let index = LibrarySearchIndex(library: library)
        #expect(index.keys.count == 8)
    }

    @Test func parsesEmulatorAssignments() throws {
        let snapshot = try FixtureLibrary.snapshot()
        #expect(snapshot.emulators.map(\.title) == ["RetroArch", "Dolphin"])
        #expect(snapshot.emulatorPlatforms.count == 3)
        let nes = try #require(snapshot.emulatorAssignment(for: "Nintendo Entertainment System"))
        #expect(nes.emulator.executableName == "retroarch")
        #expect(nes.platform.retroArchCore == "fceumm_libretro")
        // The default assignment wins over a non-default one listed first.
        let gamecube = try #require(snapshot.emulatorAssignment(for: "Nintendo GameCube"))
        #expect(gamecube.emulator.title == "RetroArch")
        #expect(snapshot.emulatorAssignment(for: "Unknown") == nil)
    }
}

@Suite("Library cache")
struct LibraryCacheTests {
    @Test func reusesCacheWhileFilesAreUnchanged() throws {
        let directory = try FixtureLibrary.scratchDirectory().appendingPathComponent("LibraryCache")
        let cache = LibraryCache(directory: directory)
        let collection = LibraryCollection(name: "Fixture", rootPath: FixtureLibrary.rootURL.path)
        let fingerprint = LibraryCache.fingerprint(for: collection.root)
        #expect(fingerprint.contains("MS-DOS.xml"))
        #expect(cache.load(collectionID: collection.id, fingerprint: fingerprint) == nil)

        let parsed = try LibraryLoader(collection: collection, cache: cache).load()
        let payload = try #require(cache.load(collectionID: collection.id, fingerprint: fingerprint))
        #expect(payload.games.count == parsed.games.count)
        #expect(payload.games.allSatisfy { $0.collectionID == collection.id })
        #expect(payload.emulators.count == 2)

        let cached = try LibraryLoader(collection: collection, cache: cache).load()
        #expect(cached.games.map(\.title) == parsed.games.map(\.title))
        #expect(cached.playlists.count == parsed.playlists.count)
        #expect(cached.tree.map(\.title) == parsed.tree.map(\.title))
        #expect(cached.installedFolderNames == ["ultima5"])
        #expect(cache.load(collectionID: collection.id, fingerprint: fingerprint + "x") == nil)
        cache.remove(collectionID: collection.id)
        #expect(cache.load(collectionID: collection.id, fingerprint: fingerprint) == nil)
    }
}
