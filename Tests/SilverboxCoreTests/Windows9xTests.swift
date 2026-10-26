import Foundation
import Testing

@testable import SilverboxCore

/// A small eXoWin9x library, made in a scratch folder: one DOSBox-X game
/// with network play, one 86Box game, and Windows 98 parent disks.
nonisolated enum Win9xFixture {
    static let title = "Mini Win (1996)"
    static let cdName = "Mini Win.cue"
    static let boxTitle = "Box Game (1996)"

    /// An 86Box config as eXo writes it: paths relative to `emulators/86Box98`,
    /// and a CD name in another case than the file.
    static let boxCfg = """
        [General]
        vid_renderer = qt_software

        [Machine]
        machine = 686bx

        [Hard disks]
        hdd_01_fn = W98-C.vhd
        hdd_01_ide_channel = 0:0
        hdd_02_fn = ../../eXoWin9x/1996/Box Game (1996)/Box Game (1996).vhd
        hdd_02_ide_channel = 0:1

        [Floppy and CD-ROM drives]
        cdrom_01_ide_channel = 1:0
        cdrom_01_image_path = ../../eXoWin9x/1996/Box Game (1996)/box.cue
        """

    static let playConf = """
        [sdl]
        fullscreen        = False
        windowresolution  = original
        output            = opengl
        mapperfile        = mapper-dosbox-x.map
        [dosbox]
        title  = eXo's Windows 98 BaseImage
        machine = svga_s3
        memsize = 64
        [render]
        scaler = normal2x
        [ne2000]
        ne2000  = true
        macaddr = AC:DE:48:88:89:AA
        backend = pcap
        [autoexec]
        # Lines in this section will be run at startup.
        vhdmake -f -l .\\emulators\\dosbox\\x98\\parent/W98-C-Net.vhd .\\emulators\\dosbox\\x98\\W98-H.vhd
        IMGMOUNT c .\\emulators\\dosbox\\x98\\W98-H.vhd
        IMGMOUNT d ".\\eXoWin9x\\1996\\Mini Win (1996)\\Mini Win (1996).vhd"
        IMGMOUNT e ".\\eXoWin9x\\1996\\Mini Win (1996)\\Mini Win.cue" -t cdrom -ide 2m
        echo off
        cls
        BOOT -l c
        """

    static func game(_ title: String = title) -> Game {
        Game(
            id: "win-\(title)", title: title, platform: "Windows 9x",
            applicationPath: "eXo\\eXoWin9x\\!win9x\\1996\\\(title)\\\(title).bat",
            configurationPath: "eXo\\eXoWin9x\\!win9x\\1996\\\(title)\\Install.bat",
            rootFolder: "eXo\\eXoWin9x\\!win9x\\1996\\\(title)")
    }

    /// Writes the library and returns its root. The game is unpacked in the
    /// library when `unpacked` is true.
    static func makeLibrary(in scratch: URL, unpacked: Bool) throws -> LibraryRoot {
        let fm = FileManager.default
        let root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
        let eXo = root.eXoDirectory
        let configs = eXo.appendingPathComponent("eXoWin9x/!win9x/1996/\(title)", isDirectory: true)
        try fm.createDirectory(at: configs, withIntermediateDirectories: true)
        try playConf.write(to: configs.appendingPathComponent("Play.conf"), atomically: true, encoding: .utf8)
        try "Write-Host".write(to: configs.appendingPathComponent("Network.ps1"), atomically: true, encoding: .utf8)

        let boxConfigs = eXo.appendingPathComponent("eXoWin9x/!win9x/1996/\(boxTitle)", isDirectory: true)
        try fm.createDirectory(at: boxConfigs, withIntermediateDirectories: true)
        try ("\u{FEFF}" + boxCfg).write(
            to: boxConfigs.appendingPathComponent("Play.cfg"), atomically: true, encoding: .utf8)
        try #"..\..\..\..\util\9xlaunch86Box.bat"#.write(
            to: boxConfigs.appendingPathComponent("\(boxTitle).bat"), atomically: true, encoding: .utf8)
        let util = eXo.appendingPathComponent("util", isDirectory: true)
        try fm.createDirectory(at: util, withIntermediateDirectories: true)
        try
            "del .\\emulators\\86Box98\\W98-C.vhd\r\n.\\emulators\\86Box98\\makevhd.exe -f .\\emulators\\86Box98\\W98-C.vhd .\\emulators\\86Box98\\parent\\W98-P.vhd\r\n"
            .write(to: util.appendingPathComponent("9xlaunch86Box.bat"), atomically: true, encoding: .utf8)
        let box = eXo.appendingPathComponent("emulators/86Box98", isDirectory: true)
        for folder in ["parent", "nvr", "roms"] {
            try fm.createDirectory(at: box.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data(count: 256).write(to: box.appendingPathComponent("nvr/686bx.nvr"))
        try VHDFixture.fixedDisk(size: 4 * 1024 * 1024).write(to: box.appendingPathComponent("parent/W98-P.vhd"))

        let parents = eXo.appendingPathComponent("emulators/dosbox/x98/parent", isDirectory: true)
        try fm.createDirectory(at: parents, withIntermediateDirectories: true)
        for name in ["W98-C.vhd", "W98-C-Net.vhd"] {
            try Data("vhd".utf8).write(to: parents.appendingPathComponent(name))
        }
        if unpacked {
            let folder = eXo.appendingPathComponent("eXoWin9x/1996/\(title)", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("disk".utf8).write(to: folder.appendingPathComponent("\(title).vhd"))
            try "FILE".write(to: folder.appendingPathComponent(cdName), atomically: true, encoding: .utf8)
            let boxFolder = eXo.appendingPathComponent("eXoWin9x/1996/\(boxTitle)", isDirectory: true)
            try fm.createDirectory(at: boxFolder, withIntermediateDirectories: true)
            try Data("disk".utf8).write(to: boxFolder.appendingPathComponent("\(boxTitle).vhd"))
            try "FILE".write(to: boxFolder.appendingPathComponent("Box.cue"), atomically: true, encoding: .utf8)
        }
        return root
    }

    static func snapshot(root: LibraryRoot, localStore: LocalStore?) -> LibrarySnapshot {
        LibrarySnapshot(
            root: root, games: [game(), game(boxTitle)], platforms: [], categories: [],
            platformFolders: [], playlists: [], parents: [], alternateNames: [], additionalApplications: [],
            installedGamePaths: LibraryLoader.installedGamePaths(in: root.eXoDirectory), localStore: localStore,
            locallyInstalledGamePaths: localStore.map { LibraryLoader.installedGamePaths(in: $0.gamesRoot) } ?? [])
    }
}

@Suite("eXoWin9x games")
struct Windows9xTests {
    @Test func recognisesWin9xGames() throws {
        let game = Win9xFixture.game()
        #expect(game.eXoPack == .win9x)
        #expect(game.launchKind == .windows9x)
        #expect(game.installPath == "eXoWin9x/1996/Mini Win (1996)")
        #expect(!game.isDOSGame)

        // The pack's own setup entry is a Windows batch file, not a game.
        let setup = Game(
            id: "setup", title: "eXoWin9x", platform: "Windows 9x", applicationPath: "Setup eXoWin9x.bat")
        #expect(setup.eXoPack == nil)
        #expect(setup.launchKind == .windowsProgram)

        let ultima = try #require(try FixtureLibrary.snapshot().game(id: FixtureLibrary.ultimaID))
        #expect(ultima.eXoPack == .dos)
        #expect(ultima.installPath == "eXoDOS/ultima5")
    }

    @Test func findsUnpackedGamesInYearFolders() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = try Win9xFixture.makeLibrary(in: scratch, unpacked: true)
        let paths = LibraryLoader.installedGamePaths(in: root.eXoDirectory)
        #expect(paths == ["eXoWin9x/1996/Mini Win (1996)", "eXoWin9x/1996/Box Game (1996)"])
        let snapshot = Win9xFixture.snapshot(root: root, localStore: nil)
        let game = Win9xFixture.game()
        #expect(snapshot.isInstalled(game))
        #expect(
            snapshot.installedLocation(for: game)
                == .library(root.eXoDirectory.appendingPathComponent("eXoWin9x/1996/Mini Win (1996)")))
    }

    @Test func installsIntoTheYearFolderOfTheLocalStore() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = try Win9xFixture.makeLibrary(in: scratch, unpacked: false)
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let fm = FileManager.default
        let stage = scratch.appendingPathComponent("stage", isDirectory: true)
        let staged = stage.appendingPathComponent(Win9xFixture.title, isDirectory: true)
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("disk".utf8).write(to: staged.appendingPathComponent("\(Win9xFixture.title).vhd"))
        let year = root.eXoDirectory.appendingPathComponent("eXoWin9x/1996", isDirectory: true)
        try fm.createDirectory(at: year, withIntermediateDirectories: true)
        let zipURL = year.appendingPathComponent("\(Win9xFixture.title).zip")
        let zip = try await CommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", zipURL.path, Win9xFixture.title],
            workingDirectory: stage)
        #expect(zip.status == 0, Comment(rawValue: zip.output))

        let game = Win9xFixture.game()
        let installer = GameInstaller(snapshot: Win9xFixture.snapshot(root: root, localStore: localStore))
        let plan = try #require(installer.plan(for: game))
        #expect(plan.archiveURL == zipURL)
        #expect(plan.destinationDirectory.path == localStore.gamesRoot.appendingPathComponent("eXoWin9x/1996").path)
        #expect(plan.saveBackupURL == localStore.savesDirectory.appendingPathComponent("eXoWin9x/Mini Win (1996).zip"))
        try await installer.install(plan)

        let snapshot = Win9xFixture.snapshot(root: root, localStore: localStore)
        let installed = localStore.gamesRoot.appendingPathComponent("eXoWin9x/1996/Mini Win (1996)", isDirectory: true)
        #expect(snapshot.installedLocation(for: game) == .local(installed))
        #expect(fm.fileExists(atPath: installed.appendingPathComponent("Mini Win (1996).vhd").path))
    }

    @Test func plansWindows98BootWithLocalDisks() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = try Win9xFixture.makeLibrary(in: scratch, unpacked: true)
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let gameFolder = root.eXoDirectory.appendingPathComponent("eXoWin9x/1996/Mini Win (1996)", isDirectory: true)
        // The library is read-only, so the game's disk must be copied.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: gameFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gameFolder.path) }

        let emulator = try FixtureLibrary.fakeEmulator(.dosboxX, in: scratch)
        let planner = LaunchPlanner(
            snapshot: Win9xFixture.snapshot(root: root, localStore: localStore),
            scratchDirectory: scratch.appendingPathComponent("launch"))
        let plan = try planner.plan(
            game: Win9xFixture.game(), variant: nil, emulator: emulator, options: LaunchOptions(windowSize: .medium))

        let disks = localStore.overlayRoot.appendingPathComponent("emulators/dosbox/x98")
        let diskCopy = localStore.overlayRoot.appendingPathComponent(
            "eXoWin9x/1996/Mini Win (1996)/Mini Win (1996).vhd")
        let parent = root.eXoDirectory.appendingPathComponent("emulators/dosbox/x98/parent/W98-C.vhd")
        let doc = DOSBoxConfigDocument.parse(plan.configText)
        // Network.ps1 is there, so the Solo disks replace the Host ones.
        #expect(
            doc.autoexecLines == [
                "vhdmake -f -l \"\(parent.path)\" \"\(disks.path)/W98-C.vhd\"",
                "IMGMOUNT c \"\(disks.path)/W98-C.vhd\"",
                "IMGMOUNT d \"\(diskCopy.path)\"",
                "IMGMOUNT e \"\(gameFolder.path)/Mini Win.cue\" -t cdrom -ide 2m",
                "echo off",
                "cls",
                "BOOT -l c",
            ])
        #expect(doc.value("ne2000", "backend") == "slirp")
        #expect(doc.value("ne2000", "macaddr") == "AC:DE:48:88:89:A0")
        #expect(doc.value("sdl", "windowresolution") == "1280x960")
        #expect(doc.value("sdl", "mapperfile") == nil)
        #expect(plan.arguments.contains("-conf"))
        #expect(
            plan.fileCopies == [
                FileCopy(source: gameFolder.appendingPathComponent("Mini Win (1996).vhd"), destination: diskCopy)
            ])

        try plan.writeConfig()
        #expect(FileManager.default.fileExists(atPath: diskCopy.path))
        #expect(FileManager.default.fileExists(atPath: disks.path))
    }

    @Test func plans86BoxWithAFreshDifferencingDisk() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = try Win9xFixture.makeLibrary(in: scratch, unpacked: true)
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let gameFolder = root.eXoDirectory.appendingPathComponent("eXoWin9x/1996/Box Game (1996)", isDirectory: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: gameFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gameFolder.path) }

        let emulator = try FixtureLibrary.fakeEmulator(.box86, in: scratch)
        let planner = LaunchPlanner(
            snapshot: Win9xFixture.snapshot(root: root, localStore: localStore),
            scratchDirectory: scratch.appendingPathComponent("launch"))
        let game = Win9xFixture.game(Win9xFixture.boxTitle)
        #expect(planner.needs86Box(game))
        let plan = try planner.plan(
            game: game, variant: nil, emulator: emulator, options: LaunchOptions(fullscreen: true))

        let vm = localStore.overlayRoot.appendingPathComponent("emulators/86Box98")
        let library86Box = root.eXoDirectory.appendingPathComponent("emulators/86Box98")
        let diskCopy = localStore.overlayRoot.appendingPathComponent(
            "eXoWin9x/1996/Box Game (1996)/Box Game (1996).vhd")
        #expect(plan.configURL == vm.appendingPathComponent("86box.cfg"))
        #expect(
            plan.arguments == [
                "-P", vm.path, "-R", library86Box.appendingPathComponent("roms").path, "-N", "-F", plan.configURL.path,
            ])
        let lines = plan.configText.components(separatedBy: "\n")
        #expect(lines.first == "[General]")
        #expect(lines.contains("hdd_01_fn = \(vm.path)/W98-C.vhd"))
        #expect(lines.contains("hdd_02_fn = \(diskCopy.path)"))
        // The CD keeps the library path. eXo spells it box.cue; a volume that
        // tells case apart needs the file's own spelling, Box.cue.
        #expect(lines.contains { $0.lowercased() == "cdrom_01_image_path = \(gameFolder.path)/box.cue".lowercased() })
        #expect(lines.contains("hdd_01_ide_channel = 0:0"))
        #expect(
            plan.differencingDisks == [
                DifferencingDisk(
                    child: vm.appendingPathComponent("W98-C.vhd"),
                    parent: library86Box.appendingPathComponent("parent/W98-P.vhd"))
            ])

        try plan.writeConfig()
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: vm.appendingPathComponent("nvr/686bx.nvr").path))
        #expect(fm.fileExists(atPath: diskCopy.path))
        #expect(fm.fileExists(atPath: vm.appendingPathComponent("W98-C.vhd").path))
        #expect(try String(contentsOf: plan.configURL, encoding: .utf8) == plan.configText)
    }

    @Test func refusesOtherEmulatorsAnd86BoxGames() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let root = try Win9xFixture.makeLibrary(in: scratch, unpacked: true)
        let planner = LaunchPlanner(
            snapshot: Win9xFixture.snapshot(root: root, localStore: nil), scratchDirectory: scratch)
        let staging = try FixtureLibrary.fakeEmulator(.dosboxStaging, in: scratch)
        let dosboxX = try FixtureLibrary.fakeEmulator(.dosboxX, in: scratch)
        #expect(throws: LaunchPlanError.needsDOSBoxX) {
            try planner.plan(game: Win9xFixture.game(), variant: nil, emulator: staging, options: LaunchOptions())
        }
        #expect(throws: LaunchPlanError.needs86Box) {
            try planner.plan(
                game: Win9xFixture.game(Win9xFixture.boxTitle), variant: nil, emulator: dosboxX,
                options: LaunchOptions())
        }
        #expect(planner.recommendedEmulator(for: Win9xFixture.game()) == .dosboxX)
        #expect(planner.variants(for: Win9xFixture.game()).isEmpty)
    }
}

