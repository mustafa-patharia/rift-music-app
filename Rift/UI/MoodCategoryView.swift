// SPDX-License-Identifier: GPL-3.0-only
//
// MoodCategoryView — playlists of one mood/genre chip (Chill, Workout, …).
// Carousels of playlist cards; tapping one pushes the shared collection page.

import SwiftUI

struct MoodCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    let category: InnerTubeClient.MoodCategory

    @State private var sections: [HomeSection] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    backButton
                    Text(category.title).font(.largeTitle.bold())
                }
                .padding(.horizontal, 22)
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let error {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.slash",
                                           description: Text(error))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title).font(.title3.bold()).padding(.horizontal, 22)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 18) {
                                    ForEach(section.cards) { MusicCardView(card: $0) }
                                }
                                .padding(.horizontal, 22)
                            }
                            .noScrollbar()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
        .navigationBarBackButtonHidden(true)
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
    }

    private func load() async {
        guard sections.isEmpty else { return }
        loading = true; error = nil
        do { sections = try await InnerTubeClient.moodPlaylists(category) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
