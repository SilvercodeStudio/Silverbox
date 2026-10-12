import Foundation
import Testing
@testable import eXoCore

@Suite("Music decoders")
struct MusicDecoderTests {
    static var audio: URL { FixtureLibrary.rootURL.appendingPathComponent("Audio") }

    /// Reads up to `maxFrames` and reports how many came back and the loudest sample.
    private func drain(_ decoder: any MusicDecoder, maxFrames: Int) -> (frames: Int, peak: Int) {
        let chunk = 2048
        var buffer = [Int16](repeating: 0, count: chunk * decoder.channelCount)
        var total = 0
        var peak = 0
        while total < maxFrames {
            let got = buffer.withUnsafeMutableBufferPointer { decoder.read(into: $0.baseAddress!, frameCount: chunk) }
            if got == 0 { break }
            total += got
            peak = max(peak, buffer[..<(got * decoder.channelCount)].map { abs(Int($0)) }.max() ?? 0)
        }
        return (total, peak)
    }

    @Test func decodesOggVorbis() throws {
        let decoder = try MusicDecoders.decoder(for: Self.audio.appendingPathComponent("tone.ogg"))
        #expect(decoder is VorbisDecoder)
        #expect(decoder.sampleRate == 22050)
        #expect(decoder.channelCount == 2)
        let first = drain(decoder, maxFrames: 100_000)
        #expect(first.frames > 10_000 && first.frames < 12_000, "0.5 s at 22,050 Hz, got \(first.frames) frames")
        #expect(first.peak > 1_000)
        decoder.rewind()
        #expect(drain(decoder, maxFrames: 100_000).frames == first.frames)
    }

    @Test func playsProTrackerModule() throws {
        let decoder = try MusicDecoders.decoder(for: Self.audio.appendingPathComponent("tone.mod"))
        let module = try #require(decoder as? ModuleDecoder)
        #expect(module.title == "eXoCore test tone")
        #expect(module.channelCount == 2)
        #expect(module.sampleRate == 44100)
        let result = drain(decoder, maxFrames: 44_100)
        #expect(result.frames >= 44_100, "modules loop, so the decoder never runs dry")
        #expect(result.peak > 1_000)
        decoder.rewind()
        #expect(drain(decoder, maxFrames: 4_096).frames >= 4_096)
    }

    @Test func rejectsFormatsWithoutADecoder() {
        #expect(MusicDecoders.canDecode(URL(fileURLWithPath: "/tmp/track.xm")))
        #expect(!MusicDecoders.canDecode(URL(fileURLWithPath: "/tmp/track.amf")))
        #expect(throws: MusicDecoderError.self) {
            try MusicDecoders.decoder(for: URL(fileURLWithPath: "/tmp/track.amf"))
        }
        #expect(throws: MusicDecoderError.self) {
            try MusicDecoders.decoder(for: URL(fileURLWithPath: "/tmp/missing.ogg"))
        }
    }
}
