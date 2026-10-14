import Foundation
import Testing

@testable import eXoCore

/// A small eXoIF library: eXo's system table and one game unpacked with
/// versions for Spatterlight, DOSBox, a system the Mac does not run, and a
/// language menu.
nonisolated enum IFFixture {
    static let folder = "Zork I (1980)"

    static let launcher = """
        @echo off\r
        for %%S in ("!selection1!" "!selection2!") do (\r
            for %%A in (\r
        	    "C64=C64"\r
        	    "MS-DOS=MSDOS"\r
        	    "PC Booter=MSDOS"\r
        	    "WinFrotz=WinFrotz"\r
        	    "Lectrote=Lectrote"\r
        	    "ZX Spectrum=ZXSpectrum"\r
        	    "Proteus__Poly=Windows"\r
        	    "Atari 8bit=Atari8"\r
        	    "Amiga=AMIGA"\r
        	) do (\r
        """

    static let game = Game(
        id: "if-zork", title: "Zork I", platform: "Interactive Fiction",
        applicationPath: "eXo\\eXoIF\\!IF\\\(folder)\\\(folder).bat", rootFolder: "eXo\\eXoIF\\!IF\\\(folder)\\")

    static let mission = "Secret Mission (1984)"
    static let missionGame = Game(
        id: "if-mission", title: "Secret Mission", platform: "Interactive Fiction",
        applicationPath: "eXo\\eXoIF\\!IF\\\(mission)\\\(mission).bat", rootFolder: "eXo\\eXoIF\\!IF\\\(mission)")

    static func make(in scratch: URL) throws -> LibrarySnapshot {
        let fm = FileManager.default
        let root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
        func write(_ text: String, _ path: String) throws {
            let url = root.eXoDirectory.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(launcher, "util/launch_if.bat")
        let game = "eXoIF/\(folder)/"
        try write("zcode", game + "WinFrotz/zork1.z3")
        try write("zork1.z3", game + "WinFrotz/launch.file")
        // The same story under a second interpreter, as eXo often has it.
        try write("zcode", game + "Lectrote/zork1.z3")
        try write("zork1.z3", game + "Lectrote/launch.file")
        try write(
            "[cpu]\ncycles=fixed 3000\n[autoexec]\nmount c \".\\eXoIF\\\(folder)\\MS-DOS\"\nc:\nZORK1.COM\n",
            game + "MS-DOS/dosbox.conf")
        try write("com", game + "MS-DOS/ZORK1.COM")
        try write("d64", game + "C64/zork.d64")
        try write("d64", game + "C64/zork2.d64")
        try write("zork.d64", game + "C64/launch.file")
        try write("# Vice fliplist file\r\nUNIT 8\r\nzork.d64\r\nzork2.d64\r\n", game + "C64/fliplist.vfl")
        try write("menu", game + "English/menu.txt")
        try write("tzx", game + "English/ZX Spectrum/zork.tzx")
        try write("exe", game + "Proteus__Poly/zork.exe")
        try write("xex", "eXoIF/\(mission)/Atari 8bit/mission.xex")
        try write("adf", "eXoIF/\(mission)/Amiga/mission.adf")
        for rom in ["REV02.ROM", "REVBNTSC.ROM", "REVC.ROM"] { try write("rom", "emulators/Altirra-4.31/\(rom)") }
        return LibrarySnapshot(
            root: root, games: [Self.game, Self.missionGame], platforms: [], categories: [], platformFolders: [],
            playlists: [],
            parents: [], alternateNames: [], additionalApplications: [],
            installedGamePaths: LibraryLoader.installedGamePaths(in: root.eXoDirectory),
            localStore: LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true)))
    }

    /// A stand-in RetroArch with the VICE C64, atari800 and PUAE cores, and
    /// an empty system folder.
    static func retroArch(in scratch: URL) throws -> RetroArchSetup {
        let cores = scratch.appendingPathComponent("cores", isDirectory: true)
        let system = scratch.appendingPathComponent("system", isDirectory: true)
        try FileManager.default.createDirectory(at: cores, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        for core in ["vice_x64sc", "atari800", "puae"] {
            try Data().write(to: cores.appendingPathComponent("\(core)_libretro.dylib"))
        }
        let app = try FixtureLibrary.fakeEmulator(.retroArch, in: scratch)
        return RetroArchSetup(installation: app, coresDirectory: cores, infoDirectory: nil, systemDirectory: system)
    }

    /// A stand-in Spatterlight.app with an executable inside.
    static func spatterlight(in scratch: URL) throws -> EmulatorInstallation {
        let macOS = scratch.appendingPathComponent("Spatterlight.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let installation = try FixtureLibrary.fakeEmulator(.spatterlight, in: macOS)
        return installation
    }
}

@Suite("eXoIF launching")
struct IFTests {
    @Test func readsEXosSystemTable() {
        let table = IFSystemTable.parse(IFFixture.launcher)
        #expect(table.labels["PC Booter"] == "MSDOS")
        #expect(table.labels.count == 9)
        // A language folder is not a system; the folder inside it is.
        #expect(table.label(forFolders: ["English", "ZX Spectrum"]) == "ZXSpectrum")
    }

    @Test func listsVersionsAndPrefersAnInterpreter() throws {
        let snapshot = try IFFixture.make(in: try FixtureLibrary.scratchDirectory())
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: snapshot.root.url)
        #expect(IFFixture.game.launchKind == .interactiveFiction)
        let versions = planner.variants(for: IFFixture.game)
        // WinFrotz holds the same file as Lectrote, so it is left out.
        #expect(versions.map(\.id) == ["C64", "English/ZX Spectrum", "Lectrote", "MS-DOS", "Proteus__Poly"])
        #expect(versions.map(\.title)[1] == "English › ZX Spectrum")
        #expect(versions.map(\.title)[2] == "Z-code story file")
        #expect(versions.map(\.title)[4] == "Proteus/Poly")
        #expect(versions.map(\.isPlayable) == [false, false, true, true, false])
        #expect(LaunchPlanner.defaultIFVersion(versions)?.id == "Lectrote")
        #expect(planner.recommendedEmulator(for: IFFixture.game) == .spatterlight)
    }

    @Test func opensStoryFilesInSpatterlight() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try IFFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let spatterlight = try IFFixture.spatterlight(in: scratch)
        let plan = try planner.plan(
            game: IFFixture.game, variant: nil, emulator: spatterlight, options: LaunchOptions())
        let story = snapshot.root.eXoDirectory.appendingPathComponent("eXoIF/\(IFFixture.folder)/Lectrote/zork1.z3")
        #expect(plan.emulator.executableURL.path == "/usr/bin/open")
        #expect(plan.arguments == ["-W", "-a", try #require(spatterlight.appBundleURL).path, story.path])
        // Writing the plan leaves the story file alone.
        try plan.writeConfig()
        #expect(try String(contentsOf: story, encoding: .utf8) == "zcode")
    }

    @Test func runsDOSVersionsInDOSBox() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try IFFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let dos = try #require(planner.variants(for: IFFixture.game).first { $0.id == "MS-DOS" })
        #expect(planner.ifRoute(for: IFFixture.game, variant: dos)?.emulator == .dosboxStaging)
        let emulator = try FixtureLibrary.fakeEmulator(.dosboxStaging, in: scratch)
        let plan = try planner.plan(game: IFFixture.game, variant: dos, emulator: emulator, options: LaunchOptions())
        let doc = DOSBoxConfigDocument.parse(plan.configText)
        let folder = snapshot.root.eXoDirectory.appendingPathComponent("eXoIF/\(IFFixture.folder)/MS-DOS")
        #expect(doc.autoexecLines.first == "mount c \"\(folder.path)\"")
    }

    @Test func refusesVersionsWithoutAMacRoute() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try IFFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let versions = planner.variants(for: IFFixture.game)
        let proteus = try #require(versions.first { $0.id == "Proteus__Poly" })
        #expect(proteus.unsupportedReason == "Proteus/Poly is not supported on the Mac yet")
        #expect(versions.first?.unsupportedReason == "needs RetroArch")
        let spatterlight = try IFFixture.spatterlight(in: scratch)
        #expect(throws: LaunchPlanError.ifVersionUnsupported("Proteus__Poly")) {
            try planner.plan(game: IFFixture.game, variant: proteus, emulator: spatterlight, options: LaunchOptions())
        }
    }

    @Test func runsEightBitVersionsInRetroArch() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try IFFixture.make(in: scratch)
        let retroArch = try IFFixture.retroArch(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch, retroArch: retroArch)
        let versions = planner.variants(for: IFFixture.game)
        // The C64 core is installed; the Spectrum one is not.
        #expect(versions.first { $0.id == "C64" }?.isPlayable == true)
        #expect(versions.first { $0.id == "English/ZX Spectrum" }?.unsupportedReason == "needs RetroArch's fuse core")

        let c64 = try #require(versions.first { $0.id == "C64" })
        let plan = try planner.plan(
            game: IFFixture.game, variant: c64, emulator: retroArch.installation,
            options: LaunchOptions(fullscreen: true))
        let folder = snapshot.root.eXoDirectory.appendingPathComponent("eXoIF/\(IFFixture.folder)/C64")
        #expect(
            plan.arguments == [
                "-L", retroArch.coresDirectory!.appendingPathComponent("vice_x64sc_libretro.dylib").path, "-f",
                plan.configURL.path,
            ])
        // The fliplist becomes a playlist, with eXo's start disk first.
        #expect(plan.configURL.pathExtension == "m3u")
        #expect(
            plan.configText
                == "\(folder.appendingPathComponent("zork.d64").path)\n\(folder.appendingPathComponent("zork2.d64").path)\n"
        )
    }

    @Test func givesCoresTheROMsTheyNeed() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try IFFixture.make(in: scratch)
        let retroArch = try IFFixture.retroArch(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch, retroArch: retroArch)
        let versions = planner.variants(for: IFFixture.missionGame)
        let amiga = try #require(versions.first { $0.id == "Amiga" })
        #expect(
            amiga.unsupportedReason
                == "needs the Amiga Kickstart 1.3 ROM (kick34005.A500) in RetroArch's system folder")

        // atari800 gets eXo's Altirra ROMs in a system folder of its own.
        let atari = try #require(versions.first { $0.id == "Atari 8bit" })
        #expect(atari.isPlayable)
        let plan = try planner.plan(
            game: IFFixture.missionGame, variant: atari, emulator: retroArch.installation, options: LaunchOptions())
        #expect(plan.arguments.prefix(2) == ["--appendconfig", plan.configURL.path])
        #expect(plan.configText == "system_directory = \"\(planner.ifRetroArchSystemDirectory.path)\"\n")
        #expect(
            plan.fileCopies.map(\.destination.lastPathComponent) == ["ATARIXL.ROM", "ATARIOSB.ROM", "ATARIBAS.ROM"])
        try plan.writeConfig()
        #expect(
            FileManager.default.fileExists(
                atPath: planner.ifRetroArchSystemDirectory.appendingPathComponent("ATARIXL.ROM").path))

        // With a Kickstart in RetroArch's system folder, Amiga versions play.
        try Data("rom".utf8).write(to: retroArch.systemDirectory!.appendingPathComponent("kick34005.A500"))
        #expect(planner.variants(for: IFFixture.missionGame).first { $0.id == "Amiga" }?.isPlayable == true)
    }
}
