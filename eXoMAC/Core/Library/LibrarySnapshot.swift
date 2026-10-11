import Foundation

/// An immutable, fully loaded view of a library. Built once by
/// ``LibraryLoader`` and shared with the UI.
nonisolated public struct LibrarySnapshot: Sendable {
    public let root: LibraryRoot
    public let games: [Game]
    public let platforms: [Platform]
    public let categories: [PlatformCategory]
    public let platformFolders: [PlatformFolder]
    public let playlists: [Playlist]
    public let parents: [ParentLink]
    public let tree: [LibraryNode]
    public let alternateNames: [String: [AlternateName]]
    public let additionalApplications: [String: [AdditionalApplication]]
    public let dosboxIndex: DOSBoxIndex
    /// Names of folders directly inside `eXo/eXoDOS/`: a game whose
    /// ``Game/gameFolderName`` is listed here is installed.
    public let installedFolderNames: Set<String>
    public let loadedAt: Date

    private let indexByID: [String: Int]

    public init(root: LibraryRoot, games: [Game], platforms: [Platform], categories: [PlatformCategory],
                platformFolders: [PlatformFolder], playlists: [Playlist], parents: [ParentLink],
                alternateNames: [AlternateName], additionalApplications: [AdditionalApplication],
                dosboxIndex: DOSBoxIndex, installedFolderNames: Set<String>, loadedAt: Date = Date()) {
        self.root = root
        self.games = games
        self.platforms = platforms
        self.categories = categories
        self.platformFolders = platformFolders
        self.playlists = playlists
        self.parents = parents
        self.tree = LibraryTreeBuilder.build(categories: categories, platforms: platforms, playlists: playlists, parents: parents)
        self.alternateNames = Dictionary(grouping: alternateNames, by: \.gameID)
        self.additionalApplications = Dictionary(grouping: additionalApplications, by: \.gameID)
        self.dosboxIndex = dosboxIndex
        self.installedFolderNames = installedFolderNames
        self.loadedAt = loadedAt
        var index: [String: Int] = [:]
        index.reserveCapacity(games.count)
        for (offset, game) in games.enumerated() { index[game.id] = offset }
        self.indexByID = index
    }

    public func game(id: String) -> Game? {
        guard let offset = indexByID[id] else { return nil }
        return games[offset]
    }

    public func playlist(id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    public func platform(named name: String) -> Platform? {
        platforms.first { $0.name == name }
    }

    /// True when the game's folder exists under `eXo/eXoDOS/`.
    public func isInstalled(_ game: Game) -> Bool {
        guard game.isDOSGame, let folder = game.gameFolderName else { return !game.isDOSGame }
        return installedFolderNames.contains(folder) || installedFolderNames.contains(folder.lowercased())
    }

    /// The media folder LaunchBox configured for `mediaType` on `platform`,
    /// or the conventional default.
    public func mediaFolder(platform: String, mediaType: String) -> URL {
        if let entry = platformFolders.first(where: { $0.platform == platform && $0.mediaType == mediaType }) {
            return root.url(forWindowsRelativePath: entry.folderPath)
        }
        switch mediaType {
        case "Video": return root.videosDirectory.appendingPathComponent(platform, isDirectory: true)
        case "Manual": return root.manualsDirectory.appendingPathComponent(platform, isDirectory: true)
        case "Music": return root.musicDirectory.appendingPathComponent(platform, isDirectory: true)
        default:
            return root.imagesDirectory
                .appendingPathComponent(platform, isDirectory: true)
                .appendingPathComponent(mediaType, isDirectory: true)
        }
    }

    public func node(for ref: LibraryEntityRef) -> LibraryNode? {
        func find(in nodes: [LibraryNode]) -> LibraryNode? {
            for node in nodes {
                if node.ref == ref { return node }
                if let found = find(in: node.children) { return found }
            }
            return nil
        }
        return find(in: tree)
    }
}
