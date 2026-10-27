import AppKit
import Foundation
import Observation
import SilverboxCore

/// A running emulator process.
struct GameSession: Identifiable {
    let id: UUID
    let launch: EmulatorLaunch
    let startedAt: Date
    let logURL: URL?
    let processIdentifier: Int32
    var exitStatus: Int32 = 0
    /// Set when the emulator has quit.
    var endedAt: Date?

    var game: Game { launch.game }
    var isRunning: Bool { endedAt == nil }
}

/// A game left running by an earlier Silverbox session, whose files are
/// reserved again until its emulator quits.
struct AdoptedGame: Identifiable {
    let id: UUID
    let title: String
    let processIdentifier: Int32
}

/// Starts emulators and reports when they quit.
@Observable
final class GameLauncher {
    private(set) var sessions: [GameSession] = []
    private(set) var adopted: [AdoptedGame] = []
    var onSessionEnded: ((GameSession) -> Void)?

    @ObservationIgnored private var processes: [UUID: Process] = [:]
    @ObservationIgnored private var logHandles: [UUID: FileHandle] = [:]

    @ObservationIgnored private var reservations: [UUID: FileOperationLease] = [:]
    @ObservationIgnored private let ledger = RunningGameLedger(url: AppPaths.runningGames)
    @ObservationIgnored private var records: [RunningGameRecord] = []
    @ObservationIgnored private var watchers: [UUID: any DispatchSourceProcess] = [:]

    var isRunning: Bool { !sessions.isEmpty }

    init() {
        adoptGamesLeftRunning()
    }

    func launch(_ plan: LaunchPlan) throws {
        let urls = plan.operationURLs
        let lease = try FileOperationCoordinator.shared.acquire(urls, operation: "\(plan.game.title) playing")
        do {
            try plan.writeConfig()
            try launch(plan.launch, reservation: (lease, urls))
        } catch {
            lease.release()
            throw error
        }
    }

    func launch(_ plan: EmulatorLaunch) throws {
        try launch(plan, reservation: nil)
    }

    private func launch(_ plan: EmulatorLaunch, reservation: (lease: FileOperationLease, urls: [URL])?) throws {
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
                let handle = try? FileHandle(forWritingTo: url)
            {
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
        do {
            try process.run()
        } catch {
            try? logHandles.removeValue(forKey: id)?.close()
            throw error
        }
        if let reservation {
            reservations[id] = reservation.lease
            let pid = process.processIdentifier
            if let start = ProcessStart.time(of: pid) {
                remember(
                    RunningGameRecord(
                        id: id, processIdentifier: pid, processStart: start, title: plan.game.title,
                        paths: reservation.urls.map(\.path)))
            }
        }
        processes[id] = process
        sessions.append(
            GameSession(
                id: id, launch: plan, startedAt: Date(), logURL: logURL, processIdentifier: process.processIdentifier))
    }

    private func finish(id: UUID, status: Int32) {
        processes[id] = nil
        reservations.removeValue(forKey: id)?.release()
        forget(id)
        try? logHandles.removeValue(forKey: id)?.close()
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions.remove(at: index)
        session.exitStatus = status
        session.endedAt = Date()
        onSessionEnded?(session)
    }

    func terminate(_ session: GameSession) {
        processes[session.id]?.terminate()
    }

    func bringToFront(_ session: GameSession) {
        NSRunningApplication(processIdentifier: session.processIdentifier)?.activate()
    }

    // MARK: - Games left running

    /// Reserves the files of games that an earlier session started and that
    /// still run, and releases them when each emulator quits.
    private func adoptGamesLeftRunning() {
        for record in ledger.load() {
            let pid = record.processIdentifier
            guard ProcessStart.time(of: pid) == record.processStart,
                let lease = try? FileOperationCoordinator.shared.acquire(
                    record.paths.map { URL(fileURLWithPath: $0) }, operation: "\(record.title) playing")
            else { continue }
            let watcher = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            watcher.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.release(adopted: record.id) }
            }
            reservations[record.id] = lease
            watchers[record.id] = watcher
            records.append(record)
            adopted.append(AdoptedGame(id: record.id, title: record.title, processIdentifier: pid))
            watcher.resume()
            // The emulator can quit before the watch begins.
            if ProcessStart.time(of: pid) != record.processStart { release(adopted: record.id) }
        }
        try? ledger.save(records)
    }

    private func release(adopted id: UUID) {
        watchers.removeValue(forKey: id)?.cancel()
        reservations.removeValue(forKey: id)?.release()
        adopted.removeAll { $0.id == id }
        forget(id)
    }

    private func remember(_ record: RunningGameRecord) {
        records.append(record)
        try? ledger.save(records)
    }

    private func forget(_ id: UUID) {
        guard records.contains(where: { $0.id == id }) else { return }
        records.removeAll { $0.id == id }
        try? ledger.save(records)
    }
}

/// When the system started a process: in microseconds since 1970, or nil
/// when no process has that number.
enum ProcessStart {
    static func time(of pid: Int32) -> Int64? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
    }
}
