import Foundation
import SilverboxCore

/// How Silverbox picks an emulator for a game.
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

/// Light or dark, or whichever the system uses.
enum AppAppearance: String, CaseIterable, Codable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// The two app icons: an amber or a green floppy disk.
enum AppIconVariant: String, CaseIterable, Codable, Identifiable {
    case amber, green

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amber: return "Amber"
        case .green: return "Green"
        }
    }

    /// The image set in the asset catalog that holds the 1024 px icon.
    var imageName: String {
        switch self {
        case .amber: return "AppIconAmber"
        case .green: return "AppIconGreen"
        }
    }

    /// The Icon Composer icon of this colour, when the build compiled it in.
    var iconName: String {
        switch self {
        case .amber: return "AppIcon"
        case .green: return "AppIcon-Green"
        }
    }
}

/// Everything the user configures. Saved as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
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
    /// Keep the menu music playing while another app is in front.
    var musicInBackground = false
    /// The app that plays videos; nil for the macOS default for MP4 files.
    var videoPlayerPath: String?
    var tileSize: Double = Self.defaultTileSize
    static let defaultTileSize: Double = 150
    static let tileSizeRange: ClosedRange<Double> = 96...260
    var viewMode: LibraryViewMode = .grid
    var sortOrder: GameSortOrder = .title
    /// False sorts the other way, set by a click on a list column header.
    var sortAscending = true
    var showHiddenGames = false
    var inspectorShown = true
    /// Which of the two app icons the Dock and the About window show.
    var appIcon: AppIconVariant = .amber
    var appearance: AppAppearance = .system

    static let defaultsKey = "Silverbox.settings"

    /// True when launch arguments replaced the saved collections; such
    /// settings are not written back.
    var transient = false

    init() {}

    /// Missing keys keep their defaults, so adding a setting later never
    /// resets what the user already configured.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collections = try c.decodeIfPresent([LibraryCollection].self, forKey: .collections) ?? []
        localStorePath = try c.decodeIfPresent(String.self, forKey: .localStorePath)
        installLocation = try c.decodeIfPresent(InstallLocation.self, forKey: .installLocation) ?? .localStore
        showLaunchOptions = try c.decodeIfPresent(Bool.self, forKey: .showLaunchOptions) ?? true
        emulatorPaths = try c.decodeIfPresent([String: String].self, forKey: .emulatorPaths) ?? [:]
        retroArchCoresPath = try c.decodeIfPresent(String.self, forKey: .retroArchCoresPath)
        platformEmulators = try c.decodeIfPresent([PlatformEmulatorAssignment].self, forKey: .platformEmulators) ?? []
        emulatorPolicy = try c.decodeIfPresent(EmulatorPolicy.self, forKey: .emulatorPolicy) ?? .recommended
        launchOptions = try c.decodeIfPresent(LaunchOptions.self, forKey: .launchOptions) ?? LaunchOptions()
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? 0.6
        musicInBackground = try c.decodeIfPresent(Bool.self, forKey: .musicInBackground) ?? false
        videoPlayerPath = try c.decodeIfPresent(String.self, forKey: .videoPlayerPath)
        tileSize = try c.decodeIfPresent(Double.self, forKey: .tileSize) ?? Self.defaultTileSize
        viewMode = try c.decodeIfPresent(LibraryViewMode.self, forKey: .viewMode) ?? .grid
        sortOrder = try c.decodeIfPresent(GameSortOrder.self, forKey: .sortOrder) ?? .title
        sortAscending = try c.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? true
        showHiddenGames = try c.decodeIfPresent(Bool.self, forKey: .showHiddenGames) ?? false
        inspectorShown = try c.decodeIfPresent(Bool.self, forKey: .inspectorShown) ?? true
        appIcon = try c.decodeIfPresent(AppIconVariant.self, forKey: .appIcon) ?? .amber
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        var settings = decode(defaults.data(forKey: defaultsKey)) ?? AppSettings()
        // Launch arguments such as `-libraryPath /Volumes/eXoDOS` replace the
        // collections for this run only. Handy for testing other installs.
        // Several folders can be given, separated by "|". `-demoLibrary 1`
        // gives the test fixtures' small libraries.
        if let paths = defaults.string(forKey: "libraryPath") ?? AppPaths.demoLibraryPaths, !paths.isEmpty {
            settings.collections = paths.split(separator: "|").enumerated().map { offset, path in
                let url = URL(fileURLWithPath: String(path), isDirectory: true)
                let id = UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", offset + 1))!
                return LibraryCollection(
                    id: id, name: LibraryCollection.suggestedName(for: url), rootPath: String(path))
            }
            settings.transient = true
        }
        // `-dataPath <folder>` sends installs, caches, logs and the user's
        // state to a scratch folder for this run only, so a test never
        // touches the real data.
        if let folder = AppPaths.scratchData {
            settings.localStorePath = folder.path
            settings.installLocation = .localStore
            settings.transient = true
        }
        if defaults.object(forKey: "musicEnabled") != nil {
            settings.musicEnabled = defaults.bool(forKey: "musicEnabled")
        }
        if let name = defaults.string(forKey: "appearance"), let appearance = AppAppearance(rawValue: name) {
            settings.appearance = appearance
        }
        return settings
    }

    private static func decode(_ data: Data?) -> AppSettings? {
        data.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
    }

    func save(to defaults: UserDefaults = .standard) {
        guard !transient else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case collections, localStorePath, installLocation, showLaunchOptions, emulatorPaths, retroArchCoresPath,
            platformEmulators, emulatorPolicy, launchOptions,
            musicEnabled, musicVolume, musicInBackground, videoPlayerPath, tileSize, viewMode, sortOrder, sortAscending,
            showHiddenGames,
            inspectorShown,
            appIcon, appearance
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
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
        try c.encode(musicInBackground, forKey: .musicInBackground)
        try c.encodeIfPresent(videoPlayerPath, forKey: .videoPlayerPath)
        try c.encode(tileSize, forKey: .tileSize)
        try c.encode(viewMode, forKey: .viewMode)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(sortAscending, forKey: .sortAscending)
        try c.encode(showHiddenGames, forKey: .showHiddenGames)
        try c.encode(inspectorShown, forKey: .inspectorShown)
        try c.encode(appIcon, forKey: .appIcon)
        try c.encode(appearance, forKey: .appearance)
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

/// Folders Silverbox writes to. Bulky and disposable things (installed games,
/// caches, launch configs, logs) live under the local data folder, which the
/// user can move to another drive; the small, important `user-library.json`
/// (favorites, play history) stays in Application Support with the settings.
enum AppPaths {
    /// `~/Library/Application Support/Silverbox`.
    static let applicationSupport: URL = {
        let fm = FileManager.default
        let base =
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Silverbox", isDirectory: true)
    }()

    /// The local data folder chosen in Settings, when there is one. Set by
    /// `AppModel` whenever the setting changes.
    static var customRoot: URL?

    static var dataRoot: URL { customRoot ?? applicationSupport }

    static var launchConfigs: URL { dataRoot.appendingPathComponent("Launch", isDirectory: true) }
    static var logs: URL { dataRoot.appendingPathComponent("Logs", isDirectory: true) }
    static var mediaIndexes: URL { dataRoot.appendingPathComponent("MediaIndex", isDirectory: true) }
    static var libraryCache: URL { dataRoot.appendingPathComponent("LibraryCache", isDirectory: true) }
    static var userLibraryState: URL {
        (scratchData ?? applicationSupport).appendingPathComponent("user-library.json")
    }

    /// The scratch data folder for this run: `-dataPath <folder>`, or a
    /// folder in the temporary folder for `-demoLibrary 1`. Nil normally.
    static let scratchData: URL? = {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "dataPath"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard demoLibraryPaths != nil else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("Silverbox Demo", isDirectory: true)
    }()

    /// The test fixtures' eXoDOS-style and console libraries, for
    /// `-demoLibrary 1` in a debug build run from this source tree.
    static var demoLibraryPaths: String? {
        #if DEBUG
            guard UserDefaults.standard.bool(forKey: "demoLibrary") else { return nil }
            let fixtures = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tests/SilverboxCoreTests/Fixtures", isDirectory: true)
            return [fixtures, fixtures.appendingPathComponent("ConsoleLibrary", isDirectory: true)]
                .map(\.path).joined(separator: "|")
        #else
            return nil
        #endif
    }
}
