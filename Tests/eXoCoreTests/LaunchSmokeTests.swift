import Foundation
import Testing

@testable import eXoCore

/// Starts real games in the real emulator for a few seconds. Opt in with
/// `EXOMAC_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke`.
@Suite(
    "Launch smoke",
    .enabled(if: ProcessInfo.processInfo.environment["EXOMAC_LAUNCH_SMOKE"] == "1" && RealLibrary.isAvailable))
struct LaunchSmokeTests {
    @Test func runsUnpackedGamesInStaging() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        // A local store next to the read-only library, so saves get an overlay mount.
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        try localStore.ensureDirectories()
        let snapshot = try LibraryLoader(root: RealLibrary.root, localStore: localStore).load()
        let emulator = try #require(EmulatorLocator.discover(.dosboxStaging))
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let titles =
            ProcessInfo.processInfo.environment["EXOMAC_SMOKE_TITLES"]?.components(separatedBy: "|")
            ?? ["Super Tetris", "Western Front: The Liberation of Europe 1944-1945"]
        for title in titles {
            let game = try #require(snapshot.games.first { $0.title == title }, "game \(title) not found")
            #expect(snapshot.isInstalled(game), "\(title) is not unpacked on the volume")
            let plan = try planner.plan(game: game, variant: nil, emulator: emulator, options: LaunchOptions())
            try plan.writeConfig()
            print("=== \(title)\n\(plan.commandLine)\n--- notes: \(plan.notes)\n--- config:\n\(plan.configText)")

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
            if alive { process.terminate() }
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            print("--- emulator output (exit \(process.terminationStatus)):\n\(output)")
            #expect(alive, "the emulator quit within 7 seconds")
            #expect(!output.contains("doesn't exist"), "a mount failed")
            #expect(!output.lowercased().contains("config file not found"))
            // Only the start-up part of the log reflects the generated config;
            // later CONFIG lines come from the game's own batch menus.
            let startup = output.components(separatedBy: "AUTOEXEC:").first ?? output
            let invalid = startup.components(separatedBy: "\n").filter {
                $0.contains("Invalid '") || $0.contains("unknown") && $0.contains("CONFIG")
            }
            #expect(invalid.isEmpty, "the emulator rejected generated settings: \(invalid)")
            if planner.libraryIsReadOnly {
                #expect(plan.configText.contains("-t overlay"), "no overlay mount for a read-only library")
                #expect(!output.contains("file creation failed"), "the game could not write despite the overlay")
                let written =
                    (try? FileManager.default.subpathsOfDirectory(atPath: localStore.overlayDirectory.path)) ?? []
                print("--- overlay folder now holds: \(written)")
            }
        }
    }

    /// Boots Windows 98 for one eXoWin9x game in DOSBox-X and one in 86Box,
    /// and checks that Windows writes to the fresh differencing disk. The
    /// 86Box game is installed into a scratch local store first. Set
    /// `EXOMAC_86BOX` to an 86Box executable when it is not in /Applications.
    @Test func bootsWindows9xGames() async throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        try localStore.ensureDirectories()
        var snapshot = try LibraryLoader(root: RealLibrary.root, localStore: localStore).load()

        let box86 =
            ProcessInfo.processInfo.environment["EXOMAC_86BOX"].map {
                EmulatorInstallation(kind: .box86, executableURL: URL(fileURLWithPath: $0))
            } ?? EmulatorLocator.discover(.box86)
        var runs: [(title: String, emulator: EmulatorInstallation)] = []
        if let dosboxX = EmulatorLocator.discover(.dosboxX) { runs.append(("Marathon 2: Durandal", dosboxX)) }
        if let box86 {
            let locus = try #require(snapshot.games.first { $0.title == "Locus" && $0.platform == "Windows 9x" })
            let installer = GameInstaller(snapshot: snapshot, installLocation: .localStore)
            try await installer.install(try #require(installer.plan(for: locus)))
            snapshot = try LibraryLoader(root: RealLibrary.root, localStore: localStore).load()
            runs.append(("Locus", box86))
        }
        #expect(!runs.isEmpty, "neither DOSBox-X nor 86Box was found")

        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        for run in runs {
            let game = try #require(snapshot.games.first { $0.title == run.title && $0.platform == "Windows 9x" })
            let plan = try planner.plan(game: game, variant: nil, emulator: run.emulator, options: LaunchOptions())
            try plan.writeConfig()
            print("=== \(run.title)\n\(plan.commandLine)\n--- notes: \(plan.notes)")

            let log = scratch.appendingPathComponent("\(LaunchPlanner.safeFileName(run.title)).log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            let process = Process()
            process.executableURL = plan.emulator.executableURL
            process.arguments = plan.arguments
            process.currentDirectoryURL = plan.workingDirectory
            process.standardOutput = output
            process.standardError = output
            try process.run()
            try await Task.sleep(for: .seconds(40))
            let alive = process.isRunning
            if alive { process.terminate() }
            process.waitUntilExit()
            try output.close()
            #expect(alive, "\(run.emulator.kind.displayName) quit within 40 seconds")

            // The differencing disk starts empty; Windows writes to it as it boots.
            let child =
                run.emulator.kind == .box86
                ? planner.local86BoxDirectory.appendingPathComponent("W98-C.vhd")
                : planner.windowsDiskDirectory.appendingPathComponent("W98-C.vhd")
            let size = (try FileManager.default.attributesOfItem(atPath: child.path)[.size] as? Int) ?? 0
            print("--- \(child.lastPathComponent) is \(size / 1_048_576) MB after 40 seconds")
            #expect(size > 4 * 1_048_576, "Windows did not write to the differencing disk")
        }
    }
}
