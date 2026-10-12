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
        let platformFiles = platforms.map { (platform: $0, url: root.platformFile(named: $0.name)) }
            .filter { fm.fileExists(atPath: $0.url.path) }
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
                    if var game = Game(record: record) {
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
        let dosboxIndex = (try? DOSBoxIndex(contentsOf: root.dosboxIndexFile)) ?? DOSBoxIndex()

        let payload = LibraryCache.Payload(
            version: LibraryCache.version, fingerprint: fingerprint ?? "",
            games: games.map {
                var g = $0
                g.collectionID = collection.id
                return g
            },
            platforms: platforms, categories: categories, platformFolders: folders, playlists: playlists,
            parents: parents,
            alternateNames: alternates, additionalApplications: extraApps, dosboxIndex: dosboxIndex,
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
        let installed = root.hasEXoDOS ? Self.installedFolderNames(in: root.gamesDirectory) : []
        let local = localStore.map { Self.installedFolderNames(in: $0.gamesDirectory) } ?? []
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
            dosboxIndex: payload.dosboxIndex,
            emulators: payload.emulators,
            emulatorPlatforms: payload.emulatorPlatforms,
            installedFolderNames: installed,
            localStore: localStore,
            locallyInstalledFolderNames: local
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

    /// Lists the sub-folders of `eXo/eXoDOS/` (installed games), skipping `!dos`.
    public static func installedFolderNames(in gamesDirectory: URL) -> Set<String> {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: gamesDirectory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        var names: Set<String> = []
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let name = entry.lastPathComponent
            if name == "!dos" || name.hasPrefix("!") { continue }
            names.insert(name)
        }
        return names
    }
}
