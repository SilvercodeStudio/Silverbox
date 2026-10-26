import Foundation
import Testing

@testable import SilverboxCore

/// A small eXoAppleIIGS library: eXo's emulator index, GSplus's ROM, and
/// three unpacked games: one with a menu of configs, one for GSport and
/// one for MAME.
nonisolated enum AppleIIGSFixture {
    static let index = """
        Designasaurus (1988):GSPlus\\gsplus.exe\r
        Sensei (1991):GSPort\\gsport.exe\r
        Arkanoid (1987):MAME\r
        Arkanoid II - Revenge of Doh (1989):GSPlus\\gsplus.exe\r
        """

    static let exception = """
        @echo off\r
        cd %VAR%\r
        ..\\..\\..\\util\\setconsole.exe /reset\r
        cls\r
        echo.\r
        echo Press 1 to play Designasaurus: Walk a Dinosaur\r
        echo Press 2 to play Designasaurus: Build a Dinosaur\r
        echo.\r
        ..\\..\\..\\util\\choice /C:12 /N Please Choose:\r
        \r
        if errorlevel = 2 goto build\r
        if errorlevel = 1 goto walk\r
        \r
        :walk\r
        cls\r
        echo.\r
        echo Double click "Dino.Walk" to start\r
        echo the program.\r
        echo.\r
        pause\r
        SET CONFIGTXT=config1.txt\r
        goto end\r
        \r
        :build\r
        echo.\r
        echo Double click "Dino.sys16" to start the program\r
        echo.\r
        SET CONFIGTXT=config2.txt\r
        goto end\r
        \r
        :end\r
        """

    static func config(disk: String, joystick: Bool = false) -> String {
        """
        # GSplus configuration file version 0.14\r
        \r
        s5d1 = \(disk)\r
        s5d2 = \r
        \r
        s7d1 = \r
        \r
        \(joystick ? "g_joystick_type = 0\r\n" : "")g_cfg_rom_path = ..\\..\\..\\GSPlus\\ROM1\r
        g_limit_speed = 2\r
        g_win_status_debug_request = 0\r
        \r
        bram1[00] = 00 00 00 01 00 00 0d 06 02 01 01 00 01 00 00 00\r
        """
    }

    static func game(_ folder: String) -> Game {
        Game(
            id: "iigs-\(folder)", title: folder, platform: "Apple IIGS",
            applicationPath: "eXo\\eXoAppleIIGS\\!appleiigs\\\(folder)\\\(folder).bat",
            rootFolder: "eXo\\eXoAppleIIGS\\!appleiigs\\\(folder)")
    }

    static let designasaurus = game("Designasaurus (1988)")
    static let sensei = game("Sensei (1991)")
    static let arkanoid = game("Arkanoid (1987)")

    static func make(in scratch: URL) throws -> LibrarySnapshot {
        let fm = FileManager.default
        let root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
        func write(_ text: String, _ path: String) throws {
            let url = root.eXoDirectory.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(index, "util/appleIIGS.txt")
        try write("rom", "emulators/GSPlus/ROM1")
        let configs = "eXoAppleIIGS/!appleiigs/"
        try write(exception, configs + "Designasaurus (1988)/exception.bat")
        try write(config(disk: "disk1.2mg"), configs + "Designasaurus (1988)/config1.txt")
        try write(config(disk: "Disk2.2mg"), configs + "Designasaurus (1988)/config2.txt")
        try write("2mg", "eXoAppleIIGS/Designasaurus (1988)/Disk1.2mg")
        try write("2mg", "eXoAppleIIGS/Designasaurus (1988)/Disk2.2mg")
        try write(
            "echo off\r\ncd %VAR%\r\necho.\r\necho Keys:\r\necho d = Delete\r\necho.\r\npause\r\n",
            configs + "Sensei (1991)/exception.bat")
        try write(config(disk: "Sensei.2mg", joystick: true), "eXoAppleIIGS/Sensei (1991)/config.txt")
        try write("2mg", "eXoAppleIIGS/Sensei (1991)/Sensei.2mg")
        try write("hdv", "eXoAppleIIGS/Arkanoid (1987)/Game.hdv")
        try write(
            "echo off\r\nSET DISK1=game.hdv\r\nSET DISK2=\r\nSET SPEED=TRUE\r\nSET DISKS=1\r\ncd %VAR%\r\n",
            configs + "Arkanoid (1987)/exception.bat")
        try write("<mameconfig/>", "emulators/MAME/apple2gs.cfg")
        try write("<mameconfig fast/>", "emulators/MAME/fast/apple2gs.cfg")
        try write("nvram", "emulators/MAME/apple2gs/nvram")
        try write("zip", "emulators/MAME/roms/apple2gs.zip")
        return LibrarySnapshot(
            root: root, games: [designasaurus, sensei, arkanoid], platforms: [], categories: [],
            platformFolders: [], playlists: [], parents: [], alternateNames: [], additionalApplications: [],
            installedGamePaths: LibraryLoader.installedGamePaths(in: root.eXoDirectory),
            localStore: LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true)))
    }

    /// A stand-in GSplus.app with an executable inside.
    static func gsplus(in scratch: URL) throws -> EmulatorInstallation {
        let macOS = scratch.appendingPathComponent("GSplus.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        return try FixtureLibrary.fakeEmulator(.gsplus, in: macOS)
    }
}

