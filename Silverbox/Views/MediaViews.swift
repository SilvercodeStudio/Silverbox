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
    @Environment(AppModel.self) private var model
    @State private var player: AVPlayer?

    /// False while the Finder ejects the video's volume, so the file is let go.
    private var mayOpen: Bool {
        model.releasingVolume.map { !AppModel.isOnVolume(url, $0) } ?? true
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { if mayOpen { player = AVPlayer(url: url) } }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .onChange(of: mayOpen) { _, open in
                player?.pause()
                player = open ? AVPlayer(url: url) : nil
            }
    }
}

/// Shows one media item (video or image) with a filmstrip beneath it. The
/// items and the current index live in the model, so the keyboard and a
/// controller can page through them too.
struct MediaGalleryView: View {
    let game: Game
    var height: CGFloat? = nil
    /// A black frame behind the image, which fills the inspector's fixed
    /// 4:3 box. The game page leaves it out, so an image of another shape
    /// has no black bars beside it.
    var framed = true
    @Environment(AppModel.self) private var model
    @State private var pixelPerfect = true
    @State private var filmstripOverflow = FilmstripOverflow()

    var body: some View {
        @Bindable var model = model
        let items = model.galleryItems
        let index = model.galleryIndex
        VStack(spacing: 10) {
            ZStack {
                if framed || items.isEmpty { Color(hex: 0x050607) }
                if items.indices.contains(index) {
                    let item = items[index]
                    switch item.kind {
                    case .video:
                        GameVideoPlayer(url: item.url)
                    case .image:
                        FullImageView(url: item.url, pixelPerfect: pixelPerfect)
                            .padding(framed ? 8 : 0)
                    }
                } else if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.largeTitle)
                        Text("No media").font(.caption)
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
            }
            .modifier(GalleryFrame(height: height))
            .clipShape(RoundedRectangle(cornerRadius: framed ? 8 : 0))
            .contentShape(Rectangle())
            // The filmstrip names the image; one image alone has no filmstrip.
            .help(items.indices.contains(index) ? items[index].label : "")
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

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                                FilmstripThumb(item: item, isSelected: offset == index)
                                    .id(offset)
                                    .onTapGesture { model.galleryIndex = offset }
                            }
                        }
                        .padding(2)
                    }
                    .onScrollGeometryChange(for: FilmstripOverflow.self) { geometry in
                        FilmstripOverflow(
                            leading: geometry.contentOffset.x > 1,
                            trailing: geometry.contentOffset.x + geometry.containerSize.width
                                < geometry.contentSize.width - 1)
                    } action: { _, overflow in
                        filmstripOverflow = overflow
                    }
                    // A fade at an edge says that the strip goes on there.
                    .mask {
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [filmstripOverflow.leading ? .clear : .black, .black], startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 28)
                            Color.black
                            LinearGradient(
                                colors: [.black, filmstripOverflow.trailing ? .clear : .black], startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 28)
                        }
                    }
                    // The arrows and the keyboard keep the current image's thumbnail in view.
                    .onChange(of: index) { _, index in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index) }
                    }
                }
            }
        }
    }
}

/// The gallery's box: all the width at a given height, or a 4:3 box. Not
/// `aspectRatio(nil, …)`, which keeps the shape of what is inside, so that a
/// title screen sat in a frame cut for box art.
private struct GalleryFrame: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(maxWidth: .infinity).frame(height: height)
        } else {
            content.aspectRatio(4 / 3, contentMode: .fit)
        }
    }
}

/// Whether the filmstrip has thumbnails out of view at each end.
private struct FilmstripOverflow: Equatable {
    var leading = false
    var trailing = false
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
