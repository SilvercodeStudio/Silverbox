import Foundation
import Testing

@testable import SilverboxCore

/// A small eXo download, laid out as the torrent ships it, before setup.
nonisolated enum DownloadFixture {
    static let gameID = "dddddddd-0000-0000-0000-000000000001"
    static let adultID = "dddddddd-0000-0000-0000-000000000002"
    static let win9xID = "dddddddd-0000-0000-0000-000000000003"

    static func game(id: String, title: String, platform: String, folder: String) -> String {
        """
          <Game>
            <ID>\(id)</ID>
            <Title>\(title)</Title>
            <Platform>\(platform)</Platform>
            <ApplicationPath>\(folder)\\\(title) (1990).bat</ApplicationPath>
            <RootFolder>\(folder)</RootFolder>
          </Game>

        """
    }

    static let mini = game(id: gameID, title: "Mini Game", platform: "MS-DOS", folder: "eXo\\eXoDOS\\!dos\\mini")
    static let adult = game(id: adultID, title: "Adult Game", platform: "MS-DOS", folder: "eXo\\eXoDOS\\!dos\\adult")
    static let win9x = game(
        id: win9xID, title: "Win Game", platform: "Windows 9x", folder: "eXo\\eXoWin9x\\!win9x\\1996\\Win Game (1996)")

    static func list(_ games: String) -> String {
        "\u{FEFF}<?xml version=\"1.0\" standalone=\"yes\"?>\n<LaunchBox>\n\(games)</LaunchBox>\n"
    }

    /// The batch files eXo ships in `xml/`, with Windows line endings.
    static func mergeScript(output: String, pattern: String) -> String {
        let quoted = output.contains(" ") ? "\"\(output)\"" : output
        return [
            "@echo off",
            "echo ^<?xml version=\"1.0\" standalone=\"yes\"?^> > \(quoted)",
            "echo ^<LaunchBox^> >> \(quoted)",
            "type .\\\(pattern) >> \(quoted)",
            "echo . >> \(quoted)",
            "echo ^</LaunchBox^> >> \(quoted)",
        ].joined(separator: "\r\n")
    }

    /// Writes `files` (relative path to text) and zips them into `archive`.
    static func zip(_ files: [String: String], to archive: URL, scratch: URL) async throws {
        let stage = scratch.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in files {
            let url = stage.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(
            at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = try await CommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", archive.path, "."],
            workingDirectory: stage)
        #expect(result.status == 0, Comment(rawValue: result.output))
        try FileManager.default.removeItem(at: stage)
    }

    static func make(in scratch: URL) async throws -> URL {
        let download = scratch.appendingPathComponent("download", isDirectory: true)
        let content = download.appendingPathComponent("Content", isDirectory: true)
        try await zip(
            [
                "eXo/eXoDOS/!dos/mini/Mini Game (1990).bat": "@echo off",
                "eXo/eXoDOS/!dos/mini/dosbox.conf": "[autoexec]\nmount c .\\eXoDOS\\mini\n",
            ], to: content.appendingPathComponent("!DOSmetadata.zip"), scratch: scratch)
        try await zip(
            [
                "Images/MS-DOS/Box - Front/Mini Game-01.png": "png",
                "Plugins/eXoPlugin.dll": "dll",
                "xml/all/MS-DOS.xml": list(mini + adult),
                "xml/family/MS-DOS.xml": list(mini),
                "xml/all/1994-1996.9x": win9x,
                "xml/family/1994-1996.9x": "",
                "xml/platforms/ms-dos.platforms":
                    "  <Platform>\n    <Name>MS-DOS</Name>\n  </Platform>\n  <PlatformCategory>\n    <Name>Computers</Name>\n  </PlatformCategory>\n",
                "xml/platforms/windows9x.platforms":
                    "\u{FEFF}  <Platform>\n    <Name>Windows 9x</Name>\n  </Platform>\n",
                "xml/parents/ms-dos.parent":
                    "  <Parent>\n    <PlatformName>MS-DOS</PlatformName>\n    <ParentPlatformCategoryName>Computers</ParentPlatformCategoryName>\n  </Parent>\n",
                "xml/merge_platforms.bat": mergeScript(output: "Platforms.xml", pattern: "platforms\\*.platforms"),
                "xml/merge_parents.bat": mergeScript(output: "Parents.xml", pattern: "parents\\*.parent"),
                "xml/merge_9xall.bat": mergeScript(output: "Windows 9x.xml", pattern: "all\\*.9x"),
                "xml/merge_9xfamily.bat": mergeScript(output: "Windows 9x.xml", pattern: "family\\*.9x"),
                "xml/Playlists/Favorites.xml": list(""),
            ], to: content.appendingPathComponent("XODOSMetadata.zip"), scratch: scratch)
        try await zip(
            [
                "Data/Platforms/MS-DOS Books.xml": list(
                    game(
                        id: "dddddddd-0000-0000-0000-000000000009", title: "A Book", platform: "MS-DOS Books",
                        folder: "eXo\\Books")),
                "eXo/Books/A Book.pdf": "pdf",
            ], to: content.appendingPathComponent("DOSBooks.zip"), scratch: scratch)
        try await zip(
            ["Data/Platforms/MS-DOS Magazines.xml": list("")],
            to: content.appendingPathComponent("DOS_linux_Magazines.zip"), scratch: scratch)
        try await zip(
            ["Manuals/MS-DOS/Mini Game (1990).pdf": "manual"],
            to: content.appendingPathComponent("GameData/eXoDOS/Mini Game (1990).zip"), scratch: scratch)

        // util.zip holds the nested EXT and OPT archives.
        let nested = scratch.appendingPathComponent("nested", isDirectory: true)
        try await zip(
            ["mt32/MT32_CONTROL.ROM": "rom"], to: nested.appendingPathComponent("EXTDOS.zip"), scratch: scratch)
        try await zip(["GBC/readme.txt": "tool"], to: nested.appendingPathComponent("OPTDOS.zip"), scratch: scratch)
        try "zip".write(to: nested.appendingPathComponent("deprotect.zip"), atomically: true, encoding: .utf8)
        try "ultima5:dosbox.exe\n".write(
            to: nested.appendingPathComponent("dosbox.txt"), atomically: true, encoding: .utf8)
        let util = download.appendingPathComponent("eXo/util", isDirectory: true)
        try FileManager.default.createDirectory(at: util, withIntermediateDirectories: true)
        let result = try await CommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: [
                "-q", "-j", util.appendingPathComponent("util.zip").path, "EXTDOS.zip", "OPTDOS.zip", "deprotect.zip",
                "dosbox.txt",
            ],
            workingDirectory: nested)
        #expect(result.status == 0, Comment(rawValue: result.output))

        try await zip(
            ["mini/GAME.EXE": "exe"], to: download.appendingPathComponent("eXo/eXoDOS/Mini Game (1990).zip"),
            scratch: scratch)
        return download
    }
}

