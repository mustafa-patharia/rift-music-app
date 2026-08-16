// SPDX-License-Identifier: GPL-3.0-only
//
// LibraryView — YOUR music: downloaded (offline) songs, your YT Music
// playlists (signed in), and full listening history. Downloads come from
// AudioFileCache; titles/posters come from local play history metadata.

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var auth: AuthController

    @ObservedObject private var playlistStore = PlaylistStore.shared

    @State private var downloads: [PlayEvent] = []
    @State private var playlists: [MusicCard] = []
    @State private var loadedPlaylists = false

    private var isEmpty: Bool {
        downloads.isEmpty && playlists.isEmpty && playlistStore.playlists.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Library").font(.largeTitle.bold()).padding(.horizontal, 22)

                if isEmpty {
                    // Empty state owns the whole page — showing it above an
                    // empty "Your Playlists" shelf read as a broken layout.
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "square.stack")
                    } description: {
                        Text("Use Download on any song to keep it offline — it shows up here, along with your playlists.")
                    } actions: {
                        GlassPillButton("New Playlist", icon: "plus") {
                            playlistStore.newPrompt = .init(track: nil)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    if !downloads.isEmpty { downloadsSection }
                    // Liked songs live inside "Your Playlists" as the Liked Music
                    // auto-playlist — no separate listing (owner's call). History
                    // lives on Home ("Recently played" → View more), not here.
                    playlistsSection
                }
            }
            .padding(.vertical, 20)
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
    }

    // MARK: downloads (offline copies on disk)
    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            shelfHeader("Downloads", subtitle: "\(downloads.count) songs · available offline")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(downloads) { e in
                        posterCard(e)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    // MARK: playlists (yours + YT Music library)
    @ViewBuilder private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                shelfHeader("Your Playlists",
                            subtitle: auth.isAuthenticated ? "yours + YouTube Music" : "created in Rift")
                Spacer()
                GlassPillButton("New Playlist", icon: "plus") {
                    playlistStore.newPrompt = .init(track: nil)
                }
                .padding(.horizontal, 22)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(playlistStore.playlists) { LocalPlaylistCard(playlist: $0) }
                    // Remote cards, minus the ones that are just our own pushed
                    // playlists coming back down (card id = VL<playlistId>).
                    ForEach(playlists.filter { c in
                        !playlistStore.remoteIds.contains(
                            c.id.hasPrefix("VL") ? String(c.id.dropFirst(2)) : c.id)
                    }) { MusicCardView(card: $0) }
                }
                .padding(.horizontal, 22)
            }
        }

        if !auth.isAuthenticated && !downloads.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill").foregroundStyle(.tint)
                Text("Sign in to see your YouTube Music playlists here.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                GlassPillButton("Sign in") { auth.showingLogin = true }
            }
            .padding(14)
            .liquidGlass(in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.10)))
            .padding(.horizontal, 22)
        }
    }

    // MARK: pieces
    private func posterCard(_ e: PlayEvent) -> some View {
        Button { player.play(e.asTrack) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Artwork(url: e.asTrack.artworkURL, size: 140)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(.white, .green)
                            .padding(6)
                    }
                Text(e.title).font(.subheadline.weight(.semibold))
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(e.cleanArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { player.play(e.asTrack) } label: { Label("Play", systemImage: "play.fill") }
            Button { player.playNext(e.asTrack) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { player.addToQueue(e.asTrack) } label: { Label("Add to Queue", systemImage: "text.append") }
            Button(role: .destructive) {
                Task {
                    await AudioFileCache.shared.remove(e.trackId)
                    await load()
                }
            } label: { Label("Remove Download", systemImage: "trash") }
        }
    }

    private func shelfHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
    }

    private func load() async {
        // Downloads = ONLY what the user explicitly downloaded (Download button).
        // Files cached from playback are internal cache — never shown here.
        downloads = await AudioFileCache.shared.downloads().map { d in
            PlayEvent(trackId: d.id, title: d.meta.title, artist: d.meta.artist,
                      artworkURL: d.meta.artworkURL,
                      ts: d.meta.downloadedAt ?? .distantPast, seconds: 0, duration: nil)
        }

        if auth.isAuthenticated && !loadedPlaylists {
            loadedPlaylists = true
            async let pls = InnerTubeClient.libraryPlaylists()
            async let lk = InnerTubeClient.likedSongs()
            playlists = (try? await pls) ?? []
            // Hearts sync down silently — YTM-liked tracks show filled hearts.
            if let likedIds = (try? await lk)?.map(\.id) {
                LikeStore.shared.importLiked(likedIds)
            }
        }
    }
}
