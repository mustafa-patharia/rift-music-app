// SPDX-License-Identifier: GPL-3.0-only
//
// CompactPlayerView — the shared mini now-playing surface used by both the
// menu-bar popover and the expanded notch. Binds the same PlayerController as
// the main window; no engine knowledge. `dark` forces light-on-dark styling for
// the notch (which sits on black); the popover uses default material styling.

import AppKit
import SwiftUI

struct CompactPlayerView: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var likes = LikeStore.shared
    var dark: Bool = false
    var width: CGFloat = 300   // notch passes its own (tighter) width

    @State private var scrubValue: Double = 0
    @State private var scrubbing = false

    var body: some View {
        // Per-gap paddings (not one VStack spacing) so each gap tunes alone.
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.track?.title ?? "Nothing playing")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let t = player.track {
                    glassButton(likes.isLiked(t.id) ? "heart.fill" : "heart",
                                diameter: 26, font: .footnote) { likes.toggle(t) }
                        .foregroundStyle(likes.isLiked(t.id)
                                         ? AnyShapeStyle(.red)
                                         : AnyShapeStyle(dark ? Color.white : Color.primary))
                        .help(likes.isLiked(t.id) ? "Remove from Liked" : "Like")
                }
                glassButton("arrow.up.forward.app", diameter: 26, font: .footnote) { openMainApp() }
                    .help("Open Rift")
            }
            scrubber.padding(.top, 14)   // poster row ↔ scrubber
            controls.padding(.top, 6)    // scrubber ↔ buttons
        }
        .padding(12)   // uniform — keeps card insets symmetric on every side
        .frame(width: width)
        .foregroundStyle(dark ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }

    private var artwork: some View {
        AsyncImage(url: player.track?.artworkURL) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var subtitle: String {
        switch player.state {
        case .loading: return "Loading…"
        case .error(let m): return "Error: \(m)"
        default: return player.track?.artist ?? ""
        }
    }

    private var controls: some View {
        LiquidGlassContainer {
            HStack(spacing: 14) {
                glassButton("shuffle", diameter: 28, font: .footnote) { player.toggleShuffle() }
                    .foregroundStyle(activeStyle(player.isShuffled))
                glassButton("backward.fill", diameter: 34) { player.previous() }
                    .disabled(!player.hasPrevious && player.currentTime <= 3)
                glassButton(player.isPlaying ? "pause.fill" : "play.fill",
                            diameter: 44, font: .title2) { player.togglePlayPause() }
                glassButton("forward.fill", diameter: 34) { player.next() }
                    .disabled(!player.hasNext)
                glassButton(player.repeatMode == .one ? "repeat.1" : "repeat",
                            diameter: 28, font: .footnote) { player.cycleRepeat() }
                    .foregroundStyle(activeStyle(player.repeatMode != .off))
            }
        }
        .disabled(player.track == nil)
    }

    private func activeStyle(_ active: Bool) -> AnyShapeStyle {
        active ? AnyShapeStyle(.tint) : AnyShapeStyle(dark ? Color.white : Color.primary)
    }

    private func glassButton(_ symbol: String, diameter: CGFloat, font: Font = .body,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(font)
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .liquidGlass(true, in: .circle)
    }

    private var scrubber: some View {
        let dur = max(player.duration, 0.01)
        return VStack(spacing: 2) {
            Slider(value: $scrubValue, in: 0...dur) { editing in
                scrubbing = editing
                if !editing { player.seek(to: scrubValue) }
            }
            .controlSize(.mini)
            .onChange(of: player.currentTime) { _, t in if !scrubbing { scrubValue = min(t, dur) } }
            .onChange(of: player.track?.id) { _, _ in scrubValue = 0 }
            HStack {
                Text(fmt(scrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(fmt(player.duration))
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .disabled(player.track == nil)
    }

    // Bring the main window forward. The WindowGroup window survives closing
    // (SwiftUI keeps it in NSApp.windows), so ordering it front is enough;
    // panels (notch, menu-bar popover) are skipped.
    private func openMainApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) && $0.contentView != nil }?
            .makeKeyAndOrderFront(nil)
    }

    private func fmt(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
