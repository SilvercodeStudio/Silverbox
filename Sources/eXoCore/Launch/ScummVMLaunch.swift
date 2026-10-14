import Foundation

/// eXo's index of ScummVM games, `eXo/util/scummvm.txt`. Each line names a
/// game or a variant folder, its ScummVM game id or target, and the eXo
/// ScummVM build that runs it:
///
///     Beneath a Steel Sky (CD DOS);sky:sky;2.9.0\scummvm.exe
///     King's Quest VI (CD DOS);kq6-cd;2.9.0\scummvm.exe
///
/// eXo looks lines up with `findstr /b`: the last line that starts with the
/// name wins.
nonisolated public struct ScummVMIndex: Sendable, Hashable {
    nonisolated public struct Entry: Sendable, Hashable {
        public var line: String
        /// `engine:game`, a bare game id, or a target eXo defines in its
        /// `scummvm.ini`, such as `kq6-cd`.
        public var gameID: String
        /// The folder of eXo's ScummVM build under `emulators/scmvm`, empty
        /// for the build at its top.
        public var versionFolder: String

        /// The engine, when the id names one (`sky:sky` → `sky`).
        public var engineID: String? {
            gameID.firstIndex(of: ":").map { String(gameID[..<$0]) }
        }
    }

    public var entries: [Entry]

    /// Ids eXo uses for older ScummVM builds that ScummVM has since merged:
    /// the CD versions of Gobliiins are now found under the floppy ids.
    static let renamedIDs = ["gob:gob1cd": "gob:gob1", "gob:gob2cd": "gob:gob2"]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self = Self.parse(String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> ScummVMIndex {
        var entries: [Entry] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            let fields = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            var gameID = fields[1].trimmingCharacters(in: .whitespaces)
            guard !gameID.isEmpty else { continue }
            gameID = renamedIDs[gameID.lowercased()] ?? gameID
            let executable = WindowsPath.components(of: fields[2].trimmingCharacters(in: .whitespaces))
            entries.append(
                Entry(line: line, gameID: gameID, versionFolder: executable.dropLast().joined(separator: "/")))
        }
        return ScummVMIndex(entries: entries)
    }

    /// The last line that starts with `name`, as `findstr /b` finds it.
    public func entry(forPrefix name: String) -> Entry? {
        guard !name.isEmpty else { return nil }
        return entries.last { $0.line.hasPrefix(name) }
    }
}

/// The choices eXo's ScummVM launcher asks for besides the version: the
/// music device from `sound.txt`, and subtitles from `subtitle.txt`.
nonisolated public struct LaunchChoices: Hashable, Sendable, Codable {
    /// The `sound.txt` entry, such as `Roland MT32`.
    public var music: String?
    public var subtitles: Bool?

    public init(music: String? = nil, subtitles: Bool? = nil) {
        self.music = music
        self.subtitles = subtitles
    }

    public var isEmpty: Bool { music == nil && subtitles == nil }
}

/// The small text files eXo puts in a ScummVM variant folder. Each holds
/// one line; eXo reads the part before the first colon.
nonisolated public struct ScummVMVariantFiles: Sendable, Hashable {
    /// `--platform` value, from `platform.txt`.
    public var platform: String?
    /// Extra options from `video.txt`, such as `--render-mode=cga`.
    public var video: String?
    /// Extra options from `audio.txt`.
    public var audio: String?
    /// Options added when subtitles are chosen, from `subtitle.txt`.
    public var subtitle: String?
    /// Music devices to choose from, from `sound.txt`.
    public var musicChoices: [String]
    /// True when `mt32_rev0.txt` asks for the first MT-32 ROM revision.
    public var usesMT32Rev0: Bool

    public init(folder: URL) {
        func firstField(_ name: String) -> String? {
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path) else {
                return nil
            }
            let text = String(decoding: data, as: UTF8.self)
            let line = text.components(separatedBy: .newlines).first {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            let field = line?.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init)
            return field?.trimmingCharacters(in: .whitespaces)
        }
        platform = firstField("platform.txt")
        video = firstField("video.txt")
        audio = firstField("audio.txt")
        subtitle = firstField("subtitle.txt")
        if let data = FileManager.default.contents(atPath: folder.appendingPathComponent("sound.txt").path) {
            let line = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).first ?? ""
            musicChoices = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            musicChoices = []
        }
        usesMT32Rev0 = FileManager.default.fileExists(atPath: folder.appendingPathComponent("mt32_rev0.txt").path)
    }

    /// Extra options for one music choice, from `<prefix>audio.txt`.
    static func musicAudio(_ choice: String, folder: URL) -> String? {
        guard let prefix = ScummVMMusic.audioFilePrefix(choice),
            let data = FileManager.default.contents(atPath: folder.appendingPathComponent(prefix + "audio.txt").path)
        else { return nil }
        let line = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).first ?? ""
        return line.split(separator: ":").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// The music devices eXo's launcher offers, and the options each one sets.
