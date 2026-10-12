import Foundation

/// A source of interleaved 16-bit PCM for a music track that macOS cannot
/// decode itself. Instances are not thread-safe: read from one thread.
nonisolated public protocol MusicDecoder: AnyObject {
    var sampleRate: Int { get }
    var channelCount: Int { get }
    /// The title stored in the file, when the format has one.
    var title: String? { get }
    /// Fills `buffer` with up to `frameCount` frames (`frameCount * channelCount`
    /// samples) and returns the number of frames written; 0 at the end.
    func read(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int) -> Int
    /// Returns to the start of the track.
    func rewind()
}

nonisolated public enum MusicDecoderError: Error, LocalizedError, Equatable {
    case unsupportedFormat(String)
    case cannotOpen(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "No decoder for .\(ext) files."
        case .cannotOpen(let detail): return detail
        }
    }
}

/// Chooses a bundled decoder for the music formats that need one.
nonisolated public enum MusicDecoders {
    /// Ogg Vorbis, decoded by the vendored stb_vorbis.
    public static let vorbisExtensions: Set<String> = ["ogg", "oga"]
    /// Tracker modules, played by the vendored libxmp-lite.
    public static let moduleExtensions: Set<String> = ["mod", "s3m", "xm", "it"]
    public static let extensions: Set<String> = vorbisExtensions.union(moduleExtensions)

    public static func canDecode(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func decoder(for url: URL) throws -> any MusicDecoder {
        let ext = url.pathExtension.lowercased()
        if vorbisExtensions.contains(ext) { return try VorbisDecoder(url: url) }
        if moduleExtensions.contains(ext) { return try ModuleDecoder(url: url) }
        throw MusicDecoderError.unsupportedFormat(ext)
    }
}
