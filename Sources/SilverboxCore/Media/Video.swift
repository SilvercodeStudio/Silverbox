import Foundation

/// One video file of a video entry: a documentary, an episode or a DVD disc image.
nonisolated public struct VideoItem: Hashable, Sendable, Identifiable {
    /// The menu text of the launcher ("Disc 1", "S01E21: Computer Games
    /// (1984)"), or the file name without its extension.
    public var title: String
    public var url: URL

    public var id: URL { url }

    /// True for a DVD image (`.iso`, `.cdr`), which needs a DVD-capable
    /// player such as VLC.
    public var isDiscImage: Bool {
        VideoLibrary.discImageExtensions.contains(url.pathExtension.lowercased())
    }

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// The video entries of the eXoDOS library (`eXo\Videos`). eXoDOS starts
/// them with a batch file that hands the file to VLC; batch files with
/// several videos show a console menu first. On the Mac the batch file is
/// read for its files and menu text, and the files open in a Mac player.
nonisolated public enum VideoLibrary {
    public static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "mov", "avi", "mpg", "mpeg", "webm", "wmv", "flv",
    ]
    public static let discImageExtensions: Set<String> = ["iso", "cdr"]

    /// The videos of the entry, in menu order. Files that do not exist (menu
    /// items for episodes that are not released yet) are left out. When the
    /// launcher names no files, every video in its folder is listed.
    public static func items(for game: Game, root: LibraryRoot) -> [VideoItem] {
        guard game.launchKind == .video else { return [] }
        let launcher = root.url(forWindowsRelativePath: game.applicationPath)
        let folder = launcher.deletingLastPathComponent()
        if let data = try? Data(contentsOf: launcher),
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        {
            let items = items(batchText: text, batchURL: launcher).compactMap { item -> VideoItem? in
                guard let url = existingFile(item.url) else { return nil }
                return VideoItem(title: item.title, url: url)
            }
            if !items.isEmpty { return items }
        }
        return folderItems(in: folder)
    }

    /// Every video and disc image in the folder, sorted by name.
    public static func folderItems(in folder: URL) -> [VideoItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return
            names
            .filter { !$0.hasPrefix(".") }
            .filter {
                let ext = ($0 as NSString).pathExtension.lowercased()
                return videoExtensions.contains(ext) || discImageExtensions.contains(ext)
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map {
                VideoItem(
                    title: ($0 as NSString).deletingPathExtension, url: folder.appendingPathComponent($0))
            }
    }

    /// The videos a launcher batch file plays, in menu order, without
    /// checking that the files exist.
    ///
    /// Two forms occur. A single video: `set filename=%~n0` and
    /// `vlc.exe "%filename%.mp4"`. A menu: `echo Press 1 for <text>` lines,
    /// `choice /C 12…`, then `if errorlevel = 1 goto disc1` (a label whose
    /// block starts VLC) or `if errorlevel = 1 ( set title=S01E21 … )` (a
    /// variable used in the VLC line). Menu items that go to another menu
    /// page are skipped.
    public static func items(batchText: String, batchURL: URL) -> [VideoItem] {
        let script = BatchScript(text: batchText)
        let folder = batchURL.deletingLastPathComponent()
        var variables = ["~n0": batchURL.deletingPathExtension().lastPathComponent, "cd": "."]
        for (name, value) in script.assignments where value.lowercased() == "%cd%" || value.lowercased() == "%~n0" {
            variables[name] = variables[value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "%"))]
        }

        var items: [VideoItem] = []
        func add(_ title: String, _ argument: String, extra: [String: String] = [:]) {
            let path = expand(argument, variables: variables.merging(extra) { $1 })
            guard !path.contains("%") else { return }
            let url = WindowsPath.resolve(path, against: folder)
            guard !items.contains(where: { $0.url == url }) else { return }
            items.append(VideoItem(title: title, url: url))
        }

        for item in script.menuItems {
            let title = menuTitle(item.text)
            switch item.target {
            case .label(let label):
                for argument in script.playerArguments(inBlock: label) { add(title, argument) }
            case .assignment(let name, let value):
                for argument in script.playerArguments where argument.lowercased().contains("%\(name)%") {
                    add(title, argument, extra: [name: value])
                }
            }
        }
        if items.isEmpty {
            for argument in script.playerArguments {
                let path = expand(argument, variables: variables)
                add(WindowsPath.baseName(of: path), argument)
            }
        }
        return items
    }

    /// "Play Disc 1" is shown as "Disc 1"; runs of spaces collapse.
    static func menuTitle(_ text: String) -> String {
        var title = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if title.lowercased().hasPrefix("play ") { title.removeFirst(5) }
        return title
    }

    /// Replaces `%name%` with the variable's value, ignoring case.
    static func expand(_ text: String, variables: [String: String]) -> String {
        var result = text
        for (name, value) in variables {
            result = result.replacingOccurrences(of: "%\(name)%", with: value, options: .caseInsensitive)
        }
        return result
    }

    /// The file, or a file of the same name in another case.
    private static func existingFile(_ url: URL) -> URL? {
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent.lowercased()
        let match = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
            .first { $0.lowercased() == name }
        return match.map { folder.appendingPathComponent($0) }
    }
}

