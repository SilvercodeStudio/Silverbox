import Foundation

/// A LaunchBox platform (`Data/Platforms.xml`), for example `MS-DOS`.
nonisolated public struct Platform: Identifiable, Hashable, Sendable, Codable {
    public var name: String
    public var category: String?
    public var releaseDate: Date?
    public var developer: String?
    public var manufacturer: String?
    public var notes: String?
    public var imageType: String?
    public var folder: String?
    public var sortTitle: String?

    public var id: String { name }

    public init(name: String, category: String? = nil, releaseDate: Date? = nil, developer: String? = nil,
                manufacturer: String? = nil, notes: String? = nil, imageType: String? = nil,
                folder: String? = nil, sortTitle: String? = nil) {
        self.name = name
        self.category = category
        self.releaseDate = releaseDate
        self.developer = developer
        self.manufacturer = manufacturer
        self.notes = notes
        self.imageType = imageType
        self.folder = folder
        self.sortTitle = sortTitle
    }
}

/// A LaunchBox platform category (`Data/Platforms.xml`), for example `Computers`.
nonisolated public struct PlatformCategory: Identifiable, Hashable, Sendable, Codable {
    public var name: String
    public var nestedName: String?
    public var notes: String?

    public var id: String { name }

    public init(name: String, nestedName: String? = nil, notes: String? = nil) {
        self.name = name
        self.nestedName = nestedName
        self.notes = notes
    }
}

/// Where LaunchBox keeps one media type for one platform, for example
/// `Box - Front` for `MS-DOS` lives in `Images\MS-DOS\Box - Front`.
nonisolated public struct PlatformFolder: Hashable, Sendable, Codable {
    public var platform: String
    public var mediaType: String
    public var folderPath: String

    public init(platform: String, mediaType: String, folderPath: String) {
        self.platform = platform
        self.mediaType = mediaType
        self.folderPath = folderPath
    }
}

/// A reference to a sidebar entity in `Data/Parents.xml`.
nonisolated public enum LibraryEntityRef: Hashable, Sendable, Codable {
    case category(String)
    case platform(String)
    case playlist(String)
}

/// One nesting rule from `Data/Parents.xml`: `child` appears under `parent`.
/// A missing parent means the child sits at the root of the sidebar.
nonisolated public struct ParentLink: Hashable, Sendable, Codable {
    public var child: LibraryEntityRef
    public var parent: LibraryEntityRef?

    public init(child: LibraryEntityRef, parent: LibraryEntityRef?) {
        self.child = child
        self.parent = parent
    }
}
