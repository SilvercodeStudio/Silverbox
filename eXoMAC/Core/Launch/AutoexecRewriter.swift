import Foundation

/// Rewrites the `[autoexec]` section of an eXoDOS config for a Mac emulator.
///
/// eXoDOS launchers run DOSBox from the `eXo/` folder, so host paths in
/// `mount` and `imgmount` lines are Windows-relative to it, for example
/// `mount c .\eXoDOS\`. Those become absolute POSIX paths. Windows-only
/// CD-ROM flags are dropped.
nonisolated public struct AutoexecRewriter: Sendable {
    /// The folder the original launchers used as the working directory.
    public let baseDirectory: URL
    /// Folders tried in order when a relative path does not exist under
    /// `baseDirectory`: a few menus run DOSBox from the game folder instead.
    public let fallbackDirectories: [URL]

    public init(baseDirectory: URL, fallbackDirectories: [URL] = []) {
        self.baseDirectory = baseDirectory
        self.fallbackDirectories = fallbackDirectories
    }

    nonisolated public struct Result: Sendable, Hashable {
        public var lines: [String]
        public var notes: [String]
    }

    private static let pathCommands: Set<String> = ["mount", "imgmount", "boot"]
    private static let droppedFlags: Set<String> = ["-ioctl", "-ioctl_dx", "-ioctl_dio", "-ioctl_mci", "-noioctl", "-aspi"]
    private static let droppedFlagsWithValue: Set<String> = ["-usecd"]
    private static let flagsWithValue: Set<String> = ["-t", "-label", "-freesize", "-fs", "-size", "-ide", "-l", "-o"]

    public func rewrite(_ lines: [String]) -> Result {
        var out: [String] = []
        var notes: [String] = []
        for line in lines {
            out.append(rewriteLine(line, notes: &notes))
        }
        return Result(lines: out, notes: notes)
    }

    func rewriteLine(_ rawLine: String, notes: inout [String]) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        var prefix = ""
        if line.hasPrefix("@") {
            prefix = "@"
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        let tokens = Self.tokenize(line)
        guard let first = tokens.first else { return rawLine }
        let command = first.text.lowercased()
        guard Self.pathCommands.contains(command) else { return rawLine }

        var rebuilt: [String] = [first.text]
        var index = 1
        var sawDrive = command == "boot"
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
                rebuilt.append(token.text)
                index += 1
                continue
            }
            if Self.looksLikeHostPath(token.text, quoted: token.quoted) {
                rebuilt.append(hostPath(token.text, notes: &notes))
            } else {
                rebuilt.append(token.quoted ? "\"\(token.text)\"" : token.text)
            }
            index += 1
        }
        return prefix + rebuilt.joined(separator: " ")
    }

    /// Host paths carry a separator or start with `.`; bare names such as
    /// `GAME.IMG` are DOS-side paths that the emulator resolves itself.
    static func looksLikeHostPath(_ text: String, quoted: Bool) -> Bool {
        if text.contains("\\") || text.contains("/") { return true }
        return text.hasPrefix(".")
    }

    /// Converts a Windows-relative host path to a quoted absolute POSIX path.
    public func hostPath(_ text: String, notes: inout [String]) -> String {
        let posix = WindowsPath.posix(text)
        if posix.hasPrefix("/") {
            return "\"\(posix)\""
        }
        if WindowsPath.isAbsolute(text) {
            notes.append("Kept absolute Windows path \(text); it will not exist on this Mac.")
            return "\"\(posix)\""
        }
        let resolved = WindowsPath.resolve(text, against: baseDirectory)
        if FileManager.default.fileExists(atPath: resolved.path) { return "\"\(resolved.path)\"" }
        for fallback in fallbackDirectories {
            let candidate = WindowsPath.resolve(text, against: fallback)
            if FileManager.default.fileExists(atPath: candidate.path) {
                notes.append("Resolved \(text) relative to \(fallback.lastPathComponent) because it does not exist under eXo.")
                return "\"\(candidate.path)\""
            }
        }
        if fallbackDirectories.isEmpty || !FileManager.default.fileExists(atPath: baseDirectory.path) {
            // Nothing to check against (unit tests, missing library): resolve blindly.
            return "\"\(resolved.path)\""
        }
        // Not a host path we can find. Leave it for the emulator, which also
        // tries the path on the mounted DOS drives.
        notes.append("Could not find \(text) on disk; the emulator will look it up on the mounted DOS drives.")
        return "\"\(text)\""
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
