// SPDX-License-Identifier: GPL-3.0-only
//
// NowPlayingBar — the floating glass "pill" transport (ref: detached rounded
// player bar). RESPONSIVE: as the pill narrows it sheds elements by priority
// (play/pause never drops; queue icon + volume drop first). Volume is a
// horizontal slider when there's room, a vertical popover when it's tight.
//
// Priority kept longest → dropped first:
//   play/pause > poster > name > prev/next > time > repeat/shuffle
//   > volume (horizontal→vertical→hidden) > queue icon

import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var ui: UIState
    @Binding var showQueue: Bool

    @ObservedObject private var likes = LikeStore.shared

    @State private var scrubValue: Double = 0
    @State private var scrubbing = false

    // Must match PlayerPanelController: the panel is `pillHeight + headroom` tall;
    // the pill sits at the bottom.
    private let pillHeight: CGFloat = 124

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Breakpoints (pill content width). Each element appears above its width.
            // Volume control removed (owner's call) — media keys + Settings cover it.
            // 320, not 620: the elapsed/total label used to sit in this row next
            // to the heart (~67pt incl. spacing) and now lives under the scrubber,
            // so the queue icon fits at a correspondingly narrower pill.
            let showQueueIcon = w >= 320
            let showExtras    = w >= 470   // shuffle + repeat
            let showTime      = w >= 400
            let showSkip      = w >= 340   // prev / next
            let showName      = w >= 250
            let showPoster    = w >= 190

            pill(w: w, showQueueIcon: showQueueIcon,
                 showExtras: showExtras, showTime: showTime, showSkip: showSkip,
                 showName: showName, showPoster: showPoster)
                .frame(height: pillHeight)
                .frame(width: w, height: geo.size.height, alignment: .bottom)
        }
    }

    private func pill(w: CGFloat, showQueueIcon: Bool,
                      showExtras: Bool, showTime: Bool, showSkip: Bool,
                      showName: Bool, showPoster: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                left(showPoster: showPoster, showName: showName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                transport(showExtras: showExtras, showSkip: showSkip)
                right(showQueueIcon: showQueueIcon)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            scrubber(showTime: showTime)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(width: w, height: pillHeight)
        .liquidGlass(in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    // MARK: left — artwork + title
    private func left(showPoster: Bool, showName: Bool) -> some View {
        HStack(spacing: 11) {
            if showPoster { Artwork(url: player.track?.artworkURL, size: 46) }
            if showName {
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.track?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {   // open the full-screen Now Playing
            guard player.track != nil else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { ui.showFullPlayer = true }
        }
        .help("Open full player")
    }

    // MARK: center — transport
    private func transport(showExtras: Bool, showSkip: Bool) -> some View {
        HStack(spacing: 16) {
            if showExtras {
                iconButton("shuffle", active: player.isShuffled) { player.toggleShuffle() }
            }
            if showSkip {
                iconButton("backward.fill", size: 15) { player.previous() }
                    .disabled(!player.hasPrevious && player.currentTime <= 3)
            }
            Button { isErrored ? player.retry() : player.togglePlayPause() } label: {
                Image(systemName: centerIcon)
                    .font(.system(size: 38)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isErrored ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            .buttonStyle(.plain)
            .help(isErrored ? "Playback failed — tap to retry" : "")
            if showSkip {
                iconButton("forward.fill", size: 15) { player.next() }
                    .disabled(!player.hasNext)
            }
            if showExtras {
                iconButton(repeatIcon, active: player.repeatMode != .off) { player.cycleRepeat() }
            }
        }
        .foregroundStyle(.primary)
        .fixedSize()
    }

    // MARK: right — like, queue
    // Elapsed/duration used to live here as one "1:17 / 4:01" label; it now sits
    // under the scrubber, split to the two ends (see `scrubber`).
    private func right(showQueueIcon: Bool) -> some View {
        HStack(spacing: 12) {
            if let t = player.track {
                iconButton(likes.isLiked(t.id) ? "heart.fill" : "heart",
                           active: likes.isLiked(t.id), activeColor: .red) { likes.toggle(t) }
                    .help(likes.isLiked(t.id) ? "Remove from Liked" : "Like")
            }
            if showQueueIcon {
                iconButton("sidebar.right", active: showQueue) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showQueue.toggle() }
                }
            }
        }
    }

    private func scrubber(showTime: Bool) -> some View {
        let dur = max(player.duration, 0.01)
        return VStack(spacing: 2) {
            Slider(value: $scrubValue, in: 0...dur) { editing in
                scrubbing = editing
                if !editing { player.seek(to: scrubValue) }
            }
            .tint(.riftAccent)
            // onAppear too: a restored (resume-on-launch) session sets currentTime
            // BEFORE this view exists, so onChange alone leaves the knob at 0.
            .onAppear { scrubValue = min(player.currentTime, dur) }
            .onChange(of: player.currentTime) { _, t in if !scrubbing { scrubValue = min(t, dur) } }
            .onChange(of: player.track?.id) { _, _ in scrubValue = 0 }

            // Elapsed left, total right — same layout as the full player.
            if showTime {
                HStack(spacing: 0) {
                    Text(fmt(scrubbing ? scrubValue : player.currentTime))
                    Spacer(minLength: 8)
                    Text(fmt(player.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func iconButton(_ name: String, size: CGFloat = 14, active: Bool = false,
                            activeColor: Color? = nil,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active
                    ? (activeColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
                    : AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var isErrored: Bool { if case .error = player.state { return true }; return false }
    private var centerIcon: String {
        if isErrored { return "arrow.clockwise.circle.fill" }
        return player.isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }
    private var repeatIcon: String { player.repeatMode == .one ? "repeat.1" : "repeat" }

    private var status: String {
        switch player.state {
        case .loading: return "Loading…"
        case .paused:  return "Paused"
        case .ended:   return "Ended"
        case .error: return "Couldn't play — tap ↻ to retry"
        default: return player.track?.artist ?? ""
        }
    }

    private func fmt(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Preview
#if DEBUG
import Combine

/// Stub source so the canvas can show a mid-track playing state — the
/// controller's track/time/duration are `private(set)` and only move when a
/// PlaybackSource publishes.
@MainActor
private final class PreviewSource: PlaybackSource {
    let stateSubject = CurrentValueSubject<PlaybackState, Never>(.playing)
    let timeSubject = CurrentValueSubject<TimeInterval, Never>(77)
    let durationSubject = CurrentValueSubject<TimeInterval, Never>(212)
    var state: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTime: AnyPublisher<TimeInterval, Never> { timeSubject.eraseToAnyPublisher() }
    var duration: AnyPublisher<TimeInterval, Never> { durationSubject.eraseToAnyPublisher() }
    func load(_ track: PlayableTrack) {}
    func play() { stateSubject.send(.playing) }
    func pause() { stateSubject.send(.paused) }
    func seek(to seconds: TimeInterval) { timeSubject.send(seconds) }
    func setVolume(_ volume: Double) {}
}

#Preview("NowPlayingBar") {
    let source = PreviewSource()
    let player = PlayerController(source: source)
    player.play(PlayableTrack(id: "preview", title: "Midnight Rift",
                              artist: "The Placeholders", artworkURL: nil, duration: 212))
    source.durationSubject.send(212)
    source.timeSubject.send(77)
    source.stateSubject.send(.playing)

    return NowPlayingBar(showQueue: .constant(false))
        .frame(width: 680, height: 140)
        .padding(24)
        .background(.black)
        .environmentObject(player)
        .environmentObject(UIState())
}
#endif

