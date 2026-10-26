import Foundation
import SilverboxCore

/// Lets one download run at a time, as eXo's script does; the others wait
/// their turn. Two aria2 processes on one torrent would each look for the
/// same peers.
@MainActor
final class DownloadGate {
    private(set) var isBusy = false
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    /// Waits for the turn. False when the task was cancelled first.
    func acquire() async -> Bool {
        guard isBusy else {
            isBusy = true
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiting.append((id, $0)) }
        } onCancel: {
            Task { @MainActor in self.drop(id) }
        }
    }

    func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().continuation.resume(returning: true)
        }
    }

    private func drop(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: false)
    }
}

extension AppModel {
    /// How to download the game's archive when the collection lacks it, as
    /// in eXo's Lite editions; nil when it is present or no torrent lists it.
    func downloadPlan(for game: Game) -> DownloadPlan? {
        guard let installer = installer(for: game), let plan = installer.plan(for: game) else { return nil }
        return installer.downloadPlan(for: plan)
    }

    /// Downloads the plan's files for an installation, after any download
    /// before it, and reports to the run.
    func download(_ plan: DownloadPlan, for run: InstallRun) async throws {
        guard let downloader = torrentDownloader else { throw TorrentDownloadError.noDownloader }
        if downloadGate.isBusy { run.apply(InstallProgress(stage: "Waiting for another download")) }
        guard await downloadGate.acquire() else { throw CancellationError() }
        defer { downloadGate.release() }
        try Task.checkCancellation()
        run.isDownloading = true
        run.apply(InstallProgress(stage: "Looking for peers"))
        try await downloader.download(plan) { [weak self] progress in
            // The main queue keeps the reports in order; a Task per report would not.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    run.apply(progress, totalBytes: plan.totalBytes)
                    self?.updateDockProgress()
                }
            }
        }
        run.isDownloading = false
    }
}
