// SPDX-License-Identifier: GPL-3.0-only
//
// HistoryPageView — the full "Recently played" page (Home shows only the
// latest shelf; "View more" pushes this). Poster grid, newest first, distinct
// tracks, playable with the whole history as the queue.

import SwiftUI

/// Navigation token for the full history page.
struct HistoryRoute: Hashable {}

struct HistoryPageView: View {
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [PlayableTrack] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    backButton
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recently Played").font(.largeTitle.bold())
                        Text("\(tracks.count) songs · stored only on this Mac")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 22)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)],
                          alignment: .leading, spacing: 22) {
                    ForEach(tracks) { t in
                        TrackPosterCard(track: t) { player.play(t, in: tracks) }
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.vertical)
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
        .navigationBarBackButtonHidden(true)
        .task {
            let events = await PlayHistoryStore.shared.all()
            var seen = Set<String>()
            tracks = events.reversed().compactMap {
                seen.insert($0.trackId).inserted ? $0.asTrack : nil
            }
        }
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
    }
}
