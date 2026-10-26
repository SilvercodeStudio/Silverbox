import AVKit
import SwiftUI
import SilverboxCore

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
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

/// Shows one media item (video or image) with a filmstrip beneath it. The
/// items and the current index live in the model, so the keyboard and a
/// controller can page through them too.
struct MediaGalleryView: View {
    let game: Game
    var height: CGFloat? = nil
    @Environment(AppModel.self) private var model
    @State private var pixelPerfect = true

    var body: some View {
        @Bindable var model = model
        let items = model.galleryItems
        let index = model.galleryIndex
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
            .onTapGesture { model.quickLookCurrentMedia() }

            if items.count > 1 {
                HStack(spacing: 8) {
                    Button {
                        model.showPreviousMedia()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Previous image (Option-Left)")
                    Button {
                        model.showNextMedia()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .help("Next image (Option-Right)")
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
                                .onTapGesture { model.galleryIndex = offset }
                        }
                    }
                    .padding(2)
                }
            }
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
