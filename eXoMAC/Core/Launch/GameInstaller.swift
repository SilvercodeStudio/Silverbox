import Foundation

/// What installing a game means in eXoDOS: unzip `eXo/eXoDOS/<name>.zip`
/// into `eXo/eXoDOS/`, then apply `eXo/Update/!dos/<name>.zip` if present.
nonisolated public struct InstallPlan: Sendable, Hashable {
    public var game: Game
    public var archiveURL: URL
    public var destinationDirectory: URL
    public var installedFolderURL: URL
    public var updateArchiveURL: URL?

    public var archiveExists: Bool { FileManager.default.fileExists(atPath: archiveURL.path) }
    public var isInstalled: Bool { FileManager.default.fileExists(atPath: installedFolderURL.path) }

    public var archiveSize: Int64? {
        (try? FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? Int64) ?? nil
    }
}

nonisolated public enum InstallError: Error, Sendable, Equatable {
    case notADOSGame
    case archiveMissing(URL)
    case extractionFailed(status: Int32, output: String)
    case folderMissingAfterExtract(URL)
    case notInstalled
}

nonisolated extension InstallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notADOSGame: return "This item is not a DOS game."
        case .archiveMissing(let url): return "The game archive is not present: \(url.lastPathComponent). This copy of eXoDOS may be the Lite edition; downloading is not supported yet."
        case .extractionFailed(let status, let output): return "Unzip failed (exit code \(status)). \(output)"
        case .folderMissingAfterExtract(let url): return "The archive did not create the expected folder \(url.lastPathComponent)."
        case .notInstalled: return "The game is not installed."
        }
    }
}

nonisolated public protocol ArchiveExtractor: Sendable {
    /// Extracts `archive` into `directory`, overwriting existing files.
    func extract(archive: URL, into directory: URL) async throws
}

/// Extracts with the system `unzip` command.
nonisolated public struct UnzipCommandExtractor: ArchiveExtractor {
    public var executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/unzip")) {
        self.executableURL = executableURL
    }

    public func extract(archive: URL, into directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try await CommandRunner.run(executable: executableURL,
                                                 arguments: ["-o", "-q", archive.path, "-d", directory.path],
                                                 workingDirectory: directory)
        // unzip returns 1 for warnings (for example, mismatched timestamps) and still extracts.
        guard result.status == 0 || result.status == 1 else {
            throw InstallError.extractionFailed(status: result.status, output: result.output)
        }
    }
}

nonisolated public struct CommandResult: Sendable, Hashable {
    public var status: Int32
    public var output: String
}

/// Runs a command to completion and collects its output.
nonisolated public enum CommandRunner {
    public static func run(executable: URL, arguments: [String], workingDirectory: URL? = nil) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let workingDirectory { process.currentDirectoryURL = workingDirectory }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(status: finished.terminationStatus, output: output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

nonisolated public struct GameInstaller: Sendable {
    public let snapshot: LibrarySnapshot

    public init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
    }

    public func plan(for game: Game) -> InstallPlan? {
        guard game.isDOSGame, let folderName = game.gameFolderName else { return nil }
        let root = snapshot.root
        let archive = root.gamesDirectory.appendingPathComponent("\(game.launcherBaseName).zip")
        let update = root.updateDirectory.appendingPathComponent("!dos", isDirectory: true)
            .appendingPathComponent("\(game.launcherBaseName).zip")
        return InstallPlan(
            game: game,
            archiveURL: archive,
            destinationDirectory: root.gamesDirectory,
            installedFolderURL: root.gamesDirectory.appendingPathComponent(folderName, isDirectory: true),
            updateArchiveURL: FileManager.default.fileExists(atPath: update.path) ? update : nil
        )
    }

    public func install(_ plan: InstallPlan, extractor: any ArchiveExtractor = UnzipCommandExtractor()) async throws {
        guard plan.archiveExists else { throw InstallError.archiveMissing(plan.archiveURL) }
        try await extractor.extract(archive: plan.archiveURL, into: plan.destinationDirectory)
        if let update = plan.updateArchiveURL {
            try await extractor.extract(archive: update, into: plan.destinationDirectory)
        }
        guard plan.isInstalled else { throw InstallError.folderMissingAfterExtract(plan.installedFolderURL) }
    }

    public func uninstall(_ plan: InstallPlan) throws {
        guard plan.isInstalled else { throw InstallError.notInstalled }
        try FileManager.default.removeItem(at: plan.installedFolderURL)
    }
}
