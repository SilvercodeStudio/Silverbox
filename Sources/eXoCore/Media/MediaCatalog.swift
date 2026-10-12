import Foundation

/// The LaunchBox image types eXoMAC shows, named by their folder.
nonisolated public enum ImageType: String, CaseIterable, Sendable, Codable, Hashable {
    case boxFront = "Box - Front"
    case boxFrontReconstructed = "Box - Front - Reconstructed"
    case boxBack = "Box - Back"
    case box3D = "Box - 3D"
    case boxFull = "Box - Full"
    case clearLogo = "Clear Logo"
    case screenshotGameTitle = "Screenshot - Game Title"
    case screenshotGameplay = "Screenshot - Gameplay"
    case screenshotGameSelect = "Screenshot - Game Select"
    case screenshotGameOver = "Screenshot - Game Over"
    case screenshotHighScores = "Screenshot - High Scores"
    case fanartBackground = "Fanart - Background"
    case fanartBoxFront = "Fanart - Box - Front"
    case banner = "Banner"
    case advertisementFlyerFront = "Advertisement Flyer - Front"
    case advertisementFlyerBack = "Advertisement Flyer - Back"
    case disc = "Disc"

    public var displayName: String {
        switch self {
        case .boxFront: return "Box front"
        case .boxFrontReconstructed: return "Box front (reconstructed)"
        case .boxBack: return "Box back"
        case .box3D: return "Box 3D"
        case .boxFull: return "Box full"
        case .clearLogo: return "Clear logo"
        case .screenshotGameTitle: return "Title screen"
        case .screenshotGameplay: return "Gameplay"
        case .screenshotGameSelect: return "Game select"
        case .screenshotGameOver: return "Game over"
        case .screenshotHighScores: return "High scores"
        case .fanartBackground: return "Fan art background"
        case .fanartBoxFront: return "Fan art box"
        case .banner: return "Banner"
        case .advertisementFlyerFront: return "Advertisement"
        case .advertisementFlyerBack: return "Advertisement back"
        case .disc: return "Disc"
        }
    }

    /// The order the grid tries when it needs one cover image.
    public static let coverFallbacks: [ImageType] = [
        .boxFront, .boxFrontReconstructed, .fanartBoxFront, .box3D, .screenshotGameTitle, .screenshotGameplay,
    ]

    /// The order the inspector shows in its filmstrip.
    public static let gallery: [ImageType] = [
        .boxFront, .screenshotGameTitle, .screenshotGameplay, .boxBack, .box3D, .clearLogo,
        .screenshotGameSelect, .screenshotHighScores, .screenshotGameOver, .disc,
        .advertisementFlyerFront, .fanartBackground, .banner,
    ]
}

/// A labelled media item for galleries.
nonisolated public struct GameMediaItem: Hashable, Sendable, Identifiable {
    nonisolated public enum Kind: Hashable, Sendable {
        case image(ImageType)
        case video
    }
    public var kind: Kind
    public var url: URL
    public var label: String
    public var id: URL { url }

    public init(kind: Kind, url: URL, label: String) {
        self.kind = kind
        self.url = url
        self.label = label
    }
}

/// A document in a game's `Extras` folder.
nonisolated public struct GameExtra: Hashable, Sendable, Identifiable {
    nonisolated public enum Kind: Hashable, Sendable {
        case pdf, image, text, archive, other
    }
    public var name: String
    public var url: URL
    public var kind: Kind
    public var id: URL { url }

    public init(name: String, url: URL, kind: Kind) {
        self.name = name
        self.url = url
        self.kind = kind
    }

    /// A light grouping for the Extras list: strategy guides and books go in
    /// one group, everything that shipped in the box in the other.
    public var isGuideBook: Bool {
        let lowered = name.lowercased()
        return [
            "guide", "atlas", "hint", "strategy", "walkthrough", "solution", "official book", "companion", "handbook",
            "secrets",
        ]
        .contains { lowered.contains($0) }
    }
}

