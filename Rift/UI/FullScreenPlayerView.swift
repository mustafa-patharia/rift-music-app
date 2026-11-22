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
    @AppStorage(NowPlayingStyle.storageKey) private var style: NowPlayingStyle = .artwork
    @State private var scrubValue: Double = 0
    @State private var scrubbing = false
    @State private var showLyrics = false
    @State private var lyrics: String?
    /// Time-stamped lines (LRCLIB) — when present the panel follows playback.
    @State private var synced: [LyricLine]?
    @State private var lyricsState: LyricsState = .idle
    // AI lyric views (local model via AI facade) — cached per track.
    private enum LyricsDisplay: Equatable { case original, script(LyricScript) }
    @State private var display: LyricsDisplay = .original
    /// Sing-along rewrites, line-for-line with `sourceLines`, per script.
    @State private var scripted: [LyricScript: [String]] = [:]
    @State private var aiWorking = false
    /// Last AI failure, shown under the lyrics header until the next try.
    @State private var aiError: String?
    /// Pointer offset from the poster's centre, -0.5…0.5 per axis. Drives the
    /// parallax tilt; .zero is flat.
    @State private var tilt: CGSize = .zero

    private enum LyricsState: Equatable { case idle, loading, none, loaded }

    private var isLiked: Bool { player.track.map { likes.isLiked($0.id) } ?? false }

    var body: some View {
        // TRANSPARENT — no background of its own. The shared ambient album-art bg
        // lives in ContentView (behind everything) and never moves; the home list
        // just hides while this shows. One shared bg, two swapping foregrounds.
        VStack(spacing: 0) {
            topBar
            // Everything below scales with the window instead of using fixed
            // point sizes — at the 875×600 minimum the old 460pt columns and
            // 60pt gutters overflowed the content column.
            GeometryReader { geo in
                let tight = geo.size.width < 720
                let column = min(460, geo.size.width * 0.44)
                // Side-by-side needs ~300pt for the transport row plus a readable
                // lyrics column. Below that, lyrics take over the column (Apple
                // Music's small-window layout) instead of overlapping the poster.
                if showLyrics && geo.size.width < 680 {
                    stackedLyrics
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: tight ? 20 : 40) {
                        nowPlaying
                            .frame(maxWidth: showLyrics ? column : .infinity)
                        if showLyrics { lyricsPanel.frame(maxWidth: column) }
                    }
                    .padding(.horizontal, tight ? 24 : 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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

    // Narrow layout: small art + title on top, lyrics fill, transport below.
    private var stackedLyrics: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Artwork(url: player.track?.artworkURL, size: 56)
                    .clipShape(.rect(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.track?.title ?? "—").font(.headline).lineLimit(1)
                    Text(player.track?.artist ?? "").font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                lyricsAIMenu
            }
            .padding(.top, 16)
            lyricsBody
            scrubber
            transport(roomy: false).padding(.bottom, 20)
        }
    }

    // MARK: now playing column
    private var nowPlaying: some View {
        // Poster is a share of the column, not a fixed 340pt: capped at 340 so
        // big windows look unchanged, and bounded by a fraction of the available
        // HEIGHT so a short window still fits title + scrubber + transport below
        // it. 0.4 (not 0.5) — at 0.5 the stack exactly filled the column, which
        // collapsed the centring Spacers and left the transport on the edge.
        GeometryReader { geo in
            let poster = min(340, min(geo.size.width, geo.size.height * 0.4))
            let roomy = poster > 220

            VStack(spacing: roomy ? 28 : 16) {
                Spacer(minLength: 0)
                if style == .record {
                    RecordPlayerView(url: player.track?.artworkURL, height: poster,
                                     maxWidth: geo.size.width, isPlaying: player.isPlaying)
                } else {
                Artwork(url: player.track?.artworkURL, size: poster)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                    .scaleEffect(player.isPlaying ? 1 : 0.94)
                    // Parallax: the poster tilts toward the cursor. `tilt` is the
                    // pointer's offset from centre, normalised to -0.5…0.5 on each
                    // axis, so the effect is identical at every poster size.
                    .rotation3DEffect(.degrees(Double(tilt.height) * -10),
                                      axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(Double(tilt.width) * 10),
                                      axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: player.isPlaying)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: tilt)
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let p):
                            tilt = CGSize(width: (p.x / poster) - 0.5,
                                          height: (p.y / poster) - 0.5)
                        case .ended:
                            tilt = .zero   // settle back to flat on exit
                        }
                    }
                }

                VStack(spacing: 6) {
                    Text(player.track?.title ?? "—")
                        .font(.system(size: roomy ? 26 : 20, weight: .bold))
                        .lineLimit(2).multilineTextAlignment(.center)
                    Text(player.track?.artist ?? "")
                        .font(roomy ? .title3 : .subheadline).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)

                scrubber
                transport(roomy: roomy)
                Spacer(minLength: 0)
            }
            // Hard floor under the transport: the Spacers above centre the stack
            // when there's room, but they collapse to 0 once content fills the
            // column — this keeps the buttons off the window edge regardless.
            .padding(.bottom, roomy ? 28 : 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var scrubber: some View {
        let dur = max(player.duration, 0.01)
        return VStack(spacing: 4) {
            Slider(value: $scrubValue, in: 0...dur) { editing in
                scrubbing = editing
                if !editing { player.seek(to: scrubValue) }
            }
            // A restored session sets currentTime before this view exists, so
            // onChange alone would leave the knob parked at 0.
            .onAppear { scrubValue = min(player.currentTime, dur) }
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

    // Sized off the same `roomy` flag as the poster: at full width this is the
    // original 34pt/68pt layout, in a narrow column it tightens instead of
    // overflowing (the row is ~364pt fixed otherwise).
    private func transport(roomy: Bool) -> some View {
        HStack(spacing: roomy ? 34 : 18) {
            icon("shuffle", size: 18, active: player.isShuffled) { player.toggleShuffle() }
            icon("backward.fill", size: 24) { player.previous() }
                .disabled(!player.hasPrevious && player.currentTime <= 3)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: roomy ? 68 : 52)).symbolRenderingMode(.hierarchical)
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
            lyricsBody
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 40)
    }

    private var lyricsBody: some View {
            Group {
                switch lyricsState {
                case .loading: ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
                case .none, .idle:
                    Text("No lyrics available").foregroundStyle(.secondary).padding(.top, 40)
                case .loaded:
                    VStack(alignment: .leading, spacing: 8) {
                        if let aiError {
                            Label(aiError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if aiWorking {
                            // Writing-Tools-style shimmer while the model generates.
                            AISkeletonLines().padding(.top, 10)
                        } else if let lines = displayedSynced {
                            SyncedLyricsView(lines: lines, time: player.currentTime) { player.seek(to: $0) }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var displayedLyrics: String {
        switch display {
        case .original:  return lyrics ?? ""
        case .script(let s): return scripted[s]?.joined(separator: "\n") ?? lyrics ?? ""
        }
    }

    /// The lines a sing-along rewrite maps onto: synced lines when timed, so
    /// the rewrite keeps every timestamp; otherwise the plain text's lines.
    private var sourceLines: [String] {
        synced?.map(\.text) ?? (lyrics ?? "").components(separatedBy: "\n")
    }

    /// Synced lines in the current view's script; nil → show static text.
    private var displayedSynced: [LyricLine]? {
        guard let lines = synced else { return nil }
        switch display {
        case .original: return lines
        case .script(let s): return aligned(scripted[s], to: lines)
        }
    }

    private func aligned(_ texts: [String]?, to lines: [LyricLine]) -> [LyricLine]? {
        guard let texts, texts.count == lines.count else { return nil }
        return zip(lines, texts).map { LyricLine(time: $0.time, text: $1) }
    }

    // AI lyric controls (local model, per Settings), hidden until a provider
    // is enabled:
    //  • mic — "Sing along": the same words rewritten in a script the
    //    listener reads (phonetic, never translated)
    @ViewBuilder private var lyricsAIMenu: some View {
        if lyricsState == .loaded, let text = lyrics, ai.isReady {
            let source = LyricScript.dominant(in: text)
            let singing: Bool = { if case .script = display { return true }; return false }()
            Menu {
                Section("Sing along in") {
                    Button { display = .original } label: { check("Original script", !singing) }
                    ForEach(LyricScript.allCases.filter { !$0.isSource(of: source) }) { s in
                        Button { switchTo(.script(s)) } label: { check(s.label, display == .script(s)) }
                    }
                }
            } label: {
                aiCapsule("music.mic", active: singing)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            // borderlessButton drops the label's background — redraw it here.
            .frame(width: 34, height: 26)
            .background(.ultraThinMaterial, in: .capsule)
            .help("Sing along — same words in a script you can read")
            .accessibilityLabel("Sing along script")

            .disabled(aiWorking)
        }
    }

    // Icon never disappears — it pulses while the model works.
    private func aiCapsule(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
            .symbolEffect(.pulse, options: .repeating, isActive: aiWorking)
            .frame(width: 34, height: 26)
            .background(.ultraThinMaterial, in: .capsule)
            .contentShape(.capsule)
    }

    private func check(_ title: String, _ on: Bool) -> Label<Text, Image> {
        Label(title, systemImage: on ? "checkmark" : "")
    }

    private func switchTo(_ target: LyricsDisplay) {
        // Cached → instant flip; otherwise run the model once and cache.
        let cached: Bool
        switch target {
        case .script(let s): cached = scripted[s] != nil
        case .original: cached = true
        }
        if cached { display = target; return }
        guard let trackId = player.track?.id else { return }
        let lines = sourceLines
        aiWorking = true; aiError = nil
        Task {
            defer { aiWorking = false }
            do {
                switch target {
                case .script(let s):
                    let r = try await AI.transliterate(lines, into: s)
                    guard player.track?.id == trackId else { return }
                    scripted[s] = r
                case .original: break
                }
                display = target
            } catch {
                guard player.track?.id == trackId else { return }
                aiError = "Couldn't reach the AI model — \(error.localizedDescription)"
            }
        }
    }

    private func loadLyrics() async {
        guard let track = player.track, URL(string: track.id)?.isFileURL != true else {
            lyricsState = .none; lyrics = nil; synced = nil; scripted = [:]; aiError = nil; display = .original; return
        }
        scripted = [:]; aiError = nil; display = .original
        lyricsState = .loading; lyrics = nil; synced = nil
        // Every source in order (YTM timed → LRCLIB → official audio → plain).
        let found = await SyncedLyrics.resolve(track,
            duration: track.duration ?? (player.duration > 0 ? player.duration : nil))
        guard player.track?.id == track.id else { return }   // skipped mid-load
        synced = found?.lines
        if let t = found?.text, !t.isEmpty { lyrics = t; lyricsState = .loaded }
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


/// Line-synced lyrics: the sung line is large and bright, neighbours shrink
/// and fade with distance, and the view keeps the active line in the upper
/// third as the song plays. Click a line to jump there.
private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let time: TimeInterval
    let seek: (TimeInterval) -> Void

    // Lyrics stamps mark the line START; nudging forward feels on-beat
    // given the web player's time-update latency.
    private var active: Int? { SyncedLyrics.activeIndex(in: lines, at: time + 0.25) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        row(line, distance: active.map { abs(i - $0) } ?? 99, isActive: i == active)
                            .id(i)
                            .onTapGesture { seek(line.time) }
                    }
                }
                .padding(.vertical, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Soft fade at the top and bottom edges.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.85),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: active) { _, i in
                guard let i else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                    proxy.scrollTo(i, anchor: UnitPoint(x: 0, y: 0.35))
                }
            }
            .onAppear { if let i = active { proxy.scrollTo(i, anchor: UnitPoint(x: 0, y: 0.35)) } }
        }
    }

    private func row(_ line: LyricLine, distance: Int, isActive: Bool) -> some View {
        let text = line.text.isEmpty ? "♪" : line.text
        return Text(text)
            .font(.system(size: isActive ? 26 : 19, weight: isActive ? .bold : .semibold))
            .foregroundStyle(.white.opacity(isActive ? 1 : max(0.18, 0.5 - Double(distance) * 0.08)))
            .blur(radius: isActive ? 0 : min(Double(distance) * 0.35, 1.5))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isActive)
    }
}
