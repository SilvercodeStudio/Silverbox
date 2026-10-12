import eXoCore
import Foundation

/// How eXoMAC picks an emulator for a game.
enum EmulatorPolicy: String, CaseIterable, Codable, Identifiable {
    case recommended
    case alwaysStaging
    case alwaysDOSBoxX

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recommended: return "Match the build eXoDOS uses"
        case .alwaysStaging: return "Always DOSBox Staging"
        case .alwaysDOSBoxX: return "Always DOSBox-X"
        }
    }
}

enum LibraryViewMode: String, Codable, CaseIterable {
    case grid, list
}

/// Everything the user configures. Saved as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    /// Kept for migration from the single-library days.
    var libraryPath: String?
    var collections: [LibraryCollection] = []
    var localStorePath: String?
    var installLocation: InstallLocation = .localStore
    var showLaunchOptions = true
    /// Chosen emulator executables, keyed by `EmulatorKind.rawValue`; kinds
    /// not listed are found automatically.
    var emulatorPaths: [String: String] = [:]
    /// RetroArch's cores folder when the user chose one.
    var retroArchCoresPath: String?
    /// Which emulator runs each platform; platforms not listed follow LaunchBox.
    var platformEmulators: [PlatformEmulatorAssignment] = []
    var emulatorPolicy: EmulatorPolicy = .recommended
    var launchOptions = LaunchOptions()
    var musicEnabled = true
    var musicVolume: Double = 0.6
    var tileSize: Double = 150
    var viewMode: LibraryViewMode = .grid
    var sortOrder: GameSortOrder = .title
    var showHiddenGames = false
    var inspectorShown = true

    static let defaultsKey = "eXoMAC.settings"

    /// True when launch arguments replaced the saved collections; such
    /// settings are not written back.
    var transient = false

    init() {}

    /// Missing keys keep their defaults, so adding a setting later never
    /// resets what the user already configured.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        libraryPath = try c.decodeIfPresent(String.self, forKey: .libraryPath)
        collections = try c.decodeIfPresent([LibraryCollection].self, forKey: .collections) ?? []
        localStorePath = try c.decodeIfPresent(String.self, forKey: .localStorePath)
        installLocation = try c.decodeIfPresent(InstallLocation.self, forKey: .installLocation) ?? .localStore
        showLaunchOptions = try c.decodeIfPresent(Bool.self, forKey: .showLaunchOptions) ?? true
        emulatorPaths = try c.decodeIfPresent([String: String].self, forKey: .emulatorPaths) ?? [:]
        // Paths saved before every emulator had a slot in the dictionary.
        if let legacy = try c.decodeIfPresent(String.self, forKey: .stagingExecutablePath), emulatorPaths[EmulatorKind.dosboxStaging.rawValue] == nil {
            emulatorPaths[EmulatorKind.dosboxStaging.rawValue] = legacy
        }
        if let legacy = try c.decodeIfPresent(String.self, forKey: .dosboxXExecutablePath), emulatorPaths[EmulatorKind.dosboxX.rawValue] == nil {
            emulatorPaths[EmulatorKind.dosboxX.rawValue] = legacy
        }
        retroArchCoresPath = try c.decodeIfPresent(String.self, forKey: .retroArchCoresPath)
        platformEmulators = try c.decodeIfPresent([PlatformEmulatorAssignment].self, forKey: .platformEmulators) ?? []
        emulatorPolicy = try c.decodeIfPresent(EmulatorPolicy.self, forKey: .emulatorPolicy) ?? .recommended
        launchOptions = try c.decodeIfPresent(LaunchOptions.self, forKey: .launchOptions) ?? LaunchOptions()
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? 0.6
        tileSize = try c.decodeIfPresent(Double.self, forKey: .tileSize) ?? 150
        viewMode = try c.decodeIfPresent(LibraryViewMode.self, forKey: .viewMode) ?? .grid
        sortOrder = try c.decodeIfPresent(GameSortOrder.self, forKey: .sortOrder) ?? .title
        showHiddenGames = try c.decodeIfPresent(Bool.self, forKey: .showHiddenGames) ?? false
        inspectorShown = try c.decodeIfPresent(Bool.self, forKey: .inspectorShown) ?? true
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        var settings = AppSettings()
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        }
        // A library chosen before collections existed becomes the first collection.
        if settings.collections.isEmpty, let path = settings.libraryPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            settings.collections = [LibraryCollection(name: LibraryCollection.suggestedName(for: url), rootPath: path)]
            settings.libraryPath = nil
        }
        // Launch arguments such as `-libraryPath /Volumes/eXoDOS` replace the
        // collections for this run only. Handy for testing other installs.
        // Several folders can be given, separated by "|".
        if let paths = defaults.string(forKey: "libraryPath"), !paths.isEmpty {
            settings.collections = paths.split(separator: "|").enumerated().map { offset, path in
                let url = URL(fileURLWithPath: String(path), isDirectory: true)
                let id = UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", offset + 1))!
                return LibraryCollection(id: id, name: LibraryCollection.suggestedName(for: url), rootPath: String(path))
            }
            settings.transient = true
        }
        if defaults.object(forKey: "musicEnabled") != nil {
            settings.musicEnabled = defaults.bool(forKey: "musicEnabled")
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard !transient else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case libraryPath, collections, localStorePath, installLocation, showLaunchOptions, stagingExecutablePath,
             dosboxXExecutablePath, emulatorPaths, retroArchCoresPath, platformEmulators, emulatorPolicy, launchOptions,
             musicEnabled, musicVolume, tileSize, viewMode, sortOrder, showHiddenGames, inspectorShown
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(libraryPath, forKey: .libraryPath)
        try c.encode(collections, forKey: .collections)
        try c.encodeIfPresent(localStorePath, forKey: .localStorePath)
        try c.encode(installLocation, forKey: .installLocation)
        try c.encode(showLaunchOptions, forKey: .showLaunchOptions)
        try c.encode(emulatorPaths, forKey: .emulatorPaths)
        try c.encodeIfPresent(retroArchCoresPath, forKey: .retroArchCoresPath)
        try c.encode(platformEmulators, forKey: .platformEmulators)
        try c.encode(emulatorPolicy, forKey: .emulatorPolicy)
        try c.encode(launchOptions, forKey: .launchOptions)
        try c.encode(musicEnabled, forKey: .musicEnabled)
        try c.encode(musicVolume, forKey: .musicVolume)
        try c.encode(tileSize, forKey: .tileSize)
        try c.encode(viewMode, forKey: .viewMode)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(showHiddenGames, forKey: .showHiddenGames)
        try c.encode(inspectorShown, forKey: .inspectorShown)
    }

    var enabledCollections: [LibraryCollection] { collections.filter(\.isEnabled) }

    /// The writable companion folder; Application Support unless chosen.
    var localStore: LocalStore {
        if let localStorePath, !localStorePath.isEmpty {
            return LocalStore(directory: URL(fileURLWithPath: localStorePath, isDirectory: true))
        }
        return LocalStore(directory: AppPaths.applicationSupport)
    }

    func emulatorInstallation(_ kind: EmulatorKind) -> EmulatorInstallation? {
        if let configured = emulatorPath(for: kind), !configured.isEmpty {
            let url = EmulatorInstallation.resolveExecutable(from: URL(fileURLWithPath: configured), kind: kind)
            return EmulatorInstallation(kind: kind, executableURL: url)
        }
        return EmulatorLocator.discover(kind)
    }

    func emulatorPath(for kind: EmulatorKind) -> String? {
        emulatorPaths[kind.rawValue]
    }

    mutating func setEmulatorPath(_ path: String?, for kind: EmulatorKind) {
        emulatorPaths[kind.rawValue] = path
    }

    /// The emulators for consoles and arcade that are present on this Mac.
    var installedRomEmulators: Set<EmulatorKind> {
        Set(EmulatorKind.romEmulators.filter { emulatorInstallation($0)?.exists == true })
    }

    /// RetroArch with its cores folder, when RetroArch is installed.
    var retroArchSetup: RetroArchSetup? {
        guard let installation = emulatorInstallation(.retroArch), installation.exists else { return nil }
        let override = retroArchCoresPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return RetroArchSetup.discover(installation: installation, coresDirectoryOverride: override)
    }

    func platformAssignment(for platform: String) -> PlatformEmulatorAssignment? {
        platformEmulators.first { $0.platform == platform }
    }

    mutating func setPlatformAssignment(_ assignment: PlatformEmulatorAssignment?, for platform: String) {
        platformEmulators.removeAll { $0.platform == platform }
        if let assignment { platformEmulators.append(assignment) }
    }
}

/// Folders eXoMAC writes to under Application Support.
enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("eXoMAC", isDirectory: true)
    }

    static var launchConfigs: URL { applicationSupport.appendingPathComponent("Launch", isDirectory: true) }
    static var logs: URL { applicationSupport.appendingPathComponent("Logs", isDirectory: true) }
    static var mediaIndexes: URL { applicationSupport.appendingPathComponent("MediaIndex", isDirectory: true) }
    static var libraryCache: URL { applicationSupport.appendingPathComponent("LibraryCache", isDirectory: true) }
    static var userLibraryState: URL { applicationSupport.appendingPathComponent("user-library.json") }
}
