import Foundation

/// How an eXoIF version runs on the Mac.
nonisolated public enum IFRoute: Hashable, Sendable {
    /// An MS-DOS version: its DOSBox config, for DOSBox Staging or DOSBox-X.
    case dosBox(config: URL, dosboxX: Bool)
    /// A story file for a text-adventure interpreter, opened in Spatterlight.
    case storyFile(URL)
    /// No Mac route yet, with the system eXo runs it on.
    case unsupported(system: String)

    public var emulator: EmulatorKind? {
        switch self {
        case .dosBox(_, let dosboxX): return dosboxX ? .dosboxX : .dosboxStaging
        case .storyFile: return .spatterlight
        case .unsupported: return nil
        }
    }

    /// Lower is better, for choosing the default version: an interpreter
    /// first, then DOS.
    var preference: Int {
        switch self {
        case .storyFile: return 0
        case .dosBox: return 1
        case .unsupported: return 9
        }
    }
}

/// eXo's table in `launch_if.bat` that maps a version folder's name to the
/// emulator section that runs it:
///
///     "C64=C64"
///     "PC Booter=MSDOS"
///     "Lectrote=Lectrote"
nonisolated public struct IFSystemTable: Sendable, Hashable {
    public var labels: [String: String]

    public init(labels: [String: String] = [:]) {
        self.labels = labels
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self = Self.parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> IFSystemTable {
        var labels: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            guard let match = raw.firstMatch(of: /^\s*"([^"=]+)=([^"=]+)"\s*$/) else { continue }
            labels[String(match.1)] = String(match.2)
        }
        return IFSystemTable(labels: labels)
    }

    /// The emulator section for a version: its own folder first, then the
    /// folder above it, as eXo checks them.
    public func label(forFolders folders: [String]) -> String? {
        folders.lazy.compactMap { labels[$0] }.first
    }
}

