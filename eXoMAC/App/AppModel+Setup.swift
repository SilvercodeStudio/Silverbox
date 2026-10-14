import AppKit
import Foundation
import eXoCore

/// An eXo download waiting for the setup sheet.
struct PendingSetup: Identifiable {
    let download: EXoDownload
    /// Where setup writes: the download, or a folder in the local data
    /// folder when the download cannot be written.
    let target: URL
    /// The packs a previous setup there covered; empty for a first setup.
    let setUpPacks: [String]
    var id: URL { download.root }

    var isInPlace: Bool { target.standardizedFileURL == download.root.standardizedFileURL }
}

/// Setting up eXo downloads on the Mac, without eXo's Windows setup.
extension AppModel {
    /// Adds a folder chosen or dropped by the user. An eXo download opens
    /// the setup sheet first, unless it is already set up.
    func addFolder(_ url: URL) {
        guard EXoDownload.hasPacks(url) else {
            addCollection(url: url)
            return
        }
        Task { await prepareSetup(for: url) }
    }

    /// Decides between adding the folder, adding an earlier Mac setup of it,
    /// and showing the setup sheet.
    func prepareSetup(for url: URL) async {
        guard let download = await EXoDownload.inspect(url) else {
            addCollection(url: url)
            return
        }
        let target = setupTarget(for: download)
        let record = EXoSetupRecord.read(in: target)
        let packs = Set(download.packs.map(\.name))
        if let record, packs.isSubset(of: Set(record.packs)) {
            addSetUpCollection(download: download, target: target)
            return
        }
        if record == nil, download.isSetUp {
            // Set up by eXo's own setup on Windows.
            addCollection(url: url)
            return
        }
        pendingSetup = PendingSetup(download: download, target: target, setUpPacks: record?.packs ?? [])
    }

    /// The download itself when it can be written, else a folder named
    /// after it in the local data folder.
    func setupTarget(for download: EXoDownload) -> URL {
        if download.isWritable { return download.root }
        return localStore.directory.appendingPathComponent("Collections", isDirectory: true)
            .appendingPathComponent(download.root.lastPathComponent, isDirectory: true)
    }

    func startSetup(_ pending: PendingSetup, options: EXoSetupOptions) {
        guard setupTask == nil else { return }
        let setup = EXoSetup(download: pending.download, target: pending.target, options: options)
        setupProgress = EXoSetupProgress(stage: "Starting", detail: nil, fraction: 0)
        let throttle = ProgressThrottle()
        setupTask = Task { [weak self] in
            do {
                try await setup.run { progress in
                    guard throttle.shouldReport(progress) else { return }
                    Task { @MainActor in self?.setupProgress = progress }
                }
                guard let self else { return }
                self.setupTask = nil
                self.setupProgress = nil
                self.pendingSetup = nil
                self.addSetUpCollection(download: pending.download, target: pending.target)
            } catch {
                guard let self else { return }
                self.setupTask = nil
                self.setupProgress = nil
                if !(error is CancellationError) {
                    self.alert = AppAlert(
                        title: "Setup did not finish",
                        message:
                            "\(error.localizedDescription) Run the setup again to continue; it unpacks everything again over what is there."
                    )
                }
            }
        }
    }

    func cancelSetup() {
        setupTask?.cancel()
    }

    /// Adds the set-up folder as a collection, or reloads it when it is one.
    private func addSetUpCollection(download: EXoDownload, target: URL) {
        let downloadPath = target.standardizedFileURL == download.root.standardizedFileURL ? nil : download.root.path
        if let index = settings.collections.firstIndex(where: { $0.root.url == LibraryRoot(url: target).url }) {
            settings.collections[index].downloadPath = downloadPath
            reloadLibrary()
        } else {
            settings.collections.append(
                LibraryCollection(name: download.suggestedName, rootPath: target.path, downloadPath: downloadPath))
        }
    }
}

/// Passes on progress at most every half percent, or when the stage changes.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: EXoSetupProgress?

    func shouldReport(_ progress: EXoSetupProgress) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last, last.stage == progress.stage, last.detail == progress.detail,
            progress.fraction - last.fraction < 0.005, progress.fraction < 1
        {
            return false
        }
        last = progress
        return true
    }
}
