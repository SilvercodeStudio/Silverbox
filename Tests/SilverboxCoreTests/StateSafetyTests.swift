import Foundation
import Testing

@testable import SilverboxCore

@Suite("State and setup safety")
struct StateSafetyTests {
    @Test func equalDownloadNamesHaveDifferentTargets() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let store = LocalStore(directory: scratch.appendingPathComponent("local"))
        let first = scratch.appendingPathComponent("driveA/eXoDOS")
        let second = scratch.appendingPathComponent("driveB/eXoDOS")
        let a = EXoSetupTarget.localTarget(for: first, in: store)
        let b = EXoSetupTarget.localTarget(for: second, in: store)
        #expect(a != b)
        try EXoSetupTarget.claim(a, for: first)
        #expect(EXoSetupTarget.localTarget(for: first, in: store) == a)
        #expect(!EXoSetupTarget.belongs(to: second, target: a))
        #expect(throws: EXoSetupTargetError.self) { try EXoSetupTarget.claim(a, for: second) }
        #expect(EXoSetupTarget.belongs(to: first, target: a))
    }

    @Test func legacySetupRequiresMatchingProvenance() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let store = LocalStore(directory: scratch.appendingPathComponent("local"))
        let source = scratch.appendingPathComponent("drive/eXoDOS")
        let legacy = store.directory.appendingPathComponent("Collections/eXoDOS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent("Data"), withIntermediateDirectories: true)
        try EXoSetupRecord(date: Date(), packs: ["DOS"], options: EXoSetupOptions(), downloadPath: source.path).write(
            in: legacy)
        #expect(EXoSetupTarget.localTarget(for: source, in: store) == legacy)
        #expect(EXoSetupTarget.localTarget(for: scratch.appendingPathComponent("other/eXoDOS"), in: store) != legacy)
    }

    @Test func occupiedSetupDestinationIsLeftUntouched() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let target = scratch.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let existing = target.appendingPathComponent("important.txt")
        try Data("keep".utf8).write(to: existing)
        #expect(throws: EXoSetupTargetError.self) {
            try EXoSetupTarget.claim(target, for: scratch.appendingPathComponent("download"))
        }
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    }

    @Test func scansMergeIntoCurrentLibraryAndRejectChangedSources() throws {
        let a = try FixtureLibrary.snapshot()
        let rootB = LibraryRoot(url: try FixtureLibrary.scratchDirectory())
        let b = LibrarySnapshot(
            root: rootB, games: [], platforms: [], categories: [], platformFolders: [], playlists: [],
            parents: [], alternateNames: [], additionalApplications: [], installedGamePaths: [])
        let scanA = InstalledGameScan(snapshot: a, libraryPaths: ["eXoDOS/newA"], localPaths: [])
        let scanB = InstalledGameScan(snapshot: b, libraryPaths: ["eXoDOS/newB"], localPaths: [])
        let original = Library(snapshots: [a, b])
        let merged = original.applying(scanB).applying(scanA)
        #expect(merged.snapshot(id: a.collection.id)?.installedGamePaths == ["eXoDOS/newA"])
        #expect(merged.snapshot(id: b.collection.id)?.installedGamePaths == ["eXoDOS/newB"])
        #expect(Library(snapshots: [a]).applying(scanB).snapshots.count == 1)
        var changedCollection = b.collection
        changedCollection.rootPath = rootB.url.appendingPathComponent("moved").path
        let changed = LibrarySnapshot(
            root: changedCollection.root, collection: changedCollection, games: [], platforms: [],
            categories: [], platformFolders: [], playlists: [], parents: [], alternateNames: [],
            additionalApplications: [], installedGamePaths: [])
        #expect(Library(snapshots: [changed]).applying(scanB).snapshots[0].installedGamePaths.isEmpty)
    }

    @Test func corruptUserStateIsPreservedAndPreviousGenerationRecovered() throws {
        let store = UserLibraryStateStore(
            url: try FixtureLibrary.scratchDirectory().appendingPathComponent("state.json"))
        var previous = UserLibraryState()
        previous.update("keep") { $0.favorite = true }
        try store.save(previous)
        var latest = previous
        latest.update("new") { $0.completed = true }
        try store.save(latest)
        let broken = Data("{ damaged".utf8)
        try broken.write(to: store.url)
        let writer = UserLibraryStatePersistence(store: store)
        let recovery = try writer.load()
        #expect(recovery.state == previous)
        let preserved = try #require(recovery.preservedURL)
        #expect(try Data(contentsOf: preserved) == broken)
        writer.enqueue(latest)
        try writer.flush()
        #expect(try store.load() == latest)
        #expect(try Data(contentsOf: preserved) == broken)
    }

    @Test func pendingStateIsLatestAndFailedFlushCanRetry() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let parent = scratch.appendingPathComponent("parent")
        let store = UserLibraryStateStore(url: parent.appendingPathComponent("state.json"))
        let writer = UserLibraryStatePersistence(store: store)
        _ = try writer.load()
        var state = UserLibraryState()
        state.update("game") { $0.favorite = false }
        writer.enqueue(state)
        state.update("game") { $0.favorite = true }
        writer.enqueue(state)
        try Data("blocks directory creation".utf8).write(to: parent)
        #expect(throws: (any Error).self) { try writer.flush() }
        try FileManager.default.removeItem(at: parent)
        try writer.flush()
        #expect(try store.load() == state)
        try writer.flush()
        #expect(try store.load() == state)
    }

    @Test func savingWithoutSuccessfulLoadIsBlocked() throws {
        let store = UserLibraryStateStore(
            url: try FixtureLibrary.scratchDirectory().appendingPathComponent("state.json"))
        let writer = UserLibraryStatePersistence(store: store)
        writer.enqueue(UserLibraryState())
        #expect(throws: UserStatePersistenceError.self) { try writer.flush() }
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}

@Suite("Games left running")
struct RunningGameLedgerTests {
    @Test func keepsRecordsUntilNoneAreLeft() throws {
        let url = try FixtureLibrary.scratchDirectory().appendingPathComponent("running-games.json")
        let ledger = RunningGameLedger(url: url)
        #expect(ledger.load().isEmpty)
        let record = RunningGameRecord(
            id: UUID(), processIdentifier: 123, processStart: 1_761_500_000_123_456, title: "Mini Game",
            paths: ["/tmp/Games/eXoDOS/MiniGame"])
        try ledger.save([record])
        #expect(ledger.load() == [record])
        try ledger.save([])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // A damaged file reads as no games, so it never blocks anything.
        try Data("{".utf8).write(to: url)
        #expect(ledger.load().isEmpty)
    }
}
