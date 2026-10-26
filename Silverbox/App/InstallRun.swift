import Foundation
import Observation
import SilverboxCore

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
    /// True while the run downloads the game's archive, and after a
    /// download that stopped; a stopped download resumes on the next try.
    var isDownloading = false
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

    /// Reports a download of `totalBytes`: how much is done, the speed
    /// and the peers. aria2 counts whole torrent pieces, which can be far
    /// more than a small game's files, so only its fraction is used.
    func apply(_ progress: DownloadProgress, totalBytes: Int64) {
        let looking = progress.connections == 0 && progress.bytesDone == 0
        let stage = looking ? "Looking for peers" : "Downloading"
        if stage != self.stage {
            self.stage = stage
            add(stage)
        }
        fraction = progress.fraction
        guard !looking, let fraction = progress.fraction else {
            detail = nil
            return
        }
        let done = Int64(Double(totalBytes) * fraction)
        var parts = ["\(Formatters.bytes(done)) of \(Formatters.bytes(totalBytes))"]
        if progress.bytesPerSecond > 0 { parts.append("\(Formatters.bytes(progress.bytesPerSecond))/s") }
        if progress.connections > 0 {
            parts.append("\(progress.connections) peer\(progress.connections == 1 ? "" : "s")")
        }
        detail = parts.joined(separator: " · ")
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
