import SwiftUI
import SilverboxCore

/// The grid or list of games for the current scope and search.
struct GameCollectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.visibleGames.isEmpty {
            EmptyCollectionView()
        } else if model.settings.viewMode == .grid {
            GameGridView(games: model.visibleGames)
        } else {
            GameListView(games: model.visibleGames)
        }
    }
}

struct EmptyCollectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.searchText.isEmpty {
                ContentUnavailableView(
                    "No Games Here Yet", systemImage: "gamecontroller",
                    description: Text("Pick another platform or playlist in the sidebar."))
            } else {
                ContentUnavailableView {
                    Label("No Results for “\(model.searchText)”", systemImage: "magnifyingglass")
                } description: {
                    Text("Check the spelling, or clear the search to see every game.")
                } actions: {
                    Button("Clear Search") { model.searchText = "" }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameGridView: View {
    let games: [Game]
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    private static let spacing: CGFloat = 18
    private static let inset: CGFloat = 24

    var body: some View {
        let tile = CGFloat(model.settings.tileSize)
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: tile, maximum: tile * 1.3), spacing: Self.spacing, alignment: .bottom
                            )
                        ],
                        alignment: .leading, spacing: 24
                    ) {
                        ForEach(games) { game in
                            GameTileView(game: game, width: tile, isSelected: model.selectedGameID == game.id)
                                .background {
                                    if model.selectedGameID == game.id {
                                        SelectedTileReporter(gameID: game.id, model: model)
                                    }
                                }
                                .onTapGesture(count: 2) { model.play(game) }
                                .onTapGesture {
                                    model.selectedGameID = game.id
                                    focused = true
                                }
                                .contextMenu { GameContextMenu(game: game) }
                                .onHover { if $0 { model.prefetchExtras(for: game) } }
                                .id(game.id)
                        }
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onChange(of: geometry.size.width, initial: true) {
                                    model.gridColumns = Self.columns(in: geometry.size.width, tile: tile)
                                }
                                .onChange(of: tile) {
                                    model.gridColumns = Self.columns(in: geometry.size.width, tile: tile)
                                }
                        }
                    )
                    .padding(Self.inset)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onChange(of: focused, initial: true) { model.gridFocused = focused }
            .onDisappear { model.gridFocused = false }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                model.gridFrame = $0
            }
            .onMoveCommand { direction in
                switch direction {
                case .up: model.moveSelection(.up)
                case .down: model.moveSelection(.down)
                case .left: model.moveSelection(.left)
                case .right: model.moveSelection(.right)
                @unknown default: break
                }
            }
            .onKeyPress(.return) {
                model.activateSelection()
                return .handled
            }
            .onKeyPress(.space) {
                model.quickLookCurrentMedia()
                return .handled
            }
            .onKeyPress(.escape) { model.goBack() ? .handled : .ignored }
            .onKeyPress(phases: .down) { press in
                let modifiers = press.modifiers
                guard modifiers.contains(.option), modifiers.isDisjoint(with: [.command, .shift, .control]) else {
                    return .ignored
                }
                switch press.key {
                case .leftArrow: model.showPreviousMedia()
                case .rightArrow: model.showNextMedia()
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(.home) {
                model.selectFirstGame()
                return .handled
            }
            .onKeyPress(.end) {
                model.selectLastGame()
                return .handled
            }
            .onKeyPress(.pageUp) {
                model.moveSelectionByPage(forward: false)
                return .handled
            }
            .onKeyPress(.pageDown) {
                model.moveSelectionByPage(forward: true)
                return .handled
            }
            .onAppear { focused = true }
            .onChange(of: model.scope) {
                if let first = games.first?.id { proxy.scrollTo(first, anchor: .top) }
            }
            .onChange(of: model.selectedGameID, initial: true) {
                if let id = model.selectedGameID { proxy.scrollTo(id) }
            }
            .onChange(of: model.revealSelectionRequest) {
                if let id = model.selectedGameID { proxy.scrollTo(id) }
            }
        }
    }

    /// How many tiles LazyVGrid fits per row with adaptive columns, from the
    /// grid's own width (so scroll bars and padding are already taken off).
    static func columns(in width: CGFloat, tile: CGFloat) -> Int {
        let available = width
        return max(1, Int(((available + spacing) / (tile + spacing)).rounded(.down)))
    }
}

