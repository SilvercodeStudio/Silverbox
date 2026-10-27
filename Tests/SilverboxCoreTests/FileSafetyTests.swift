import Foundation
import Testing

@testable import SilverboxCore

nonisolated private enum SafetyFixture {
    static func installation() async throws -> (GameInstaller, InstallPlan) {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = LibraryRoot(url: scratch.appendingPathComponent("library"))
        let store = LocalStore(directory: scratch.appendingPathComponent("local"))
        let game = Game(
            id: "mini", title: "Mini Game", platform: "MS-DOS",
            applicationPath: "eXo\\eXoDOS\\!dos\\MiniGame\\Mini Game.bat", rootFolder: "eXo\\eXoDOS\\!dos\\MiniGame")
        try await DownloadFixture.zip(
            ["MiniGame/GAME.EXE": "original"],
            to: root.gamesDirectory.appendingPathComponent("Mini Game.zip"), scratch: scratch)
        let snapshot = LibrarySnapshot(
            root: root, games: [game], platforms: [], categories: [], platformFolders: [],
            playlists: [], parents: [], alternateNames: [], additionalApplications: [], installedGamePaths: [],
            localStore: store)
        let installer = GameInstaller(snapshot: snapshot)
        return (installer, try #require(installer.plan(for: game)))
    }
}

nonisolated private struct InterruptedExtractor: ArchiveExtractor {
    var cancelled = false
    func extract(archive: URL, into directory: URL) async throws {
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("MiniGame"), withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("MiniGame/GAME.EXE"))
        if cancelled { throw CancellationError() }
        throw CocoaError(.fileWriteOutOfSpace)
    }
    func extract(archive: URL, into directory: URL, only patterns: [String]) async throws {
        try await extract(archive: archive, into: directory)
    }
    func extract(archive: URL, into directory: URL, only patterns: [String], onFile: (@Sendable (Int) -> Void)?)
        async throws
    {
        try await extract(archive: archive, into: directory)
    }
}

nonisolated private struct PausedExtractor: ArchiveExtractor {
    let started: AsyncStream<Void>.Continuation
    let resume: AsyncStream<Void>

    func extract(archive: URL, into directory: URL) async throws {
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("MiniGame"), withIntermediateDirectories: true)
        started.yield(())
        for await _ in resume { break }
        try Task.checkCancellation()
    }
    func extract(archive: URL, into directory: URL, only patterns: [String]) async throws {
        try await extract(archive: archive, into: directory)
    }
    func extract(archive: URL, into directory: URL, only patterns: [String], onFile: (@Sendable (Int) -> Void)?)
        async throws
    {
        try await extract(archive: archive, into: directory)
    }
}

