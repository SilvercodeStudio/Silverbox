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

    /// True when an entry's name is neither flagged as UTF-8 nor valid
    /// UTF-8, so it is in the DOS code page. Reads the central directory,
    /// which holds each name's bytes and flags; unzip's own listing turns
    /// such bytes into Latin-1 or "?".
    static func namesNeedCodePage(_ archive: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // The end record sits in the last 64 KB plus its own 22 bytes.
        let tailLength = min(size, 65_557 + 20)
        try handle.seek(toOffset: size - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let end = tail.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06]))?.lowerBound else { return false }
        var directoryOffset = UInt64(tail.littleEndian(UInt32.self, at: end + 16))
        var directorySize = UInt64(tail.littleEndian(UInt32.self, at: end + 12))
        // Zip64: the locator just before the end record points at the larger record.
        if directoryOffset == 0xFFFF_FFFF || directorySize == 0xFFFF_FFFF, end >= 20,
            tail.littleEndian(UInt32.self, at: end - 20) == 0x0706_4B50
        {
            try handle.seek(toOffset: tail.littleEndian(UInt64.self, at: end - 12))
            let record = try handle.read(upToCount: 56) ?? Data()
            guard record.count == 56, record.littleEndian(UInt32.self, at: 0) == 0x0606_4B50 else { return false }
            directorySize = record.littleEndian(UInt64.self, at: 40)
            directoryOffset = record.littleEndian(UInt64.self, at: 48)
        }
        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()
        var offset = 0
        while offset + 46 <= directory.count, directory.littleEndian(UInt32.self, at: offset) == 0x0201_4B50 {
            let flags = directory.littleEndian(UInt16.self, at: offset + 8)
            let nameLength = Int(directory.littleEndian(UInt16.self, at: offset + 28))
            let extraLength = Int(directory.littleEndian(UInt16.self, at: offset + 30))
            let commentLength = Int(directory.littleEndian(UInt16.self, at: offset + 32))
            let start = directory.startIndex + offset + 46
            guard start + nameLength <= directory.endIndex else { break }
            let name = directory[start..<(start + nameLength)]
            if flags & 0x0800 == 0, name.contains(where: { $0 >= 0x80 }), String(data: name, encoding: .utf8) == nil {
                return true
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return false
    }

    /// Extracts `archive` into `directory`, overwriting files. `only` limits
    /// it to matching entries. `onFile` gets the number of entries written so
    /// far. Cancelling the task stops the extraction.
    public static func extract(
        _ archive: URL, into directory: URL, only patterns: [String] = [], excluding excluded: [String] = [],
        onFile: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let isUTF8 = !(try namesNeedCodePage(archive))
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
        let succeeded =
            isUTF8 ? (status == 0 || status == 1 || (status == 11 && !patterns.isEmpty)) : status == 0
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
