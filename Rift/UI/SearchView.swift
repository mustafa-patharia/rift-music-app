// SPDX-License-Identifier: GPL-3.0-only
//
// SearchView — top-pinned search over InnerTube. Idle: recent searches. Typing:
// live suggestions (debounced). Submit: song results. Recents persist locally.

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var store = HomeStore.shared   // trending shelves (cached)

    @State private var query = ""
    @State private var results: [PlayableTrack] = []
    @State private var artists: [MusicCard] = []
    @State private var suggestions: [String] = []
    @State private var recents: [String] = []
    @State private var searching = false
    @State private var error: String?

    @State private var suggestTask: Task<Void, Never>?
    private static let recentsKey = "recentSearches"

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Search")
        .onAppear { recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [] }
        .task { store.start() }   // idempotent — trending comes from the home cache
    }

    // MARK: search bar (always on top)
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search YouTube Music…", text: $query)
                .textFieldStyle(.plain).onSubmit { run(query) }
                .onChange(of: query) { _, q in scheduleSuggestions(q) }
            if searching { ProgressView().controlSize(.small) }
            if !query.isEmpty {
                Button { query = ""; results = []; artists = []; suggestions = []; error = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(12).liquidGlass(in: .capsule)
        .padding([.horizontal, .top], 20).padding(.bottom, 10)
    }

    // MARK: content
    @ViewBuilder private var content: some View {
        if let error {
            ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
                .frame(maxHeight: .infinity)
        } else if !results.isEmpty || !artists.isEmpty {
            resultsList
        } else if !suggestions.isEmpty {
            suggestionList
        } else {
            idle
        }
    }

    // Poster grid, not a table — songs render like the home shelves (owner's
    // call: table listings feel dated; posters carry the vibe).
    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !artists.isEmpty {
                    Text("Artists").font(.headline).padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(artists) { MusicCardView(card: $0) }
                        }
                    }
                    .noScrollbar()
                    .padding(.bottom, 6)
                    if !results.isEmpty { Text("Songs").font(.headline) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)],
                          alignment: .leading, spacing: 22) {
                    ForEach(results) { track in
                        TrackPosterCard(track: track) { player.play(track, in: results) }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions, id: \.self) { s in
                    Button { run(s) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            Text(s).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
    }

    // Idle: recent searches up top, then the Trending shelves (charts — Top
    // artists + Video charts) so the page isn't dead space before typing.
    @ViewBuilder private var idle: some View {
        if recents.isEmpty && store.charts.isEmpty {
            ContentUnavailableView("Search YouTube Music", systemImage: "magnifyingglass",
                                   description: Text("Find songs to play."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !recents.isEmpty {
                        HStack {
                            Text("Recent").font(.headline)
                            Spacer()
                            Button("Clear") { clearRecents() }.buttonStyle(.plain)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)
                        ForEach(recents, id: \.self) { r in
                            Button { run(r) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                    Text(r).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 8).padding(.horizontal, 10).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(store.charts) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title == "Video charts" ? "Trending" : section.title)
                                .font(.title3.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 18) {
                                    ForEach(section.cards) { MusicCardView(card: $0) }
                                }
                            }
                            .noScrollbar()
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6)
            }
            .scrollContentBackground(.hidden)
            .noScrollbar()
        }
    }

    // MARK: actions
    private func scheduleSuggestions(_ q: String) {
        suggestTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { suggestions = []; return }
        if !results.isEmpty { results = [] }   // back to typing → drop stale results
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let hits = (try? await InnerTubeClient.searchSuggestions(trimmed)) ?? []
            if Task.isCancelled { return }
            suggestions = hits
        }
    }

    private func run(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query = q
        suggestTask?.cancel(); suggestions = []
        searching = true; error = nil
        addRecent(q)
        Task {
            do {
                async let songHits = InnerTubeClient.searchSongs(q)
                async let artistHits = InnerTubeClient.searchArtists(q)
                results = try await songHits
                artists = Array(((try? await artistHits) ?? []).prefix(6))
                if results.isEmpty && artists.isEmpty { error = "No results for “\(q)”." }
                else { await Prefetcher.shared.warm(results, limit: 5) }   // top hits instant on tap
            } catch { self.error = error.localizedDescription }
            searching = false
        }
    }

    private func addRecent(_ q: String) {
        var r = recents.filter { $0.lowercased() != q.lowercased() }
        r.insert(q, at: 0)
        recents = Array(r.prefix(10))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }

    private func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }
}