@Suite("File operation safety")
struct FileSafetyTests {
    @Test func failedBackupPreservesPreviousArchive() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        let save = plan.installedFolderURL.appendingPathComponent("SAVE.DAT")
        try Data("progress".utf8).write(to: save)
        try await SaveArchiver.backup(
            folder: plan.installedFolderURL, originalArchive: plan.archiveURL, to: plan.saveBackupURL)
        let previous = try Data(contentsOf: plan.saveBackupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: save.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: save.path) }
        await #expect(throws: (any Error).self) {
            try await SaveArchiver.backup(
                folder: plan.installedFolderURL, originalArchive: plan.archiveURL, to: plan.saveBackupURL)
        }
        #expect(try Data(contentsOf: plan.saveBackupURL) == previous)
        #expect(plan.isInstalled)
    }

    @Test func successfulBackupReplacesPreviousArchive() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        let save = plan.installedFolderURL.appendingPathComponent("SAVE.DAT")
        for progress in ["first", "second"] {
            try Data(progress.utf8).write(to: save)
            try await SaveArchiver.backup(
                folder: plan.installedFolderURL, originalArchive: plan.archiveURL, to: plan.saveBackupURL)
        }
        let read = try await CommandRunner.run(
            executable: SaveArchiver.unzipExecutable,
            arguments: ["-p", plan.saveBackupURL.path, "MiniGame/SAVE.DAT"])
        #expect(read.status == 0)
        #expect(read.output == "second")
    }

    @Test func hiddenFilesSurviveUninstallAndRestore() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        let hidden = plan.installedFolderURL.appendingPathComponent(".saves/.progress")
        try FileManager.default.createDirectory(
            at: hidden.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hidden progress".utf8).write(to: hidden)
        #expect(try await installer.uninstall(plan, backupSaves: true) == 1)
        var restore = plan
        restore.saveArchiveURL = plan.saveBackupURL
        try await installer.install(restore, restoreSaves: true)
        #expect(try Data(contentsOf: hidden) == Data("hidden progress".utf8))
    }

    @Test func unreadableSubtreePreventsRemoval() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        let saves = plan.installedFolderURL.appendingPathComponent("saves")
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Data("save".utf8).write(to: saves.appendingPathComponent("progress"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: saves.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: saves.path) }
        await #expect(throws: (any Error).self) { try await installer.uninstall(plan, backupSaves: true) }
        #expect(plan.isInstalled)
    }

    @Test(arguments: [false, true]) func interruptedInstallNeverPublishesPartialGame(cancelled: Bool) async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        await #expect(throws: (any Error).self) {
            try await installer.install(plan, extractor: InterruptedExtractor(cancelled: cancelled))
        }
        #expect(!plan.isInstalled)
        #expect(LibraryLoader.installedGamePaths(in: installer.snapshot.localStore!.gamesRoot).isEmpty)
        try await installer.install(plan)
        #expect(plan.isInstalled)
    }

    @Test func existingInstallationIsNeverOverwrittenOrRemoved() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        let save = plan.installedFolderURL.appendingPathComponent("SAVE.DAT")
        try Data("keep me".utf8).write(to: save)
        await #expect(throws: InstallError.alreadyInstalled(plan.installedFolderURL)) {
            try await installer.install(plan, extractor: InterruptedExtractor(cancelled: true))
        }
        #expect(try Data(contentsOf: save) == Data("keep me".utf8))
    }

    @Test func playingReservationPreventsInstallAndUninstall() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        let lease = try FileOperationCoordinator.shared.acquire([plan.installedFolderURL], operation: "a running game")
        defer { lease.release() }
        await #expect(throws: FileOperationConflict.self) { try await installer.uninstall(plan, backupSaves: false) }
        await #expect(throws: FileOperationConflict.self) { try await installer.install(plan) }
        #expect(plan.isInstalled)
    }

    @Test func duplicateCollectionCannotInstallOverAnotherRun() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        let first = Task {
            try await installer.install(
                plan, extractor: PausedExtractor(started: started.continuation, resume: resume.stream))
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        var duplicate = plan
        duplicate.game.collectionID = UUID()
        #expect(duplicate.game.id != plan.game.id)
        await #expect(throws: FileOperationConflict.self) { try await installer.install(duplicate) }
        first.cancel()
        resume.continuation.yield(())
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(!plan.isInstalled)
        try await installer.install(duplicate)
        #expect(plan.isInstalled)
    }

    @Test func unrelatedExtrasDoNotLockTheWholeCollection() async throws {
        let (installer, base) = try await SafetyFixture.installation()
        let scratch = try FixtureLibrary.scratchDirectory()
        var firstPlan = base
        firstPlan.extrasArchiveURL = scratch.appendingPathComponent("first.zip")
        firstPlan.extrasDestination = scratch.appendingPathComponent("collection")
        try await DownloadFixture.zip(["Manuals/first.pdf": "first"], to: firstPlan.extrasArchiveURL!, scratch: scratch)
        var second = firstPlan
        second.installedFolderURL = base.destinationDirectory.appendingPathComponent("SecondGame")
        second.archiveURL = base.archiveURL.deletingLastPathComponent().appendingPathComponent("Second Game.zip")
        second.saveBackupURL = base.saveBackupURL.deletingLastPathComponent().appendingPathComponent("second.zip")
        try FileManager.default.copyItem(at: base.archiveURL, to: second.archiveURL)
        second.extrasArchiveURL = scratch.appendingPathComponent("second.zip")
        try await DownloadFixture.zip(["Manuals/second.pdf": "second"], to: second.extrasArchiveURL!, scratch: scratch)
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        let first = Task {
            try await installer.install(
                firstPlan, extractor: PausedExtractor(started: started.continuation, resume: resume.stream))
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        // Reaching the extractor (and its deliberate cancellation) proves
        // this did not fail with a reservation conflict on the collection.
        await #expect(throws: CancellationError.self) {
            try await installer.install(second, extractor: InterruptedExtractor(cancelled: true))
        }
        first.cancel()
        resume.continuation.yield(())
        await #expect(throws: CancellationError.self) { try await first.value }
    }

    @Test func symbolicLinkCannotSilentlyEscapeBackup() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        try await installer.install(plan)
        try FileManager.default.createSymbolicLink(
            at: plan.installedFolderURL.appendingPathComponent("saves"),
            withDestinationURL: plan.archiveURL.deletingLastPathComponent())
        await #expect(throws: SaveBackupError.self) { try await installer.uninstall(plan, backupSaves: true) }
        #expect(plan.isInstalled)
        #expect(plan.archiveExists)
    }

    @Test func reservationsRecognizeAliasesAndFolderBoundaries() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let real = scratch.appendingPathComponent("Games")
        let alias = scratch.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let coordinator = FileOperationCoordinator()
        let lease = try coordinator.acquire([real.appendingPathComponent("Mini")], operation: "install")
        defer { lease.release() }
        #expect(throws: FileOperationConflict.self) {
            try coordinator.acquire([alias.appendingPathComponent("mini/SAVE")], operation: "play")
        }
        #expect(throws: FileOperationConflict.self) { try coordinator.acquire([real], operation: "setup") }
        let independent = try coordinator.acquire([real.appendingPathComponent("Mini2")], operation: "other game")
        independent.release()
        lease.release()
        let retry = try coordinator.acquire([alias.appendingPathComponent("Mini")], operation: "retry")
        retry.release()
    }

    @Test func win9xPlansReserveVMAndInstallationBeforeWriting() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = try Win9xFixture.makeLibrary(in: scratch, unpacked: true)
        let store = LocalStore(directory: scratch.appendingPathComponent("local"))
        let planner = LaunchPlanner(
            snapshot: Win9xFixture.snapshot(root: root, localStore: store), scratchDirectory: scratch)
        for (game, kind) in [
            (Win9xFixture.game(), EmulatorKind.dosboxX), (Win9xFixture.game(Win9xFixture.boxTitle), .box86),
        ] {
            let plan = try planner.plan(
                game: game, variant: nil,
                emulator: FixtureLibrary.fakeEmulator(kind, in: scratch), options: LaunchOptions())
            let coordinator = FileOperationCoordinator()
            let first = try coordinator.acquire(plan.operationURLs, operation: "playing")
            defer { first.release() }
            let vm = kind == .box86 ? planner.local86BoxDirectory : planner.windowsDiskDirectory
            #expect(throws: FileOperationConflict.self) { try coordinator.acquire([vm], operation: "another VM") }
            #expect(throws: FileOperationConflict.self) {
                try coordinator.acquire([try #require(plan.installedFolderURL)], operation: "uninstall")
            }
        }
    }

    @Test func backupsAreScopedToPhysicalInstallation() async throws {
        let (installer, plan) = try await SafetyFixture.installation()
        let store = try #require(installer.snapshot.localStore)
        var copy = plan.game
        copy.collectionID = UUID()
        #expect(store.saveArchiveURL(for: copy, installation: plan.installedFolderURL) == plan.saveBackupURL)
        #expect(
            store.saveArchiveURL(for: copy, installation: plan.installedFolderURL.appendingPathComponent("other"))
                != plan.saveBackupURL)
        let moved = LocalStore(directory: store.directory.deletingLastPathComponent().appendingPathComponent("moved"))
        let movedInstallation = moved.gamesDirectory.appendingPathComponent("MiniGame")
        #expect(
            moved.saveArchiveURL(for: plan.game, installation: movedInstallation).deletingLastPathComponent()
                .lastPathComponent
                == plan.saveBackupURL.deletingLastPathComponent().lastPathComponent)
        let legacy = store.saveArchiveURL(for: plan.game)
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: plan.archiveURL, to: legacy)
        #expect(installer.plan(for: plan.game)?.saveArchiveURL == legacy)
    }
}

