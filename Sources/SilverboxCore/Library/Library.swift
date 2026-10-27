import Foundation

/// Every enabled collection, loaded. Games keep their collection-scoped ids,
/// so two copies of the same LaunchBox library can coexist.
nonisolated public struct Library: Sendable {
    public let snapshots: [LibrarySnapshot]
    public let games: [Game]
    /// The eXo packs that have games here, in ``EXoPack`` order.
    public let packs: [EXoPack]
    /// True when any eXo pack marks games as its favorites.
    public let hasEXoFavorites: Bool
    private let locations: [String: (snapshot: Int, game: Int)]
    private let snapshotIndexByID: [UUID: Int]

    public init(snapshots: [LibrarySnapshot]) {
        self.snapshots = snapshots
        var games: [Game] = []
        var locations: [String: (Int, Int)] = [:]
        var byID: [UUID: Int] = [:]
        for (snapshotIndex, snapshot) in snapshots.enumerated() {
            byID[snapshot.collection.id] = snapshotIndex
            games.reserveCapacity(games.count + snapshot.games.count)
            for (gameIndex, game) in snapshot.games.enumerated() {
                locations[game.id] = (snapshotIndex, gameIndex)
                games.append(game)
            }
        }
        self.games = games
        let present = Set(games.lazy.compactMap(\.eXoPack))
        self.packs = EXoPack.allCases.filter(present.contains)
        self.hasEXoFavorites = games.contains(where: \.isEXoFavorite)
        self.locations = locations
        self.snapshotIndexByID = byID
    }

    public static let empty = Library(snapshots: [])

    public var isEmpty: Bool { snapshots.isEmpty }

    public func snapshot(id: UUID) -> LibrarySnapshot? {
        guard let index = snapshotIndexByID[id] else { return nil }
        return snapshots[index]
    }

    public func snapshot(for game: Game) -> LibrarySnapshot? {
        snapshot(id: game.collectionID)
    }

    public func game(id: String) -> Game? {
        guard let location = locations[id] else { return nil }
        return snapshots[location.snapshot].games[location.game]
    }

    public func isInstalled(_ game: Game) -> Bool {
        snapshot(for: game)?.isInstalled(game) ?? false
    }

    public func installedLocation(for game: Game) -> GameLocation? {
        snapshot(for: game)?.installedLocation(for: game)
    }

    public func alternateNames(for game: Game) -> [AlternateName] {
        snapshot(for: game)?.alternateNames[game.launchBoxID] ?? []
    }

    public func node(collectionID: UUID, ref: LibraryEntityRef) -> LibraryNode? {
        snapshot(id: collectionID)?.node(for: ref)
    }

    /// A copy with one snapshot replaced, after installing or removing a game.
    public func replacing(_ snapshot: LibrarySnapshot) -> Library {
        Library(snapshots: snapshots.map { $0.collection.id == snapshot.collection.id ? snapshot : $0 })
    }
}

/// A filesystem scan carries the source it read. Applying it to the current
/// library preserves other collections and rejects changed/removed sources.
nonisolated public struct InstalledGameScan: Sendable {
    public let collectionID: UUID
    public let root: LibraryRoot
    public let localStore: LocalStore?
    public let libraryPaths: Set<String>
    public let localPaths: Set<String>

    public init(snapshot: LibrarySnapshot, libraryPaths: Set<String>, localPaths: Set<String>) {
        collectionID = snapshot.collection.id
        root = snapshot.root
        localStore = snapshot.localStore
        self.libraryPaths = libraryPaths
        self.localPaths = localPaths
    }
}

nonisolated extension Library {
    public func applying(_ scan: InstalledGameScan) -> Library {
        guard let snapshot = snapshot(id: scan.collectionID), snapshot.root == scan.root,
            snapshot.localStore == scan.localStore
        else { return self }
        return replacing(snapshot.replacingInstalledGames(library: scan.libraryPaths, local: scan.localPaths))
    }
}
