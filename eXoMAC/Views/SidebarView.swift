import SwiftUI
import eXoCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                Label("All Games", systemImage: "square.grid.3x3").tag(LibraryScope.all)
                Label("Favorites", systemImage: "heart").tag(LibraryScope.favorites)
                if model.library?.hasEXoFavorites == true {
                    Label("eXo Favorites", systemImage: "star").tag(LibraryScope.eXoFavorites)
                }
                Label("Installed", systemImage: "internaldrive").tag(LibraryScope.installed)
                Label("Recently Played", systemImage: "clock").tag(LibraryScope.recentlyPlayed)
            }
            // With more than one eXo pack loaded, each can be shown on its
            // own, even when several share a collection.
            if let packs = model.library?.packs, packs.count > 1 {
                Section("eXo Packs") {
                    ForEach(packs, id: \.self) { pack in
                        Label(pack.displayName, systemImage: pack.systemImage).tag(LibraryScope.pack(pack))
                    }
                }
            }
            ForEach(model.library?.snapshots ?? [], id: \.collection.id) { snapshot in
                Section(snapshot.collection.name) {
                    OutlineGroup(snapshot.tree, children: \.outlineChildren) { node in
                        Label(node.title, systemImage: node.systemImage)
                            .tag(LibraryScope.node(collectionID: snapshot.collection.id, ref: node.ref))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
    }

    private var selection: Binding<LibraryScope?> {
        Binding(
            get: { model.scope },
            set: { newValue in
                guard let newValue else { return }
                model.scope = newValue
                model.openedGameID = nil
            }
        )
    }
}

extension EXoPack {
    var systemImage: String {
        switch self {
        case .dos: return "pc"
        case .win9x: return "macwindow"
        case .demoScene: return "sparkles.tv"
        case .scummVM: return "cursorarrow.click.2"
        case .appleIIGS: return "desktopcomputer"
        case .interactiveFiction: return "text.book.closed"
        }
    }
}
