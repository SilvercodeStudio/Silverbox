import QuickLook
import SwiftUI
import eXoCore

/// The full game page with media, metadata, extras and related games.
struct GameDetailView: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case extras = "Extras"
        case media = "Media"
        case related = "Related"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 32) {
                    MediaGalleryView(game: game, height: 420)
                        .frame(maxWidth: 720)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(game.title)
                            .font(.system(size: 30, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Formatters.releaseLine(game))
                            .foregroundStyle(Theme.textSecondary)
                        PlayButtonRow(game: game, large: true)
                        StatsRow(game: game)
                        TagRow(game: game)
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.toneColor(for: game.title))

                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Group {
                    switch tab {
                    case .overview:
                        HStack(alignment: .top, spacing: 40) {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionTitle("About")
                                Text(game.notes ?? "No description.")
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: 560, alignment: .leading)
                            VStack(alignment: .leading, spacing: 18) {
                                MetadataGrid(game: game)
                                FilesSection(game: game)
                            }
                            .frame(maxWidth: 440, alignment: .leading)
                        }
                    case .extras:
                        ExtrasList(game: game)
                            .frame(maxWidth: 560, alignment: .leading)
                    case .media:
                        MediaGridView(game: game)
                    case .related:
                        RelatedGamesView(game: game)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.window)
    }
}

/// Every image for a game, as a grid.
struct MediaGridView: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @State private var items: [GameMediaItem] = []
    @State private var previewURL: URL?

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)], alignment: .leading, spacing: 20
        ) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    ZStack {
                        Color(hex: 0x0A0B0D)
                        switch item.kind {
                        case .image: FullImageView(url: item.url, maxPixelSize: 600)
                        case .video: Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                        }
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(item.label).font(.system(size: 12))
                }
                .onTapGesture {
                    if case .video = item.kind { model.open(item.url) } else { previewURL = item.url }
                }
                .contextMenu {
                    Button("Open") { model.open(item.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                }
            }
        }
        .quickLookPreview($previewURL)
        .task(id: game.id) {
            guard let media = model.media(for: game) else { return }
            items = await media.gallery(for: game)
        }
    }
}

/// Games that share a series or developer with this one.
struct RelatedGamesView: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let related = relatedGames()
        if related.isEmpty {
            Text("No related games found.").foregroundStyle(Theme.textSecondary)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16, alignment: .bottom)],
                alignment: .leading, spacing: 20
            ) {
                ForEach(related) { other in
                    GameTileView(game: other, width: 140, isSelected: false)
                        .onTapGesture {
                            model.selectedGameID = other.id
                            model.openedGameID = other.id
                        }
                        .contextMenu { GameContextMenu(game: other) }
                }
            }
        }
    }

    private func relatedGames() -> [Game] {
        guard let library = model.snapshot(for: game) else { return [] }
        let series = Set(game.seriesNames)
        var result: [Game] = []
        if !series.isEmpty {
            result = library.games.filter { $0.id != game.id && !series.isDisjoint(with: $0.seriesNames) }
        }
        if result.count < 6, let developer = game.developer {
            let sameDeveloper = library.games.filter {
                $0.id != game.id && $0.developer == developer && !result.contains($0)
            }
            result += sameDeveloper
        }
        return Array(result.sorted { $0.sortKey < $1.sortKey }.prefix(24))
    }
}
