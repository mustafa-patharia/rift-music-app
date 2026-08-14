// SPDX-License-Identifier: GPL-3.0-only
//
// ArtistDetailView — an artist's channel page: hero header (photo, monthly
// listeners, Play / Radio), Top Songs, and the artist's carousels (Albums,
// Singles & EPs, Featured on, Fans might also like → related-artist cards
// push further artist pages via the shared MusicCard destination).

import SwiftUI

struct ArtistDetailView: View {
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let card: MusicCard

    @State private var page: InnerTubeClient.ArtistPage?
    @State private var topSongs: [PlayableTrack] = []
    @State private var showAllSongs = false
    @State private var wikiBio: String?     // fallback when YTM has no description
    @State private var bioExpanded = false
    @State private var loading = false
    @State private var error: String?

    private var about: (text: String, source: String?)? {
        if let d = page?.description { return (d, nil) }
        if let w = wikiBio { return (w, "Wikipedia") }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                backButton
                header
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let error {
                    ContentUnavailableView("Couldn't load artist", systemImage: "wifi.slash",
                                           description: Text(error))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    // About sits right under the header (X-Ray style), clamped
                    // to 3 lines with Read more.
                    if let about { aboutCard(about.text, source: about.source) }
                    if !topSongs.isEmpty { topSongsSection }
                    ForEach(page?.sections ?? []) { section in
                        carousel(section)
                    }
                }
            }
            .padding(.vertical)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(page?.name ?? card.title)
        .navigationBarBackButtonHidden(true)   // custom back lives in the content
        .task { await load() }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            Artwork(url: page?.heroURL ?? card.artworkURL, size: 148, circle: true)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(page?.name ?? card.title)
                    .font(.system(size: 34, weight: .bold)).lineLimit(2)
                if let listeners = page?.listeners {
                    Text(listeners).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    GlassPillButton("Play", icon: "play.fill", prominent: true) {
                        if let first = topSongs.first { player.play(first, in: topSongs) }
                    }
                    .disabled(topSongs.isEmpty)

                    GlassPillButton("Radio", icon: "dot.radiowaves.left.and.right") {
                        startRadio()
                    }
                    .disabled(page?.radioPlaylistId == nil)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top songs").font(.title3.bold())
                Spacer()
                if topSongs.count > 5 {
                    Button(showAllSongs ? "Show less" : "Show all") {
                        withAnimation(.easeInOut(duration: 0.25)) { showAllSongs.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            LazyVStack(spacing: 2) {
                ForEach(Array(visibleSongs.enumerated()), id: \.element.id) { i, t in
                    TrackRow(index: i + 1, track: t,
                             isCurrent: player.track?.id == t.id,
                             isPlaying: player.isPlaying) {
                        player.play(t, in: topSongs)   // full artist list = queue
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var visibleSongs: [PlayableTrack] {
        showAllSongs ? topSongs : Array(topSongs.prefix(5))
    }

    private func carousel(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title).font(.title3.bold()).padding(.horizontal, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(section.cards) { MusicCardView(card: $0) }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private func aboutCard(_ text: String, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("About").font(.headline)
                if let source {
                    Text("· \(source)").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(bioExpanded ? nil : 3)
            Button(bioExpanded ? "Read less" : "Read more") {
                withAnimation(.easeInOut(duration: 0.2)) { bioExpanded.toggle() }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.10)))
        .padding(.horizontal, 22)
    }

    private func startRadio() {
        guard let id = page?.radioPlaylistId else { return }
        Task {
            let tracks = (try? await InnerTubeClient.watchPlaylist(id)) ?? []
            if let first = tracks.first { player.play(first, in: tracks) }
        }
    }

    private func load() async {
        guard page == nil else { return }
        loading = true; error = nil
        do {
            let p = try await InnerTubeClient.artist(browseId: card.id)
            page = p
            // Anonymous artist pages have no top-songs shelf; the header's
            // shuffle playlist (RDAO…) is the artist's catalog — use it.
            if let shuffle = p.shufflePlaylistId {
                topSongs = try await InnerTubeClient.watchPlaylist(shuffle)
                await Prefetcher.shared.warm(topSongs, limit: 5)
            }
            if p.description == nil {
                wikiBio = await WikipediaClient.artistBio(named: p.name)
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
