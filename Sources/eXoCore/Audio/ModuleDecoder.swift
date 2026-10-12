import CXmpLite
import Foundation

/// Tracker module playback (MOD, S3M, XM, IT) through the vendored
/// libxmp-lite (Sources/CXmpLite). The module loops for as long as it is read.
nonisolated public final class ModuleDecoder: MusicDecoder {
    private let context: xmp_context
    public let sampleRate: Int
    public let channelCount = 2
    public let title: String?
    /// The module format as libxmp names it, for example "Protracker".
    public let format: String

    public init(url: URL, sampleRate: Int = 44100) throws {
        guard let context = xmp_create_context() else {
            throw MusicDecoderError.cannotOpen("libxmp could not create a player.")
        }
        guard xmp_load_module(context, url.path) == 0 else {
            xmp_free_context(context)
            throw MusicDecoderError.cannotOpen("libxmp could not load \(url.lastPathComponent).")
        }
        guard xmp_start_player(context, Int32(sampleRate), 0) == 0 else {
            xmp_release_module(context)
            xmp_free_context(context)
            throw MusicDecoderError.cannotOpen("libxmp could not start \(url.lastPathComponent).")
        }
        _ = xmp_set_player(context, XMP_PLAYER_INTERP, XMP_INTERP_SPLINE)
        self.context = context
        self.sampleRate = sampleRate

        var info = xmp_module_info()
        xmp_get_module_info(context, &info)
        let module = info.mod.pointee
        let name = Self.string(fromCArray: module.name)
        title = name.isEmpty ? nil : name
        format = Self.string(fromCArray: module.type)
    }

    deinit {
        xmp_end_player(context)
        xmp_release_module(context)
        xmp_free_context(context)
    }

    public func read(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int) -> Int {
        let bytes = frameCount * channelCount * MemoryLayout<Int16>.size
        // loop = 0 disables the loop check, so the module plays on indefinitely.
        return xmp_play_buffer(context, buffer, Int32(bytes), 0) == 0 ? frameCount : 0
    }

    public func rewind() {
        xmp_restart_module(context)
        _ = xmp_play_buffer(context, nil, 0, 0)   // resets the buffered frame
    }

    private static func string<T>(fromCArray array: T) -> String {
        withUnsafeBytes(of: array) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
