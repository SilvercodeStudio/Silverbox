import eXoCore
import SwiftUI

/// The right-hand inspector for the selected game.
struct GameInspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let game = model.selectedGame {
            GameInspectorContent(game: game)
                .id(game.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "gamecontroller").font(.largeTitle).foregroundStyle(Theme.textTertiary)
                Text("Select a game").foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panel)
        }
    }
}

struct GameInspectorContent: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var notesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        InspectorIconButton(systemImage: model.isFavorite(game) ? "heart.fill" : "heart", help: "Favorite") {
                            model.toggleFavorite(game)
                        }
                        .foregroundStyle(model.isFavorite(game) ? Theme.accent : Theme.textPrimary)
                        InspectorIconButton(systemImage: "pencil", help: "Edit game info") { model.pendingInfoGame = game }
                        InspectorIconButton(systemImage: "arrow.up.forward.square", help: "Open game page") { model.openedGameID = game.id }
                    }
                    MediaGalleryView(game: game)
                    Text(game.title)
                        .font(.system(size: 18, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Formatters.releaseLine(game))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    PlayButtonRow(game: game)
                }
                .padding(16)
                .background(Theme.toneColor(for: game.title))

                VStack(alignment: .leading, spacing: 18) {
                    StatsRow(game: game)
                    TagRow(game: game)
                    MetadataGrid(game: game)
                    if let notes = game.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle("About")
                            Text(notes)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(notesExpanded ? nil : 6)
                                .fixedSize(horizontal: false, vertical: true)
                            if notes.count > 360 {
                                Button(notesExpanded ? "Less" : "More") { notesExpanded.toggle() }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle("Extras")
                        ExtrasList(game: game, limit: 6)
                    }
                    FilesSection(game: game)
                    if let alternates = model.library.map({ $0.alternateNames(for: game) }), !alternates.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionTitle("Also known as")
                            ForEach(alternates, id: \.name) { alternate in
                                HStack {
                                    Text(alternate.name).font(.system(size: 12))
                                    if let region = alternate.region {
                                        Text(region).font(.caption).foregroundStyle(Theme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.panel)
    }
}

struct InspectorIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
    }
}

/// Play (with a version menu when a game offers several), or Install.
struct PlayButtonRow: View {
    let game: Game
    var large = false
    @Environment(AppModel.self) private var model

    var body: some View {
        let installed = model.isInstalled(game)
        let variants = game.isDOSGame && installed ? model.launchVariants(for: game) : []
        HStack(spacing: 8) {
            if game.isDOSGame, !installed {
                Button { model.pendingInstall = game } label: {
                    Label("Install…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .frame(height: large ? 40 : 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else {
                Button { model.play(game) } label: {
                    Label(model.isDocumentItem(game) ? "Open" : "Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: large ? 40 : 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                if variants.count > 1 {
                    Menu {
                        ForEach(variants) { variant in
                            Button(variant.title) { model.play(game, variant: variant) }
                                .disabled(variant.needsWindowsHelper)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Choose a version to play")
                }
            }
            Button("Configure") { model.configure(game) }
                .help("Save launch choices for this game")
                .frame(height: large ? 40 : 30)
            Menu {
                GameContextMenu(game: game)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .foregroundStyle(Theme.accentText)
    }
}

struct StatsRow: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Stat(label: "Last played", value: Formatters.date(model.lastPlayed(game)))
            Stat(label: "Play time", value: Formatters.playTime(model.playTimeSeconds(game)))
            Stat(label: "Times played", value: String(model.playCount(game)))
        }
        .padding(12)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
    }

    struct Stat: View {
        let label: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                Text(value).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Playlist, theme and series chips.
struct TagRow: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let tags = game.playlistTags.map { ($0, "list.bullet") } + game.themeTags.map { ("Theme: \($0)", "tag") } + game.seriesNames.map { ($0, "square.stack") }
        if !tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.0) { tag in
                    Label(tag.0, systemImage: tag.1)
                        .font(.system(size: 11))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().stroke(Theme.borderStrong))
                }
            }
        }
    }
}

struct MetadataGrid: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let build = model.eXoDOSBuild(for: game)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            row("Developer", game.developer)
            row("Publisher", game.publisher)
            row("Genre", game.genres.isEmpty ? nil : game.genres.joined(separator: ", "))
            row("Play mode", game.playMode)
            row("Players", game.maxPlayers.map(String.init))
            row("Rating", game.rating)
            row("Source", game.source)
            row("Region", game.region)
            row("Version", game.version)
            if game.communityStarRatingVotes > 0, let rating = game.communityStarRating {
                row("Community", String(format: "%.1f ★ (%d votes)", rating, game.communityStarRatingVotes))
            }
            if game.isDOSGame {
                row("eXoDOS runs with", build?.displayName ?? "DOSBox")
                row("Mac emulator", model.emulatorKind(for: game).displayName)
            }
            if let url = game.wikipediaURL, let link = URL(string: url) {
                GridRow {
                    Text("Wikipedia").foregroundStyle(Theme.textTertiary)
                    Link("Open article", destination: link)
                }
            }
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow(alignment: .top) {
                Text(label).foregroundStyle(Theme.textTertiary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

/// The launcher, installer and config paths, in LaunchBox's relative form.
struct FilesSection: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Files")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Launch", game.applicationPath)
                row("Install", game.configurationPath)
                if game.isDOSGame, let root = game.rootFolder { row("Config", root + "\\dosbox.conf") }
                row("Manual", game.manualPath)
                row("Music", game.musicPath)
            }
            Button("Show in Finder") { model.revealInFinder(game) }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(12)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow(alignment: .top) {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Text(WindowsPath.posix(value))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
