import Foundation

nonisolated public struct LibraryLoadProgress: Sendable, Hashable {
    public var stage: String
    public var fraction: Double
    public var gamesLoaded: Int

    public init(stage: String, fraction: Double, gamesLoaded: Int) {
        self.stage = stage
        self.fraction = fraction
        self.gamesLoaded = gamesLoaded
    }
}

nonisolated public enum LibraryLoadError: Error, Sendable {
    case missingPlatformList(URL)
}

/// Reads a whole LaunchBox `Data` folder into a ``LibrarySnapshot``.
///
/// Loading is synchronous and can take a few seconds for the 7,600-game
/// MS-DOS file, so call it off the main thread.
nonisolated public struct LibraryLoader: Sendable {
    public let collection: LibraryCollection
    public let root: LibraryRoot
    public let localStore: LocalStore?
    public let cache: LibraryCache?

    public init(collection: LibraryCollection, localStore: LocalStore? = nil, cache: LibraryCache? = nil) {
        self.collection = collection
        self.root = collection.root
        self.localStore = localStore
        self.cache = cache
    }

    public init(root: LibraryRoot, localStore: LocalStore? = nil) {
        self.init(
            collection: LibraryCollection(
                name: LibraryCollection.suggestedName(for: root.url), rootPath: root.url.path,
                substitutions: root.substitutions),
            localStore: localStore)
    }

    public func load(progress: (@Sendable (LibraryLoadProgress) -> Void)? = nil) throws -> LibrarySnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.platformsFile.path) else {
            throw LibraryLoadError.missingPlatformList(root.platformsFile)
        }

        let fingerprint = cache.map { _ in LibraryCache.fingerprint(for: root) }
        if let cache, let fingerprint, let payload = cache.load(collectionID: collection.id, fingerprint: fingerprint) {
            progress?(
                LibraryLoadProgress(stage: "Loading saved library", fraction: 0.9, gamesLoaded: payload.games.count))
            return snapshot(from: payload)
        }

        progress?(LibraryLoadProgress(stage: "Reading platforms", fraction: 0, gamesLoaded: 0))
        var platforms: [Platform] = []
        var categories: [PlatformCategory] = []
        var folders: [PlatformFolder] = []
        try LaunchBoxXMLParser.parse(url: root.platformsFile) { record in
            switch record.element {
            case "Platform": if let p = Platform(record: record) { platforms.append(p) }
            case "PlatformCategory": if let c = PlatformCategory(record: record) { categories.append(c) }
            case "PlatformFolder": if let f = PlatformFolder(record: record) { folders.append(f) }
            default: break
            }
        }

        var parents: [ParentLink] = []
        if fm.fileExists(atPath: root.parentsFile.path) {
            try LaunchBoxXMLParser.parse(url: root.parentsFile) { record in
                if record.element == "Parent", let link = ParentLink(record: record) { parents.append(link) }
            }
        }

        progress?(LibraryLoadProgress(stage: "Reading playlists", fraction: 0.05, gamesLoaded: 0))
        let playlists = try loadPlaylists()

        var games: [Game] = []
        var alternates: [AlternateName] = []
        var extraApps: [AdditionalApplication] = []
        // eXo lists its media add-on platforms whether or not the add-on is
        // installed; a platform without a game list would show up empty.
        // Earlier Mac setups listed some add-on platforms twice.
        var platformNames = Set<String>()
        platforms.removeAll {
            !fm.fileExists(atPath: root.platformFile(named: $0.name).path)
                || !platformNames.insert($0.name.lowercased()).inserted
        }
        let platformFiles = platforms.map { (platform: $0, url: root.platformFile(named: $0.name)) }
        // Weight progress by file size so the big MS-DOS file dominates.
        let sizes = platformFiles.map { (try? fm.attributesOfItem(atPath: $0.url.path)[.size] as? Int) ?? 1 }
        let totalSize = max(1, sizes.reduce(0, +))
        var doneSize = 0
        for (entry, size) in zip(platformFiles, sizes) {
            let base = 0.1 + 0.85 * Double(doneSize) / Double(totalSize)
            progress?(
                LibraryLoadProgress(stage: "Reading \(entry.platform.name)", fraction: base, gamesLoaded: games.count))
            var countInFile = 0
            try LaunchBoxXMLParser.parse(url: entry.url) { record in
                switch record.element {
                case "Game":
                    // Each pack lists its Windows setup script as a game.
                    if var game = Game(record: record), !game.isEXoSetupScript {
                        if game.platform.isEmpty { game.platform = entry.platform.name }
                        games.append(game)
                        countInFile += 1
                        if countInFile % 500 == 0 {
                            progress?(
                                LibraryLoadProgress(
                                    stage: "Reading \(entry.platform.name)", fraction: base, gamesLoaded: games.count))
                        }
                    }
                case "AlternateName":
                    if let alt = AlternateName(record: record) { alternates.append(alt) }
                case "AdditionalApplication":
                    if let app = AdditionalApplication(record: record) { extraApps.append(app) }
                default:
                    break
                }
            }
            doneSize += size
        }
        // eXo gives a few games the same ID on two platforms, such as
        // Lighthouse: The Dark Being in MS-DOS and Windows 9x. The later one
        // gets its platform added, so that each game has an ID of its own.
        var gameIDs = Set<String>()
        for index in games.indices where !gameIDs.insert(games[index].launchBoxID).inserted {
            games[index].launchBoxID += "#" + games[index].platform
        }

        progress?(LibraryLoadProgress(stage: "Reading emulators", fraction: 0.96, gamesLoaded: games.count))
        var emulators: [LaunchBoxEmulator] = []
        var emulatorPlatforms: [LaunchBoxEmulatorPlatform] = []
        if fm.fileExists(atPath: root.emulatorsFile.path) {
            try? LaunchBoxXMLParser.parse(url: root.emulatorsFile) { record in
                switch record.element {
                case "Emulator": if let e = LaunchBoxEmulator(record: record) { emulators.append(e) }
                case "EmulatorPlatform":
                    if let e = LaunchBoxEmulatorPlatform(record: record) { emulatorPlatforms.append(e) }
                default: break
                }
            }
        }
        var dosboxIndexes: [EXoPack: DOSBoxIndex] = [:]
        for pack in EXoPack.allCases {
            if let file = root.dosboxIndexFile(for: pack), let index = try? DOSBoxIndex(contentsOf: file) {
                dosboxIndexes[pack] = index
            } else if pack.runsInDOSBox, pack.dosboxIndexName == nil {
                let configs = root.gameConfigsDirectory(for: pack)
                if fm.fileExists(atPath: configs.path) { dosboxIndexes[pack] = DOSBoxIndex.fromLaunchers(in: configs) }
            }
        }

        let payload = LibraryCache.Payload(
            version: LibraryCache.version, fingerprint: fingerprint ?? "",
            games: games.map {
                var g = $0
                g.collectionID = collection.id
                return g
            },
            platforms: platforms, categories: categories, platformFolders: folders, playlists: playlists,
            parents: parents,
            alternateNames: alternates, additionalApplications: extraApps, dosboxIndexes: dosboxIndexes,
            emulators: emulators, emulatorPlatforms: emulatorPlatforms)
        if let cache, fingerprint != nil {
            progress?(LibraryLoadProgress(stage: "Saving library cache", fraction: 0.98, gamesLoaded: games.count))
            cache.save(payload, collectionID: collection.id)
        }
        progress?(LibraryLoadProgress(stage: "Done", fraction: 1, gamesLoaded: games.count))
        return snapshot(from: payload)
    }

    /// Builds the snapshot, reading the installed-folder sets fresh.
    func snapshot(from payload: LibraryCache.Payload) -> LibrarySnapshot {
        let installed = root.hasEXoDOS ? Self.installedGamePaths(in: root.eXoDirectory) : []
        let local = localStore.map { Self.installedGamePaths(in: $0.gamesRoot) } ?? []
        return LibrarySnapshot(
            root: root,
            collection: collection,
            games: payload.games,
            platforms: payload.platforms,
            categories: payload.categories,
            platformFolders: payload.platformFolders,
            playlists: payload.playlists,
            parents: payload.parents,
            alternateNames: payload.alternateNames,
            additionalApplications: payload.additionalApplications,
            dosboxIndexes: payload.dosboxIndexes,
            emulators: payload.emulators,
            emulatorPlatforms: payload.emulatorPlatforms,
            installedGamePaths: installed,
            localStore: localStore,
            locallyInstalledGamePaths: local
        )
    }

    public func loadPlaylists() throws -> [Playlist] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.playlistsDirectory.path) else { return [] }
        var playlists: [Playlist] = []
        for name in names.sorted() where name.lowercased().hasSuffix(".xml") {
            let url = root.playlistsDirectory.appendingPathComponent(name)
            var playlist: Playlist?
            var filters: [PlaylistFilter] = []
            var games: [PlaylistGame] = []
            try LaunchBoxXMLParser.parse(url: url) { record in
                switch record.element {
                case "Playlist": playlist = Playlist(record: record)
                case "PlaylistFilter": if let f = PlaylistFilter(record: record) { filters.append(f) }
                case "PlaylistGame": if let g = PlaylistGame(record: record) { games.append(g) }
                default: break
                }
            }
            if var playlist {
                playlist.filters = filters
                playlist.games = games
                playlists.append(playlist)
            }
        }
        return playlists
    }

    /// Lists the unpacked games under an `eXo/` folder (or the local store's
    /// mirror of it) as paths relative to it, such as `eXoDOS/ultima5` and
    /// `eXoWin9x/1996/A-10 Cuba (1996)`.
    public static func installedGamePaths(in eXoDirectory: URL) -> Set<String> {
        var paths: Set<String> = []
        for pack in EXoPack.allCases {
            var level = [pack.directoryName]
            for _ in 0..<pack.installDepth {
                level = level.flatMap { parent in
                    subfolderNames(of: eXoDirectory.appendingPathComponent(parent, isDirectory: true))
                        .map { parent + "/" + $0 }
                }
            }
            paths.formUnion(level)
        }
        return paths
    }

    /// Folder names inside `directory`, skipping `!dos`, `!win9x`, `!save`
    /// and other `!` folders. Hidden folders count: eXoScummVM has a game
    /// named `.i.f`.
    private static func subfolderNames(of directory: URL) -> [String] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        return entries.compactMap { entry in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = entry.lastPathComponent
            return isDirectory && !name.hasPrefix("!") ? name : nil
        }
    }
}
