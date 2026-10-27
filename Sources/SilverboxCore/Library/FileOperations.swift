import Foundation

/// Identity and publication of files managed by Silverbox. Temporary files
/// must be siblings of their destination so publication stays on one volume.
nonisolated public enum FileOperations {
    public static func identity(of url: URL) -> String {
        // Foundation may leave symlinks unresolved when a later component
        // doesn't exist yet. Resolve the existing ancestor, then append the
        // missing suffix: reservations must work before extraction creates it.
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        let resolved = suffix.reversed().reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
        return resolved.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Stable across launches (unlike Swift's Hasher). Used for storage names,
    /// not for security or archive integrity.
    public static func storageKey(for url: URL) -> String {
        storageKey(forIdentity: identity(of: url))
    }

    static func storageKey(forIdentity identity: String) -> String {
        let hash = identity.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    public static func publish(_ temporary: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
    }
}

nonisolated public struct FileOperationConflict: Error, LocalizedError, Sendable {
    public let operation: String
    public var errorDescription: String? { "These files are already in use by \(operation). Wait until it finishes." }
}

/// Reserves actual paths, including aliases and ancestor folders, rather than
/// game IDs. A session holds its reservation until the emulator exits.
nonisolated public final class FileOperationCoordinator: @unchecked Sendable {
    public static let shared = FileOperationCoordinator()
    private let lock = NSLock()
    private var entries: [UUID: (paths: [String], operation: String)] = [:]

    public init() {}

    public func acquire(_ urls: [URL], operation: String) throws -> FileOperationLease {
        let paths = urls.map(FileOperations.identity(of:))
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries.values.first(where: { entry in
            paths.contains { path in entry.paths.contains { Self.overlaps(path, $0) } }
        }) {
            throw FileOperationConflict(operation: entry.operation)
        }
        let id = UUID()
        entries[id] = (paths, operation)
        return FileOperationLease(coordinator: self, id: id)
    }

    public func conflict(for urls: [URL]) -> FileOperationConflict? {
        let paths = urls.map(FileOperations.identity(of:))
        lock.lock()
        defer { lock.unlock() }
        return entries.values.first { entry in
            paths.contains { path in entry.paths.contains { Self.overlaps(path, $0) } }
        }.map { FileOperationConflict(operation: $0.operation) }
    }

    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs.hasSuffix("/") ? rhs : rhs + "/")
            || rhs.hasPrefix(lhs.hasSuffix("/") ? lhs : lhs + "/")
    }

    fileprivate func release(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        entries[id] = nil
    }
}

nonisolated public final class FileOperationLease: Sendable {
    private let coordinator: FileOperationCoordinator
    private let id: UUID

    fileprivate init(coordinator: FileOperationCoordinator, id: UUID) {
        self.coordinator = coordinator
        self.id = id
    }

    public func release() { coordinator.release(id) }
    deinit { coordinator.release(id) }
}
