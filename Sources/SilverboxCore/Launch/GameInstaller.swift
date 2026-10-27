import Foundation

/// What installing a game means in eXoDOS: unzip `eXo/eXoDOS/<name>.zip`
/// into `eXo/eXoDOS/`, then apply `eXo/Update/!dos/<name>.zip` if present.
/// eXoWin9x games unzip `eXo/eXoWin9x/<year>/<name>.zip` into that year folder.
nonisolated public struct InstallPlan: Sendable, Hashable {
    public var game: Game
    public var archiveURL: URL
    public var destinationDirectory: URL
    public var installedFolderURL: URL
    public var updateArchiveURL: URL?
    /// The game's manual, music, videos and extras
    /// (`Content/GameData/<pack>/<name>.zip`), when the setup left them packed.
    public var extrasArchiveURL: URL?
    /// Where the extras unpack: the library folder.
    public var extrasDestination: URL?
    /// The entries to take from ``extrasArchiveURL``, when it is the pack's
    /// config archive rather than a GameData zip of the game's own.
    public var extrasPatterns: [String] = []
    /// An existing save backup that can be restored after unpacking.
    public var saveArchiveURL: URL?
    /// Where a save backup is written on uninstall.
    public var saveBackupURL: URL
    public var location: InstallLocation

    /// Shared save files as well as the physical game folder.
    public var operationURLs: [URL] {
        [installedFolderURL, archiveURL, saveBackupURL] + [saveArchiveURL].compactMap { $0 }
    }

    public var archiveExists: Bool { FileManager.default.fileExists(atPath: archiveURL.path) }
    public var isInstalled: Bool { FileManager.default.fileExists(atPath: installedFolderURL.path) }

    public var archiveSize: Int64? {
        (try? FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? Int64) ?? nil
    }

    public var saveArchiveDate: Date? {
        guard let saveArchiveURL else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: saveArchiveURL.path)[.modificationDate] as? Date)
            ?? nil
    }
}

nonisolated public enum InstallError: Error, Sendable, Equatable {
    case notADOSGame
    case archiveMissing(URL)
    case extractionFailed(status: Int32, output: String)
    case folderMissingAfterExtract(URL)
    case notInstalled
    case alreadyInstalled(URL)
    case unsafeDestination
}

nonisolated extension InstallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notADOSGame: return "This item is not an eXo game that installs from an archive."
        case .archiveMissing(let url):
            return
                "The game archive is not present: \(url.lastPathComponent). This copy may be a Lite edition; downloading is not supported yet."
        case .extractionFailed(let status, let output): return "Unzip failed (exit code \(status)). \(output)"
        case .folderMissingAfterExtract(let url):
            return "The archive did not create the expected folder \(url.lastPathComponent)."
        case .notInstalled: return "The game is not installed."
        case .alreadyInstalled(let url):
            return "A game is already installed at \(url.path). It has been left unchanged."
        case .unsafeDestination: return "The installation path is not a safe game folder."
        }
    }
}

/// How far an installation has come: the step under way and the files
/// written so far, out of the archive's total when that is known.
nonisolated public struct InstallProgress: Sendable, Hashable {
    public var stage: String
    public var filesDone: Int
    public var filesTotal: Int?

    public init(stage: String, filesDone: Int = 0, filesTotal: Int? = nil) {
        self.stage = stage
        self.filesDone = filesDone
        self.filesTotal = filesTotal
    }

    /// 0 to 1, or nil while the total is unknown.
    public var fraction: Double? {
        guard let filesTotal, filesTotal > 0 else { return nil }
        return min(1, Double(filesDone) / Double(filesTotal))
    }
}

nonisolated public protocol ArchiveExtractor: Sendable {
    /// Extracts `archive` into `directory`, overwriting existing files.
    func extract(archive: URL, into directory: URL) async throws
    /// Extracts only the entries that match `patterns`.
    func extract(archive: URL, into directory: URL, only patterns: [String]) async throws
    /// The same, telling `onFile` the number of entries written so far.
    func extract(archive: URL, into directory: URL, only patterns: [String], onFile: (@Sendable (Int) -> Void)?)
        async throws
}

nonisolated extension ArchiveExtractor {
    public func extract(archive: URL, into directory: URL, only patterns: [String]) async throws {
        try await ZipArchive.extract(archive, into: directory, only: patterns)
    }

    public func extract(
        archive: URL, into directory: URL, only patterns: [String], onFile: (@Sendable (Int) -> Void)?
    ) async throws {
        try await ZipArchive.extract(archive, into: directory, only: patterns, onFile: onFile)
    }
}

