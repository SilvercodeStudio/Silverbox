import Foundation

/// The writable folder that pairs with a (possibly read-only) eXoDOS library:
/// unpacked games, save backups, config overrides and overlay folders live
/// here, so the library itself is never changed.
nonisolated public struct LocalStore: Hashable, Sendable, Codable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    /// Unpacked games of every eXo project. Mirrors `eXo/`, so a game's
    /// ``Game/installPath`` is the same here as in the library.
    public var gamesRoot: URL { directory.appendingPathComponent("Games", isDirectory: true) }
    /// Unpacked eXoDOS games. Mirrors `eXo/eXoDOS/` so mount paths look the same.
    public var gamesDirectory: URL { gamesDirectory(for: .dos) }
    /// Unpacked games of one pack, mirroring `eXo/<pack>/`.
    public func gamesDirectory(for pack: EXoPack) -> URL {
        gamesRoot.appendingPathComponent(pack.directoryName, isDirectory: true)
    }
    /// Writable copies of library files, mirroring `eXo/`: eXoDOS overlay
    /// folders, Windows 98 differencing disks and game disks.
    public var overlayRoot: URL { directory.appendingPathComponent("Overlay", isDirectory: true) }
    /// Writable overlays for eXoDOS games that are unpacked on a read-only library.
    public var overlayDirectory: URL { overlayDirectory(for: .dos) }
    /// Writable overlays for one pack's games unpacked on a read-only library.
    public func overlayDirectory(for pack: EXoPack) -> URL {
        overlayRoot.appendingPathComponent(pack.directoryName, isDirectory: true)
    }
    /// Save backups made when a game is uninstalled, like eXoDOS's `!save`.
    public var savesDirectory: URL { directory.appendingPathComponent("Saves", isDirectory: true) }
    /// ScummVM's settings file for eXoScummVM games, kept apart from the
    /// user's own ScummVM settings.
    public var scummVMConfigURL: URL {
        directory.appendingPathComponent("ScummVM", isDirectory: true).appendingPathComponent("scummvm.ini")
    }
    /// ScummVM saves, shared by all collections as in eXo.
    public var scummVMSavesDirectory: URL { savesDirectory.appendingPathComponent("ScummVM", isDirectory: true) }
    /// MAME's settings and memory for eXoAppleIIGS games, copied from eXo's
    /// MAME once, and in `roms` the ROM files the user adds.
    public var mameDirectory: URL { directory.appendingPathComponent("MAME", isDirectory: true) }
    /// Per-game edited copies of DOSBox configs.
    public var overridesDirectory: URL { directory.appendingPathComponent("Overrides", isDirectory: true) }
    /// Soundtrack albums unpacked from the library's zips.
    public var soundtracksDirectory: URL { directory.appendingPathComponent("Soundtracks", isDirectory: true) }

    public func ensureDirectories() throws {
        for url in [gamesDirectory, overlayDirectory, savesDirectory, overridesDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// eXoDOS backups sit directly in `Saves/`; other projects have a folder each.
    public func saveArchiveURL(for game: Game) -> URL {
        let folder =
            game.eXoPack.map { $0 == .dos ? savesDirectory : savesDirectory.appendingPathComponent($0.directoryName) }
            ?? savesDirectory
        return folder.appendingPathComponent("\(game.launcherBaseName).zip")
    }

    /// New backups follow the physical installation, so two in-place copies
    /// cannot overwrite each other's progress. Legacy backups remain restore sources.
    public func saveArchiveURL(for game: Game, installation: URL) -> URL {
        let root = FileOperations.identity(of: gamesRoot) + "/"
        let path = FileOperations.identity(of: installation)
        // Moving the entire local data folder must not orphan its backups.
        let identity = path.hasPrefix(root) ? "local/" + path.dropFirst(root.count) : path
        return savesDirectory.appendingPathComponent("Installations", isDirectory: true)
            .appendingPathComponent(FileOperations.storageKey(forIdentity: identity), isDirectory: true)
            .appendingPathComponent("\(game.launcherBaseName).zip")
    }

    /// The game's backup for another installation, when there is exactly one.
    /// A collection reached by another path (a volume mounted under a new
    /// name) gets new keys, and this finds its backups again. With two or
    /// more, none is chosen, so one copy's progress never goes to another.
    public func soleSaveArchiveOfAnotherInstallation(for game: Game) -> URL? {
        let fm = FileManager.default
        let folder = savesDirectory.appendingPathComponent("Installations", isDirectory: true)
        let matches = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .map {
                folder.appendingPathComponent($0, isDirectory: true).appendingPathComponent(
                    "\(game.launcherBaseName).zip")
            }
            .filter { fm.fileExists(atPath: $0.path) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// The edited config a user keeps for a game, if any.
    public func overrideConfigURL(for game: Game, configName: String) -> URL {
        overridesDirectory.appendingPathComponent(game.launchBoxID, isDirectory: true).appendingPathComponent(
            configName)
    }
}

/// Where new installations go.
nonisolated public enum InstallLocation: String, Codable, Sendable, CaseIterable, Identifiable {
    case localStore
    case inPlace

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localStore: return "Local data folder (recommended)"
        case .inPlace: return "Inside the eXoDOS folder, as on Windows"
        }
    }
}

/// Where an installed game's folder was found.
nonisolated public enum GameLocation: Hashable, Sendable {
    case local(URL)
    case library(URL)

    public var url: URL {
        switch self {
        case .local(let url), .library(let url): return url
        }
    }

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}
