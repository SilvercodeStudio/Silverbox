import Foundation

/// An eXo project whose games unpack from zips under `eXo/<pack>/` and start
/// from a per-game folder of launchers and configs.
///
/// eXoDOS keeps a game's configs in `eXo/eXoDOS/!dos/<folder>` and unpacks it
/// to `eXo/eXoDOS/<folder>`. eXoWin9x adds a year: configs in
/// `eXo/eXoWin9x/!win9x/<year>/<folder>`, the game in
/// `eXo/eXoWin9x/<year>/<folder>`, its zip beside that folder. The other
/// packs have the eXoDOS shape under their own folder names; eXoWin3x is an
/// eXoDOS-style pack whose games boot their own Windows 3.1 in DOSBox.
nonisolated public enum EXoPack: String, CaseIterable, Sendable, Codable, Hashable {
    case dos = "eXoDOS"
    case win3x = "eXoWin3x"
    case win9x = "eXoWin9x"
    case demoScene = "eXoDemoScene"
    case scummVM = "eXoScummVM"
    case appleIIGS = "eXoAppleIIGS"
    case interactiveFiction = "eXoIF"

    /// The folder under `eXo/` that holds the archives and unpacked games.
    public var directoryName: String {
        switch self {
        case .demoScene: return "eXoDemoScn"
        default: return rawValue
        }
    }

    /// The folder under ``directoryName`` that holds the per-game configs.
    public var configFolderName: String {
        switch self {
        case .dos: return "!dos"
        case .win3x: return "!win3x"
        case .win9x: return "!win9x"
        case .demoScene: return "!demoscn"
        case .scummVM: return "!ScummVM"
        case .appleIIGS: return "!appleiigs"
        case .interactiveFiction: return "!IF"
        }
    }

    /// The name in the download's `Content/!<name>metadata.zip`.
    public var archiveName: String {
        switch self {
        case .dos: return "DOS"
        case .win3x: return "Win3X"
        case .win9x: return "Win9X"
        case .demoScene: return "DemoScene"
        case .scummVM: return "ScummVM"
        case .appleIIGS: return "AppleIIGS"
        case .interactiveFiction: return "IF"
        }
    }

    /// `Content/!<name>metadata.zip`, relative to the download.
    public var configArchivePath: String { "Content/!\(archiveName)metadata.zip" }

    /// How many folder levels below ``directoryName`` an unpacked game sits:
    /// `<folder>` for most packs, `<year>/<folder>` for eXoWin9x.
    public var installDepth: Int {
        switch self {
        case .win9x: return 2
        default: return 1
        }
    }

    /// The pack's index of DOSBox builds in `eXo/util`. eXoWin3x has none:
    /// each launcher names its build (``DOSBoxIndex/fromLaunchers(in:)``).
    public var dosboxIndexName: String? {
        switch self {
        case .dos: return "dosbox.txt"
        case .demoScene: return "demoscn.txt"
        default: return nil
        }
    }

    /// True when the games run in DOSBox through a translated `dosbox.conf`.
    public var runsInDOSBox: Bool {
        switch self {
        case .dos, .win3x, .demoScene: return true
        case .win9x, .scummVM, .appleIIGS, .interactiveFiction: return false
        }
    }

    public var displayName: String { rawValue }
}

nonisolated extension Game {
    /// The eXo project the game belongs to, when it is one that installs
    /// from an archive.
    public var eXoPack: EXoPack? {
        if isEXoDOSLauncher { return .dos }
        guard applicationPath.lowercased().hasSuffix(".bat"), let rootFolder else { return nil }
        let parts = WindowsPath.components(of: rootFolder)
        return EXoPack.allCases.first { $0 != .dos && Self.configSubpath(of: parts, for: $0) != nil }
    }

    /// True for games that install from an eXo archive and can be uninstalled.
    public var isEXoGame: Bool { eXoPack != nil }

    /// One of eXo's picks: in an eXo pack's XML, `Favorite` marks the games
    /// eXo recommends, not the user's favorites.
    public var isEXoFavorite: Bool { favorite && isEXoGame }

    /// A favorite before the user changes it: the XML flag, which outside the
    /// eXo packs is the user's own from LaunchBox.
    public var isFavoriteByDefault: Bool { favorite && !isEXoGame }

    /// The unpacked game folder relative to `eXo/`, as path components: for
    /// example `["eXoDOS", "ultima5"]` or `["eXoWin9x", "1996", "A-10 Cuba (1996)"]`.
    public var installPathComponents: [String]? {
        switch eXoPack {
        case .dos:
            return gameFolderName.map { [EXoPack.dos.directoryName, $0] }
        case let pack?:
            return configSubpath(for: pack).map { [pack.directoryName] + $0 }
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
        rootFolder.flatMap { Self.configSubpath(of: WindowsPath.components(of: $0), for: pack) }
    }

    private static func configSubpath(of parts: [String], for pack: EXoPack) -> [String]? {
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
