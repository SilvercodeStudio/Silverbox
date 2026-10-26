import Foundation

/// One audio file in a soundtrack album.
nonisolated public struct SoundtrackTrack: Hashable, Sendable, Identifiable {
    /// The entry's path inside the zip, or the file's path under the album folder.
    public var entry: String
    /// The track number parsed from the file name, when it has one.
    public var number: Int?
    /// The file name without its number and extension.
    public var title: String
    /// The unpacked file, when the album is unpacked.
    public var url: URL?

    public var id: String { entry }
    public var fileName: String { (entry as NSString).lastPathComponent }

    public init(entry: String, url: URL? = nil) {
        self.entry = entry
        self.url = url
        let base = ((entry as NSString).lastPathComponent as NSString).deletingPathExtension
        let parsed = SoundtrackLibrary.parse(trackName: base)
        number = parsed.number
        title = parsed.title
    }
}

/// A soundtrack entry of the eXoDOS library: a zip of audio tracks and a
/// cover image that eXoDOS plays with foobar2000. On the Mac it is unpacked
/// into the local data folder and played by the app.
nonisolated public struct SoundtrackAlbum: Hashable, Sendable {
    public var archiveURL: URL
    /// Where the album is, or will be, unpacked.
    public var folderURL: URL
    public var tracks: [SoundtrackTrack]
    public var coverURL: URL?
    public var isUnpacked: Bool
    /// The audio formats in the album, for example ["FLAC"] or ["MP3"].
    public var formats: [String]
    public var archiveSize: Int64?
}

nonisolated public enum SoundtrackLibrary {
    public static let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "wav", "aiff", "aif"]
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png"]

    /// The zip the LaunchBox entry hands to foobar2000, resolved against the
    /// entry's root folder: `"..\..\..\Soundtracks\Foo.zip"` under
    /// `eXo\emulators\audio\foobar2000` is `eXo\Soundtracks\Foo.zip`.
    public static func archiveURL(for game: Game, root: LibraryRoot) -> URL? {
        guard game.launchKind == .soundtrack, let commandLine = game.commandLine else { return nil }
        let argument = commandLine.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard argument.lowercased().hasSuffix(".zip") else { return nil }
        if WindowsPath.isAbsolute(argument) { return root.url(forWindowsRelativePath: argument) }
        let base =
            game.rootFolder ?? WindowsPath.components(of: game.applicationPath).dropLast().joined(separator: "\\")
        return root.url(forWindowsRelativePath: base.isEmpty ? argument : base + "\\" + argument)
    }

    /// The album's folder in the local data folder, named after the zip.
    public static func folderURL(for archiveURL: URL, localStore: LocalStore) -> URL {
        localStore.soundtracksDirectory.appendingPathComponent(
            archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
    }

    /// Reads the album from its unpacked folder when it exists, else from the
    /// zip's directory (without unpacking).
    public static func album(archiveURL: URL, localStore: LocalStore) async throws -> SoundtrackAlbum {
        let folder = folderURL(for: archiveURL, localStore: localStore)
        if let entries = try? FileManager.default.subpathsOfDirectory(atPath: folder.path), !entries.isEmpty {
            return album(archiveURL: archiveURL, folderURL: folder, entries: entries, unpacked: true)
        }
        let entries = try archiveEntries(of: archiveURL)
        return album(archiveURL: archiveURL, folderURL: folder, entries: entries, unpacked: false)
    }

    /// The entry names in a zip, from `unzip -Z1`.
    public static func archiveEntries(of archiveURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archiveURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.extractionFailed(status: process.terminationStatus, output: "unzip -Z1 failed")
        }
        return (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
    }

    /// Builds the album from entry names (zip entries or paths under the
    /// folder): audio files become tracks sorted by number, the first image
    /// is the cover. Hidden files such as `__MACOSX/._x` are skipped.
    public static func album(archiveURL: URL, folderURL: URL, entries: [String], unpacked: Bool) -> SoundtrackAlbum {
        var tracks: [SoundtrackTrack] = []
        var cover: URL?
        var formats: Set<String> = []
        for entry in entries where !entry.hasSuffix("/") {
            let name = (entry as NSString).lastPathComponent
            guard !name.hasPrefix("."), !entry.hasPrefix("__MACOSX") else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            if audioExtensions.contains(ext) {
                tracks.append(
                    SoundtrackTrack(entry: entry, url: unpacked ? folderURL.appendingPathComponent(entry) : nil))
                formats.insert(ext.uppercased())
            } else if imageExtensions.contains(ext), cover == nil, unpacked {
                cover = folderURL.appendingPathComponent(entry)
            }
        }
        tracks.sort { lhs, rhs in
            if let l = lhs.number, let r = rhs.number, l != r { return l < r }
            return lhs.entry.localizedStandardCompare(rhs.entry) == .orderedAscending
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: archiveURL.path))?[.size] as? Int64
        return SoundtrackAlbum(
            archiveURL: archiveURL, folderURL: folderURL, tracks: tracks, coverURL: cover, isUnpacked: unpacked,
            formats: formats.sorted(), archiveSize: size)
    }

    public static func unpack(_ album: SoundtrackAlbum) async throws {
        try await UnzipCommandExtractor().extract(archive: album.archiveURL, into: album.folderURL)
    }

    public static func remove(_ album: SoundtrackAlbum) throws {
        try FileManager.default.removeItem(at: album.folderURL)
    }

    /// "01 Chapel Pain" is track 1, "Chapel Pain"; "Track 3 - Foo" is 3,
    /// "Foo"; a name without a leading number keeps its text. Four or more
    /// digits are a year, not a number.
    public static func parse(trackName name: String) -> (number: Int?, title: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var rest = Substring(trimmed)
        if rest.lowercased().hasPrefix("track ") { rest = rest.dropFirst(6) }
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return (nil, trimmed) }
        let title = rest.dropFirst(digits.count).drop(while: { " -._)".contains($0) })
        return (number, title.isEmpty ? trimmed : String(title))
    }
}