nonisolated public enum ScummVMMusic {
    /// Options every eXo launch starts with.
    static let base = ["--opl-driver=nuked", "--output-rate=44100"]

    static func audioFilePrefix(_ choice: String) -> String? {
        switch choice {
        case "Tandy": return "T_"
        case "Creative Music System (CMS)": return "CMS_"
        case "Sound Blaster": return "sb_"
        case "Roland MT32": return "mt32_"
        case "Sound Canvas": return "sc_"
        case "James Woodcock's Enhanced Music": return "eh_"
        default: return nil
        }
    }

    /// The options for a choice. Paths are relative to `eXo/`, as in eXo's
    /// script; the planner resolves them.
    static func options(for choice: String, mt32Rev0: Bool) -> [String] {
        switch choice {
        case "Tandy": return ["-epcjr"]
        case "Creative Music System (CMS)": return ["-ecms"]
        case "Roland MT32":
            return ["-emt32", "--multi-midi", "--extrapath=.\\mt32\\" + (mt32Rev0 ? "rev0" : "")]
        case "Sound Canvas": return ["-efluidsynth", "--multi-midi", "--soundfont=.\\mt32\\soundcanvas.sf2"]
        default: return []
        }
    }
}

/// A ScummVM settings file as ScummVM writes it: `[section]` headers and
/// `key=value` lines, in order, with keys kept as they are.
nonisolated public struct ScummVMSettings: Sendable, Hashable {
    nonisolated public struct Section: Sendable, Hashable {
        public var name: String
        public var entries: [(key: String, value: String)]

        public static func == (a: Section, b: Section) -> Bool {
            a.name == b.name && a.entries.elementsEqual(b.entries) { $0.key == $1.key && $0.value == $1.value }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            for entry in entries {
                hasher.combine(entry.key)
                hasher.combine(entry.value)
            }
        }
    }

    public var sections: [Section]

    public init(sections: [Section] = []) {
        self.sections = sections
    }

    public static func parse(_ text: String) -> ScummVMSettings {
        var sections: [Section] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append(Section(name: String(line.dropFirst().dropLast()), entries: []))
            } else if let equals = line.firstIndex(of: "="), !sections.isEmpty, !line.hasPrefix("#") {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].entries.append((key, value))
            }
        }
        return ScummVMSettings(sections: sections)
    }

    public func serialized() -> String {
        sections.map { section in
            (["[\(section.name)]"] + section.entries.map { "\($0.key)=\($0.value)" }).joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    public func section(_ name: String) -> Section? {
        sections.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func value(_ section: String, _ key: String) -> String? {
        self.section(section)?.entries.last { $0.key == key }?.value
    }

    public mutating func set(_ section: String, _ key: String, _ value: String) {
        guard let index = sections.firstIndex(where: { $0.name.caseInsensitiveCompare(section) == .orderedSame })
        else {
            sections.append(Section(name: section, entries: [(key, value)]))
            return
        }
        sections[index].entries.removeAll { $0.key == key }
        sections[index].entries.append((key, value))
    }

    public mutating func remove(_ section: String, _ key: String) {
        guard let index = sections.firstIndex(where: { $0.name.caseInsensitiveCompare(section) == .orderedSame })
        else { return }
        sections[index].entries.removeAll { $0.key == key }
    }
}

/// Launching eXoScummVM games, following eXo's `launch_svm.bat`.
nonisolated extension LaunchPlanner {
    /// `eXo/util/scummvm.txt`.
    public var scummVMIndexFile: URL { snapshot.root.utilDirectory.appendingPathComponent("scummvm.txt") }

    /// eXo's ScummVM builds and their settings files.
    public var scummVMDirectory: URL {
        snapshot.root.emulatorsDirectory.appendingPathComponent("scmvm", isDirectory: true)
    }

    /// A variant whose index name differs from its folder: eXo looks the
    /// first up and plays the second.
    static let scummVMFolderAliases = [
        "Blade Runner with Restored Content (CD Windows)": "Blade Runner (CD Windows)"
    ]

    /// The versions of an installed ScummVM game: each folder in it, and
    /// for a folder with a `menu.txt`, each folder inside that one.
    public func scummVMVariants(for game: Game) -> [LaunchVariant] {
        guard let folder = snapshot.installedLocation(for: game)?.url else { return [] }
        var variants: [LaunchVariant] = []
        for name in Self.subfolders(of: folder) {
            let top = folder.appendingPathComponent(name, isDirectory: true)
            let label = Self.versionLabel(name, within: folder.lastPathComponent)
            if FileManager.default.fileExists(atPath: top.appendingPathComponent("menu.txt").path) {
                for sub in Self.subfolders(of: top) {
                    let subLabel = Self.versionLabel(sub, within: name)
                    variants.append(
                        LaunchVariant(
                            title: subLabel == sub ? "\(label) › \(sub)" : subLabel,
                            configURL: top.appendingPathComponent(sub, isDirectory: true), id: "\(name)/\(sub)"))
                }
            } else {
                variants.append(LaunchVariant(title: label, configURL: top, id: name))
            }
        }
        return variants
    }

    /// The part that tells a version apart: `DOS CD` for
    /// `King's Quest 6 (DOS CD)` inside `King's Quest 6 (Multi-Platform)`.
    /// The whole name when the rest differs.
    static func versionLabel(_ name: String, within container: String) -> String {
        func split(_ text: String) -> (stem: String, detail: String)? {
            guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return nil }
            return (
                text[..<open].trimmingCharacters(in: .whitespaces),
                String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            )
        }
        guard let version = split(name), let outer = split(container), version.stem == outer.stem,
            !version.detail.isEmpty
        else { return name }
        return version.detail
    }

    /// The note eXo shows before the game starts, from `note.txt`.
    public func scummVMNote(for game: Game, variant: LaunchVariant?) -> String? {
        guard let folder = snapshot.installedLocation(for: game)?.url else { return nil }
        var candidates = [folder.appendingPathComponent("note.txt")]
        if let variant, variant.id.contains("/") {
            candidates.append(variant.configURL.deletingLastPathComponent().appendingPathComponent("note.txt"))
        }
        let notes = candidates.compactMap { url in
            FileManager.default.contents(atPath: url.path).map {
                String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.filter { !$0.isEmpty }
        return notes.isEmpty ? nil : notes.joined(separator: "\n\n")
    }

    /// The `engine:game` id the game needs, with eXo's targets resolved
    /// through its settings files (`kq6-cd` → `sci:kq6`). A bare id that is
    /// no target, such as `losteden`, stays bare.
    public func scummVMGameID(for game: Game, variant: LaunchVariant?) -> String? {
        let variants = scummVMVariants(for: game)
        guard let entry = scummVMEntry(for: game, variant: variant ?? variants.first, variantCount: variants.count)
        else { return nil }
        if entry.gameID.contains(":") { return entry.gameID }
        for folder in [entry.versionFolder, ""] {
            let url = (folder.isEmpty ? scummVMDirectory : scummVMDirectory.appendingPathComponent(folder))
                .appendingPathComponent("scummvm.ini")
            guard let data = FileManager.default.contents(atPath: url.path) else { continue }
            let settings = ScummVMSettings.parse(String(decoding: data, as: UTF8.self))
            if let engine = settings.value(entry.gameID, "engineid"), let id = settings.value(entry.gameID, "gameid") {
                return "\(engine):\(id)"
            }
        }
        return entry.gameID
    }

    /// The variant's eXo files, for the launch dialog's choices.
    public func scummVMFiles(for variant: LaunchVariant) -> ScummVMVariantFiles {
        ScummVMVariantFiles(folder: variant.configURL)
    }

    /// The index entry for the game, or for the chosen variant when it has
    /// its own line.
    public func scummVMEntry(for game: Game, variant: LaunchVariant?, variantCount: Int) -> ScummVMIndex.Entry? {
        let index = (try? ScummVMIndex(contentsOf: scummVMIndexFile)) ?? ScummVMIndex()
        var entry = index.entry(forPrefix: game.launcherBaseName)
        guard let variant, variantCount > 1 else { return entry }
        let parts = variant.id.split(separator: "/").map(String.init)
        for part in parts {
            entry = index.entry(forPrefix: part) ?? entry
        }
        return entry
    }

    public func planScummVM(
        game: Game, variant chosen: LaunchVariant?, emulator: EmulatorInstallation, options: LaunchOptions,
        choices: LaunchChoices = LaunchChoices()
    ) throws -> LaunchPlan {
        guard let folderName = game.gameFolderName else { throw LaunchPlanError.missingGameFolder }
        guard snapshot.installedLocation(for: game) != nil else {
            throw LaunchPlanError.notInstalled(folderName: folderName)
        }
        guard emulator.kind.isScummVM else { throw LaunchPlanError.needsScummVM }
        guard emulator.exists else { throw LaunchPlanError.emulatorMissing(emulator.kind) }
        let variants = scummVMVariants(for: game)
        guard let variant = chosen.flatMap({ c in variants.first { $0.id == c.id } }) ?? variants.first else {
            throw LaunchPlanError.notInstalled(folderName: folderName)
        }
        guard let entry = scummVMEntry(for: game, variant: variant, variantCount: variants.count) else {
            throw LaunchPlanError.scummVMNotInIndex(game.launcherBaseName)
        }

        let isSub = variant.id.contains("/")
        let top = isSub ? variant.configURL.deletingLastPathComponent() : variant.configURL
        var path = variant.configURL
        if let alias = Self.scummVMFolderAliases[variant.id] {
            path = top.deletingLastPathComponent().appendingPathComponent(alias, isDirectory: true)
        }
        let files = ScummVMVariantFiles(folder: variant.configURL)
        let topFiles = isSub ? ScummVMVariantFiles(folder: top) : files

        var arguments: [String] = []
        arguments.append(options.fullscreen ? "-f" : "-F")
        switch options.windowSize {
        case .default: break
        case .small: arguments.append("--scale-factor=2")
        case .medium: arguments.append("--scale-factor=4")
        case .large: arguments.append("--scale-factor=8")
        }
        switch options.aspect {
        case .gameConfig: break
        case .on: arguments.append("--aspect-ratio")
        case .off: arguments.append("--no-aspect-ratio")
        }
        // eXo's order: render mode, subtitles, stretch mode, platform, sound.
        if let video = files.video { arguments += Self.splitOptions(video) }
        if !isSub, let subtitle = topFiles.subtitle, choices.subtitles ?? true {
            arguments += Self.splitOptions(subtitle)
        }
        arguments.append("--stretch-mode=pixel-perfect")
        // eXo passes the platform only when it asked which version to play.
        if !isSub, variants.count > 1, let platform = topFiles.platform {
            arguments.append("--platform=\(platform)")
        }
        var sound = ScummVMMusic.base
        var notes: [String] = []
        if !files.musicChoices.isEmpty {
            let music = choices.music.flatMap { files.musicChoices.contains($0) ? $0 : nil } ?? files.musicChoices[0]
            sound += ScummVMMusic.options(for: music, mt32Rev0: files.usesMT32Rev0 || topFiles.usesMT32Rev0)
            if let extra = ScummVMVariantFiles.musicAudio(music, folder: variant.configURL) {
                sound += Self.splitOptions(extra)
            }
            notes.append("Music: \(music).")
        } else if let audio = files.audio {
            sound += Self.splitOptions(audio)
        }
        arguments += sound.map(resolveEXoPath)

        let configURL =
            localStore?.scummVMConfigURL ?? scratchDirectory.appendingPathComponent("scummvm.ini")
        let saves =
            localStore?.scummVMSavesDirectory ?? scratchDirectory.appendingPathComponent("ScummVM Saves")
        let (settings, source) = scummVMSettings(at: configURL, savePath: saves, entry: entry)
        arguments += ["--config=\(configURL.path)", "--savepath=\(saves.path)", "--path=\(path.path)", entry.gameID]

        if let note = scummVMNote(for: game, variant: variant) { notes.append(note) }
        return LaunchPlan(
            game: game, variant: variant, emulator: emulator, arguments: arguments,
            workingDirectory: snapshot.root.eXoDirectory, configURL: configURL,
            configText: settings.serialized(), sourceConfigURL: source, notes: notes,
            directoriesToCreate: [saves])
    }

    /// The local ScummVM settings with what this launch needs: eXo's global
    /// settings the first time, the save folder, and the target the game id
    /// names when eXo defines one. ScummVM writes its own changes back to
    /// the same file, so they are kept.
    func scummVMSettings(at url: URL, savePath: URL, entry: ScummVMIndex.Entry) -> (ScummVMSettings, URL) {
        let fm = FileManager.default
        let builds = [entry.versionFolder, ""] + Self.subfolders(of: scummVMDirectory).reversed()
        let eXoFiles = builds.map {
            ($0.isEmpty ? scummVMDirectory : scummVMDirectory.appendingPathComponent($0, isDirectory: true))
                .appendingPathComponent("scummvm.ini")
        }.filter { fm.fileExists(atPath: $0.path) }
        let eXoSettings = eXoFiles.map { url in
            (url, ScummVMSettings.parse(String(decoding: fm.contents(atPath: url.path) ?? Data(), as: UTF8.self)))
        }

        var settings: ScummVMSettings
        if let data = fm.contents(atPath: url.path) {
            settings = ScummVMSettings.parse(String(decoding: data, as: UTF8.self))
        } else {
            settings = ScummVMSettings()
            if let global = eXoSettings.first(where: { $0.1.section("scummvm") != nil })?.1.section("scummvm") {
                settings.sections.append(global)
            }
            // The Mac build records its own version, and needs no Windows paths.
            settings.remove("scummvm", "versioninfo")
        }
        settings.set("scummvm", "savepath", savePath.path)
        settings.set("scummvm", "updates_check", "0")

        var source = eXoFiles.first ?? scummVMDirectory.appendingPathComponent("scummvm.ini")
        if !entry.gameID.contains(":"), settings.section(entry.gameID) == nil,
            let defining = eXoSettings.first(where: { $0.1.section(entry.gameID) != nil }),
            let target = defining.1.section(entry.gameID)
        {
            settings.sections.append(target)
            source = defining.0
        }
        return (settings, source)
    }

    /// Resolves an eXo path option such as `--soundfont=.\mt32\soundcanvas.sf2`
    /// against `eXo/`, matching the case of the files on disk.
    func resolveEXoPath(_ option: String) -> String {
        guard let equals = option.firstIndex(of: "=") else { return option }
        let value = String(option[option.index(after: equals)...])
        guard value.hasPrefix(".\\") || value.hasPrefix("..\\") else { return option }
        let url = WindowsPath.matchingCase(WindowsPath.resolve(value, against: snapshot.root.eXoDirectory))
        return String(option[...equals]) + url.path
    }

    /// Splits eXo's option text on spaces, keeping quoted parts together.
    static func splitOptions(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
            } else if character == " ", !quoted {
                if !current.isEmpty { parts.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Folder names inside `folder`, sorted as `dir` lists them on Windows.
    static func subfolders(of folder: URL) -> [String] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// The games a ScummVM build can run, from `scummvm --list-games`.
nonisolated public struct ScummVMGames: Sendable, Hashable {
    /// `engine:game` ids, in lower case.
    public var ids: Set<String>

    public init(listGamesOutput output: String) {
        var ids: Set<String> = []
        for line in output.components(separatedBy: .newlines) {
            guard let first = line.split(separator: " ").first, first.contains(":") else { continue }
            ids.insert(first.lowercased())
        }
        self.ids = ids
    }

    /// True when the build has the game. A bare id matches any engine.
    public func supports(_ gameID: String) -> Bool {
        let id = gameID.trimmingCharacters(in: .whitespaces).lowercased()
        if id.contains(":") { return ids.contains(id) }
        return ids.contains { $0.hasSuffix(":" + id) }
    }
}
