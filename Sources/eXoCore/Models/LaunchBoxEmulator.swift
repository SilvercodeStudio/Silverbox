import Foundation

/// A LaunchBox emulator definition from `Data/Emulators.xml`.
nonisolated public struct LaunchBoxEmulator: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var applicationPath: String
    public var commandLine: String?
    public var noQuotes: Bool
    public var noSpace: Bool

    public init(
        id: String, title: String, applicationPath: String, commandLine: String? = nil, noQuotes: Bool = false,
        noSpace: Bool = false
    ) {
        self.id = id
        self.title = title
        self.applicationPath = applicationPath
        self.commandLine = commandLine
        self.noQuotes = noQuotes
        self.noSpace = noSpace
    }

    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let id = r["ID"], let title = r["Title"] else { return nil }
        self.init(
            id: id, title: title, applicationPath: r["ApplicationPath"] ?? "", commandLine: r["CommandLine"],
            noQuotes: r.bool("NoQuotes"), noSpace: r.bool("NoSpace"))
    }

    /// The executable name without folders or extension, for example `retroarch`.
    public var executableName: String {
        WindowsPath.baseName(of: applicationPath).lowercased()
    }
}

/// Which emulator (and command line) LaunchBox uses for a platform.
nonisolated public struct LaunchBoxEmulatorPlatform: Hashable, Sendable, Codable {
    public var emulatorID: String
    public var platform: String
    public var commandLine: String?
    public var isDefault: Bool

    public init(emulatorID: String, platform: String, commandLine: String? = nil, isDefault: Bool = false) {
        self.emulatorID = emulatorID
        self.platform = platform
        self.commandLine = commandLine
        self.isDefault = isDefault
    }

    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let emulatorID = r["Emulator"], let platform = r["Platform"] else { return nil }
        self.init(
            emulatorID: emulatorID, platform: platform, commandLine: r["CommandLine"], isDefault: r.bool("Default"))
    }

    /// The libretro core named in a RetroArch command line, for example
    /// `fceumm_libretro` from `-L "cores\fceumm_libretro.dll" -f`.
    public var retroArchCore: String? {
        guard let commandLine, let match = commandLine.firstMatch(of: /-L\s+"?([^"\s]+)"?/) else { return nil }
        let name = WindowsPath.baseName(of: String(match.1))
        return name.isEmpty ? nil : name
    }
}