@Suite("Mac setup of eXo downloads")
struct SetupTests {
    @Test func inspectsADownload() async throws {
        let download = try await DownloadFixture.make(in: try FixtureLibrary.scratchDirectory())
        let found = try #require(await EXoDownload.inspect(download))
        #expect(found.packs.map(\.name) == ["DOS"])
        #expect(found.packs.first?.displayName == "eXoDOS")
        #expect(found.metadataArchives.map(\.lastPathComponent) == ["XODOSMetadata.zip"])
        #expect(found.addOns.map(\.platforms) == [["MS-DOS Books"]])
        #expect(found.addOns.first?.category == "Literature")
        #expect(found.addOns.first?.size ?? 0 > 0)
        #expect(found.gameDataArchives.map(\.lastPathComponent) == ["Mini Game (1990).zip"])
        #expect(found.utilArchives.map(\.lastPathComponent) == ["util.zip"])
        #expect(!found.isSetUp)
        #expect(await EXoDownload.inspect(FixtureLibrary.rootURL) == nil)
    }

    @Test func readsEXoMergeScripts() {
        let script = DownloadFixture.mergeScript(output: "Windows 9x.xml", pattern: "all\\*.9x")
        let merge = EXoSetup.mergeCommand(in: script)
        #expect(merge?.output == "Windows 9x.xml")
        #expect(merge?.folder == "all")
        #expect(merge?.fileExtension == "9x")
        let platforms = EXoSetup.mergeCommand(
            in: DownloadFixture.mergeScript(output: "Platforms.xml", pattern: "platforms\\*.platforms"))
        #expect(platforms?.output == "Platforms.xml")
        #expect(platforms?.folder == "platforms")
    }

