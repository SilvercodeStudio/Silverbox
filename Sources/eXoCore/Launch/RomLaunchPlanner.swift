import Foundation

/// A command line ready to start an emulator for a game. DOSBox launches
/// come from ``LaunchPlan``; ROM and disc launches from ``RomLaunchPlanner``.
nonisolated public struct EmulatorLaunch: Sendable, Hashable {
    public var game: Game
    public var emulator: EmulatorInstallation
    public var arguments: [String]
    public var workingDirectory: URL
    public var notes: [String]

    public init(
        game: Game, emulator: EmulatorInstallation, arguments: [String], workingDirectory: URL, notes: [String] = []
    ) {
        self.game = game
        self.emulator = emulator
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.notes = notes
    }

    /// A shell-style rendering for display and logs.
    public var commandLine: String {
        ([emulator.executableURL.path] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}

nonisolated extension LaunchPlan {
    public var launch: EmulatorLaunch {
        EmulatorLaunch(
            game: game, emulator: emulator, arguments: arguments, workingDirectory: workingDirectory, notes: notes)
    }
}

nonisolated public enum RomLaunchError: Error, Sendable, Equatable {
    case notAnEmulatedGame
    case noEmulator(String)
    case emulatorMissing(EmulatorKind)
    case coreMissing(String)
    case fileMissing(URL)
    case unsupportedFile(String, EmulatorKind)
}

nonisolated extension RomLaunchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAnEmulatedGame: return "This item is not a game for an emulator."
        case .noEmulator(let problem): return problem
        case .emulatorMissing(let kind): return "\(kind.displayName) was not found. Choose it in Settings › Emulators."
        case .coreMissing(let core): return "The RetroArch core \(core) is not installed."
        case .fileMissing(let url): return "The game file is not present: \(url.path)"
        case .unsupportedFile(let ext, let kind):
            return "\(kind.displayName) cannot open .\(ext) files. Unpack the game first."
        }
    }
}

/// Builds the command line that starts a console, computer or arcade game.
nonisolated public struct RomLaunchPlanner: Sendable {
    public let snapshot: LibrarySnapshot

    public init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
    }

    /// The ROM, disc image or folder the LaunchBox record points at.
    public func fileURL(for game: Game) -> URL {
        snapshot.root.url(forWindowsRelativePath: game.applicationPath)
    }

    public func plan(
        game: Game, resolved: ResolvedEmulatorAssignment, emulator: EmulatorInstallation,
        retroArch: RetroArchSetup?, options: LaunchOptions
    ) throws -> EmulatorLaunch {
        guard game.launchKind == .emulator else { throw RomLaunchError.notAnEmulatedGame }
        guard let assignment = resolved.assignment, resolved.problem == nil else {
            throw RomLaunchError.noEmulator(resolved.problem ?? "No emulator is assigned to \(game.platform).")
        }
        guard emulator.kind == assignment.emulator else { throw RomLaunchError.emulatorMissing(assignment.emulator) }
        guard emulator.exists else { throw RomLaunchError.emulatorMissing(emulator.kind) }

        let file = fileURL(for: game)
        guard FileManager.default.fileExists(atPath: file.path) else { throw RomLaunchError.fileMissing(file) }
        let ext = file.pathExtension.lowercased()
        if Self.unsupportedExtensions(for: emulator.kind).contains(ext) {
            throw RomLaunchError.unsupportedFile(ext, emulator.kind)
        }

        var notes = resolved.notes
        var extra = CommandLineTokenizer.tokenize(assignment.arguments)
        var gameArguments = CommandLineTokenizer.tokenize(game.commandLine ?? "")
        var arguments: [String] = []

        switch emulator.kind {
        case .retroArch:
            var coreName = assignment.core ?? ""
            // A game-level `-L` in LaunchBox picks another core for that game.
            if let index = gameArguments.firstIndex(where: { $0 == "-L" }), index + 1 < gameArguments.count {
                coreName = gameArguments[index + 1]
                gameArguments.removeSubrange(index...(index + 1))
            }
            gameArguments.removeAll { $0 == "-f" }
            guard let retroArch, let core = retroArch.resolveCore(named: coreName) else {
                throw RomLaunchError.coreMissing(RetroArchSetup.coreName(from: coreName))
            }
            arguments = ["-L", core.url.path]
            if options.fullscreen { arguments.append("-f") }
            arguments += extra + gameArguments + [file.path]
        case .dolphin:
            arguments = ["-b", "-e", file.path]
            if options.fullscreen { arguments.append("--config=Dolphin.Display.Fullscreen=True") }
            arguments += extra + gameArguments
        case .mame:
            extra.removeAll { $0.lowercased() == "-skip_gameinfo" }
            arguments = [
                file.deletingPathExtension().lastPathComponent, "-rompath", file.deletingLastPathComponent().path,
                "-skip_gameinfo",
            ]
            if !options.fullscreen { arguments.append("-window") }
            arguments += extra + gameArguments
        case .mednafen:
            arguments = ["-video.fs", options.fullscreen ? "1" : "0"] + extra + gameArguments + [file.path]
        case .dosboxStaging, .dosboxX, .box86, .scummVM, .scummVMDaily, .spatterlight:
            throw RomLaunchError.notAnEmulatedGame
        }

        if ["zip", "7z"].contains(ext), emulator.kind == .retroArch {
            notes.append(
                "The game is an archive; RetroArch unpacks it to its cache folder when the core needs the plain file.")
        }
        return EmulatorLaunch(
            game: game, emulator: emulator, arguments: arguments,
            workingDirectory: file.deletingLastPathComponent(), notes: notes)
    }

    /// File types an emulator cannot open directly.
    public static func unsupportedExtensions(for kind: EmulatorKind) -> Set<String> {
        switch kind {
        case .retroArch, .mame, .mednafen: return ["rar"]
        case .dolphin: return ["rar", "zip", "7z"]
        case .dosboxStaging, .dosboxX, .box86, .scummVM, .scummVMDaily, .spatterlight: return []
        }
    }
}
