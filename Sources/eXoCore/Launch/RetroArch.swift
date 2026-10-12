import Foundation

/// A libretro core installed for RetroArch, with the details from its
/// `.info` file when RetroArch has one.
nonisolated public struct RetroArchCore: Hashable, Sendable, Identifiable, Codable {
    /// The core's base name, for example `fceumm_libretro`.
    public var name: String
    public var url: URL
    /// RetroArch's name for the core, for example `Nintendo - NES / Famicom (FCEUmm)`.
    public var displayName: String?
    public var systemName: String?
    public var supportedExtensions: [String]

    public var id: String { name }
    public var title: String { displayName ?? name }

    public init(name: String, url: URL, displayName: String? = nil, systemName: String? = nil, supportedExtensions: [String] = []) {
        self.name = name
        self.url = url
        self.displayName = displayName
        self.systemName = systemName
        self.supportedExtensions = supportedExtensions
    }
}

/// Where RetroArch keeps its cores and core info on this Mac.
nonisolated public struct RetroArchSetup: Sendable, Hashable {
    public var installation: EmulatorInstallation
    public var coresDirectory: URL?
    public var infoDirectory: URL?

    public init(installation: EmulatorInstallation, coresDirectory: URL?, infoDirectory: URL?) {
        self.installation = installation
        self.coresDirectory = coresDirectory
        self.infoDirectory = infoDirectory
    }

    /// RetroArch's user folder on macOS.
    public static var userDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RetroArch", isDirectory: true)
    }

    public static var configFile: URL {
        userDirectory.appendingPathComponent("config/retroarch.cfg")
    }

    /// Reads `retroarch.cfg` for the cores and info folders, falling back to
    /// the default places. `coresDirectoryOverride` wins when given.
    public static func discover(installation: EmulatorInstallation, coresDirectoryOverride: URL? = nil,
                                configFile: URL = RetroArchSetup.configFile) -> RetroArchSetup {
        let fm = FileManager.default
        let config = Self.parseConfig(at: configFile)
        let bundleResources = installation.appBundleURL?.appendingPathComponent("Contents/Resources", isDirectory: true)

        func firstExisting(_ candidates: [URL?]) -> URL? {
            candidates.compactMap { $0 }.first { fm.fileExists(atPath: $0.path) }
        }

        let cores = coresDirectoryOverride ?? firstExisting([
            config["libretro_directory"].flatMap { Self.directory(fromConfigValue: $0, bundleResources: bundleResources) },
            userDirectory.appendingPathComponent("cores", isDirectory: true),
            bundleResources?.appendingPathComponent("cores", isDirectory: true),
        ])
        let info = firstExisting([
            config["libretro_info_path"].flatMap { Self.directory(fromConfigValue: $0, bundleResources: bundleResources) },
            userDirectory.appendingPathComponent("info", isDirectory: true),
            bundleResources?.appendingPathComponent("info", isDirectory: true),
            cores,
        ])
        return RetroArchSetup(installation: installation, coresDirectory: cores, infoDirectory: info)
    }

    /// `key = "value"` lines from a RetroArch config file.
    static func parseConfig(at url: URL) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [:] }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    /// Expands the `~` and `:` prefixes RetroArch uses in its config paths.
    /// `:` stands for the application folder, which is the app bundle's
    /// Resources folder on the Mac.
    static func directory(fromConfigValue value: String, bundleResources: URL?) -> URL? {
        if value.isEmpty || value == "default" { return nil }
        if value.hasPrefix("~") {
            let rest = value.dropFirst()
            return URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + rest, isDirectory: true)
        }
        if value.hasPrefix(":") {
            guard let bundleResources else { return nil }
            let rest = value.dropFirst().drop(while: { $0 == "/" })
            return rest.isEmpty ? bundleResources : bundleResources.appendingPathComponent(String(rest), isDirectory: true)
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// Cores that RetroArch no longer ships under their LaunchBox-era names,
    /// and the cores that replace them on the Mac.
    public static let coreAliases: [String: [String]] = [
        "fbalpha_libretro": ["fbneo_libretro"],
        "fbalpha2012_libretro": ["fbneo_libretro"],
        "duckstation_libretro": ["swanstation_libretro", "mednafen_psx_hw_libretro", "pcsx_rearmed_libretro"],
        "vba_next_libretro": ["mgba_libretro"],
        "mednafen_psx_libretro": ["mednafen_psx_hw_libretro"],
        "snes9x2010_libretro": ["snes9x_libretro"],
        "mupen64plus_libretro": ["mupen64plus_next_libretro"],
    ]

    /// Cores that have no Mac build; the standalone app that covers the platform instead.
    public static let standaloneReplacements: [String: EmulatorKind] = [
        "dolphin_libretro": .dolphin,
        "pcsx2_libretro": .mednafen,
    ]

    /// Normalises a core name from a LaunchBox command line or a user entry:
    /// `fceumm`, `fceumm_libretro`, `cores\fceumm_libretro.dll` all give `fceumm_libretro`.
    public static func coreName(from text: String) -> String {
        var name = WindowsPath.baseName(of: text.trimmingCharacters(in: .whitespacesAndNewlines))
        if name.hasSuffix(".dylib") || name.hasSuffix(".dll") || name.hasSuffix(".so") {
            name = WindowsPath.baseName(of: name)
        }
        if !name.hasSuffix("_libretro"), !name.isEmpty { name += "_libretro" }
        return name
    }

    public func coreURL(named name: String) -> URL? {
        guard let coresDirectory else { return nil }
        let url = coresDirectory.appendingPathComponent("\(Self.coreName(from: name)).dylib")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The installed core for `name`, or an installed replacement for it.
    public func resolveCore(named name: String) -> (name: String, url: URL)? {
        let wanted = Self.coreName(from: name)
        if let url = coreURL(named: wanted) { return (wanted, url) }
        for alias in Self.coreAliases[wanted] ?? [] {
            if let url = coreURL(named: alias) { return (alias, url) }
        }
        return nil
    }

    /// Every `*_libretro.dylib` in the cores folder, sorted by title.
    public func installedCores() -> [RetroArchCore] {
        guard let coresDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(at: coresDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var cores: [RetroArchCore] = []
        for url in entries where url.pathExtension == "dylib" && url.deletingPathExtension().lastPathComponent.hasSuffix("_libretro") {
            let name = url.deletingPathExtension().lastPathComponent
            let info = coreInfo(named: name)
            cores.append(RetroArchCore(name: name, url: url, displayName: info["display_name"], systemName: info["systemname"],
                                       supportedExtensions: (info["supported_extensions"] ?? "").split(separator: "|").map { String($0).lowercased() }))
        }
        return cores.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func coreInfo(named name: String) -> [String: String] {
        guard let infoDirectory else { return [:] }
        return Self.parseConfig(at: infoDirectory.appendingPathComponent("\(name).info"))
    }
}
