// SPDX-License-Identifier: GPL-3.0-only
//
// HomeView — the YT Music recommendation feed: featured hero, recently played,
// your top artists (from local history), recommendation carousels, charts
// (top artists + video charts), and mood/genre chips. All remote data lives in
// HomeStore (cached across visits, background-refreshed every 30 min) — the
// view renders instantly on revisit.

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var store = HomeStore.shared
    @State private var recent: [PlayEvent] = []

    var body: some View {
        ScrollView {
            if store.loading && store.sections.isEmpty {
                ProgressView("Loading recommendations…")
                    .frame(maxWidth: .infinity).padding(.top, 120)
            } else if let error = store.error, store.sections.isEmpty {
                ContentUnavailableView("Couldn't load home", systemImage: "wifi.slash",
                                       description: Text(error))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let hero { HeroCard(card: hero).padding(.horizontal, 22) }
                    if !recent.isEmpty { recentShelf }
                    if !store.topArtists.isEmpty {
                        shelf("Your top artists", cards: store.topArtists)
                    }
                    if let d = store.discovery { shelf(d.title, cards: d.cards) }
                    if let l = store.likedDiscovery { shelf(l.title, cards: l.cards) }
                    ForEach(store.sections) { shelf($0.title, cards: $0.cards) }
                    ForEach(store.charts) { shelf($0.title, cards: $0.cards) }
                    if !store.moods.isEmpty { moodGrid }
                }
                // Shared top line: safe-area inset + 16 lands the hero on the
                // same line as the sidebar's first section and the queue header.
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
        .task { store.start() }
        .task { recent = await PlayHistoryStore.shared.recent() }
        // Recently played updates the moment a track changes (the finished
        // session was just logged) — no need to leave and revisit Home.
        .onChange(of: player.track?.id) { _, _ in
            Task { recent = await PlayHistoryStore.shared.recent() }
        }
    }

    /// First tile of the first carousel becomes the hero.
    private var hero: MusicCard? { store.sections.first?.cards.first }

    private func shelf(_ title: String, cards: [MusicCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold()).padding(.horizontal, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(cards) { MusicCardView(card: $0) }
                }
                .padding(.horizontal, 22)
            }
            .noScrollbar()
        }
    }

    /// "Recently played" — from local listening history (PlayHistoryStore).
    /// "View more" pushes the full poster-grid history page.
    private var recentShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently played").font(.title3.bold())
                Spacer()
                NavigationLink(value: HistoryRoute()) {
                    Text("View more").font(.subheadline).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(recent) { e in
                        Button { player.play(e.asTrack) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(url: e.asTrack.artworkURL, size: 140)
                                    .clipShape(.rect(cornerRadius: 10))
                                Text(e.title).font(.subheadline.weight(.semibold))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                Text(e.cleanArtist).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { player.play(e.asTrack) } label: { Label("Play", systemImage: "play.fill") }
                            Button { player.playNext(e.asTrack) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            Button { player.addToQueue(e.asTrack) } label: { Label("Add to Queue", systemImage: "text.append") }
                            Divider()
                            Button { Downloader.download(e.asTrack) } label: { Label("Download", systemImage: "arrow.down.circle") }
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
            .noScrollbar()
        }
    }

    /// "Moods & genres" — chip grid; a chip pushes its playlists page.
    private var moodGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moods & genres").font(.title3.bold()).padding(.horizontal, 22)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(store.moods) { mood in
                    MoodChip(mood: mood)
                }
            }
            .padding(.horizontal, 22)
        }
    }
}

private struct MoodChip: View {
    let mood: InnerTubeClient.MoodCategory
    @State private var hover = false

    var body: some View {
        NavigationLink(value: mood) {
            Text(mood.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .liquidGlass(in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(hover ? 0.22 : 0.10)))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(hover ? 1.035 : 1)
        .brightness(hover ? 0.06 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
    }
}
