import Foundation

/// An eXo project whose games unpack from zips under `eXo/<pack>/` and start
/// from a per-game folder of launchers and configs.
///
/// eXoDOS keeps a game's configs in `eXo/eXoDOS/!dos/<folder>` and unpacks it
/// to `eXo/eXoDOS/<folder>`. eXoWin9x adds a year: configs in
/// `eXo/eXoWin9x/!win9x/<year>/<folder>`, the game in
/// `eXo/eXoWin9x/<year>/<folder>`, its zip beside that folder.
nonisolated public enum EXoPack: String, CaseIterable, Sendable, Codable, Hashable {
    case dos = "eXoDOS"
    case win9x = "eXoWin9x"

    /// The folder under `eXo/` that holds the archives and unpacked games.
    public var directoryName: String { rawValue }

    /// The folder under ``directoryName`` that holds the per-game configs.
    public var configFolderName: String {
        switch self {
        case .dos: return "!dos"
        case .win9x: return "!win9x"
        }
    }

    /// How many folder levels below ``directoryName`` an unpacked game sits:
    /// `<folder>` for eXoDOS, `<year>/<folder>` for eXoWin9x.
    public var installDepth: Int {
        switch self {
        case .dos: return 1
        case .win9x: return 2
        }
    }

    public var displayName: String { rawValue }
}

nonisolated extension Game {
    /// The eXo project the game belongs to, when it is one that installs
    /// from an archive.
    public var eXoPack: EXoPack? {
        if isDOSGame { return .dos }
        guard applicationPath.lowercased().hasSuffix(".bat"), configSubpath(for: .win9x) != nil else { return nil }
        return .win9x
    }

    /// True for games that install from an eXo archive and can be uninstalled.
    public var isEXoGame: Bool { eXoPack != nil }

    /// The unpacked game folder relative to `eXo/`, as path components: for
    /// example `["eXoDOS", "ultima5"]` or `["eXoWin9x", "1996", "A-10 Cuba (1996)"]`.
    public var installPathComponents: [String]? {
        switch eXoPack {
        case .dos:
            return gameFolderName.map { [EXoPack.dos.directoryName, $0] }
        case .win9x:
            return configSubpath(for: .win9x).map { [EXoPack.win9x.directoryName] + $0 }
        case nil:
            return nil
        }
    }

    /// ``installPathComponents`` joined with `/`, the key that installed-game
    /// sets use.
    public var installPath: String? {
        installPathComponents?.joined(separator: "/")
    }

    /// The components of `RootFolder` after `<pack>\<config folder>`, when
    /// they match the pack's install depth.
    private func configSubpath(for pack: EXoPack) -> [String]? {
        guard let rootFolder else { return nil }
        let parts = WindowsPath.components(of: rootFolder)
        guard
            let start = parts.indices.dropLast().first(where: {
                parts[$0].caseInsensitiveCompare(pack.directoryName) == .orderedSame
                    && parts[$0 + 1].caseInsensitiveCompare(pack.configFolderName) == .orderedSame
            })
        else { return nil }
        let rest = Array(parts[(start + 2)...])
        return rest.count == pack.installDepth ? rest : nil
    }
}
