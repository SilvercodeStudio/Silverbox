import Foundation

/// LaunchBox's media file naming: `<sanitized title>[.<game id>]-<NN>.<ext>`,
/// optionally inside a region sub-folder.
nonisolated public enum MediaFileName {
    /// Characters LaunchBox replaces with `_` when it derives file names from
    /// titles. Verified against eXoDOS: `Ultima V: Warriors of Destiny` becomes
    /// `Ultima V_ Warriors of Destiny`, `D/Generation` becomes `D_Generation`,
    /// and `Vampire's Castle` becomes `Vampire_s Castle`.
    public static let replacedCharacters: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", "'"]

    public static func sanitize(_ title: String) -> String {
        String(title.map { replacedCharacters.contains($0) ? "_" : $0 })
    }

    /// The parts of a media file stem such as `Jeopardy! Sports Edition.0501fe6c-abc7-4a24-aebd-1d50628823d1-01`.
    nonisolated public struct Parsed: Hashable, Sendable {
        public var key: String
        public var gameID: String?
        public var index: Int

        public init(key: String, gameID: String? = nil, index: Int = 0) {
            self.key = key
            self.gameID = gameID
            self.index = index
        }
    }

    nonisolated(unsafe) private static let guidPattern =
        #/^(?<key>.*?)(?:\.(?<guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}))?-(?<index>\d{2,3})$/#

    public static func parse(stem: String) -> Parsed {
        if let match = stem.wholeMatch(of: guidPattern) {
            return Parsed(key: String(match.key), gameID: match.guid.map(String.init), index: Int(match.index) ?? 0)
        }
        return Parsed(key: stem, gameID: nil, index: 0)
    }
}

/// One media file that belongs to a game.
nonisolated public struct MediaFile: Hashable, Sendable, Identifiable, Codable {
    public var url: URL
    public var region: String
    public var index: Int
    public var gameID: String?

    public var id: URL { url }

    public init(url: URL, region: String, index: Int, gameID: String? = nil) {
        self.url = url
        self.region = region
        self.index = index
        self.gameID = gameID
    }
}