    /// eXo's zips can hold names in the DOS code page without the UTF-8
    /// flag; they must come out as UTF-8 names.
    @Test func convertsDOSCodePageNames() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let archive = scratch.appendingPathComponent("names.zip")
        try await DownloadFixture.zip(["Ast#rix.txt": "text", "plain.txt": "text"], to: archive, scratch: scratch)
        // CP437 has é at 0x82.
        var data = try Data(contentsOf: archive)
        let placeholder = Data("Ast#rix".utf8)
        while let range = data.range(of: placeholder) {
            data.replaceSubrange(range, with: Data([0x41, 0x73, 0x74, 0x82, 0x72, 0x69, 0x78]))
        }
        try data.write(to: archive)

        let out = scratch.appendingPathComponent("out", isDirectory: true)
        try await ZipArchive.extract(archive, into: out)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).map {
            $0.precomposedStringWithCanonicalMapping
        }
        #expect(Set(names) == ["Astérix.txt", "plain.txt"])
        #expect(try await ZipArchive.entries(of: archive).count == 2)
    }

    /// A read-only download set up into another folder, without adult games,
    /// with the extras left for install time.
    @Test func setsUpIntoAnotherFolderAndInstallsFromTheDownload() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let downloadURL = try await DownloadFixture.make(in: scratch)
        let download = try #require(await EXoDownload.inspect(downloadURL))
        let target = scratch.appendingPathComponent("setup", isDirectory: true)
        let fractions = Fractions()
        try await EXoSetup(download: download, target: target, options: EXoSetupOptions(includeAdultGames: false))
            .run { fractions.add($0.fraction) }
        #expect(fractions.isIncreasing)
        #expect(fractions.last == 1)

        let fm = FileManager.default
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: target.appendingPathComponent(path).path) }
        #expect(exists("Images/MS-DOS/Box - Front/Mini Game-01.png"))
        #expect(!exists("Plugins/eXoPlugin.dll"))
        #expect(exists("eXo/eXoDOS/!dos/mini/dosbox.conf"))
        #expect(exists("eXo/Books/A Book.pdf"))
        #expect(exists("eXo/util/dosbox.txt"))
        #expect(exists("eXo/mt32/MT32_CONTROL.ROM"))
        #expect(exists("eXo/util/GBC/readme.txt"))
        #expect(!exists("eXo/util/EXTDOS.zip"))
        #expect(!exists("eXo/util/OPTDOS.zip"))
        #expect(!exists("eXo/util/deprotect.zip"))
        #expect(!exists("Manuals/MS-DOS/Mini Game (1990).pdf"))
        #expect(exists("Data/Playlists/Favorites.xml"))
        #expect(exists("Data/Platforms/Windows 9x.xml"))
        let record = try #require(EXoSetupRecord.read(in: target))
        #expect(record.packs == ["DOS"])
        #expect(record.downloadPath == downloadURL.standardizedFileURL.path)

        let collection = LibraryCollection(name: "eXoDOS", rootPath: target.path, downloadPath: downloadURL.path)
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let snapshot = try LibraryLoader(collection: collection, localStore: localStore).load()
        #expect(Set(snapshot.platforms.map(\.name)) == ["MS-DOS", "Windows 9x", "MS-DOS Books"])
        #expect(snapshot.game(id: DownloadFixture.gameID) != nil)
        #expect(snapshot.game(id: DownloadFixture.adultID) == nil)
        #expect(snapshot.game(id: DownloadFixture.win9xID) == nil)
        #expect(snapshot.games.contains { $0.platform == "MS-DOS Books" })
        #expect(snapshot.tree.contains { $0.title == "Literature" })

        // The game zip and its extras come from the download; the extras
        // unpack into the set-up folder.
        let game = try #require(snapshot.game(id: DownloadFixture.gameID))
        let installer = GameInstaller(snapshot: snapshot, installLocation: .localStore)
        let plan = try #require(installer.plan(for: game))
        #expect(plan.archiveURL.path == downloadURL.appendingPathComponent("eXo/eXoDOS/Mini Game (1990).zip").path)
        #expect(plan.extrasArchiveURL?.lastPathComponent == "Mini Game (1990).zip")
        try await installer.install(plan)
        #expect(exists("Manuals/MS-DOS/Mini Game (1990).pdf"))
        #expect(fm.fileExists(atPath: localStore.gamesDirectory.appendingPathComponent("mini/GAME.EXE").path))
    }

    /// A writable download set up in place, with adult games and all extras.
    @Test func setsUpInPlace() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let downloadURL = try await DownloadFixture.make(in: scratch)
        let download = try #require(await EXoDownload.inspect(downloadURL))
        try await EXoSetup(
            download: download, target: downloadURL,
            options: EXoSetupOptions(includeAdultGames: true, unpackGameData: true)
        ).run()
        #expect(
            FileManager.default.fileExists(
                atPath: downloadURL.appendingPathComponent("Manuals/MS-DOS/Mini Game (1990).pdf").path))
        #expect(try #require(await EXoDownload.inspect(downloadURL)).isSetUp)
        #expect(EXoSetupRecord.read(in: downloadURL)?.downloadPath == nil)

        let snapshot = try LibraryLoader(root: LibraryRoot(url: downloadURL)).load()
        #expect(snapshot.game(id: DownloadFixture.adultID) != nil)
        #expect(snapshot.game(id: DownloadFixture.win9xID)?.platform == "Windows 9x")
        // The extras are already there, so installing does not unpack them again.
        let game = try #require(snapshot.game(id: DownloadFixture.gameID))
        #expect(GameInstaller(snapshot: snapshot).plan(for: game)?.extrasArchiveURL == nil)
    }
}

