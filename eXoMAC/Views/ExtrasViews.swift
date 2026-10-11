import QuickLook
import SwiftUI

/// The manual and the documents in a game's Extras folder.
struct ExtrasList: View {
    let game: Game
    var limit: Int? = nil
    @Environment(AppModel.self) private var model
    @State private var extras: [GameExtra] = []
    @State private var manual: URL?
    @State private var showAll = false
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let manual {
                ExtraRow(name: "Manual", kind: .pdf, url: manual, previewURL: $previewURL)
            }
            let inBox = extras.filter { !$0.isGuideBook }
            let guides = extras.filter(\.isGuideBook)
            let visibleInBox = limited(inBox)
            let visibleGuides = limited(guides, after: inBox.count)
            if !visibleInBox.isEmpty {
                ExtrasGroup(title: "In the box", extras: visibleInBox, previewURL: $previewURL)
            }
            if !visibleGuides.isEmpty {
                ExtrasGroup(title: "Guide books", extras: visibleGuides, previewURL: $previewURL)
            }
            if extras.isEmpty, manual == nil {
                Text("No extras for this game.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            if let limit, !showAll, extras.count > limit {
                Button("Show all \(extras.count) extras") { showAll = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .quickLookPreview($previewURL)
        .task(id: game.id) {
            showAll = false
            guard let media = model.media else { return }
            extras = await media.extras(for: game)
            manual = await media.manual(for: game)
        }
    }

    private func limited(_ list: [GameExtra], after offset: Int = 0) -> [GameExtra] {
        guard let limit, !showAll else { return list }
        let remaining = max(0, limit - offset)
        return Array(list.prefix(remaining))
    }
}

struct ExtrasGroup: View {
    let title: String
    let extras: [GameExtra]
    @Binding var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            ForEach(extras) { extra in
                ExtraRow(name: extra.name, kind: extra.kind, url: extra.url, previewURL: $previewURL)
            }
        }
    }
}

struct ExtraRow: View {
    let name: String
    let kind: GameExtra.Kind
    let url: URL
    @Binding var previewURL: URL?
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            previewURL = url
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16)
                Text(name)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .contextMenu {
            Button("Quick Look") { previewURL = url }
            Button("Open") { model.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        .help(url.lastPathComponent)
    }

    private var icon: String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .image: return "map"
        case .text: return "doc.text"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }
}
