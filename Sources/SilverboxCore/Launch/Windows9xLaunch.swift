import Foundation

/// A file to copy before the emulator starts, when the copy does not exist yet.
nonisolated public struct FileCopy: Hashable, Sendable {
    public var source: URL
    public var destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }
}

/// Rewrites the `[autoexec]` section of an eXoWin9x `Play.conf` for the Mac.
///
/// Every eXoWin9x game boots Windows 98 in DOSBox-X the same way:
///
///     vhdmake -f -l .\emulators\dosbox\x98\parent/W98-C.vhd .\emulators\dosbox\x98\W98-C.vhd
///     IMGMOUNT c .\emulators\dosbox\x98\W98-C.vhd
///     IMGMOUNT d ".\eXoWin9x\1996\A-10 Cuba (1996)\A-10 Cuba (1996).vhd"
///     IMGMOUNT e ".\eXoWin9x\1996\A-10 Cuba (1996)\A10_Cuba.cue" -t cdrom -ide 2m
///     BOOT -l c
///
/// `vhdmake` makes a fresh differencing disk over the shared Windows 98
/// image at each start, so Windows always boots clean; the game's own disk
/// keeps its saves. Here the differencing disk goes to the local store, and
/// a game disk on a read-only library is copied there once, so that both
/// can be written. Paths become absolute, as for eXoDOS games.
nonisolated public struct Windows9xAutoexecRewriter: Sendable {
    public let root: LibraryRoot
    /// Where the Windows 98 differencing disks are written.
    public let diskDirectory: URL
    /// Prefix replacements, for games unpacked in the local store.
    public let mappings: [PathMapping]
    /// For a game unpacked on a read-only library: its folder there, and
    /// the local folder that holds writable copies of its disks.
    public let gameDiskCopies: OverlayMount?
    /// Folders tried for relative paths that are not under `eXo/`.
    public let fallbackDirectories: [URL]

    public init(
        root: LibraryRoot, diskDirectory: URL, mappings: [PathMapping] = [], gameDiskCopies: OverlayMount? = nil,
        fallbackDirectories: [URL] = []
    ) {
        self.root = root
        self.diskDirectory = diskDirectory.standardizedFileURL
        self.mappings = mappings
        self.gameDiskCopies = gameDiskCopies
        self.fallbackDirectories = fallbackDirectories
    }

    nonisolated public struct Result: Sendable, Hashable {
        public var lines: [String]
        public var notes: [String]
        /// Game disks to copy from the library before the first start.
        public var copies: [FileCopy]
    }

    /// The commands eXo's `Network.ps1` writes for Solo play: the Windows 98
    /// image without network drivers. Host and Join need NPCap on Windows.
    public static let soloDiskLines = [
        #"vhdmake -f -l .\emulators\dosbox\x98\parent/W98-C.vhd .\emulators\dosbox\x98\W98-C.vhd"#,
        #"IMGMOUNT c .\emulators\dosbox\x98\W98-C.vhd"#,
    ]

    /// Replaces the Windows disk lines with the Solo ones, as `Network.ps1` does.
    public static func soloLines(_ lines: [String]) -> [String] {
        lines.map { line in
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            if lowered.hasPrefix("vhdmake ") { return soloDiskLines[0] }
            if lowered.hasPrefix("imgmount c ") { return soloDiskLines[1] }
            return line
        }
    }

    public func rewrite(_ lines: [String]) -> Result {
        var notes: [String] = []
        var copies: [FileCopy] = []
        var fileMappings: [PathMapping] = []
        var out: [String] = []

        for line in lines {
            let tokens = AutoexecRewriter.tokenize(line.trimmingCharacters(in: .whitespaces))
            switch tokens.first?.text.lowercased() {
            case "vhdmake":
                let rewritten = rewriteVHDMake(tokens, notes: &notes)
                out.append(rewritten.line)
                if let mapping = rewritten.mapping { fileMappings.append(mapping) }
            case "imgmount":
                if let copy = writableDiskCopy(tokens) {
                    copies.append(copy)
                    fileMappings.append(PathMapping(from: copy.source, to: copy.destination))
                }
                out.append(line)
            default:
                out.append(line)
            }
        }

        let autoexec = AutoexecRewriter(
            baseDirectory: root.eXoDirectory, fallbackDirectories: fallbackDirectories,
            mappings: fileMappings + mappings)
        let result = autoexec.rewrite(out)
        return Result(lines: result.lines, notes: notes + result.notes, copies: copies)
    }

    /// `vhdmake [flags] <parent> <child>`: the parent stays in the library,
    /// the child goes to ``diskDirectory``. Returns the mapping that sends
    /// the later `imgmount` of the child there too.
    private func rewriteVHDMake(_ tokens: [AutoexecRewriter.Token], notes: inout [String]) -> (
        line: String, mapping: PathMapping?
    ) {
        let flags = tokens.dropFirst().filter { !$0.quoted && $0.text.hasPrefix("-") }.map(\.text)
        let paths = tokens.dropFirst().filter { $0.quoted || !$0.text.hasPrefix("-") }.map(\.text)
        guard paths.count == 2 else {
            notes.append("Kept vhdmake line with \(paths.count) paths as it is.")
            return (([tokens.first?.text ?? "vhdmake"] + tokens.dropFirst().map(\.text)).joined(separator: " "), nil)
        }
        let parent = Self.existingCaseInsensitive(WindowsPath.resolve(paths[0], against: root.eXoDirectory))
        let libraryChild = WindowsPath.resolve(paths[1], against: root.eXoDirectory)
        let child = diskDirectory.appendingPathComponent(libraryChild.lastPathComponent)
        let line = (["vhdmake"] + flags + ["\"\(parent.path)\"", "\"\(child.path)\""]).joined(separator: " ")
        return (line, PathMapping(from: libraryChild, to: child))
    }

    /// A hard-disk image (`imgmount` of a `.vhd` that is not a CD) under the
    /// game's folder on a read-only library: Windows writes to it, so it is
    /// mounted from a local copy.
    private func writableDiskCopy(_ tokens: [AutoexecRewriter.Token]) -> FileCopy? {
        guard let gameDiskCopies else { return nil }
        var index = 1
        var type: String?
        var images: [String] = []
        var sawDrive = false
        while index < tokens.count {
            let token = tokens[index]
            let lowered = token.text.lowercased()
            if !token.quoted, lowered.hasPrefix("-") {
                if lowered == "-t", index + 1 < tokens.count { type = tokens[index + 1].text.lowercased() }
                index += ["-t", "-ide", "-size", "-fs", "-o", "-l", "-label"].contains(lowered) ? 2 : 1
                continue
            }
            if sawDrive { images.append(token.text) } else { sawDrive = true }
            index += 1
        }
        guard type == nil || type == "hdd", images.count == 1, images[0].lowercased().hasSuffix(".vhd") else {
            return nil
        }
        let source = WindowsPath.resolve(images[0], against: root.eXoDirectory)
        guard let destination = gameDiskCopies.overlayFolder(for: source) else { return nil }
        return FileCopy(source: source, destination: destination)
    }

    /// eXo's configs spell some disk names in another case than the files
    /// (`win98jap.vhd` for `win98Jap.vhd`). Finds the file whatever its case.
    static func existingCaseInsensitive(_ url: URL) -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return url }
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path),
            let match = entries.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return url }
        return folder.appendingPathComponent(match)
    }
}

