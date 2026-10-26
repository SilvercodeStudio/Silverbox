import Foundation

/// A node of the sidebar tree: a platform category, a platform, or a playlist.
nonisolated public struct LibraryNode: Identifiable, Hashable, Sendable {
    public var ref: LibraryEntityRef
    public var title: String
    public var children: [LibraryNode]

    public var id: LibraryEntityRef { ref }

    public init(ref: LibraryEntityRef, title: String, children: [LibraryNode] = []) {
        self.ref = ref
        self.title = title
        self.children = children
    }

    /// Every platform name reachable from this node, including its own.
    public var platformNames: [String] {
        var names: [String] = []
        collectPlatforms(into: &names)
        return names
    }

    private func collectPlatforms(into names: inout [String]) {
        if case .platform(let name) = ref { names.append(name) }
        for child in children { child.collectPlatforms(into: &names) }
    }
}

/// Builds the sidebar tree from LaunchBox's flat parent/child rules.
nonisolated public enum LibraryTreeBuilder {
    public static func build(
        categories: [PlatformCategory], platforms: [Platform],
        playlists: [Playlist], parents: [ParentLink]
    ) -> [LibraryNode] {
        var titles: [LibraryEntityRef: String] = [:]
        for category in categories { titles[.category(category.name)] = category.name }
        for platform in platforms { titles[.platform(platform.name)] = platform.name }
        for playlist in playlists { titles[.playlist(playlist.id)] = playlist.name }

        // Keep only rules whose child exists; a missing parent means "root".
        var parentOf: [LibraryEntityRef: LibraryEntityRef?] = [:]
        for link in parents where titles[link.child] != nil {
            if let parent = link.parent, titles[parent] == nil { continue }
            parentOf[link.child] = link.parent
        }

        var childrenOf: [LibraryEntityRef: [LibraryEntityRef]] = [:]
        var roots: [LibraryEntityRef] = []
        for ref in titles.keys {
            // Guard against cycles: a child whose ancestry loops is shown at the root.
            var parent = parentOf[ref] ?? nil
            var seen: Set<LibraryEntityRef> = [ref]
            var cyclic = false
            var cursor = parent
            while let current = cursor {
                if seen.contains(current) {
                    cyclic = true
                    break
                }
                seen.insert(current)
                cursor = parentOf[current] ?? nil
            }
            if cyclic { parent = nil }
            if let parent {
                childrenOf[parent, default: []].append(ref)
            } else {
                roots.append(ref)
            }
        }

        func node(for ref: LibraryEntityRef) -> LibraryNode {
            let kids = (childrenOf[ref] ?? []).map(node(for:)).sorted(by: Self.order)
            return LibraryNode(ref: ref, title: titles[ref] ?? "", children: kids)
        }
        return roots.map(node(for:)).sorted(by: Self.order)
    }

    private static func order(_ a: LibraryNode, _ b: LibraryNode) -> Bool {
        let result = a.title.localizedCaseInsensitiveCompare(b.title)
        if result == .orderedSame { return a.ref.sortRank < b.ref.sortRank }
        return result == .orderedAscending
    }
}

nonisolated extension LibraryEntityRef {
    /// A stable string form, useful for persistence and SwiftUI identity.
    public var key: String {
        switch self {
        case .category(let name): return "category:\(name)"
        case .platform(let name): return "platform:\(name)"
        case .playlist(let id): return "playlist:\(id)"
        }
    }

    fileprivate var sortRank: Int {
        switch self {
        case .category: return 0
        case .platform: return 1
        case .playlist: return 2
        }
    }
}
