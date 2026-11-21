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

nonisolated extension LibraryNode {
    /// A playlist's title without the words that the sidebar already says
    /// above it. A pack's name goes wherever it is a word of the title:
    /// "eXoDOS Games with MT-32" is "MT-32", and "Installed eXoDemoScene
    /// Demos" is "Installed Demos". The title of a row above (or the
    /// collection's name) goes only from the start: under Arcade, "Arcade
    /// Fighting Games" is "Fighting Games". Platforms and categories keep
    /// their titles, and so does a playlist that would have no words left.
    public func sidebarTitle(under ancestors: [String], packs: [String]) -> String {
        guard case .playlist = ref else { return title }
        var words = title.split(separator: " ").map(String.init)
        func matches(_ name: [String], at index: Int) -> Bool {
            index + name.count <= words.count
                && zip(name, words[index...]).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
        }
        // The longest name first, so that "eXoDOS" does not hide "eXoDOS Lite".
        let longestFirst: ([String]) -> [[String]] = { names in
            names.map { $0.split(separator: " ").map(String.init) }.filter { !$0.isEmpty }
                .sorted { $0.joined().count > $1.joined().count }
        }
        var shortened = false
        if let pack = longestFirst(packs).first(where: { name in words.indices.contains { matches(name, at: $0) } }),
            let index = words.indices.first(where: { matches(pack, at: $0) }), words.count > pack.count
        {
            words.removeSubrange(index..<index + pack.count)
            shortened = true
        } else if let ancestor = longestFirst(ancestors).first(where: { matches($0, at: 0) }),
            words.count > ancestor.count
        {
            words.removeFirst(ancestor.count)
            shortened = true
        }
        guard shortened else { return title }
        if words.count > 2, matches(["Games", "with"], at: 0) { words.removeFirst(2) }
        return words.joined(separator: " ")
    }

    /// ``sidebarTitle(under:packs:)`` for every node of a tree whose title it shortens.
    public static func sidebarTitles(in tree: [LibraryNode], under ancestors: [String] = [], packs: [String])
        -> [LibraryEntityRef: String]
    {
        var titles: [LibraryEntityRef: String] = [:]
        for node in tree {
            let short = node.sidebarTitle(under: ancestors, packs: packs)
            if short != node.title { titles[node.ref] = short }
            titles.merge(sidebarTitles(in: node.children, under: ancestors + [node.title], packs: packs)) {
                first, _ in first
            }
        }
        return titles
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
