import Foundation
import Testing
@testable import eXoCore

/// Starts real games in the real emulator for a few seconds. Opt in with
/// `EXOMAC_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke`.
@Suite("Launch smoke", .enabled(if: ProcessInfo.processInfo.environment["EXOMAC_LAUNCH_SMOKE"] == "1" && RealLibrary.isAvailable))
struct LaunchSmokeTests {
    @Test func runsUnpackedGamesInStaging() async throws {
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let emulator = try #require(EmulatorLocator.discover(.dosboxStaging))
        let scratch = try FixtureLibrary.scratchDirectory()
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let titles = ProcessInfo.processInfo.environment["EXOMAC_SMOKE_TITLES"]?.components(separatedBy: "|")
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
            let invalid = output.components(separatedBy: "\n").filter { $0.contains("Invalid '") || $0.contains("unknown") && $0.contains("CONFIG") }
            #expect(invalid.isEmpty, "the emulator rejected generated settings: \(invalid)")
        }
    }
}
