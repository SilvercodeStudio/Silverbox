import Foundation

/// Replaces one host folder prefix with another when resolving paths, for
/// example the library's `eXo/eXoDOS` with the local store's games folder.
nonisolated public struct PathMapping: Hashable, Sendable {
    public var from: URL
    public var to: URL

    public init(from: URL, to: URL) {
        self.from = from.standardizedFileURL
        self.to = to.standardizedFileURL
    }

    func apply(to url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        if path == from.path { return to }
        guard path.hasPrefix(from.path + "/") else { return nil }
        return to.appendingPathComponent(String(path.dropFirst(from.path.count + 1)))
    }
}

/// Adds a writable overlay on top of folders mounted from a read-only base.
nonisolated public struct OverlayMount: Hashable, Sendable {
    public var base: URL
    public var directory: URL

    public init(base: URL, directory: URL) {
        self.base = base.standardizedFileURL
        self.directory = directory.standardizedFileURL
    }

    func overlayFolder(for mounted: URL) -> URL? {
        let path = mounted.standardizedFileURL.path
        if path == base.path { return directory }
        guard path.hasPrefix(base.path + "/") else { return nil }
        return directory.appendingPathComponent(String(path.dropFirst(base.path.count + 1)))
    }
}

/// Rewrites the `[autoexec]` section of an eXoDOS config for a Mac emulator.
///
/// eXoDOS launchers run DOSBox from the `eXo/` folder, so host paths in
/// `mount` and `imgmount` lines are Windows-relative to it, for example
/// `mount c .\eXoDOS\`. Those become absolute POSIX paths, optionally mapped
/// into the local store. Windows-only CD-ROM flags are dropped.
nonisolated public struct AutoexecRewriter: Sendable {
    /// The folder the original launchers used as the working directory.
    public let baseDirectory: URL
    /// Folders tried in order when a relative path does not exist under
    /// `baseDirectory`: a few menus run DOSBox from the game folder instead.
    public let fallbackDirectories: [URL]
    /// Prefix replacements applied to resolved host paths.
    public let mappings: [PathMapping]
    /// When set, every `mount` of a folder under the overlay base gets a
    /// second, writable overlay mount.
    public let overlay: OverlayMount?

    public init(
        baseDirectory: URL, fallbackDirectories: [URL] = [], mappings: [PathMapping] = [], overlay: OverlayMount? = nil
    ) {
        self.baseDirectory = baseDirectory
        self.fallbackDirectories = fallbackDirectories
        self.mappings = mappings
        self.overlay = overlay
    }

    nonisolated public struct Result: Sendable, Hashable {
        public var lines: [String]
        public var notes: [String]
        /// Overlay folders the launcher should create before starting.
        public var overlayFolders: [URL]
    }

    private static let pathCommands: Set<String> = ["mount", "imgmount", "boot"]
    private static let droppedFlags: Set<String> = [
        "-ioctl", "-ioctl_dx", "-ioctl_dio", "-ioctl_mci", "-noioctl", "-aspi",
    ]
    private static let droppedFlagsWithValue: Set<String> = ["-usecd"]
    private static let flagsWithValue: Set<String> = ["-t", "-label", "-freesize", "-fs", "-size", "-ide", "-l", "-o"]

    public func rewrite(_ lines: [String]) -> Result {
        var out: [String] = []
        var notes: [String] = []
        var overlays: [URL] = []
        for line in lines {
            out.append(contentsOf: rewriteLine(line, notes: &notes, overlayFolders: &overlays))
        }
        return Result(lines: out, notes: notes, overlayFolders: overlays)
    }

    func rewriteLine(_ rawLine: String, notes: inout [String], overlayFolders: inout [URL]) -> [String] {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        var prefix = ""
        if line.hasPrefix("@") {
            prefix = "@"
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        let tokens = Self.tokenize(line)
        guard let first = tokens.first else { return [rawLine] }
        let command = first.text.lowercased()
        guard Self.pathCommands.contains(command) else { return [rawLine] }

        var rebuilt: [String] = [first.text]
        var index = 1
        var sawDrive = command == "boot"
        var driveToken: String?
        var mountedFolder: URL?
        var mountType: String?
        while index < tokens.count {
            let token = tokens[index]
            let lowered = token.text.lowercased()
            if lowered.hasPrefix("-") {
                if Self.droppedFlags.contains(lowered) {
                    notes.append("Dropped Windows-only option \(token.text) from \(command).")
                    index += 1
                    continue
                }
                if Self.droppedFlagsWithValue.contains(lowered) {
                    notes.append("Dropped Windows-only option \(token.text) from \(command).")
                    index += 2
                    continue
                }
                rebuilt.append(token.text)
                if Self.flagsWithValue.contains(lowered), index + 1 < tokens.count {
                    if lowered == "-t" { mountType = tokens[index + 1].text.lowercased() }
                    rebuilt.append(tokens[index + 1].text)
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if !sawDrive {
                // The first non-flag token after mount/imgmount is the drive letter or number.
                sawDrive = true
                driveToken = token.text
                rebuilt.append(token.text)
                index += 1
                continue
            }
            if Self.looksLikeHostPath(token.text, quoted: token.quoted) {
                let resolved = resolve(token.text, notes: &notes)
                rebuilt.append(resolved.quoted)
                if command == "mount", mountedFolder == nil { mountedFolder = resolved.url }
            } else {
                rebuilt.append(token.quoted ? "\"\(token.text)\"" : token.text)
            }
            index += 1
        }
        var lines = [prefix + rebuilt.joined(separator: " ")]
        if command == "mount", let overlay, let drive = driveToken, let folder = mountedFolder,
            mountType == nil || mountType == "dir", let overlayFolder = overlay.overlayFolder(for: folder)
        {
            lines.append("\(prefix)mount \(drive) \"\(overlayFolder.path)\" -t overlay")
            overlayFolders.append(overlayFolder)
        }
        return lines
    }

    /// Host paths carry a separator or start with `.`; bare names such as
    /// `GAME.IMG` are DOS-side paths that the emulator resolves itself.
    static func looksLikeHostPath(_ text: String, quoted: Bool) -> Bool {
        if text.contains("\\") || text.contains("/") { return true }
        return text.hasPrefix(".")
    }

    nonisolated struct ResolvedPath: Sendable {
        var quoted: String
        var url: URL?
    }

    /// Converts a Windows-relative host path to a quoted absolute POSIX path.
    public func hostPath(_ text: String, notes: inout [String]) -> String {
        resolve(text, notes: &notes).quoted
    }

    func resolve(_ text: String, notes: inout [String]) -> ResolvedPath {
        let posix = WindowsPath.posix(text)
        if posix.hasPrefix("/") {
            let url = mapped(URL(fileURLWithPath: posix))
            return ResolvedPath(quoted: "\"\(url.path)\"", url: url)
        }
        if WindowsPath.isAbsolute(text) {
            notes.append("Kept absolute Windows path \(text); it will not exist on this Mac.")
            return ResolvedPath(quoted: "\"\(posix)\"", url: nil)
        }
        let unmapped = WindowsPath.resolve(text, against: baseDirectory)
        let resolved = mapped(unmapped)
        // A mapping for this exact path names a file made at launch, such
        // as a differencing disk, so it need not exist yet.
        let isPlannedFile = mappings.contains { $0.from == unmapped }
        if isPlannedFile || FileManager.default.fileExists(atPath: resolved.path) {
            return ResolvedPath(quoted: "\"\(resolved.path)\"", url: resolved)
        }
        for fallback in fallbackDirectories {
            let candidate = mapped(WindowsPath.resolve(text, against: fallback))
            if FileManager.default.fileExists(atPath: candidate.path) {
                notes.append(
                    "Resolved \(text) relative to \(fallback.lastPathComponent) because it does not exist under eXo.")
                return ResolvedPath(quoted: "\"\(candidate.path)\"", url: candidate)
            }
        }
        if fallbackDirectories.isEmpty || !FileManager.default.fileExists(atPath: baseDirectory.path) {
            // Nothing to check against (unit tests, missing library): resolve blindly.
            return ResolvedPath(quoted: "\"\(resolved.path)\"", url: resolved)
        }
        // Not a host path we can find. Leave it for the emulator, which also
        // tries the path on the mounted DOS drives.
        notes.append("Could not find \(text) on disk; the emulator will look it up on the mounted DOS drives.")
        return ResolvedPath(quoted: "\"\(text)\"", url: nil)
    }

    /// Applies the first matching mapping, if any.
    func mapped(_ url: URL) -> URL {
        for mapping in mappings {
            if let replaced = mapping.apply(to: url) { return replaced }
        }
        return url.standardizedFileURL
    }

    nonisolated struct Token: Hashable, Sendable {
        var text: String
        var quoted: Bool
    }

    /// Splits on spaces, honouring double quotes.
    static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inQuotes = false
        var wasQuoted = false
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
                wasQuoted = true
                continue
            }
            if character == " " || character == "\t", !inQuotes {
                if !current.isEmpty || wasQuoted {
                    tokens.append(Token(text: current, quoted: wasQuoted))
                    current = ""
                    wasQuoted = false
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty || wasQuoted {
            tokens.append(Token(text: current, quoted: wasQuoted))
        }
        return tokens
    }
}
