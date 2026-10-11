import Foundation
import Testing
@testable import eXoCore

@Suite("Media file names")
struct MediaFileNameTests {
    @Test func sanitizesLikeLaunchBox() {
        #expect(MediaFileName.sanitize("Ultima V: Warriors of Destiny") == "Ultima V_ Warriors of Destiny")
        #expect(MediaFileName.sanitize("D/Generation") == "D_Generation")
        #expect(MediaFileName.sanitize("Vampire's Castle") == "Vampire_s Castle")
        #expect(MediaFileName.sanitize("Where in the World Is Carmen Sandiego?") == "Where in the World Is Carmen Sandiego_")
        #expect(MediaFileName.sanitize("Sam & Max Hit the Road") == "Sam & Max Hit the Road")
        #expect(MediaFileName.sanitize("1,000 Miler") == "1,000 Miler")
        #expect(MediaFileName.sanitize("Jeopardy! (1987)") == "Jeopardy! (1987)")
    }

    @Test func parsesStems() {
        let plain = MediaFileName.parse(stem: "Ultima V_ Warriors of Destiny-01")
        #expect(plain.key == "Ultima V_ Warriors of Destiny" && plain.index == 1 && plain.gameID == nil)
        let guid = MediaFileName.parse(stem: "Jeopardy! Sports Edition.0501fe6c-abc7-4a24-aebd-1d50628823d1-01")
        #expect(guid.key == "Jeopardy! Sports Edition")
        #expect(guid.gameID == "0501fe6c-abc7-4a24-aebd-1d50628823d1")
        let none = MediaFileName.parse(stem: "Just A Name")
        #expect(none.key == "Just A Name" && none.index == 0)
    }
}

@Suite("Media catalog")
struct MediaCatalogTests {
    @Test func findsRegionalBoxArtAndGuidSuffixedFiles() async throws {
        let snapshot = try FixtureLibrary.snapshot()
        let catalog = MediaCatalog(snapshot: snapshot)
        let ultima = try #require(snapshot.game(id: FixtureLibrary.ultimaID))
        let front = await catalog.images(for: ultima, type: .boxFront)
        #expect(front.first?.url.lastPathComponent == "Ultima V_ Warriors of Destiny-01.jpg")
        #expect(front.first?.region == "North America")

        let jeopardy = try #require(snapshot.game(id: FixtureLibrary.jeopardyID))
        let jeopardyFront = await catalog.images(for: jeopardy, type: .boxFront)
        #expect(jeopardyFront.count == 1)
        #expect(jeopardyFront.first?.gameID == FixtureLibrary.jeopardyID)

        let tetris = try #require(snapshot.game(id: FixtureLibrary.tetrisID))
        let cover = await catalog.firstImage(for: tetris)
        #expect(cover?.url.lastPathComponent == "Super Tetris-01.png")
    }

    @Test func findsVideoManualMusicAndExtras() async throws {
        let snapshot = try FixtureLibrary.snapshot()
        let catalog = MediaCatalog(snapshot: snapshot)
        let ultima = try #require(snapshot.game(id: FixtureLibrary.ultimaID))
        #expect(await catalog.video(for: ultima)?.lastPathComponent == "Ultima V - Warriors of Destiny (1988).mp4")
        #expect(await catalog.manual(for: ultima)?.lastPathComponent == "Ultima V - Warriors of Destiny (1988).pdf")
        #expect(await catalog.music(for: ultima) == nil)
        let tetris = try #require(snapshot.game(id: FixtureLibrary.tetrisID))
        #expect(await catalog.music(for: tetris)?.lastPathComponent == "Super Tetris (1991).mp3")

        let extras = await catalog.extras(for: ultima)
        #expect(extras.map(\.name) == ["Cluebook", "Map", "Master Ultima (Guide Book)"])
        #expect(extras.filter(\.isGuideBook).map(\.name) == ["Master Ultima (Guide Book)"])

        let gallery = await catalog.gallery(for: ultima)
        #expect(gallery.first?.kind == .video)
        #expect(gallery.map(\.label).contains("Title screen"))
    }
}

@Suite("Media index store")
struct MediaIndexStoreTests {
    @Test func savesAndReloadsWhileFolderUnchanged() throws {
        let folder = FixtureLibrary.root.imagesDirectory.appendingPathComponent("MS-DOS/Box - Front", isDirectory: true)
        let scanned = MediaFolderIndex.scan(folder: folder)
        #expect(scanned.fileCount == 4)
        let store = MediaIndexStore(directory: try FixtureLibrary.scratchDirectory().appendingPathComponent("MediaIndex"))
        #expect(store.load(folder: folder) == nil)
        store.save(scanned)
        let loaded = try #require(store.load(folder: folder))
        #expect(loaded.fileCount == 4)
        #expect(loaded.files(forTitle: "Super Tetris", gameID: "x").first?.url.lastPathComponent == "Super Tetris-01.png")
        store.clear()
        #expect(store.load(folder: folder) == nil)
    }
}
