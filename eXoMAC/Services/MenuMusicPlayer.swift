import AVFoundation
import Foundation
import Observation
import eXoCore

/// Plays a game's menu music track, like LaunchBox does while browsing.
/// Formats macOS decodes itself go through AVAudioPlayer. Ogg Vorbis and
/// tracker modules are decoded by the core's bundled decoders and streamed
/// through AVAudioEngine.
@Observable
final class MenuMusicPlayer {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var isUnsupportedFormat = false
    /// Why the current track could not be opened, for the music bar.
    private(set) var errorMessage: String?
    var volume: Double = 0.6 {
        didSet {
            player?.volume = Float(volume)
            stream?.volume = Float(volume)
        }
    }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stream: DecodedMusicStream?

    /// Formats AVAudioPlayer handles on its own.
    static let nativeExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]
    static let supportedExtensions: Set<String> = nativeExtensions.union(MusicDecoders.extensions)

    var trackName: String? {
        currentURL?.deletingPathExtension().lastPathComponent
    }

    func play(url: URL) {
        if currentURL == url {
            if !isPlaying { resume() }
            return
        }
        stop()
        currentURL = url
        let ext = url.pathExtension.lowercased()
        do {
            if Self.nativeExtensions.contains(ext) {
                let next = try AVAudioPlayer(contentsOf: url)
                next.numberOfLoops = -1
                next.volume = Float(volume)
                next.prepareToPlay()
                next.play()
                player = next
            } else if MusicDecoders.canDecode(url) {
                let next = try DecodedMusicStream(decoder: MusicDecoders.decoder(for: url))
                next.volume = Float(volume)
                try next.start()
                stream = next
            } else {
                isUnsupportedFormat = true
                return
            }
            isPlaying = true
        } catch {
            errorMessage = error.localizedDescription
            isUnsupportedFormat = true
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        stream?.pause()
        isPlaying = false
    }

    func resume() {
        guard player != nil || stream != nil else { return }
        player?.play()
        stream?.resume()
        isPlaying = true
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        player?.stop()
        player = nil
        stream?.stop()
        stream = nil
        isPlaying = false
        currentURL = nil
        isUnsupportedFormat = false
        errorMessage = nil
    }
}

/// Streams a core ``MusicDecoder`` through AVAudioEngine and loops the track.
/// A feeder thread keeps a few buffers queued on the player node.
nonisolated final class DecodedMusicStream: @unchecked Sendable {
    private let decoder: any MusicDecoder
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let framesPerBuffer = 8192
    private let queuedBuffers = DispatchSemaphore(value: 3)
    private let stopped = StopFlag()
    private var scratch: [Int16]

    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    init(decoder: any MusicDecoder) throws {
        self.decoder = decoder
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(decoder.sampleRate),
                channels: AVAudioChannelCount(decoder.channelCount))
        else {
            throw MusicDecoderError.cannotOpen("The track's sample format is not supported.")
        }
        self.format = format
        scratch = [Int16](repeating: 0, count: framesPerBuffer * decoder.channelCount)
        engine.attach(node)
        try engine.connectNode(node, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        try engine.start()
        try node.playAudio()
        let thread = Thread { [self] in feed() }
        thread.name = "eXoMAC.menuMusic"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func pause() {
        node.pause()
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        try? node.playAudio()
    }

    func stop() {
        stopped.set()
        queuedBuffers.signal()
        node.stop()
        engine.stop()
    }

    /// Runs on the feeder thread until the stream stops.
    private func feed() {
        let channels = decoder.channelCount
        while true {
            queuedBuffers.wait()
            if stopped.isSet { return }
            var frames = decoder.read(into: &scratch, frameCount: framesPerBuffer)
            if frames == 0 {
                decoder.rewind()
                frames = decoder.read(into: &scratch, frameCount: framesPerBuffer)
            }
            guard frames > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                let channelData = buffer.floatChannelData
            else { return }
            for channel in 0..<channels {
                let out = channelData[channel]
                for frame in 0..<frames {
                    out[frame] = Float(scratch[frame * channels + channel]) / 32768
                }
            }
            buffer.frameLength = AVAudioFrameCount(frames)
            node.scheduleBuffer(buffer) { [queuedBuffers] in queuedBuffers.signal() }
        }
    }
}

nonisolated private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
