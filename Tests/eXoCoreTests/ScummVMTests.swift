import Foundation
import Testing

@testable import eXoCore

/// A small eXoScummVM library in a scratch folder, laid out as eXo installs
/// it: the index, eXo's settings files, MT-32 files and three games.
nonisolated enum ScummVMFixture {
    static let index = """
        \u{FEFF}Beneath a Steel Sky (CD DOS);sky:sky ;scummvm.exe\r
        King's Quest VI;sci:kq6;2.9.0\\scummvm.exe\r
        King's Quest VI (CD DOS);kq6-cd;2.9.0\\scummvm.exe\r
        Black Cauldron, The;agi:bc;scummvm.exe\r
        Black Cauldron, The (Later);agi:bc-later;scummvm.exe\r
        CGA;agi:bc-cga;scummvm.exe\r
        """

    static let globalSettings = """
        [scummvm]
        savepath=.\\Emulators\\scmvm\\SavedGames
        versioninfo=2.8.0
        scale_factor=8

        [lol-dos]
        engineid=kyra
        gameid=lol
        """

    static let versionSettings = """
        [scummvm]
        versioninfo=2.9.0

        [kq6-cd]
        engineid=sci
        gameid=kq6
        enable_high_resolution_graphics=true
        """

    static func game(_ name: String) -> Game {
        Game(
            id: "svm-\(name)", title: name, platform: "ScummVM",
            applicationPath: "eXo\\eXoScummVM\\!ScummVM\\\(name)\\\(name).bat",
            rootFolder: "eXo\\eXoScummVM\\!ScummVM\\\(name)")
    }

    static let sky = game("Beneath a Steel Sky (CD DOS)")
    static let kq6 = game("King's Quest VI")
    static let cauldron = game("Black Cauldron, The")

    /// Writes the library, with every game unpacked, and returns a snapshot.
    static func make(in scratch: URL) throws -> LibrarySnapshot {
        let fm = FileManager.default
        let root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
        func write(_ text: String, _ path: String) throws {
            let url = root.eXoDirectory.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(index, "util/scummvm.txt")
        try write(globalSettings, "emulators/scmvm/scummvm.ini")
        try write(versionSettings, "emulators/scmvm/2.9.0/scummvm.ini")
        try write("rom", "mt32/MT32_CONTROL.ROM")
        try write("sf2", "mt32/SoundCanvas.sf2")

        try write("--subtitles:", "eXoScummVM/Beneath a Steel Sky (CD DOS)/Beneath a Steel Sky (CD DOS)/subtitle.txt")
        try write("data", "eXoScummVM/Beneath a Steel Sky (CD DOS)/Beneath a Steel Sky (CD DOS)/sky.dsk")

        let kq6 = "eXoScummVM/King's Quest VI/"
        try write("Press Ctrl+F5 for the menu.", kq6 + "note.txt")
        try write("pc:", kq6 + "King's Quest VI (CD DOS)/platform.txt")
        try write("Sound Blaster:Roland MT32:Sound Canvas", kq6 + "King's Quest VI (CD DOS)/sound.txt")
        try write("--midi-gain=220:", kq6 + "King's Quest VI (CD DOS)/mt32_audio.txt")
        try write("windows:", kq6 + "King's Quest VI (Windows)/platform.txt")

        let cauldron = "eXoScummVM/Black Cauldron, The/"
        try write("menu", cauldron + "Black Cauldron, The (Later)/menu.txt")
        try write("--render-mode=cga:", cauldron + "Black Cauldron, The (Later)/CGA/video.txt")
        try write("data", cauldron + "Black Cauldron, The (Later)/EGA/vol.0")
        try write("data", cauldron + "Black Cauldron, The (Original)/vol.0")

        return LibrarySnapshot(
            root: root, games: [sky, Self.kq6, Self.cauldron], platforms: [], categories: [], platformFolders: [],
            playlists: [], parents: [], alternateNames: [], additionalApplications: [],
            installedGamePaths: LibraryLoader.installedGamePaths(in: root.eXoDirectory),
            localStore: LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true)))
    }
}

