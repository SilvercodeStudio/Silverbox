import Foundation
import Testing
@testable import eXoCore

@Suite("DOSBox config documents")
struct ConfigDocumentTests {
    @Test func parsesAndSerializes() {
        let text = """
        # Config file for Dosbox-ECE r4230
        [sdl]
        fullscreen=false
        output = openglnb
        [cpu]
        cycles=5000
        [autoexec]
        @mount c .\\eXoDOS\\
        c:
        exit
        """
        var document = DOSBoxConfigDocument.parse(text)
        #expect(document.header == ["Config file for Dosbox-ECE r4230"])
        #expect(document.value("sdl", "output") == "openglnb")
        #expect(document.value("CPU", "cycles") == "5000")
        #expect(document.autoexecLines == ["@mount c .\\eXoDOS\\", "c:", "exit"])
        document.set("cpu", "cycles", "max")
        document.set("render", "aspect", "on")
        document.remove("sdl", "output")
        let out = document.serialized()
        #expect(out.contains("[cpu]\ncycles = max\n"))
        #expect(out.contains("[render]\naspect = on\n"))
        #expect(!out.contains("openglnb"))
        #expect(out.hasSuffix("[autoexec]\n@mount c .\\eXoDOS\\\nc:\nexit\n\n"))
    }
}

@Suite("DOSBox index")
struct DOSBoxIndexTests {
    @Test func classifiesBuilds() {
        let index = DOSBoxIndex.parse("""
        Ultima V - Warriors of Destiny (1988):ece4230\\dosbox.exe
        Ultima I - The First Age of Darkness (1986):staging0.81.0a\\dosbox.exe
        Jeopardy! (1987):dosbox.exe
        Some Daum Game (1995):daum\\dosbox.exe
        Some X Game (1996):x\\dosbox.exe
        Weird (1990):GunStick_dosbox\\dosbox.exe
        """)
        #expect(index.count == 6)
        #expect(index.build(forLauncherBaseName: "ultima v - warriors of destiny (1988)")?.family == .ece)
        #expect(index.build(forLauncherBaseName: "Ultima V - Warriors of Destiny (1988)")?.displayName == "DOSBox ECE r4230")
        #expect(index.build(forLauncherBaseName: "Ultima I - The First Age of Darkness (1986)")?.displayName == "DOSBox Staging 0.81.0a")
        #expect(index.build(forLauncherBaseName: "Jeopardy! (1987)")?.family == .vanilla)
        #expect(index.build(forLauncherBaseName: "Some Daum Game (1995)")?.recommendedEmulator == .dosboxX)
        #expect(index.build(forLauncherBaseName: "Some X Game (1996)")?.recommendedEmulator == .dosboxX)
        #expect(index.build(forLauncherBaseName: "Weird (1990)")?.family == .custom)
        #expect(index.build(forLauncherBaseName: "Missing") == nil)
    }
}

@Suite("Autoexec rewriting")
struct AutoexecRewriterTests {
    let base = URL(fileURLWithPath: "/lib/eXo", isDirectory: true)

    @Test func tokenizesQuotes() {
        let tokens = AutoexecRewriter.tokenize("imgmount d \".\\a b\\x.cue\" .\\c\\y.cue -t cdrom")
        #expect(tokens.map(\.text) == ["imgmount", "d", ".\\a b\\x.cue", ".\\c\\y.cue", "-t", "cdrom"])
        #expect(tokens.map(\.quoted) == [false, false, true, false, false, false])
    }

    @Test func rewritesMountPaths() {
        let rewriter = AutoexecRewriter(baseDirectory: base)
        let result = rewriter.rewrite([
            "@mount c .\\eXoDOS\\",
            "mount a .\\eXoDOS\\SuperTet\\floppy -t floppy",
            "imgmount d \".\\eXoDOS\\7thguest\\cd\\T7G1.cue\" \".\\eXoDOS\\7thguest\\cd\\T7G2.cue\" -t cdrom -usecd 0 -ioctl",
            "c:",
            "cd ultima5",
            "@boot 3KTRIVIA.IMG -l a",
            "boot .\\eXoDOS\\bkgm1983\\Backgammon.img",
            "exit",
        ])
        #expect(result.lines == [
            "@mount c \"/lib/eXo/eXoDOS\"",
            "mount a \"/lib/eXo/eXoDOS/SuperTet/floppy\" -t floppy",
            "imgmount d \"/lib/eXo/eXoDOS/7thguest/cd/T7G1.cue\" \"/lib/eXo/eXoDOS/7thguest/cd/T7G2.cue\" -t cdrom",
            "c:",
            "cd ultima5",
            "@boot 3KTRIVIA.IMG -l a",
            "boot \"/lib/eXo/eXoDOS/bkgm1983/Backgammon.img\"",
            "exit",
        ])
        #expect(result.notes.count == 2)
    }
}