struct GameTileView: View {
    let game: Game
    let width: CGFloat
    let isSelected: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            BoxArtView(game: game, width: width)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if model.isFavorite(game) {
                            Image(systemName: "heart.fill").foregroundStyle(Theme.accent)
                        }
                        if game.isEXoGame, model.isInstalled(game) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 11))
                    .padding(5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
                    .opacity(model.isFavorite(game) || (game.isEXoGame && model.isInstalled(game)) ? 1 : 0)
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            Text(game.title)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: width)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(game.title)
    }
}

/// Box art, or a tinted placeholder tile that carries the title.
struct BoxArtView: View {
    let game: Game
    let width: CGFloat
    var maxPixelSize: Int = 400
    /// Optional: when the sidebar changes the scope from the keyboard,
    /// SwiftUI updates tiles that are being removed with an environment
    /// that has no model, and a required one would stop the app.
    @Environment(AppModel.self) private var model: AppModel?
    @State private var image: CGImageBox?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PlaceholderTile(game: game)
                    .aspectRatio(3 / 4, contentMode: .fit)
            }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: "\(game.id)#\(maxPixelSize)") {
            await load()
        }
    }

    private func load() async {
        guard let model, let media = model.media(for: game) else { return }
        let cache = model.thumbnails
        guard let file = await media.firstImage(for: game) else {
            image = nil
            return
        }
        let box = await cache.image(for: file.url, maxPixelSize: maxPixelSize)
        if !Task.isCancelled { image = box }
    }
}

struct PlaceholderTile: View {
    let game: Game

    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.6, min(1.4, geometry.size.width / 150))
            VStack(alignment: .leading) {
                Text(game.releaseYear.map(String.init) ?? "")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.white.opacity(0.74))
                Spacer()
                Text(game.shortTitle)
                    .font(.system(size: 17 * scale, weight: .bold))
                    .lineLimit(3)
                if let subtitle = game.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }
            }
            .padding(12 * scale)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(Theme.tileColor(for: game.title))
            .overlay(ScanlineOverlay())
        }
        .foregroundStyle(.white)
    }
}

/// Faint horizontal lines, a nod to CRT monitors.
struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.18)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

/// Reports where the selected tile is, so Control-Return can open its menu.
private struct SelectedTileReporter: View {
    let gameID: String
    let model: AppModel

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                model.selectedTileFrame = (gameID, $0)
            }
            .onDisappear {
                if model.selectedTileFrame?.id == gameID { model.selectedTileFrame = nil }
            }
    }
}

struct GameListView: View {
    let games: [Game]
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var frame: CGRect = .zero
    @State private var clickMonitor: Any?