/// Minimal VHD images for tests.
nonisolated enum VHDFixture {
    static let uuid = Data((1...16).map { UInt8($0) })

    /// A fixed disk: `size` bytes of data and the footer.
    static func fixedDisk(size: Int) -> Data {
        var footer = Data(count: 512)
        footer.replaceSubrange(0..<8, with: Data("conectix".utf8))
        footer.replaceSubrange(48..<56, with: Swift.withUnsafeBytes(of: UInt64(size).bigEndian) { Data($0) })
        footer.replaceSubrange(56..<60, with: Data([0x02, 0x00, 0x10, 0x3F]))
        footer.replaceSubrange(60..<64, with: Data([0, 0, 0, 2]))
        footer.replaceSubrange(68..<84, with: uuid)
        return Data(count: size) + footer
    }
}

@Suite("Differencing VHDs")
struct VHDDifferencingDiskTests {
    @Test func writesAChildThatPointsAtItsParent() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let parent = scratch.appendingPathComponent("parent/W98-P.vhd")
        try FileManager.default.createDirectory(
            at: parent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try VHDFixture.fixedDisk(size: 5 * 1024 * 1024).write(to: parent)
        let child = scratch.appendingPathComponent("vm/W98-C.vhd")
        try VHDDifferencingDisk.create(at: child, parent: parent)

        let data = try Data(contentsOf: child)
        let footer = data.suffix(512)
        #expect(data.prefix(512) == footer)
        #expect(footer.prefix(8) == Data("conectix".utf8))
        #expect(Data(footer)[60..<64] == Data([0, 0, 0, 4]))
        #expect(Data(footer).uint64(at: 48) == 5 * 1024 * 1024)
        var zeroed = Data(footer)
        let stored = zeroed.uint32(at: 64)
        zeroed.replaceSubrange(64..<68, with: Data(count: 4))
        #expect(stored == VHDDifferencingDisk.checksum(zeroed))

        let header = data.subdata(in: 512..<1536)
        #expect(header.prefix(8) == Data("cxsparse".utf8))
        #expect(header.subdata(in: 40..<56) == VHDFixture.uuid)
        #expect(header.uint32(at: 28) == 3)  // three 2 MB blocks
        let modified = try #require(
            try FileManager.default.attributesOfItem(atPath: parent.path)[.modificationDate] as? Date)
        #expect(header.uint32(at: 56) == VHDDifferencingDisk.timestamp(modified))

        // Locator 0: the parent's absolute path in UTF-16LE.
        #expect(header.subdata(in: 576..<580) == Data("W2ku".utf8))
        let length = Int(header.uint32(at: 584))
        let offset = Int(header.uint64(at: 592))
        let path = String(data: data.subdata(in: offset..<(offset + length)), encoding: .utf16LittleEndian)
        #expect(path == parent.standardizedFileURL.path)
        #expect(header.subdata(in: 600..<604) == Data("W2ru".utf8))
        let relativeLength = Int(header.uint32(at: 608))
        let relativeOffset = Int(header.uint64(at: 616))
        let relative = String(
            data: data.subdata(in: relativeOffset..<(relativeOffset + relativeLength)), encoding: .utf16LittleEndian)
        #expect(relative == "../parent/W98-P.vhd")
    }
}