@Suite("Config translation")
struct ConfigTranslatorTests {
    @Test func translatesECEConfigForStaging() throws {
        let root = FixtureLibrary.root
        let source = DOSBoxConfigDocument.parse(try String(contentsOf: root.gameConfigsDirectory.appendingPathComponent("ultima5/dosbox.conf"), encoding: .utf8))
        let translator = ConfigTranslator(root: root, emulator: .dosboxStaging, options: LaunchOptions(fullscreen: true, windowSize: .medium))
        let result = translator.translate(source)
        let doc = result.document
        #expect(doc.value("sdl", "fullscreen") == "on")
        #expect(doc.value("sdl", "window_size") == "medium")
        #expect(doc.value("sdl", "output") == nil)
        #expect(doc.value("sdl", "mapperfile") == nil)
        #expect(doc.value("dosbox", "machine") == "svga_s3")
        #expect(doc.value("dosbox", "memsize") == "16")
        #expect(doc.value("dosbox", "startup_verbosity") == "quiet")
        #expect(doc.value("render", "aspect") == "on")
        #expect(doc.value("render", "scaler") == nil)
        #expect(doc.value("render", "shader") == "crt-auto")
        #expect(doc.value("cpu", "core") == "simple")
        #expect(doc.value("cpu", "cputype") == "386")
        #expect(doc.value("cpu", "cpu_cycles") == "5000")
        #expect(doc.value("cpu", "cpu_cycles_protected") == "auto")
        #expect(doc.value("cpu", "cycles") == nil)
        #expect(doc.value("cpu", "cycleup") == "500")
        #expect(doc.value("midi", "mididevice") == "mt32")
        #expect(doc.value("mt32", "romdir") == root.mt32Directory.path)
        #expect(doc.value("fluidsynth", "soundfont") == root.mt32Directory.appendingPathComponent("SoundCanvas.sf2").path)
        #expect(doc.value("speaker", "lpt_dac") == "disney")
        #expect(doc.value("dos", "keyboard_layout") == "auto")
        #expect(doc.autoexecLines.first == "@mount c \"\(root.gamesDirectory.path)\"")
        #expect(doc.autoexecLines.last == "exit")
        #expect(doc.section("pci") == nil)
        #expect(result.notes.isEmpty, "unexpected notes: \(result.notes)")
    }

    @Test func generalMIDIFollowsAvailability() throws {
        let root = FixtureLibrary.root
        let source = DOSBoxConfigDocument.parse(try String(contentsOf: root.gameConfigsDirectory.appendingPathComponent("SuperTet/dosbox.conf"), encoding: .utf8))
        let withoutFluid = ConfigTranslator(root: root, emulator: .dosboxStaging, options: LaunchOptions(), fluidSynthAvailable: false).translate(source)
        #expect(withoutFluid.document.value("midi", "mididevice") == "coreaudio")
        // cycles=auto becomes Staging's split real/protected mode settings.
        #expect(withoutFluid.document.value("cpu", "cpu_cycles") == "3000")
        #expect(withoutFluid.document.value("cpu", "cpu_cycles_protected") == "max")
        let withFluid = ConfigTranslator(root: root, emulator: .dosboxStaging, options: LaunchOptions(), fluidSynthAvailable: true).translate(source)
        #expect(withFluid.document.value("midi", "mididevice") == "fluidsynth")
        #expect(withFluid.document.value("fluidsynth", "soundfont")?.hasSuffix("SoundCanvas.sf2") == true)
        let forced = ConfigTranslator(root: root, emulator: .dosboxStaging, options: LaunchOptions(generalMIDI: .coreAudio), fluidSynthAvailable: true).translate(source)
        #expect(forced.document.value("midi", "mididevice") == "coreaudio")
        #expect(withFluid.document.value("speaker", "tandy") == "on")
        #expect(withFluid.document.value("ipx", "ipx") == "true")
        // The imgmount line loses its Windows-only flags and gets absolute, quoted paths.
        let imgmount = try #require(withFluid.document.autoexecLines.first { $0.hasPrefix("imgmount") })
        #expect(imgmount == "imgmount d \"\(root.gamesDirectory.path)/SuperTet/cd/disc 1.cue\" \"\(root.gamesDirectory.path)/SuperTet/cd/disc 2.cue\" -t cdrom")
    }

