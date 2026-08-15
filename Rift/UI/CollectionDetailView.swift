// SPDX-License-Identifier: GPL-3.0-only
//
// CollectionDetailView — album / playlist page. Full-bleed poster hero with
// glass controls layered on the artwork (HeroCard language), then the songs
// as a poster grid (no table rows — owner's call). Songs missing their own
// thumb inherit the collection's artwork.

import SwiftUI

struct CollectionDetailView: View {
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let card: MusicCard

    @State private var tracks: [PlayableTrack] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let error {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.slash", description: Text(error))
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)],
                              alignment: .leading, spacing: 22) {
                        ForEach(displayTracks) { t in
                            TrackPosterCard(track: t) { player.play(t, in: tracks) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom)
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
        // No .navigationTitle — it only reserves a toolbar row, misaligning
        // the custom back button against QueueRail's header.
        .navigationBarBackButtonHidden(true)   // custom back floats on the hero
        .task { await load() }
    }

    // Songs without their own poster inherit the album/playlist artwork.
    private var displayTracks: [PlayableTrack] {
        tracks.map { t in
            t.artworkURL != nil ? t : PlayableTrack(id: t.id, title: t.title, artist: t.artist,
                                                    artworkURL: card.artworkURL, duration: t.duration)
        }
    }

    // MARK: hero — artwork banner, controls in glass on the poster
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: card.artworkURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(height: 300).frame(maxWidth: .infinity).clipped()

            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text((card.kind == .album ? "Album" : "Playlist").uppercased())
                    .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                Text(card.title)
                    .font(.system(size: 34, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 8) {
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle)
                    }
                    if !tracks.isEmpty {
                        if !card.subtitle.isEmpty { Text("·") }
                        Text("\(tracks.count) songs")
                    }
                }
                .font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(1)

                HStack(spacing: 10) {
                    GlassPillButton("Play", icon: "play.fill", prominent: true) {
                        if let first = tracks.first { player.play(first, in: tracks) }
                    }
                    GlassPillButton("Shuffle", icon: "shuffle") {
                        guard let random = tracks.randomElement() else { return }
                        player.play(random, in: tracks)
                        if !player.isShuffled { player.toggleShuffle() }
                    }
                }
                .disabled(tracks.isEmpty)
                .padding(.top, 6)
            }
            .padding(24)
        }
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .liquidGlass(true, in: .circle)
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .padding(.horizontal, 16)
    }

    private func load() async {
        guard tracks.isEmpty else { return }
        loading = true; error = nil
        do {
            tracks = try await InnerTubeClient.tracks(forBrowseId: card.id)
            // Warm the top few so the first taps are instant.
            await Prefetcher.shared.warm(tracks, limit: 5)
        }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
