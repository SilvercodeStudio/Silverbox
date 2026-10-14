import Foundation

/// Everything needed to start an emulator for one game.
nonisolated public struct LaunchPlan: Sendable, Hashable {
    public var game: Game
    public var variant: LaunchVariant?
    public var emulator: EmulatorInstallation
    public var arguments: [String]
    public var workingDirectory: URL
    public var configURL: URL
    public var configText: String
    public var sourceConfigURL: URL
    public var notes: [String]
    /// Folders to create before launch (writable overlays).
    public var directoriesToCreate: [URL]
    /// Files copied before the first launch (game disks from a read-only library).
    public var fileCopies: [FileCopy]
    /// Differencing disks made fresh before each launch.
    public var differencingDisks: [DifferencingDisk]

    public init(
        game: Game, variant: LaunchVariant?, emulator: EmulatorInstallation, arguments: [String],
        workingDirectory: URL, configURL: URL, configText: String, sourceConfigURL: URL, notes: [String],
        directoriesToCreate: [URL] = [], fileCopies: [FileCopy] = [], differencingDisks: [DifferencingDisk] = []
    ) {
        self.game = game
        self.variant = variant
        self.emulator = emulator
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.configURL = configURL
        self.configText = configText
        self.sourceConfigURL = sourceConfigURL
        self.notes = notes
        self.directoriesToCreate = directoriesToCreate
        self.fileCopies = fileCopies
        self.differencingDisks = differencingDisks
    }

    /// Writes the generated config where the arguments point, creates any
    /// overlay folders the config mounts, makes missing file copies and
    /// fresh differencing disks.
    public func writeConfig() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for directory in directoriesToCreate {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for copy in fileCopies where !fm.fileExists(atPath: copy.destination.path) {
            try fm.createDirectory(at: copy.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: copy.source, to: copy.destination)
        }
        for disk in differencingDisks {
            try VHDDifferencingDisk.create(at: disk.child, parent: disk.parent)
        }
        try configText.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// A shell-style rendering for display and debugging.
    public var commandLine: String {
        ([emulator.executableURL.path] + arguments).map { Self.quote($0) }.joined(separator: " ")
    }

    private static func quote(_ argument: String) -> String {
        argument.contains(" ") ? "\"\(argument)\"" : argument
    }
}

nonisolated public enum LaunchPlanError: Error, Sendable, Equatable {
    case notADOSGame
    case missingGameFolder
    case notInstalled(folderName: String)
    case missingConfig(URL)
    case emulatorMissing(EmulatorKind)
    case notADOSBoxEmulator(EmulatorKind)
    case needsDOSBoxX
    case needs86Box
    case needsScummVM
    case scummVMNotInIndex(String)
}

nonisolated extension LaunchPlanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notADOSGame: return "This item is not a DOS game and cannot be launched in DOSBox."
        case .missingGameFolder: return "The game record has no root folder."
        case .notInstalled(let folder):
            return "The game is not installed: folder \(folder) is missing under eXo."
        case .missingConfig(let url): return "The DOSBox config is missing: \(url.path)"
        case .emulatorMissing(let kind): return "\(kind.displayName) was not found. Set its location in Settings."
        case .notADOSBoxEmulator(let kind):
            return "\(kind.displayName) cannot run DOS games; choose DOSBox Staging or DOSBox-X."
        case .needsDOSBoxX:
            return "eXoWin9x games run Windows 98 in DOSBox-X. Choose DOSBox-X for this game."
        case .needs86Box:
            return "This eXoWin9x game runs in 86Box. Set the 86Box location in Settings › Emulators."
        case .needsScummVM:
            return "eXoScummVM games run in ScummVM. Set the ScummVM location in Settings › Emulators."
        case .scummVMNotInIndex(let name):
            return "eXo's ScummVM index (eXo/util/scummvm.txt) has no entry for \(name)."
        }
    }
}