    @Test func translatesStagingFormatConfig() {
        let root = FixtureLibrary.root
        let source = DOSBoxConfigDocument.parse("""
        [sdl]
        fullscreen = false
        output = openglnb
        texture_renderer = auto
        [render]
        aspect = true
        glshader = crt-auto
        integer_scaling = auto
        [cpu]
        core = auto
        cycles = 3000
        [mouse]
        mouse_capture = onclick
        dos_mouse_driver = true
        ps2_mouse_model = intellimouse
        [mt32]
        romdir = .\\mt32
        [fluidsynth]
        soundfont = SoundCanvas.sf2
        chorus = off
        [composite]
        composite = auto
        brightness = 0
        [innovation]
        sidmodel = none
        [voodoo]
        voodoo = false
        voodoo_perf = auto
        [midi]
        mididevice = auto
        [autoexec]
        @mount c .\\eXoDOS\\
        exit
        """)
        let result = ConfigTranslator(root: root, emulator: .dosboxStaging, options: LaunchOptions(shader: .sharp), fluidSynthAvailable: false).translate(source)
        let doc = result.document
        #expect(doc.value("render", "shader") == "sharp")
        #expect(doc.value("render", "integer_scaling") == "auto")
        #expect(doc.value("cpu", "cpu_cycles") == "3000")
        #expect(doc.value("mouse", "mouse_capture") == "onclick")
        #expect(doc.value("mouse", "builtin_dos_mouse_driver") == "true")
        #expect(doc.value("mouse", "ps2_mouse_model") == nil)
        #expect(doc.value("mt32", "romdir") == root.mt32Directory.path)
        #expect(doc.value("fluidsynth", "soundfont") == root.mt32Directory.appendingPathComponent("SoundCanvas.sf2").path)
        #expect(doc.value("fluidsynth", "fsynth_chorus") == "off")
        #expect(doc.value("composite", "composite") == "auto")
        #expect(doc.value("composite", "brightness") == nil)
        #expect(doc.value("innovation", "innovation") == "none")
        #expect(doc.value("voodoo", "voodoo") == "false")
        #expect(doc.value("voodoo", "voodoo_perf") == nil)
        #expect(doc.value("midi", "mididevice") == "coreaudio")
        #expect(result.notes.isEmpty, "unexpected notes: \(result.notes)")
    }

    @Test func translatesForDOSBoxX() throws {
        let root = FixtureLibrary.root
        let source = DOSBoxConfigDocument.parse(try String(contentsOf: root.gameConfigsDirectory.appendingPathComponent("ultima5/dosbox.conf"), encoding: .utf8))
        let result = ConfigTranslator(root: root, emulator: .dosboxX, options: LaunchOptions(windowSize: .large)).translate(source)
        let doc = result.document
        #expect(doc.value("sdl", "output") == "openglnb")
        #expect(doc.value("sdl", "windowresolution") == "2560x1920")
        #expect(doc.value("sdl", "fullscreen") == "false")
        #expect(doc.value("sdl", "mapperfile") == nil)
        #expect(doc.value("render", "scaler") == "normal2x")
        #expect(doc.value("cpu", "cycles") == "5000")
        #expect(doc.value("midi", "mididevice") == "mt32")
        #expect(doc.value("midi", "mt32.romdir") == root.mt32Directory.path)
        #expect(doc.value("midi", "fluid.soundfont") == root.mt32Directory.appendingPathComponent("SoundCanvas.sf2").path)
        #expect(doc.value("dosbox", "fastbioslogo") == "true")
        #expect(doc.autoexecLines.first == "@mount c \"\(root.gamesDirectory.path)\"")
    }
}

@Suite("Launch variants")
struct LaunchVariantTests {
    @Test func parsesExceptionMenu() {
        let folder = FixtureLibrary.root.gameConfigsDirectory.appendingPathComponent("ultima5", isDirectory: true)
        let variants = LaunchVariantDetector.variants(inGameConfigFolder: folder)
        #expect(variants.map(\.title) == [
            "Ultima V - Warriors of Destiny",
            "Ultima V - Warriors of Destiny with Ultimapper5",
            "Ultima V - Warriors of Destiny (Upgrade)",
            "Ultima V - Warriors of Destiny (Upgrade) with Ultimapper5",
        ])
        #expect(variants.map { $0.configURL.lastPathComponent } == ["dosbox.conf", "dosbox.conf", "dosbox2.conf", "dosbox2.conf"])
        #expect(variants.map(\.needsWindowsHelper) == [false, true, false, true])
    }

    @Test func fallsBackToConfigFiles() {
        let folder = FixtureLibrary.root.gameConfigsDirectory.appendingPathComponent("SuperTet", isDirectory: true)
        let variants = LaunchVariantDetector.variants(inGameConfigFolder: folder)
        #expect(variants.map(\.title) == ["Default"])
    }
}

