// SPDX-License-Identifier: GPL-3.0-only
//
// FullScreenPlayerView — the dedicated Now Playing screen: large artwork, ambient
// poster-tinted background, full transport, and an optional lyrics panel. Shown as
// a cover overlay from ContentView (macOS has no fullScreenCover).

import SwiftUI

struct FullScreenPlayerView: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var ui: UIState

    @ObservedObject private var likes = LikeStore.shared
    @ObservedObject private var ai = AIStore.shared
    @State private var scrubValue: Double = 0
    @State private var scrubbing = false
    @State private var showLyrics = false
    @State private var lyrics: String?
    @State private var lyricsState: LyricsState = .idle
    // AI lyric views (local model via AI facade) — cached per track.
    private enum LyricsDisplay { case original, romanized, english }
    @State private var display: LyricsDisplay = .original
    @State private var romanized: String?
    @State private var english: String?
    @State private var aiWorking = false

    private enum LyricsState: Equatable { case idle, loading, none, loaded }

    private var isLiked: Bool { player.track.map { likes.isLiked($0.id) } ?? false }

    var body: some View {
        // TRANSPARENT — no background of its own. The shared ambient album-art bg
        // lives in ContentView (behind everything) and never moves; the home list
        // just hides while this shows. One shared bg, two swapping foregrounds.
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 40) {
                nowPlaying
                    .frame(maxWidth: showLyrics ? 460 : .infinity)
                if showLyrics { lyricsPanel.frame(maxWidth: 460) }
            }
            .padding(.horizontal, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: player.track?.id) { await loadLyrics() }
    }

    private var topBar: some View {
        HStack {
            circleButton("chevron.down", help: "Close") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { ui.showFullPlayer = false }
            }
            Spacer()
            circleButton(isLiked ? "heart.fill" : "heart",
                         help: isLiked ? "Remove from Liked" : "Like",
                         active: isLiked, activeColor: .red) {
                if let t = player.track { likes.toggle(t) }
            }
            circleButton("arrow.down.circle", help: "Download") {
                if let t = player.track { Downloader.download(t) }
            }
            playlistMenuButton
            circleButton("sidebar.right", help: "Queue", active: ui.showQueue) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.showQueue.toggle() }
            }
            circleButton("text.quote", help: "Lyrics", active: showLyrics) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showLyrics.toggle() }
            }
            // Disabled only when there's nothing to open AND nothing to close —
            // an open panel must always be closable.
            .disabled(lyricsState == .none && !showLyrics)
            .opacity(lyricsState == .none && !showLyrics ? 0.4 : 1)
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }

    // Same circle chrome as the buttons, but opens the playlist picker.
    private var playlistMenuButton: some View {
        Menu {
            if let t = player.track { PlaylistMenuItems(track: t) }
        } label: {
            circleGlyph("rectangle.stack.badge.plus")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Add to Playlist")
    }

    // One 40pt circular button; the glyph is centered in a fixed square via ZStack
    // so asymmetric SF Symbol bounding boxes (chevron/quote) don't sit off-center.
    private func circleButton(_ name: String, help: String, active: Bool = false,
                              activeColor: Color? = nil,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleGlyph(name, active: active, activeColor: activeColor)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func circleGlyph(_ name: String, active: Bool = false,
                             activeColor: Color? = nil) -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active
                    ? (activeColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
                    : AnyShapeStyle(.white))
        }
        .frame(width: 40, height: 40)
        .contentShape(.circle)
    }

    // MARK: now playing column
    private var nowPlaying: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Artwork(url: player.track?.artworkURL, size: 340)
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                .scaleEffect(player.isPlaying ? 1 : 0.94)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: player.isPlaying)

            VStack(spacing: 6) {
                Text(player.track?.title ?? "—").font(.system(size: 26, weight: .bold))
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(player.track?.artist ?? "").font(.title3).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)

            scrubber
            transport
            Spacer(minLength: 0)
        }
    }

    private var scrubber: some View {
        let dur = max(player.duration, 0.01)
        return VStack(spacing: 4) {
            Slider(value: $scrubValue, in: 0...dur) { editing in
                scrubbing = editing
                if !editing { player.seek(to: scrubValue) }
            }
            .onChange(of: player.currentTime) { _, t in if !scrubbing { scrubValue = min(t, dur) } }
            .onChange(of: player.track?.id) { _, _ in scrubValue = 0 }
            HStack {
                Text(fmt(scrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(fmt(player.duration))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420)
    }

    private var transport: some View {
        HStack(spacing: 34) {
            icon("shuffle", size: 18, active: player.isShuffled) { player.toggleShuffle() }
            icon("backward.fill", size: 24) { player.previous() }
                .disabled(!player.hasPrevious && player.currentTime <= 3)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            icon("forward.fill", size: 24) { player.next() }
                .disabled(!player.hasNext)
            icon(player.repeatMode == .one ? "repeat.1" : "repeat", size: 18,
                 active: player.repeatMode != .off) { player.cycleRepeat() }
        }
    }

    // MARK: lyrics panel
    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lyrics").font(.title2.bold()).foregroundStyle(.white)
                Spacer()
                lyricsAIMenu
            }
            Group {
                switch lyricsState {
                case .loading: ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
                case .none, .idle:
                    Text("No lyrics available").foregroundStyle(.secondary).padding(.top, 40)
                case .loaded:
                    if aiWorking {
                        // Writing-Tools-style shimmer while the model generates.
                        AISkeletonLines().padding(.top, 10)
                    } else {
                        ScrollView(showsIndicators: false) {
                            Text(displayedLyrics)
                                .font(.title3).foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 40)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 40)
    }

    private var displayedLyrics: String {
        switch display {
        case .original:  return lyrics ?? ""
        case .romanized: return romanized ?? lyrics ?? ""
        case .english:   return english ?? lyrics ?? ""
        }
    }

    // Language menu — AI lyric views (all on the local model, per Settings):
    // romanization for any non-Latin script (Hindi, Korean, Chinese, Russian,
    // Malayalam, …), English translation for any non-English lyrics. Hidden
    // until an AI provider is enabled in Settings.
    @ViewBuilder private var lyricsAIMenu: some View {
        if lyricsState == .loaded, let text = lyrics, ai.isReady,
           AI.hasNonLatinScript(text) || AI.isNonEnglish(text) {
            Menu {
                Button { display = .original } label: {
                    display == .original ? Label("Original", systemImage: "checkmark") : Label("Original", systemImage: "")
                }
                if AI.hasNonLatinScript(text) {
                    Button { switchTo(.romanized, text) } label: {
                        display == .romanized ? Label("Romanized", systemImage: "checkmark") : Label("Romanized", systemImage: "")
                    }
                }
                if AI.isNonEnglish(text) {
                    Button { switchTo(.english, text) } label: {
                        display == .english ? Label("English translation", systemImage: "checkmark") : Label("English translation", systemImage: "")
                    }
                }
            } label: {
                // Icon never disappears — it pulses while the model works.
                Image(systemName: "translate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(aiWorking || display != .original
                                     ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                    .symbolEffect(.pulse, options: .repeating, isActive: aiWorking)
                    .frame(width: 34, height: 26)
                    .background(.ultraThinMaterial, in: .capsule)
                    .contentShape(.capsule)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(aiWorking)
            .help("Lyrics language")
        }
    }

    private func switchTo(_ target: LyricsDisplay, _ text: String) {
        // Cached → instant flip; otherwise run the model once and cache.
        if (target == .romanized && romanized != nil) || (target == .english && english != nil) {
            display = target; return
        }
        aiWorking = true
        Task {
            defer { aiWorking = false }
            switch target {
            case .romanized:
                if let r = try? await AI.romanize(text) { romanized = r; display = .romanized }
            case .english:
                if let r = try? await AI.translate(text) { english = r; display = .english }
            case .original: break
            }
        }
    }

    private func loadLyrics() async {
        guard let id = player.track?.id, URL(string: id)?.isFileURL != true else {
            lyricsState = .none; lyrics = nil; romanized = nil; english = nil; display = .original; return
        }
        romanized = nil; english = nil; display = .original
        lyricsState = .loading; lyrics = nil
        let text = try? await InnerTubeClient.lyrics(videoId: id)
        if let text, !text.isEmpty { lyrics = text; lyricsState = .loaded }
        else {
            lyricsState = .none
            // Panel was open (previous track / clicked mid-load) but this song
            // has no lyrics — close it instead of showing a dead panel.
            if showLyrics {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showLyrics = false }
            }
        }
    }

    private func icon(_ name: String, size: CGFloat, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                .frame(width: 40, height: 40).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func fmt(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Writing-Tools-style AI skeleton: ghost text lines with an Apple
/// Intelligence-colored shimmer sweeping through while the model generates.
private struct AISkeletonLines: View {
    @State private var phase: CGFloat = -0.7
    // Varying line widths so it reads as stanzas, not a table.
    private let widths: [CGFloat] = [0.82, 0.64, 0.9, 0.55, 0, 0.76, 0.6, 0.86, 0.5, 0, 0.7, 0.8, 0.58]

    var body: some View {
        GeometryReader { geo in
            lines(width: geo.size.width)
                .overlay {
                    LinearGradient(
                        colors: [.clear, Color.pink.opacity(0.85), Color.purple.opacity(0.85),
                                 Color.orange.opacity(0.7), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: geo.size.width * phase)
                        .mask(lines(width: geo.size.width))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }

    private func lines(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                if w == 0 {
                    Spacer().frame(height: 6)   // stanza gap
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.14))
                        .frame(width: width * w, height: 13)
                }
            }
        }
    }
}
