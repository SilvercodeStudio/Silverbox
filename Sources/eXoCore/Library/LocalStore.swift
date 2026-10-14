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
    public var gamesDirectory: URL { gamesRoot.appendingPathComponent(EXoPack.dos.directoryName, isDirectory: true) }
    /// Writable copies of library files, mirroring `eXo/`: eXoDOS overlay
    /// folders, Windows 98 differencing disks and game disks.
    public var overlayRoot: URL { directory.appendingPathComponent("Overlay", isDirectory: true) }
    /// Writable overlays for eXoDOS games that are unpacked on a read-only library.
    public var overlayDirectory: URL {
        overlayRoot.appendingPathComponent(EXoPack.dos.directoryName, isDirectory: true)
    }
    /// Save backups made when a game is uninstalled, like eXoDOS's `!save`.
    public var savesDirectory: URL { directory.appendingPathComponent("Saves", isDirectory: true) }
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
