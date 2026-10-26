import Foundation

/// What an eXo download folder holds before (or after) its setup has run.
///
/// Every eXo pack ships the same way: `Content/!<pack>metadata.zip` with the
/// per-game launchers and configs, `Content/XO<pack>Metadata.zip` with the
/// box art and LaunchBox XML fragments, optional media add-ons such as
/// `Content/DOSBooks.zip`, per-game extras under `Content/GameData/`, and
/// the tools and emulators in `eXo/util/util*.zip`. Several packs copied
/// into one folder are set up together, as eXo's own setup merges them.
nonisolated public struct EXoDownload: Hashable, Sendable {
    nonisolated public struct Pack: Hashable, Sendable, Identifiable {
        /// The name in the archive, such as `DOS` or `Win9X`.
        public var name: String
        /// `Content/!<name>metadata.zip`.
        public var configArchive: URL
        /// True when the pack's extras come as `Content/GameData/<pack>/*.zip`.
        /// Other packs keep them in the config archive, under each game's
        /// `Extras` folder.
        public var hasGameData = false
        public var id: String { name }
        /// The name eXo uses for the pack, such as `eXoDOS` or `eXoWin9x`.
        public var displayName: String {
            EXoPack.allCases.first { $0.rawValue.caseInsensitiveCompare("eXo" + name) == .orderedSame }?.rawValue
                ?? "eXo" + name
        }
    }

    /// A media add-on zip and the platforms it brings.
    nonisolated public struct AddOn: Hashable, Sendable, Identifiable {
        public var archive: URL
        /// Platform names from the zip's `Data/Platforms/*.xml` files. Empty
        /// when the pack's metadata already lists the platform, as for
        /// eXoDemoScene's videos.
        public var platforms: [String]
        /// The sidebar category eXo files these platforms under.
        public var category: String
        public var size: Int64
        /// True for `Mag*.zip`, which eXo's older setup unpacks into `eXo/`.
        public var unpacksIntoEXo: Bool {
            archive.lastPathComponent.lowercased().hasPrefix("mag")
        }
        /// The platforms, or the kind of media when the zip names none.
        public var title: String {
            platforms.isEmpty
                ? EXoDownload.addOnKind(for: archive.lastPathComponent) : platforms.joined(separator: ", ")
        }
        public var id: URL { archive }
    }

    public let root: URL
    public var packs: [Pack]
    /// `Content/XO*Metadata.zip`: box art, manuals and XML fragments.
    public var metadataArchives: [URL]
    public var addOns: [AddOn]
    /// `Content/GameData/<pack>/<game>.zip`: each game's manual, music,
    /// videos and extras (eXoDOS only).
    public var gameDataArchives: [URL]
    /// `eXo/util/util*.zip`: tools, emulator files, MT-32 ROMs, updates.
    public var utilArchives: [URL]

    public var contentDirectory: URL { root.appendingPathComponent("Content", isDirectory: true) }

    /// `Content/LaunchBox.zip`: LaunchBox for Windows with its `Data`
    /// folder. Setup takes only `Data/Platforms.xml` and `Data/Parents.xml`
    /// from it, for packs whose metadata has no `merge_platforms.bat`, such
    /// as eXoWin3x.
    public var launchBoxArchive: URL? {
        let url = contentDirectory.appendingPathComponent("LaunchBox.zip")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// True when a setup has already written `Data/Platforms.xml` here.
    public var isSetUp: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("Data/Platforms.xml").path)
    }

    /// True when setup can write into the download itself.
    public var isWritable: Bool {
        FileManager.default.isWritableFile(atPath: root.path)
    }

    /// Bytes of the game extras archives.
    public var gameDataSize: Int64
    /// Unpacked bytes of the `Extras` folders in config archives of packs
    /// without GameData zips.
    public var packedExtrasSize: Int64 = 0
    /// Bytes of every game's manuals, music and extras, which setup can
    /// leave packed until a game is installed.
    public var extrasSize: Int64 { gameDataSize + packedExtrasSize }
    /// Bytes of the archives every setup unpacks: metadata, configs and
    /// tools. The unpacked size is close to this; most files are images.
    public var setupArchiveSize: Int64

    /// A quick check for `Content/!<pack>metadata.zip`, without reading archives.
    public static func hasPacks(_ root: URL) -> Bool {
        let content = root.appendingPathComponent("Content", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: content.path)) ?? []
        return names.contains { $0.hasPrefix("!") && $0.lowercased().hasSuffix("metadata.zip") }
    }

    /// A name for the collection, such as `eXoDOS` or `eXoDOS + eXoWin9x`.
    public var suggestedName: String {
        packs.map(\.displayName).joined(separator: " + ")
    }

    /// Reads the folder. Returns nil when it holds no eXo pack.
    public static func inspect(_ root: URL) async -> EXoDownload? {
        let fm = FileManager.default
        let content = root.appendingPathComponent("Content", isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: content.path) else { return nil }
        func zips(where predicate: (String) -> Bool) -> [URL] {
            names.filter { $0.lowercased().hasSuffix(".zip") && predicate($0) }.sorted()
                .map { content.appendingPathComponent($0) }
        }

        let gameDataRoot = content.appendingPathComponent("GameData", isDirectory: true)
        let packs = zips { $0.hasPrefix("!") && $0.lowercased().hasSuffix("metadata.zip") }.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            var pack = Pack(name: String(name.dropFirst().dropLast("metadata".count)), configArchive: url)
            pack.hasGameData = fm.fileExists(
                atPath: gameDataRoot.appendingPathComponent(pack.displayName, isDirectory: true).path)
            return pack
        }
        guard !packs.isEmpty else { return nil }
        let metadata = zips { $0.lowercased().hasPrefix("xo") && $0.lowercased().hasSuffix("metadata.zip") }

        var addOns: [AddOn] = []
        // DOS_linux_*.zip hold Linux launchers for the same media, not add-ons.
        for archive in zips(where: { name in
            addOnCategory(for: name) != nil && !name.hasPrefix("!") && !name.lowercased().contains("_linux_")
        }) {
            let entries = (try? await ZipArchive.entries(of: archive)) ?? []
            let platforms = entries.compactMap { entry -> String? in
                let parts = entry.split(separator: "/")
                guard parts.count == 3, parts[0] == "Data", parts[1] == "Platforms",
                    entry.lowercased().hasSuffix(".xml")
                else { return nil }
                return String(parts[2].dropLast(4))
            }
            guard let category = addOnCategory(for: archive.lastPathComponent) else { continue }
            addOns.append(
                AddOn(archive: archive, platforms: platforms, category: category, size: size(of: [archive])))
        }

        var gameData: [URL] = []
        for folder in (try? fm.contentsOfDirectory(atPath: gameDataRoot.path))?.sorted() ?? [] {
            let directory = gameDataRoot.appendingPathComponent(folder, isDirectory: true)
            for name in (try? fm.contentsOfDirectory(atPath: directory.path))?.sorted() ?? []
            where name.lowercased().hasSuffix(".zip") {
                gameData.append(directory.appendingPathComponent(name))
            }
        }

        let util = root.appendingPathComponent("eXo/util", isDirectory: true)
        let utilArchives = ((try? fm.contentsOfDirectory(atPath: util.path)) ?? [])
            .filter { $0.lowercased().hasPrefix("util") && $0.lowercased().hasSuffix(".zip") }.sorted()
            .map { util.appendingPathComponent($0) }

        // Packs without GameData zips keep each game's extras in the config
        // archive; their PDFs can be most of it.
        let packedExtras = packs.filter { !$0.hasGameData }.reduce(Int64(0)) {
            $0 + ZipArchive.unpackedSize(of: $1.configArchive, matching: "/Extras/")
        }
        var download = EXoDownload(
            root: root, packs: packs, metadataArchives: metadata, addOns: addOns, gameDataArchives: gameData,
            utilArchives: utilArchives, gameDataSize: size(of: gameData),
            setupArchiveSize: max(0, size(of: packs.map(\.configArchive) + metadata + utilArchives) - packedExtras))
        download.packedExtrasSize = packedExtras
        return download
    }

    /// eXo's setup registers add-on platforms under these categories.
    static func addOnCategory(for archiveName: String) -> String? {
        switch addOnKind(for: archiveName) {
        case "Books", "Catalogs", "Magazines": return "Literature"
        case "Soundtracks": return "Audio"
        case "Videos": return "Video"
        default: return nil
        }
    }

    /// The kind of media an add-on zip holds, from its name: `DOSBooks.zip`,
    /// `IFMagazines.zip`, `Mag!AppleIIGS.zip`, `DSNVideos.zip`.
    static func addOnKind(for archiveName: String) -> String {
        let name = archiveName.lowercased()
        for kind in ["Books", "Catalogs", "Magazines", "Soundtracks", "Videos"]
        where name.hasSuffix(kind.lowercased() + ".zip") {
            return kind
        }
        return name.hasPrefix("mag") ? "Magazines" : ""
    }

    static func size(of urls: [URL]) -> Int64 {
        urls.reduce(0) { total, url in
            total + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }
    }
}
