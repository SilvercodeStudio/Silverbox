import Foundation

/// Every enabled collection, loaded. Games keep their collection-scoped ids,
/// so two copies of the same LaunchBox library can coexist.
nonisolated public struct Library: Sendable {
    public let snapshots: [LibrarySnapshot]
    public let games: [Game]
    /// The eXo packs that have games here, in ``EXoPack`` order.
    public let packs: [EXoPack]
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
