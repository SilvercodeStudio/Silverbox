import CStbVorbis
import Foundation

/// Ogg Vorbis decoding through the vendored stb_vorbis (Sources/CStbVorbis).
nonisolated public final class VorbisDecoder: MusicDecoder {
    private let handle: OpaquePointer
    public let sampleRate: Int
    public let channelCount: Int
    public let title: String? = nil
    /// The length of the track in frames.
    public let frameCount: Int

    public init(url: URL) throws {
        var error: Int32 = 0
        guard let handle = stb_vorbis_open_filename(url.path, &error, nil) else {
            throw MusicDecoderError.cannotOpen("stb_vorbis could not open \(url.lastPathComponent) (error \(error)).")
        }
        self.handle = handle
        let info = stb_vorbis_get_info(handle)
        sampleRate = Int(info.sample_rate)
        channelCount = Int(info.channels)
        frameCount = Int(stb_vorbis_stream_length_in_samples(handle))
    }

    deinit {
        stb_vorbis_close(handle)
    }

    public func read(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int) -> Int {
        Int(stb_vorbis_get_samples_short_interleaved(handle, Int32(channelCount), buffer, Int32(frameCount * channelCount)))
    }

    public func rewind() {
        _ = stb_vorbis_seek_start(handle)
    }
}