/// Finds media files for games. Folder scans happen once and are cached.
public actor MediaCatalog {
    public let snapshot: LibrarySnapshot
    private var imageIndexes: [String: MediaFolderIndex] = [:]
    private var imageIndexTasks: [String: Task<MediaFolderIndex, Never>] = [:]
    private var stemIndexes: [String: StemIndex] = [:]
    private var stemIndexTasks: [String: Task<StemIndex, Never>] = [:]

    public static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "webm"]
    public static let manualExtensions: Set<String> = ["pdf", "txt", "cbz", "cbr", "html", "htm", "doc", "docx"]
    /// Music formats in order of preference when a game has several files:
    /// what macOS plays itself, then the bundled decoders (see ``MusicDecoders``),
    /// then formats that are listed but cannot be played.
    public static let musicPreference: [String] = [
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "oga", "xm", "it", "s3m", "mod", "amf", "voc",
    ]
    public static let musicExtensions: Set<String> = Set(musicPreference)

    /// Where scanned indexes are saved between launches, if anywhere.
    public let indexStore: MediaIndexStore?

    public init(snapshot: LibrarySnapshot, indexStore: MediaIndexStore? = nil) {
        self.snapshot = snapshot
        self.indexStore = indexStore
    }

    /// Scans a media folder once. Scans run off the actor so lookups for
    /// other folders are not blocked, and concurrent callers share one scan.
    private func imageIndex(for folder: URL) async -> MediaFolderIndex {
        let key = folder.path
        if let cached = imageIndexes[key] { return cached }
        if let task = imageIndexTasks[key] { return await task.value }
        let store = indexStore
        let task = Task.detached(priority: .userInitiated) {
            if let saved = store?.load(folder: folder) {
                MediaCatalog.log("loaded saved index of \(saved.fileCount) files for \(folder.lastPathComponent)")
                return saved
            }
            let start = Date()
            let index = MediaFolderIndex.scan(folder: folder)
            MediaCatalog.log(
                "scanned \(index.fileCount) files in \(folder.lastPathComponent) in \(String(format: "%.2f", Date().timeIntervalSince(start))) s"
            )
            store?.save(index)
            return index
        }
        imageIndexTasks[key] = task
        let index = await task.value
        imageIndexes[key] = index
        imageIndexTasks[key] = nil
        return index
    }

    private func stemIndex(for folder: URL, extensions: Set<String>) async -> StemIndex {
        let key = folder.path
        if let cached = stemIndexes[key] { return cached }
        if let task = stemIndexTasks[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { StemIndex.scan(folder: folder, extensions: extensions) }
        stemIndexTasks[key] = task
        let index = await task.value
        stemIndexes[key] = index
        stemIndexTasks[key] = nil
        return index
    }

    /// Starts scanning the folders the grid needs, so the first tiles do not
    /// wait on each other.
    public func prewarm(platforms: [String]) async {
        // One platform at a time, box fronts first and alone: on slow volumes
        // many concurrent scans contend with each other and the grid waits.
        for platform in platforms {
            let covers = snapshot.mediaFolder(platform: platform, mediaType: ImageType.boxFront.rawValue)
            _ = await imageIndex(for: covers)
            await withTaskGroup(of: Void.self) { group in
                for type in ImageType.coverFallbacks.dropFirst() {
                    let folder = snapshot.mediaFolder(platform: platform, mediaType: type.rawValue)
                    group.addTask { _ = await self.imageIndex(for: folder) }
                }
                for (mediaType, extensions) in [
                    ("Video", Self.videoExtensions), ("Manual", Self.manualExtensions), ("Music", Self.musicExtensions),
                ] {
                    let folder = snapshot.mediaFolder(platform: platform, mediaType: mediaType)
                    group.addTask { _ = await self.stemIndex(for: folder, extensions: extensions) }
                }
            }
        }
    }

    public func images(for game: Game, type: ImageType) async -> [MediaFile] {
        let folder = snapshot.mediaFolder(platform: game.platform, mediaType: type.rawValue)
        let index = await imageIndex(for: folder)
        return index.files(forTitle: game.title, gameID: game.launchBoxID)
    }

    /// The first image found, trying `types` in order.
    public func firstImage(for game: Game, types: [ImageType] = ImageType.coverFallbacks) async -> MediaFile? {
        for type in types {
            if let file = await images(for: game, type: type).first { return file }
        }
        return nil
    }

    public func video(for game: Game) async -> URL? {
        if let path = game.videoPath, let url = existing(snapshot.root.url(forWindowsRelativePath: path)) { return url }
        return await stemFile(for: game, mediaType: "Video", extensions: Self.videoExtensions)
    }

    public func manual(for game: Game) async -> URL? {
        if let path = game.manualPath, let url = existing(snapshot.root.url(forWindowsRelativePath: path)) {
            return url
        }
        return await stemFile(for: game, mediaType: "Manual", extensions: Self.manualExtensions)
    }

    public func music(for game: Game) async -> URL? {
        if let path = game.musicPath, let url = existing(snapshot.root.url(forWindowsRelativePath: path)) { return url }
        let folder = snapshot.mediaFolder(platform: game.platform, mediaType: "Music")
        let index = await stemIndex(for: folder, extensions: Self.musicExtensions)
        var candidates = index.urls(forStem: game.launcherBaseName)
        if candidates.isEmpty { candidates = index.urls(forStem: MediaFileName.sanitize(game.title)) }
        func rank(_ url: URL) -> Int {
            Self.musicPreference.firstIndex(of: url.pathExtension.lowercased()) ?? Self.musicPreference.count
        }
        return candidates.min { rank($0) < rank($1) }
    }

    /// Everything the inspector's filmstrip shows: the video first, then one
    /// image per type in gallery order.
    public func gallery(for game: Game) async -> [GameMediaItem] {
        // Start every folder scan at once; the loop below then only waits
        // for the slowest one instead of for each in turn.
        await withTaskGroup(of: Void.self) { group in
            for type in ImageType.gallery {
                let folder = snapshot.mediaFolder(platform: game.platform, mediaType: type.rawValue)
                group.addTask { _ = await self.imageIndex(for: folder) }
            }
            let videos = snapshot.mediaFolder(platform: game.platform, mediaType: "Video")
            group.addTask { _ = await self.stemIndex(for: videos, extensions: MediaCatalog.videoExtensions) }
        }
        var items: [GameMediaItem] = []
        if let video = await video(for: game) {
            items.append(GameMediaItem(kind: .video, url: video, label: "Video"))
        }
        for type in ImageType.gallery {
            let files = await images(for: game, type: type)
            for (offset, file) in files.prefix(4).enumerated() {
                let label = files.count > 1 ? "\(type.displayName) \(offset + 1)" : type.displayName
                items.append(GameMediaItem(kind: .image(type), url: file.url, label: label))
            }
        }
        return items
    }

    public func extras(for game: Game) -> [GameExtra] {
        guard let folder = game.rootFolder else { return [] }
        let extrasDirectory = snapshot.root.url(forWindowsRelativePath: folder).appendingPathComponent(
            "Extras", isDirectory: true)
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: extrasDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        return entries.compactMap { url -> GameExtra? in
            let ext = url.pathExtension.lowercased()
            guard ext != "bat", ext != "exe", ext != "cmd" else { return nil }
            let kind: GameExtra.Kind
            switch ext {
            case "pdf": kind = .pdf
            case "png", "jpg", "jpeg", "gif", "bmp", "webp", "tif", "tiff": kind = .image
            case "txt", "md", "doc", "rtf", "htm", "html": kind = .text
            case "zip", "7z", "rar", "cbz", "cbr": kind = .archive
            default: kind = .other
            }
            return GameExtra(name: url.deletingPathExtension().lastPathComponent, url: url, kind: kind)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func stemFile(for game: Game, mediaType: String, extensions: Set<String>) async -> URL? {
        let folder = snapshot.mediaFolder(platform: game.platform, mediaType: mediaType)
        let index = await stemIndex(for: folder, extensions: extensions)
        return index.url(forStem: game.launcherBaseName) ?? index.url(forStem: MediaFileName.sanitize(game.title))
    }

    private func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Timing output on stderr when `EXOMAC_LOG` is set in the environment.
    nonisolated static func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["EXOMAC_LOG"] != nil else { return }
        FileHandle.standardError.write(Data("media: \(message)\n".utf8))
    }
}
