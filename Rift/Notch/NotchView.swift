// SPDX-License-Identifier: GPL-3.0-only
//
// NotchView — the SwiftUI content of the notch island. Collapsed it is a black
// notch-shaped pill that merges into the physical notch; on hover it expands
// into the compact player. Interaction is confined to the pill/card — the
// surrounding transparent margin isn't hit-testable, so hover only fires over
// the notch itself. Respects reduce-motion.
//
// Expand/collapse-on-hover behaviour follows Atoll / boring.notch (GPL-3.0);
// reimplemented against our PlayerController. See /NOTICE.

import SwiftUI

struct NotchView: View {
    @EnvironmentObject var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let notchSize: CGSize
    /// No camera housing behind it (non-notch Mac): the collapsed pill is the
    /// whole visible bar, so it gets softer, fully rounded bottom corners.
    var isVirtual = false
    let expandedSize: CGSize

    @State private var hovering = false

    // ── STYLING KNOBS — tune these ─────────────────────────────────────────
    // IMPORTANT geometry fact: NotchShape's body is INSET by topCornerRadius on
    // each side — only the top scoop "wings" reach the full frame width. So the
    // VISIBLE card body = frame width − 2 × openTopRadius. All math below is in
    // terms of the visible body; the frame adds the wing room automatically.
    private let bodyExtraWidth: CGFloat = 140   // visible card width beyond the physical notch
    private let openTopRadius: CGFloat = 20     // S-curve scoop size when open
    private let openBottomRadius: CGFloat = 35  // bottom corner rounding when open
    private let closedTopRadius: CGFloat = 6    // scoop when collapsed (merges with notch)
    private let closedBottomRadius: CGFloat = 14
    private let sideMargin: CGFloat = 10        // content inset from the visible card edges
    private let bottomMargin: CGFloat = 8
    private let glow: CGFloat = 0.4             // ambient artwork strength, 0…1
    private let peekSideWidth: CGFloat = 46     // closed-pill wing width per side while playing
    private let peekArtSize: CGFloat = 24       // artwork thumb in the left peek wing
    private let peekEdgeInset: CGFloat = 5      // nudge art/eq inward from the pill's outer edges

    // DEBUG: `NOTCH_FORCE_OPEN=1 Rift.app/Contents/MacOS/Rift` pins
    // the card open so it can be screenshotted/tuned without holding a hover.
    private var forcedOpen: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTCH_FORCE_OPEN"] == "1"
        #else
        false
        #endif
    }

    var body: some View {
        let open = hovering || forcedOpen
        let peeking = !open && player.isPlaying && player.track != nil
        // The virtual bar is shorter than a real notch: fit the thumb with an
        // even 4pt margin top and bottom instead of the fixed 24pt.
        let artSide = isVirtual ? max(notchSize.height - 8, 12) : peekArtSize
        // A virtual notch is ~half a real one; open the card as wide as on a
        // notch Mac (real notch ≈ 185pt) so the player isn't cramped.
        let bodyW = (isVirtual ? max(notchSize.width, 190) : notchSize.width) + bodyExtraWidth
        let w = open ? bodyW + openTopRadius * 2            // + scoop wings
              : peeking ? notchSize.width + peekSideWidth * 2
              : notchSize.width

        VStack(spacing: 0) {
            if open {
                CompactPlayerView(dark: true, width: bodyW - sideMargin * 2)
                    .environmentObject(player)
                    .padding(.top, notchSize.height)   // clear the camera housing
                    .padding(.bottom, bottomMargin)
                    .transition(.opacity)
            } else if peeking {
                // Peek while playing (Dynamic Island style): artwork left of
                // the camera housing, eq bars right. Same black pill, wider.
                HStack(spacing: 0) {
                    AsyncImage(url: player.track?.artworkURL) {
                        $0.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.clear }
                        .frame(width: artSide, height: artSide)
                        .clipShape(.rect(cornerRadius: 5))
                        .frame(width: peekSideWidth)
                        .offset(x: peekEdgeInset)               // slight breathing room from the left edge
                    Color.clear.frame(width: notchSize.width)   // the camera housing
                    EqBars(animated: !reduceMotion)
                        .frame(width: peekSideWidth)
                        .offset(x: -peekEdgeInset)              // …and from the right edge
                }
                .frame(height: notchSize.height)
                .transition(.opacity)
            } else {
                // Closed idle: plain black, merges with the physical notch.
                Color.clear.frame(height: notchSize.height)
            }
        }
        .frame(width: w)
        .background(
            // Black base always (must merge with the physical notch when closed).
            // The ambient artwork hangs off the shape as an .overlay — overlays
            // never affect layout. (Putting the AsyncImage as a ZStack SIBLING
            // let its aspect-fill size inflate the ZStack, which redrew the
            // NotchShape in a bigger rect and pushed the S-curve wings outside
            // the visible card. That bug cost a day — do not "simplify" back.)
            notchShape(open).fill(.black)
                .overlay {
                    if open, let art = player.track?.artworkURL {
                        // Ambient tint: blurred artwork under a top→bottom
                        // black→clear gradient — pure black up top (merges with
                        // the notch), artwork colour emerging at the bottom.
                        AsyncImage(url: art) { $0.resizable().aspectRatio(contentMode: .fill) }
                            placeholder: { Color.clear }
                            .blur(radius: 55).saturation(1.4).opacity(glow)
                            .overlay(
                                LinearGradient(colors: [.black, .black.opacity(0.6), .clear],
                                               startPoint: .top, endPoint: .bottom))
                            .transition(.opacity)
                    }
                }
                .clipShape(notchShape(open))
        )
        .clipShape(notchShape(open))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: open)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: peeking)
        // Transparent margin centers the pill under the notch and takes no hits.
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
    }

    private func notchShape(_ open: Bool) -> NotchShape {
        NotchShape(topCornerRadius: open ? openTopRadius : closedTopRadius,
                   bottomCornerRadius: open ? openBottomRadius
                                     : isVirtual ? notchSize.height / 2 : closedBottomRadius)
    }
}

/// Three bouncing equalizer bars for the playing peek. Static mid-height bars
/// when `animated` is false (reduce-motion).
private struct EqBars: View {
    var animated: Bool
    @State private var up = false

    private let tall: [CGFloat] = [10, 15, 8]
    private let short: [CGFloat] = [4, 6, 5]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(.white)
                    .frame(width: 2.5, height: barHeight(i))
                    .animation(animated
                        ? .easeInOut(duration: 0.35 + Double(i) * 0.12).repeatForever(autoreverses: true)
                        : nil, value: up)
            }
        }
        .onAppear { if animated { up = true } }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard animated else { return (tall[i] + short[i]) / 2 }
        return up ? tall[i] : short[i]
    }
}