@Suite("Archive failure safety")
struct ArchiveSafetyTests {
    @Test func extractorStartupFailureReturnsWithoutWaitingForPipeEOF() async throws {
        let missing = try FixtureLibrary.scratchDirectory().appendingPathComponent("missing-extractor")
        await #expect(throws: CocoaError.self) {
            _ = try await ZipArchive.runExtractor(executable: missing, arguments: [])
        }
    }

    @Test func cancelledExtractionThrowsWithoutStartingAProcess() async throws {
        let (_, plan) = try await SafetyFixture.installation()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ZipArchive.extract(plan.archiveURL, into: plan.destinationDirectory)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func processCancellationBeforeAndAfterLaunchIsSafe() throws {
        let before = CancellableProcess()
        before.cancel()
        #expect(throws: CancellationError.self) { try before.run() }
        let during = CancellableProcess()
        during.process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        during.process.arguments = ["30"]
        try during.run()
        during.cancel()
        during.process.waitUntilExit()
        during.finished()
        during.cancel()
        #expect(!during.process.isRunning)
    }

    @Test func truncatedEndRecordThrowsInsteadOfTrapping() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let archive = scratch.appendingPathComponent("bad.zip")
        for length in 4..<22 {
            try (Data([0x50, 0x4B, 0x05, 0x06]) + Data(count: length - 4)).write(to: archive)
            #expect(throws: ZipArchiveError.self) { try ZipArchive.centralDirectory(of: archive) }
            #expect(ZipArchive.unpackedSize(of: archive, matching: "") == 0)
        }
    }

    @Test func signatureInsideZipCommentDoesNotHideRealEndRecord() async throws {
        let (_, plan) = try await SafetyFixture.installation()
        var data = try Data(contentsOf: plan.archiveURL)
        let comment = Data([0x50, 0x4B, 0x05, 0x06])
        data[data.count - 2] = UInt8(comment.count)
        data.append(comment)
        try data.write(to: plan.archiveURL)
        #expect(try ZipArchive.centralDirectory(of: plan.archiveURL).contains { $0.path == "MiniGame/GAME.EXE" })
    }

    @Test func invalidZip64OffsetsThrowInsteadOfAllocating() throws {
        let archive = try FixtureLibrary.scratchDirectory().appendingPathComponent("bad64.zip")
        var data = Data([0x50, 0x4B, 0x06, 0x07]) + Data(count: 4) + Data(repeating: 0xFF, count: 8) + Data(count: 4)
        data += Data([0x50, 0x4B, 0x05, 0x06]) + Data(count: 8) + Data(repeating: 0xFF, count: 8) + Data(count: 2)
        try data.write(to: archive)
        #expect(throws: ZipArchiveError.self) { try ZipArchive.centralDirectory(of: archive) }
    }
}
