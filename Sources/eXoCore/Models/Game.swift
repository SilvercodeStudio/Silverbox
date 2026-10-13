import Foundation

/// One LaunchBox game record, as found in `Data/Platforms/<Platform>.xml`.
///
/// Path fields keep LaunchBox's Windows-relative form (`eXo\eXoDOS\!dos\ultima5\...`).
/// Use ``LibraryRoot/url(forWindowsRelativePath:)`` to turn them into file URLs.
nonisolated public struct Game: Identifiable, Hashable, Sendable, Codable {
    /// LaunchBox's GUID for the game. Unique within a library, and the same
    /// game keeps it across copies of that library, so user state is keyed on it.
    public var launchBoxID: String
    /// The collection this record was loaded from.
    public var collectionID: UUID
    public var title: String
    public var sortTitle: String?
    public var platform: String
    public var developer: String?
    public var publisher: String?
    public var releaseDate: Date?
    public var genres: [String]
    public var series: [String]
    public var playMode: String?
    public var rating: String?
    public var starRating: Double
    public var communityStarRating: Double?
    public var communityStarRatingVotes: Int
    public var notes: String?
    public var applicationPath: String
    public var commandLine: String?
    public var configurationPath: String?
    public var configurationCommandLine: String?
    public var rootFolder: String?
    public var manualPath: String?
    public var musicPath: String?
    public var videoPath: String?
    public var dosBoxConfigurationPath: String?
    public var emulatorID: String?
    public var favorite: Bool
    public var installed: Bool
    public var completed: Bool
    public var hidden: Bool
    public var broken: Bool
    public var portable: Bool
    public var playCount: Int
    public var playTimeSeconds: Int
    public var lastPlayed: Date?
    public var dateAdded: Date?
    public var dateModified: Date?
    public var databaseID: Int?
    public var wikipediaURL: String?
    public var videoURL: String?
    public var source: String?
    public var status: String?
    public var region: String?
    public var version: String?
    public var releaseType: String?
    public var maxPlayers: Int?
    public var cloneOf: String?
    public var useDosBox: Bool
    public var useScummVM: Bool
    public var missingMedia: MissingMedia

    /// LaunchBox's cached "Missing…" flags. They are hints only; the media
    /// catalog checks the file system.
    nonisolated public struct MissingMedia: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let video = MissingMedia(rawValue: 1 << 0)
        public static let boxFront = MissingMedia(rawValue: 1 << 1)
        public static let screenshot = MissingMedia(rawValue: 1 << 2)
        public static let marquee = MissingMedia(rawValue: 1 << 3)
        public static let clearLogo = MissingMedia(rawValue: 1 << 4)
        public static let background = MissingMedia(rawValue: 1 << 5)
        public static let box3D = MissingMedia(rawValue: 1 << 6)
        public static let cart = MissingMedia(rawValue: 1 << 7)
        public static let cart3D = MissingMedia(rawValue: 1 << 8)
        public static let manual = MissingMedia(rawValue: 1 << 9)
        public static let banner = MissingMedia(rawValue: 1 << 10)
        public static let music = MissingMedia(rawValue: 1 << 11)
    }

    /// Marks a game not yet assigned to a collection; ``LibrarySnapshot`` fills it in.
    public static let unassignedCollection = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Unique across collections: the collection and the LaunchBox GUID.
    public var id: String { "\(collectionID.uuidString)/\(launchBoxID)" }

    public init(
        id: String,
        collectionID: UUID = Game.unassignedCollection,
        title: String,
        platform: String,
        applicationPath: String,
        sortTitle: String? = nil,
        developer: String? = nil,
        publisher: String? = nil,
        releaseDate: Date? = nil,
        genres: [String] = [],
        series: [String] = [],
        playMode: String? = nil,
        rating: String? = nil,
        starRating: Double = 0,
        communityStarRating: Double? = nil,
        communityStarRatingVotes: Int = 0,
        notes: String? = nil,
        commandLine: String? = nil,
        configurationPath: String? = nil,
        configurationCommandLine: String? = nil,
        rootFolder: String? = nil,
        manualPath: String? = nil,
        musicPath: String? = nil,
        videoPath: String? = nil,
        dosBoxConfigurationPath: String? = nil,
        emulatorID: String? = nil,
        favorite: Bool = false,
        installed: Bool = false,
        completed: Bool = false,
        hidden: Bool = false,
        broken: Bool = false,
        portable: Bool = false,
        playCount: Int = 0,
        playTimeSeconds: Int = 0,
        lastPlayed: Date? = nil,
        dateAdded: Date? = nil,
        dateModified: Date? = nil,
        databaseID: Int? = nil,
        wikipediaURL: String? = nil,
        videoURL: String? = nil,
        source: String? = nil,
        status: String? = nil,
        region: String? = nil,
        version: String? = nil,
        releaseType: String? = nil,
        maxPlayers: Int? = nil,
        cloneOf: String? = nil,
        useDosBox: Bool = false,
        useScummVM: Bool = false,
        missingMedia: MissingMedia = []
    ) {
        self.launchBoxID = id
        self.collectionID = collectionID
        self.title = title
        self.sortTitle = sortTitle
        self.platform = platform
        self.developer = developer
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.genres = genres
        self.series = series
        self.playMode = playMode
        self.rating = rating
        self.starRating = starRating
        self.communityStarRating = communityStarRating
        self.communityStarRatingVotes = communityStarRatingVotes
        self.notes = notes
        self.applicationPath = applicationPath
        self.commandLine = commandLine
        self.configurationPath = configurationPath
        self.configurationCommandLine = configurationCommandLine
        self.rootFolder = rootFolder
        self.manualPath = manualPath
        self.musicPath = musicPath
        self.videoPath = videoPath
        self.dosBoxConfigurationPath = dosBoxConfigurationPath
        self.emulatorID = emulatorID
        self.favorite = favorite
        self.installed = installed
        self.completed = completed
        self.hidden = hidden
        self.broken = broken
        self.portable = portable
        self.playCount = playCount
        self.playTimeSeconds = playTimeSeconds
        self.lastPlayed = lastPlayed
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.databaseID = databaseID
        self.wikipediaURL = wikipediaURL
        self.videoURL = videoURL
        self.source = source
        self.status = status
        self.region = region
        self.version = version
        self.releaseType = releaseType
        self.maxPlayers = maxPlayers
        self.cloneOf = cloneOf
        self.useDosBox = useDosBox
        self.useScummVM = useScummVM
        self.missingMedia = missingMedia
    }
}