@Suite("Launch planning")
struct LaunchPlannerTests {
    @Test func plansStagingLaunch() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let scratch = try FixtureLibrary.scratchDirectory()
        let emulator = try FixtureLibrary.fakeEmulator(.dosboxStaging, in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let ultima = try #require(snapshot.game(id: FixtureLibrary.ultimaID))
        #expect(planner.recommendedEmulator(for: ultima) == .dosboxStaging)
        let variants = planner.variants(for: ultima)
        let plan = try planner.plan(game: ultima, variant: variants[2], emulator: emulator, options: LaunchOptions())
        #expect(plan.workingDirectory == snapshot.root.eXoDirectory)
        #expect(plan.arguments == ["--noprimaryconf", "--nolocalconf", "--working-dir", snapshot.root.eXoDirectory.path, "--conf", plan.configURL.path])
        #expect(plan.configURL.lastPathComponent == "80984a42-2c4e-47b3-a132-b4b439c08cfc-dosbox2-dosboxStaging.conf")
        #expect(plan.sourceConfigURL.lastPathComponent == "dosbox2.conf")
        #expect(plan.configText.contains("cd upgrade"))
        try plan.writeConfig()
        #expect(FileManager.default.fileExists(atPath: plan.configURL.path))
        #expect(plan.commandLine.contains("--conf"))
    }

    @Test func plansDOSBoxXLaunchWithRecommendationNote() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let scratch = try FixtureLibrary.scratchDirectory()
        let emulator = try FixtureLibrary.fakeEmulator(.dosboxX, in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let ultima = try #require(snapshot.game(id: FixtureLibrary.ultimaID))
        let plan = try planner.plan(game: ultima, variant: nil, emulator: emulator, options: LaunchOptions())
        #expect(plan.arguments.first == "-defaultdir")
        #expect(plan.notes.first?.contains("DOSBox ECE r4230") == true)
    }

    @Test func refusesUninstalledGames() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let scratch = try FixtureLibrary.scratchDirectory()
        let emulator = try FixtureLibrary.fakeEmulator(.dosboxStaging, in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let tetris = try #require(snapshot.game(id: FixtureLibrary.tetrisID))
        #expect(throws: LaunchPlanError.notInstalled(folderName: "SuperTet")) {
            try planner.plan(game: tetris, variant: nil, emulator: emulator, options: LaunchOptions())
        }
        let book = try #require(snapshot.game(id: "bbbbbbbb-0000-0000-0000-000000000001"))
        #expect(throws: LaunchPlanError.notADOSGame) {
            try planner.plan(game: book, variant: nil, emulator: emulator, options: LaunchOptions())
        }
    }

    @Test func installPlanLocatesArchives() throws {
        let snapshot = try FixtureLibrary.snapshot()
        let installer = GameInstaller(snapshot: snapshot)
        let tetris = try #require(snapshot.game(id: FixtureLibrary.tetrisID))
        let plan = try #require(installer.plan(for: tetris))
        #expect(plan.archiveURL.lastPathComponent == "Super Tetris (1991).zip")
        #expect(plan.installedFolderURL.lastPathComponent == "SuperTet")
        #expect(!plan.archiveExists)
        #expect(!plan.isInstalled)
        let book = try #require(snapshot.game(id: "bbbbbbbb-0000-0000-0000-000000000001"))
        #expect(installer.plan(for: book) == nil)
    }

    @Test func installsFromZip() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        // Build a tiny library with a real zip archive.
        let root = LibraryRoot(url: scratch)
        let fm = FileManager.default
        try fm.createDirectory(at: root.gamesDirectory, withIntermediateDirectories: true)
        let staging = scratch.appendingPathComponent("stage/MiniGame", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try "hello".write(to: staging.appendingPathComponent("GAME.EXE"), atomically: true, encoding: .utf8)
        let zipURL = root.gamesDirectory.appendingPathComponent("Mini Game (1990).zip")
        let zip = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zip"),
                                              arguments: ["-q", "-r", zipURL.path, "MiniGame"],
                                              workingDirectory: scratch.appendingPathComponent("stage"))
        #expect(zip.status == 0, Comment(rawValue: zip.output))
        let game = Game(id: "mini", title: "Mini Game", platform: "MS-DOS",
                        applicationPath: "eXo\\eXoDOS\\!dos\\MiniGame\\Mini Game (1990).bat",
                        rootFolder: "eXo\\eXoDOS\\!dos\\MiniGame")
        let snapshot = LibrarySnapshot(root: root, games: [game], platforms: [], categories: [], platformFolders: [],
                                       playlists: [], parents: [], alternateNames: [], additionalApplications: [],
                                       dosboxIndex: DOSBoxIndex(), installedFolderNames: [])
        let installer = GameInstaller(snapshot: snapshot)
        let plan = try #require(installer.plan(for: game))
        #expect(plan.archiveExists)
        try await installer.install(plan)
        #expect(fm.fileExists(atPath: plan.installedFolderURL.appendingPathComponent("GAME.EXE").path))
        try installer.uninstall(plan)
        #expect(!plan.isInstalled)
    }
}
