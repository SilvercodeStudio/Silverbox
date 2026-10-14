import Foundation
import Testing

@testable import eXoCore

/// The eXo packs beyond eXoDOS and eXoWin9x: how their games are recognised,
/// found once unpacked, and set up.
@Suite("eXo packs")
struct PackTests {
    static func game(_ title: String, folder: String, platform: String = "eXoDemoScene") -> Game {
        Game(
            id: "pack-\(title)", title: title, platform: platform,
            applicationPath: "\(folder)\\\(title).bat", rootFolder: folder)
    }

    static let demo = game("realtime (1993)", folder: "eXo\\eXoDemoScn\\!demoscn\\realtime")

    @Test func recognisesEachPackFromItsConfigFolder() {
        #expect(Self.demo.eXoPack == .demoScene)
        #expect(Self.demo.installPath == "eXoDemoScn/realtime")
        #expect(Self.demo.isDOSGame)
        #expect(Self.demo.launchKind == .dosBox)

        let scumm = Self.game(
            "Beneath a Steel Sky (CD DOS)", folder: "eXo\\eXoScummVM\\!ScummVM\\Beneath a Steel Sky (CD DOS)",
            platform: "ScummVM")
        #expect(scumm.eXoPack == .scummVM)
        #expect(scumm.installPath == "eXoScummVM/Beneath a Steel Sky (CD DOS)")
        #expect(!scumm.isDOSGame)

        let iigs = Self.game(
            "Arkanoid (1987)", folder: "eXo\\eXoAppleIIGS\\!appleiigs\\Arkanoid (1987)", platform: "Apple IIGS")
        #expect(iigs.eXoPack == .appleIIGS)

        // eXoIF writes some root folders with a trailing backslash.
        let zork = Self.game(
            "Zork I (1980)", folder: "eXo\\eXoIF\\!IF\\Zork I (1980)\\", platform: "Interactive Fiction")
        #expect(zork.eXoPack == .interactiveFiction)
        #expect(zork.installPath == "eXoIF/Zork I (1980)")
    }

    @Test func hidesEachPacksSetupScript() {
        let setup = Game(
            id: "setup", title: "eXoDemoScene", platform: "eXoDemoScene", applicationPath: "Setup eXoDemoScene.bat")
        #expect(setup.isEXoSetupScript)
        #expect(!Self.demo.isEXoSetupScript)
    }

    @Test func classifiesNewerDOSBoxXBuilds() {
        for path in ["X_2024\\dosbox-x.exe", "X_Nov\\dosbox-x.exe", "x-if\\dosbox-x.exe", "x\\dosbox.exe"] {
            #expect(EXoDOSBuild(rawPath: path).family == .x, "\(path)")
        }
        #expect(EXoDOSBuild(rawPath: "staging0.82.0\\dosbox.exe").family == .staging)
    }

    @Test func findsUnpackedFoldersWhateverTheirCase() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
        let fm = FileManager.default
        // A demo whose zip unpacks to upper case, and a hidden ScummVM folder.
        for folder in ["eXoDemoScn/REALTIME", "eXoScummVM/.i.f (Macintosh)", "eXoDemoScn/!demoscn/realtime"] {
            try fm.createDirectory(
                at: root.eXoDirectory.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true)
        }
        let paths = LibraryLoader.installedGamePaths(in: root.eXoDirectory)
        #expect(paths == ["eXoDemoScn/REALTIME", "eXoScummVM/.i.f (Macintosh)"])

