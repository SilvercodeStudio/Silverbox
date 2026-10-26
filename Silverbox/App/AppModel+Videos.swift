import AppKit
import Foundation
import UniformTypeIdentifiers
import SilverboxCore

/// A video entry with several videos (episodes, DVD discs) and the list to
/// choose from.
struct VideoChoice: Identifiable {
    let game: Game
    let items: [VideoItem]
    /// The app chosen in Open With; nil for the video player setting.
    let app: URL?
    var id: String { game.id }
}

/// Video entries: eXoDOS starts them in VLC through a batch file. Here the
/// files open in the video player from Settings (the macOS default unless
/// chosen) or an app picked in Open With; DVD disc images open in VLC.
extension AppModel {
    /// The bundle identifier of VLC, the one common Mac player for DVD images.
    static let vlcBundleID = "org.videolan.vlc"

    /// Play or Open With on a video entry: opens its only video, or asks
    /// which one to open. `app` overrides the video player setting.
    func playVideo(_ game: Game, with app: URL? = nil) {
        guard let snapshot = snapshot(for: game) else { return }
        let items = VideoLibrary.items(for: game, root: snapshot.root)
        switch items.count {
        case 0:
            let launcher = snapshot.root.url(forWindowsRelativePath: game.applicationPath)
            alert = AppAlert(
                title: "No videos found",
                message: "No video files for \(game.title) are in \(launcher.deletingLastPathComponent().path).")
        case 1:
            openVideo(items[0], of: game, with: app)
        default:
            pendingVideoChoice = VideoChoice(game: game, items: items, app: app)
        }
    }

    /// Opens one video: in `app` when given, a DVD image in VLC, anything
    /// else in the video player setting.
    func openVideo(_ item: VideoItem, of game: Game, with app: URL? = nil) {
        var player = app
        if player == nil, item.isDiscImage {
            player = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.vlcBundleID)
            if player == nil {
                alert = AppAlert(
                    title: "VLC is needed",
                    message:
                        "\(item.title) of \(game.title) is a DVD disc image. QuickTime Player cannot play DVD images. Install VLC from videolan.org, then press Play again, or use Open With to choose another player."
                )
                return
            }
        }
        if let player = player ?? chosenVideoPlayer?.url {
            NSWorkspace.shared.open(
                [item.url], withApplicationAt: player, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(item.url)
        }
        music.pause()
        userState.recordPlay(game.launchBoxID, seconds: 0)
        if scope == .recentlyPlayed { refreshVisibleGames() }
    }

    /// "Other…" in Open With: plays the entry in any app.
    func chooseVideoPlayer(for game: Game) {
        guard let app = ExternalPlayer.choose(message: "Choose an app to play \(game.title)") else { return }
        playVideo(game, with: app)
    }

    /// The player from Settings, when one is chosen and still installed.
    var chosenVideoPlayer: ExternalPlayer? {
        guard let path = settings.videoPlayerPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return ExternalPlayer(url: URL(fileURLWithPath: path))
    }

    /// The app Play opens videos in: the setting, else the macOS default.
    var videoPlayer: ExternalPlayer? {
        chosenVideoPlayer ?? ExternalPlayer.systemDefault(for: .mpeg4Movie)
    }

    /// Every app registered for MP4 video, the macOS default first.
    var videoPlayers: [ExternalPlayer] {
        ExternalPlayer.all(for: .mpeg4Movie)
    }
}