/// Collects progress fractions from the setup's callback.
nonisolated private final class Fractions: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func add(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var last: Double? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }

    var isIncreasing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }
    }
}

/// Runs the Mac setup on the real download's original archives (the
/// `Content` and util zips kept beside the Windows setup), into the folder
/// in `SILVERBOX_SETUP_TARGET`, and compares the result with the Windows setup.
/// Takes a while: about 25 GB is unpacked.
@Suite(
    "Mac setup of the real download",
    .enabled(if: ProcessInfo.processInfo.environment["SILVERBOX_SETUP_TARGET"] != nil && RealLibrary.isAvailable))
struct RealSetupTests {
    @Test func matchesTheWindowsSetup() async throws {
        let target = URL(
            fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SILVERBOX_SETUP_TARGET"]),
            isDirectory: true
        )
        let download = try #require(await EXoDownload.inspect(RealLibrary.root.url))
        print("Packs: \(download.packs.map(\.displayName)), add-ons: \(download.addOns.flatMap(\.platforms))")
        print(
            "Setup archives: \(download.setupArchiveSize / 1_000_000_000) GB, extras: \(download.gameDataSize / 1_000_000_000) GB"
        )
        let start = Date()
        let last = LastStage()
        // SILVERBOX_SETUP_REUSE=1 keeps an earlier setup in the target.
        let reuse =
            ProcessInfo.processInfo.environment["SILVERBOX_SETUP_REUSE"] == "1"
            && EXoSetupRecord.read(in: target) != nil
        // The media add-ons are about 200 GB; leave them out.
        let options = EXoSetupOptions(skippedAddOns: download.addOns.map(\.archive.lastPathComponent))
        if !reuse {
            try await EXoSetup(download: download, target: target, options: options).run { progress in
                if last.changed(progress.stage + (progress.detail ?? "")) {
                    print(
                        String(format: "%5.1f%% %@ %@", progress.fraction * 100, progress.stage, progress.detail ?? ""))
                }
            }
        }
        print("Setup took \(Int(Date().timeIntervalSince(start))) s")

        let windows = try LibraryLoader(root: RealLibrary.root).load()
        let mac = try LibraryLoader(
            collection: LibraryCollection(
                name: "Mac setup", rootPath: target.path, downloadPath: RealLibrary.root.url.path)
        ).load()
        print("Windows setup: \(windows.games.count) games, Mac setup: \(mac.games.count) games")
        let addOnPlatforms = Set(download.addOns.flatMap(\.platforms))
        #expect(Set(mac.platforms.map(\.name)) == Set(windows.platforms.map(\.name)).subtracting(addOnPlatforms))
        let byPlatform = { (snapshot: LibrarySnapshot) in
            Dictionary(grouping: snapshot.games.filter { !addOnPlatforms.contains($0.platform) }, by: \.platform)
                .mapValues(\.count)
        }
        #expect(byPlatform(mac)["MS-DOS"] == byPlatform(windows)["MS-DOS"])
        // eXo's Windows script swaps the adult choice for Windows 9x: keeping
        // adult games merges the family list. The Mac merges the full list.
        let fullList = try String(contentsOf: target.appendingPathComponent("xml/all/1994-1996.9x"), encoding: .utf8)
        #expect(byPlatform(mac)["Windows 9x"] == fullList.components(separatedBy: "<Game>").count - 1)
        print(
            "Windows 9x: \(byPlatform(mac)["Windows 9x"] ?? 0) games (Windows setup: \(byPlatform(windows)["Windows 9x"] ?? 0))"
        )
        let asterix = target.appendingPathComponent("Images/MS-DOS/Box - 3D/Astérix_ Operation Getafix-01.png")
        #expect(FileManager.default.fileExists(atPath: asterix.path))
        #expect(mac.dosboxIndex.count == windows.dosboxIndex.count)
        #expect(
            FileManager.default.fileExists(
                atPath: target.appendingPathComponent("eXo/emulators/dosbox/x98/parent/W98-C.vhd").path))
        #expect(
            FileManager.default.fileExists(atPath: target.appendingPathComponent("eXo/emulators/86Box98/roms").path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("eXo/mt32").path))

        // Install a small game from the download into a scratch local store,
        // with its extras, and plan its launch from the set-up folder.
        let scratch = try FixtureLibrary.scratchDirectory()
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let collection = LibraryCollection(
            name: "Mac setup", rootPath: target.path, downloadPath: RealLibrary.root.url.path)
        let before = try LibraryLoader(collection: collection, localStore: localStore).load()
        let tetris = try #require(before.games.first { $0.title == "Super Tetris" })
        let installer = GameInstaller(snapshot: before, installLocation: .localStore)
        let plan = try #require(installer.plan(for: tetris))
        #expect(plan.archiveURL.path.hasPrefix(RealLibrary.root.url.path))
        #expect(plan.extrasArchiveURL != nil)
        try await installer.install(plan)
        let after = try LibraryLoader(collection: collection, localStore: localStore).load()
        #expect(after.installedLocation(for: tetris)?.isLocal == true)
        let manuals = try FileManager.default.contentsOfDirectory(
            atPath: target.appendingPathComponent("Manuals/MS-DOS").path)
        #expect(manuals.contains { $0.hasPrefix("Super Tetris") })
        let emulator = try FixtureLibrary.fakeEmulator(.dosboxStaging, in: scratch)
        let launch = try LaunchPlanner(snapshot: after, scratchDirectory: scratch).plan(
            game: tetris, variant: nil, emulator: emulator, options: LaunchOptions())
        #expect(launch.notes.filter { $0.hasPrefix("Could not find") }.isEmpty, "\(launch.notes)")
        #expect(launch.configText.contains(localStore.gamesDirectory.path))
        print("Super Tetris launch notes: \(launch.notes)")
    }
}

nonisolated private final class LastStage: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func changed(_ stage: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard stage != value else { return false }
        value = stage
        return true
    }
}
