import Foundation

/// A game that Silverbox started and that may still run. Each launch is
/// recorded until its emulator quits, so a Silverbox that quit (or stopped)
/// while a game ran can protect that game's files again when it starts.
nonisolated public struct RunningGameRecord: Codable, Hashable, Sendable {
    public var id: UUID
    public var processIdentifier: Int32
    /// When the system started the process, in microseconds since 1970. It
    /// tells the emulator apart from a later process with the same number.
    public var processStart: Int64
    public var title: String
    /// The paths the launch reserved (``LaunchPlan/operationURLs``).
    public var paths: [String]

    public init(id: UUID, processIdentifier: Int32, processStart: Int64, title: String, paths: [String]) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.processStart = processStart
        self.title = title
        self.paths = paths
    }
}

/// The file of ``RunningGameRecord``s. It is kept beside the user's
/// favorites, not in the local data folder, which can move.
nonisolated public struct RunningGameLedger: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The records; none when the file is missing or damaged.
    public func load() -> [RunningGameRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RunningGameRecord].self, from: data)) ?? []
    }

    /// Writes the records, or removes the file when there are none.
    public func save(_ records: [RunningGameRecord]) throws {
        guard !records.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}
