import SwiftUI
import UniformTypeIdentifiers
import eXoCore

/// The native stand-in for the console menu of a video entry with several
/// videos: episodes or DVD discs. Return or a double-click opens one.
struct VideoChoiceSheet: View {
    let choice: VideoChoice
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: VideoItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BoxArtView(game: choice.game, width: 56, maxPixelSize: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text(choice.game.title).font(.headline)
                    Text(
                        choice.app.map {
                            "Choose one of \(choice.items.count) videos to open in \(ExternalPlayer(url: $0).name)."
                        } ?? "Choose one of \(choice.items.count) videos."
                    )
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            List(choice.items, selection: $selection) { item in
                Label(item.title, systemImage: item.isDiscImage ? "opticaldisc" : "film")
                    .help(item.url.lastPathComponent)
            }
            .contextMenu(forSelectionType: VideoItem.ID.self) { _ in
            } primaryAction: { ids in
                play(ids.first)
            }
            .frame(height: min(CGFloat(choice.items.count) * 28 + 16, 380))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Play") { play(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { selection = choice.items.first?.id }
    }

    private func play(_ id: VideoItem.ID?) {
        guard let item = choice.items.first(where: { $0.id == id }) else { return }
        dismiss()
        model.openVideo(item, of: choice.game, with: choice.app)
    }
}

/// Open With for a video entry: every registered video player, then Other….
struct VideoOpenWithMenu: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Open With") {
            ForEach(model.videoPlayers) { player in
                Button {
                    model.playVideo(game, with: player.url)
                } label: {
                    Label {
                        Text(player.isDefault ? "\(player.name) (default)" : player.name)
                    } icon: {
                        Image(nsImage: player.icon)
                    }
                }
            }
            Divider()
            Button("Other…") { model.chooseVideoPlayer(for: game) }
        }
    }
}

/// Settings › General: the app that plays videos.
struct VideoPlayerSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let systemDefault = ExternalPlayer.systemDefault(for: .mpeg4Movie)
        let players = model.videoPlayers
        let custom = model.chosenVideoPlayer.flatMap { chosen in
            players.contains { $0.url == chosen.url } ? nil : chosen
        }
        Section("Videos") {
            HStack {
                Picker("Video player", selection: $model.settings.videoPlayerPath) {
                    Text("macOS default" + (systemDefault.map { " (\($0.name))" } ?? "")).tag(String?.none)
                    Divider()
                    ForEach(players + (custom.map { [$0] } ?? [])) { player in
                        Text(player.name).tag(Optional(player.url.path))
                    }
                }
                Button("Choose…") {
                    if let app = ExternalPlayer.choose(message: "Choose the app that plays videos", prompt: "Choose") {
                        model.settings.videoPlayerPath = app.path
                    }
                }
            }
            Text(
                "Play opens videos in this app. QuickTime Player cannot play some of them, such as MP4 files with VP9 video; VLC plays them all. DVD disc images always open in VLC. Right-click a video and use Open With to pick a player once."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
