import AVFoundation
import Foundation
import Observation
import SilverboxCore

/// Plays an unpacked soundtrack album track by track through AVAudioPlayer
/// (FLAC and MP3 are native). The position is published for the album bar.
@Observable
final class AlbumPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var game: Game?
    private(set) var album: SoundtrackAlbum?
    private(set) var trackIndex = 0
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?
    var volume: Double = 0.6 {
        didSet { player?.volume = Float(volume) }
    }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?

    /// True while an album is loaded, playing or paused.
    var isActive: Bool { album != nil }

    var currentTrack: SoundtrackTrack? {
        guard let album, album.tracks.indices.contains(trackIndex) else { return nil }
        return album.tracks[trackIndex]
    }

    func play(_ album: SoundtrackAlbum, game: Game, startAt index: Int = 0) {
        self.album = album
        self.game = game
        start(track: index)
    }

    func playTrack(_ index: Int) {
        guard album != nil else { return }
        start(track: index)
    }

    func next() {
        guard let album else { return }
        if trackIndex + 1 < album.tracks.count {
            start(track: trackIndex + 1)
        } else {
            finish()
        }
    }

    /// Restarts the track after a few seconds in, like a CD player.
    func previous() {
        if position > 3 || trackIndex == 0 {
            seek(to: 0)
            if !isPlaying { resume() }
        } else {
            start(track: trackIndex - 1)
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func resume() {
        guard let player else {
            if album != nil { start(track: trackIndex) }
            return
        }
        player.play()
        isPlaying = true
        startTicker()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, duration))
        position = player.currentTime
    }

    func stop() {
        player?.stop()
        player = nil
        stopTicker()
        album = nil
        game = nil
        trackIndex = 0
        position = 0
        duration = 0
        isPlaying = false
        errorMessage = nil
    }

    private func start(track index: Int) {
        guard let album, album.tracks.indices.contains(index), let url = album.tracks[index].url else { return }
        player?.stop()
        trackIndex = index
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            next.volume = Float(volume)
            next.prepareToPlay()
            next.play()
            player = next
            duration = next.duration
            position = 0
            isPlaying = true
            errorMessage = nil
            startTicker()
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    /// The album ended: back to the first track, paused, still in the bar.
    private func finish() {
        player?.stop()
        player = nil
        stopTicker()
        trackIndex = 0
        position = 0
        duration = 0
        isPlaying = false
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next() }
    }
}
