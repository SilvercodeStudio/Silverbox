import Foundation

/// A command line ready to start an emulator for a game. DOSBox launches
/// come from ``LaunchPlan``; ROM and disc launches from ``RomLaunchPlanner``.
nonisolated public struct EmulatorLaunch: Sendable, Hashable {
    public var game: Game
    public var emulator: EmulatorInstallation
    public var arguments: [String]
    public var workingDirectory: URL
    public var notes: [String]
    /// The config the emulator reads, for the launch report; ROM launches have none.
    public var configURL: URL?
    /// Files to copy before the start when they are not there yet: BIOS
    /// files from the library's RetroArch into RetroArch's system folder.
    public var fileCopies: [FileCopy]

    public init(
        game: Game, emulator: EmulatorInstallation, arguments: [String], workingDirectory: URL, notes: [String] = [],
        configURL: URL? = nil, fileCopies: [FileCopy] = []
    ) {
        self.game = game
        self.emulator = emulator
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.notes = notes
        self.configURL = configURL
        self.fileCopies = fileCopies
    }

    /// Makes the copies in ``fileCopies`` that are missing. Never replaces a file.
    public func copyFiles() throws {
        let fm = FileManager.default
        for copy in fileCopies where !fm.fileExists(atPath: copy.destination.path) {
            try fm.createDirectory(at: copy.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: copy.source, to: copy.destination)
        }
    }

    /// A shell-style rendering for display and logs.
    public var commandLine: String {
        ([emulator.executableURL.path] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}

nonisolated extension LaunchPlan {
    public var launch: EmulatorLaunch {
        EmulatorLaunch(
            game: game, emulator: emulator, arguments: arguments, workingDirectory: workingDirectory, notes: notes,
            configURL: configURL)
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

/// The BIOS files a RetroArch core lacks in RetroArch's system folder.
nonisolated public struct RetroArchFirmwareCheck: Sendable, Hashable {
    /// Files found in the library's own RetroArch, to copy into RetroArch's
    /// system folder.
    public var copies: [FileCopy] = []
    /// Files the core needs that are in neither place.
    public var missing: [RetroArchFirmware] = []

    public init(copies: [FileCopy] = [], missing: [RetroArchFirmware] = []) {
        self.copies = copies
        self.missing = missing
    }

    /// Why the core may not start, or nil when nothing it needs is missing.
    public func problem(core: String, systemDirectory: URL?) -> String? {
        guard !missing.isEmpty else { return nil }
        let files = missing.map(\.description).joined(separator: ", ")
        let folder = systemDirectory.map { " (\($0.path))" } ?? ""
        return
            "RetroArch's \(core) core needs \(files) in RetroArch's system folder\(folder). Silverbox found it neither there nor in the library's RetroArch."
    }
}

/// Builds the command line that starts a console, computer or arcade game.
nonisolated public struct RomLaunchPlanner: Sendable {
    public let snapshot: LibrarySnapshot

    public init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
    }

    /// The system folder of the library's own RetroArch, which holds the
    /// BIOS files LaunchBox uses on Windows: `system_directory` in its
    /// `retroarch.cfg`, else `system` beside `retroarch.exe`.
    public var libraryRetroArchSystemDirectory: URL? {
        let fm = FileManager.default
        func isFolder(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        for emulator in snapshot.emulators where emulator.macKind == .retroArch {
            let folder = snapshot.root.url(forWindowsRelativePath: emulator.applicationPath).deletingLastPathComponent()
            var candidates: [URL] = []
            let config = RetroArchSetup.parseConfig(at: folder.appendingPathComponent("retroarch.cfg"))
            if let value = config["system_directory"], !value.isEmpty, value != "default" {
                // `:` is RetroArch's own folder.
                candidates.append(
                    value.hasPrefix(":")
                        ? WindowsPath.resolve(String(value.dropFirst()), against: folder)
                        : snapshot.root.url(forWindowsRelativePath: value))
            }
            candidates.append(folder.appendingPathComponent("system", isDirectory: true))
            if let found = candidates.first(where: isFolder) { return found }
        }
        return nil
    }

    /// The BIOS files `core` lists that RetroArch's system folder lacks:
    /// those to copy from the library's RetroArch, and the required ones
    /// found nowhere.
    public func firmwareCheck(core: String, retroArch: RetroArchSetup) -> RetroArchFirmwareCheck {
        var check = RetroArchFirmwareCheck()
        let absent = retroArch.firmware(forCore: core).filter { retroArch.systemFile($0.path) == nil }
        guard !absent.isEmpty else { return check }
        let library = libraryRetroArchSystemDirectory
        for item in absent {
            if let library, let systemDirectory = retroArch.systemDirectory,
                let source = RetroArchSetup.file(item.path, in: library)
            {
                check.copies.append(
                    FileCopy(source: source, destination: systemDirectory.appendingPathComponent(item.path)))
            } else if !item.isOptional {
                check.missing.append(item)
            }
        }
        return check
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
        var fileCopies: [FileCopy] = []

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
            // --verbose sends RetroArch's and the core's messages, such as a
            // missing BIOS, to the launch log.
            arguments = ["--verbose", "-L", core.url.path]
            if options.fullscreen { arguments.append("-f") }
            arguments += extra + gameArguments + [file.path]
            let firmware = firmwareCheck(core: core.name, retroArch: retroArch)
            fileCopies = firmware.copies
            if !firmware.copies.isEmpty {
                let names = firmware.copies.map(\.destination.lastPathComponent).joined(separator: ", ")
                notes.append("Copies \(names) from the library's RetroArch into RetroArch's system folder.")
            }
            if let problem = firmware.problem(core: core.name, systemDirectory: retroArch.systemDirectory) {
                notes.append(problem)
            }
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
        case .dosboxStaging, .dosboxX, .box86, .scummVM, .scummVMDaily, .spatterlight, .gsplus:
            throw RomLaunchError.notAnEmulatedGame
        }

        if ["zip", "7z"].contains(ext), emulator.kind == .retroArch {
            notes.append(
                "The game is an archive; RetroArch unpacks it to its cache folder when the core needs the plain file.")
        }
        return EmulatorLaunch(
            game: game, emulator: emulator, arguments: arguments,
            workingDirectory: file.deletingLastPathComponent(), notes: notes, fileCopies: fileCopies)
    }

    /// File types an emulator cannot open directly.
    public static func unsupportedExtensions(for kind: EmulatorKind) -> Set<String> {
        switch kind {
        case .retroArch, .mame, .mednafen: return ["rar"]
        case .dolphin: return ["rar", "zip", "7z"]
        case .dosboxStaging, .dosboxX, .box86, .scummVM, .scummVMDaily, .spatterlight, .gsplus: return []
        }
    }
}