        let hidden = Self.game(".i.f (Macintosh)", folder: "eXo\\eXoScummVM\\!ScummVM\\.i.f (Macintosh)")
        let snapshot = LibrarySnapshot(
            root: root, games: [Self.demo, hidden], platforms: [], categories: [], platformFolders: [],
            playlists: [], parents: [], alternateNames: [], additionalApplications: [], installedGamePaths: paths)
        #expect(
            snapshot.installedLocation(for: Self.demo)
                == .library(root.eXoDirectory.appendingPathComponent("eXoDemoScn/REALTIME", isDirectory: true)))
        #expect(snapshot.isInstalled(hidden))
    }

    @Test func plansADemoInstalledInTheLocalStore() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let fm = FileManager.default
        let root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
        let configs = root.gameConfigsDirectory(for: .demoScene).appendingPathComponent("realtime", isDirectory: true)
        try fm.createDirectory(at: configs, withIntermediateDirectories: true)
        try "[cpu]\ncycles=fixed 20000\n[autoexec]\n@mount c .\\eXoDemoScn\\realtime\nc:\nREALTIME.EXE\nexit\n"
            .write(to: configs.appendingPathComponent("dosbox.conf"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.utilDirectory, withIntermediateDirectories: true)
        try "realtime (1993):X_2024\\dosbox-x.exe\n".write(
            to: root.utilDirectory.appendingPathComponent("demoscn.txt"), atomically: true, encoding: .utf8)

        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let installed = localStore.gamesDirectory(for: .demoScene).appendingPathComponent("realtime", isDirectory: true)
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)

        let snapshot = LibrarySnapshot(
            root: root, games: [Self.demo], platforms: [], categories: [], platformFolders: [], playlists: [],
            parents: [], alternateNames: [], additionalApplications: [],
            dosboxIndexes: [
                .demoScene: try DOSBoxIndex(contentsOf: try #require(root.dosboxIndexFile(for: .demoScene)))
            ],
            installedGamePaths: [], localStore: localStore,
            locallyInstalledGamePaths: LibraryLoader.installedGamePaths(in: localStore.gamesRoot))
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        #expect(planner.recommendedEmulator(for: Self.demo) == .dosboxX)

        let emulator = try FixtureLibrary.fakeEmulator(.dosboxX, in: scratch)
        let plan = try planner.plan(game: Self.demo, variant: nil, emulator: emulator, options: LaunchOptions())
        let doc = DOSBoxConfigDocument.parse(plan.configText)
        #expect(doc.autoexecLines.first == "@mount c \"\(installed.path)\"")
    }

    @Test func unpacksAddOnsThatNameNoPlatform() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let download = scratch.appendingPathComponent("download", isDirectory: true)
        let content = download.appendingPathComponent("Content", isDirectory: true)
        try await DownloadFixture.zip(
            ["eXo/eXoAppleIIGS/!appleiigs/Arkanoid (1987)/Arkanoid (1987).bat": "@echo off"],
            to: content.appendingPathComponent("!AppleIIGSmetadata.zip"), scratch: scratch)
        let magazines = DownloadFixture.list(
            DownloadFixture.game(
                id: "dddddddd-0000-0000-0000-000000000010", title: "GS+", platform: "Apple IIGS Magazines",
                folder: "eXo\\Magazines"))
        try await DownloadFixture.zip(
            [
                "xml/all/Apple IIGS.xml": DownloadFixture.list(""),
                "xml/Apple IIGS Magazines.xml": magazines,
                "xml/platforms/appleIIGS.platforms": "  <Platform>\n    <Name>Apple IIGS</Name>\n  </Platform>\n",
                "xml/merge_platforms.bat": DownloadFixture.mergeScript(
                    output: "Platforms.xml", pattern: "platforms\\*.platforms"),
            ], to: content.appendingPathComponent("XOAppleIIGSMetadata.zip"), scratch: scratch)
        try await DownloadFixture.zip(
            ["Magazines/GS+.pdf": "pdf"], to: content.appendingPathComponent("Mag!AppleIIGS.zip"), scratch: scratch)
        try await DownloadFixture.zip(
            ["eXo/Videos/Demo Film/film.mp4": "mp4"], to: content.appendingPathComponent("DSNVideos.zip"),
            scratch: scratch)

        let inspected = await EXoDownload.inspect(download)
        let found = try #require(inspected)
        #expect(found.packs.map(\.displayName) == ["eXoAppleIIGS"])
        #expect(found.addOns.map(\.title) == ["Videos", "Magazines"])
        #expect(found.addOns.map(\.category) == ["Video", "Literature"])

        let target = scratch.appendingPathComponent("setup", isDirectory: true)
        try await EXoSetup(download: found, target: target, options: EXoSetupOptions()).run { _ in }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: target.appendingPathComponent("eXo/Magazines/GS+.pdf").path))
        #expect(fm.fileExists(atPath: target.appendingPathComponent("eXo/Videos/Demo Film/film.mp4").path))
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Data/Platforms/Apple IIGS Magazines.xml").path))
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Data/Platforms.xml").path))
    }

    @Test func leavesExtrasAndWindowsBuildsPackedUntilInstall() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let download = scratch.appendingPathComponent("download", isDirectory: true)
        let content = download.appendingPathComponent("Content", isDirectory: true)
        let folder = "eXo/eXoScummVM/!ScummVM/Sky [CD]"
        try await DownloadFixture.zip(
            [
                "\(folder)/Sky [CD].bat": "@echo off",
                "\(folder)/Extras/Guide.pdf": String(repeating: "pdf ", count: 1000),
            ], to: content.appendingPathComponent("!ScummVMmetadata.zip"), scratch: scratch)
        try await DownloadFixture.zip(
            [
                "xml/all/ScummVM.xml": DownloadFixture.list(
                    DownloadFixture.game(
                        id: "dddddddd-0000-0000-0000-000000000020", title: "Sky [CD]", platform: "ScummVM",
                        folder: "eXo\\eXoScummVM\\!ScummVM\\Sky [CD]")),
                "xml/platforms/scummvm.platforms": "  <Platform>\n    <Name>ScummVM</Name>\n  </Platform>\n",
                "xml/merge_platforms.bat": DownloadFixture.mergeScript(
                    output: "Platforms.xml", pattern: "platforms\\*.platforms"),
            ], to: content.appendingPathComponent("XOScummVMMetadata.zip"), scratch: scratch)
        let nested = scratch.appendingPathComponent("nested", isDirectory: true)
        try await DownloadFixture.zip(
            ["emulators/scmvm/scummvm.exe": "exe", "emulators/scmvm/scummvm.ini": "[scummvm]\n"],
            to: nested.appendingPathComponent("EXTsvm.zip"), scratch: scratch)
        let util = download.appendingPathComponent("eXo/util", isDirectory: true)
        try FileManager.default.createDirectory(at: util, withIntermediateDirectories: true)
        let zipped = try await CommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-j", util.appendingPathComponent("utilSVM.zip").path, "EXTsvm.zip"],
            workingDirectory: nested)
        #expect(zipped.status == 0)
        try await DownloadFixture.zip(
            ["Sky [CD]/Sky (CD DOS)/sky.dsk": "data"],
            to: download.appendingPathComponent("eXo/eXoScummVM/Sky [CD] (1990).zip"), scratch: scratch)

        let found = try #require(await EXoDownload.inspect(download))
        #expect(found.packs.first?.hasGameData == false)
        #expect(found.packedExtrasSize == 4000)

        let target = scratch.appendingPathComponent("setup", isDirectory: true)
        try await EXoSetup(download: found, target: target, options: EXoSetupOptions()).run { _ in }
        let fm = FileManager.default
        let guide = target.appendingPathComponent("\(folder)/Extras/Guide.pdf")
        #expect(fm.fileExists(atPath: target.appendingPathComponent("\(folder)/Sky [CD].bat").path))
        #expect(!fm.fileExists(atPath: guide.path))
        #expect(fm.fileExists(atPath: target.appendingPathComponent("eXo/emulators/scmvm/scummvm.ini").path))
        #expect(!fm.fileExists(atPath: target.appendingPathComponent("eXo/emulators/scmvm/scummvm.exe").path))

        let collection = LibraryCollection(name: "ScummVM", rootPath: target.path, downloadPath: download.path)
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let snapshot = try LibraryLoader(collection: collection, localStore: localStore).load()
        let game = try #require(snapshot.games.first)
        #expect(game.launchKind == .scummVM)
        let installer = GameInstaller(snapshot: snapshot, installLocation: .localStore)
        let plan = try #require(installer.plan(for: game))
        #expect(plan.extrasPatterns == ["eXo/eXoScummVM/!ScummVM/Sky [[]CD]/Extras/*"])
        try await installer.install(plan)
        #expect(fm.fileExists(atPath: guide.path))
        #expect(
            fm.fileExists(
                atPath: localStore.gamesDirectory(for: .scummVM).appendingPathComponent("Sky [CD]/Sky (CD DOS)/sky.dsk")
                    .path))
    }
}
