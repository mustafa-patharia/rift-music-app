// SPDX-License-Identifier: GPL-3.0-only
//
// LocalPlaylistView — detail page for a user-created playlist (PlaylistStore),
// with rename / delete / per-row remove. Plus the shared "Add to Playlist"
// context-menu section and the Library shelf card. Reads the store live by id,
// so edits made anywhere update the open page.

import SwiftUI

struct LocalPlaylistRoute: Hashable { let id: String }

struct LocalPlaylistView: View {
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlaylistStore.shared
    let id: String

    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let p = store.playlist(id) {
                VStack(alignment: .leading, spacing: 18) {
                    backButton
                    header(p)
                    if p.tracks.isEmpty {
                        ContentUnavailableView(
                            "Empty playlist", systemImage: "music.note.list",
                            description: Text("Right-click any song → Add to Playlist → \(p.title)."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(p.tracks.enumerated()), id: \.element.id) { i, t in
                                HStack(spacing: 4) {
                                    TrackRow(index: i + 1, track: t,
                                             isCurrent: player.track?.id == t.id,
                                             isPlaying: player.isPlaying) {
                                        player.play(t, in: p.tracks)
                                    }
                                    Button { store.remove(trackId: t.id, from: id) } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 26, height: 26).contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove from playlist")
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationBarBackButtonHidden(true)
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Rename") { store.rename(id, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(store.playlist(id)?.title ?? "")”?",
                            isPresented: $confirmDelete) {
            Button("Delete Playlist", role: .destructive) {
                store.delete(id)
                dismiss()
            }
        } message: {
            Text(store.playlist(id)?.remoteId != nil
                 ? "Also deletes it from your YouTube Music account."
                 : "This can't be undone.")
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .liquidGlass(true, in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func header(_ p: PlaylistStore.UserPlaylist) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            PlaylistCover(playlist: p, size: 128)
            VStack(alignment: .leading, spacing: 6) {
                Text(p.title).font(.title.bold()).lineLimit(2)
                Text(subtitle(p)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    GlassPillButton("Play", icon: "play.fill", prominent: true) {
                        if let first = p.tracks.first { player.play(first, in: p.tracks) }
                    }
                    .disabled(p.tracks.isEmpty)
                    Menu {
                        Button { draftName = p.title; renaming = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .liquidGlass(true, in: .circle)
                            .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                            .contentShape(.circle)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func subtitle(_ p: PlaylistStore.UserPlaylist) -> String {
        let count = "\(p.tracks.count) song\(p.tracks.count == 1 ? "" : "s")"
        return p.remoteId != nil ? count + " · synced to YouTube Music" : count
    }
}

/// Cover = first track's poster, or a glass placeholder for empty playlists.
struct PlaylistCover: View {
    let playlist: PlaylistStore.UserPlaylist
    var size: CGFloat = 150

    var body: some View {
        if let art = playlist.tracks.first?.artworkURL {
            Artwork(url: art, size: size).clipShape(.rect(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.3)).foregroundStyle(.secondary))
                .frame(width: size, height: size)
        }
    }
}

/// The playlist choices themselves — existing lists + "New Playlist…". Reused
/// by the context-menu submenu and the full player's top-bar menu.
struct PlaylistMenuItems: View {
    @ObservedObject private var store = PlaylistStore.shared
    let track: PlayableTrack

    var body: some View {
        ForEach(store.playlists) { p in
            Button(p.title) { store.add(track, to: p.id) }
        }
        if !store.playlists.isEmpty { Divider() }
        Button { store.newPrompt = .init(track: track) } label: {
            Label("New Playlist…", systemImage: "plus")
        }
    }
}

/// "Add to Playlist" submenu — shared by every song context menu.
struct AddToPlaylistMenu: View {
    let track: PlayableTrack

    var body: some View {
        Menu {
            PlaylistMenuItems(track: track)
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
    }
}

/// Shelf card for a user playlist (Library → Your Playlists).
struct LocalPlaylistCard: View {
    let playlist: PlaylistStore.UserPlaylist
    @State private var hover = false

    var body: some View {
        NavigationLink(value: LocalPlaylistRoute(id: playlist.id)) {
            VStack(alignment: .leading, spacing: 8) {
                PlaylistCover(playlist: playlist, size: 150)
                    .shadow(color: .black.opacity(hover ? 0.35 : 0.18),
                            radius: hover ? 14 : 6, y: 5)
                Text(playlist.title).font(.callout.weight(.medium)).lineLimit(2)
                Text("\(playlist.tracks.count) song\(playlist.tracks.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(hover ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
        .contextMenu {
            Button(role: .destructive) { PlaylistStore.shared.delete(playlist.id) } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
    }
}
