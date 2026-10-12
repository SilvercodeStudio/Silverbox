import Foundation

/// An immutable, fully loaded view of a library. Built once by
/// ``LibraryLoader`` and shared with the UI.
nonisolated public struct LibrarySnapshot: Sendable {
    public let collection: LibraryCollection
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
    public let emulators: [LaunchBoxEmulator]
    public let emulatorPlatforms: [LaunchBoxEmulatorPlatform]
    /// Names of folders directly inside `eXo/eXoDOS/`: a game whose
    /// ``Game/gameFolderName`` is listed here is installed in the library.
    public let installedFolderNames: Set<String>
    /// The writable companion folder, when configured.
    public let localStore: LocalStore?
    /// Names of game folders unpacked in the local store.
    public let locallyInstalledFolderNames: Set<String>
    public let loadedAt: Date

    private let indexByID: [String: Int]

    public init(
        root: LibraryRoot, collection: LibraryCollection? = nil, games: [Game], platforms: [Platform],
        categories: [PlatformCategory],
        platformFolders: [PlatformFolder], playlists: [Playlist], parents: [ParentLink],
        alternateNames: [AlternateName], additionalApplications: [AdditionalApplication],
        dosboxIndex: DOSBoxIndex, emulators: [LaunchBoxEmulator] = [],
        emulatorPlatforms: [LaunchBoxEmulatorPlatform] = [],
        installedFolderNames: Set<String>, localStore: LocalStore? = nil,
        locallyInstalledFolderNames: Set<String> = [], loadedAt: Date = Date()
    ) {
        let resolvedCollection =
            collection
            ?? LibraryCollection(
                name: LibraryCollection.suggestedName(for: root.url), rootPath: root.url.path,
                substitutions: root.substitutions)
        self.collection = resolvedCollection
        self.root = root
        self.games = games.map { game in
            guard game.collectionID == Game.unassignedCollection else { return game }
            var stamped = game
            stamped.collectionID = resolvedCollection.id
            return stamped
        }
        self.platforms = platforms
        self.categories = categories
        self.platformFolders = platformFolders
        self.playlists = playlists
        self.parents = parents
        self.tree = LibraryTreeBuilder.build(
            categories: categories, platforms: platforms, playlists: playlists, parents: parents)
        self.alternateNames = Dictionary(grouping: alternateNames, by: \.gameID)
        self.additionalApplications = Dictionary(grouping: additionalApplications, by: \.gameID)
        self.dosboxIndex = dosboxIndex
        self.emulators = emulators
        self.emulatorPlatforms = emulatorPlatforms
        self.installedFolderNames = installedFolderNames
        self.localStore = localStore
        self.locallyInstalledFolderNames = locallyInstalledFolderNames
        self.loadedAt = loadedAt
        var index: [String: Int] = [:]
        index.reserveCapacity(games.count)
        for (offset, game) in self.games.enumerated() where index[game.launchBoxID] == nil {
            index[game.launchBoxID] = offset
        }
        self.indexByID = index
    }

    /// Looks a game up by its LaunchBox GUID, or by its collection-scoped id.
    public func game(id: String) -> Game? {
        let key = id.contains("/") ? String(id.split(separator: "/", maxSplits: 1).last ?? "") : id
        guard let offset = indexByID[key] else { return nil }
        return games[offset]
    }

    public func playlist(id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    public func platform(named name: String) -> Platform? {
        platforms.first { $0.name == name }
    }

    /// True when the game's folder exists in the local store or the library.
    public func isInstalled(_ game: Game) -> Bool {
        guard game.isDOSGame else { return true }
        return installedLocation(for: game) != nil
    }

    /// The installed game folder, local store first.
    public func installedLocation(for game: Game) -> GameLocation? {
        guard game.isDOSGame, let folder = game.gameFolderName else { return nil }
        if let localStore, locallyInstalledFolderNames.contains(folder) {
            return .local(localStore.gamesDirectory.appendingPathComponent(folder, isDirectory: true))
        }
        if installedFolderNames.contains(folder) {
            return .library(root.gamesDirectory.appendingPathComponent(folder, isDirectory: true))
        }
        return nil
    }

    /// A copy with fresh installed-folder sets, after installing or removing a game.
    public func replacingInstalledFolders(library: Set<String>, local: Set<String>) -> LibrarySnapshot {
        LibrarySnapshot(
            root: root, collection: collection, games: games, platforms: platforms, categories: categories,
            platformFolders: platformFolders,
            playlists: playlists, parents: parents,
            alternateNames: alternateNames.values.flatMap { $0 },
            additionalApplications: additionalApplications.values.flatMap { $0 },
            dosboxIndex: dosboxIndex, emulators: emulators, emulatorPlatforms: emulatorPlatforms,
            installedFolderNames: library, localStore: localStore,
            locallyInstalledFolderNames: local, loadedAt: loadedAt)
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

    /// LaunchBox's emulator assignment for a platform, default first.
    public func emulatorAssignment(for platform: String) -> (
        emulator: LaunchBoxEmulator, platform: LaunchBoxEmulatorPlatform
    )? {
        let candidates = emulatorPlatforms.filter { $0.platform == platform }.sorted { $0.isDefault && !$1.isDefault }
        for candidate in candidates {
            if let emulator = emulators.first(where: { $0.id == candidate.emulatorID }) { return (emulator, candidate) }
        }
        return nil
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
