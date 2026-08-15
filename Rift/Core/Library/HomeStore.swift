// SPDX-License-Identifier: GPL-3.0-only
//
// HomeStore — the Home feed's data, cached OUTSIDE the view. HomeView is
// recreated on every panel switch (ContentView resets the NavigationStack via
// .id(panel)), so view-local @State reloaded the feed each visit. The store
// loads once, keeps serving instantly, and a background loop refreshes every
// 30 minutes. "Your top artists" resolves history names → artist cards.

import SwiftUI

@MainActor
final class HomeStore: ObservableObject {
    static let shared = HomeStore()

    @Published var sections: [HomeSection] = []
    @Published var charts: [HomeSection] = []
    @Published var moods: [InnerTubeClient.MoodCategory] = []
    @Published var topArtists: [MusicCard] = []
    @Published var discovery: HomeSection?        // "More like <last played>" (radio-seeded)
    @Published var likedDiscovery: HomeSection?   // "Because you liked <song>" (liked-seeded)
    @Published var loading = false
    @Published var error: String?

    private var started = false

    /// Idempotent — first call loads + starts the 30-min background refresh;
    /// later calls (every Home visit) are no-ops serving the cache.
    func start() {
        guard !started else { return }
        started = true
        Task {
            loading = true
            await refresh()
            loading = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                await refresh()
            }
        }
    }

    /// Full refetch (also called on sign-in/out so the feed re-personalizes).
    func refresh() async {
        error = nil
        do {
            async let home = InnerTubeClient.home()
            async let chartsFeed = InnerTubeClient.charts()
            async let moodChips = InnerTubeClient.moodCategories()
            sections = try await home
            charts = (try? await chartsFeed) ?? []
            moods = (try? await moodChips) ?? []
            // Warm the directly-playable song tiles so tapping one is instant.
            let songs = sections.flatMap(\.cards).filter { $0.kind == .song }.map(\.asTrack)
            await Prefetcher.shared.warm(songs, limit: 10)
        } catch {
            if sections.isEmpty { self.error = error.localizedDescription }
        }
        await refreshTopArtists()
        await refreshDiscovery()
    }

    /// Discovery row (#26): seed the newest history track into the radio
    /// endpoint → "More like …" shelf of related songs. Local taste driving
    /// YTM's recommendation engine — works signed out too.
    func refreshDiscovery() async {
        let events = await PlayHistoryStore.shared.all()
        guard let seed = events.sorted(by: { $0.ts > $1.ts })
            .first(where: { URL(string: $0.trackId)?.isFileURL != true }) else { return }
        guard let related = try? await InnerTubeClient.radio(videoId: seed.trackId),
              !related.isEmpty else { return }
        let cards = related.prefix(12).map {
            MusicCard(id: $0.id, kind: .song, title: $0.title,
                      subtitle: $0.artist, artworkURL: $0.artworkURL)
        }
        discovery = HomeSection(title: "More like \(seed.title)", cards: Array(cards))
        await refreshLikedDiscovery(excluding: seed.trackId)
    }

    /// Second discovery row (#26): seed a LIKED song (newest hearted track we
    /// have a title for in history) into radio → "Because you liked …". Skips
    /// the seed the "More like" row already used so the two rows differ.
    private func refreshLikedDiscovery(excluding usedSeed: String) async {
        let likedIds = LikeStore.shared.ids
        guard !likedIds.isEmpty else { return }
        let events = await PlayHistoryStore.shared.all()
        guard let seed = events.sorted(by: { $0.ts > $1.ts })
            .first(where: { likedIds.contains($0.trackId) && $0.trackId != usedSeed
                            && URL(string: $0.trackId)?.isFileURL != true }) else { return }
        guard let related = try? await InnerTubeClient.radio(videoId: seed.trackId),
              !related.isEmpty else { return }
        let cards = related.prefix(12).map {
            MusicCard(id: $0.id, kind: .song, title: $0.title,
                      subtitle: $0.artist, artworkURL: $0.artworkURL)
        }
        likedDiscovery = HomeSection(title: "Because you liked \(seed.title)", cards: Array(cards))
    }

    /// Minimum plays in history before "Your top artists" means anything —
    /// below this a ranking is just whatever got played first, not a taste
    /// signal.
    private static let minPlaysForTopArtists = 100

    /// Most-listened artists from local history → artist cards (name → search
    /// lookup, capped at 6 to keep it one cheap burst).
    func refreshTopArtists() async {
        let events = await PlayHistoryStore.shared.all()
        guard events.count >= Self.minPlaysForTopArtists else { topArtists = []; return }
        var secs: [String: TimeInterval] = [:]
        for e in events where !e.cleanArtist.isEmpty {
            secs[e.cleanArtist, default: 0] += e.cleanSeconds
        }
        let names = secs.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.prefix(6).map(\.key)
        guard names != topArtists.map(\.title) else { return }   // unchanged → skip lookups
        var cards: [MusicCard] = []
        for n in names {
            if let c = try? await InnerTubeClient.artistCard(named: n) { cards.append(c) }
        }
        topArtists = cards
    }
}
