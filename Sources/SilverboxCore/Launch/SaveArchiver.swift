import Foundation

/// A zip entry's size and checksum, from `unzip -v`.
nonisolated public struct ArchiveEntry: Hashable, Sendable {
    public var size: Int
    public var crc: UInt32
}

/// Backs up the files a player changed in a game folder, the way eXoDOS's
/// uninstaller does with `zip --dif`: only files that are new or differ from
/// the original archive are kept, so a save backup stays small.
nonisolated public enum SaveArchiver {
    public static let unzipExecutable = URL(fileURLWithPath: "/usr/bin/unzip")
    public static let zipExecutable = URL(fileURLWithPath: "/usr/bin/zip")

    /// Lists an archive's file entries keyed by lower-cased path.
    public static func entries(of archive: URL) async throws -> [String: ArchiveEntry] {
        let result = try await CommandRunner.run(executable: unzipExecutable, arguments: ["-v", archive.path])
        guard result.status == 0 || result.status == 1 else {
            throw InstallError.extractionFailed(status: result.status, output: result.output)
        }
        var entries: [String: ArchiveEntry] = [:]
        for line in result.output.components(separatedBy: "\n") {
            guard let match = line.wholeMatch(of: Self.verbosePattern) else { continue }
            let name = String(match.name)
            guard !name.hasSuffix("/") else { continue }
            entries[name.lowercased()] = ArchiveEntry(
                size: Int(match.size) ?? 0, crc: UInt32(match.crc, radix: 16) ?? 0)
        }
        return entries
    }

    nonisolated(unsafe) private static let verbosePattern =
        #/^\s*(?<size>\d+)\s+\S+\s+\d+\s+\S+\s+\S+\s+\S+\s+(?<crc>[0-9a-fA-F]{8})\s+(?<name>.+?)\s*$/#

    /// Paths (relative to the folder's parent, like archive entries) of files
    /// in `folder` that are new or differ from `archive`.
    public static func changedFiles(in folder: URL, comparedTo archive: URL) async throws -> [String] {
        let original = try await entries(of: archive)
        return try localFiles(in: folder).compactMap { file -> String? in
            guard let entry = original[file.relativePath.lowercased()] else { return file.relativePath }
            if try file.size != entry.size || CRC32.readChecksum(ofFileAt: file.url) != entry.crc {
                return file.relativePath
            }
            return nil
        }
        .sorted()
    }

    nonisolated struct LocalFile: Sendable {
        var url: URL
        var relativePath: String
        var size: Int
    }

    /// Every regular file under `folder`, with paths prefixed by the folder name.
    static func localFiles(in folder: URL) throws -> [LocalFile] {
        let fm = FileManager.default
        let basePath = folder.standardizedFileURL.path
        let prefix = folder.lastPathComponent
        var files: [LocalFile] = []
        func visit(_ directory: URL) throws {
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                ])
                // Following links could back up files outside the installation,
                // and ignoring them would silently lose them on uninstall.
                guard values.isSymbolicLink != true else { throw SaveBackupError.unsupportedFile(url) }
                if values.isDirectory == true {
                    try visit(url)
                } else if values.isRegularFile == true {
                    let path = url.standardizedFileURL.path
                    guard path.hasPrefix(basePath + "/"), let size = values.fileSize else {
                        throw SaveBackupError.unsupportedFile(url)
                    }
                    let relative = prefix + "/" + path.dropFirst(basePath.count + 1)
                    guard !relative.contains("\n"), !relative.contains("\r") else {
                        throw SaveBackupError.unsupportedFile(url)
                    }
                    files.append(LocalFile(url: url, relativePath: relative, size: size))
                } else {
                    throw SaveBackupError.unsupportedFile(url)
                }
            }
        }
        try visit(folder)
        return files
    }

    /// Writes the changed files to `saveArchive`. Returns how many were saved;
    /// no archive is written when nothing changed.
    @discardableResult
    public static func backup(folder: URL, originalArchive: URL, to saveArchive: URL) async throws -> Int {
        let changed = try await changedFiles(in: folder, comparedTo: originalArchive)
        guard !changed.isEmpty else { return 0 }
        let fm = FileManager.default
        try fm.createDirectory(at: saveArchive.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = saveArchive.deletingLastPathComponent().appendingPathComponent(
            ".silverbox-backup-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: temporary) }
        let listURL = fm.temporaryDirectory.appendingPathComponent("exo-save-\(UUID().uuidString).txt")
        try changed.joined(separator: "\n").write(to: listURL, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: listURL) }
        let result = try await CommandRunner.run(
            executable: zipExecutable, arguments: ["-q", "-@", temporary.path],
            workingDirectory: folder.deletingLastPathComponent(), standardInput: listURL)
        guard result.status == 0 else {
            throw InstallError.extractionFailed(status: result.status, output: result.output)
        }
        try Task.checkCancellation()
        let check = try await CommandRunner.run(executable: unzipExecutable, arguments: ["-tqq", temporary.path])
        guard check.status == 0 else {
            throw InstallError.extractionFailed(status: check.status, output: check.output)
        }
        try Task.checkCancellation()
        try FileOperations.publish(temporary, to: saveArchive)
        return changed.count
    }
}

/// CRC-32 as used by zip, computed in chunks so large disc images do not
/// need to be loaded whole.
nonisolated public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    public static func checksum(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        update(&crc, with: data)
        return crc ^ 0xFFFF_FFFF
    }

    public static func checksum(ofFileAt url: URL) -> UInt32? {
        try? readChecksum(ofFileAt: url)
    }

    static func readChecksum(ofFileAt url: URL) throws -> UInt32 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            update(&crc, with: chunk)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func update(_ crc: inout UInt32, with data: Data) {
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
}

nonisolated public enum SaveBackupError: Error, LocalizedError, Sendable {
    case unsupportedFile(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let url): return "Cannot safely back up \(url.path). The game has not been removed."
        }
    }
}
