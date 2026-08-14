// SPDX-License-Identifier: GPL-3.0-only
//
// ContentView — the glass dashboard shell. Custom Sidebar + a NavigationStack
// detail that pushes album/playlist pages, an optional QueueRail, and the
// floating NowPlayingBar overlaid at the bottom. The window is non-opaque so the
// desktop wallpaper blurs through (VisualEffectBackground + WindowConfigurator).

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var auth: AuthController
    @EnvironmentObject var ui: UIState
    @ObservedObject private var playlistStore = PlaylistStore.shared
    @State private var panel: Panel = .home
    @State private var newPlaylistName = ""

    private var hasTrack: Bool { player.track != nil }

    var body: some View {
        // Foreground content RESPECTS the safe area so it never slides under the
        // traffic lights. Only the background bleeds edge-to-edge. (Putting an
        // .ignoresSafeArea() view as a ZStack *sibling* expands the container and
        // pushes the foreground under the window chrome — the top-clip bug.)
        HStack(spacing: 0) {
            Sidebar(panel: $panel).frame(width: 189)

            // Center column. The full player is an in-window layer that slides up
            // over ONLY this column (home/albums stay mounted behind it). Sidebar +
            // queue are HStack siblings — their layout never changes, so nothing
            // reflows. clipped() contains the slide within the column.
            ZStack {
                // Song list / album / home — hidden (not unmounted) while the player
                // is up, so it keeps its scroll state and the shared bg shows through.
                NavigationStack {
                    detail
                        .navigationDestination(for: MusicCard.self) { card in
                            if card.kind == .artist { ArtistDetailView(card: card) }
                            else { CollectionDetailView(card: card) }
                        }
                        .navigationDestination(for: InnerTubeClient.MoodCategory.self) {
                            MoodCategoryView(category: $0)
                        }
                        .navigationDestination(for: HistoryRoute.self) { _ in
                            HistoryPageView()
                        }
                        .navigationDestination(for: LocalPlaylistRoute.self) {
                            LocalPlaylistView(id: $0.id)
                        }
                        .toolbarBackground(.hidden, for: .windowToolbar)
                }
                .id(panel)   // reset pushed stack when the section changes
                .opacity(ui.showFullPlayer ? 0 : 1)
                .allowsHitTesting(!ui.showFullPlayer)

                // Full player — transparent; the shared ambient bg (ContentView) shows
                // through. Slides up as the list hides.
                if ui.showFullPlayer && hasTrack {
                    FullScreenPlayerView()
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // Extra scroll room at the END of every scroll view so the last items
            // can scroll up past the floating pill. contentMargins (not
            // safeAreaPadding!) — it pads inside the scroll content only, without
            // shrinking the visible column height.
            .contentMargins(.bottom, hasTrack && !ui.showFullPlayer ? 112 : 0, for: .scrollContent)
            .background(.clear)

            if ui.showQueue && hasTrack {
                QueueRail().frame(width: 264)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Background only — bleeds full window behind everything.
            ZStack {
                LinearGradient(colors: [Color(white: 0.11), Color(white: 0.05)],
                               startPoint: .top, endPoint: .bottom)
                if let art = player.track?.artworkURL {
                    AmbientArtwork(url: art)   // now-playing poster tint behind the glass
                }
            }
            .ignoresSafeArea()
        }
        // The player is NOT in this window. It's a separate borderless child
        // panel (PlayerPanelController) that floats past the bottom edge — an
        // NSWindow can't draw outside its own rect, so the spill-out pill has to
        // be its own window. Grab our NSWindow and hand it over.
        .background(WindowAccessor { w in
            AppServices.shared.playerPanel.attach(to: w)
            // Draw edge-to-edge under the title bar so the center column (and the
            // full player) reach the very top — no title-bar strip gap. Traffic
            // lights float over the sidebar's top padding (standard music-app look).
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
        })
        // Home feed is cached in HomeStore — re-personalize it on sign-in/out.
        .onChange(of: auth.isAuthenticated) { _, _ in
            Task { await HomeStore.shared.refresh() }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasTrack)
        .animation(.easeInOut(duration: 0.5), value: player.track?.id)
        // One app-level name prompt for every "New Playlist…" entry point
        // (Library button + song context menus set PlaylistStore.newPrompt).
        .alert("New Playlist", isPresented: Binding(
            get: { playlistStore.newPrompt != nil },
            set: { if !$0 { playlistStore.newPrompt = nil } })
        ) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                playlistStore.create(newPlaylistName, with: playlistStore.newPrompt?.track)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        } message: {
            if let t = playlistStore.newPrompt?.track {
                Text("“\(t.title)” will be its first song.")
            }
        }
        .sheet(isPresented: $auth.showingLogin) {
            if auth.pendingAuth != nil {
                // Account chooser — shown after Google login when multiple
                // accounts (primary + brand) are available.
                AccountSelectionView(auth: auth)
            } else {
                // Google sign-in webview.
                NavigationStack {
                    GoogleSignInView { auth.loginCaptured($0) }
                        .frame(minWidth: 520, minHeight: 640)
                        .navigationTitle("Sign in to YouTube Music")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { auth.showingLogin = false }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch panel {
        case .home:    HomeView().id(auth.isAuthenticated)   // refetch feed on sign in/out
        case .search:  SearchView()
        case .library: LibraryView()
        case .stats:   StatsView()
        case .settings: SettingsPanelView()
        }
    }

}
