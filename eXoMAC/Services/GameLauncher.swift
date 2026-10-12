import eXoCore
import AppKit
import Foundation
import Observation

/// A running emulator process.
struct GameSession: Identifiable {
    let id: UUID
    let launch: EmulatorLaunch
    let startedAt: Date
    let logURL: URL?
    let processIdentifier: Int32
    var exitStatus: Int32 = 0

    var game: Game { launch.game }
}

/// Starts emulators and reports when they quit.
@Observable
final class GameLauncher {
    private(set) var sessions: [GameSession] = []
    var onSessionEnded: ((GameSession) -> Void)?

    @ObservationIgnored private var processes: [UUID: Process] = [:]
    @ObservationIgnored private var logHandles: [UUID: FileHandle] = [:]

    var isRunning: Bool { !sessions.isEmpty }

    func launch(_ plan: LaunchPlan) throws {
        try launch(plan.launch)
    }

    func launch(_ plan: EmulatorLaunch) throws {
        let id = UUID()
        let process = Process()
        process.executableURL = plan.emulator.executableURL
        process.arguments = plan.arguments
        process.currentDirectoryURL = plan.workingDirectory

        var logURL: URL?
        if (try? FileManager.default.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)) != nil {
            let url = AppPaths.logs.appendingPathComponent("\(LaunchPlanner.safeFileName(plan.game.id)).log")
            let header = "# \(plan.game.title)\n# \(Date())\n# \(plan.commandLine)\n\n"
            if FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8)),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                process.standardOutput = handle
                process.standardError = handle
                logHandles[id] = handle
                logURL = url
            }
        }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in
                self?.finish(id: id, status: status)
            }
        }
        try process.run()
        processes[id] = process
        sessions.append(GameSession(id: id, launch: plan, startedAt: Date(), logURL: logURL, processIdentifier: process.processIdentifier))
    }

    private func finish(id: UUID, status: Int32) {
        processes[id] = nil
        try? logHandles.removeValue(forKey: id)?.close()
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions.remove(at: index)
        session.exitStatus = status
        onSessionEnded?(session)
    }

    func terminate(_ session: GameSession) {
        processes[session.id]?.terminate()
    }

    func bringToFront(_ session: GameSession) {
        NSRunningApplication(processIdentifier: session.processIdentifier)?.activate()
    }
}
