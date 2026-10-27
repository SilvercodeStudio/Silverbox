import Foundation

/// Per-game changes the user makes in Silverbox. They are kept outside the
/// LaunchBox XML so the eXoDOS install stays untouched.
nonisolated public struct GameUserState: Hashable, Sendable, Codable {
    public var favorite: Bool?
    public var completed: Bool?
    public var hidden: Bool?
    public var broken: Bool?
    public var playCount: Int
    public var playTimeSeconds: Int
    public var lastPlayed: Date?
    public var emulatorOverride: EmulatorKind?
    public var preferredVariantID: String?
    public var launchOverrides: LaunchOverrides?
    /// Choices such as the music device, for games whose launcher asks.
    public var launchChoices: LaunchChoices?

    public init(
        favorite: Bool? = nil, completed: Bool? = nil, hidden: Bool? = nil, broken: Bool? = nil,
        playCount: Int = 0, playTimeSeconds: Int = 0, lastPlayed: Date? = nil,
        emulatorOverride: EmulatorKind? = nil, preferredVariantID: String? = nil,
        launchOverrides: LaunchOverrides? = nil, launchChoices: LaunchChoices? = nil
    ) {
        self.favorite = favorite
        self.completed = completed
        self.hidden = hidden
        self.broken = broken
        self.playCount = playCount
        self.playTimeSeconds = playTimeSeconds
        self.lastPlayed = lastPlayed
        self.emulatorOverride = emulatorOverride
        self.preferredVariantID = preferredVariantID
        self.launchOverrides = launchOverrides
        self.launchChoices = launchChoices
    }

    public var isEmpty: Bool {
        favorite == nil && completed == nil && hidden == nil && broken == nil
            && playCount == 0 && playTimeSeconds == 0 && lastPlayed == nil
            && emulatorOverride == nil && preferredVariantID == nil
            && (launchOverrides?.isEmpty ?? true) && (launchChoices?.isEmpty ?? true)
    }
}

nonisolated public struct UserLibraryState: Hashable, Sendable, Codable {
    public static let currentVersion = 1

    public var version: Int
    public var games: [String: GameUserState]

    public init(version: Int = UserLibraryState.currentVersion, games: [String: GameUserState] = [:]) {
        self.version = version
        self.games = games
    }

    public func state(for gameID: String) -> GameUserState {
        games[gameID] ?? GameUserState()
    }

    /// The user's favorite, which is never one of eXo's picks unless the
    /// user chose it (``Game/isEXoFavorite``).
    public func isFavorite(_ game: Game) -> Bool {
        state(for: game.launchBoxID).favorite ?? game.isFavoriteByDefault
    }

    public mutating func update(_ gameID: String, _ change: (inout GameUserState) -> Void) {
        var state = games[gameID] ?? GameUserState()
        change(&state)
        if state.isEmpty {
            games.removeValue(forKey: gameID)
        } else {
            games[gameID] = state
        }
    }

    /// Records one finished play session.
    public mutating func recordPlay(_ gameID: String, seconds: Int, endedAt: Date = Date()) {
        update(gameID) { state in
            state.playCount += 1
            state.playTimeSeconds += max(0, seconds)
            state.lastPlayed = Date(timeIntervalSince1970: endedAt.timeIntervalSince1970.rounded(.down))
        }
    }
}

/// Reads and writes ``UserLibraryState`` as JSON.
nonisolated public struct UserLibraryStateStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var previousURL: URL { url.appendingPathExtension("previous") }

    public func load() throws -> UserLibraryState {
        guard FileManager.default.fileExists(atPath: url.path) else { return UserLibraryState() }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserLibraryState.self, from: data)
    }

    /// Preserve an unreadable original before allowing subsequent changes.
    /// If preservation fails, callers must keep saving disabled.
    public func loadRecovering() throws -> UserStateRecovery {
        do {
            return UserStateRecovery(state: try load(), preservedURL: nil)
        } catch {
            let preserved = url.deletingLastPathComponent()
                .appendingPathComponent("user-library-unreadable-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: preserved)
            let previous = try? UserLibraryStateStore(url: previousURL).load()
            return UserStateRecovery(state: previous ?? UserLibraryState(), preservedURL: preserved)
        }
    }

    public func save(_ state: UserLibraryState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep one known-readable generation. Never replace it with a damaged
        // original that loadRecovering has just preserved separately.
        if (try? load()) != nil, let old = try? Data(contentsOf: url) {
            try old.write(to: previousURL, options: .atomic)
        }
        try data.write(to: url, options: [.atomic])
    }
}

nonisolated public struct UserStateRecovery: Sendable {
    public let state: UserLibraryState
    public let preservedURL: URL?
}

/// Debounced callers enqueue immediately; every flush writes the latest
/// pending state under one lock. An older task can never write an old snapshot
/// after a newer flush. Failed writes remain pending for retry or shutdown.
nonisolated public final class UserLibraryStatePersistence: @unchecked Sendable {
    private let lock = NSLock()
    private let store: UserLibraryStateStore
    private var pending: UserLibraryState?
    private var loaded = false

    public init(store: UserLibraryStateStore) { self.store = store }

    public func load() throws -> UserStateRecovery {
        lock.lock()
        defer { lock.unlock() }
        let result = try store.loadRecovering()
        loaded = true
        return result
    }

    public func enqueue(_ state: UserLibraryState) {
        lock.lock()
        defer { lock.unlock() }
        pending = state
    }

    public func flush() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let pending else { return }
        guard loaded else { throw UserStatePersistenceError.originalNotPreserved }
        try store.save(pending)
        self.pending = nil
    }
}

nonisolated public enum UserStatePersistenceError: Error, LocalizedError, Sendable {
    case originalNotPreserved
    public var errorDescription: String? {
        "The existing favorites and play history could not be read or preserved. Saving is disabled to protect the original file."
    }
}
