import AppKit
import SwiftUI
import SilverboxCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = model.sidebarCounts
        List(selection: selection) {
            Section("Library") {
                row("All Games", "square.grid.3x3", .all, counts)
                row("Favorites", "heart", .favorites, counts)
                if model.library?.hasEXoFavorites == true {
                    row("eXo Favorites", "star", .eXoFavorites, counts)
                }
                row("Installed", "internaldrive", .installed, counts)
                row("Recently Played", "clock", .recentlyPlayed, counts)
            }
            // With more than one eXo pack loaded, each can be shown on its
            // own, even when several share a collection.
            if let packs = model.library?.packs, packs.count > 1 {
                Section("eXo Packs") {
                    ForEach(packs, id: \.self) { pack in
                        row(pack.displayName, pack.systemImage, .pack(pack), counts)
                    }
                }
            }
            ForEach(model.library?.snapshots ?? [], id: \.collection.id) { snapshot in
                Section {
                    OutlineGroup(snapshot.tree, children: \.outlineChildren) { node in
                        Label(node.title, systemImage: node.systemImage)
                            .badge(counts.nodes[snapshot.collection.id]?[node.ref] ?? 0)
                            .tag(LibraryScope.node(collectionID: snapshot.collection.id, ref: node.ref))
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.collection.name)
                        if let subtitle = counts.collections[snapshot.collection.id] {
                            Text(subtitle).font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Sidebar icons take the app's accent from the asset catalog otherwise.
        .listItemTint(Theme.accent)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DataFolderFooter()
        }
    }

    /// A library row with its game count; a badge of 0 is not shown.
    private func row(_ title: String, _ systemImage: String, _ scope: LibraryScope, _ counts: AppModel.SidebarCounts)
        -> some View
    {
        Label(title, systemImage: systemImage)
            .badge(counts.scopes[scope] ?? 0)
            .tag(scope)
    }

    private var selection: Binding<LibraryScope?> {
        Binding(
            get: { model.scope },
            set: { newValue in
                // A same-value write would still re-sort the visible games.
                guard let newValue, newValue != model.scope else { return }
                model.scope = newValue
                model.openedGameID = nil
            }
        )
    }
}

/// The local data folder, where installed games and caches go; a click
/// shows it in the Finder.
private struct DataFolderFooter: View {
    var body: some View {
        let folder = AppPaths.dataRoot
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } label: {
            Label(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("The local data folder: installed games, saves, caches and logs. Click to show it in the Finder.")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.sidebar)
    }
}

extension EXoPack {
    var systemImage: String {
        switch self {
        case .dos: return "pc"
        case .win3x: return "macwindow.on.rectangle"
        case .win9x: return "macwindow"
        case .demoScene: return "sparkles.tv"
        case .scummVM: return "cursorarrow.click.2"
        case .appleIIGS: return "desktopcomputer"
        case .interactiveFiction: return "text.book.closed"
        }
    }
}
