import AppKit
import Foundation
import Observation
import eXoCore

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
            if settings.musicVolume != oldValue.musicVolume {
                music.volume = settings.musicVolume
                album.volume = settings.musicVolume
            }
            if settings.musicEnabled != oldValue.musicEnabled { updateMusic() }
            if settings.appIcon != oldValue.appIcon { applyAppIcon() }
            if settings.sortOrder != oldValue.sortOrder || settings.showHiddenGames != oldValue.showHiddenGames {
                refreshVisibleGames()
            }
            if settings.localStorePath != oldValue.localStorePath {
                applyDataRoot()
                warnedMissingStore = false
            }
            if settings.localStorePath != oldValue.localStorePath || settings.collections != oldValue.collections {
                scheduleReload()
            }
        }
    }

    private(set) var loadState: LoadState = .idle
    private(set) var library: Library?
    private(set) var media: [UUID: MediaCatalog] = [:]
    private(set) var searchIndex: LibrarySearchIndex?
    private(set) var rootReports: [UUID: LibraryRootReport] = [:]
    private(set) var loadErrors: [UUID: String] = [:]
    /// Platforms whose games start in a console or arcade emulator.
    private(set) var romPlatforms: [RomPlatformSummary] = []

    struct RomPlatformSummary: Identifiable, Hashable {
        let name: String
        let gameCount: Int
        var id: String { name }
    }

    var userState: UserLibraryState {
        didSet { scheduleUserStateSave() }
    }

    var scope: LibraryScope = .all { didSet { refreshVisibleGames() } }
    var searchText = "" { didSet { scheduleSearchRefresh() } }
    private(set) var visibleGames: [Game] = []
    var selectedGameID: String? {
        didSet {
            updateMusic()
            if selectedGameID != oldValue { refreshSelectedMedia() }
        }
    }
    /// The game page on show. Opening a page selects its game, so the
    /// inspector, media and keyboard commands follow it.
    var openedGameID: String? {
        didSet {
            if let openedGameID, openedGameID != selectedGameID { selectedGameID = openedGameID }
        }
    }
    var pendingInstall: Game?
    var pendingUninstall: Game?
    var pendingInfoGame: Game?
    var pendingLaunch: PendingLaunch?
    var alert: AppAlert?

    /// Columns in the game grid, reported by the grid view for arrow keys.
    var gridColumns = 1
    /// The selected game's screenshots and videos, shown by the media gallery.
    var galleryItems: [GameMediaItem] = []
    var galleryIndex = 0
    var selectedManual: URL?
    /// The selected game's extras (maps, clue books, cards), for Quick Look.
    var selectedExtras: [GameExtra] = []
    /// Extras and manual per game, loaded ahead of the context menu because an
    /// open menu does not update. Filled on hover and selection by
    /// `prefetchExtras(for:)`; cleared on reload.
    var extrasCache: [String: GameExtrasEntry] = [:]
    @ObservationIgnored var extrasTasks: Set<String> = []
    @ObservationIgnored var musicPausedForBackground = false
    @ObservationIgnored private var warnedMissingStore = false
    /// The file the Quick Look panel shows, if any.
    var quickLookURL: URL?
    /// Bumped by Search Games (Cmd-F); the search field takes focus when it changes.
    var searchFocusRequest = 0
    /// True while the Keyboard Shortcuts window is open, so Cmd-/ toggles it.
    var shortcutsShown = false
    @ObservationIgnored var mediaTask: Task<Void, Never>?

    /// A game waiting in the launch options dialog.
    struct PendingLaunch: Identifiable {
        let id = UUID()
        let game: Game
        let variants: [LaunchVariant]
        /// True when the dialog saves choices without starting the game (Configure).
        var configureOnly = false
    }

    let thumbnails = ThumbnailCache()
    let music = MenuMusicPlayer()
    let launcher = GameLauncher()
    let gamepad = GamepadInput()
    let album = AlbumPlayer()
    /// Soundtrack albums by game id: tracks, cover and durations.
    var albumCache: [String: AlbumInfo] = [:]
    /// The soundtrack being unpacked right now, shown in the album bar.
    var albumUnpackingID: String?
    /// An unpacked album waiting for the user to confirm its removal.
    var pendingAlbumRemoval: Game?
    /// A video entry with several videos, waiting for the user to choose one.
    var pendingVideoChoice: VideoChoice?

    private let userStateStore = UserLibraryStateStore(url: AppPaths.userLibraryState)
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSelectTitle: String?
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    struct AppAlert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    init() {
        settings = AppSettings.load()
        userState = (try? userStateStore.load()) ?? UserLibraryState()
        applyDataRoot()
        music.volume = settings.musicVolume
        album.volume = settings.musicVolume
        applyAppIcon()
        // Debug conveniences: `-searchText ultima -selectTitle "Ultima V: Warriors of Destiny"`.
        if let text = UserDefaults.standard.string(forKey: "searchText") { searchText = text }
        pendingSelectTitle = UserDefaults.standard.string(forKey: "selectTitle")
        launcher.onSessionEnded = { [weak self] session in
            self?.sessionEnded(session)
        }
        gamepad.model = self
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in self?.applicationActiveChanged(false) }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in self?.applicationActiveChanged(true) }
        }
        if !settings.enabledCollections.isEmpty {
            reloadLibrary()
        }
    }

    /// Points the caches, launch configs and logs at the chosen local data
    /// folder. While its drive is unplugged they fall back to Application
    /// Support, so nothing is created under an empty /Volumes mount point.
    private func applyDataRoot() {
        let root = settings.localStorePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        AppPaths.customRoot = root.flatMap { Self.volumeIsMissing(for: $0) ? nil : $0 }
    }

    /// True for a path under /Volumes whose volume is not mounted.
    static func volumeIsMissing(for url: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return false }
        return !FileManager.default.fileExists(atPath: "/Volumes/" + parts[2])
    }

    // MARK: - Collections and loading

    /// Shows the chosen icon in the Dock; nil restores the bundle icon with its
    /// appearance variants. The Finder keeps the icon built into the bundle.
    private func applyAppIcon() {
        NSApplication.shared.applicationIconImage = settings.appIcon == .amber ? nil : settings.appIcon.image
    }

    var localStore: LocalStore { settings.localStore }
    var collections: [LibraryCollection] { settings.collections }

    func addCollection(url: URL) {
        let collection = LibraryCollection(name: LibraryCollection.suggestedName(for: url), rootPath: url.path)
        settings.collections.append(collection)
    }

    /// Folders dropped on the window from the Finder become collections when
    /// they hold a LaunchBox library; the rest are explained in an alert.
    /// Returns true when at least one collection was added.
    @discardableResult
    func addDroppedFolders(_ urls: [URL]) -> Bool {
        var added = 0
        var rejected: [String] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
            else {
                rejected.append(url.lastPathComponent)
                continue
            }
            let root = LibraryRoot(url: url)
            if settings.collections.contains(where: { $0.root.url == root.url }) { continue }
            if root.inspect().isUsable {
                addCollection(url: url)
                added += 1
            } else {
                rejected.append(url.lastPathComponent)
            }
        }
        if !rejected.isEmpty {
            alert = AppAlert(
                title: rejected.count == 1 ? "\(rejected[0]) is not a library folder" : "Not library folders",
                message:
                    "A collection is an eXoDOS folder, or any LaunchBox library folder that holds Data and Images. "
                    + (rejected.count == 1 ? "" : "Skipped: \(rejected.joined(separator: ", ")).")
            )
        }
        return added > 0
    }

    func removeCollection(id: UUID) {
        settings.collections.removeAll { $0.id == id }
        LibraryCache(directory: AppPaths.libraryCache).remove(collectionID: id)
    }

    func snapshot(for game: Game) -> LibrarySnapshot? {
        library?.snapshot(for: game)
    }

    func media(for game: Game) -> MediaCatalog? {
        media[game.collectionID]
    }

    /// Reloads after settings changes settle, so typing in a path field does
    /// not trigger a load per keystroke.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.reloadLibrary()
        }
    }

    /// Reads every enabled collection again. Pass `clearMediaCache` for an
    /// explicit rescan, so saved indexes and parsed libraries are rebuilt.
    func reloadLibrary(clearMediaCache: Bool = false) {
        loadTask?.cancel()
        extrasCache = [:]
        extrasTasks = []
        albumCache = [:]
        if clearMediaCache {
            MediaIndexStore(directory: AppPaths.mediaIndexes).clear()
            LibraryCache(directory: AppPaths.libraryCache).clear()
        }
        let collections = settings.enabledCollections
        guard !collections.isEmpty else {
            loadState = .idle
            library = nil
            media = [:]
            return
        }
        rootReports = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.root.inspect()) })
        loadErrors = [:]
        let localStore = settings.localStore
        applyDataRoot()
        do {
            if Self.volumeIsMissing(for: localStore.directory) { throw CocoaError(.fileNoSuchFile) }
            try localStore.ensureDirectories()
        } catch {
            if settings.localStorePath != nil, !warnedMissingStore {
                warnedMissingStore = true
                alert = AppAlert(
                    title: "The local data folder is not available",
                    message:
                        "\(localStore.directory.path) cannot be used right now. Is the drive connected? Installed games, soundtracks and caches there stay out of reach until it is; Settings › Library can switch back to the default folder."
                )
            }
        }
        let cache = LibraryCache(directory: AppPaths.libraryCache)
        loadState = .loading(LibraryLoadProgress(stage: "Starting", fraction: 0, gamesLoaded: 0))
        let names = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.name) })
        let started = Date()
        loadTask = Task { [weak self] in
            var snapshots: [UUID: LibrarySnapshot] = [:]
            var errors: [UUID: String] = [:]
            await withTaskGroup(of: (UUID, Result<LibrarySnapshot, Error>).self) { group in
                for collection in collections {
                    let report: @Sendable (LibraryLoadProgress) -> Void = { progress in
                        Task { @MainActor in
                            self?.reportLoadProgress(
                                progress, collection: collection.id, name: names[collection.id] ?? "")
                        }
                    }
                    group.addTask {
                        let result = Result {
                            try LibraryLoader(collection: collection, localStore: localStore, cache: cache).load(
                                progress: report)
                        }
                        return (collection.id, result)
                    }
                }
                for await (id, result) in group {
                    switch result {
                    case .success(let snapshot): snapshots[id] = snapshot
                    case .failure(let error): errors[id] = error.localizedDescription
                    }
                }
            }
            guard let self, !Task.isCancelled else { return }
            let ordered = collections.compactMap { snapshots[$0.id] }
            let library = Library(snapshots: ordered)
            let index = await Task.detached(priority: .utility) { LibrarySearchIndex(library: library) }.value
            guard !Task.isCancelled else { return }
            self.loadErrors = errors
            if ordered.isEmpty, let message = errors.values.first {
                self.loadState = .failed(message)
                self.library = nil
                return
            }
            self.library = library
            self.romPlatforms = Self.romPlatforms(in: library)
            var catalogs: [UUID: MediaCatalog] = [:]
            for snapshot in ordered {
                catalogs[snapshot.collection.id] = MediaCatalog(
                    snapshot: snapshot, indexStore: MediaIndexStore(directory: AppPaths.mediaIndexes))
            }
            self.media = catalogs
            self.searchIndex = index
            self.loadState = .loaded
            self.refreshVisibleGames()
            if ProcessInfo.processInfo.environment["EXOMAC_LOG"] != nil {
                let summary = ordered.map { "\($0.collection.name)=\($0.games.count)" }.joined(separator: ", ")
                FileHandle.standardError.write(
                    Data(
                        "library: loaded \(library.games.count) games (\(summary)) in \(String(format: "%.2f", Date().timeIntervalSince(started))) s\n"
                            .utf8))
            }
            // Biggest platforms first, so the main grid gets its covers soonest.
            for snapshot in ordered {
                guard let catalog = catalogs[snapshot.collection.id] else { continue }
                let counts = Dictionary(grouping: snapshot.games, by: \.platform).mapValues(\.count)
                let platforms = snapshot.platforms.map(\.name).sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
                Task.detached(priority: .utility) { await catalog.prewarm(platforms: platforms) }
            }
        }
    }

    @ObservationIgnored private var collectionProgress: [UUID: LibraryLoadProgress] = [:]

    private static func romPlatforms(in library: Library) -> [RomPlatformSummary] {
        var counts: [String: Int] = [:]
        for game in library.games where game.launchKind == .emulator {
            counts[game.platform, default: 0] += 1
        }
        return counts.map { RomPlatformSummary(name: $0.key, gameCount: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func reportLoadProgress(_ progress: LibraryLoadProgress, collection: UUID, name: String) {
        guard case .loading = loadState else { return }
        collectionProgress[collection] = progress
        let count = max(1, settings.enabledCollections.count)
        let fraction = collectionProgress.values.map(\.fraction).reduce(0, +) / Double(count)
        let games = collectionProgress.values.map(\.gamesLoaded).reduce(0, +)
        let stage = count > 1 ? "\(name): \(progress.stage)" : progress.stage
        loadState = .loading(LibraryLoadProgress(stage: stage, fraction: fraction, gamesLoaded: games))
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
        library.map(LibraryQuery.init(library:))
    }

    func refreshVisibleGames() {
        guard let query else {
            visibleGames = []
            return
        }
        var games = query.games(in: scope, overlay: userState)
        if !settings.showHiddenGames {
            games = games.filter { !(userState.state(for: $0.launchBoxID).hidden ?? $0.hidden) }
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
            } else if UserDefaults.standard.bool(forKey: "autoConfigure") {
                Task { @MainActor in self.configure(match) }
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
        case .node(let collectionID, let ref):
            return library?.node(collectionID: collectionID, ref: ref)?.title ?? "Library"
        }
    }

    // MARK: - Per-game state

    func isFavorite(_ game: Game) -> Bool {
        userState.state(for: game.launchBoxID).favorite ?? game.favorite
    }

    func toggleFavorite(_ game: Game) {
        let next = !isFavorite(game)
        userState.update(game.launchBoxID) { $0.favorite = next == game.favorite ? nil : next }
        if scope == .favorites { refreshVisibleGames() }
    }

    func isInstalled(_ game: Game) -> Bool {
        library?.isInstalled(game) ?? false
    }

    func installedLocation(for game: Game) -> GameLocation? {
        library?.installedLocation(for: game)
    }

    func playCount(_ game: Game) -> Int {
        game.playCount + userState.state(for: game.launchBoxID).playCount
    }

    func playTimeSeconds(_ game: Game) -> Int {
        game.playTimeSeconds + userState.state(for: game.launchBoxID).playTimeSeconds
    }

    func lastPlayed(_ game: Game) -> Date? {
        userState.state(for: game.launchBoxID).lastPlayed ?? game.lastPlayed
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
        if let override = userState.state(for: game.launchBoxID).emulatorOverride { return override }
        return defaultEmulatorKind(for: game)
    }

    /// The emulator the settings policy picks, ignoring per-game overrides.
    func defaultEmulatorKind(for game: Game) -> EmulatorKind {
        switch settings.emulatorPolicy {
        case .alwaysStaging: return .dosboxStaging
        case .alwaysDOSBoxX: return .dosboxX
        case .recommended:
            guard let snapshot = snapshot(for: game) else { return .dosboxStaging }
            return LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs).recommendedEmulator(
                for: game)
        }
    }

    func launchVariants(for game: Game) -> [LaunchVariant] {
        guard let snapshot = snapshot(for: game) else { return [] }
        return LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs).variants(for: game)
    }

    func eXoDOSBuild(for game: Game) -> EXoDOSBuild? {
        snapshot(for: game)?.dosboxIndex.build(forLauncherBaseName: game.launcherBaseName)
    }

    /// The global launch options with this game's remembered choices applied.
    func effectiveLaunchOptions(for game: Game) -> LaunchOptions {
        settings.launchOptions.applying(userState.state(for: game.launchBoxID).launchOverrides)
    }

    func preferredVariant(for game: Game, in variants: [LaunchVariant]) -> LaunchVariant? {
        guard !variants.isEmpty else { return nil }
        if let preferred = userState.state(for: game.launchBoxID).preferredVariantID,
            let variant = variants.first(where: { $0.id == preferred })
        {
            return variant
        }
        return variants.first { !$0.needsWindowsHelper } ?? variants.first
    }

    /// Plays the game: opens non-game items, offers installation, shows the
    /// launch options dialog, or starts the emulator right away.
    func play(_ game: Game, variant: LaunchVariant? = nil) {
        guard let library else { return }
        switch game.launchKind {
        case .dosBox: break
        case .emulator:
            launchEmulated(game)
            return
        case .document, .link, .windowsProgram:
            openNonGameItem(game)
            return
        case .soundtrack:
            playAlbum(game)
            return
        case .video:
            playVideo(game)
            return
        }
        guard snapshot(for: game)?.root.hasEXoDOS == true else {
            alert = AppAlert(
                title: "Not an eXoDOS game",
                message:
                    "This game's launcher is a batch file, but its collection is not an eXoDOS install, so it cannot be translated."
            )
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
        launch(
            game, variant: variant ?? preferredVariant(for: game, in: variants),
            options: effectiveLaunchOptions(for: game), emulatorKind: emulatorKind(for: game))
    }

    /// Opens the launch options dialog to save choices for a game without
    /// starting it, like eXoDOS's Configure menu. Works before installation.
    func configure(_ game: Game) {
        guard game.isDOSGame, snapshot(for: game)?.root.hasEXoDOS == true else {
            pendingInfoGame = game
            return
        }
        pendingLaunch = PendingLaunch(game: game, variants: launchVariants(for: game), configureOnly: true)
    }

    /// Starts the emulator with explicit choices.
    func launch(_ game: Game, variant: LaunchVariant?, options: LaunchOptions, emulatorKind kind: EmulatorKind) {
        guard let snapshot = snapshot(for: game) else { return }
        guard let emulator = settings.emulatorInstallation(kind), emulator.exists else {
            alert = AppAlert(
                title: "\(kind.displayName) not found",
                message: "Choose the \(kind.displayName) application in Settings › Emulators.")
            return
        }
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs)
        do {
            let plan = try planner.plan(game: game, variant: variant, emulator: emulator, options: options)
            try plan.writeConfig()
            music.pause()
            album.pause()
            try launcher.launch(plan)
        } catch {
            alert = AppAlert(title: "Could not start \(game.title)", message: error.localizedDescription)
            updateMusic()
        }
    }

    /// Keeps the launch dialog's choices for next time.
    func rememberLaunchChoices(
        for game: Game, options: LaunchOptions, variant: LaunchVariant?, emulatorKind kind: EmulatorKind
    ) {
        let overrides = LaunchOverrides(base: settings.launchOptions, chosen: options)
        let defaultKind = defaultEmulatorKind(for: game)
        userState.update(game.launchBoxID) { state in
            state.launchOverrides = overrides.isEmpty ? nil : overrides
            state.preferredVariantID = variant?.id
            state.emulatorOverride = kind == defaultKind ? nil : kind
        }
    }

    func forgetLaunchChoices(for game: Game) {
        userState.update(game.launchBoxID) { state in
            state.launchOverrides = nil
            state.preferredVariantID = nil
            state.emulatorOverride = nil
        }
    }

    // MARK: - Config overrides

    func overrideConfigURL(for game: Game) -> URL? {
        guard let snapshot = snapshot(for: game) else { return nil }
        return LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs).overrideConfigURL(
            for: game, variant: nil)
    }

    /// Copies the game's config into the local store (once) and opens it.
    func editConfig(for game: Game) {
        guard let snapshot = snapshot(for: game), let folder = game.rootFolder else { return }
        let source = snapshot.root.url(forWindowsRelativePath: folder).appendingPathComponent("dosbox.conf")
        let target = localStore.overrideConfigURL(for: game, configName: "dosbox.conf")
        do {
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    // MARK: - Console, computer and arcade games

    /// Weighs the user's platform choices, the libraries' `Emulators.xml`
    /// and what is installed on this Mac.
    func emulatorResolver() -> EmulatorAssignmentResolver {
        EmulatorAssignmentResolver(
            userAssignments: settings.platformEmulators, snapshots: library?.snapshots ?? [],
            installedKinds: settings.installedRomEmulators, retroArch: settings.retroArchSetup)
    }

    func resolvedEmulator(for game: Game) -> ResolvedEmulatorAssignment {
        emulatorResolver().resolve(platform: game.platform)
    }

    /// Starts a ROM or disc image in the emulator assigned to its platform.
    func launchEmulated(_ game: Game) {
        guard let snapshot = snapshot(for: game) else { return }
        let resolved = resolvedEmulator(for: game)
        guard let assignment = resolved.assignment, resolved.problem == nil else {
            alert = AppAlert(
                title: "Could not start \(game.title)",
                message: resolved.problem ?? "No emulator is assigned to \(game.platform).")
            return
        }
        guard let emulator = settings.emulatorInstallation(assignment.emulator), emulator.exists else {
            alert = AppAlert(
                title: "\(assignment.emulator.displayName) not found",
                message: "Choose the \(assignment.emulator.displayName) application in Settings › Emulators.")
            return
        }
        do {
            let launch = try RomLaunchPlanner(snapshot: snapshot).plan(
                game: game, resolved: resolved, emulator: emulator,
                retroArch: settings.retroArchSetup, options: effectiveLaunchOptions(for: game))
            music.pause()
            album.pause()
            try launcher.launch(launch)
        } catch {
            alert = AppAlert(title: "Could not start \(game.title)", message: error.localizedDescription)
            updateMusic()
        }
    }

    /// Documents (books, magazines, soundtracks) open in their default app;
    /// links and Windows programs are explained.
    private func openNonGameItem(_ game: Game) {
        guard let snapshot = snapshot(for: game) else { return }
        switch game.launchKind {
        case .link:
            alert = AppAlert(
                title: "Link",
                message:
                    "\(game.title) is a link in the LaunchBox library (\(game.applicationPath)) and is not opened by this app."
            )
        case .windowsProgram:
            alert = AppAlert(
                title: "Windows program",
                message:
                    "\(game.title) starts a Windows program (\(WindowsPath.lastComponent(of: game.applicationPath))), which cannot run on the Mac."
            )
        default:
            let url = snapshot.root.url(forWindowsRelativePath: game.applicationPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                alert = AppAlert(title: "File not found", message: url.path)
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// True for books, magazines, soundtracks and other items opened in another app.
    func isDocumentItem(_ game: Game) -> Bool {
        game.launchKind == .document
    }

    private func sessionEnded(_ session: GameSession) {
        let seconds = Int(Date().timeIntervalSince(session.startedAt))
        userState.recordPlay(session.game.launchBoxID, seconds: seconds)
        if session.exitStatus != 0, let log = session.logURL {
            alert = AppAlert(
                title: "\(session.game.title) exited with code \(session.exitStatus)",
                message: "The emulator log is at \(log.path)")
        }
        updateMusic()
        if scope == .recentlyPlayed { refreshVisibleGames() }
    }

    // MARK: - Installing

    func installer(for game: Game) -> GameInstaller? {
        guard let snapshot = snapshot(for: game) else { return nil }
        return GameInstaller(snapshot: snapshot, installLocation: settings.installLocation)
    }

    func install(_ game: Game, playAfter: Bool, restoreSaves: Bool) async {
        guard let installer = installer(for: game), let plan = installer.plan(for: game) else { return }
        do {
            try await installer.install(plan, restoreSaves: restoreSaves)
            await refreshInstalledFolders(for: game)
            if playAfter { play(game) }
        } catch {
            alert = AppAlert(title: "Could not install \(game.title)", message: error.localizedDescription)
        }
    }

    func uninstall(_ game: Game, backupSaves: Bool) async {
        guard let installer = installer(for: game), let plan = installer.plan(for: game) else { return }
        do {
            let saved = try await installer.uninstall(plan, backupSaves: backupSaves)
            await refreshInstalledFolders(for: game)
            if saved > 0 {
                alert = AppAlert(
                    title: "\(game.title) uninstalled",
                    message:
                        "\(saved) changed file\(saved == 1 ? "" : "s") were backed up to \(plan.saveBackupURL.path).")
            }
        } catch {
            alert = AppAlert(title: "Could not uninstall \(game.title)", message: error.localizedDescription)
        }
    }

    /// Re-reads the installed game folders of one collection without reparsing the XML.
    func refreshInstalledFolders(for game: Game) async {
        guard let library, let snapshot = library.snapshot(for: game) else { return }
        let gamesDirectory = snapshot.root.gamesDirectory
        let localGames = snapshot.localStore?.gamesDirectory
        let (names, local) = await Task.detached {
            (
                LibraryLoader.installedFolderNames(in: gamesDirectory),
                localGames.map { LibraryLoader.installedFolderNames(in: $0) } ?? []
            )
        }.value
        let updated = snapshot.replacingInstalledFolders(library: names, local: local)
        self.library = library.replacing(updated)
        media[updated.collection.id] = MediaCatalog(
            snapshot: updated, indexStore: MediaIndexStore(directory: AppPaths.mediaIndexes))
        refreshVisibleGames()
    }

    // MARK: - Music

    func updateMusic() {
        guard settings.musicEnabled, launcher.sessions.isEmpty, !album.isActive else {
            music.pause()
            return
        }
        if !settings.musicInBackground, !NSApplication.shared.isActive {
            music.pause()
            musicPausedForBackground = true
            return
        }
        guard let game = selectedGame, let media = media(for: game) else {
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

    /// Pauses the menu music while another app is in front, unless the
    /// setting allows it, and resumes it when the app comes back. Music the
    /// user paused stays paused.
    func applicationActiveChanged(_ active: Bool) {
        if active {
            guard musicPausedForBackground else { return }
            musicPausedForBackground = false
            updateMusic()
        } else if !settings.musicInBackground, music.isPlaying {
            music.pause()
            musicPausedForBackground = true
        }
    }

    // MARK: - Files

    func revealInFinder(_ game: Game) {
        guard let snapshot = snapshot(for: game) else { return }
        if game.launchKind == .soundtrack, let info = albumCache[game.id] {
            NSWorkspace.shared.activateFileViewerSelecting([
                info.album.isUnpacked ? info.album.folderURL : info.album.archiveURL
            ])
            return
        }
        var url = snapshot.root.url(forWindowsRelativePath: game.rootFolder ?? game.applicationPath)
        if let location = snapshot.installedLocation(for: game) {
            url = location.url
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

extension AppIconVariant {
    /// The icon as the system renders it from the Icon Composer file, else
    /// the flat PNG from the image set.
    var image: NSImage {
        NSImage(named: iconName) ?? NSImage(named: imageName) ?? NSImage()
    }
}
