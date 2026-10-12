import Foundation

/// The writable folder that pairs with a (possibly read-only) eXoDOS library:
/// unpacked games, save backups, config overrides and overlay folders live
/// here, so the library itself is never changed.
nonisolated public struct LocalStore: Hashable, Sendable, Codable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    /// Unpacked games. Mirrors `eXo/eXoDOS/` so mount paths look the same.
    public var gamesDirectory: URL { directory.appendingPathComponent("Games/eXoDOS", isDirectory: true) }
    /// Writable overlays for games that are unpacked on a read-only library.
    public var overlayDirectory: URL { directory.appendingPathComponent("Overlay/eXoDOS", isDirectory: true) }
    /// Save backups made when a game is uninstalled, like eXoDOS's `!save`.
    public var savesDirectory: URL { directory.appendingPathComponent("Saves", isDirectory: true) }
    /// Per-game edited copies of DOSBox configs.
    public var overridesDirectory: URL { directory.appendingPathComponent("Overrides", isDirectory: true) }

    public func ensureDirectories() throws {
        for url in [gamesDirectory, overlayDirectory, savesDirectory, overridesDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func saveArchiveURL(for game: Game) -> URL {
        savesDirectory.appendingPathComponent("\(game.launcherBaseName).zip")
    }

    /// The edited config a user keeps for a game, if any.
    public func overrideConfigURL(for game: Game, configName: String) -> URL {
        overridesDirectory.appendingPathComponent(game.launchBoxID, isDirectory: true).appendingPathComponent(configName)
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
