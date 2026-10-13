import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers
import eXoCore

/// A soundtrack album as the app shows it: the core's album plus the track
/// durations, read once the files are unpacked.
struct AlbumInfo {
    var album: SoundtrackAlbum
    var durations: [String: TimeInterval] = [:]
}

/// Soundtrack albums: reading, unpacking on first play, playing in the app
/// or handing the tracks to another player.
extension AppModel {
    func albumInfo(for game: Game) -> AlbumInfo? {
        albumCache[game.id]
    }

    /// Reads the album from its unpacked folder or the zip's directory, and
    /// the track durations when the files are there. Cached per game.
    @discardableResult
    func loadAlbum(for game: Game, force: Bool = false) async -> AlbumInfo? {
        if !force, let cached = albumCache[game.id] { return cached }
        guard let snapshot = snapshot(for: game),
            let archive = SoundtrackLibrary.archiveURL(for: game, root: snapshot.root)
        else { return nil }
        let store = localStore
        do {
            let album = try await Task.detached {
                try await SoundtrackLibrary.album(archiveURL: archive, localStore: store)
            }
            .value
            var info = AlbumInfo(album: album)
            if album.isUnpacked {
                for track in album.tracks {
                    guard let url = track.url else { continue }
                    if let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite {
                        info.durations[track.id] = seconds
                    }
                }
            }
            albumCache[game.id] = info
            return info
        } catch {
            alert = AppAlert(title: "Could not read \(game.title)", message: error.localizedDescription)
            return nil
        }
    }

    /// Play on a soundtrack: unpacks the zip the first time, then plays from
    /// the chosen track. Play on the album that is already loaded resumes it;
    /// a track index restarts from that track. Menu music waits meanwhile.
    func playAlbum(_ game: Game, startAt index: Int? = nil) {
        if index == nil, album.game?.id == game.id {
            if !album.isPlaying { album.resume() }
            return
        }
        let index = index ?? 0
        Task { [weak self] in
            guard let self, let info = await self.unpackedAlbum(for: game) else { return }
            guard !info.album.tracks.isEmpty else {
                self.alert = AppAlert(
                    title: "No tracks", message: "\(game.title) holds no audio files that macOS can play.")
                return
            }
            self.music.pause()
            self.album.play(info.album, game: game, startAt: min(index, info.album.tracks.count - 1))
            self.userState.recordPlay(game.launchBoxID, seconds: 0)
            if self.scope == .recentlyPlayed { self.refreshVisibleGames() }
        }
    }

    func stopAlbum() {
        album.stop()
        updateMusic()
    }

    /// The album, unpacking it first when needed; the bar shows the progress.
    private func unpackedAlbum(for game: Game) async -> AlbumInfo? {
        guard let info = await loadAlbum(for: game) else { return nil }
        if info.album.isUnpacked { return info }
        albumUnpackingID = game.id
        defer { albumUnpackingID = nil }
        do {
            try await SoundtrackLibrary.unpack(info.album)
        } catch {
            alert = AppAlert(title: "Could not unpack \(game.title)", message: error.localizedDescription)
            return nil
        }
        return await loadAlbum(for: game, force: true)
    }

    /// The album's file type; FLAC until the album is read.
    private func albumFileType(for game: Game) -> UTType? {
        let ext =
            albumCache[game.id]?.album.tracks.first?.fileName.split(separator: ".").last.map(String.init) ?? "flac"
        return UTType(filenameExtension: ext)
    }

    /// The app macOS opens the album's files with, for "Open in …".
    func externalPlayer(for game: Game) -> ExternalPlayer? {
        albumFileType(for: game).flatMap { ExternalPlayer.systemDefault(for: $0) }
    }

    /// Every app registered for the album's file type, the default first.
    func externalPlayers(for game: Game) -> [ExternalPlayer] {
        albumFileType(for: game).map { ExternalPlayer.all(for: $0) } ?? []
    }

    /// Hands the unpacked tracks to an app (the default one when nil),
    /// unpacking first when needed.
    func openAlbum(_ game: Game, with app: URL? = nil) {
        Task { [weak self] in
            guard let self, let info = await self.unpackedAlbum(for: game) else { return }
            let urls = info.album.tracks.compactMap(\.url)
            guard !urls.isEmpty else { return }
            guard let app = app ?? self.externalPlayer(for: game)?.url else {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                return
            }
            do {
                _ = try await NSWorkspace.shared.open(
                    urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                self.alert = AppAlert(title: "Could not open \(game.title)", message: error.localizedDescription)
            }
        }
    }

    /// "Other…": lets the user pick any app for the album's tracks.
    func chooseAlbumPlayer(_ game: Game) {
        guard let app = ExternalPlayer.choose(message: "Choose an app to open the tracks of \(game.title)") else {
            return
        }
        openAlbum(game, with: app)
    }

    /// Deletes the unpacked copy; the zip in the library stays.
    func removeAlbum(_ game: Game) {
        guard let info = albumCache[game.id], info.album.isUnpacked else { return }
        if album.game?.id == game.id { stopAlbum() }
        do {
            try SoundtrackLibrary.remove(info.album)
        } catch {
            alert = AppAlert(title: "Could not remove \(game.title)", message: error.localizedDescription)
            return
        }
        albumCache[game.id] = nil
        Task { await loadAlbum(for: game) }
    }
}
