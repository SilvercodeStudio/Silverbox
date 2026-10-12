import Foundation
import Testing

@testable import eXoCore

/// The console-style LaunchBox library under `Fixtures/ConsoleLibrary`, plus
/// a fake RetroArch with two cores.
nonisolated enum ConsoleFixture {
    static var rootURL: URL { FixtureLibrary.rootURL.appendingPathComponent("ConsoleLibrary", isDirectory: true) }

    static func snapshot() throws -> LibrarySnapshot {
        try LibraryLoader(root: LibraryRoot(url: rootURL)).load()
    }

    /// A RetroArch "install" in `directory`: an executable, a cores folder
    /// with fceumm and fbneo, and an info file for fceumm.
    static func fakeRetroArch(in directory: URL, cores: [String] = ["fceumm_libretro", "fbneo_libretro"]) throws
        -> RetroArchSetup
    {
        let installation = try FixtureLibrary.fakeEmulator(.retroArch, in: directory)
        let coresDirectory = directory.appendingPathComponent("cores", isDirectory: true)
        let infoDirectory = directory.appendingPathComponent("info", isDirectory: true)
        try FileManager.default.createDirectory(at: coresDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: infoDirectory, withIntermediateDirectories: true)
        for core in cores {
            try Data().write(to: coresDirectory.appendingPathComponent("\(core).dylib"))
        }
        try """
        display_name = "Nintendo - NES / Famicom (FCEUmm)"
        systemname = "Nintendo - NES / Famicom"
        supported_extensions = "fds|nes|unif|unf"
        """.write(to: infoDirectory.appendingPathComponent("fceumm_libretro.info"), atomically: true, encoding: .utf8)
        return RetroArchSetup(installation: installation, coresDirectory: coresDirectory, infoDirectory: infoDirectory)
    }

    static let blasterID = "cccccccc-0000-0000-0000-000000000001"
    static let cubeID = "cccccccc-0000-0000-0000-000000000002"
    static let pacmanID = "cccccccc-0000-0000-0000-000000000003"
    static let conanID = "cccccccc-0000-0000-0000-000000000004"
    static let otherCoreID = "cccccccc-0000-0000-0000-000000000005"
    static let packedID = "cccccccc-0000-0000-0000-000000000006"
}

@Suite("Launch kinds")
struct LaunchKindTests {
    @Test func classifiesItems() throws {
        let snapshot = try ConsoleFixture.snapshot()
        #expect(snapshot.game(id: ConsoleFixture.blasterID)?.launchKind == .emulator)
        #expect(snapshot.game(id: ConsoleFixture.cubeID)?.launchKind == .emulator)
        let dos = try FixtureLibrary.snapshot()
        #expect(dos.game(id: FixtureLibrary.ultimaID)?.launchKind == .dosBox)
        #expect(dos.game(id: "bbbbbbbb-0000-0000-0000-000000000001")?.launchKind == .document)
        #expect(
            Game(id: "x", title: "Steam", platform: "Windows", applicationPath: "steam://rungameid/1").launchKind
                == .link)
        #expect(
            Game(
                id: "x", title: "Player", platform: "Soundtracks",
                applicationPath: "eXo\\emulators\\audio\\foobar2000\\foobar2000.exe"
            ).launchKind == .windowsProgram)
        #expect(
            Game(id: "x", title: "Folder", platform: "Arcade", applicationPath: "Games\\Arcade\\pacman").launchKind
                == .emulator)
    }
}