nonisolated extension Game {
    /// The launcher file name without its extension, for example
    /// `Ultima V - Warriors of Destiny (1988)`. eXoDOS keys its DOSBox index,
    /// videos, manuals, music and game archives on this name.
    public var launcherBaseName: String {
        WindowsPath.baseName(of: applicationPath)
    }

    /// The last component of `RootFolder`, for example `ultima5`. eXoDOS uses
    /// it both for the config folder (`eXo/eXoDOS/!dos/<name>`) and for the
    /// installed game folder (`eXo/eXoDOS/<name>`).
    public var gameFolderName: String? {
        guard let rootFolder, !rootFolder.isEmpty else { return nil }
        let name = WindowsPath.lastComponent(of: rootFolder)
        return name.isEmpty ? nil : name
    }

    public var releaseYear: Int? {
        guard let releaseDate else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: releaseDate)
    }

    /// Series entries of the form `Playlist: X`, without the prefix.
    public var playlistTags: [String] {
        series.compactMap { Self.strip(prefix: "Playlist:", from: $0) }
    }

    /// Series entries of the form `Theme: X`, without the prefix.
    public var themeTags: [String] {
        series.compactMap { Self.strip(prefix: "Theme:", from: $0) }
    }

    /// Series entries that are neither playlist nor theme markers.
    public var seriesNames: [String] {
        series.filter {
            Self.strip(prefix: "Playlist:", from: $0) == nil && Self.strip(prefix: "Theme:", from: $0) == nil
        }
    }

    /// True when the launcher is an eXoDOS batch file in a `!dos` config
    /// folder. Other batch files, such as a plain DOS folder import, are not
    /// eXoDOS games and cannot be installed or translated the eXoDOS way.
    public var isDOSGame: Bool {
        guard applicationPath.lowercased().hasSuffix(".bat") else { return false }
        let folder = (rootFolder ?? applicationPath).lowercased()
        return folder.contains("\\!dos\\") || folder.contains("/!dos/") || folder.hasSuffix("\\!dos")
            || folder.contains("exo\\exodos\\")
    }

    /// How the item starts: in DOSBox, in another emulator, in a document
    /// viewer, or not at all.
    public var launchKind: GameLaunchKind {
        if isDOSGame { return .dosBox }
        let path = applicationPath.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { return .windowsProgram }
        if path.range(of: "://") != nil { return .link }
        if commandLine?.lowercased().contains(".zip") == true,
            WindowsPath.lastComponent(of: path).lowercased() == "foobar2000.exe"
                || platform.caseInsensitiveCompare("Soundtracks") == .orderedSame
        {
            return .soundtrack
        }
        let ext = WindowsPath.fileExtension(of: path)?.lowercased() ?? ""
        if ext == "bat", isVideoLauncher { return .video }
        if Self.documentExtensions.contains(ext) { return .document }
        if Self.windowsProgramExtensions.contains(ext) { return .windowsProgram }
        return .emulator
    }

    /// True for a launcher under `eXo\Videos` or on a videos platform, such
    /// as `MS-DOS Videos`.
    private var isVideoLauncher: Bool {
        platform.range(of: "videos", options: .caseInsensitive) != nil
            || WindowsPath.components(of: applicationPath).dropLast().contains {
                $0.caseInsensitiveCompare("Videos") == .orderedSame
            }
    }

    /// Files that open in their default app instead of an emulator.
    public static let documentExtensions: Set<String> = [
        "pdf", "txt", "cbz", "cbr", "epub", "html", "htm", "mp3", "ogg", "flac",
        "m4a", "wav", "mp4", "mkv", "avi", "mov", "jpg", "jpeg", "png", "gif",
    ]
    public static let windowsProgramExtensions: Set<String> = ["exe", "bat", "cmd", "lnk", "url", "msi", "com"]

    /// The key used for sorting: LaunchBox's `SortTitle` when present.
    public var sortKey: String {
        let base = (sortTitle?.isEmpty == false ? sortTitle! : title)
        return base.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func strip(prefix: String, from value: String) -> String? {
        guard value.hasPrefix(prefix) else { return nil }
        let rest = value.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}

nonisolated public enum GameLaunchKind: Sendable, Hashable {
    /// An eXoDOS game, run through the translated DOSBox config.
    case dosBox
    /// A ROM, disc image or folder for a platform emulator.
    case emulator
    /// A manual, magazine, soundtrack or video opened in its own app.
    case document
    /// A web or Steam link.
    case link
    /// A Windows program or script with no Mac equivalent.
    case windowsProgram
    /// A soundtrack album: a zip of audio tracks that eXoDOS opens in foobar2000.
    case soundtrack
    /// A video or a menu of videos: a batch file that eXoDOS uses to start VLC.
    case video
}
