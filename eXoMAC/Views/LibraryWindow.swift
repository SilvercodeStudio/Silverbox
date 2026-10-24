import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import eXoCore

/// The main window: sidebar, game collection (or game page), inspector.
struct LibraryWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            ContentColumn()
                .inspector(isPresented: $model.settings.inspectorShown) {
                    GameInspectorView()
                        .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
                }
        }
        // A library folder dragged in from the Finder becomes a collection.
        .dropDestination(for: URL.self) { urls, _ in
            model.addDroppedFolders(urls)
        } isTargeted: {
            dropTargeted = $0
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 1040, minHeight: 640)
        .onAppear {
            #if DEBUG
                DebugScreenshot.scheduleIfRequested()
                if let id = UserDefaults.standard.string(forKey: "openWindow"), !id.isEmpty {
                    if id == "settings" { openSettings() } else { openWindow(id: id) }
                }
                if let page = UserDefaults.standard.string(forKey: "helpPage"), !page.isEmpty {
                    HelpState.shared.show(topicPrefix: page)
                }
            #endif
        }
        .sheet(item: $model.pendingInstall) { game in
            InstallSheet(game: game)
        }
        .sheet(item: $model.pendingInfoGame) { game in
            GameInfoSheet(game: game)
        }
        .sheet(item: $model.pendingLaunchLog) { item in
            LaunchLogSheet(session: item.session)
        }
        .sheet(item: $model.pendingLaunch) { pending in
            LaunchOptionsSheet(pending: pending)
        }
        .sheet(item: $model.pendingUninstall) { game in
            UninstallSheet(game: game)
        }
        .sheet(item: $model.pendingVideoChoice) { choice in
            VideoChoiceSheet(choice: choice)
        }
        .sheet(item: $model.pendingSetup) { pending in
            SetupSheet(pending: pending)
        }
        .confirmationDialog(
            "Remove the unpacked album?",
            isPresented: Binding(
                get: { model.pendingAlbumRemoval != nil }, set: { if !$0 { model.pendingAlbumRemoval = nil } }),
            presenting: model.pendingAlbumRemoval
        ) { game in
            Button("Remove", role: .destructive) { model.removeAlbum(game) }
        } message: { game in
            Text(
                "\(game.title) is deleted from the local data folder. The zip in the library stays, so Play unpacks it again."
            )
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

/// The middle column: setup, loading, the collection, or an opened game page.
struct ContentColumn: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.loadState {
            case .idle:
                LibrarySetupView(error: nil)
            case .failed(let message):
                LibrarySetupView(error: message)
            case .loading(let progress):
                LoadingView(progress: progress)
            case .loaded:
                if let game = model.openedGame {
                    GameDetailView(game: game)
                } else {
                    GameCollectionView()
                }
            }
        }
        .background(Theme.window)
        .quickLookPreview($model.quickLookURL, in: model.quickLookItems)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                JobsBar()
                if model.launcher.isRunning { NowPlayingBar() }
                if model.album.isActive || model.albumUnpackingID != nil {
                    AlbumBar()
                } else if model.settings.musicEnabled, model.loadState == .loaded {
                    MusicBar()
                }
            }
        }
        .navigationTitle(model.openedGame?.title ?? model.scopeTitle(model.scope))
        .navigationSubtitle(subtitle)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search games")
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.openedGame != nil {
                    Button {
                        model.openedGameID = nil
                    } label: {
                        Label("Back to Library", systemImage: "chevron.left")
                    }
                }
                if model.settings.viewMode == .grid, model.openedGame == nil {
                    Slider(value: $model.settings.tileSize, in: AppSettings.tileSizeRange) { Text("Tile size") }
                        .frame(width: 110)
                        .help("Tile size")
                }
                Picker("View", selection: $model.settings.viewMode) {
                    Image(systemName: "square.grid.2x2").tag(LibraryViewMode.grid)
                    Image(systemName: "list.bullet").tag(LibraryViewMode.list)
                }
                .pickerStyle(.segmented)
                .help("Grid or list")
                Menu {
                    Picker("Sort by", selection: $model.settings.sortOrder) {
                        Text("Title").tag(GameSortOrder.title)
                        Text("Release year").tag(GameSortOrder.releaseYear)
                        Text("Developer").tag(GameSortOrder.developer)
                        Text("Last played").tag(GameSortOrder.lastPlayed)
                        Text("Date added").tag(GameSortOrder.dateAdded)
                        Text("Times played").tag(GameSortOrder.playCount)
                        Text("Community rating").tag(GameSortOrder.communityRating)
                    }
                    .pickerStyle(.inline)
                    Toggle("Show hidden games", isOn: $model.settings.showHiddenGames)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    model.settings.inspectorShown.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector")
            }
        }
    }

    private var subtitle: String {
        guard model.loadState == .loaded, model.openedGame == nil else { return "" }
        let count = model.visibleGames.count
        let total = model.library?.games.count ?? 0
        if model.searchText.isEmpty { return "\(count.formatted()) games" }
        return "\(count.formatted()) of \(total.formatted()) games match “\(model.searchText)”"
    }
}