@Suite("RetroArch setup")
struct RetroArchSetupTests {
    @Test func listsCoresWithInfo() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let cores = retroArch.installedCores()
        #expect(cores.map(\.name) == ["fbneo_libretro", "fceumm_libretro"])
        let fceumm = try #require(cores.last)
        #expect(fceumm.title == "Nintendo - NES / Famicom (FCEUmm)")
        #expect(fceumm.systemName == "Nintendo - NES / Famicom")
        #expect(fceumm.supportedExtensions == ["fds", "nes", "unif", "unf"])
        #expect(retroArch.coreURL(named: "fceumm")?.lastPathComponent == "fceumm_libretro.dylib")
        #expect(retroArch.coreURL(named: "cores\\fceumm_libretro.dll")?.lastPathComponent == "fceumm_libretro.dylib")
        #expect(retroArch.coreURL(named: "nestopia") == nil)
        // fbalpha was renamed fbneo; the replacement is found.
        #expect(retroArch.resolveCore(named: "fbalpha_libretro")?.name == "fbneo_libretro")
    }

    @Test func readsConfigPaths() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let config = scratch.appendingPathComponent("retroarch.cfg")
        let cores = scratch.appendingPathComponent("my-cores", isDirectory: true)
        try FileManager.default.createDirectory(at: cores, withIntermediateDirectories: true)
        try """
        # comment
        libretro_directory = "\(cores.path)"
        libretro_info_path = ":/info"
        video_fullscreen = "false"
        """.write(to: config, atomically: true, encoding: .utf8)
        let values = RetroArchSetup.parseConfig(at: config)
        #expect(values["libretro_directory"] == cores.path)
        #expect(values["video_fullscreen"] == "false")
        let installation = try FixtureLibrary.fakeEmulator(.retroArch, in: scratch)
        let setup = RetroArchSetup.discover(installation: installation, configFile: config)
        #expect(setup.coresDirectory == cores)
        #expect(RetroArchSetup.directory(fromConfigValue: "~/x", bundleResources: nil)?.path.hasSuffix("/x") == true)
        let resources = URL(fileURLWithPath: "/Applications/RetroArch.app/Contents/Resources", isDirectory: true)
        #expect(
            RetroArchSetup.directory(fromConfigValue: ":/cores", bundleResources: resources)?.path
                == resources.appendingPathComponent("cores").path)
        #expect(RetroArchSetup.directory(fromConfigValue: "default", bundleResources: resources) == nil)
    }
}

@Suite("Emulator assignments")
struct EmulatorAssignmentTests {
    func resolver(installed: Set<EmulatorKind>, retroArch: RetroArchSetup?, user: [PlatformEmulatorAssignment] = [])
        throws -> EmulatorAssignmentResolver
    {
        let snapshot = try ConsoleFixture.snapshot()
        return EmulatorAssignmentResolver(
            userAssignments: user, snapshots: [snapshot], installedKinds: installed, retroArch: retroArch)
    }

    @Test func followsLaunchBoxWhenTheEmulatorIsInstalled() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let resolver = try resolver(installed: [.retroArch, .dolphin], retroArch: retroArch)

        let nes = resolver.resolve(platform: "Nintendo Entertainment System")
        #expect(nes.isReady)
        #expect(nes.assignment?.emulator == .retroArch)
        #expect(nes.assignment?.core == "fceumm_libretro")
        #expect(nes.source == .launchBox("RetroArch"))
        #expect(nes.summary == "RetroArch · fceumm_libretro")

        // The Dolphin core has no Mac build, so the Dolphin app takes over.
        let cube = resolver.resolve(platform: "Nintendo GameCube")
        #expect(cube.isReady)
        #expect(cube.assignment?.emulator == .dolphin)
        #expect(cube.notes.first?.contains("no Mac build") == true)
        #expect(cube.launchBoxCore == "dolphin_libretro")

        // MAME is the LaunchBox default but is not installed; the RetroArch
        // alternative needs a core that is not installed either.
        let arcade = resolver.resolve(platform: "Arcade")
        #expect(!arcade.isReady)
        #expect(arcade.assignment?.emulator == .mame)
        #expect(arcade.problem?.contains("MAME is not installed") == true)

        // AppleWin has no Mac version.
        let apple = resolver.resolve(platform: "Apple II")
        #expect(apple.assignment == nil)
        #expect(apple.problem?.contains("AppleWin") == true)
        #expect(apple.launchBoxEmulatorTitle == "AppleWin")