@Suite("eXoAppleIIGS launching")
struct AppleIIGSTests {
    @Test func readsEXosEmulatorIndex() {
        let index = AppleIIGSIndex.parse(AppleIIGSFixture.index)
        #expect(index.route(for: "Sensei (1991)") == .gsport)
        #expect(index.route(for: "Designasaurus (1988)") == .gsplus)
        // findstr finds any line that contains the name; the last one wins.
        #expect(index.route(for: "Arkanoid") == .gsplus)
        #expect(index.route(for: "Arkanoid (1987)") == .mame)
        #expect(index.route(for: "Nothing (1990)") == nil)
    }

    @Test func readsTheMenuAndInstructions() {
        let parsed = AppleIIGSException.parse(AppleIIGSFixture.exception)
        #expect(parsed.note == nil)
        #expect(parsed.choices.map(\.title) == ["Designasaurus: Walk a Dinosaur", "Designasaurus: Build a Dinosaur"])
        #expect(parsed.choices.map(\.configName) == ["config1.txt", "config2.txt"])
        #expect(parsed.choices.first?.note == "Double click \"Dino.Walk\" to start the program.")

        let list = AppleIIGSException.parse(
            "echo off\r\necho.\r\necho The game starts with a party.\r\necho Some commands are:\r\necho.\r\necho d = Delete\r\necho z = Create\r\necho.\r\n"
        )
        #expect(list.note == "The game starts with a party. Some commands are:\n\nd = Delete\nz = Create")
        #expect(list.choices.isEmpty)
    }

