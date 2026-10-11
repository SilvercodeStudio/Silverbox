import AVFoundation
import Foundation
import Observation

/// Plays a game's menu music track, like LaunchBox does while browsing.
@Observable
final class MenuMusicPlayer {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var isUnsupportedFormat = false
    var volume: Double = 0.6 {
        didSet { player?.volume = Float(volume) }
    }

    @ObservationIgnored private var player: AVAudioPlayer?

    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]

    var trackName: String? {
        currentURL?.deletingPathExtension().lastPathComponent
    }

    func play(url: URL) {
        if currentURL == url {
            if let player, !player.isPlaying {
                player.play()
                isPlaying = true
            }
            return
        }
        stop()
        currentURL = url
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            isUnsupportedFormat = true
            return
        }
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1
            next.volume = Float(volume)
            next.prepareToPlay()
            next.play()
            player = next
            isPlaying = true
            isUnsupportedFormat = false
        } catch {
            isUnsupportedFormat = true
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentURL = nil
        isUnsupportedFormat = false
    }
}