/// Extracts with the system tools, through ``ZipArchive``.
nonisolated public struct UnzipCommandExtractor: ArchiveExtractor {
    public init() {}

    public func extract(archive: URL, into directory: URL) async throws {
        try await ZipArchive.extract(archive, into: directory)
    }
}

nonisolated public struct CommandResult: Sendable, Hashable {
    public var status: Int32
    /// Standard output and error as UTF-8; empty when they are not valid UTF-8.
    public var output: String
    /// The same output as bytes.
    public var data: Data
}

/// Runs a command to completion and collects its output.
nonisolated public enum CommandRunner {
    public static func run(
        executable: URL, arguments: [String], workingDirectory: URL? = nil, standardInput: URL? = nil
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let workingDirectory { process.currentDirectoryURL = workingDirectory }
            if let standardInput, let handle = FileHandle(forReadingAtPath: standardInput.path) {
                process.standardInput = handle
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            // Read while the command runs: a command that prints more than
            // the pipe holds would otherwise block and never exit.
            let collected = CollectedOutput()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                collected.append(handle.availableData)
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
                let data = collected.data
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(
                    returning: CommandResult(status: finished.terminationStatus, output: output, data: data))
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Output gathered from a pipe's background reads.
nonisolated private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

nonisolated public struct GameInstaller: Sendable {
    public let snapshot: LibrarySnapshot
    public let installLocation: InstallLocation

    public init(snapshot: LibrarySnapshot, installLocation: InstallLocation = .localStore) {
        self.snapshot = snapshot
        self.installLocation = installLocation
    }

    public func plan(for game: Game) -> InstallPlan? {
        guard let pack = game.eXoPack, let components = game.installPathComponents,
            let folderName = components.last,
            components.allSatisfy({ !$0.isEmpty && $0 != ".." && !$0.hasPrefix(".silverbox-") })
        else { return nil }
        let root = snapshot.root
        let localStore = snapshot.localStore
        // The zip sits beside the folder it unpacks to: `eXoDOS/<name>.zip`,
        // `eXoWin9x/<year>/<name>.zip`.
        let parent = components.dropLast().joined(separator: "/")
        let archive = root.downloadFile("eXo/\(parent)/\(game.launcherBaseName).zip")
        let update = root.updateDirectory.appendingPathComponent(pack.configFolderName, isDirectory: true)
            .appendingPathComponent("\(game.launcherBaseName).zip")

        let destination: URL
        let location: InstallLocation
        if let existing = snapshot.installedLocation(for: game) {
            destination = existing.url.deletingLastPathComponent()
            location = existing.isLocal ? .localStore : .inPlace
        } else if installLocation == .localStore, let localStore {
            destination = localStore.gamesRoot.appendingPathComponent(parent, isDirectory: true)
            location = .localStore
        } else {
            destination = root.eXoDirectory.appendingPathComponent(parent, isDirectory: true)
            location = .inPlace
        }

        let librarySave = root.eXoDirectory.appendingPathComponent(pack.directoryName, isDirectory: true)
            .appendingPathComponent("!save", isDirectory: true)
            .appendingPathComponent("\(game.launcherBaseName).zip")
        let installedFolder = destination.appendingPathComponent(folderName, isDirectory: true)
        let backupTarget = localStore?.saveArchiveURL(for: game, installation: installedFolder) ?? librarySave
        let existingSave = [backupTarget, localStore?.saveArchiveURL(for: game), librarySave].compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }

        // A Mac setup can leave each game's extras packed until it is
        // installed: in a GameData zip of its own, or in the pack's config
        // archive under the game's `Extras` folder.
        var extras: URL?
        var extrasPatterns: [String] = []
        if let record = EXoSetupRecord.read(in: root.url), !record.options.unpackGameData {
            let url = root.downloadFile("Content/GameData/\(pack.directoryName)/\(game.launcherBaseName).zip")
            let configArchive = root.downloadFile(pack.configArchivePath)
            if FileManager.default.fileExists(atPath: url.path) {
                extras = url
            } else if let rootFolder = game.rootFolder, FileManager.default.fileExists(atPath: configArchive.path) {
                let folder = WindowsPath.components(of: rootFolder).joined(separator: "/")
                extras = configArchive
                extrasPatterns = [ZipArchive.literalPattern(folder) + "/Extras/*"]
            }
        }

        return InstallPlan(
            game: game,
            archiveURL: archive,
            destinationDirectory: destination,
            installedFolderURL: destination.appendingPathComponent(folderName, isDirectory: true),
            updateArchiveURL: FileManager.default.fileExists(atPath: update.path) ? update : nil,
            extrasArchiveURL: extras,
            extrasDestination: extras == nil ? nil : root.url,
            extrasPatterns: extrasPatterns,
            saveArchiveURL: existingSave,
            saveBackupURL: backupTarget,
            location: location
        )
    }

    @concurrent public func install(
        _ plan: InstallPlan, restoreSaves: Bool = false, extractor: any ArchiveExtractor = UnzipCommandExtractor(),
        progress: (@Sendable (InstallProgress) -> Void)? = nil
    ) async throws {
        // Reserve the extras' actual file paths rather than the whole
        // collection: unrelated games may still install in parallel.
        var resources = plan.operationURLs
        if let extras = plan.extrasArchiveURL, let destination = plan.extrasDestination {
            let prefixes = plan.extrasPatterns.map(ZipArchive.literalPrefix(of:))
            let entries = try await ZipArchive.entries(of: extras)
            resources += entries.filter { entry in
                !entry.hasSuffix("/") && (prefixes.isEmpty || prefixes.contains { entry.hasPrefix($0) })
            }.map { destination.appendingPathComponent($0) }
        }
        let lease = try FileOperationCoordinator.shared.acquire(
            resources, operation: "installation of \(plan.game.title)")
        defer { lease.release() }
        try Task.checkCancellation()
        guard plan.archiveExists else { throw InstallError.archiveMissing(plan.archiveURL) }
        guard !plan.isInstalled else { throw InstallError.alreadyInstalled(plan.installedFolderURL) }
        let fm = FileManager.default
        // A sibling staging folder stays on the destination volume, but is
        // never counted as an installed game. Only its game folder is committed.
        try fm.createDirectory(at: plan.destinationDirectory, withIntermediateDirectories: true)
        let staging = plan.destinationDirectory.appendingPathComponent(
            ".silverbox-install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var steps: [(stage: String, archive: URL, destination: URL, patterns: [String])] = [
            ("Unpacking the game", plan.archiveURL, staging, [])
        ]
        if let update = plan.updateArchiveURL { steps.append(("Applying eXo's update", update, staging, [])) }
        if let extras = plan.extrasArchiveURL, let destination = plan.extrasDestination {
            steps.append(("Unpacking the extras", extras, destination, plan.extrasPatterns))
        }
        if restoreSaves, let save = plan.saveArchiveURL {
            steps.append(("Restoring saved progress", save, staging, []))
        }
        for step in steps {
            try Task.checkCancellation()
            let total: Int? =
                progress != nil && step.patterns.isEmpty ? try? await ZipArchive.entries(of: step.archive).count : nil
            progress?(InstallProgress(stage: step.stage, filesDone: 0, filesTotal: total))
            try await extractor.extract(archive: step.archive, into: step.destination, only: step.patterns) { done in
                progress?(InstallProgress(stage: step.stage, filesDone: done, filesTotal: total))
            }
        }
        let name = plan.installedFolderURL.lastPathComponent
        let matches = try fm.contentsOfDirectory(
            at: staging, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        .filter { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
        guard matches.count == 1, let stagedGame = matches.first else {
            throw InstallError.folderMissingAfterExtract(plan.installedFolderURL)
        }
        let values = try stagedGame.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw InstallError.unsafeDestination }
        try Task.checkCancellation()
        guard !plan.isInstalled else { throw InstallError.alreadyInstalled(plan.installedFolderURL) }
        // moveItem refuses to replace an existing folder. Never remove an
        // existing installation to make this commit succeed.
        try fm.moveItem(at: stagedGame, to: plan.installedFolderURL)
    }

    /// Removes the game folder. With `backupSaves`, files that are new or
    /// changed since the original archive are zipped first. Returns the
    /// number of files backed up.
    @discardableResult
    @concurrent public func uninstall(_ plan: InstallPlan, backupSaves: Bool) async throws -> Int {
        let lease = try FileOperationCoordinator.shared.acquire(
            plan.operationURLs, operation: "removal of \(plan.game.title)")
        defer { lease.release() }
        try Task.checkCancellation()
        guard plan.isInstalled else { throw InstallError.notInstalled }
        var saved = 0
        if backupSaves {
            guard plan.archiveExists else { throw InstallError.archiveMissing(plan.archiveURL) }
            saved = try await SaveArchiver.backup(
                folder: plan.installedFolderURL, originalArchive: plan.archiveURL, to: plan.saveBackupURL)
        }
        try Task.checkCancellation()
        try FileManager.default.removeItem(at: plan.installedFolderURL)
        return saved
    }
}
