import Foundation

/// Maps a Windows path prefix found in LaunchBox data to a folder on this
/// Mac, for example `X:\Emulation` to `/Volumes/storage/Emulation`, or the
/// relative `Games` folder to a copy on a NAS.
nonisolated public struct PathSubstitution: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var windowsPrefix: String
    public var macPath: String

    public init(id: UUID = UUID(), windowsPrefix: String, macPath: String) {
        self.id = id
        self.windowsPrefix = windowsPrefix
        self.macPath = macPath
    }

    /// The prefix as path components, compared case-insensitively.
    var prefixComponents: [String] {
        WindowsPath.components(of: windowsPrefix).map { $0.lowercased() }
    }

    /// The remaining components when `path` starts with this prefix.
    func remainder(of path: String) -> [String]? {
        let components = WindowsPath.components(of: path)
        let prefix = prefixComponents
        guard !prefix.isEmpty, components.count >= prefix.count else { return nil }
        for (offset, part) in prefix.enumerated() where components[offset].lowercased() != part {
            return nil
        }
        return Array(components.dropFirst(prefix.count))
    }
}

nonisolated public enum CollectionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A LaunchBox-format library: `Data`, `Images`, and optionally eXoDOS.
    case launchBox
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .launchBox: return "LaunchBox library"
        }
    }
}

/// One source of games shown in the sidebar, such as an eXoDOS mirror or a
/// LaunchBox install with console platforms.
nonisolated public struct LibraryCollection: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var kind: CollectionKind
    public var rootPath: String
    public var substitutions: [PathSubstitution]
    public var isEnabled: Bool
    /// The read-only eXo download that was set up into ``rootPath``, if any.
    public var downloadPath: String?

    public init(
        id: UUID = UUID(), name: String, kind: CollectionKind = .launchBox, rootPath: String,
        substitutions: [PathSubstitution] = [], isEnabled: Bool = true, downloadPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rootPath = rootPath
        self.substitutions = substitutions
        self.isEnabled = isEnabled
        self.downloadPath = downloadPath
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Library"
        kind = try c.decodeIfPresent(CollectionKind.self, forKey: .kind) ?? .launchBox
        rootPath = try c.decode(String.self, forKey: .rootPath)
        substitutions = try c.decodeIfPresent([PathSubstitution].self, forKey: .substitutions) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        downloadPath = try c.decodeIfPresent(String.self, forKey: .downloadPath)
    }

    public var rootURL: URL { URL(fileURLWithPath: rootPath, isDirectory: true) }

    public var root: LibraryRoot {
        LibraryRoot(
            url: rootURL, substitutions: substitutions,
            downloadURL: downloadPath.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    /// A sensible name for a folder: "eXoDOS" or "eXoWin9x" when the folder
    /// is named after them, else the folder name. A general LaunchBox install
    /// may contain an `eXo` folder too, so the contents are not used.
    public static func suggestedName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lowered = name.lowercased()
        if lowered.contains("exodos") { return "eXoDOS" }
        if lowered.contains("exowin9x") || lowered.contains("win9x") { return "eXoWin9x" }
        return name.isEmpty ? "Library" : name
    }
}