/// Builds ``LaunchPlan`` values from a library snapshot.
nonisolated public struct LaunchPlanner: Sendable {
    public let snapshot: LibrarySnapshot
    /// Where generated config files are written.
    public let scratchDirectory: URL

    public init(snapshot: LibrarySnapshot, scratchDirectory: URL) {
        self.snapshot = snapshot
        self.scratchDirectory = scratchDirectory
    }

    public var localStore: LocalStore? { snapshot.localStore }

    /// True when the library's eXoDOS folder cannot be written, so games
    /// unpacked there need an overlay for their saves.
    public var libraryIsReadOnly: Bool { libraryIsReadOnly(for: .dos) }

    /// True when the pack's folder in the library cannot be written.
    public func libraryIsReadOnly(for pack: EXoPack) -> Bool {
        !FileManager.default.isWritableFile(atPath: snapshot.root.gamesDirectory(for: pack).path)
    }

    /// The `!dos/<game>` folder that holds the launcher, configs and extras.
    public func configFolder(for game: Game) -> URL? {
        guard let rootFolder = game.rootFolder, !rootFolder.isEmpty else { return nil }
        return snapshot.root.url(forWindowsRelativePath: rootFolder)
    }

    /// The folder the game is unpacked in, wherever that is.
    public func installedFolder(for game: Game) -> URL? {
        snapshot.installedLocation(for: game)?.url
    }

    /// The config the user edited for this variant, if they kept one.
    public func overrideConfigURL(for game: Game, variant: LaunchVariant?) -> URL? {
        guard let localStore else { return nil }
        let name = variant?.configURL.lastPathComponent ?? "dosbox.conf"
        let url = localStore.overrideConfigURL(for: game, configName: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func variants(for game: Game) -> [LaunchVariant] {
        if game.launchKind == .scummVM { return scummVMVariants(for: game) }
        guard game.isDOSGame, let folder = configFolder(for: game) else { return [] }
        return LaunchVariantDetector.variants(inGameConfigFolder: folder)
    }

    public func eXoDOSBuild(for game: Game) -> EXoDOSBuild? {
        snapshot.dosboxBuild(for: game)
    }

    public func recommendedEmulator(for game: Game) -> EmulatorKind {
        if game.eXoPack == .win9x { return .dosboxX }
        if game.launchKind == .scummVM { return .scummVM }
        return eXoDOSBuild(for: game)?.recommendedEmulator ?? .dosboxStaging
    }

    public func plan(
        game: Game, variant: LaunchVariant?, emulator: EmulatorInstallation, options: LaunchOptions,
        choices: LaunchChoices = LaunchChoices()
    ) throws -> LaunchPlan {
        if game.eXoPack == .win9x { return try planWindows9x(game: game, emulator: emulator, options: options) }
        if game.launchKind == .scummVM {
            return try planScummVM(game: game, variant: variant, emulator: emulator, options: options, choices: choices)
        }
        guard game.isDOSGame, let pack = game.eXoPack else { throw LaunchPlanError.notADOSGame }
        guard let folderName = game.gameFolderName, let configFolder = configFolder(for: game) else {
            throw LaunchPlanError.missingGameFolder
        }
        guard let location = snapshot.installedLocation(for: game) else {
            throw LaunchPlanError.notInstalled(folderName: folderName)
        }
        guard emulator.kind.isDOSBox else { throw LaunchPlanError.notADOSBoxEmulator(emulator.kind) }
        guard emulator.exists else { throw LaunchPlanError.emulatorMissing(emulator.kind) }

        let sourceURL =
            overrideConfigURL(for: game, variant: variant)
            ?? variant?.configURL
            ?? configFolder.appendingPathComponent("dosbox.conf")
        guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
            throw LaunchPlanError.missingConfig(sourceURL)
        }
        let sourceText = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let source = DOSBoxConfigDocument.parse(sourceText)

        // Games unpacked in the local store: point `eXo/<pack>` paths there.
        // Games unpacked on a read-only library: overlay a local folder so
        // saves and settings can be written.
        var mappings: [PathMapping] = []
        var overlay: OverlayMount?
        switch location {
        case .local:
            if let localStore {
                mappings.append(
                    PathMapping(
                        from: snapshot.root.gamesDirectory(for: pack), to: localStore.gamesDirectory(for: pack)))
            }
        case .library:
            if let localStore, libraryIsReadOnly(for: pack) {
                overlay = OverlayMount(
                    base: snapshot.root.gamesDirectory(for: pack), directory: localStore.overlayDirectory(for: pack))
            }
        }
        let fallbacks: [URL] = [location.url, configFolder]
        let translator = ConfigTranslator(
            root: snapshot.root, emulator: emulator.kind, options: options,
            fluidSynthAvailable: EmulatorCapabilities.fluidSynthAvailable(for: emulator),
            fallbackDirectories: fallbacks, pathMappings: mappings, overlay: overlay)
        var translation = translator.translate(source)
        if overlay != nil {
            translation.notes.append(
                "The library is read-only; saves are written to \(localStore?.overlayDirectory(for: pack).path ?? "the local overlay folder")."
            )
        }

        if let build = eXoDOSBuild(for: game), build.recommendedEmulator != emulator.kind {
            translation.notes.insert(
                "\(pack.displayName) runs this game with \(build.displayName); \(build.recommendedEmulator.displayName) is the closer match on the Mac.",
                at: 0)
        }

        let variantSuffix = variant.map { "-" + $0.configURL.deletingPathExtension().lastPathComponent } ?? ""
        let configURL =
            scratchDirectory
            .appendingPathComponent(
                "\(Self.safeFileName(game.launchBoxID))\(variantSuffix)-\(emulator.kind.rawValue).conf")
        let workingDirectory = snapshot.root.eXoDirectory

        let arguments: [String]
        switch emulator.kind {
        case .dosboxStaging:
            arguments = [
                "--noprimaryconf", "--nolocalconf", "--working-dir", workingDirectory.path, "--conf", configURL.path,
            ]
        case .dosboxX:
            arguments = ["-defaultdir", workingDirectory.path, "-conf", configURL.path, "-fastlaunch"]
        case .retroArch, .dolphin, .mame, .mednafen, .box86, .scummVM, .scummVMDaily:
            throw LaunchPlanError.notADOSBoxEmulator(emulator.kind)
        }

        return LaunchPlan(
            game: game,
            variant: variant,
            emulator: emulator,
            arguments: arguments,
            workingDirectory: workingDirectory,
            configURL: configURL,
            configText: translation.document.serialized(),
            sourceConfigURL: sourceURL,
            notes: translation.notes,
            directoriesToCreate: translation.overlayFolders
        )
    }

    public static func safeFileName(_ value: String) -> String {
        String(value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }
}