    var body: some View {
        Table(games, selection: selection, sortOrder: tableSort) {
            TableColumn("Title", value: \.title) { game in
                HStack(spacing: 10) {
                    BoxArtView(game: game, width: 22, maxPixelSize: 64)
                        .frame(height: 30)
                    Text(game.title)
                    if model.isFavorite(game) {
                        Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.caption)
                    }
                }
                .onHover { if $0 { model.prefetchExtras(for: game) } }
            }
            .width(min: 240, ideal: 360)
            TableColumn("Year", value: \.sortYear) { game in
                Text(game.releaseYear.map(String.init) ?? "").foregroundStyle(Theme.textSecondary).monospacedDigit()
            }
            .width(52)
            TableColumn("Developer", value: \.sortDeveloper) { game in
                Text(game.developer ?? "").foregroundStyle(Theme.textSecondary)
            }
            TableColumn("Genre") { game in
                Text(game.genres.joined(separator: ", ")).foregroundStyle(Theme.textSecondary)
            }
            TableColumn("Installed") { game in
                if game.isEXoGame {
                    Image(systemName: model.isInstalled(game) ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(model.isInstalled(game) ? Theme.accent : Theme.textTertiary)
                }
            }
            .width(64)
            TableColumn("Last played") { game in
                Text(Formatters.date(model.lastPlayed(game))).foregroundStyle(Theme.textSecondary)
            }
            .width(100)
            TableColumn("Played") { game in
                Text(model.playCount(game) == 0 ? "" : String(model.playCount(game)))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .width(52)
        }
        // Take the keyboard on appearing, as the grid does, so the arrow
        // keys move in the list and not in the sidebar.
        .focused($focused)
        .onAppear {
            focused = true
            startClickMonitor()
        }
        .onDisappear {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let game = model.library?.game(id: id) {
                GameContextMenu(game: game)
            }
        } primaryAction: { ids in
            if let id = ids.first, let game = model.library?.game(id: id) { model.play(game) }
        }
        .onKeyPress(.return) {
            model.activateSelection()
            return .handled
        }
        .onKeyPress(.space) {
            model.quickLookCurrentMedia()
            return .handled
        }
        .onKeyPress(.escape) { model.goBack() ? .handled : .ignored }
        .onKeyPress(phases: .down) { press in
            let modifiers = press.modifiers
            guard modifiers.contains(.option), modifiers.isDisjoint(with: [.command, .shift, .control]) else {
                return .ignored
            }
            switch press.key {
            case .leftArrow: model.showPreviousMedia()
            case .rightArrow: model.showNextMedia()
            default: return .ignored
            }
            return .handled
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.selectedGameID }, set: { model.selectedGameID = $0 })
    }

    /// A click on a column header sorts by it, through the same setting as
    /// the toolbar's Sort menu; a second click turns the order around. The
    /// columns that read the user's play history have no key path to sort
    /// by here; the Sort menu covers them.
    private var tableSort: Binding<[KeyPathComparator<Game>]> {
        Binding(
            get: {
                let order: SortOrder = model.settings.sortAscending ? .forward : .reverse
                switch model.settings.sortOrder {
                case .title: return [KeyPathComparator(\.title, order: order)]
                case .releaseYear: return [KeyPathComparator(\.sortYear, order: order)]
                case .developer: return [KeyPathComparator(\.sortDeveloper, order: order)]
                default: return []
                }
            },
            set: { comparators in
                guard let first = comparators.first else { return }
                let column: GameSortOrder?
                switch first.keyPath {
                case \Game.title: column = .title
                case \Game.sortYear: column = .releaseYear
                case \Game.sortDeveloper: column = .developer
                default: column = nil
                }
                guard let column else { return }
                model.settings.sortOrder = column
                model.settings.sortAscending = first.order == .forward
            })
    }

    /// A click on a row does not take the keyboard back from the sidebar,
    /// not even on another row, so the arrow keys keep moving the sidebar.
    /// Watch clicks in the window and take focus when one lands in the list.
    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                guard let content = event.window?.contentView, event.window === NSApp.mainWindow else { return }
                // SwiftUI's global space has its origin at the top left of the content view.
                let point = content.convert(event.locationInWindow, from: nil)
                let global = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
                if frame.contains(global) { focused = true }
            }
            return event
        }
    }
}