        let none = resolver.resolve(platform: "Ghost")
        #expect(none.source == .none && none.problem != nil)
    }

    @Test func mameWinsWhenInstalledAndKeepsPortableArguments() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let resolver = try resolver(installed: [.retroArch, .mame], retroArch: retroArch)
        let arcade = resolver.resolve(platform: "Arcade")
        #expect(arcade.isReady)
        #expect(arcade.assignment?.emulator == .mame)
        #expect(arcade.assignment?.arguments == "-artwork_crop -skip_gameinfo -waitvsync -nofilter")
    }

    @Test func userChoiceWinsAndReportsMissingCore() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let user = [
            PlatformEmulatorAssignment(
                platform: "Nintendo Entertainment System", emulator: .retroArch, core: "nestopia"),
            PlatformEmulatorAssignment(platform: "Apple II", emulator: .mednafen),
        ]
        let resolver = try resolver(installed: [.retroArch, .mednafen], retroArch: retroArch, user: user)
        let nes = resolver.resolve(platform: "Nintendo Entertainment System")
        #expect(nes.source == .user)
        #expect(!nes.isReady)
        #expect(nes.problem?.contains("nestopia_libretro is not installed") == true)
        let apple = resolver.resolve(platform: "Apple II")
        #expect(apple.isReady && apple.assignment?.emulator == .mednafen)

        let noRetroArch = try self.resolver(installed: [], retroArch: nil, user: user)
        #expect(
            noRetroArch.resolve(platform: "Nintendo Entertainment System").problem?.contains(
                "RetroArch is not installed") == true)
    }

    @Test func replacedCoresAreNoted() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch, cores: ["swanstation_libretro"])
        let resolver = try resolver(installed: [.retroArch], retroArch: retroArch)
        let psx = resolver.resolve(platform: "Sony Playstation")
        #expect(psx.isReady)
        #expect(psx.assignment?.core == "swanstation_libretro")
        #expect(psx.notes.first?.contains("duckstation_libretro core is not installed") == true)
    }

    @Test func assignmentsRoundTripThroughJSON() throws {
        let assignment = PlatformEmulatorAssignment(platform: "Arcade", emulator: .mame, arguments: "-skip_gameinfo")
        let data = try JSONEncoder().encode(assignment)
        #expect(try JSONDecoder().decode(PlatformEmulatorAssignment.self, from: data) == assignment)
        let minimal = try JSONDecoder().decode(
            PlatformEmulatorAssignment.self, from: Data(#"{"platform":"NES","emulator":"retroArch"}"#.utf8))
        #expect(minimal.core == nil && minimal.arguments.isEmpty)
    }
}

@Suite("ROM launch planning")
struct RomLaunchPlannerTests {
    @Test func plansRetroArchLaunch() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let snapshot = try ConsoleFixture.snapshot()
        let resolver = EmulatorAssignmentResolver(
            snapshots: [snapshot], installedKinds: [.retroArch], retroArch: retroArch)
        let planner = RomLaunchPlanner(snapshot: snapshot)
        let game = try #require(snapshot.game(id: ConsoleFixture.blasterID))
        let resolved = resolver.resolve(platform: game.platform)
        let launch = try planner.plan(
            game: game, resolved: resolved, emulator: retroArch.installation, retroArch: retroArch,
            options: LaunchOptions())
        let rom = ConsoleFixture.rootURL.appendingPathComponent("Games/Nintendo Entertainment System/Test Blaster.zip")
        #expect(
            launch.arguments == [
                "-L", retroArch.coresDirectory!.appendingPathComponent("fceumm_libretro.dylib").path, rom.path,
            ])
        #expect(launch.workingDirectory == rom.deletingLastPathComponent())
        #expect(launch.notes.contains { $0.contains("archive") })
        #expect(launch.commandLine.contains("-L"))

        let fullscreen = try planner.plan(
            game: game, resolved: resolved, emulator: retroArch.installation, retroArch: retroArch,
            options: LaunchOptions(fullscreen: true))
        #expect(fullscreen.arguments[2] == "-f")

        // A game-level `-L` in LaunchBox asks for another core, which is missing here.
        let other = try #require(snapshot.game(id: ConsoleFixture.otherCoreID))
        #expect(throws: RomLaunchError.coreMissing("nestopia_libretro")) {
            try planner.plan(
                game: other, resolved: resolved, emulator: retroArch.installation, retroArch: retroArch,
                options: LaunchOptions())
        }
    }

    @Test func plansDolphinAndMAMELaunches() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let dolphin = try FixtureLibrary.fakeEmulator(.dolphin, in: scratch)
        let mame = try FixtureLibrary.fakeEmulator(.mame, in: scratch)
        let snapshot = try ConsoleFixture.snapshot()
        let resolver = EmulatorAssignmentResolver(
            snapshots: [snapshot], installedKinds: [.retroArch, .dolphin, .mame], retroArch: retroArch)
        let planner = RomLaunchPlanner(snapshot: snapshot)

        let cube = try #require(snapshot.game(id: ConsoleFixture.cubeID))
        let cubeLaunch = try planner.plan(
            game: cube, resolved: resolver.resolve(platform: cube.platform), emulator: dolphin, retroArch: retroArch,
            options: LaunchOptions(fullscreen: true))
        let image = ConsoleFixture.rootURL.appendingPathComponent("Games/Nintendo GameCube/Cube Demo.rvz")
        #expect(cubeLaunch.arguments == ["-b", "-e", image.path, "--config=Dolphin.Display.Fullscreen=True"])
        #expect(cubeLaunch.notes.first?.contains("no Mac build") == true)

        let pacman = try #require(snapshot.game(id: ConsoleFixture.pacmanID))
        let pacmanLaunch = try planner.plan(
            game: pacman, resolved: resolver.resolve(platform: pacman.platform), emulator: mame, retroArch: retroArch,
            options: LaunchOptions())
        let folder = ConsoleFixture.rootURL.appendingPathComponent("Games/Arcade")
        #expect(
            pacmanLaunch.arguments == [
                "pacman", "-rompath", folder.path, "-skip_gameinfo", "-window", "-artwork_crop", "-waitvsync",
                "-nofilter",
            ])
        #expect(pacmanLaunch.workingDirectory == folder)
    }

    @Test func refusesWhatCannotRun() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try ConsoleFixture.fakeRetroArch(in: scratch)
        let dolphin = try FixtureLibrary.fakeEmulator(.dolphin, in: scratch)
        let snapshot = try ConsoleFixture.snapshot()
        let planner = RomLaunchPlanner(snapshot: snapshot)
        let resolver = EmulatorAssignmentResolver(
            snapshots: [snapshot], installedKinds: [.retroArch, .dolphin], retroArch: retroArch)

        let conan = try #require(snapshot.game(id: ConsoleFixture.conanID))
        #expect(throws: RomLaunchError.self) {
            try planner.plan(
                game: conan, resolved: resolver.resolve(platform: conan.platform), emulator: retroArch.installation,
                retroArch: retroArch, options: LaunchOptions())
        }

        let packed = try #require(snapshot.game(id: ConsoleFixture.packedID))
        let psx = ResolvedEmulatorAssignment(
            platform: packed.platform,
            assignment: PlatformEmulatorAssignment(platform: packed.platform, emulator: .retroArch, core: "fceumm"))
        #expect(throws: RomLaunchError.unsupportedFile("rar", .retroArch)) {
            try planner.plan(
                game: packed, resolved: psx, emulator: retroArch.installation, retroArch: retroArch,
                options: LaunchOptions())
        }

        let blaster = try #require(snapshot.game(id: ConsoleFixture.blasterID))
        let zipForDolphin = ResolvedEmulatorAssignment(
            platform: blaster.platform,
            assignment: PlatformEmulatorAssignment(platform: blaster.platform, emulator: .dolphin))
        #expect(throws: RomLaunchError.unsupportedFile("zip", .dolphin)) {
            try planner.plan(
                game: blaster, resolved: zipForDolphin, emulator: dolphin, retroArch: nil, options: LaunchOptions())
        }

        // The wrong emulator for the assignment, and a DOS game.
        let mismatch = ResolvedEmulatorAssignment(
            platform: blaster.platform,
            assignment: PlatformEmulatorAssignment(platform: blaster.platform, emulator: .mame))
        #expect(throws: RomLaunchError.emulatorMissing(.mame)) {
            try planner.plan(
                game: blaster, resolved: mismatch, emulator: dolphin, retroArch: nil, options: LaunchOptions())
        }
        let dos = try FixtureLibrary.snapshot()
        let ultima = try #require(dos.game(id: FixtureLibrary.ultimaID))
        #expect(throws: RomLaunchError.notAnEmulatedGame) {
            try RomLaunchPlanner(snapshot: dos).plan(
                game: ultima, resolved: psx, emulator: retroArch.installation, retroArch: retroArch,
                options: LaunchOptions())
        }
    }

    @Test func dosPlannerRefusesRomEmulators() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let scratch = try FixtureLibrary.scratchDirectory()
        let retroArch = try FixtureLibrary.fakeEmulator(.retroArch, in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let ultima = try #require(snapshot.game(id: FixtureLibrary.ultimaID))
        #expect(throws: LaunchPlanError.notADOSBoxEmulator(.retroArch)) {
            try planner.plan(game: ultima, variant: nil, emulator: retroArch, options: LaunchOptions())
        }
    }
}
