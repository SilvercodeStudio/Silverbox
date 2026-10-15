import Foundation

/// Saves a parsed library so later launches skip re-reading hundreds of
/// megabytes of XML. A cache entry is used only while the data files it was
/// built from are unchanged.
nonisolated public struct LibraryCache: Sendable {
    public static let version = 3

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    nonisolated public struct Payload: Codable, Sendable {
        public var version: Int
        public var fingerprint: String
        public var games: [Game]
        public var platforms: [Platform]
        public var categories: [PlatformCategory]
        public var platformFolders: [PlatformFolder]
        public var playlists: [Playlist]
        public var parents: [ParentLink]
        public var alternateNames: [AlternateName]
        public var additionalApplications: [AdditionalApplication]
        public var dosboxIndexes: [EXoPack: DOSBoxIndex]
        public var emulators: [LaunchBoxEmulator]
        public var emulatorPlatforms: [LaunchBoxEmulatorPlatform]
    }

    /// Sizes and modification dates of every data file the loader reads.
    public static func fingerprint(for root: LibraryRoot) -> String {
        let fm = FileManager.default
        var files: [URL] =
            [root.platformsFile, root.parentsFile, root.emulatorsFile]
            + EXoPack.allCases.compactMap { root.dosboxIndexFile(for: $0) }
        for directory in [root.platformsDirectory, root.playlistsDirectory] {
            if let names = try? fm.contentsOfDirectory(atPath: directory.path) {
                files += names.sorted().filter { $0.lowercased().hasSuffix(".xml") }.map {
                    directory.appendingPathComponent($0)
                }
            }
        }
        var parts: [String] = ["v\(version)"]
        for file in files {
            guard let attributes = try? fm.attributesOfItem(atPath: file.path) else { continue }
            let size = (attributes[.size] as? Int) ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(file.lastPathComponent):\(size):\(Int(modified))")
        }
        return parts.joined(separator: "|")
    }

    public func load(collectionID: UUID, fingerprint: String) -> Payload? {
        let url = fileURL(for: collectionID)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
            payload.version == Self.version, payload.fingerprint == fingerprint
        else { return nil }
        return payload
    }

    public func save(_ payload: Payload, collectionID: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: collectionID), options: [.atomic])
    }

    public func remove(collectionID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: collectionID))
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    func fileURL(for collectionID: UUID) -> URL {
        directory.appendingPathComponent("\(collectionID.uuidString).json")
    }
}
