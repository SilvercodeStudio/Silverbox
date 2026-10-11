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
    var libraryPath: String?
    var stagingExecutablePath: String?
    var dosboxXExecutablePath: String?
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

    init() {}

    /// Missing keys keep their defaults, so adding a setting later never
    /// resets what the user already configured.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        libraryPath = try c.decodeIfPresent(String.self, forKey: .libraryPath)
        stagingExecutablePath = try c.decodeIfPresent(String.self, forKey: .stagingExecutablePath)
        dosboxXExecutablePath = try c.decodeIfPresent(String.self, forKey: .dosboxXExecutablePath)
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
        // Launch arguments such as `-libraryPath /Volumes/eXoDOS` override the
        // saved values for this run only. Handy for testing other installs.
        if let path = defaults.string(forKey: "libraryPath"), !path.isEmpty {
            settings.libraryPath = path
        }
        if defaults.object(forKey: "musicEnabled") != nil {
            settings.musicEnabled = defaults.bool(forKey: "musicEnabled")
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    var libraryRoot: LibraryRoot? {
        guard let libraryPath, !libraryPath.isEmpty else { return nil }
        return LibraryRoot(url: URL(fileURLWithPath: libraryPath, isDirectory: true))
    }

    func emulatorInstallation(_ kind: EmulatorKind) -> EmulatorInstallation? {
        let configured: String?
        switch kind {
        case .dosboxStaging: configured = stagingExecutablePath
        case .dosboxX: configured = dosboxXExecutablePath
        }
        if let configured, !configured.isEmpty {
            let url = EmulatorInstallation.resolveExecutable(from: URL(fileURLWithPath: configured), kind: kind)
            return EmulatorInstallation(kind: kind, executableURL: url)
        }
        return EmulatorLocator.discover(kind)
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
    static var userLibraryState: URL { applicationSupport.appendingPathComponent("user-library.json") }
}
