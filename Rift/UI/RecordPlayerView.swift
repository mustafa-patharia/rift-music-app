// SPDX-License-Identifier: GPL-3.0-only
//
// RecordPlayerView — optional Now Playing style (Settings → Playback → Now
// Playing style): the cover becomes the label of a spinning record on a
// turntable — no deck box, just the record on the ambient background, with a
// tonearm on a base plate that drops on while playing and lifts off when paused.

import SwiftUI

enum NowPlayingStyle: String, CaseIterable, Identifiable {
    case artwork, record
    var id: String { rawValue }
    var label: String { self == .artwork ? "Artwork" : "Record Player" }
    static let storageKey = "nowPlayingStyle"
}

struct RecordPlayerView: View {
    let url: URL?
    /// Record diameter target; shrinks to fit `maxWidth` with the tonearm.
    let height: CGFloat
    let maxWidth: CGFloat
    let isPlaying: Bool

    // Spin is accumulated so pause → play continues from the same angle.
    @State private var baseAngle: Double = 0
    @State private var spinStart: Date?
    // Slower than a real 33⅓ rpm (200°/s), which read as frantic on screen.
    private let degreesPerSecond = 60.0    // 10 rpm

    // Tonearm overhangs the record's right edge by ~22% of the diameter.
    private var disc: CGFloat { min(height, maxWidth / 1.22) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            record
                .frame(width: disc, height: disc)
                .frame(maxWidth: .infinity, alignment: .leading)
            tonearm
        }
        .frame(width: disc * 1.22, height: disc)
        .onAppear { if isPlaying { spinStart = Date() } }
        .onChange(of: isPlaying) { _, playing in
            if playing { spinStart = Date() }
            else if let s = spinStart { baseAngle += Date().timeIntervalSince(s) * degreesPerSecond; spinStart = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Record spinning" : "Record paused")
    }

    private var record: some View {
        TimelineView(.animation(paused: !isPlaying)) { ctx in
            let angle = baseAngle + (spinStart.map { ctx.date.timeIntervalSince($0) } ?? 0) * degreesPerSecond
            ZStack {
                // Vinyl with grooves.
                Canvas { g, size in
                    let r = size.width / 2
                    let c = CGPoint(x: r, y: r)
                    g.fill(Circle().path(in: CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.06)))
                    var rr = r * 0.97
                    while rr > r * 0.42 {
                        let rect = CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)
                        g.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.045)), lineWidth: 0.6)
                        rr -= r * 0.035
                    }
                }
                // Label = album art.
                Artwork(url: url, size: disc * 0.4, circle: true)
                    .clipShape(.circle)
                Circle().fill(Color(white: 0.85)).frame(width: disc * 0.035)   // spindle
            }
            .rotationEffect(.degrees(angle))
            // Fixed sheen (doesn't rotate) sells the spin.
            .overlay(
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.10), .clear, .clear,
                                                      .white.opacity(0.07), .clear],
                                              center: .center))
                    .blendMode(.screen)
            )
        }
        .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
    }

    // Pivot sits top-right of the platter; the arm swings onto the record.
    private var tonearm: some View {
        let len = disc * 0.62
        let arm = ZStack(alignment: .top) {
            Capsule().fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.68)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: disc * 0.036, height: len)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.88))
                .frame(width: disc * 0.07, height: disc * 0.11)
                .offset(y: len - disc * 0.02)
            Circle().fill(Color(white: 0.8))
                .overlay(Circle().fill(Color(white: 0.55)).padding(disc * 0.025))
                .frame(width: disc * 0.11)
                .offset(y: -disc * 0.04)
        }
        .rotationEffect(.degrees(isPlaying ? 24 : 4), anchor: UnitPoint(x: 0.5, y: 0))
        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: isPlaying)
        .shadow(color: .black.opacity(0.4), radius: 5, x: 2, y: 4)

        // Base plate the pivot sits on, so the arm reads as mounted.
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: disc * 0.045)
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: disc * 0.045)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .frame(width: disc * 0.2, height: disc * 0.2)
                .offset(y: -disc * 0.1)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            arm
        }
        .padding(.top, disc * 0.12)
        .padding(.trailing, disc * 0.04)
    }
}