struct LoadingView: View {
    let progress: LibraryLoadProgress

    var body: some View {
        VStack(spacing: 14) {
            ProgressView(value: progress.fraction)
                .frame(width: 320)
            Text(progress.stage)
                .foregroundStyle(Theme.textSecondary)
            if progress.gamesLoaded > 0 {
                Text("\(progress.gamesLoaded.formatted()) games")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown until an eXoDOS folder is chosen, or when loading it fails.
struct LibrarySetupView: View {
    let error: String?
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(error == nil ? "Add your first collection" : "The library could not be loaded")
                .font(.title2.weight(.semibold))
            Text(
                error
                    ?? "Drop your eXoDOS folder here from the Finder, or pick it with the button. Any LaunchBox library folder that holds Data and Images works, and it can be read-only: games you install, saves and settings are kept in a local data folder on this Mac."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: 440)
            ForEach(Array(model.rootReports.values), id: \.root.url) { report in
                LibraryRootReportView(report: report)
                    .frame(maxWidth: 480)
            }
            HStack {
                Button("Add Collection…") { showingPicker = true }
                    .buttonStyle(.borderedProminent)
                if !model.collections.isEmpty {
                    Button("Try Again") { model.reloadLibrary() }
                }
                Button("Library Settings…") {
                    SettingsState.shared.show(tab: .library)
                    openSettings()
                }
            }
            if error == nil {
                Text(
                    "Installed games, soundtracks and caches go to the local data folder, \(model.localStore.directory.path). To keep them on another drive, choose that folder in Library Settings before you install anything."
                )
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: 440)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addFolder(url) }
        }
    }
}

struct LibraryRootReportView: View {
    let report: LibraryRootReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(report.items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.exists ? "checkmark" : (item.isRequired ? "xmark" : "minus"))
                        .foregroundStyle(item.exists ? Theme.good : (item.isRequired ? Theme.bad : Theme.textTertiary))
                        .frame(width: 16)
                    Text(item.label)
                    Spacer()
                    Text(item.relativePath)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                if item.id != report.items.last?.id { Divider() }
            }
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
    }
}

/// The menu-music bar along the bottom of the window.
struct MusicBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Button {
                model.music.toggle()
            } label: {
                Image(systemName: model.music.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 30, height: 30)
                    .background(Theme.panelRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.music.currentURL == nil || model.music.isUnsupportedFormat)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Text(model.music.trackName ?? "No menu music for this game")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "speaker.wave.2")
                .foregroundStyle(Theme.textTertiary)
            Slider(value: $model.settings.musicVolume, in: 0...1)
                .frame(width: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusLine: String {
        if model.music.isUnsupportedFormat {
            return model.music.errorMessage
                ?? "Menu music, .\(model.music.currentURL?.pathExtension.lowercased() ?? "") format not supported"
        }
        if model.music.currentURL == nil { return "Menu music" }
        return model.music.isPlaying ? "Menu music, playing" : "Menu music, paused"
    }
}

/// Shows the game that is running right now.
struct NowPlayingBar: View {
    @Environment(AppModel.self) private var model
    @State private var showingNotes = false

    var body: some View {
        ForEach(model.launcher.sessions) { session in
            HStack(spacing: 12) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Playing").font(.caption).foregroundStyle(Theme.accent)
                    Text(session.game.title).font(.headline)
                }
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(Formatters.elapsed(context.date.timeIntervalSince(session.startedAt)))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
                Text(session.launch.emulator.kind.displayName)
                    .foregroundStyle(Theme.textSecondary)
                if !session.launch.notes.isEmpty {
                    Button("\(session.launch.notes.count) notes") { showingNotes = true }
                        .popover(isPresented: $showingNotes) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(session.launch.notes.enumerated()), id: \.offset) { Text($0.element) }
                            }
                            .padding()
                            .frame(width: 420)
                        }
                }
                Spacer()
                Button("Show Log") { model.showLaunchLog(for: session) }
                Button("Show Game Window") { model.launcher.bringToFront(session) }
                Button("Quit Game") { model.launcher.terminate(session) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.panelRaised)
            .overlay(alignment: .top) { Divider() }
        }
    }
}
