import Foundation

/// Which Mac emulator runs the games of one LaunchBox platform, chosen by
/// the user in Settings. Platforms without an assignment follow the
/// library's `Emulators.xml`.
nonisolated public struct PlatformEmulatorAssignment: Hashable, Sendable, Codable, Identifiable {
    public var platform: String
    public var emulator: EmulatorKind
    /// The libretro core for RetroArch, for example `fceumm_libretro`.
    public var core: String?
    /// Extra command-line arguments, space separated with double quotes honoured.
    public var arguments: String

    public var id: String { platform }

    public init(platform: String, emulator: EmulatorKind, core: String? = nil, arguments: String = "") {
        self.platform = platform
        self.emulator = emulator
        self.core = core
        self.arguments = arguments
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = try c.decode(String.self, forKey: .platform)
        emulator = try c.decode(EmulatorKind.self, forKey: .emulator)
        core = try c.decodeIfPresent(String.self, forKey: .core)
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case platform, emulator, core, arguments }
}

nonisolated public enum EmulatorAssignmentSource: Sendable, Hashable {
    /// Set by the user in Settings.
    case user
    /// Derived from the library's `Emulators.xml`; the title LaunchBox shows.
    case launchBox(String)
    case none
}

/// The emulator a platform's games start in, after the user's choice, the
/// LaunchBox assignment and what is installed on this Mac are weighed up.
nonisolated public struct ResolvedEmulatorAssignment: Sendable, Hashable {
    public var platform: String
    /// What would run, or nil when nothing applies.
    public var assignment: PlatformEmulatorAssignment?
    public var source: EmulatorAssignmentSource
    /// What the LaunchBox library runs the platform with, for the Settings table.
    public var launchBoxEmulatorTitle: String?
    public var launchBoxCore: String?
    /// Why the assignment cannot start a game right now.
    public var problem: String?
    /// Things worth telling the user, such as a replaced core.
    public var notes: [String]

    public var isReady: Bool { assignment != nil && problem == nil }

    public init(
        platform: String, assignment: PlatformEmulatorAssignment? = nil, source: EmulatorAssignmentSource = .none,
        launchBoxEmulatorTitle: String? = nil, launchBoxCore: String? = nil, problem: String? = nil,
        notes: [String] = []
    ) {
        self.platform = platform
        self.assignment = assignment
        self.source = source
        self.launchBoxEmulatorTitle = launchBoxEmulatorTitle
        self.launchBoxCore = launchBoxCore
        self.problem = problem
        self.notes = notes
    }

    /// A short line for the inspector and the Settings table.
    public var summary: String {
        guard let assignment else { return problem ?? "No emulator assigned" }
        var text = assignment.emulator.displayName
        if assignment.emulator == .retroArch, let core = assignment.core { text += " · \(core)" }
        return text
    }
}

nonisolated extension LaunchBoxEmulator {
    /// The Mac emulator that corresponds to this Windows one, if any.
    public var macKind: EmulatorKind? {
        let name = executableName
        if name.contains("retroarch") { return .retroArch }
        if name.contains("dolphin") { return .dolphin }
        if name.hasPrefix("mame") { return .mame }
        if name.contains("mednafen") { return .mednafen }
        return nil
    }

    /// The emulator's own arguments with Windows-only input providers removed.
    public var portableArguments: [String] {
        guard let commandLine else { return [] }
        return Self.portableArguments(from: commandLine)
    }

    static func portableArguments(from commandLine: String) -> [String] {
        let tokens = CommandLineTokenizer.tokenize(commandLine)
        var result: [String] = []
        var skipNext = false
        for token in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            let lowered = token.lowercased()
            if [
                "-keyboardprovider", "-mouseprovider", "-joystickprovider", "-lightgunprovider", "-uimodekey", "-video",
            ].contains(lowered) {
                skipNext = true
                continue
            }
            result.append(token)
        }
        return result
    }
}

/// Splits a command line on spaces, honouring double quotes.
nonisolated public enum CommandLineTokenizer {
    public static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
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
                    tokens.append(current)
                    current = ""
                    wasQuoted = false
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty || wasQuoted { tokens.append(current) }
        return tokens
    }
}

