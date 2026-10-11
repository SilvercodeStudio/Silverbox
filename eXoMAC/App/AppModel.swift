import Foundation
import Observation
import AppKit

/// The app's state: the loaded library, the current selection, user data,
/// and the services that play music and launch games.
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        case loading(LibraryLoadProgress)
        case loaded
        case failed(String)
    }

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.musicVolume != oldValue.musicVolume { music.volume = settings.musicVolume }
            if settings.musicEnabled != oldValue.musicEnabled { updateMusic() }
            if settings.sortOrder != oldValue.sortOrder || settings.showHiddenGames != oldValue.showHiddenGames {
                refreshVisibleGames()
            }
            if settings.localStorePath != oldValue.localStorePath { reloadLibrary() }
        }
    }

    private(set) var loadState: LoadState = .idle
    private(set) var library: LibrarySnapshot?
    private(set) var media: MediaCatalog?
    private(set) var searchIndex: LibrarySearchIndex?
    private(set) var rootReport: LibraryRootReport?

    var userState: UserLibraryState {
        didSet { scheduleUserStateSave() }
    }

    var scope: LibraryScope = .all { didSet { refreshVisibleGames() } }
    var searchText = "" { didSet { scheduleSearchRefresh() } }
    private(set) var visibleGames: [Game] = []
    var selectedGameID: String? { didSet { updateMusic() } }
    var openedGameID: String?
    var pendingInstall: Game?
    var pendingUninstall: Game?
    var pendingInfoGame: Game?
    var pendingLaunch: PendingLaunch?
    var alert: AppAlert?

    /// A game waiting in the launch options dialog.
    struct PendingLaunch: Identifiable {
        let id = UUID()
        let game: Game
        let variants: [LaunchVariant]
    }

    let thumbnails = ThumbnailCache()
    let music = MenuMusicPlayer()
    let launcher = GameLauncher()

    private let userStateStore = UserLibraryStateStore(url: AppPaths.userLibraryState)
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSelectTitle: String?
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    struct AppAlert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    init() {
        settings = AppSettings.load()
        userState = (try? userStateStore.load()) ?? UserLibraryState()
        music.volume = settings.musicVolume
        // Debug conveniences: `-searchText ultima -selectTitle "Ultima V: Warriors of Destiny"`.
        if let text = UserDefaults.standard.string(forKey: "searchText") { searchText = text }
        pendingSelectTitle = UserDefaults.standard.string(forKey: "selectTitle")
        launcher.onSessionEnded = { [weak self] session in
            self?.sessionEnded(session)
        }
        if settings.libraryRoot != nil {
            reloadLibrary()
        }
    }

    // MARK: - Library loading

    var libraryRoot: LibraryRoot? { settings.libraryRoot }
    var localStore: LocalStore { settings.localStore }

    func setLibrary(url: URL) {
        settings.libraryPath = url.path
        reloadLibrary(clearMediaCache: true)
    }

    /// Reads the library again. Pass `clearMediaCache` for an explicit rescan,
    /// so saved media indexes are rebuilt from the folders.
    func reloadLibrary(clearMediaCache: Bool = false) {
        loadTask?.cancel()
        if clearMediaCache { MediaIndexStore(directory: AppPaths.mediaIndexes).clear() }
        guard let root = settings.libraryRoot else {
            loadState = .idle
            library = nil
            return
        }
        rootReport = root.inspect()
        let localStore = settings.localStore
        try? localStore.ensureDirectories()
        loadState = .loading(LibraryLoadProgress(stage: "Starting", fraction: 0, gamesLoaded: 0))
        let report: @Sendable (LibraryLoadProgress) -> Void = { progress in
            Task { @MainActor in self.reportLoadProgress(progress) }
        }
        loadTask = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try LibraryLoader(root: root, localStore: localStore).load(progress: report)
                }.value
                let index = await Task.detached(priority: .utility) { LibrarySearchIndex(snapshot: snapshot) }.value
                guard let self, !Task.isCancelled else { return }
                self.library = snapshot
                let media = MediaCatalog(snapshot: snapshot, indexStore: MediaIndexStore(directory: AppPaths.mediaIndexes))
                self.media = media
                self.searchIndex = index
                self.loadState = .loaded
                self.refreshVisibleGames()
                // Biggest platforms first, so the main grid gets its covers soonest.
                let counts = Dictionary(grouping: snapshot.games, by: \.platform).mapValues(\.count)
                let platforms = snapshot.platforms.map(\.name).sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
                Task.detached(priority: .utility) { await media.prewarm(platforms: platforms) }
            } catch {
                self?.loadState = .failed(error.localizedDescription)
            }
        }
    }

    private func reportLoadProgress(_ progress: LibraryLoadProgress) {
        if case .loading = loadState { loadState = .loading(progress) }
    }

    // MARK: - Selection and queries

    var selectedGame: Game? {
        guard let selectedGameID else { return nil }
        return library?.game(id: selectedGameID)
    }

    var openedGame: Game? {
        guard let openedGameID else { return nil }
        return library?.game(id: openedGameID)
    }

    var query: LibraryQuery? {
        library.map(LibraryQuery.init(snapshot:))
    }

    func refreshVisibleGames() {
        guard let query else { visibleGames = []; return }
        var games = query.games(in: scope, overlay: userState)
        if !settings.showHiddenGames {
            games = games.filter { !(userState.state(for: $0.id).hidden ?? $0.hidden) }
        }
        games = query.filter(games, search: searchText, index: searchIndex)
        if scope != .recentlyPlayed {
            games = query.sort(games, by: settings.sortOrder, overlay: userState)
        }
        visibleGames = games
        if let title = pendingSelectTitle, let match = games.first(where: { $0.title == title }) {
            pendingSelectTitle = nil
            selectedGameID = match.id
            if UserDefaults.standard.bool(forKey: "autoPlay") {
                Task { @MainActor in self.play(match) }
            }
        }
        if let selectedGameID, !games.contains(where: { $0.id == selectedGameID }) {
            self.selectedGameID = games.first?.id
        } else if selectedGameID == nil {
            selectedGameID = games.first?.id
        }
    }

    private func scheduleSearchRefresh() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.refreshVisibleGames()
        }
    }

    func scopeTitle(_ scope: LibraryScope) -> String {
        switch scope {
        case .all: return "All Games"
        case .favorites: return "Favorites"
        case .installed: return "Installed"
        case .recentlyPlayed: return "Recently Played"
        case .node(let ref): return library?.node(for: ref)?.title ?? "Library"
        }
    }

    // MARK: - Per-game state

    func isFavorite(_ game: Game) -> Bool {
        userState.state(for: game.id).favorite ?? game.favorite
    }

    func toggleFavorite(_ game: Game) {
        let next = !isFavorite(game)
        userState.update(game.id) { $0.favorite = next == game.favorite ? nil : next }
        if scope == .favorites { refreshVisibleGames() }
    }

    func isInstalled(_ game: Game) -> Bool {
        library?.isInstalled(game) ?? false
    }

    func playCount(_ game: Game) -> Int {
        game.playCount + userState.state(for: game.id).playCount
    }

    func playTimeSeconds(_ game: Game) -> Int {
        game.playTimeSeconds + userState.state(for: game.id).playTimeSeconds
    }

    func lastPlayed(_ game: Game) -> Date? {
        userState.state(for: game.id).lastPlayed ?? game.lastPlayed
    }

    private func scheduleUserStateSave() {
        saveTask?.cancel()
        let state = userState
        let store = userStateStore
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? store.save(state)
        }
    }

    // MARK: - Launching

    func emulatorKind(for game: Game) -> EmulatorKind {
        if let override = userState.state(for: game.id).emulatorOverride { return override }
        return defaultEmulatorKind(for: game)
    }

    /// The emulator the settings policy picks, ignoring per-game overrides.
    func defaultEmulatorKind(for game: Game) -> EmulatorKind {
        switch settings.emulatorPolicy {
        case .alwaysStaging: return .dosboxStaging
        case .alwaysDOSBoxX: return .dosboxX
        case .recommended:
            guard let library else { return .dosboxStaging }
            return LaunchPlanner(snapshot: library, scratchDirectory: AppPaths.launchConfigs).recommendedEmulator(for: game)
        }
    }

    func launchVariants(for game: Game) -> [LaunchVariant] {
        guard let library else { return [] }
        return LaunchPlanner(snapshot: library, scratchDirectory: AppPaths.launchConfigs).variants(for: game)
    }

    func eXoDOSBuild(for game: Game) -> EXoDOSBuild? {
        library?.dosboxIndex.build(forLauncherBaseName: game.launcherBaseName)
    }

    /// The global launch options with this game's remembered choices applied.
    func effectiveLaunchOptions(for game: Game) -> LaunchOptions {
        settings.launchOptions.applying(userState.state(for: game.id).launchOverrides)
    }

    func preferredVariant(for game: Game, in variants: [LaunchVariant]) -> LaunchVariant? {
        guard !variants.isEmpty else { return nil }
        if let preferred = userState.state(for: game.id).preferredVariantID,
           let variant = variants.first(where: { $0.id == preferred }) {
            return variant
        }
        return variants.first { !$0.needsWindowsHelper } ?? variants.first
    }

    /// Plays the game: opens non-game items, offers installation, shows the
    /// launch options dialog, or starts the emulator right away.
    func play(_ game: Game, variant: LaunchVariant? = nil) {
        guard let library else { return }
        guard game.isDOSGame else {
            openNonGameItem(game)
            return
        }
        guard library.isInstalled(game) else {
            pendingInstall = game
            return
        }
        let variants = launchVariants(for: game)
        if settings.showLaunchOptions, variant == nil {
            pendingLaunch = PendingLaunch(game: game, variants: variants)
            return
        }
        launch(game, variant: variant ?? preferredVariant(for: game, in: variants),
               options: effectiveLaunchOptions(for: game), emulatorKind: emulatorKind(for: game))
    }

    /// Starts the emulator with explicit choices.
    func launch(_ game: Game, variant: LaunchVariant?, options: LaunchOptions, emulatorKind kind: EmulatorKind) {
        guard let library else { return }
        guard let emulator = settings.emulatorInstallation(kind), emulator.exists else {
            alert = AppAlert(title: "\(kind.displayName) not found",
                             message: "Choose the \(kind.displayName) application in Settings › Emulators.")
            return
        }
        let planner = LaunchPlanner(snapshot: library, scratchDirectory: AppPaths.launchConfigs)
        do {
            let plan = try planner.plan(game: game, variant: variant, emulator: emulator, options: options)
            try plan.writeConfig()
            music.pause()
            try launcher.launch(plan)
        } catch {
            alert = AppAlert(title: "Could not start \(game.title)", message: error.localizedDescription)
            updateMusic()
        }
    }

    /// Keeps the launch dialog's choices for next time.
    func rememberLaunchChoices(for game: Game, options: LaunchOptions, variant: LaunchVariant?, emulatorKind kind: EmulatorKind) {
        let overrides = LaunchOverrides(base: settings.launchOptions, chosen: options)
        let defaultKind = defaultEmulatorKind(for: game)
        userState.update(game.id) { state in
            state.launchOverrides = overrides.isEmpty ? nil : overrides
            state.preferredVariantID = variant?.id
            state.emulatorOverride = kind == defaultKind ? nil : kind
        }
    }

    func forgetLaunchChoices(for game: Game) {
        userState.update(game.id) { state in
            state.launchOverrides = nil
            state.preferredVariantID = nil
            state.emulatorOverride = nil
        }
    }

    // MARK: - Config overrides

    func overrideConfigURL(for game: Game) -> URL? {
        guard let library else { return nil }
        return LaunchPlanner(snapshot: library, scratchDirectory: AppPaths.launchConfigs).overrideConfigURL(for: game, variant: nil)
    }

    /// Copies the game's config into the local store (once) and opens it.
    func editConfig(for game: Game) {
        guard let library, let folder = game.rootFolder else { return }
        let source = library.root.url(forWindowsRelativePath: folder).appendingPathComponent("dosbox.conf")
        let target = localStore.overrideConfigURL(for: game, configName: "dosbox.conf")
        do {
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
            }
            NSWorkspace.shared.open(target)
        } catch {
            alert = AppAlert(title: "Could not copy the config", message: error.localizedDescription)
        }
    }

    func revertConfig(for game: Game) {
        let target = localStore.overrideConfigURL(for: game, configName: "dosbox.conf")
        try? FileManager.default.removeItem(at: target)
    }

    private func openNonGameItem(_ game: Game) {
        guard let library else { return }
        let url = library.root.url(forWindowsRelativePath: game.applicationPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alert = AppAlert(title: "File not found", message: url.path)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func sessionEnded(_ session: GameSession) {
        let seconds = Int(Date().timeIntervalSince(session.startedAt))
        userState.recordPlay(session.plan.game.id, seconds: seconds)
        if session.exitStatus != 0, let log = session.logURL {
            alert = AppAlert(title: "\(session.plan.game.title) exited with code \(session.exitStatus)",
                             message: "The emulator log is at \(log.path)")
        }
        updateMusic()
        if scope == .recentlyPlayed { refreshVisibleGames() }
    }

    // MARK: - Installing

    func installer() -> GameInstaller? {
        guard let library else { return nil }
        return GameInstaller(snapshot: library, installLocation: settings.installLocation)
    }

    func install(_ game: Game, playAfter: Bool, restoreSaves: Bool) async {
        guard let installer = installer(), let plan = installer.plan(for: game) else { return }
        do {
            try await installer.install(plan, restoreSaves: restoreSaves)
            await refreshInstalledFolders()
            if playAfter { play(game) }
        } catch {
            alert = AppAlert(title: "Could not install \(game.title)", message: error.localizedDescription)
        }
    }

    func uninstall(_ game: Game, backupSaves: Bool) async {
        guard let installer = installer(), let plan = installer.plan(for: game) else { return }
        do {
            let saved = try await installer.uninstall(plan, backupSaves: backupSaves)
            await refreshInstalledFolders()
            if saved > 0 {
                alert = AppAlert(title: "\(game.title) uninstalled",
                                 message: "\(saved) changed file\(saved == 1 ? "" : "s") were backed up to \(plan.saveBackupURL.path).")
            }
        } catch {
            alert = AppAlert(title: "Could not uninstall \(game.title)", message: error.localizedDescription)
        }
    }

    /// Re-reads the installed game folders without reparsing the XML.
    func refreshInstalledFolders() async {
        guard let library else { return }
        let gamesDirectory = library.root.gamesDirectory
        let localGames = library.localStore?.gamesDirectory
        let (names, local) = await Task.detached {
            (LibraryLoader.installedFolderNames(in: gamesDirectory),
             localGames.map { LibraryLoader.installedFolderNames(in: $0) } ?? [])
        }.value
        self.library = library.replacingInstalledFolders(library: names, local: local)
        if let snapshot = self.library {
            media = MediaCatalog(snapshot: snapshot, indexStore: MediaIndexStore(directory: AppPaths.mediaIndexes))
        }
        refreshVisibleGames()
    }

    // MARK: - Music

    func updateMusic() {
        guard settings.musicEnabled, launcher.sessions.isEmpty else {
            music.pause()
            return
        }
        guard let game = selectedGame, let media else {
            music.pause()
            return
        }
        Task { [weak self] in
            let url = await media.music(for: game)
            guard let self, self.selectedGameID == game.id else { return }
            if let url {
                self.music.play(url: url)
            } else {
                self.music.pause()
            }
        }
    }

    // MARK: - Files

    func revealInFinder(_ game: Game) {
        guard let library else { return }
        var url = library.root.url(forWindowsRelativePath: game.rootFolder ?? game.applicationPath)
        if let location = library.installedLocation(for: game) {
            url = location.url
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
