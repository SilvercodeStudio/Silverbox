import Foundation

/// A value in a `.torrent` file: bencoding has integers, byte strings,
/// lists and dictionaries with byte-string keys.
nonisolated public enum BencodeValue: Sendable, Hashable {
    case integer(Int64)
    case bytes(Data)
    case list([BencodeValue])
    case dictionary([String: BencodeValue])

    public subscript(key: String) -> BencodeValue? {
        if case .dictionary(let entries) = self { return entries[key] }
        return nil
    }

    public var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// A byte string as UTF-8, which torrent paths use.
    public var string: String? {
        if case .bytes(let data) = self { return String(data: data, encoding: .utf8) }
        return nil
    }

    public var list: [BencodeValue]? {
        if case .list(let values) = self { return values }
        return nil
    }
}

nonisolated public enum BencodeError: Error, Equatable, LocalizedError {
    case malformed(offset: Int)

    public var errorDescription: String? {
        switch self {
        case .malformed(let offset): return "The torrent file is damaged near byte \(offset)."
        }
    }
}

nonisolated public enum Bencode {
    public static func decode(_ data: Data) throws -> BencodeValue {
        var reader = Reader(bytes: [UInt8](data))
        return try reader.value()
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func value() throws -> BencodeValue {
            guard offset < bytes.count else { throw BencodeError.malformed(offset: offset) }
            switch bytes[offset] {
            case UInt8(ascii: "i"):
                offset += 1
                let value = try number(until: UInt8(ascii: "e"))
                return .integer(value)
            case UInt8(ascii: "l"):
                offset += 1
                var values: [BencodeValue] = []
                while try peek() != UInt8(ascii: "e") { values.append(try value()) }
                offset += 1
                return .list(values)
            case UInt8(ascii: "d"):
                offset += 1
                var entries: [String: BencodeValue] = [:]
                while try peek() != UInt8(ascii: "e") {
                    let key = try byteString()
                    entries[String(decoding: key, as: UTF8.self)] = try value()
                }
                offset += 1
                return .dictionary(entries)
            default:
                return .bytes(Data(try byteString()))
            }
        }

        private func peek() throws -> UInt8 {
            guard offset < bytes.count else { throw BencodeError.malformed(offset: offset) }
            return bytes[offset]
        }

        private mutating func byteString() throws -> ArraySlice<UInt8> {
            let length = try number(until: UInt8(ascii: ":"))
            guard length >= 0, length <= bytes.count - offset else { throw BencodeError.malformed(offset: offset) }
            let start = offset
            offset += Int(length)
            return bytes[start..<offset]
        }

        /// The decimal number up to `terminator`, which is skipped.
        private mutating func number(until terminator: UInt8) throws -> Int64 {
            let start = offset
            while offset < bytes.count, bytes[offset] != terminator { offset += 1 }
            guard offset < bytes.count, offset > start,
                let value = Int64(String(decoding: bytes[start..<offset], as: UTF8.self))
            else { throw BencodeError.malformed(offset: start) }
            offset += 1
            return value
        }
    }
}

/// The files a `.torrent` lists, numbered as aria2's `--select-file`
/// counts them (from 1, in the torrent's order). eXo's Lite editions ship
/// the full collection's torrent in `eXo/util/aria/` and download one game
/// at a time from it.
nonisolated public struct TorrentFileList: Sendable, Hashable {
    nonisolated public struct File: Sendable, Hashable {
        public var index: Int
        /// The path inside the torrent, without its top folder:
        /// `eXo/eXoDOS/<game>.zip`, the same path as in the download.
        public var path: String
        public var length: Int64
    }

    public let url: URL
    public let name: String
    public let files: [File]
    private let indexByPath: [String: Int]

    public init(url: URL, data: Data) throws {
        let torrent = try Bencode.decode(data)
        guard let info = torrent["info"], let name = info["name"]?.string else {
            throw BencodeError.malformed(offset: 0)
        }
        var files: [File] = []
        if let entries = info["files"]?.list {
            for (offset, entry) in entries.enumerated() {
                guard let length = entry["length"]?.integer,
                    let components = entry["path"]?.list?.compactMap(\.string), !components.isEmpty
                else { throw BencodeError.malformed(offset: 0) }
                files.append(File(index: offset + 1, path: components.joined(separator: "/"), length: length))
            }
        } else if let length = info["length"]?.integer {
            files.append(File(index: 1, path: name, length: length))
        }
        self.url = url
        self.name = name
        self.files = files
        // Matched without regard to case, as the Mac's file system does.
        var paths: [String: Int] = [:]
        for (position, file) in files.enumerated() { paths[file.path.lowercased()] = position }
        indexByPath = paths
    }

    public init(contentsOf url: URL) throws {
        try self.init(url: url, data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public func file(at path: String) -> File? {
        indexByPath[path.lowercased()].map { files[$0] }
    }

    /// The torrent at `url`, read once until the file changes. eXoDOS's is
    /// 2.7 MB, and the install sheet asks for it on every redraw.
    public static func cached(_ url: URL) -> TorrentFileList? {
        cache.value(for: url) { try? TorrentFileList(contentsOf: $0) }
    }

    private static let cache = FileAnswerCache<TorrentFileList?>()
}
