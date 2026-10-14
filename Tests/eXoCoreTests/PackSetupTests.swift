import Foundation
import Testing

@testable import eXoCore

/// Sets up any untouched eXo download (`EXOMAC_SETUP_DOWNLOAD`) into
/// `EXOMAC_SETUP_TARGET`, without its media add-ons, and checks what the app
/// can do with it: games per pack and launch kind, every DOSBox config
/// translated, and a few of the smallest games installed and planned. The
/// download is only read. `EXOMAC_SETUP_REUSE=1` keeps an earlier setup.
@Suite(
    "Mac setup of an eXo pack download",
    .enabled(
        if: ProcessInfo.processInfo.environment["EXOMAC_SETUP_DOWNLOAD"] != nil
            && ProcessInfo.processInfo.environment["EXOMAC_SETUP_TARGET"] != nil))
struct PackSetupTests {
    @Test func setsUpAndPlansTheDownload() async throws {
        let environment = ProcessInfo.processInfo.environment
        let downloadURL = URL(fileURLWithPath: try #require(environment["EXOMAC_SETUP_DOWNLOAD"]), isDirectory: true)
        let target = URL(fileURLWithPath: try #require(environment["EXOMAC_SETUP_TARGET"]), isDirectory: true)
        let download = try #require(await EXoDownload.inspect(downloadURL))
        print("Packs: \(download.packs.map(\.displayName)), add-ons: \(download.addOns.map(\.title))")

        let start = Date()
        let reuse = environment["EXOMAC_SETUP_REUSE"] == "1" && EXoSetupRecord.read(in: target) != nil
        if !reuse {
            let options = EXoSetupOptions(skippedAddOns: download.addOns.map(\.archive.lastPathComponent))
            try await EXoSetup(download: download, target: target, options: options).run { _ in }
        }
        print("Setup took \(Int(Date().timeIntervalSince(start))) s")

        let scratch = try FixtureLibrary.scratchDirectory()
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let collection = LibraryCollection(name: "Pack setup", rootPath: target.path, downloadPath: downloadURL.path)
        let snapshot = try LibraryLoader(collection: collection, localStore: localStore).load()
        let counts = { (key: (Game) -> String) in
            Dictionary(grouping: snapshot.games, by: key).mapValues(\.count).sorted { $0.value > $1.value }
        }
        print("Games: \(snapshot.games.count)")
        print("By platform: \(counts(\.platform))")
        print("By pack: \(counts { $0.eXoPack?.displayName ?? "none" })")
        print("By launch kind: \(counts { "\($0.launchKind)" })")
        #expect(!snapshot.games.contains { $0.isEXoSetupScript })
        #expect(snapshot.games.contains { $0.isEXoGame })

        // Every DOSBox game: its configs, archive and build, and a translation.
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let fm = FileManager.default
        var missing: [String: [String]] = [:]
        var builds: [String: Int] = [:]
        var notes: [String: Int] = [:]
        let dosGames = snapshot.games.filter { $0.launchKind == .dosBox }
        for game in dosGames {
            guard let folder = planner.configFolder(for: game), fm.fileExists(atPath: folder.path) else {
                missing["config folder", default: []].append(game.title)
                continue
            }
            if let pack = game.eXoPack,
                !fm.fileExists(
                    atPath: snapshot.root.downloadFile("eXo/\(pack.directoryName)/\(game.launcherBaseName).zip").path)
            {
                missing["archive", default: []].append(game.title)
            }
            if let build = planner.eXoDOSBuild(for: game) {
                builds[build.displayName, default: 0] += 1
            } else {
                missing["build", default: []].append(game.title)
            }
            let configURL =
                planner.variants(for: game).first?.configURL ?? folder.appendingPathComponent("dosbox.conf")
            guard let data = fm.contents(atPath: configURL.path) else {
                missing["dosbox.conf", default: []].append(game.title)
                continue
            }
            let translator = ConfigTranslator(
                root: snapshot.root, emulator: planner.recommendedEmulator(for: game), options: LaunchOptions(),
                fluidSynthAvailable: false, fallbackDirectories: [folder])
            let result = translator.translate(DOSBoxConfigDocument.parse(String(decoding: data, as: UTF8.self)))
            for note in result.notes { notes[LaunchSweepTests.generalise(note), default: 0] += 1 }
        }
        print("DOSBox games: \(dosGames.count), builds: \(builds.sorted { $0.value > $1.value })")
        for (kind, titles) in missing { print("Missing \(kind): \(titles.count) \(titles.prefix(8))") }
        for (note, count) in notes.sorted(by: { $0.value > $1.value }).prefix(15) { print("  \(count)\t\(note)") }

        // ScummVM: which games this Mac's ScummVM cannot run.
        if let scummVM = EmulatorLocator.discover(.scummVM),
            FileManager.default.fileExists(atPath: planner.scummVMIndexFile.path)
        {
            let listing = try await CommandRunner.run(
                executable: scummVM.executableURL,
                arguments: ["--config=\(scratch.appendingPathComponent("games.ini").path)", "--list-games"])
            let games = ScummVMGames(listGamesOutput: listing.output)
            let index = try ScummVMIndex(contentsOf: planner.scummVMIndexFile)
            // Targets such as kq6-cd are eXo's own names; they resolve through eXo's settings files.
            let missing = index.entries.filter { !games.supports($0.gameID) && $0.gameID.contains(":") }
            let bare = index.entries.filter { !games.supports($0.gameID) && !$0.gameID.contains(":") }
            print("ScummVM games: \(games.ids.count); missing: \(missing.map(\.line))")
            print("Bare ids not found (eXo targets or unsupported): \(bare.map(\.gameID))")
        }

        // Install the three smallest games of each pack and plan the DOSBox ones.
        let installer = GameInstaller(snapshot: snapshot, installLocation: .localStore)
        var installed: [Game] = []
        // EXOMAC_SMOKE_TITLES="A|B" adds games by title.
        let titles = Set(environment["EXOMAC_SMOKE_TITLES"]?.components(separatedBy: "|") ?? [])
        for game in snapshot.games where titles.contains(game.title) {
            if let plan = installer.plan(for: game) {
                try await installer.install(plan)
                installed.append(game)
            }
        }
        for pack in Set(snapshot.games.compactMap(\.eXoPack)) {
            let smallest = snapshot.games.filter { $0.eXoPack == pack }
                .compactMap { game in
                    installer.plan(for: game).flatMap { plan in plan.archiveSize.map { (game, plan, $0) } }
                }
                .sorted { $0.2 < $1.2 }.prefix(3)
            for (game, plan, _) in smallest {
                try await installer.install(plan)
                installed.append(game)
            }
        }
        let after = try LibraryLoader(collection: collection, localStore: localStore).load()
        for game in installed {
            #expect(after.installedLocation(for: game)?.isLocal == true, "\(game.title)")
            guard game.launchKind == .dosBox || game.launchKind == .scummVM else { continue }
            let afterPlanner = LaunchPlanner(snapshot: after, scratchDirectory: scratch)
            let emulator = try FixtureLibrary.fakeEmulator(afterPlanner.recommendedEmulator(for: game), in: scratch)
            let plan = try afterPlanner.plan(game: game, variant: nil, emulator: emulator, options: LaunchOptions())
            #expect(plan.notes.filter { $0.hasPrefix("Could not find") }.isEmpty, "\(game.title): \(plan.notes)")
            print("Planned \(game.title) in \(emulator.kind.displayName): \(plan.commandLine)\n  notes: \(plan.notes)")
            // EXOMAC_LAUNCH_SMOKE=1 also starts it for a few seconds.
            if ProcessInfo.processInfo.environment["EXOMAC_LAUNCH_SMOKE"] == "1",
                let real = EmulatorLocator.discover(emulator.kind)
            {
                try await Self.smoke(
                    try afterPlanner.plan(game: game, variant: nil, emulator: real, options: LaunchOptions()))
            }
        }
    }

    /// Starts the plan's emulator, lets it run, and checks its log.
    static func smoke(_ plan: LaunchPlan) async throws {
        try plan.writeConfig()
        let process = Process()
        process.executableURL = plan.emulator.executableURL
        process.arguments = plan.arguments
        process.currentDirectoryURL = plan.workingDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        try await Task.sleep(for: .seconds(7))
        let alive = process.isRunning
        if alive { await process.stop() }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        print("--- \(plan.game.title) (exit \(process.terminationStatus)):\n\(output.suffix(1500))")
        #expect(alive, "\(plan.game.title): the emulator quit within 7 seconds")
        #expect(!output.contains("doesn't exist"), "\(plan.game.title): a mount failed")
    }
}
