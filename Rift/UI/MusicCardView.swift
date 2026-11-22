// SPDX-License-Identifier: GPL-3.0-only
//
// MusicCardView — one tile in a home carousel, with hover lift + play affordance.
// Songs play on tap; albums / playlists / artists push a detail page.

import SwiftUI

extension MusicCard {
    var asTrack: PlayableTrack {
        PlayableTrack(id: id, title: title, artist: subtitle, artworkURL: artworkURL, duration: nil)
    }
}

struct MusicCardView: View {
    @EnvironmentObject var player: PlayerController
    let card: MusicCard
    @State private var hover = false
    @ObservedObject private var covers = CoverStore.shared

    var body: some View {
        Group {
            if card.kind == .song {
                Button { player.play(card.asTrack) } label: { tile }.buttonStyle(.plain)
                    .contextMenu {
                        Button { player.play(card.asTrack) } label: { Label("Play", systemImage: "play.fill") }
                        Button { player.playNext(card.asTrack) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { player.addToQueue(card.asTrack) } label: { Label("Add to Queue", systemImage: "text.append") }
                        Divider()
                        Button { LikeStore.shared.toggle(card.asTrack) } label: {
                            LikeStore.shared.isLiked(card.id)
                                ? Label("Remove from Liked", systemImage: "heart.slash")
                                : Label("Like", systemImage: "heart")
                        }
                        AddToPlaylistMenu(track: card.asTrack)
                        Button { Downloader.download(card.asTrack) } label: { Label("Download", systemImage: "arrow.down.circle") }
                    }
            } else {
                NavigationLink(value: card) { tile }.buttonStyle(.plain)
                    .contextMenu {
                        if card.kind == .playlist {
                            Button { CoverStore.shared.editing = .init(id: card.id, title: card.title) } label: {
                                Label("Customize Cover…", systemImage: "paintpalette")
                            }
                        }
                    }
            }
        }
        .scaleEffect(hover ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if card.kind == .playlist, let custom = covers.cover(for: card.id) {
                        CustomCoverArt(cover: custom, title: card.title, size: 150)
                    } else {
                        Artwork(url: card.artworkURL, size: 150, circle: card.kind == .artist)
                    }
                }
                    .shadow(color: .black.opacity(hover ? 0.35 : 0.18), radius: hover ? 14 : 6, y: 5)
                if card.kind == .song, player.track?.id == card.id, player.isPlaying {
                    // This poster is what's playing — live EQ badge.
                    EQBars(active: true, style: AnyShapeStyle(.white))
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: .rect(cornerRadius: 8))
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                } else if hover {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(8).transition(.scale.combined(with: .opacity))
                }
            }
            Text(card.title).font(.callout.weight(.medium)).lineLimit(2)
            if !card.subtitle.isEmpty {
                Text(card.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 150, alignment: .leading)
        .contentShape(.rect)
    }
}