/// Launching eXoIF games, following eXo's `launch_if.bat`.
nonisolated extension LaunchPlanner {
    /// eXo's emulator sections for text-adventure interpreters, which
    /// Spatterlight replaces.
    static let ifStoryLabels: Set<String> = [
        "WinFrotz", "Lectrote", "Gargoyle", "Glulxe", "HUGO", "TADS", "Level9", "Magnetic", "dMagnetic", "Adrift",
    ]

    /// `eXo/util/launch_if.bat`.
    public var ifLauncherFile: URL { snapshot.root.utilDirectory.appendingPathComponent("launch_if.bat") }

    /// The versions of an installed eXoIF game: each folder in it, and for a
    /// folder with a `menu.txt` (and no `ignoremenu.exo`), each folder
    /// inside that one. eXo writes `/` in folder names as `__`.
    public func ifVersions(for game: Game) -> [LaunchVariant] {
        guard let folder = snapshot.installedLocation(for: game)?.url else { return [] }
        let table = (try? IFSystemTable(contentsOf: ifLauncherFile)) ?? IFSystemTable()
        let fm = FileManager.default
        var versions: [LaunchVariant] = []
        // eXo often has the same story file under two interpreters, such as
        // Lectrote and WinFrotz; on the Mac both are Spatterlight.
        var storyFiles: Set<String> = []
        func add(_ url: URL, id: String, title: String, folders: [String]) {
            let route = ifRoute(folder: url, system: table.label(forFolders: folders), name: folders.first ?? "")
            var title = title
            var reason: String?
            switch route {
            case .unsupported(let system):
                reason = "\(system.replacingOccurrences(of: "__", with: "/")) is not supported on the Mac yet"
            case .storyFile(let file):
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard storyFiles.insert("\(file.lastPathComponent):\(size)").inserted else { return }
                // Name a version after its release or format, not the
                // Windows interpreter folder it came in.
                if folders.count > 1, table.labels[folders[0]].map(Self.ifStoryLabels.contains) == true {
                    title = folders[1]
                } else if folders.count == 1 {
                    title = Self.storyFormat(of: file)
                }
            case .dosBox:
                break
            }
            versions.append(
                LaunchVariant(
                    title: title.replacingOccurrences(of: "__", with: "/"), configURL: url, id: id,
                    unsupportedReason: reason, preference: route.preference))
        }
        for name in Self.subfolders(of: folder) {
            let top = folder.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: top.appendingPathComponent("menu.txt").path),
                !fm.fileExists(atPath: top.appendingPathComponent("ignoremenu.exo").path)
            {
                for sub in Self.subfolders(of: top) {
                    add(
                        top.appendingPathComponent(sub, isDirectory: true), id: "\(name)/\(sub)",
                        title: "\(name) › \(sub)", folders: [name, sub])
                }
            } else {
                add(top, id: name, title: name, folders: [name])
            }
        }
        return versions
    }

    /// A story file's format, for its version's name.
    static func storyFormat(of file: URL) -> String {
        let ext = file.pathExtension.lowercased()
        switch ext {
        case "z1", "z2", "z3", "z4", "z5", "z6", "z7", "z8", "zblorb", "zlb": return "Z-code story file"
        case "ulx", "gblorb", "glb": return "Glulx story file"
        case "gam", "t3": return "TADS story file"
        case "hex": return "Hugo story file"
        case "mag": return "Magnetic Scrolls story file"
        case "taf": return "Adrift story file"
        case "dat": return "Scott Adams story file"
        default: return ext.hasPrefix("l9") ? "Level 9 story file" : "Story file (.\(ext))"
        }
    }

    /// The file eXo starts in a version folder: the only file in it, else
    /// `dosbox.conf` or `dosbox-x.conf`, else the name in `launch.file`.
    static func ifLaunchFile(in folder: URL) -> URL? {
        let fm = FileManager.default
        let files =
            (fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .filter { $0.lastPathComponent != ".DS_Store" }
        if files.count == 1 { return files[0] }
        for name in ["dosbox.conf", "dosbox-x.conf"]
        where fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
            return folder.appendingPathComponent(name)
        }
        if let data = fm.contents(atPath: folder.appendingPathComponent("launch.file").path) {
            let name =
                String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !name.isEmpty { return WindowsPath.matchingCase(WindowsPath.resolve(name, against: folder)) }
        }
        return nil
    }

    /// How a version folder runs, from its system label and launch file.
    func ifRoute(folder: URL, system label: String?, name: String) -> IFRoute {
        guard let label else { return .unsupported(system: name) }
        let file = Self.ifLaunchFile(in: folder)
        if label == "MSDOS", let file, ["dosbox.conf", "dosbox-x.conf"].contains(file.lastPathComponent) {
            return .dosBox(config: file, dosboxX: file.lastPathComponent == "dosbox-x.conf")
        }
        if Self.ifStoryLabels.contains(label), let file {
            return .storyFile(file)
        }
        return .unsupported(system: label == "MSDOS" ? "This MS-DOS version" : name)
    }

    /// The route for a version, or for the default one.
    public func ifRoute(for game: Game, variant: LaunchVariant?) -> IFRoute? {
        let versions = ifVersions(for: game)
        guard
            let version = variant.flatMap({ v in versions.first { $0.id == v.id } }) ?? Self.defaultIFVersion(versions)
        else { return nil }
        let table = (try? IFSystemTable(contentsOf: ifLauncherFile)) ?? IFSystemTable()
        let folders = version.id.split(separator: "/").map(String.init)
        return ifRoute(folder: version.configURL, system: table.label(forFolders: folders), name: folders.first ?? "")
    }

    /// The best supported version, in eXo's order among equals.
    static func defaultIFVersion(_ versions: [LaunchVariant]) -> LaunchVariant? {
        versions.enumerated().min { a, b in
            (a.element.preference, a.offset) < (b.element.preference, b.offset)
        }?.element
    }

    public func planInteractiveFiction(
        game: Game, variant: LaunchVariant?, emulator: EmulatorInstallation, options: LaunchOptions
    ) throws -> LaunchPlan {
        guard let folderName = game.gameFolderName else { throw LaunchPlanError.missingGameFolder }
        guard let location = snapshot.installedLocation(for: game) else {
            throw LaunchPlanError.notInstalled(folderName: folderName)
        }
        let versions = ifVersions(for: game)
        guard
            let version = variant.flatMap({ v in versions.first { $0.id == v.id } })
                ?? Self.defaultIFVersion(versions),
            let route = ifRoute(for: game, variant: version)
        else { throw LaunchPlanError.notInstalled(folderName: folderName) }

        switch route {
        case .dosBox(let config, _):
            return try planDOSBox(
                game: game, pack: .interactiveFiction, variant: version, sourceURL: config, location: location,
                fallbackDirectories: [config.deletingLastPathComponent(), location.url], emulator: emulator,
                options: options)
        case .storyFile(let file):
            guard emulator.kind == .spatterlight else { throw LaunchPlanError.needsSpatterlight }
            guard emulator.exists, let app = emulator.appBundleURL else {
                throw LaunchPlanError.emulatorMissing(.spatterlight)
            }
            // Spatterlight opens files handed to it as documents, not as
            // arguments; `open -W` waits until it quits.
            let open = EmulatorInstallation(kind: .spatterlight, executableURL: URL(fileURLWithPath: "/usr/bin/open"))
            // There is no config to write; a note in the scratch folder
            // records what was opened. Never the story file itself.
            let note = scratchDirectory.appendingPathComponent(
                "\(Self.safeFileName(game.launchBoxID))-spatterlight.txt")
            return LaunchPlan(
                game: game, variant: version, emulator: open, arguments: ["-W", "-a", app.path, file.path],
                workingDirectory: file.deletingLastPathComponent(), configURL: note,
                configText: "Spatterlight opens \(file.path)\n", sourceConfigURL: file, notes: [])
        case .unsupported(let system):
            throw LaunchPlanError.ifVersionUnsupported(system)
        }
    }
}
