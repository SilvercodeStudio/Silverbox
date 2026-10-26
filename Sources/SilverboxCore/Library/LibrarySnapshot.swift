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
    /// Each DOSBox pack's index of the builds its games use.
    public let dosboxIndexes: [EXoPack: DOSBoxIndex]
    public let emulators: [LaunchBoxEmulator]
    public let emulatorPlatforms: [LaunchBoxEmulatorPlatform]
    /// Game folders unpacked in the library, relative to `eXo/`: a game
    /// whose ``Game/installPath`` is listed here is installed there.
    public let installedGamePaths: Set<String>
    /// The writable companion folder, when configured.
    public let localStore: LocalStore?
    /// Game folders unpacked in the local store, relative to its games root.
    public let locallyInstalledGamePaths: Set<String>
    public let loadedAt: Date

    private let indexByID: [String: Int]
    /// The installed sets keyed by lowercased path, to the path on disk:
    /// some eXo zips unpack to a folder whose case differs from the XML.
    private let libraryPathByKey: [String: String]
    private let localPathByKey: [String: String]

    public init(
        root: LibraryRoot, collection: LibraryCollection? = nil, games: [Game], platforms: [Platform],
        categories: [PlatformCategory],
        platformFolders: [PlatformFolder], playlists: [Playlist], parents: [ParentLink],
        alternateNames: [AlternateName], additionalApplications: [AdditionalApplication],
        dosboxIndexes: [EXoPack: DOSBoxIndex] = [:], emulators: [LaunchBoxEmulator] = [],
        emulatorPlatforms: [LaunchBoxEmulatorPlatform] = [],
        installedGamePaths: Set<String>, localStore: LocalStore? = nil,
        locallyInstalledGamePaths: Set<String> = [], loadedAt: Date = Date()
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
        // eXoDOS's MS-DOS.xml lists most alternate names twice, word for word.
        var seen = Set<AlternateName>()
        self.alternateNames = Dictionary(grouping: alternateNames.filter { seen.insert($0).inserted }, by: \.gameID)
        self.additionalApplications = Dictionary(grouping: additionalApplications, by: \.gameID)
        self.dosboxIndexes = dosboxIndexes
        self.emulators = emulators
        self.emulatorPlatforms = emulatorPlatforms
        self.installedGamePaths = installedGamePaths
        self.localStore = localStore
        self.locallyInstalledGamePaths = locallyInstalledGamePaths
        self.libraryPathByKey = Self.keyed(installedGamePaths)
        self.localPathByKey = Self.keyed(locallyInstalledGamePaths)
        self.loadedAt = loadedAt
        var index: [String: Int] = [:]
        index.reserveCapacity(games.count)
        for (offset, game) in self.games.enumerated() where index[game.launchBoxID] == nil {
            index[game.launchBoxID] = offset
        }
        self.indexByID = index
    }

    private static func keyed(_ paths: Set<String>) -> [String: String] {
        Dictionary(paths.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The eXoDOS index of DOSBox builds.
    public var dosboxIndex: DOSBoxIndex { dosboxIndex(for: .dos) }

    public func dosboxIndex(for pack: EXoPack) -> DOSBoxIndex { dosboxIndexes[pack] ?? DOSBoxIndex() }

    /// The DOSBox build eXo runs the game with, from its pack's index.
    public func dosboxBuild(for game: Game) -> EXoDOSBuild? {
        guard let pack = game.eXoPack else { return nil }
        return dosboxIndex(for: pack).build(forLauncherBaseName: game.launcherBaseName)
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
        guard game.isEXoGame else { return true }
        return installedLocation(for: game) != nil
    }

    /// The installed game folder, local store first.
    public func installedLocation(for game: Game) -> GameLocation? {
        guard let key = game.installPath?.lowercased() else { return nil }
        if let localStore, let path = localPathByKey[key] {
            return .local(localStore.gamesRoot.appendingPathComponent(path, isDirectory: true))
        }
        if let path = libraryPathByKey[key] {
            return .library(root.eXoDirectory.appendingPathComponent(path, isDirectory: true))
        }
        return nil
    }

    /// A copy with fresh installed-game sets, after installing or removing a game.
    public func replacingInstalledGames(library: Set<String>, local: Set<String>) -> LibrarySnapshot {
        LibrarySnapshot(
            root: root, collection: collection, games: games, platforms: platforms, categories: categories,
            platformFolders: platformFolders,
            playlists: playlists, parents: parents,
            alternateNames: alternateNames.values.flatMap { $0 },
            additionalApplications: additionalApplications.values.flatMap { $0 },
            dosboxIndexes: dosboxIndexes, emulators: emulators, emulatorPlatforms: emulatorPlatforms,
            installedGamePaths: library, localStore: localStore,
            locallyInstalledGamePaths: local, loadedAt: loadedAt)
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
