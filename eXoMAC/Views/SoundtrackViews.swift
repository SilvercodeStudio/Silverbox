import SwiftUI
import eXoCore

/// The bottom bar while a soundtrack album plays or unpacks: cover, track,
/// transport, position and volume. It replaces the menu music bar.
struct AlbumBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let player = model.album
        HStack(spacing: 12) {
            if let cover = player.album?.coverURL {
                FullImageView(url: cover, maxPixelSize: 160)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "music.note.list")
                    .frame(width: 36, height: 36)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Text(player.currentTrack?.title ?? player.errorMessage ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 160, maxWidth: 320, alignment: .leading)
            if player.isActive {
                HStack(spacing: 2) {
                    TransportButton(systemImage: "backward.fill", help: "Previous track") { player.previous() }
                    TransportButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", help: "Pause or play") {
                        player.togglePlayPause()
                    }
                    TransportButton(systemImage: "forward.fill", help: "Next track") { player.next() }
                }
                Slider(
                    value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 1)
                )
                .frame(width: 200)
                Text("\(Formatters.clock(player.position)) / \(Formatters.clock(player.duration))")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textTertiary)
                TransportButton(systemImage: "xmark", help: "Stop the album; menu music comes back") {
                    model.stopAlbum()
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Image(systemName: "speaker.wave.2")
                .foregroundStyle(Theme.textTertiary)
            Slider(value: $model.settings.musicVolume, in: 0...1)
                .frame(width: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .overlay(alignment: .top) { Divider() }
    }

    private var status: String {
        if let id = model.albumUnpackingID, let game = model.library?.game(id: id) {
            return "Unpacking \(game.title)…"
        }
        guard let album = model.album.album else { return "Album" }
        let title = model.album.game?.title ?? "Album"
        return "\(title) · track \(model.album.trackIndex + 1) of \(album.tracks.count)"
    }
}

struct TransportButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .background(Theme.panelRaised, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The album's tracks, in the inspector and on the game page. Clicking a
/// track plays the album from there.
struct AlbumTrackList: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Tracks")
            if let info = model.albumInfo(for: game) {
                Text(summary(info.album))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                ForEach(Array(info.album.tracks.enumerated()), id: \.element.id) { index, track in
                    let current = model.album.game?.id == game.id && model.album.trackIndex == index
                    Button {
                        model.playAlbum(game, startAt: index)
                    } label: {
                        HStack(spacing: 8) {
                            Text(track.number.map { String(format: "%02d", $0) } ?? "–")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 22, alignment: .trailing)
                            Image(systemName: current && model.album.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .font(.caption)
                                .foregroundStyle(current ? Theme.accent : .clear)
                                .frame(width: 14)
                            Text(track.title)
                                .lineLimit(1)
                                .foregroundStyle(current ? Theme.accent : Theme.textPrimary)
                            Spacer()
                            if let seconds = info.durations[track.id] {
                                Text(Formatters.clock(seconds))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .help("Play from this track")
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: game.id) { await model.loadAlbum(for: game) }
    }

    private func summary(_ album: SoundtrackAlbum) -> String {
        var parts = ["\(album.tracks.count) tracks"]
        if !album.formats.isEmpty { parts.append(album.formats.joined(separator: ", ")) }
        if album.isUnpacked {
            parts.append("unpacked in the local data folder")
        } else if let size = album.archiveSize {
            parts.append("\(Formatters.bytes(size)) zip, unpacked on first play")
        }
        return parts.joined(separator: " · ")
    }
}
