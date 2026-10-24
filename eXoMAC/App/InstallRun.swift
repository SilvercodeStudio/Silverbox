import Foundation
import Observation
import eXoCore

/// One installation under way or just finished: what it is doing, how far
/// it has come, and a timestamped log of its steps. Views read it; the
/// model drives it.
@Observable
final class InstallRun: Identifiable {
    enum Phase: Equatable {
        case running
        case finished
        case cancelled
        case failed(String)
    }

    let id = UUID()
    let game: Game
    let startedAt = Date()
    private(set) var phase: Phase = .running
    private(set) var stage = "Preparing"
    /// 0 to 1, or nil while the total is unknown.
    private(set) var fraction: Double?
    private(set) var detail: String?
    private(set) var log: [String] = []
    @ObservationIgnored var task: Task<Void, Never>?

    init(game: Game) {
        self.game = game
        add("Installing \(game.title)")
    }

    var isRunning: Bool { phase == .running }

    func apply(_ progress: InstallProgress) {
        if progress.stage != stage {
            stage = progress.stage
            add(progress.stage)
        }
        fraction = progress.fraction
        detail =
            progress.filesTotal.map { "\(progress.filesDone.formatted()) of \($0.formatted()) files" }
            ?? (progress.filesDone > 0 ? "\(progress.filesDone.formatted()) files" : nil)
    }

    func finish(_ phase: Phase) {
        self.phase = phase
        switch phase {
        case .running: break
        case .finished: add("Done")
        case .cancelled: add("Stopped")
        case .failed(let message): add("Failed: \(message)")
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func add(_ line: String) {
        log.append("\(Self.clock.string(from: Date())) \(line)")
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