/// Just enough of a batch file to follow eXoDOS's video menus.
nonisolated struct BatchScript {
    enum Target: Equatable {
        /// `if errorlevel = N goto <label>`
        case label(String)
        /// `if errorlevel = N ( set <name>=<value> … )`
        case assignment(String, String)
    }

    struct MenuItem: Equatable {
        var text: String
        var target: Target
        /// The position of the `echo Press` line in the file.
        var order: Int
    }

    private(set) var menuItems: [MenuItem] = []
    /// `set name=value` lines, in order.
    private(set) var assignments: [(String, String)] = []
    /// The file argument of every line that starts VLC.
    private(set) var playerArguments: [String] = []
    /// Lines under each `:label`, keyed by the lowercased label.
    private var blocks: [String: [String]] = [:]

    init(text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var prompts: [Prompt] = []
        var keys: [Character] = []
        var openLevel: Int?
        var block: String?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if line.hasPrefix(":") {
                block = String(lower.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let block { blocks[block, default: []].append(line) }
            if let argument = Self.playerArgument(line) { playerArguments.append(argument) }
            if let match = line.firstMatch(of: /(?i)^echo\s+press\s+(\S)\s+(?:for|to)\s+(.+)$/) {
                prompts.append(Prompt(key: Character(match.1.uppercased()), text: String(match.2), order: index))
            } else if let match = line.firstMatch(of: /(?i)^choice\b.*\/c:?\s*(\S+)/) {
                keys = Array(match.1.uppercased())
            } else if let match = line.firstMatch(of: /(?i)^if\s+errorlevel\s*=?=?\s*(\d+)\s+goto\s+(\S+)/) {
                addItem(level: Int(match.1), target: .label(match.2.lowercased()), keys: keys, prompts: prompts)
            } else if let match = line.firstMatch(of: /(?i)^if\s+errorlevel\s*=?=?\s*(\d+)\s*\(\s*$/) {
                openLevel = Int(match.1)
            } else if line == ")" {
                openLevel = nil
            }
            if let match = line.firstMatch(of: /(?i)^set\s+([^=\s]+)\s*=(.*)$/) {
                let name = match.1.lowercased()
                let value = String(match.2).trimmingCharacters(in: .whitespaces)
                assignments.append((name, value))
                if let level = openLevel {
                    addItem(level: level, target: .assignment(name, value), keys: keys, prompts: prompts)
                }
            }
            if lower == "cls" { prompts = [] }
        }
        // eXoDOS tests the highest errorlevel first; show the menu in its own order.
        menuItems.sort { $0.order < $1.order }
    }

    /// The VLC arguments under a label, following `goto` lines in the block.
    func playerArguments(inBlock label: String, visited: Set<String> = []) -> [String] {
        guard !visited.contains(label), let lines = blocks[label] else { return [] }
        for line in lines {
            if let argument = Self.playerArgument(line) { return [argument] }
            if let match = line.firstMatch(of: /(?i)^goto\s+(\S+)/) {
                let next = match.1.lowercased()
                // `goto quit` ends the script; another page of the menu is not a video.
                guard next != "quit", next != "eof", !next.hasPrefix(":") else { return [] }
                return playerArguments(inBlock: next, visited: visited.union([label]))
            }
        }
        return []
    }

    private struct Prompt {
        var key: Character
        var text: String
        var order: Int
    }

    /// Adds the menu item that `choice` returns `level` for.
    private mutating func addItem(level: Int?, target: Target, keys: [Character], prompts: [Prompt]) {
        guard let level, level >= 1, level <= keys.count else { return }
        let key = keys[level - 1]
        guard let prompt = prompts.last(where: { $0.key == key }) else { return }
        let item = MenuItem(text: prompt.text, target: target, order: prompt.order)
        if !menuItems.contains(item) { menuItems.append(item) }
    }

    /// The last quoted argument of a line that runs `vlc.exe`.
    static func playerArgument(_ line: String) -> String? {
        guard line.lowercased().contains("vlc.exe") else { return nil }
        guard let quoted = line.matches(of: /"([^"]*)"/).last else { return nil }
        let argument = String(quoted.1)
        return argument.lowercased().hasSuffix("vlc.exe") ? nil : argument
    }
}