/// Picks the emulator for each platform.
nonisolated public struct EmulatorAssignmentResolver: Sendable {
    public var userAssignments: [String: PlatformEmulatorAssignment]
    public var launchBoxEmulators: [LaunchBoxEmulator]
    public var launchBoxPlatforms: [LaunchBoxEmulatorPlatform]
    /// The emulators found on this Mac.
    public var installedKinds: Set<EmulatorKind>
    public var retroArch: RetroArchSetup?

    public init(
        userAssignments: [PlatformEmulatorAssignment] = [], launchBoxEmulators: [LaunchBoxEmulator] = [],
        launchBoxPlatforms: [LaunchBoxEmulatorPlatform] = [], installedKinds: Set<EmulatorKind> = [],
        retroArch: RetroArchSetup? = nil
    ) {
        self.userAssignments = Dictionary(
            userAssignments.map { ($0.platform, $0) }, uniquingKeysWith: { _, last in last })
        self.launchBoxEmulators = launchBoxEmulators
        self.launchBoxPlatforms = launchBoxPlatforms
        self.installedKinds = installedKinds
        self.retroArch = retroArch
    }

    /// Everything the user could pick from, taken from several libraries.
    public init(
        userAssignments: [PlatformEmulatorAssignment] = [], snapshots: [LibrarySnapshot],
        installedKinds: Set<EmulatorKind>, retroArch: RetroArchSetup?
    ) {
        self.init(
            userAssignments: userAssignments,
            launchBoxEmulators: snapshots.flatMap(\.emulators),
            launchBoxPlatforms: snapshots.flatMap(\.emulatorPlatforms),
            installedKinds: installedKinds, retroArch: retroArch)
    }

    /// LaunchBox's choices for a platform, the default first.
    public func launchBoxCandidates(for platform: String) -> [(
        emulator: LaunchBoxEmulator, entry: LaunchBoxEmulatorPlatform
    )] {
        let entries = launchBoxPlatforms.filter { $0.platform == platform }
            .sorted { $0.isDefault && !$1.isDefault }
        return entries.compactMap { entry in
            launchBoxEmulators.first { $0.id == entry.emulatorID }.map { ($0, entry) }
        }
    }

    public func resolve(platform: String) -> ResolvedEmulatorAssignment {
        let candidates = launchBoxCandidates(for: platform)
        let launchBoxTitle = candidates.first?.emulator.title
        let launchBoxCore = candidates.first?.entry.retroArchCore

        if let chosen = userAssignments[platform] {
            var resolved = ResolvedEmulatorAssignment(
                platform: platform, assignment: chosen, source: .user,
                launchBoxEmulatorTitle: launchBoxTitle, launchBoxCore: launchBoxCore)
            resolved.problem = problem(for: chosen, notes: &resolved.notes)
            if let core = resolved.assignment?.core, chosen.emulator == .retroArch,
                let found = retroArch?.resolveCore(named: core)
            {
                resolved.assignment?.core = found.name
            }
            return resolved
        }

        var firstFailure: ResolvedEmulatorAssignment?
        for candidate in candidates {
            guard let kind = candidate.emulator.macKind else { continue }
            let source = EmulatorAssignmentSource.launchBox(candidate.emulator.title)
            var attempts: [PlatformEmulatorAssignment] = []
            let core = candidate.entry.retroArchCore
            if kind == .retroArch, let core, let replacement = RetroArchSetup.standaloneReplacements[core],
                retroArch?.coreURL(named: core) == nil
            {
                // The core has no Mac build; the standalone app is the match.
                attempts.append(PlatformEmulatorAssignment(platform: platform, emulator: replacement))
            }
            attempts.append(
                PlatformEmulatorAssignment(
                    platform: platform, emulator: kind, core: core,
                    arguments: kind == .retroArch || kind == .dolphin
                        ? "" : candidate.emulator.portableArguments.joined(separator: " ")))
            for attempt in attempts {
                var resolved = ResolvedEmulatorAssignment(
                    platform: platform, assignment: attempt, source: source,
                    launchBoxEmulatorTitle: launchBoxTitle, launchBoxCore: launchBoxCore)
                resolved.problem = problem(for: attempt, notes: &resolved.notes)
                if resolved.problem == nil {
                    if attempt.emulator == .retroArch, let core = attempt.core,
                        let found = retroArch?.resolveCore(named: core)
                    {
                        resolved.assignment?.core = found.name
                    }
                    if attempt.emulator != kind {
                        resolved.notes.insert(
                            "LaunchBox runs this platform with the \(core ?? "") core, which has no Mac build; \(attempt.emulator.displayName) runs it instead.",
                            at: 0)
                    }
                    return resolved
                }
                if firstFailure == nil { firstFailure = resolved }
            }
        }
        if let firstFailure { return firstFailure }

        var resolved = ResolvedEmulatorAssignment(
            platform: platform, source: candidates.isEmpty ? .none : .launchBox(launchBoxTitle ?? ""),
            launchBoxEmulatorTitle: launchBoxTitle, launchBoxCore: launchBoxCore)
        if let launchBoxTitle {
            resolved.problem =
                "LaunchBox runs this platform with \(launchBoxTitle), which has no Mac version here. Choose an emulator in Settings › Emulators."
        } else {
            resolved.problem = "No emulator is assigned to this platform. Choose one in Settings › Emulators."
        }
        return resolved
    }

    /// Why `assignment` cannot start a game, or nil when it can.
    private func problem(for assignment: PlatformEmulatorAssignment, notes: inout [String]) -> String? {
        guard installedKinds.contains(assignment.emulator) else {
            return "\(assignment.emulator.displayName) is not installed. Choose it in Settings › Emulators."
        }
        guard assignment.emulator == .retroArch else { return nil }
        guard let retroArch, retroArch.coresDirectory != nil else {
            return "RetroArch's cores folder was not found. Choose it in Settings › Emulators."
        }
        guard let core = assignment.core, !core.isEmpty else {
            return "Choose a RetroArch core for this platform in Settings › Emulators."
        }
        let wanted = RetroArchSetup.coreName(from: core)
        guard let found = retroArch.resolveCore(named: wanted) else {
            return
                "The RetroArch core \(wanted) is not installed. Download it in RetroArch (Online Updater › Core Downloader) or choose another core."
        }
        if found.name != wanted {
            notes.append("The \(wanted) core is not installed; \(found.name) runs the game instead.")
        }
        return nil
    }
}
