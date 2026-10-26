import Foundation

/// How an eXoIF version runs on the Mac.
nonisolated public enum IFRoute: Hashable, Sendable {
    /// An MS-DOS version: its DOSBox config, for DOSBox Staging or DOSBox-X.
    case dosBox(config: URL, dosboxX: Bool)
    /// A story file for a text-adventure interpreter, opened in Spatterlight.
    case storyFile(URL)
    /// A disk, tape or program for an 8-bit computer, in a RetroArch core.
    case retroArch(core: String, file: URL)
    /// No Mac route yet, with the system eXo runs it on.
    case unsupported(system: String)

    public var emulator: EmulatorKind? {
        switch self {
        case .dosBox(_, let dosboxX): return dosboxX ? .dosboxX : .dosboxStaging
        case .storyFile: return .spatterlight
        case .retroArch: return .retroArch
        case .unsupported: return nil
        }
    }

    /// Lower is better, for choosing the default version: an interpreter
    /// first, then DOS.
    var preference: Int {
        switch self {
        case .storyFile: return 0
        case .dosBox: return 1
        case .retroArch: return 2
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

    /// The RetroArch core for each of eXo's emulator sections that one can
    /// replace. Most have the machine's ROMs built in.
    static let ifRetroArchCores: [String: String] = [
        "C64": "vice_x64sc", "C128": "vice_x128", "VIC20": "vice_xvic", "PLUS4": "vice_xplus4", "PET": "vice_xpet",
        "ZXSpectrum": "fuse", "ZX81": "81", "TS1000": "81", "APPLEII": "applewin", "CPC": "cap32",
        "AMIGA": "puae", "Atari8": "atari800",
    ]

    /// ROMs a core needs in RetroArch's system folder, which eXo does not ship.
    static let ifRetroArchSystemFiles: [String: (file: String, description: String)] = [
        "puae": ("kick34005.A500", "the Amiga Kickstart 1.3 ROM")
    ]

    /// ROMs eXo ships for its own emulator that a core can use: the folder
    /// under `eXo/emulators` (by prefix), and each file with the name the
    /// core looks for. atari800 takes the OS and BASIC ROMs from Altirra.
    static let ifRetroArchEXoROMs: [String: (folder: String, files: [(source: String, name: String)])] = [
        "atari800": (
            "Altirra",
            [("REV02.ROM", "ATARIXL.ROM"), ("REVBNTSC.ROM", "ATARIOSB.ROM"), ("REVC.ROM", "ATARIBAS.ROM")]
        )
    ]

    /// eXo's ROM files for a core, as copies to make: from `eXo/emulators`
    /// to `directory`. Nil when the core needs none; empty when eXo's are missing.
    func ifEXoROMCopies(for core: String, into directory: URL) -> [FileCopy]? {
        guard let roms = Self.ifRetroArchEXoROMs[core] else { return nil }
        let emulators = snapshot.root.emulatorsDirectory
        let folder = ((try? FileManager.default.contentsOfDirectory(atPath: emulators.path)) ?? []).sorted()
            .last { $0.lowercased().hasPrefix(roms.folder.lowercased()) }
        guard let folder else { return [] }
        let copies = roms.files.map { file in
            FileCopy(
                source: WindowsPath.matchingCase(
                    emulators.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(file.source)),
                destination: directory.appendingPathComponent(file.name))
        }
        return copies.allSatisfy { FileManager.default.fileExists(atPath: $0.source.path) } ? copies : []
    }

    /// Why a RetroArch version cannot start here, or nil when it can.
    func ifRetroArchProblem(core: String, file: URL) -> String? {
        guard let retroArch else { return "needs RetroArch" }
        if retroArch.resolveCore(named: core) == nil { return "needs RetroArch's \(core) core" }
        if let needed = Self.ifRetroArchSystemFiles[core], !retroArch.hasSystemFile(needed.file) {
            return "needs \(needed.description) (\(needed.file)) in RetroArch's system folder"
        }
        if ifEXoROMCopies(for: core, into: scratchDirectory)?.isEmpty == true { return "eXo's ROMs for it are missing" }
        if file.pathExtension.lowercased() == "fs-uae" { return "FS-UAE configurations are not supported" }
        return nil
    }

    /// RetroArch's system folder for cores that take eXo's ROMs.
    var ifRetroArchSystemDirectory: URL {
        (localStore?.directory ?? scratchDirectory).appendingPathComponent("RetroArch/system", isDirectory: true)
    }

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
            case .retroArch(let core, let file):
                reason = ifRetroArchProblem(core: core, file: file)
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
        if let core = Self.ifRetroArchCores[label], let file {
            return .retroArch(core: core, file: file)
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
        case .retroArch(let core, let file):
            guard emulator.kind == .retroArch else { throw LaunchPlanError.needsRetroArchCore(core) }
            guard emulator.exists, let coreURL = retroArch?.resolveCore(named: core)?.url else {
                throw LaunchPlanError.needsRetroArchCore(core)
            }
            if let problem = ifRetroArchProblem(core: core, file: file) {
                throw LaunchPlanError.ifVersionUnsupported(problem)
            }
            let base = scratchDirectory.appendingPathComponent(Self.safeFileName(game.launchBoxID))
            // A core that takes eXo's ROMs gets its own system folder,
            // through a config RetroArch adds to its own for this launch.
            if let copies = ifEXoROMCopies(for: core, into: ifRetroArchSystemDirectory) {
                let append = base.appendingPathExtension("cfg")
                var arguments = ["--appendconfig", append.path, "-L", coreURL.path]
                if options.fullscreen { arguments.append("-f") }
                arguments.append(file.path)
                return LaunchPlan(
                    game: game, variant: version, emulator: emulator, arguments: arguments,
                    workingDirectory: file.deletingLastPathComponent(), configURL: append,
                    configText: "system_directory = \"\(ifRetroArchSystemDirectory.path)\"\n", sourceConfigURL: file,
                    notes: [], fileCopies: copies)
            }
            // A fliplist (eXo's list of a C64 game's disks) becomes an m3u
            // playlist, so RetroArch can swap disks; eXo's start disk first.
            let fliplist = file.deletingLastPathComponent().appendingPathComponent("fliplist.vfl")
            let playlist = Self.playlist(fromFliplist: fliplist, startingWith: file)
            let configURL = base.appendingPathExtension(playlist == nil ? "txt" : "m3u")
            var arguments = ["-L", coreURL.path]
            if options.fullscreen { arguments.append("-f") }
            arguments.append(playlist == nil ? file.path : configURL.path)
            return LaunchPlan(
                game: game, variant: version, emulator: emulator, arguments: arguments,
                workingDirectory: file.deletingLastPathComponent(), configURL: configURL,
                configText: playlist ?? "RetroArch \(core) opens \(file.path)\n", sourceConfigURL: file,
                notes: playlist == nil ? [] : ["Disks are in RetroArch's Disk Control menu."])
        case .unsupported(let system):
            throw LaunchPlanError.ifVersionUnsupported(system)
        }
    }

    /// An m3u playlist of the disks a VICE fliplist names, `start` first.
    /// Nil when there is no fliplist.
    static func playlist(fromFliplist url: URL, startingWith start: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let folder = url.deletingLastPathComponent()
        var disks = [start.path]
        for raw in String(decoding: data, as: UTF8.self).components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.uppercased().hasPrefix("UNIT") else { continue }
            let disk = WindowsPath.matchingCase(WindowsPath.resolve(line, against: folder)).path
            if !disks.contains(disk) { disks.append(disk) }
        }
        return disks.joined(separator: "\n") + "\n"
    }
}
