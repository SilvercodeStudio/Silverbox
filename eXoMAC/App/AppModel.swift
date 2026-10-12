import eXoCore
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
        /// True when the dialog saves choices without starting the game (Configure).
        var configureOnly = false
    }

    let thumbnails = ThumbnailCache()
    let music = MenuMusicPlayer()
    let launcher = GameLauncher()

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
        music.volume = settings.musicVolume
        // Debug conveniences: `-searchText ultima -selectTitle "Ultima V: Warriors of Destiny"`.
        if let text = UserDefaults.standard.string(forKey: "searchText") { searchText = text }
        pendingSelectTitle = UserDefaults.standard.string(forKey: "selectTitle")
        launcher.onSessionEnded = { [weak self] session in
            self?.sessionEnded(session)
        }
        if !settings.enabledCollections.isEmpty {
            reloadLibrary()
        }
    }

    // MARK: - Collections and loading

    var localStore: LocalStore { settings.localStore }
    var collections: [LibraryCollection] { settings.collections }

    func addCollection(url: URL) {
        let collection = LibraryCollection(name: LibraryCollection.suggestedName(for: url), rootPath: url.path)
        settings.collections.append(collection)
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
        try? localStore.ensureDirectories()
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
                        Task { @MainActor in self?.reportLoadProgress(progress, collection: collection.id, name: names[collection.id] ?? "") }
                    }
                    group.addTask {
                        let result = Result { try LibraryLoader(collection: collection, localStore: localStore, cache: cache).load(progress: report) }
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
            var catalogs: [UUID: MediaCatalog] = [:]
            for snapshot in ordered {
                catalogs[snapshot.collection.id] = MediaCatalog(snapshot: snapshot, indexStore: MediaIndexStore(directory: AppPaths.mediaIndexes))
            }
            self.media = catalogs
            self.searchIndex = index
            self.loadState = .loaded
            self.refreshVisibleGames()
            if ProcessInfo.processInfo.environment["EXOMAC_LOG"] != nil {
                let summary = ordered.map { "\($0.collection.name)=\($0.games.count)" }.joined(separator: ", ")
                FileHandle.standardError.write(Data("library: loaded \(library.games.count) games (\(summary)) in \(String(format: "%.2f", Date().timeIntervalSince(started))) s\n".utf8))
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
        guard let query else { visibleGames = []; return }
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
        case .node(let collectionID, let ref): return library?.node(collectionID: collectionID, ref: ref)?.title ?? "Library"
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
            return LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs).recommendedEmulator(for: game)
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
        guard snapshot(for: game)?.root.hasEXoDOS == true else {
            alert = AppAlert(title: "Not an eXoDOS game",
                             message: "This game's launcher is a batch file, but its collection is not an eXoDOS install, so it cannot be translated.")
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
            alert = AppAlert(title: "\(kind.displayName) not found",
                             message: "Choose the \(kind.displayName) application in Settings › Emulators.")
            return
        }
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs)
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
        return LaunchPlanner(snapshot: snapshot, scratchDirectory: AppPaths.launchConfigs).overrideConfigURL(for: game, variant: nil)
    }

    /// Copies the game's config into the local store (once) and opens it.
    func editConfig(for game: Game) {
        guard let snapshot = snapshot(for: game), let folder = game.rootFolder else { return }
        let source = snapshot.root.url(forWindowsRelativePath: folder).appendingPathComponent("dosbox.conf")
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

    /// Documents (books, magazines, soundtracks) open in their default app.
    /// Console and arcade ROMs wait for emulator assignments.
    private func openNonGameItem(_ game: Game) {
        guard let snapshot = snapshot(for: game) else { return }
        if game.applicationPath.lowercased().hasPrefix("steam://") {
            alert = AppAlert(title: "Steam game", message: "\(game.title) is a Steam link in the LaunchBox library and is not launched by this app.")
            return
        }
        let url = snapshot.root.url(forWindowsRelativePath: game.applicationPath)
        let ext = url.pathExtension.lowercased()
        guard Self.documentExtensions.contains(ext) else {
            let assignment = snapshot.emulatorAssignment(for: game.platform)
            let hint = assignment.map { " LaunchBox runs it with \($0.emulator.title)." } ?? ""
            alert = AppAlert(title: "\(game.platform) games cannot be launched yet",
                             message: "Emulator assignments for console and arcade platforms are the next step.\(hint)")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            alert = AppAlert(title: "File not found", message: url.path)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// True for books, magazines, soundtracks and other items opened in another app.
    func isDocumentItem(_ game: Game) -> Bool {
        guard !game.isDOSGame else { return false }
        return Self.documentExtensions.contains(WindowsPath.fileExtension(of: game.applicationPath)?.lowercased() ?? "")
    }

    private static let documentExtensions: Set<String> = ["pdf", "txt", "cbz", "cbr", "epub", "html", "htm", "mp3", "ogg", "flac",
                                                           "m4a", "wav", "mp4", "mkv", "avi", "mov", "jpg", "jpeg", "png", "gif"]

    private func sessionEnded(_ session: GameSession) {
        let seconds = Int(Date().timeIntervalSince(session.startedAt))
        userState.recordPlay(session.plan.game.launchBoxID, seconds: seconds)
        if session.exitStatus != 0, let log = session.logURL {
            alert = AppAlert(title: "\(session.plan.game.title) exited with code \(session.exitStatus)",
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
                alert = AppAlert(title: "\(game.title) uninstalled",
                                 message: "\(saved) changed file\(saved == 1 ? "" : "s") were backed up to \(plan.saveBackupURL.path).")
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
            (LibraryLoader.installedFolderNames(in: gamesDirectory),
             localGames.map { LibraryLoader.installedFolderNames(in: $0) } ?? [])
        }.value
        let updated = snapshot.replacingInstalledFolders(library: names, local: local)
        self.library = library.replacing(updated)
        media[updated.collection.id] = MediaCatalog(snapshot: updated, indexStore: MediaIndexStore(directory: AppPaths.mediaIndexes))
        refreshVisibleGames()
    }

    // MARK: - Music

    func updateMusic() {
        guard settings.musicEnabled, launcher.sessions.isEmpty else {
            music.pause()
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

    // MARK: - Files

    func revealInFinder(_ game: Game) {
        guard let snapshot = snapshot(for: game) else { return }
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
