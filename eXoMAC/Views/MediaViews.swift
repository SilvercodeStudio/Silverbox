import AVKit
import SwiftUI

/// A full-size image loaded through the thumbnail cache.
struct FullImageView: View {
    let url: URL
    var pixelPerfect = false
    var maxPixelSize = 1600
    @Environment(AppModel.self) private var model
    @State private var image: CGImageBox?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image.image, scale: 1)
                    .interpolation(pixelPerfect ? .none : .high)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await model.thumbnails.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}

struct GameVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url) }
            .onDisappear { player?.pause(); player = nil }
    }
}

/// Shows one media item (video or image) with a filmstrip beneath it.
struct MediaGalleryView: View {
    let game: Game
    var height: CGFloat? = nil
    @Environment(AppModel.self) private var model
    @State private var items: [GameMediaItem] = []
    @State private var index = 0
    @State private var pixelPerfect = true

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Color(hex: 0x050607)
                if items.indices.contains(index) {
                    let item = items[index]
                    switch item.kind {
                    case .video:
                        GameVideoPlayer(url: item.url)
                    case .image:
                        FullImageView(url: item.url, pixelPerfect: pixelPerfect)
                            .padding(8)
                    }
                } else if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.largeTitle)
                        Text("No media").font(.caption)
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: height)
            .aspectRatio(height == nil ? 4 / 3 : nil, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                if items.indices.contains(index) {
                    Text(items[index].label)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(6)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
            }

            if items.count > 1 {
                HStack(spacing: 8) {
                    Button { index = (index - 1 + items.count) % items.count } label: { Image(systemName: "chevron.left") }
                    Button { index = (index + 1) % items.count } label: { Image(systemName: "chevron.right") }
                    Text("\(index + 1) of \(items.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Toggle("Pixel-perfect", isOn: $pixelPerfect)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                            FilmstripThumb(item: item, isSelected: offset == index)
                                .onTapGesture { index = offset }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .task(id: game.id) {
            index = 0
            guard let media = model.media else { items = []; return }
            items = await media.gallery(for: game)
        }
    }
}

struct FilmstripThumb: View {
    let item: GameMediaItem
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @State private var image: CGImageBox?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color(hex: 0x0A0B0D)
                if let image {
                    Image(decorative: image.image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else if case .video = item.kind {
                    Image(systemName: "play.fill").foregroundStyle(.white)
                }
            }
            .frame(width: 72, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Theme.accent : .clear, lineWidth: 2))
            Text(item.label)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 72)
        }
        .task(id: item.url) {
            if case .image = item.kind {
                image = await model.thumbnails.image(for: item.url, maxPixelSize: 160)
            }
        }
    }
}
