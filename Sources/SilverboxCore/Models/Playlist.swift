import Foundation

/// A LaunchBox playlist (`Data/Playlists/<Name>.xml`).
///
/// eXoDOS playlists are mostly auto-populated: one filter on the `Series`
/// field matching a `Playlist: X` marker. A few list games explicitly.
nonisolated public struct Playlist: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var nestedName: String?
    public var sortTitle: String?
    public var notes: String?
    public var autoPopulate: Bool
    public var includeWithPlatforms: Bool
    public var filters: [PlaylistFilter]
    public var games: [PlaylistGame]

    public init(
        id: String, name: String, nestedName: String? = nil, sortTitle: String? = nil,
        notes: String? = nil, autoPopulate: Bool = false, includeWithPlatforms: Bool = false,
        filters: [PlaylistFilter] = [], games: [PlaylistGame] = []
    ) {
        self.id = id
        self.name = name
        self.nestedName = nestedName
        self.sortTitle = sortTitle
        self.notes = notes
        self.autoPopulate = autoPopulate
        self.includeWithPlatforms = includeWithPlatforms
        self.filters = filters
        self.games = games
    }
}

nonisolated public struct PlaylistFilter: Hashable, Sendable, Codable {
    public var fieldKey: String
    public var comparison: String
    public var value: String

    public init(fieldKey: String, comparison: String, value: String) {
        self.fieldKey = fieldKey
        self.comparison = comparison
        self.value = value
    }
}

nonisolated public struct PlaylistGame: Hashable, Sendable, Codable {
    public var gameID: String
    public var title: String?
    public var fileName: String?
    public var platform: String?
    public var manualOrder: Int

    public init(
        gameID: String, title: String? = nil, fileName: String? = nil, platform: String? = nil, manualOrder: Int = -1
    ) {
        self.gameID = gameID
        self.title = title
        self.fileName = fileName
        self.platform = platform
        self.manualOrder = manualOrder
    }
}
