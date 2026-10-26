import Foundation

/// The emulator eXo runs an eXoAppleIIGS game in.
nonisolated public enum AppleIIGSRoute: String, Hashable, Sendable {
    /// GSplus, with the game's config from `!appleiigs/<game>`.
    case gsplus
    /// GSport, the emulator GSplus grew out of, with the `config.txt` in the
    /// unpacked game. GSplus reads it too.
    case gsport
    /// MAME's `apple2gs` driver, with the disks `exception.bat` names.
    case mame

    public var eXoEmulatorName: String {
        switch self {
        case .gsplus: return "GSplus"
        case .gsport: return "GSport"
        case .mame: return "MAME"
        }
    }

    /// The Mac emulator that runs the game.
    public var emulator: EmulatorKind { self == .mame ? .mame : .gsplus }
}

/// The Apple IIGS character ROM that MAME's `apple2gs` driver needs in
/// versions after 0.245. eXo ships MAME 0.245 for Windows, with a ROM set
/// that has the older, hand-made `apple2gs.chr` in its place, so the user
/// supplies this one file; everything else comes from eXo's set.
nonisolated public enum AppleIIGSCharacterROM {
    public static let fileName = "344s0047.bin"
    public static let size = 16384
    public static let sha1 = "5a5a77c8ec45632aea1a57cd9c9257f7f6e44668"

    /// Where the ROM goes in a MAME folder: MAME finds it in `roms/apple2gs`
    /// beside eXo's ROM set.
    public static func url(inMAMEDirectory directory: URL) -> URL {
        directory.appendingPathComponent("roms/apple2gs", isDirectory: true).appendingPathComponent(fileName)
    }

    nonisolated public enum ImportError: Error, LocalizedError, Equatable {
        case notTheROM(String)

        public var errorDescription: String? {
            switch self {
            case .notTheROM(let name):
                return
                    "\(name) is not the Apple IIGS character ROM. MAME needs \(AppleIIGSCharacterROM.fileName), 16 KB, with SHA-1 \(AppleIIGSCharacterROM.sha1). Choose that file, or a zip that holds it, such as apple2gs.zip from a current MAME ROM set."
            }
        }
    }

    /// Copies the ROM from `source`, the file itself or a zip that holds it,
    /// to `destination`, after checking its contents.
    public static func importFile(from source: URL, to destination: URL, expectedSHA1: String = sha1) async throws {
        let fm = FileManager.default
        var data: Data?
        if source.pathExtension.lowercased() == "zip" {
            for entry in try await ZipArchive.entries(of: source) where !entry.hasSuffix("/") {
                let result = try await CommandRunner.run(
                    executable: ZipArchive.unzip, arguments: ["-p", source.path, ZipArchive.literalPattern(entry)])
                if result.status == 0, result.data.count == size, SHA1.hex(of: result.data) == expectedSHA1 {
                    data = result.data
                    break
                }
            }
        } else if let contents = fm.contents(atPath: source.path), contents.count == size,
            SHA1.hex(of: contents) == expectedSHA1
        {
            data = contents
        }
        guard let data else { throw ImportError.notTheROM(source.lastPathComponent) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}

/// eXo's index of Apple IIGS games, `eXo/util/appleIIGS.txt`: each line names
/// a game and the emulator that runs it.
///
///     3D-Triss (1993):GSPlus\gsplus.exe
///     Sensei (1991):GSPort\gsport.exe
///     Arkanoid (1987):MAME
///
/// eXo's `Launch_IIGS.bat` finds the line with `findstr /C:"<game>"`: the
/// last line that contains the name wins.
nonisolated public struct AppleIIGSIndex: Sendable, Hashable {
    public var lines: [String]

    public init(lines: [String] = []) {
        self.lines = lines
    }

    public static func parse(_ text: String) -> AppleIIGSIndex {
        AppleIIGSIndex(
            lines: text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r\u{FEFF}")) }
                .filter { !$0.isEmpty })
    }

    public func route(for name: String) -> AppleIIGSRoute? {
        guard let line = lines.last(where: { $0.contains(name) }), let colon = line.lastIndex(of: ":") else {
            return nil
        }
        let emulator = line[line.index(after: colon)...].lowercased()
        if emulator.contains("gsplus") { return .gsplus }
        if emulator.contains("gsport") { return .gsport }
        if emulator.contains("mame") { return .mame }
        return nil
    }

    private static let cache = FileAnswerCache<AppleIIGSIndex>()

    /// The index at `url`, read again only when the file changes.
    public static func cached(_ url: URL) -> AppleIIGSIndex {
        cache.value(for: url) { url in
            FileManager.default.contents(atPath: url.path).map { parse(String(decoding: $0, as: UTF8.self)) }
                ?? AppleIIGSIndex()
        }
    }
}

/// What a game's `exception.bat` says before eXo starts the emulator: the
/// variables it sets (`CONFIGTXT` for GSplus; `DISK1`, `DISKS`, `SPEED` for
/// MAME), a menu of choices that set them, and instructions, such as which
/// program on the disk to open first.
nonisolated public struct AppleIIGSException: Sendable, Hashable {
    nonisolated public struct Choice: Sendable, Hashable {
        /// The batch label the menu jumps to.
        public var label: String
        public var title: String
        /// The variables this choice sets, over the script's own; names in
        /// capitals.
        public var settings: [String: String]
        public var note: String?

        public var configName: String? { settings["CONFIGTXT"].flatMap { $0.isEmpty ? nil : $0 } }
    }

    /// Variables set before any menu, by name in capitals.
    public var settings: [String: String]
    /// Instructions shown before the menu, or the only ones when there is
    /// no menu.
    public var note: String?
    public var choices: [Choice]

    nonisolated(unsafe) private static let pressPattern =
        #/(?i)^\s*echo\s+Press\s+(?<key>\S)\s+(?:to|for)\s+(?:play|run|launch|start)?\s*(?<title>.+?)\s*$/#
    nonisolated(unsafe) private static let choicePattern = #/(?i)choice\s+/C:(?<keys>\S+)/#
    nonisolated(unsafe) private static let errorlevelPattern =
        #/(?i)^\s*if\s+errorlevel\s*=?\s*(?<level>\d+)\s+goto\s+(?<label>\S+)/#
    nonisolated(unsafe) private static let labelPattern = #/^\s*:(?<label>\S+)\s*$/#
    nonisolated(unsafe) private static let setPattern = #/(?i)^\s*set\s+(?<name>[A-Za-z0-9_]+)\s*=(?<value>.*)$/#
    nonisolated(unsafe) private static let echoPattern = #/(?i)^\s*@?echo(?<rest>[ .].*)?$/#

    public static func parse(_ text: String) -> AppleIIGSException {
        var titles: [String: String] = [:]  // menu key → title
        var orderedKeys: [String] = []
        var choiceKeys: [Character] = []
        var labelForLevel: [Int: String] = [:]
        // Variables and paragraphs of instructions by label; "" holds those
        // before any label.
        var settings: [String: [String: String]] = [:]
        var paragraphs: [String: [[String]]] = [:]
        var currentLabel = ""

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if let match = line.firstMatch(of: pressPattern) {
                let key = String(match.key).uppercased()
                if titles[key] == nil { orderedKeys.append(key) }
                titles[key] = String(match.title)
                continue
            }
            if let match = line.firstMatch(of: choicePattern) {
                if choiceKeys.isEmpty { choiceKeys = Array(String(match.keys).uppercased()) }
                continue
            }
            if let match = line.firstMatch(of: errorlevelPattern), let level = Int(match.level) {
                labelForLevel[level] = String(match.label).lowercased()
                continue
            }
            if let match = line.wholeMatch(of: labelPattern) {
                currentLabel = String(match.label).lowercased()
                continue
            }
            if let match = line.wholeMatch(of: setPattern) {
                settings[currentLabel, default: [:]][String(match.name).uppercased()] =
                    String(match.value).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let match = line.wholeMatch(of: echoPattern) else { continue }
            let rest = match.rest.map(String.init) ?? ""
            let words = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix(".") || words.isEmpty {
                // `echo.` ends a paragraph.
                if paragraphs[currentLabel]?.last?.isEmpty == false { paragraphs[currentLabel]?.append([]) }
            } else if !["off", "on"].contains(words.lowercased()) {
                if paragraphs[currentLabel] == nil { paragraphs[currentLabel] = [[]] }
                paragraphs[currentLabel]![paragraphs[currentLabel]!.count - 1].append(words)
            }
        }

        func note(_ label: String) -> String? {
            let text = (paragraphs[label] ?? []).filter { !$0.isEmpty }.map(Self.joinLines).joined(separator: "\n\n")
            return text.isEmpty ? nil : text
        }

        let common = settings[""] ?? [:]
        var choices: [Choice] = []
        for key in orderedKeys {
            guard let title = titles[key], let position = choiceKeys.firstIndex(of: Character(key)),
                let label = labelForLevel[position + 1], let own = settings[label]
            else { continue }
            choices.append(
                Choice(
                    label: label, title: title.prefix(1).uppercased() + title.dropFirst(),
                    settings: common.merging(own) { $1 }, note: note(label)))
        }
        return AppleIIGSException(settings: common, note: note(""), choices: choices)
    }

    /// Joins the lines of one paragraph, which eXo wraps for a console
    /// window. Lines of a list, such as `d = Delete character`, stay apart.
    static func joinLines(_ lines: [String]) -> String {
        var text = ""
        for line in lines {
            let isListItem = line.contains(" = ") || line.hasPrefix("-") || line.hasPrefix("*")
            if !text.isEmpty { text += isListItem || text.hasSuffix(":") ? "\n" : " " }
            text += line
        }
        return text
    }
}

nonisolated extension LaunchPlanner {
    /// `eXo/util/appleIIGS.txt`.
    public var appleIIGSIndexFile: URL { snapshot.root.utilDirectory.appendingPathComponent("appleIIGS.txt") }

    /// The emulator eXo runs the game in. A game the index leaves out runs
    /// in GSplus, like most.
    public func appleIIGSRoute(for game: Game) -> AppleIIGSRoute {
        AppleIIGSIndex.cached(appleIIGSIndexFile).route(for: game.launcherBaseName) ?? .gsplus
    }

    /// Local copies of eXo's MAME settings, and the ROMs the user adds.
    public var appleIIGSMAMEDirectory: URL {
        localStore?.mameDirectory ?? scratchDirectory.appendingPathComponent("MAME", isDirectory: true)
    }

    /// Where the user's copy of the Apple IIGS character ROM goes; MAME
    /// finds it there beside eXo's ROM set.
    public var appleIIGSCharacterROMURL: URL {
        AppleIIGSCharacterROM.url(inMAMEDirectory: appleIIGSMAMEDirectory)
    }

    public var hasAppleIIGSCharacterROM: Bool {
        FileManager.default.fileExists(atPath: appleIIGSCharacterROMURL.path)
    }

    /// Why the game cannot start here, or nil when it can (given its emulator).
    public func appleIIGSProblem(for game: Game) -> String? {
        guard appleIIGSRoute(for: game) == .mame, !hasAppleIIGSCharacterROM else { return nil }
        return
            "eXo runs this game in MAME, which needs the Apple IIGS character ROM \(AppleIIGSCharacterROM.fileName); add it in Settings › Emulators"
    }

    func appleIIGSException(for game: Game) -> AppleIIGSException? {
        guard let folder = configFolder(for: game),
            let data = FileManager.default.contents(
                atPath: Windows9xAutoexecRewriter.existingCaseInsensitive(
                    folder.appendingPathComponent("exception.bat")
                ).path)
        else { return nil }
        return AppleIIGSException.parse(String(decoding: data, as: UTF8.self))
    }

    /// The ways to start an eXoAppleIIGS game: one per choice in its menu,
    /// else one. Each carries eXo's instructions for it. Known before the
    /// game is installed.
    public func appleIIGSVariants(for game: Game) -> [LaunchVariant] {
        guard let folder = configFolder(for: game) else { return [] }
        let route = appleIIGSRoute(for: game)
        let problem = appleIIGSProblem(for: game)
        let exception = appleIIGSException(for: game)
        let choices = (exception?.choices ?? []).filter { route == .mame || $0.configName != nil }
        if route != .gsport, let exception, !choices.isEmpty {
            return choices.map { choice in
                // A GSplus choice is its config file; a MAME choice, its label.
                let config = choice.configName ?? "config.txt"
                return LaunchVariant(
                    title: choice.title, configURL: folder.appendingPathComponent(config),
                    id: choice.configName?.lowercased() ?? choice.label, unsupportedReason: problem,
                    note: [exception.note, choice.note].compactMap { $0 }.joined(separator: "\n\n"))
            }
        }
        return [
            LaunchVariant(
                title: "Default", configURL: folder.appendingPathComponent("config.txt"), id: "config.txt",
                unsupportedReason: problem, note: exception?.note)
        ]
    }

    /// Plans an eXoAppleIIGS game in GSplus, from eXo's config for it with
    /// the disks and ROM at their paths on this Mac, or in MAME, as eXo's
    /// script starts it.
    public func planAppleIIGS(
        game: Game, variant chosen: LaunchVariant?, emulator: EmulatorInstallation, options: LaunchOptions
    ) throws -> LaunchPlan {
        guard let folderName = game.gameFolderName, let configFolder = configFolder(for: game) else {
            throw LaunchPlanError.missingGameFolder
        }
        guard let location = snapshot.installedLocation(for: game) else {
            throw LaunchPlanError.notInstalled(folderName: folderName)
        }
        let route = appleIIGSRoute(for: game)
        if let reason = appleIIGSProblem(for: game) { throw LaunchPlanError.appleIIGSUnsupported(reason) }
        guard emulator.kind == route.emulator else {
            throw route == .mame ? LaunchPlanError.needsMAME : LaunchPlanError.needsGSplus
        }
        guard emulator.exists else { throw LaunchPlanError.emulatorMissing(emulator.kind) }

        let variants = appleIIGSVariants(for: game)
        let variant = chosen.flatMap { c in variants.first { $0.id == c.id } } ?? variants.first
        // Disks in a read-only library are copied once, so the game can save.
        let diskCopies: OverlayMount? =
            if case .library = location, libraryIsReadOnly(for: .appleIIGS), let localStore {
                OverlayMount(
                    base: snapshot.root.gamesDirectory(for: .appleIIGS),
                    directory: localStore.overlayDirectory(for: .appleIIGS))
            } else { nil }
        if route == .mame {
            return try planAppleIIGSMAME(
                game: game, variant: variant, location: location, diskCopies: diskCopies, emulator: emulator,
                options: options)
        }

        let configName = variant?.configURL.lastPathComponent ?? "config.txt"
        // GSport games keep their config in the game's own folder.
        let sourceFolder = route == .gsport ? location.url : configFolder
        let sourceURL = Windows9xAutoexecRewriter.existingCaseInsensitive(
            sourceFolder.appendingPathComponent(configName))
        guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
            throw LaunchPlanError.missingConfig(sourceURL)
        }
        let translation = GSplusConfigTranslator(
            gameFolder: location.url,
            romFolder: snapshot.root.emulatorsDirectory.appendingPathComponent("GSPlus", isDirectory: true),
            diskCopies: diskCopies, fullscreen: options.fullscreen
        ).translate(String(decoding: data, as: UTF8.self))
        if let rom = translation.romURL, !FileManager.default.fileExists(atPath: rom.path) {
            throw LaunchPlanError.missingROM(rom)
        }
        var notes: [String] = []
        if route == .gsport {
            notes.append("eXo runs this game in GSport; GSplus, which grew out of GSport, runs it here.")
        }
        notes += Self.diskNotes(copies: translation.copies, overlay: diskCopies, missing: translation.missingDisks)
        if let note = variant?.note { notes.append(note) }

        let suffix = configName.lowercased() == "config.txt" ? "" : "-" + (configName as NSString).deletingPathExtension
        let folder = scratchDirectory.appendingPathComponent(
            "\(Self.safeFileName(game.launchBoxID))\(Self.safeFileName(suffix))-gsplus", isDirectory: true)
        let configURL = folder.appendingPathComponent("config.kegs")
        return LaunchPlan(
            game: game, variant: variant, emulator: emulator, arguments: ["-cfg", configURL.path],
            workingDirectory: folder, configURL: configURL, configText: translation.text, sourceConfigURL: sourceURL,
            notes: notes, fileCopies: translation.copies)
    }

    /// eXo's MAME command line from `Launch_IIGS.bat`, for the Mac's MAME:
    ///
    ///     mame apple2gs -rp .\emulators\mame\roms\ -cfg_directory %CFG%
    ///         -nvram_directory .\emulators\mame\ -sl7 cffa2 -noautosave -gameio joy
    ///         -ramsize 8M -hard1 <DISK1> [-hard2 <DISK2>] [-flop3 <DISK3>]
    ///
    /// MAME reads the user's character ROM first, then eXo's ROM set. eXo's
    /// settings (`apple2gs.cfg`; the one in `fast` when `SPEED=TRUE`) and the
    /// IIGS's saved Control Panel settings (`apple2gs/`) are copied to the
    /// local MAME folder once, since MAME writes them back. eXo's `mame.ini`
    /// is for Windows, so none is read.
    func planAppleIIGSMAME(
        game: Game, variant: LaunchVariant?, location: GameLocation, diskCopies: OverlayMount?,
        emulator: EmulatorInstallation, options: LaunchOptions
    ) throws -> LaunchPlan {
        let exception = appleIIGSException(for: game)
        let choice = exception?.choices.first { $0.label == variant?.id }
        let settings = choice?.settings ?? exception?.settings ?? [:]
        let eXoMAME = Windows9xAutoexecRewriter.existingCaseInsensitive(
            snapshot.root.emulatorsDirectory.appendingPathComponent("MAME", isDirectory: true))
        let local = appleIIGSMAMEDirectory
        let fast = settings["SPEED"]?.uppercased() == "TRUE"
        let cfgDirectory = local.appendingPathComponent(fast ? "cfg-fast" : "cfg", isDirectory: true)
        let nvramDirectory = local.appendingPathComponent("nvram", isDirectory: true)
        let settingsCopies = [
            FileCopy(
                source: eXoMAME.appendingPathComponent(fast ? "fast/apple2gs.cfg" : "apple2gs.cfg"),
                destination: cfgDirectory.appendingPathComponent("apple2gs.cfg")),
            FileCopy(
                source: eXoMAME.appendingPathComponent("apple2gs", isDirectory: true),
                destination: nvramDirectory.appendingPathComponent("apple2gs", isDirectory: true)),
        ].filter { FileManager.default.fileExists(atPath: $0.source.path) }

        // Disks as eXo names them: DISK1 always, DISK2 for two, DISK3 (a
        // floppy) for three.
        let count = Int(settings["DISKS"] ?? "") ?? 1
        let printer = settings["PRINTER"]?.uppercased() == "TRUE"
        var slots: [(option: String, name: String)] = []
        if let disk = settings["DISK1"], !disk.isEmpty { slots.append(("-hard1", disk)) }
        if !printer, count >= 2, let disk = settings["DISK2"], !disk.isEmpty { slots.append(("-hard2", disk)) }
        if !printer, count == 3, let disk = settings["DISK3"], !disk.isEmpty { slots.append(("-flop3", disk)) }
        var disks: [String] = []
        var diskCopyList: [FileCopy] = []
        var missing: [URL] = []
        for (option, name) in slots {
            var disk = Windows9xAutoexecRewriter.existingCaseInsensitive(
                WindowsPath.resolve(name, against: location.url))
            guard FileManager.default.fileExists(atPath: disk.path) else {
                missing.append(disk)
                continue
            }
            if let destination = diskCopies?.overlayFolder(for: disk) {
                diskCopyList.append(FileCopy(source: disk, destination: destination))
                disk = destination
            }
            disks += [option, disk.path]
        }

        var arguments = [
            "apple2gs", "-noreadconfig",
            "-rompath",
            [local.appendingPathComponent("roms"), eXoMAME.appendingPathComponent("roms")]
                .map(\.path).joined(separator: ";"),
            "-cfg_directory", cfgDirectory.path, "-nvram_directory", nvramDirectory.path,
            options.fullscreen ? "-nowindow" : "-window", "-skip_gameinfo",
        ]
        if printer { arguments += ["-sl1", "grapplus", "-sl1:grapplus:prn", "ap2000"] }
        arguments += ["-sl7", "cffa2", "-noautosave", "-gameio", "joy", "-ramsize", "8M"] + disks

        var notes = Self.diskNotes(copies: diskCopyList, overlay: diskCopies, missing: missing)
        if let note = variant?.note { notes.append(note) }
        let configURL = scratchDirectory.appendingPathComponent(
            "\(Self.safeFileName(game.launchBoxID))\(Self.safeFileName(choice.map { "-" + $0.label } ?? ""))-mame.txt")
        return LaunchPlan(
            game: game, variant: variant, emulator: emulator, arguments: arguments, workingDirectory: local,
            configURL: configURL,
            configText: "MAME runs apple2gs with " + slots.map(\.name).joined(separator: ", ") + "\n",
            sourceConfigURL: configFolder(for: game)?.appendingPathComponent("exception.bat") ?? configURL,
            notes: notes, directoriesToCreate: [cfgDirectory, nvramDirectory],
            fileCopies: settingsCopies + diskCopyList)
    }

    static func diskNotes(copies: [FileCopy], overlay: OverlayMount?, missing: [URL]) -> [String] {
        var notes: [String] = []
        if !copies.isEmpty {
            notes.append(
                "The library is read-only; the game's disks are copied to \(overlay?.directory.path ?? "the local overlay folder") so it can save."
            )
        }
        notes += missing.map {
            "eXo names a disk the game does not have, \($0.lastPathComponent); its drive is left empty."
        }
        return notes
    }
}

/// Rewrites eXo's GSplus config (`config.txt`, a `config.kegs` by another
/// name) for the Mac build of GSplus. eXo's paths are relative to the
/// folder its script starts the emulator in; GSplus on the Mac reads them
/// relative to the config file, so disks and the ROM get absolute paths.
nonisolated public struct GSplusConfigTranslator: Sendable {
    nonisolated public struct Result: Sendable, Hashable {
        public var text: String
        public var copies: [FileCopy]
        public var romURL: URL?
        public var missingDisks: [URL]
    }

    /// The unpacked game, which holds its disks.
    public var gameFolder: URL
    /// eXo's `emulators/GSPlus`, which holds the ROM files `ROM1` and `ROM3`.
    public var romFolder: URL
    /// Where disks are copied when the game folder cannot be written.
    public var diskCopies: OverlayMount?
    public var fullscreen: Bool

    public init(gameFolder: URL, romFolder: URL, diskCopies: OverlayMount? = nil, fullscreen: Bool = false) {
        self.gameFolder = gameFolder
        self.romFolder = romFolder
        self.diskCopies = diskCopies
        self.fullscreen = fullscreen
    }

    nonisolated(unsafe) private static let settingPattern = #/^\s*(?<key>[A-Za-z0-9_\[\]]+)\s*=\s*(?<value>.*?)\s*$/#
    nonisolated(unsafe) private static let diskKeyPattern = #/^s[5-7]d[1-9][0-9]*$/#
    /// Settings this translation writes itself, and GSport's Windows debug
    /// window, which GSplus does not know.
    private static let replacedKeys: Set<String> = ["g_status_enable", "fullscreen", "g_win_status_debug_request"]

    /// The disk images a config inserts, as eXo writes them: relative to the
    /// unpacked game, with forward slashes. A name after `#` is a disk the
    /// emulator lists but has ejected.
    public static func diskNames(in source: String) -> [String] {
        lines(of: source).compactMap { line in
            guard let match = line.wholeMatch(of: settingPattern),
                String(match.key).wholeMatch(of: diskKeyPattern) != nil,
                !match.value.isEmpty, !match.value.hasPrefix("#")
            else { return nil }
            return match.value.replacingOccurrences(of: "\\", with: "/")
        }
    }

    /// eXo's configs end their lines with CR LF.
    static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
    }

    public func translate(_ source: String) -> Result {
        var lines: [String] = []
        var copies: [FileCopy] = []
        var romURL: URL?
        var missing: [URL] = []
        for line in Self.lines(of: source) {
            guard let match = line.wholeMatch(of: Self.settingPattern) else {
                lines.append(line)
                continue
            }
            let key = String(match.key)
            let value = String(match.value)
            if Self.replacedKeys.contains(key.lowercased()) { continue }
            if key.wholeMatch(of: Self.diskKeyPattern) != nil, !value.isEmpty {
                var disk = Windows9xAutoexecRewriter.existingCaseInsensitive(
                    WindowsPath.resolve(value, against: gameFolder))
                // A few of eXo's configs name an ejected disk (`#name`) or one
                // the game does not have; the Windows build skips those too.
                guard !value.hasPrefix("#"), FileManager.default.fileExists(atPath: disk.path) else {
                    if !value.hasPrefix("#") { missing.append(disk) }
                    lines.append("\(key) = ")
                    continue
                }
                if let destination = diskCopies?.overlayFolder(for: disk) {
                    copies.append(FileCopy(source: disk, destination: destination))
                    disk = destination
                }
                lines.append("\(key) = \(disk.path)")
            } else if key == "g_cfg_rom_path" {
                // `..\..\..\GSPlus\ROM1`: only the file name means anything here.
                let rom = Windows9xAutoexecRewriter.existingCaseInsensitive(
                    romFolder.appendingPathComponent(WindowsPath.lastComponent(of: value)))
                romURL = rom
                lines.append("\(key) = \(rom.path)")
            } else if key == "g_joystick_type", value == "0" {
                // GSport's keypad joystick; GSplus's Auto mode uses a game
                // controller when there is one, else the keypad.
                lines.append("\(key) = 4")
            } else {
                lines.append(line)
            }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines += ["", "g_status_enable = 0", "fullscreen = \(fullscreen ? 1 : 0)", ""]
        return Result(text: lines.joined(separator: "\n"), copies: copies, romURL: romURL, missingDisks: missing)
    }
}
