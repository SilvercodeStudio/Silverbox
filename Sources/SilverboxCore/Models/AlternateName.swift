import Foundation

/// An alternate title for a game, often a regional release name.
nonisolated public struct AlternateName: Hashable, Sendable, Codable {
    public var gameID: String
    public var name: String
    public var region: String?

    public init(gameID: String, name: String, region: String? = nil) {
        self.gameID = gameID
        self.name = name
        self.region = region
    }
}

/// A LaunchBox "additional application" attached to a game.
nonisolated public struct AdditionalApplication: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var gameID: String
    public var name: String
    public var applicationPath: String
    public var commandLine: String?
    public var autoRunBefore: Bool
    public var autoRunAfter: Bool
    public var waitForExit: Bool
    public var playCount: Int
    public var playTimeSeconds: Int

    public init(
        id: String, gameID: String, name: String, applicationPath: String, commandLine: String? = nil,
        autoRunBefore: Bool = false, autoRunAfter: Bool = false, waitForExit: Bool = false,
        playCount: Int = 0, playTimeSeconds: Int = 0
    ) {
        self.id = id
        self.gameID = gameID
        self.name = name
        self.applicationPath = applicationPath
        self.commandLine = commandLine
        self.autoRunBefore = autoRunBefore
        self.autoRunAfter = autoRunAfter
        self.waitForExit = waitForExit
        self.playCount = playCount
        self.playTimeSeconds = playTimeSeconds
    }
}
