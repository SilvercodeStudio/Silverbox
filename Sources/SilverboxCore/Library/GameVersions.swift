import Foundation

/// Finds the other versions of a game in the loaded collections: the same
/// game in eXoDOS, eXoScummVM and eXoIF, or its floppy and CD-ROM releases.
/// Two games match when their titles are the same once case, accents,
/// punctuation, a leading article and a note in brackets at the end are
/// left out, and they share a word of their developer or publisher names
/// (or the LaunchBox database id). The names keep apart different games
/// with a common title, such as "Deadline" or "Balance".
nonisolated public struct GameVersionIndex: Sendable {
    /// Game ids by title key.
    private let groups: [String: [String]]
    private let titleKeys: [String: String]
    private let nameWords: [String: Set<String>]

    public init(library: Library) {
        var groups: [String: [String]] = [:]
        var titleKeys: [String: String] = [:]
        var nameWords: [String: Set<String>] = [:]
        for game in library.games where Self.isPlayable(game) {
            let key = Self.titleKey(game.title)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(game.id)
            titleKeys[game.id] = key
            nameWords[game.id] = Self.nameWords(game.developer).union(Self.nameWords(game.publisher))
        }
        self.groups = groups.filter { $0.value.count > 1 }
        self.titleKeys = titleKeys
        self.nameWords = nameWords
    }

    /// The other versions of `game`, ordered by pack or platform, then year.
    public func otherVersions(of game: Game, in library: Library) -> [Game] {
        guard let key = titleKeys[game.id], let ids = groups[key] else { return [] }
        let words = nameWords[game.id] ?? []
        return
            ids
            .filter { $0 != game.id }
            .compactMap { library.game(id: $0) }
            .filter { other in
                if let id = game.databaseID, id == other.databaseID { return true }
                return !words.isDisjoint(with: nameWords[other.id] ?? [])
            }
            .sorted {
                (Self.source(of: $0), $0.releaseYear ?? 0, $0.title) < (
                    Self.source(of: $1), $1.releaseYear ?? 0, $1.title
                )
            }
    }

    /// Where a version comes from: its eXo pack, else its platform.
    public static func source(of game: Game) -> String {
        game.eXoPack?.displayName ?? game.platform
    }

    /// Games, not the manuals, magazines, soundtracks and videos beside them.
    static func isPlayable(_ game: Game) -> Bool {
        guard !game.isEXoSetupScript else { return false }
        switch game.launchKind {
        case .document, .link, .soundtrack, .video: return false
        default: return true
        }
    }

    /// "The Adventures of Robin Hood (CD-ROM)" and "Adventures of Robin
    /// Hood" give the same key.
    static func titleKey(_ title: String) -> String {
        var title = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        while title.hasSuffix(")"), let open = title.lastIndex(of: "("), open > title.startIndex {
            title = String(title[..<open]).trimmingCharacters(in: .whitespaces)
        }
        title = title.replacingOccurrences(of: "][", with: " ii ")
            .replacingOccurrences(of: "&", with: " and ")
        var words: [String] = []
        var word = ""
        for character in title {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else if character == "'" || character == "’" || character == "`" {
                continue  // "Pepper's" and "Peppers" are the same.
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        if words.count > 1, ["the", "a", "an"].contains(words[0]) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// The distinctive words of a developer or publisher name: "Level 9
    /// Computing, Ltd." gives "level", and "Freeware" gives nothing.
    static func nameWords(_ name: String?) -> Set<String> {
        guard let name else { return [] }
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return Set(words.filter { $0.count >= 3 && !commonNameWords.contains($0) })
    }

    private static let commonNameWords: Set<String> = [
        "the", "and", "inc", "ltd", "llc", "corp", "corporation", "company", "software", "games", "game",
        "entertainment", "interactive", "productions", "production", "studios", "studio", "limited", "gmbh",
        "computing", "systems", "publishing", "soft", "media", "international", "group", "team", "unknown",
        "computer", "computers", "design", "designs", "development", "presents", "plc", "srl", "freeware",
        "shareware", "public", "domain", "unpublished", "none", "line", "new",
    ]
}
