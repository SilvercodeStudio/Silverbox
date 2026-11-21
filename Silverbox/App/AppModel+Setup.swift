import AppKit
import Foundation
import SilverboxCore

/// An eXo download waiting for the setup sheet.
struct PendingSetup: Identifiable {
    let download: EXoDownload
    /// The folder in the local data folder that setup can write to, which
    /// leaves the download unchanged.
    let localTarget: URL
    /// Where an earlier setup wrote; a new setup goes to the same place.
    let previousTarget: URL?
    /// The packs a previous setup there covered; empty for a first setup.
    let setUpPacks: [String]
    var id: URL { download.root }

    /// Setup can write into the download itself.
    var canSetUpInPlace: Bool {
        previousTarget.map { isDownload($0) } ?? download.isWritable
    }

    /// Setup can write to either place, so the sheet offers the choice.
    var offersChoice: Bool { previousTarget == nil && download.isWritable }

    func target(inPlace: Bool) -> URL {
        if let previousTarget { return previousTarget }
        return inPlace && download.isWritable ? download.root : localTarget
    }

    func isDownload(_ url: URL) -> Bool { url.standardizedFileURL == download.root.standardizedFileURL }
}

/// Setting up eXo downloads on the Mac, without eXo's Windows setup.
extension AppModel {
    /// Asks for a collection's folder, and adds the one the user chooses.
    func chooseCollection() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an eXo download, a collection that is set up, or a LaunchBox library folder."
        panel.prompt = "Add"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addChosenFolder(url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: done)
        } else {
            panel.begin(completionHandler: done)
        }
    }

    /// Adds the folder the user chose in the open panel. A folder that is a
    /// level off (`eXo` or `Data` inside a collection, or the folder around
    /// one collection) gives the collection it belongs to.
    func addChosenFolder(_ url: URL) {
        folderBeingRead = url.lastPathComponent
        Task {
            let choice = await Task.detached { LibraryFolderChoice.resolve(url) }.value
            folderBeingRead = nil
            switch choice {
            case .library(let folder), .corrected(let folder):
                addFolder(folder)
            case .several(let folders):
                alert = AppAlert(
                    title: "\(url.lastPathComponent) holds \(folders.count) collections",
                    message:
                        "Add them one at a time: \(ListFormatter.localizedString(byJoining: folders.map(\.lastPathComponent)))."
                )
            case .notALibrary:
                alert = AppAlert(
                    title: "\(url.lastPathComponent) is not a library folder", message: Self.libraryFolderHelp)
            }
        }
    }

    static let libraryFolderHelp =
        "A collection is an eXo download (eXoDOS, eXoWin9x and others), or any LaunchBox library folder that holds Data and Images."

    /// Adds a folder chosen or dropped by the user. An eXo download opens
    /// the setup sheet first, unless it is already set up.
    func addFolder(_ url: URL) {
        guard EXoDownload.hasPacks(url) else {
            addCollection(url: url)
            return
        }
        folderBeingRead = url.lastPathComponent
        Task {
            await prepareSetup(for: url)
            folderBeingRead = nil
        }
    }

    /// Decides between adding the folder, adding an earlier Mac setup of it,
    /// and showing the setup sheet.
    func prepareSetup(for url: URL) async {
        guard let download = await EXoDownload.inspect(url) else {
            addCollection(url: url)
            return
        }
        let localTarget = localSetupTarget(for: download)
        // An earlier Mac setup wrote its record in the download or in the local data folder.
        let previous = [download.root, localTarget].lazy
            .filter { EXoSetupTarget.belongs(to: download.root, target: $0) }
            .compactMap { target in EXoSetupRecord.read(in: target).map { (target: target, record: $0) } }.first
        let packs = Set(download.packs.map(\.name))
        if let previous, packs.isSubset(of: Set(previous.record.packs)) {
            addSetUpCollection(download: download, target: previous.target)
            return
        }
        if previous == nil, download.isSetUp {
            // Set up by eXo's own setup on Windows.
            addCollection(url: url)
            return
        }
        pendingSetup = PendingSetup(
            download: download, localTarget: localTarget, previousTarget: previous?.target,
            setUpPacks: previous?.record.packs ?? [])
    }

    /// A folder named after the download in the local data folder.
    func localSetupTarget(for download: EXoDownload) -> URL {
        EXoSetupTarget.localTarget(for: download.root, in: localStore)
    }

    func startSetup(_ pending: PendingSetup, target: URL, options: EXoSetupOptions) {
        guard setupTask == nil else { return }
        let setup = EXoSetup(download: pending.download, target: target, options: options)
        setupProgress = EXoSetupProgress(stage: "Starting", detail: nil, fraction: 0)
        let throttle = ProgressThrottle()
        setupTask = Task { [weak self] in
            do {
                try await setup.run { progress in
                    guard throttle.shouldReport(progress) else { return }
                    // An update can arrive after the setup finished; it must not bring the progress back.
                    Task { @MainActor in
                        guard let self, self.setupTask != nil else { return }
                        self.setupProgress = progress
                        self.updateDockProgress()
                    }
                }
                guard let self else { return }
                self.setupTask = nil
                self.setupProgress = nil
                self.pendingSetup = nil
                self.updateDockProgress()
                JobNotifier.notify(
                    title: "Setup finished",
                    body:
                        "\(ListFormatter.localizedString(byJoining: pending.download.packs.map(\.displayName))) is ready."
                )
                self.addSetUpCollection(download: pending.download, target: target)
            } catch {
                guard let self else { return }
                self.setupTask = nil
                self.setupProgress = nil
                self.updateDockProgress()
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
nonisolated private final class ProgressThrottle: @unchecked Sendable {
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