/// An index of one media folder (for example `Images/MS-DOS/Box - Front`),
/// keyed by the lower-cased sanitized title.
nonisolated public struct MediaFolderIndex: Sendable, Codable {
    public let folder: URL
    public private(set) var filesByKey: [String: [MediaFile]]
    public let fileCount: Int
    /// The folder's modification date when it was scanned, used to decide
    /// whether a saved index is still current.
    public var modificationDate: Date?

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic",
    ]

    /// Region sub-folders in order of preference. The empty string is the
    /// folder root (files without a region).
    public static let regionPreference: [String] = [
        "north america", "", "world", "united states", "europe", "united kingdom",
        "canada", "oceania", "australia", "germany", "france", "japan",
    ]

    public init(folder: URL, filesByKey: [String: [MediaFile]], fileCount: Int, modificationDate: Date? = nil) {
        self.folder = folder
        self.filesByKey = filesByKey
        self.fileCount = fileCount
        self.modificationDate = modificationDate
    }

    public static func modificationDate(of folder: URL) -> Date? {
        (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Scans `folder` (and its region sub-folders) once.
    public static func scan(folder: URL, extensions: Set<String> = imageExtensions) -> MediaFolderIndex {
        let fm = FileManager.default
        var byKey: [String: [MediaFile]] = [:]
        var count = 0
        guard
            let enumerator = fm.enumerator(
                at: folder, includingPropertiesForKeys: [],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return MediaFolderIndex(folder: folder, filesByKey: [:], fileCount: 0)
        }
        let basePath = folder.standardizedFileURL.path
        for case let url as URL in enumerator {
            // Anything with an image extension is taken as a file; checking
            // each entry's type would cost a stat per file on slow volumes.
            let ext = url.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            let parent = url.deletingLastPathComponent().standardizedFileURL.path
            var region = parent.hasPrefix(basePath) ? String(parent.dropFirst(basePath.count)) : ""
            if region.hasPrefix("/") { region.removeFirst() }
            let parsed = MediaFileName.parse(stem: url.deletingPathExtension().lastPathComponent)
            let file = MediaFile(url: url, region: region, index: parsed.index, gameID: parsed.gameID?.lowercased())
            byKey[parsed.key.lowercased(), default: []].append(file)
            count += 1
        }
        return MediaFolderIndex(
            folder: folder, filesByKey: byKey, fileCount: count, modificationDate: modificationDate(of: folder))
    }

    /// Files for a game, best first: exact game-ID matches win over plain
    /// title matches, then preferred regions, then the lowest index. With no
    /// file named after the title, files named after the ROM file
    /// (`fileName`, the launcher's base name) count, as LaunchBox does;
    /// scrapers such as Skraper name media that way.
    public func files(forTitle title: String, gameID: String, fileName: String? = nil) -> [MediaFile] {
        let key = MediaFileName.sanitize(title).lowercased()
        if let candidates = filesByKey[key], !candidates.isEmpty {
            let id = gameID.lowercased()
            let exact = candidates.filter { $0.gameID == id }
            let chosen = exact.isEmpty ? candidates.filter { $0.gameID == nil } : exact
            return chosen.sorted(by: Self.preferred)
        }
        guard let fileName, !fileName.isEmpty else { return [] }
        // A ROM name that ends in "-01" was indexed without that suffix.
        for stem in [fileName.lowercased(), MediaFileName.parse(stem: fileName).key.lowercased()] {
            if let candidates = filesByKey[stem], !candidates.isEmpty {
                return candidates.filter { $0.gameID == nil }.sorted(by: Self.preferred)
            }
        }
        return []
    }

    static func preferred(_ a: MediaFile, _ b: MediaFile) -> Bool {
        let ra = regionRank(a.region)
        let rb = regionRank(b.region)
        if ra != rb { return ra < rb }
        if a.index != b.index { return a.index < b.index }
        return a.url.path < b.url.path
    }

    static func regionRank(_ region: String) -> Int {
        let lowered = region.lowercased()
        if let rank = regionPreference.firstIndex(of: lowered) { return rank }
        return regionPreference.count + (lowered.isEmpty ? 0 : 1)
    }
}

/// An index of files that are named after the launcher, such as
/// `Videos/MS-DOS/Ultima V - Warriors of Destiny (1988).mp4`.
nonisolated public struct StemIndex: Sendable {
    public let folder: URL
    public private(set) var urlsByStem: [String: [URL]]

    public init(folder: URL, urlsByStem: [String: [URL]]) {
        self.folder = folder
        self.urlsByStem = urlsByStem
    }

    public static func scan(folder: URL, extensions: Set<String>) -> StemIndex {
        let fm = FileManager.default
        var byStem: [String: [URL]] = [:]
        if let entries = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        {
            for url in entries where extensions.contains(url.pathExtension.lowercased()) {
                byStem[url.deletingPathExtension().lastPathComponent.lowercased(), default: []].append(url)
            }
        }
        for key in byStem.keys { byStem[key]?.sort { $0.lastPathComponent < $1.lastPathComponent } }
        return StemIndex(folder: folder, urlsByStem: byStem)
    }

    public func url(forStem stem: String) -> URL? {
        urlsByStem[stem.lowercased()]?.first
    }

    /// Every file with this stem, in name order.
    public func urls(forStem stem: String) -> [URL] {
        urlsByStem[stem.lowercased()] ?? []
    }
}

/// Saves folder indexes as JSON so later launches skip the slow scans.
nonisolated public struct MediaIndexStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load(folder: URL) -> MediaFolderIndex? {
        let url = fileURL(for: folder)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(MediaFolderIndex.self, from: data) else { return nil }
        guard index.folder.standardizedFileURL.path == folder.standardizedFileURL.path else { return nil }
        let current = MediaFolderIndex.modificationDate(of: folder)
        guard let saved = index.modificationDate, let current,
            abs(saved.timeIntervalSince(current)) < 1
        else { return nil }
        return index
    }

    public func save(_ index: MediaFolderIndex) {
        guard index.modificationDate != nil else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(index) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: index.folder), options: [.atomic])
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    func fileURL(for folder: URL) -> URL {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in folder.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".json")
    }
}