@Suite("eXoScummVM launching")
struct ScummVMTests {
    @Test func readsTheIndexAsFindstrDoes() {
        let index = ScummVMIndex.parse(ScummVMFixture.index)
        #expect(index.entries.count == 6)
        // The id loses its trailing space; the build folder comes from the path.
        #expect(index.entry(forPrefix: "Beneath a Steel Sky (CD DOS)")?.gameID == "sky:sky")
        #expect(index.entry(forPrefix: "Beneath a Steel Sky (CD DOS)")?.versionFolder == "")
        #expect(index.entry(forPrefix: "King's Quest VI (CD DOS)")?.versionFolder == "2.9.0")
        // A prefix match: the last line that starts with the name wins.
        #expect(index.entry(forPrefix: "Black Cauldron, The")?.gameID == "agi:bc-later")
        #expect(index.entry(forPrefix: "Nothing") == nil)
        #expect(
            ScummVMIndex.parse("Gobliiins 1 (DOS CD);gob:gob1cd;2.9.0\\scummvm.exe").entries.first?.gameID == "gob:gob1"
        )
        // The game's own name also matches its versions' lines, as on Windows.
        #expect(index.entry(forPrefix: "King's Quest VI")?.gameID == "kq6-cd")
        #expect(index.entry(forPrefix: "King's Quest VI")?.engineID == nil)
    }

    @Test func recognisesScummVMGames() {
        #expect(ScummVMFixture.sky.launchKind == .scummVM)
        #expect(ScummVMFixture.sky.eXoPack == .scummVM)
        #expect(!ScummVMFixture.sky.isDOSGame)
    }

    @Test func listsVersionsAndSubMenus() throws {
        let snapshot = try ScummVMFixture.make(in: try FixtureLibrary.scratchDirectory())
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: snapshot.root.url)
        #expect(
            planner.variants(for: ScummVMFixture.kq6).map(\.id) == [
                "King's Quest VI (CD DOS)", "King's Quest VI (Windows)",
            ])
        let cauldron = planner.variants(for: ScummVMFixture.cauldron)
        #expect(
            cauldron.map(\.id) == [
                "Black Cauldron, The (Later)/CGA", "Black Cauldron, The (Later)/EGA", "Black Cauldron, The (Original)",
            ])
        #expect(cauldron[0].title == "Black Cauldron, The (Later) › CGA")
        #expect(
            planner.variants(for: ScummVMFixture.kq6).map(\.title) == [
                "King's Quest VI (CD DOS)", "King's Quest VI (Windows)",
            ])
        #expect(LaunchPlanner.versionLabel("KQ6 (DOS CD)", within: "KQ6 (Multi-Platform)") == "DOS CD")
        #expect(LaunchPlanner.versionLabel("KQ6 (DOS Floppy EGA)", within: "KQ6 (DOS Floppy)") == "DOS Floppy EGA")
        #expect(LaunchPlanner.versionLabel("Other (DOS)", within: "KQ6 (Multi-Platform)") == "Other (DOS)")
        #expect(planner.scummVMNote(for: ScummVMFixture.kq6, variant: nil) == "Press Ctrl+F5 for the menu.")
    }

    @Test func plansAVersionWithMT32Music() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try ScummVMFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let emulator = try FixtureLibrary.fakeEmulator(.scummVM, in: scratch)
        let game = ScummVMFixture.kq6
        let cd = try #require(planner.variants(for: game).first)
        let plan = try planner.plan(
            game: game, variant: cd, emulator: emulator, options: LaunchOptions(windowSize: .medium),
            choices: LaunchChoices(music: "Roland MT32"))
        let eXo = snapshot.root.eXoDirectory.path
        let installed = snapshot.root.eXoDirectory.appendingPathComponent(
            "eXoScummVM/King's Quest VI/King's Quest VI (CD DOS)")
        #expect(
            plan.arguments == [
                "-F", "--scale-factor=4", "--stretch-mode=pixel-perfect", "--platform=pc", "--opl-driver=nuked",
                "--output-rate=44100", "-emt32", "--multi-midi", "--extrapath=\(eXo)/mt32", "--midi-gain=220",
                "--config=\(plan.configURL.path)", "--savepath=\(snapshot.localStore!.scummVMSavesDirectory.path)",
                "--path=\(installed.path)", "kq6-cd",
            ])
        // The target comes from eXo's 2.9.0 settings; the save folder is local.
        let settings = ScummVMSettings.parse(plan.configText)
        #expect(settings.value("kq6-cd", "enable_high_resolution_graphics") == "true")
        #expect(settings.value("scummvm", "savepath") == snapshot.localStore?.scummVMSavesDirectory.path)
        #expect(settings.value("scummvm", "versioninfo") == nil)
        #expect(planner.scummVMGameID(for: game, variant: cd) == "sci:kq6")

        // Sound Canvas finds the SoundFont whatever the case of its name.
        let canvas = try planner.plan(
            game: game, variant: cd, emulator: emulator, options: LaunchOptions(),
            choices: LaunchChoices(music: "Sound Canvas"))
        #expect(canvas.arguments.contains("--soundfont=\(eXo)/mt32/SoundCanvas.sf2"))
    }

    @Test func followsEXoForSingleVersionsAndSubMenus() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try ScummVMFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let emulator = try FixtureLibrary.fakeEmulator(.scummVM, in: scratch)

        // One version: subtitles by default, no platform, the game's own line.
        let sky = try planner.plan(
            game: ScummVMFixture.sky, variant: nil, emulator: emulator, options: LaunchOptions(fullscreen: true))
        #expect(sky.arguments.first == "-f")
        #expect(sky.arguments.contains("--subtitles"))
        #expect(!sky.arguments.contains { $0.hasPrefix("--platform") })
        #expect(sky.arguments.last == "sky:sky")
        let quiet = try planner.plan(
            game: ScummVMFixture.sky, variant: nil, emulator: emulator, options: LaunchOptions(),
            choices: LaunchChoices(subtitles: false))
        #expect(!quiet.arguments.contains("--subtitles"))

        // A sub-menu version: its own line when there is one, its video options.
        let cga = try #require(planner.variants(for: ScummVMFixture.cauldron).first)
        let plan = try planner.plan(
            game: ScummVMFixture.cauldron, variant: cga, emulator: emulator, options: LaunchOptions())
        #expect(plan.arguments.contains("--render-mode=cga"))
        #expect(plan.arguments.last == "agi:bc-cga")
        #expect(plan.arguments.contains { $0.hasSuffix("Black Cauldron, The (Later)/CGA") })
    }

    @Test func keepsChangesScummVMWrites() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let snapshot = try ScummVMFixture.make(in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let emulator = try FixtureLibrary.fakeEmulator(.scummVM, in: scratch)
        let first = try planner.plan(
            game: ScummVMFixture.sky, variant: nil, emulator: emulator, options: LaunchOptions())
        try first.writeConfig()
        // ScummVM saves its own settings to the file between launches.
        var changed = ScummVMSettings.parse(first.configText)
        changed.set("scummvm", "music_volume", "100")
        try changed.serialized().write(to: first.configURL, atomically: true, encoding: .utf8)

        let second = try planner.plan(
            game: ScummVMFixture.kq6, variant: nil, emulator: emulator, options: LaunchOptions())
        let settings = ScummVMSettings.parse(second.configText)
        #expect(settings.value("scummvm", "music_volume") == "100")
        #expect(settings.value("scummvm", "scale_factor") == "8")
        #expect(settings.section("kq6-cd") != nil)
    }

    @Test func readsTheGameList() {
        let games = ScummVMGames(
            listGamesOutput: """
                Game ID                        Full Title
                ------------------------------ -----------------------------------
                sci:kq6                        King's Quest VI: Heir Today, Gone Tomorrow
                scumm:Baseball2003             Backyard Baseball 2003
                cryomni3d:versailles           Versailles 1685
                """)
        #expect(games.supports("sci:kq6"))
        #expect(games.supports("scumm:baseball2003"))
        #expect(games.supports("versailles"))
        #expect(!games.supports("losteden"))
        #expect(!games.supports("ultima:ultima1"))
    }
}