nonisolated extension LaunchPlanner {
    /// The local folder for Windows 98 differencing disks: the store's
    /// mirror of eXo's `emulators/dosbox/x98`.
    public var windowsDiskDirectory: URL {
        let base = localStore?.overlayRoot ?? scratchDirectory
        return base.appendingPathComponent("emulators/dosbox/x98", isDirectory: true)
    }

    /// True for an eXoWin9x game that eXo runs in 86Box: its folder has a
    /// `Play.cfg` and no `Play.conf`.
    public func needs86Box(_ game: Game) -> Bool {
        guard game.eXoPack == .win9x, let folder = configFolder(for: game) else { return false }
        return Self.file(named: "Play.conf", in: folder) == nil && Self.file(named: "Play.cfg", in: folder) != nil
    }

    /// Plans an eXoWin9x game: DOSBox-X boots Windows 98 with the game's
    /// disks attached, from the game's `Play.conf`.
    func planWindows9x(game: Game, emulator: EmulatorInstallation, options: LaunchOptions) throws -> LaunchPlan {
        guard let configFolder = configFolder(for: game), let installPath = game.installPath else {
            throw LaunchPlanError.missingGameFolder
        }
        guard let sourceURL = Self.file(named: "Play.conf", in: configFolder) else {
            if let box = Self.file(named: "Play.cfg", in: configFolder) {
                return try plan86Box(game: game, sourceURL: box, emulator: emulator, options: options)
            }
            throw LaunchPlanError.missingConfig(configFolder.appendingPathComponent("Play.conf"))
        }
        guard let location = snapshot.installedLocation(for: game) else {
            throw LaunchPlanError.notInstalled(folderName: installPath)
        }
        guard emulator.kind == .dosboxX else { throw LaunchPlanError.needsDOSBoxX }
        guard emulator.exists else { throw LaunchPlanError.emulatorMissing(emulator.kind) }
        guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
            throw LaunchPlanError.missingConfig(sourceURL)
        }
        let sourceText = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var source = DOSBoxConfigDocument.parse(sourceText)
        var notes: [String] = []

        // Games with network play: eXo's Network.ps1 asks Solo, Host or Join
        // and rewrites Play.conf. Host and Join need NPCap on Windows; the
        // Mac always plays Solo.
        if Self.file(named: "Network.ps1", in: configFolder) != nil {
            source.autoexecLines = Windows9xAutoexecRewriter.soloLines(source.autoexecLines)
            if source.section("ne2000") != nil {
                source.set("ne2000", "macaddr", "AC:DE:48:88:89:A0")
                source.set("ne2000", "backend", "slirp")
            }
            notes.append("Network play (Host or Join) is not available on the Mac; the game starts in Solo mode.")
        }

        var mappings: [PathMapping] = []
        var diskCopies: OverlayMount?
        switch location {
        case .local(let folder):
            mappings.append(
                PathMapping(from: snapshot.root.eXoDirectory.appendingPathComponent(installPath), to: folder))
        case .library(let folder):
            if let localStore, !FileManager.default.isWritableFile(atPath: folder.path) {
                diskCopies = OverlayMount(
                    base: folder, directory: localStore.overlayRoot.appendingPathComponent(installPath))
            }
        }
        let rewriter = Windows9xAutoexecRewriter(
            root: snapshot.root, diskDirectory: windowsDiskDirectory, mappings: mappings,
            gameDiskCopies: diskCopies, fallbackDirectories: [location.url, configFolder])
        let autoexec = rewriter.rewrite(source.autoexecLines)
        source.autoexecLines = autoexec.lines
        notes += autoexec.notes
        if let copy = autoexec.copies.first {
            notes.append(
                "The library is read-only; the game's disk is used from a copy in \(copy.destination.deletingLastPathComponent().path)."
            )
        }

        // The autoexec paths are absolute now, so the translator keeps them.
        let translator = ConfigTranslator(
            root: snapshot.root, emulator: .dosboxX, options: options,
            fluidSynthAvailable: EmulatorCapabilities.fluidSynthAvailable(for: emulator))
        var translation = translator.translate(source)
        translation.notes.insert(contentsOf: notes, at: 0)

        let configURL = scratchDirectory.appendingPathComponent(
            "\(Self.safeFileName(game.launchBoxID))-\(emulator.kind.rawValue).conf")
        let workingDirectory = snapshot.root.eXoDirectory
        return LaunchPlan(
            game: game,
            variant: nil,
            emulator: emulator,
            arguments: ["-defaultdir", workingDirectory.path, "-conf", configURL.path, "-fastlaunch"],
            workingDirectory: workingDirectory,
            configURL: configURL,
            configText: translation.document.serialized(),
            sourceConfigURL: sourceURL,
            notes: translation.notes,
            directoriesToCreate: [windowsDiskDirectory],
            fileCopies: autoexec.copies
        )
    }

    /// Finds `name` in `folder` whatever its case: eXo writes both
    /// `Play.conf` and `play.conf`.
    static func file(named name: String, in folder: URL) -> URL? {
        let url = Windows9xAutoexecRewriter.existingCaseInsensitive(folder.appendingPathComponent(name))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// A differencing disk to make fresh before each start.
nonisolated public struct DifferencingDisk: Hashable, Sendable {
    public var child: URL
    public var parent: URL

    public init(child: URL, parent: URL) {
        self.child = child
        self.parent = parent
    }
}

nonisolated extension LaunchPlanner {
    /// eXo's 86Box folder, `eXo/emulators/86Box98`: ROMs, CMOS files and the
    /// Windows 98 parent disks.
    var library86BoxDirectory: URL {
        snapshot.root.emulatorsDirectory.appendingPathComponent("86Box98", isDirectory: true)
    }

    /// The local copy of that folder, where 86Box runs: its config, CMOS
    /// files and the differencing disk.
    public var local86BoxDirectory: URL {
        (localStore?.overlayRoot ?? scratchDirectory).appendingPathComponent("emulators/86Box98", isDirectory: true)
    }

    /// Plans an eXoWin9x game that eXo runs in 86Box, from its `Play.cfg`.
    ///
    /// eXo's `9xlaunch86Box.bat` makes a differencing disk over
    /// `parent/W98-P.vhd`, copies `Play.cfg` into the 86Box folder and starts
    /// 86Box there, so the paths in `Play.cfg` are relative to that folder.
    func plan86Box(game: Game, sourceURL: URL, emulator: EmulatorInstallation, options: LaunchOptions) throws
        -> LaunchPlan
    {
        guard emulator.kind == .box86 else { throw LaunchPlanError.needs86Box }
        guard let installPath = game.installPath, let location = snapshot.installedLocation(for: game) else {
            throw LaunchPlanError.notInstalled(folderName: game.installPath ?? game.title)
        }
        guard emulator.exists else { throw LaunchPlanError.emulatorMissing(emulator.kind) }
        guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
            throw LaunchPlanError.missingConfig(sourceURL)
        }

        let disk = differencingDisk86Box(for: game)
        let localVM = local86BoxDirectory
        let child = localVM.appendingPathComponent(disk.childName)
        var notes: [String] = []
        var copies: [FileCopy] = []
        let localFolder: URL? = location.isLocal ? location.url : nil
        var diskCopies: OverlayMount?
        if case .library(let folder) = location, let localStore,
            !FileManager.default.isWritableFile(atPath: folder.path)
        {
            diskCopies = OverlayMount(
                base: folder, directory: localStore.overlayRoot.appendingPathComponent(installPath))
        }
        let libraryFolder = snapshot.root.eXoDirectory.appendingPathComponent(installPath, isDirectory: true)

        var text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            guard let equals = line.firstIndex(of: "=") else {
                lines.append(line)
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, key.hasSuffix("_fn") || key.hasSuffix("_image_path") else {
                lines.append(line)
                continue
            }
            var target = WindowsPath.resolve(value, against: library86BoxDirectory)
            if target.deletingLastPathComponent().standardizedFileURL == library86BoxDirectory.standardizedFileURL,
                target.lastPathComponent.caseInsensitiveCompare(disk.childName) == .orderedSame
            {
                target = child
            } else if let localFolder, let mapped = PathMapping(from: libraryFolder, to: localFolder).apply(to: target)
            {
                target = Windows9xAutoexecRewriter.existingCaseInsensitive(mapped)
            } else {
                target = Windows9xAutoexecRewriter.existingCaseInsensitive(target)
                if key.hasPrefix("hdd_"), let copy = diskCopies?.overlayFolder(for: target) {
                    copies.append(FileCopy(source: target, destination: copy))
                    target = copy
                }
            }
            lines.append("\(key) = \(target.path)")
        }
        if let copy = copies.first {
            notes.append(
                "The library is read-only; the game's disk is used from a copy in \(copy.destination.deletingLastPathComponent().path)."
            )
        }
        // 86Box keeps each machine's CMOS settings in nvr/; eXo ships them set up.
        let nvr = library86BoxDirectory.appendingPathComponent("nvr", isDirectory: true)
        copies.insert(FileCopy(source: nvr, destination: localVM.appendingPathComponent("nvr")), at: 0)

        let configURL = localVM.appendingPathComponent("86box.cfg")
        let roms = Windows9xAutoexecRewriter.existingCaseInsensitive(
            library86BoxDirectory.appendingPathComponent("roms"))
        var arguments = ["-P", localVM.path, "-R", roms.path, "-N"]
        if options.fullscreen { arguments.append("-F") }
        arguments.append(configURL.path)
        return LaunchPlan(
            game: game,
            variant: nil,
            emulator: emulator,
            arguments: arguments,
            workingDirectory: localVM,
            configURL: configURL,
            configText: lines.joined(separator: "\n"),
            sourceConfigURL: sourceURL,
            notes: notes,
            directoriesToCreate: [localVM],
            fileCopies: copies,
            differencingDisks: [DifferencingDisk(child: child, parent: disk.parent)]
        )
    }

    /// The disk names in the eXo launcher the game's batch file calls, from
    /// its `makevhd.exe -f <child> <parent>` line: `W98-C.vhd` over
    /// `parent/W98-P.vhd`, or `ME-C.vhd` over `parent/ME-P.vhd` for Windows ME.
    func differencingDisk86Box(for game: Game) -> (childName: String, parent: URL) {
        let root = snapshot.root
        let fallback = ("W98-C.vhd", library86BoxDirectory.appendingPathComponent("parent/W98-P.vhd"))
        // Batch files are plain ASCII; Latin-1 reads any byte.
        guard
            let launcher = try? String(
                contentsOf: root.url(forWindowsRelativePath: game.applicationPath), encoding: .isoLatin1),
            let match = launcher.firstMatch(of: /util\\([^\s\\"]+\.bat)/),
            let script = try? String(
                contentsOf: root.utilDirectory.appendingPathComponent(String(match.1)), encoding: .isoLatin1),
            let line = script.components(separatedBy: .newlines).first(where: { $0.lowercased().contains("makevhd") })
        else { return fallback }
        let paths = AutoexecRewriter.tokenize(line.trimmingCharacters(in: .whitespaces)).dropFirst()
            .filter { !$0.text.hasPrefix("-") }.map(\.text)
        guard paths.count == 2 else { return fallback }
        let parent = Windows9xAutoexecRewriter.existingCaseInsensitive(
            WindowsPath.resolve(paths[1], against: root.eXoDirectory))
        return (WindowsPath.lastComponent(of: paths[0]), parent)
    }
}
