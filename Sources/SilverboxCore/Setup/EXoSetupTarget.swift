import Foundation

/// Distinguishes downloads with identical folder names, including unfinished
/// setups. Existing setups are reused only when their source matches.
nonisolated public enum EXoSetupTarget {
    private static func sourceURL(in target: URL) -> URL {
        target.appendingPathComponent("Data/Silverbox Setup Source.json")
    }

    public static func belongs(to download: URL, target: URL) -> Bool {
        if FileOperations.identity(of: download) == FileOperations.identity(of: target) { return true }
        if let record = EXoSetupRecord.read(in: target), let path = record.downloadPath,
            FileOperations.identity(of: URL(fileURLWithPath: path)) == FileOperations.identity(of: download)
        {
            return true
        }
        guard let data = try? Data(contentsOf: sourceURL(in: target)),
            let path = try? JSONDecoder().decode(String.self, from: data)
        else { return false }
        return FileOperations.identity(of: URL(fileURLWithPath: path)) == FileOperations.identity(of: download)
    }

    public static func localTarget(for download: URL, in store: LocalStore) -> URL {
        let collections = store.directory.appendingPathComponent("Collections", isDirectory: true)
        let name = download.lastPathComponent
        let legacy = collections.appendingPathComponent(name, isDirectory: true)
        if belongs(to: download, target: legacy) { return legacy }
        let stem = name + "-" + FileOperations.storageKey(for: download)
        var suffix = 0
        while true {
            let target = collections.appendingPathComponent(stem + (suffix == 0 ? "" : "-\(suffix)"), isDirectory: true)
            if !FileManager.default.fileExists(atPath: target.path) || belongs(to: download, target: target) {
                return target
            }
            suffix += 1
        }
    }

    /// Called under the setup's path reservation, before extracting anything.
    static func claim(_ target: URL, for download: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path), !belongs(to: download, target: target),
            !(try fm.contentsOfDirectory(atPath: target.path)).isEmpty
        {
            throw EXoSetupTargetError.occupied(target)
        }
        let source = sourceURL(in: target)
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(download.path).write(to: source, options: .atomic)
    }
}

nonisolated public enum EXoSetupTargetError: Error, LocalizedError, Sendable {
    case occupied(URL)
    public var errorDescription: String? {
        switch self {
        case .occupied(let target):
            return "\(target.path) already contains files from another source. Choose a different setup folder."
        }
    }
}
