import Foundation

/// Which games a sidebar selection shows.
nonisolated public enum LibraryScope: Hashable, Sendable {
    case all
    case node(LibraryEntityRef)
    case favorites
    case installed
    case recentlyPlayed
}

nonisolated public enum GameSortOrder: String, CaseIterable, Sendable, Codable {
    case title
    case releaseYear
    case developer
    case lastPlayed
    case dateAdded
    case playCount
    case communityRating
}

/// Pure query helpers over a ``LibrarySnapshot``.
nonisolated public struct LibraryQuery: Sendable {
    public let snapshot: LibrarySnapshot

    public init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
    }

    /// The games in a scope, before searching and sorting. `overlay` supplies
    /// user changes (favorites, play history) kept outside the XML.
    public func games(in scope: LibraryScope, overlay: UserLibraryState? = nil) -> [Game] {
        switch scope {
        case .all:
            return snapshot.games
        case .favorites:
            return snapshot.games.filter { overlay?.state(for: $0.id).favorite ?? $0.favorite }
        case .installed:
            return snapshot.games.filter { snapshot.isInstalled($0) }
        case .recentlyPlayed:
            guard let overlay else { return [] }
            return snapshot.games
                .filter { overlay.state(for: $0.id).lastPlayed != nil }
                .sorted { (overlay.state(for: $0.id).lastPlayed ?? .distantPast) > (overlay.state(for: $1.id).lastPlayed ?? .distantPast) }
        case .node(let ref):
            switch ref {
            case .platform(let name):
                return snapshot.games.filter { $0.platform == name }
            case .category:
                guard let node = snapshot.node(for: ref) else { return [] }
                let names = Set(node.platformNames)
                return snapshot.games.filter { names.contains($0.platform) }
            case .playlist(let id):
                guard let playlist = snapshot.playlist(id: id) else { return [] }
                return PlaylistResolver(snapshot: snapshot).games(in: playlist)
            }
        }
    }

    /// Case- and diacritic-insensitive search over titles, sort titles,
    /// alternate names and developers. Pass a ``LibrarySearchIndex`` to avoid
    /// re-folding every title on each keystroke.
    public func filter(_ games: [Game], search: String, index: LibrarySearchIndex? = nil) -> [Game] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return games }
        let terms = needle.split(separator: " ").map { String($0) }
        return games.filter { game in
            let haystack = index?.keys[game.id] ?? searchText(for: game)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    public func searchText(for game: Game) -> String {
        var parts = [game.title, game.sortTitle ?? "", game.developer ?? "", game.publisher ?? ""]
        if let alternates = snapshot.alternateNames[game.id] {
            parts.append(contentsOf: alternates.map(\.name))
        }
        return parts.joined(separator: "\n").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public func sort(_ games: [Game], by order: GameSortOrder, ascending: Bool = true, overlay: UserLibraryState? = nil) -> [Game] {
        let sorted: [Game]
        switch order {
        case .title:
            sorted = games.sorted { Self.titleLess($0, $1) }
        case .releaseYear:
            sorted = games.sorted {
                let a = $0.releaseDate ?? .distantFuture, b = $1.releaseDate ?? .distantFuture
                return a == b ? Self.titleLess($0, $1) : a < b
            }
        case .developer:
            sorted = games.sorted {
                let a = $0.developer ?? "\u{FFFF}", b = $1.developer ?? "\u{FFFF}"
                let c = a.localizedCaseInsensitiveCompare(b)
                return c == .orderedSame ? Self.titleLess($0, $1) : c == .orderedAscending
            }
        case .lastPlayed:
            sorted = games.sorted {
                let a = overlay?.state(for: $0.id).lastPlayed ?? $0.lastPlayed ?? .distantPast
                let b = overlay?.state(for: $1.id).lastPlayed ?? $1.lastPlayed ?? .distantPast
                return a == b ? Self.titleLess($0, $1) : a > b
            }
        case .dateAdded:
            sorted = games.sorted {
                let a = $0.dateAdded ?? .distantPast, b = $1.dateAdded ?? .distantPast
                return a == b ? Self.titleLess($0, $1) : a > b
            }
        case .playCount:
            sorted = games.sorted {
                let a = $0.playCount + (overlay?.state(for: $0.id).playCount ?? 0)
                let b = $1.playCount + (overlay?.state(for: $1.id).playCount ?? 0)
                return a == b ? Self.titleLess($0, $1) : a > b
            }
        case .communityRating:
            sorted = games.sorted {
                let a = $0.communityStarRating ?? -1, b = $1.communityStarRating ?? -1
                return a == b ? Self.titleLess($0, $1) : a > b
            }
        }
        return ascending ? sorted : Array(sorted.reversed())
    }

    private static func titleLess(_ a: Game, _ b: Game) -> Bool {
        let result = a.sortKey.compare(b.sortKey, options: [.numeric])
        return result == .orderedSame ? a.id < b.id : result == .orderedAscending
    }
}

/// Resolves a playlist to its games: explicit members plus auto-populate filters.
nonisolated public struct PlaylistResolver: Sendable {
    public let snapshot: LibrarySnapshot

    public init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
    }

    public func games(in playlist: Playlist) -> [Game] {
        var seen: Set<String> = []
        var result: [Game] = []
        for member in playlist.games.sorted(by: { $0.manualOrder < $1.manualOrder }) {
            if let game = snapshot.game(id: member.gameID), seen.insert(game.id).inserted {
                result.append(game)
            }
        }
        if playlist.autoPopulate, !playlist.filters.isEmpty {
            for game in snapshot.games where !seen.contains(game.id) {
                if playlist.filters.allSatisfy({ matches(game, filter: $0) }) {
                    seen.insert(game.id)
                    result.append(game)
                }
            }
        }
        return result
    }

    /// Evaluates one LaunchBox playlist filter. Multi-value fields match when
    /// any value matches, which is how `Series` equal-to filters behave.
    public func matches(_ game: Game, filter: PlaylistFilter) -> Bool {
        let values = fieldValues(of: game, key: filter.fieldKey)
        let target = filter.value.lowercased()
        switch filter.comparison {
        case "EqualTo":
            return values.contains { $0.lowercased() == target }
        case "NotEqualTo":
            return !values.contains { $0.lowercased() == target }
        case "Contains":
            return values.contains { $0.lowercased().contains(target) }
        case "DoesNotContain":
            return !values.contains { $0.lowercased().contains(target) }
        case "StartsWith":
            return values.contains { $0.lowercased().hasPrefix(target) }
        case "EndsWith":
            return values.contains { $0.lowercased().hasSuffix(target) }
        case "IsTrue":
            return boolValue(of: game, key: filter.fieldKey) == true
        case "IsFalse":
            return boolValue(of: game, key: filter.fieldKey) == false
        case "GreaterThan":
            guard let lhs = values.compactMap({ Double($0) }).first, let rhs = Double(filter.value) else { return false }
            return lhs > rhs
        case "LessThan":
            guard let lhs = values.compactMap({ Double($0) }).first, let rhs = Double(filter.value) else { return false }
            return lhs < rhs
        default:
            return false
        }
    }

    private func boolValue(of game: Game, key: String) -> Bool? {
        switch key {
        case "Installed": return snapshot.isInstalled(game)
        case "Favorite": return game.favorite
        case "Completed": return game.completed
        case "Broken": return game.broken
        case "Hide", "Hidden": return game.hidden
        case "Portable": return game.portable
        default: return nil
        }
    }

    private func fieldValues(of game: Game, key: String) -> [String] {
        switch key {
        case "Series": return game.series
        case "Genre": return game.genres
        case "Title": return [game.title]
        case "SortTitle": return [game.sortTitle ?? game.title]
        case "Developer": return [game.developer ?? ""]
        case "Publisher": return [game.publisher ?? ""]
        case "Platform": return [game.platform]
        case "PlayMode": return [game.playMode ?? ""]
        case "Rating": return [game.rating ?? ""]
        case "Region": return [game.region ?? ""]
        case "Source": return [game.source ?? ""]
        case "Status": return [game.status ?? ""]
        case "ReleaseType": return [game.releaseType ?? ""]
        case "Version": return [game.version ?? ""]
        case "ReleaseYear": return [game.releaseYear.map { String($0) } ?? ""]
        case "PlayCount": return [String(game.playCount)]
        case "StarRating", "StarRatingFloat": return [String(game.starRating)]
        case "CommunityStarRating": return [game.communityStarRating.map { String($0) } ?? ""]
        case "MaxPlayers": return [game.maxPlayers.map { String($0) } ?? ""]
        case "Notes": return [game.notes ?? ""]
        case "AlternateName", "AlternateNames":
            return snapshot.alternateNames[game.id]?.map(\.name) ?? []
        default: return []
        }
    }
}

/// Folded search text for every game, built once per snapshot.
nonisolated public struct LibrarySearchIndex: Sendable {
    public let keys: [String: String]

    public init(snapshot: LibrarySnapshot) {
        let query = LibraryQuery(snapshot: snapshot)
        var keys: [String: String] = [:]
        keys.reserveCapacity(snapshot.games.count)
        for game in snapshot.games { keys[game.id] = query.searchText(for: game) }
        self.keys = keys
    }
}
