import Foundation

/// Zip files read with the system tools, with progress for long extractions.
///
/// eXo's zips were made on Windows, and some store file names in the DOS
/// code page (CP437) without the zip's UTF-8 flag: `Astérix` has the byte
/// 0x82 for é. macOS `unzip` turns that into Latin-1 (0xE9) and writes it,
/// which APFS refuses as it is not UTF-8. Archives like that are extracted
/// with `bsdtar`, which converts the names; all others with `unzip`.
nonisolated public enum ZipArchive {
    static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
    static let bsdtar = URL(fileURLWithPath: "/usr/bin/bsdtar")

    /// The paths of the archive's entries, from its central directory. Names
    /// that are not UTF-8 come from unzip as Latin-1.
    public static func entries(of archive: URL) async throws -> [String] {
        let listing = try await list(archive)
        let text =
            String(data: listing.data, encoding: .utf8) ?? String(data: listing.data, encoding: .isoLatin1) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// The raw listing.
    static func list(_ archive: URL) async throws -> (data: Data, isUTF8: Bool) {
        let result = try await CommandRunner.run(executable: unzip, arguments: ["-Z1", archive.path])
        guard result.status == 0 else {
            throw InstallError.extractionFailed(status: result.status, output: result.output)
        }
        return (result.data, String(data: result.data, encoding: .utf8) != nil)
    }

    /// One entry of a zip's central directory.
    struct CentralEntry {
        var name: Data
        var flags: UInt16
        var uncompressedSize: UInt64

        /// The name as UTF-8, else as Latin-1.
        var path: String {
            String(data: name, encoding: .utf8) ?? String(data: name, encoding: .isoLatin1) ?? ""
        }
    }

    /// Reads the central directory, which holds each entry's name, flags and
    /// sizes, without reading the entries themselves.
    static func centralDirectory(of archive: URL) throws -> [CentralEntry] {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // The end record sits in the last 64 KB plus its own 22 bytes.
        let tailLength = min(size, 65_557 + 20)
        try handle.seek(toOffset: size - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let end = tail.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06]))?.lowerBound else { return [] }
        var directoryOffset = UInt64(tail.littleEndian(UInt32.self, at: end + 16))
        var directorySize = UInt64(tail.littleEndian(UInt32.self, at: end + 12))
        // Zip64: the locator just before the end record points at the larger record.
        if directoryOffset == 0xFFFF_FFFF || directorySize == 0xFFFF_FFFF, end >= 20,
            tail.littleEndian(UInt32.self, at: end - 20) == 0x0706_4B50
        {
            try handle.seek(toOffset: tail.littleEndian(UInt64.self, at: end - 12))
            let record = try handle.read(upToCount: 56) ?? Data()
            guard record.count == 56, record.littleEndian(UInt32.self, at: 0) == 0x0606_4B50 else { return [] }
            directorySize = record.littleEndian(UInt64.self, at: 40)
            directoryOffset = record.littleEndian(UInt64.self, at: 48)
        }
        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()
        var entries: [CentralEntry] = []
        var offset = 0
        while offset + 46 <= directory.count, directory.littleEndian(UInt32.self, at: offset) == 0x0201_4B50 {
            let flags = directory.littleEndian(UInt16.self, at: offset + 8)
            var uncompressed = UInt64(directory.littleEndian(UInt32.self, at: offset + 24))
            let nameLength = Int(directory.littleEndian(UInt16.self, at: offset + 28))
            let extraLength = Int(directory.littleEndian(UInt16.self, at: offset + 30))
            let commentLength = Int(directory.littleEndian(UInt16.self, at: offset + 32))
            let start = directory.startIndex + offset + 46
            guard start + nameLength + extraLength <= directory.endIndex else { break }
            // A zip64 extra field (id 1) holds the real size when the field is full.
            if uncompressed == 0xFFFF_FFFF {
                var extra = offset + 46 + nameLength
                let extraEnd = extra + extraLength
                while extra + 4 <= extraEnd {
                    let id = directory.littleEndian(UInt16.self, at: extra)
                    let length = Int(directory.littleEndian(UInt16.self, at: extra + 2))
                    if id == 1, length >= 8 {
                        uncompressed = directory.littleEndian(UInt64.self, at: extra + 4)
                        break
                    }
                    extra += 4 + length
                }
            }
            entries.append(
                CentralEntry(
                    name: directory[start..<(start + nameLength)], flags: flags, uncompressedSize: uncompressed))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// True when an entry's name is neither flagged as UTF-8 nor valid
    /// UTF-8, so it is in the DOS code page. unzip's own listing turns such
    /// bytes into Latin-1 or "?".
    /// With `prefixes`, only entries under them count.
    static func namesNeedCodePage(_ archive: URL, under prefixes: [String] = []) throws -> Bool {
        let prefixData = prefixes.map { Data($0.utf8) }
        return try centralDirectory(of: archive).contains { entry in
            (prefixData.isEmpty || prefixData.contains { entry.name.starts(with: $0) })
                && entry.flags & 0x0800 == 0 && entry.name.contains(where: { $0 >= 0x80 })
                && String(data: entry.name, encoding: .utf8) == nil
        }
    }

    /// The part of a pattern before its first wildcard, with the escapes
    /// of ``literalPattern(_:)`` undone.
    static func literalPrefix(of pattern: String) -> String {
        var out = ""
        var rest = Substring(pattern)
        while let next = rest.first {
            if next == "[", rest.count >= 3, rest.dropFirst(2).first == "]" {
                out.append(rest.dropFirst().first!)
                rest = rest.dropFirst(3)
            } else if next == "*" || next == "?" || next == "[" {
                break
            } else {
                out.append(next)
                rest = rest.dropFirst()
            }
        }
        return out
    }

    /// The unpacked size of the entries whose path contains `fragment`.
    public static func unpackedSize(of archive: URL, matching fragment: String) -> Int64 {
        let entries = (try? centralDirectory(of: archive)) ?? []
        return entries.reduce(0) { total, entry in
            total + (entry.path.contains(fragment) ? Int64(clamping: entry.uncompressedSize) : 0)
        }
    }

    /// Escapes the characters unzip and bsdtar read as wildcards.
    public static func literalPattern(_ path: String) -> String {
        var out = ""
        for character in path {
            switch character {
            case "[": out += "[[]"
            case "*": out += "[*]"
            case "?": out += "[?]"
            default: out.append(character)
            }
        }
        return out
    }

    /// Extracts `archive` into `directory`, overwriting files. `only` limits
    /// it to matching entries. `onFile` gets the number of entries written so
    /// far. Cancelling the task stops the extraction.
    public static func extract(
        _ archive: URL, into directory: URL, only patterns: [String] = [], excluding excluded: [String] = [],
        onFile: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Only the entries extracted matter: one game's extras can come from
        // a large archive with a few DOS names elsewhere, and unzip reads
        // just those entries where bsdtar reads the whole archive.
        let isUTF8 = !(try namesNeedCodePage(archive, under: patterns.map(literalPrefix(of:))))
        let executable: URL
        var arguments: [String]
        if isUTF8 {
            executable = unzip
            arguments = ["-o", archive.path] + patterns + ["-d", directory.path]
            if !excluded.isEmpty { arguments += ["-x"] + excluded }
        } else {
            executable = bsdtar
            arguments = ["-x", "-v", "-f", archive.path, "--options", "hdrcharset=CP437", "-C", directory.path]
            for pattern in excluded { arguments += ["--exclude", pattern] }
            arguments += patterns
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // bsdtar converts names to the locale's character set.
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "en_US.UTF-8"]) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let state = OutputState()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let count = state.add(data) { onFile?(count) }
        }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()
        // unzip: 1 means warnings (for example odd time stamps), and 11 "no
        // matching files", which a pattern can cause on purpose.
        // bsdtar reports patterns that matched nothing the same way.
        let succeeded =
            isUTF8
            ? (status == 0 || status == 1 || (status == 11 && !patterns.isEmpty))
            : status == 0 || (!patterns.isEmpty && state.tail.contains("Not found in archive"))
        guard succeeded else {
            throw InstallError.extractionFailed(status: status, output: state.tail)
        }
    }

    /// Counts the entry lines the tools print (`inflating:` from unzip,
    /// `x <path>` from bsdtar) and keeps the last output for errors.
    private final class OutputState: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = ""
        private var count = 0
        private var lastLines: [String] = []

        func add(_ data: Data) -> Int? {
            lock.lock()
            defer { lock.unlock() }
            pending += String(decoding: data, as: UTF8.self)
            var lines = pending.components(separatedBy: "\n")
            pending = lines.removeLast()
            let before = count
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("inflating:") || trimmed.hasPrefix("extracting:") || trimmed.hasPrefix("creating:")
                    || line.hasPrefix("x ")
                {
                    count += 1
                }
                lastLines.append(line)
            }
            if lastLines.count > 20 { lastLines.removeFirst(lastLines.count - 20) }
            return count == before ? nil : count
        }

        var tail: String {
            lock.lock()
            defer { lock.unlock() }
            return (lastLines + [pending]).joined(separator: "\n")
        }
    }
}

nonisolated extension Data {
    /// A little-endian integer at `offset` from the start.
    fileprivate func littleEndian<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        var value: T = 0
        let start = startIndex + offset
        for (shift, byte) in self[start..<(start + MemoryLayout<T>.size)].enumerated() {
            value |= T(byte) << (shift * 8)
        }
        return value
    }
}