    @Test func listsVersionsBeforeInstalling() throws {
        let snapshot = try AppleIIGSFixture.make(in: try FixtureLibrary.scratchDirectory())
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: snapshot.root.url)
        #expect(AppleIIGSFixture.designasaurus.launchKind == .appleIIGS)
        #expect(planner.recommendedEmulator(for: AppleIIGSFixture.designasaurus) == .gsplus)
        let versions = planner.variants(for: AppleIIGSFixture.designasaurus)
        #expect(versions.map(\.id) == ["config1.txt", "config2.txt"])
        #expect(versions.allSatisfy { $0.isPlayable })
        let sensei = planner.variants(for: AppleIIGSFixture.sensei)
        #expect(sensei.map(\.title) == ["Default"])
        #expect(sensei.first?.note == "Keys:\nd = Delete")
        let arkanoid = planner.variants(for: AppleIIGSFixture.arkanoid)
        #expect(arkanoid.first?.isPlayable == false)
    }

    @Test func writesAGSplusConfigWithMacPaths() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try AppleIIGSFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch.appendingPathComponent("launch"))
        let gsplus = try AppleIIGSFixture.gsplus(in: scratch)
        let versions = planner.variants(for: AppleIIGSFixture.designasaurus)
        let plan = try planner.plan(
            game: AppleIIGSFixture.designasaurus, variant: versions.first, emulator: gsplus,
            options: LaunchOptions(fullscreen: true))
        let games = snapshot.root.eXoDirectory.appendingPathComponent("eXoAppleIIGS", isDirectory: true)
        let rom = snapshot.root.eXoDirectory.appendingPathComponent("emulators/GSPlus/ROM1")
        #expect(plan.arguments == ["-cfg", plan.configURL.path])
        #expect(plan.configURL.lastPathComponent == "config.kegs")
        #expect(plan.configURL.deletingLastPathComponent().lastPathComponent.hasSuffix("-config1-gsplus"))
        let lines = plan.configText.components(separatedBy: "\n")
        // The config names `disk1.2mg`; the file is `Disk1.2mg`.
        let disk = "s5d1 = \(games.path)/Designasaurus (1988)/Disk1.2mg"
        #expect(lines.contains { $0.caseInsensitiveCompare(disk) == .orderedSame })
        #expect(lines.contains("s5d2 = "))
        #expect(lines.contains("g_cfg_rom_path = \(rom.path)"))
        #expect(lines.contains("g_limit_speed = 2"))
        #expect(lines.contains("bram1[00] = 00 00 00 01 00 00 0d 06 02 01 01 00 01 00 00 00"))
        #expect(lines.contains("g_status_enable = 0"))
        #expect(lines.contains("fullscreen = 1"))
        #expect(!plan.configText.contains("g_win_status_debug_request"))
        #expect(!plan.configText.contains("\r"))
        #expect(plan.notes.contains("Double click \"Dino.Walk\" to start the program."))
        #expect(plan.fileCopies.isEmpty)
    }

    @Test func runsGSportGamesFromTheirOwnConfig() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try AppleIIGSFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch.appendingPathComponent("launch"))
        let plan = try planner.plan(
            game: AppleIIGSFixture.sensei, variant: nil, emulator: try AppleIIGSFixture.gsplus(in: scratch),
            options: LaunchOptions())
        #expect(plan.sourceConfigURL.path.hasSuffix("eXoAppleIIGS/Sensei (1991)/config.txt"))
        #expect(plan.configText.contains("g_joystick_type = 4"))
        #expect(plan.configText.contains("fullscreen = 0"))
        #expect(plan.notes.first?.contains("GSport") == true)
    }

    @Test func copiesDisksFromAReadOnlyLibrary() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let games = scratch.appendingPathComponent("eXo/eXoAppleIIGS", isDirectory: true)
        let game = games.appendingPathComponent("Sensei (1991)", isDirectory: true)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data().write(to: game.appendingPathComponent("Sensei.2mg"))
        let overlay = scratch.appendingPathComponent("local/Overlay/eXoAppleIIGS", isDirectory: true)
        let result = GSplusConfigTranslator(
            gameFolder: game,
            romFolder: scratch.appendingPathComponent("eXo/emulators/GSPlus", isDirectory: true),
            diskCopies: OverlayMount(base: games, directory: overlay)
        ).translate(AppleIIGSFixture.config(disk: "Sensei.2mg"))
        let copy = overlay.appendingPathComponent("Sensei (1991)/Sensei.2mg")
        #expect(result.copies.map(\.destination) == [copy])
        #expect(result.text.contains("s5d1 = \(copy.path)\n"))
        #expect(result.missingDisks.isEmpty)
    }

    @Test func leavesEjectedAndMissingDisksOut() {
        let result = GSplusConfigTranslator(
            gameFolder: URL(fileURLWithPath: "/nonexistent/Yahtzee (1988)", isDirectory: true),
            romFolder: URL(fileURLWithPath: "/nonexistent/GSPlus", isDirectory: true)
        ).translate("s7d1 = 1.hdv\r\ns7d2 = #Shareware.hdv\r\n")
        #expect(result.text.hasPrefix("s7d1 = \ns7d2 = \n"))
        #expect(result.missingDisks.map(\.lastPathComponent) == ["1.hdv"])
        #expect(GSplusConfigTranslator.diskNames(in: "s7d1 = 1.hdv\r\ns7d2 = #Shareware.hdv\r\n") == ["1.hdv"])
    }

    @Test func startsMAMEGamesOnceTheROMIsAdded() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try AppleIIGSFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch.appendingPathComponent("launch"))
        let mame = try FixtureLibrary.fakeEmulator(.mame, in: scratch)
        let game = AppleIIGSFixture.arkanoid
        #expect(planner.recommendedEmulator(for: game) == .mame)
        #expect(planner.appleIIGSProblem(for: game)?.contains(AppleIIGSCharacterROM.fileName) == true)
        #expect(throws: LaunchPlanError.self) {
            try planner.plan(game: game, variant: nil, emulator: mame, options: LaunchOptions())
        }

        let rom = planner.appleIIGSCharacterROMURL
        #expect(rom.path.hasSuffix("local/MAME/roms/apple2gs/344s0047.bin"))
        try FileManager.default.createDirectory(at: rom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: AppleIIGSCharacterROM.size).write(to: rom)
        #expect(planner.appleIIGSProblem(for: game) == nil)
        #expect(planner.variants(for: game).first?.isPlayable == true)
        let plan = try planner.plan(game: game, variant: nil, emulator: mame, options: LaunchOptions())
        let eXoMAME = snapshot.root.eXoDirectory.appendingPathComponent("emulators/MAME")
        let local = scratch.appendingPathComponent("local/MAME")
        let disk = snapshot.root.eXoDirectory.appendingPathComponent("eXoAppleIIGS/Arkanoid (1987)/Game.hdv")
        #expect(plan.arguments.first == "apple2gs")
        #expect(plan.arguments.contains("\(local.path)/roms;\(eXoMAME.path)/roms"))
        // SPEED=TRUE: eXo's settings for full speed.
        #expect(plan.arguments.contains("\(local.path)/cfg-fast"))
        #expect(plan.arguments.suffix(2).first == "-hard1")
        #expect(plan.arguments.last?.caseInsensitiveCompare(disk.path) == .orderedSame)
        #expect(plan.arguments.contains("-window"))
        #expect(plan.fileCopies.map(\.destination.lastPathComponent).sorted() == ["apple2gs", "apple2gs.cfg"])

        try plan.writeConfig()
        let cfg = local.appendingPathComponent("cfg-fast/apple2gs.cfg")
        #expect(try String(contentsOf: cfg, encoding: .utf8) == "<mameconfig fast/>")
        #expect(FileManager.default.fileExists(atPath: local.appendingPathComponent("nvram/apple2gs/nvram").path))
    }

    @Test func readsMAMEMenus() {
        let parsed = AppleIIGSException.parse(
            "echo off\r\necho Press 1 to play Part One\r\necho Press 2 to play Part Two\r\nchoice /C:12 /N\r\nif errorlevel = 2 goto part2\r\nif errorlevel = 1 goto part1\r\n:part1\r\nSET DISK1=Game.po\r\nSET DISKS=1\r\nSET SPEED=TRUE\r\ngoto end\r\n:part2\r\nSET DISK1=Katie's Farm Dk2.2mg\r\nSET DISKS=1\r\ngoto end\r\n:end\r\n"
        )
        #expect(parsed.choices.map(\.label) == ["part1", "part2"])
        #expect(parsed.choices.map(\.title) == ["Part One", "Part Two"])
        #expect(parsed.choices[1].settings["DISK1"] == "Katie's Farm Dk2.2mg")
        #expect(parsed.choices[0].settings["SPEED"] == "TRUE")
        #expect(parsed.choices[1].configName == nil)
    }

    @Test func computesSHA1() {
        #expect(SHA1.hex(of: Data()) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(SHA1.hex(of: Data("abc".utf8)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        #expect(SHA1.hex(of: long) == "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    }

    @Test func importsTheROMFromAFileOrAZip() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let rom = Data((0..<AppleIIGSCharacterROM.size).map { UInt8(truncatingIfNeeded: $0 * 7) })
        let expected = SHA1.hex(of: rom)
        let folder = scratch.appendingPathComponent("apple2gs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try rom.write(to: folder.appendingPathComponent("344s0047.bin"))
        try Data(count: 4096).write(to: folder.appendingPathComponent("341s0632-2.bin"))
        let zip = scratch.appendingPathComponent("apple2gs.zip")
        let zipped = try await CommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-qr", zip.path, "apple2gs"],
            workingDirectory: scratch)
        #expect(zipped.status == 0)

        let destination = scratch.appendingPathComponent("MAME/roms/apple2gs/344s0047.bin")
        try await AppleIIGSCharacterROM.importFile(from: zip, to: destination, expectedSHA1: expected)
        #expect(FileManager.default.contents(atPath: destination.path) == rom)
        try FileManager.default.removeItem(at: destination)
        try await AppleIIGSCharacterROM.importFile(
            from: folder.appendingPathComponent("344s0047.bin"), to: destination, expectedSHA1: expected)
        #expect(FileManager.default.contents(atPath: destination.path) == rom)
        await #expect(throws: AppleIIGSCharacterROM.ImportError.self) {
            try await AppleIIGSCharacterROM.importFile(
                from: folder.appendingPathComponent("341s0632-2.bin"), to: destination, expectedSHA1: expected)
        }
    }
}
