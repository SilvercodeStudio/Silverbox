import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                Label("All Games", systemImage: "square.grid.3x3").tag(LibraryScope.all)
                Label("Favorites", systemImage: "heart").tag(LibraryScope.favorites)
                Label("Installed", systemImage: "internaldrive").tag(LibraryScope.installed)
                Label("Recently Played", systemImage: "clock").tag(LibraryScope.recentlyPlayed)
            }
            if let tree = model.library?.tree, !tree.isEmpty {
                Section("Platforms") {
                    OutlineGroup(tree, children: \.outlineChildren) { node in
                        Label(node.title, systemImage: node.systemImage)
                            .tag(LibraryScope.node(node.ref))
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