/// The right-click menu for a game, shared by the grid, list and inspector.
struct GameContextMenu: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let installed = model.isInstalled(game)
        let variants =
            game.hasLaunchVersions && installed ? model.launchVariants(for: game) : []
        if game.isEXoGame {
            if installed {
                Button("Play") { model.play(game) }
                if variants.count > 1 {
                    Menu("Play Version") {
                        ForEach(variants) { variant in
                            Button(variant.title) { model.play(game, variant: variant) }
                                .disabled(variant.needsWindowsHelper)
                                .help(variant.unplayableReason ?? "")
                        }
                    }
                }
            } else {
                Button("Install…") { model.pendingInstall = game }
            }
        } else if game.launchKind == .soundtrack {
            Button("Play") { model.play(game) }
            if let player = model.externalPlayer(for: game) {
                Button("Open in \(player.name)") { model.openAlbum(game, with: player.url) }
            }
            Menu("Open With") {
                ForEach(model.externalPlayers(for: game)) { player in
                    Button {
                        model.openAlbum(game, with: player.url)
                    } label: {
                        Label {
                            Text(player.isDefault ? "\(player.name) (default)" : player.name)
                        } icon: {
                            Image(nsImage: player.icon)
                        }
                    }
                }
                Divider()
                Button("Other…") { model.chooseAlbumPlayer(game) }
            }
            if model.albumInfo(for: game)?.album.isUnpacked == true {
                Button("Remove Unpacked Album…") { model.pendingAlbumRemoval = game }
            }
        } else if game.launchKind == .video {
            Button("Play") { model.play(game) }
            VideoOpenWithMenu(game: game)
        } else {
            Button(model.isDocumentItem(game) ? "Open" : "Play") { model.play(game) }
        }
        Button("Configure…") { model.configure(game) }
        if let session = model.launchSession(for: game) {
            Button(session.isRunning ? "Show Launch Log…" : "Show Last Launch Log…") {
                model.showLaunchLog(for: session)
            }
        }
        Divider()
        Button("Open Game Page") { model.openedGameID = game.id }
        GameExtrasMenu(game: game)
        OtherVersionsMenu(game: game)
        Divider()
        Button(model.isFavorite(game) ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite(game) }
        Button("Edit Game Info…") { model.pendingInfoGame = game }
        Divider()
        Button("Show in Finder") { model.revealInFinder(game) }
        if installed, game.isEXoGame {
            Button("Uninstall…") { model.pendingUninstall = game }
                .disabled(model.fileOperationBlocker(for: game) != nil)
                .help(model.fileOperationBlocker(for: game) ?? "")
        }
    }
}

/// The same game in other collections and packs; choosing one selects it.
struct OtherVersionsMenu: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let versions = model.otherVersions(of: game)
        if !versions.isEmpty {
            Menu("Other Versions") {
                ForEach(versions) { version in
                    Button(Self.label(for: version)) { model.reveal(version) }
                }
            }
        }
    }

    /// "A Mind Forever Voyaging — eXoIF", with the year when known.
    static func label(for game: Game) -> String {
        let source = GameVersionIndex.source(of: game)
        let detail = game.releaseYear.map { "\(source), \($0)" } ?? source
        return "\(game.title) — \(detail)"
    }
}

/// The Extras submenu. Menus cannot change once open, so it shows what
/// `extrasCache` holds; hovering a tile or row fills the cache in time.
struct GameExtrasMenu: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let entry = model.extrasCache[game.id]
        Menu("Extras") {
            if let manual = entry?.manual {
                Button("Manual") { model.open(manual) }
                Divider()
            }
            if let entry {
                if entry.extras.isEmpty, entry.manual == nil {
                    Text("No extras")
                }
                ForEach(entry.extras) { extra in
                    Button(extra.name) { model.open(extra.url) }
                }
            } else {
                Text("Loading…")
            }
        }
        .onAppear { model.prefetchExtras(for: game) }
    }
}

nonisolated extension Game {
    /// Sort keys for the list's column headers; `KeyPathComparator` needs non-optional values
    /// and key paths that are `Sendable`, so not isolated to the main actor.
    var sortYear: Int { releaseYear ?? 0 }
    var sortDeveloper: String { developer ?? "" }
}
