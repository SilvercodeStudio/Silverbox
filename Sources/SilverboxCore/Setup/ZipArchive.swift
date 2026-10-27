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
        let signature = Data([0x50, 0x4B, 0x05, 0x06])
        var end: Int?
        if tail.count >= 22 {
            for offset in stride(from: tail.count - 22, through: 0, by: -1) {
                if tail[offset..<(offset + 4)] == signature,
                    offset + 22 + Int(try tail.littleEndian(UInt16.self, at: offset + 20)) == tail.count
                {
                    end = offset
                    break
                }
            }
        }
        guard let end else { throw ZipArchiveError.malformed }
        // Multi-volume archives cannot be extracted as one local ZIP.
        guard try tail.littleEndian(UInt16.self, at: end + 4) == 0,
            try tail.littleEndian(UInt16.self, at: end + 6) == 0
        else { throw ZipArchiveError.malformed }
        var directoryOffset = UInt64(try tail.littleEndian(UInt32.self, at: end + 16))
        var directorySize = UInt64(try tail.littleEndian(UInt32.self, at: end + 12))
        var entryCount = UInt64(try tail.littleEndian(UInt16.self, at: end + 10))
        if directoryOffset == 0xFFFF_FFFF || directorySize == 0xFFFF_FFFF || entryCount == 0xFFFF {
            guard end >= 20, try tail.littleEndian(UInt32.self, at: end - 20) == 0x0706_4B50 else {
                throw ZipArchiveError.malformed
            }
            let recordOffset = try tail.littleEndian(UInt64.self, at: end - 12)
            guard recordOffset <= size, size - recordOffset >= 56 else { throw ZipArchiveError.malformed }
            try handle.seek(toOffset: recordOffset)
            let record = try handle.read(upToCount: 56) ?? Data()
            guard record.count == 56, try record.littleEndian(UInt32.self, at: 0) == 0x0606_4B50,
                try record.littleEndian(UInt32.self, at: 16) == 0,
                try record.littleEndian(UInt32.self, at: 20) == 0
            else { throw ZipArchiveError.malformed }
            directorySize = try record.littleEndian(UInt64.self, at: 40)
            directoryOffset = try record.littleEndian(UInt64.self, at: 48)
            entryCount = try record.littleEndian(UInt64.self, at: 32)
        }
        guard directoryOffset <= size, directorySize <= size - directoryOffset,
            let count = Int(exactly: directorySize), entryCount <= directorySize / 46
        else {
            throw ZipArchiveError.malformed
        }
        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: count) ?? Data()
        guard directory.count == count else { throw ZipArchiveError.malformed }
        var entries: [CentralEntry] = []
        var offset = 0
        while entries.count < entryCount {
            guard offset <= directory.count, directory.count - offset >= 46,
                try directory.littleEndian(UInt32.self, at: offset) == 0x0201_4B50
            else {
                throw ZipArchiveError.malformed
            }
            let flags = try directory.littleEndian(UInt16.self, at: offset + 8)
            var uncompressed = UInt64(try directory.littleEndian(UInt32.self, at: offset + 24))
            let nameLength = Int(try directory.littleEndian(UInt16.self, at: offset + 28))
            let extraLength = Int(try directory.littleEndian(UInt16.self, at: offset + 30))
            let commentLength = Int(try directory.littleEndian(UInt16.self, at: offset + 32))
            let start = offset + 46
            let length = nameLength + extraLength + commentLength
            guard length <= directory.count - start else { throw ZipArchiveError.malformed }
            if uncompressed == 0xFFFF_FFFF {
                var extra = start + nameLength
                let extraEnd = extra + extraLength
                var found = false
                while extra < extraEnd {
                    guard extraEnd - extra >= 4 else { throw ZipArchiveError.malformed }
                    let id = try directory.littleEndian(UInt16.self, at: extra)
                    let length = Int(try directory.littleEndian(UInt16.self, at: extra + 2))
                    guard length <= extraEnd - extra - 4 else { throw ZipArchiveError.malformed }
                    if id == 1 {
                        guard length >= 8 else { throw ZipArchiveError.malformed }
                        uncompressed = try directory.littleEndian(UInt64.self, at: extra + 4)
                        found = true
                        break
                    }
                    extra += 4 + length
                }
                guard found else { throw ZipArchiveError.malformed }
            }
            entries.append(
                CentralEntry(
                    name: directory[start..<(start + nameLength)], flags: flags,
                    uncompressedSize: uncompressed))
            offset = start + length
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
            guard entry.path.contains(fragment) else { return total }
            let (sum, overflow) = total.addingReportingOverflow(Int64(clamping: entry.uncompressedSize))
            return overflow ? Int64.max : sum
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

        let result = try await runExtractor(executable: executable, arguments: arguments, onFile: onFile)
        let status = result.status
        // unzip: 1 means warnings (for example odd time stamps), and 11 "no
        // matching files", which a pattern can cause on purpose.
        // bsdtar reports patterns that matched nothing the same way.
        let succeeded =
            isUTF8
            ? (status == 0 || status == 1 || (status == 11 && !patterns.isEmpty))
            : status == 0 || (!patterns.isEmpty && result.output.contains("Not found in archive"))
        guard succeeded else {
            throw InstallError.extractionFailed(status: status, output: result.output)
        }
    }

    /// Runs the selected extractor. Kept separate from archive inspection so
    /// startup failures can be exercised without replacing a system tool.
    static func runExtractor(
        executable: URL, arguments: [String], onFile: (@Sendable (Int) -> Void)? = nil
    ) async throws -> (status: Int32, output: String) {
        try Task.checkCancellation()
        let lifecycle = CancellableProcess()
        let process = lifecycle.process
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
                process.terminationHandler = { [weak lifecycle] finished in
                    lifecycle?.finished()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    _ = state.add(pipe.fileHandleForReading.readDataToEndOfFile())
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try lifecycle.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    // No child owns the pipe: its parent-side writer is still
                    // open, so draining to EOF here would wait indefinitely.
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            lifecycle.cancel()
        }
        try Task.checkCancellation()
        return (status, state.tail)
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
    fileprivate func littleEndian<T: FixedWidthInteger>(_: T.Type, at offset: Int) throws -> T {
        guard offset >= 0, offset <= count, MemoryLayout<T>.size <= count - offset else {
            throw ZipArchiveError.malformed
        }
        var value: T = 0
        let start = startIndex + offset
        for (shift, byte) in self[start..<(start + MemoryLayout<T>.size)].enumerated() {
            value |= T(byte) << (shift * 8)
        }
        return value
    }
}

nonisolated public enum ZipArchiveError: Error, LocalizedError, Sendable {
    case malformed
    public var errorDescription: String? { "The ZIP archive is damaged or has an unsupported layout." }
}
