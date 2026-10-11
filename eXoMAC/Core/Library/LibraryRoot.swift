import Foundation

/// The folder that holds an eXoDOS (LaunchBox-format) installation, and the
/// well-known places inside it.
nonisolated public struct LibraryRoot: Hashable, Sendable, Codable {
    public let url: URL

    public init(url: URL) {
        self.url = url.standardizedFileURL
    }

    public var dataDirectory: URL { url.appendingPathComponent("Data", isDirectory: true) }
    public var platformsDirectory: URL { dataDirectory.appendingPathComponent("Platforms", isDirectory: true) }
    public var playlistsDirectory: URL { dataDirectory.appendingPathComponent("Playlists", isDirectory: true) }
    public var platformsFile: URL { dataDirectory.appendingPathComponent("Platforms.xml") }
    public var parentsFile: URL { dataDirectory.appendingPathComponent("Parents.xml") }
    public var imagesDirectory: URL { url.appendingPathComponent("Images", isDirectory: true) }
    public var videosDirectory: URL { url.appendingPathComponent("Videos", isDirectory: true) }
    public var manualsDirectory: URL { url.appendingPathComponent("Manuals", isDirectory: true) }
    public var musicDirectory: URL { url.appendingPathComponent("Music", isDirectory: true) }

    /// `eXo/`: the working directory eXoDOS's launchers run DOSBox from.
    public var eXoDirectory: URL { url.appendingPathComponent("eXo", isDirectory: true) }
    /// `eXo/eXoDOS/`: game archives (`<name>.zip`) and installed game folders.
    public var gamesDirectory: URL { eXoDirectory.appendingPathComponent("eXoDOS", isDirectory: true) }
    /// `eXo/eXoDOS/!dos/`: per-game launcher, config and extras folders.
    public var gameConfigsDirectory: URL { gamesDirectory.appendingPathComponent("!dos", isDirectory: true) }
    public var emulatorsDirectory: URL { eXoDirectory.appendingPathComponent("emulators", isDirectory: true) }
    public var utilDirectory: URL { eXoDirectory.appendingPathComponent("util", isDirectory: true) }
    public var mt32Directory: URL { eXoDirectory.appendingPathComponent("mt32", isDirectory: true) }
    public var updateDirectory: URL { eXoDirectory.appendingPathComponent("Update", isDirectory: true) }
    /// `eXo/util/dosbox.txt`: maps each game to the DOSBox build eXoDOS uses.
    public var dosboxIndexFile: URL { utilDirectory.appendingPathComponent("dosbox.txt") }

    /// Resolves a LaunchBox path such as `Manuals\MS-DOS\Foo.pdf` to a file URL.
    public func url(forWindowsRelativePath path: String) -> URL {
        if WindowsPath.isAbsolute(path) {
            return URL(fileURLWithPath: WindowsPath.posix(path)).standardizedFileURL
        }
        return WindowsPath.resolve(path, against: url)
    }

    public func platformFile(named platform: String) -> URL {
        platformsDirectory.appendingPathComponent("\(platform).xml")
    }

    /// Checks which of the expected folders and files exist.
    public func inspect() -> LibraryRootReport {
        let fm = FileManager.default
        func check(_ label: String, _ target: URL) -> LibraryRootReport.Item {
            var isDirectory: ObjCBool = false
            let exists = fm.fileExists(atPath: target.path, isDirectory: &isDirectory)
            let relative = target.path.replacingOccurrences(of: url.path + "/", with: "")
            return LibraryRootReport.Item(label: label, relativePath: relative, exists: exists)
        }
        let items = [
            check("Platform list", platformsFile),
            check("Game metadata", platformsDirectory),
            check("Playlists", playlistsDirectory),
            check("Box art and screenshots", imagesDirectory),
            check("Videos", videosDirectory),
            check("Manuals", manualsDirectory),
            check("Menu music", musicDirectory),
            check("Game archives and folders", gamesDirectory),
            check("Game launch configs", gameConfigsDirectory),
            check("DOSBox build index", dosboxIndexFile),
            check("MT-32 ROMs and SoundFont", mt32Directory),
        ]
        return LibraryRootReport(root: self, items: items)
    }
}

nonisolated public struct LibraryRootReport: Hashable, Sendable {
    nonisolated public struct Item: Hashable, Sendable, Identifiable {
        public var label: String
        public var relativePath: String
        public var exists: Bool
        public var id: String { relativePath }
    }

    public var root: LibraryRoot
    public var items: [Item]

    /// The minimum needed to show a library: the platform list and game metadata.
    public var isUsable: Bool {
        items.first(where: { $0.label == "Platform list" })?.exists == true
            && items.first(where: { $0.label == "Game metadata" })?.exists == true
    }
}
