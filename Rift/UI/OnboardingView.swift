// SPDX-License-Identifier: GPL-3.0-only
//
// OnboardingView — first-launch feature showcase in the shape macOS apps use:
// a paged flow with one idea per page, an oversized animated illustration, and
// a single forward button. Shown once (gated by @AppStorage in ContentView);
// signing in reuses the existing GoogleSignInView sheet, so this view only
// decides whether to open it.
//
// Every illustration is drawn in SwiftUI — no bundled screenshots or image
// assets, so the art stays sharp at any size, follows the accent colour, and
// costs nothing in the app bundle.
//
// Motion rules this file follows (ui-ux-pro-max: Animation / Accessibility):
//   · Each page plays ONE staged reveal on appear, then rests. Looping
//     decoration is an anti-pattern — the only continuous motion here is the
//     equaliser, which is state, not ornament.
//   · Springs for anything that travels (arrival should overshoot slightly);
//     eased fades for opacity-only changes.
//   · Reduce Motion collapses every stage to the finished pose instantly.

import SwiftUI
import AppKit

struct OnboardingView: View {
    @EnvironmentObject var auth: AuthController
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let lastPage = 4

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            AmbientWash().ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    ForEach(0...lastPage, id: \.self) { index in
                        if page == index { pageContent(index).transition(pageTransition) }
                    }
                }
                .frame(maxWidth: 560)

                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: page)
    }

    // MARK: pages

    @ViewBuilder
    private func pageContent(_ index: Int) -> some View {
        switch index {
        case 0:
            Page(art: { WelcomeArt(reduceMotion: reduceMotion) },
                 title: "Welcome to Rift",
                 body: "A native macOS player for YouTube Music — its catalogue and recommendations, in an app that belongs on your Mac.")
        case 1:
            Page(art: { NotchArt(reduceMotion: reduceMotion) },
                 title: "Lives in the notch",
                 body: "Now playing peeks out of the notch while the music runs. Hover to expand into full transport — or switch it to a menu-bar player instead.")
        case 2:
            Page(art: { OfflineArt(reduceMotion: reduceMotion) },
                 title: "Take it offline",
                 body: "Download any track, album or playlist and it plays with the network off — alongside your own local files in one library.")
        case 3:
            Page(art: { LyricsArt(reduceMotion: reduceMotion) },
                 title: "Lyrics that make sense",
                 body: "Read along in the full-screen player, and turn other-language lyrics into something you can sing — processed on your Mac, off by default.")
        default:
            SignInPage(auth: auth, onDone: onDone)
        }
    }

    // MARK: chrome

    private var footer: some View {
        VStack(spacing: 18) {
            // Progress only — the last page is the end of the flow, so dots
            // there would indicate progress that no longer exists.
            if page < lastPage {
                HStack(spacing: 7) {
                    ForEach(0...lastPage, id: \.self) { index in
                        Button { page = index } label: {
                            Circle()
                                .fill(index == page ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                                .frame(width: 7, height: 7)
                                .contentShape(.rect.inset(by: -6))   // easier hit target
                        }
                        .buttonStyle(.plain)
                        .help("Go to step \(index + 1)")
                    }
                }
            }

            if page < lastPage {
                Button {
                    page += 1
                } label: {
                    Text("Continue").frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Skip") { page = lastPage }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 40)),
            removal: .opacity.combined(with: .offset(x: -40))
        )
    }
}

// MARK: - Page scaffold

private struct Page<Art: View>: View {
    @ViewBuilder var art: Art
    let title: String
    let body_: String

    init(@ViewBuilder art: () -> Art, title: String, body: String) {
        self.art = art()
        self.title = title
        self.body_ = body
    }

    var body: some View {
        VStack(spacing: 34) {
            art.frame(height: 210)

            VStack(spacing: 10) {
                Text(title).font(.largeTitle.bold())
                Text(body_)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
        }
    }
}

private struct SignInPage: View {
    let auth: AuthController
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 10) {
                Text("Ready when you are").font(.largeTitle.bold())
                Text("Sign in to bring across your playlists, likes and recommendations — or start listening straight away.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 10) {
                Button {
                    onDone()
                    auth.signIn()
                } label: {
                    Text("Sign in with Google").frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Continue without signing in") { onDone() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Text("Not affiliated with, endorsed by, or connected to Google LLC / YouTube.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }
}

// MARK: - Brand palette
//
// The app icon is warm (ember orange → coral). The system accent colour is
// blue by default, which fought the artwork — so the onboarding art keys off
// these instead of `.accentColor`.

// Used only for the icon's own glow and the background wash — controls and
// status colours stay system-standard (accent / green).
private enum Ember {
    static let warm = Color(red: 0.96, green: 0.58, blue: 0.28)
    static let hot = Color(red: 0.87, green: 0.33, blue: 0.29)
}

// MARK: - Backdrop

private struct AmbientWash: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Ember.hot.opacity(0.13))
                .frame(width: 460)
                .blur(radius: 130)
                .offset(x: -160, y: -120)
            Circle()
                .fill(Ember.warm.opacity(0.10))
                .frame(width: 380)
                .blur(radius: 130)
                .offset(x: 180, y: 140)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Illustration 1 · welcome

private struct WelcomeArt: View {
    let reduceMotion: Bool
    @State private var arrived = false

    var body: some View {
        ZStack {
            // Warm bloom instead of concentric rings — the rings read as a
            // cold "signal" motif and clashed with the ember artwork.
            Circle()
                .fill(RadialGradient(colors: [Ember.hot.opacity(0.55), .clear],
                                     center: .center, startRadius: 10, endRadius: 130))
                .frame(width: 300, height: 300)
                .blur(radius: 26)
                .scaleEffect(arrived ? 1 : 0.7)
                .opacity(arrived ? 1 : 0)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 118, height: 118)
                .shadow(color: Ember.hot.opacity(0.45), radius: 30, y: 10)
                .scaleEffect(arrived ? 1 : 0.86)
                .opacity(arrived ? 1 : 0)
        }
        .onAppear { play(reduceMotion, $arrived, .bouncy(duration: 0.65)) }
    }
}

/// Shared one-shot reveal: settle straight into the finished pose when Reduce
/// Motion is on, otherwise run the given animation once.
private func play(_ reduceMotion: Bool, _ flag: Binding<Bool>,
                  _ animation: Animation, delay: Double = 0) {
    guard !reduceMotion else { flag.wrappedValue = true; return }
    withAnimation(animation.delay(delay)) { flag.wrappedValue = true }
}

// MARK: - Illustration 2 · the notch

private struct NotchArt: View {
    let reduceMotion: Bool
    @State private var expanded = false
    @State private var detailsIn = false

    var body: some View {
        VStack(spacing: 0) {
            // The lid: black notch shape hanging off the top edge of a "screen".
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))

                ZStack {
                    UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                        .fill(.black)
                        .frame(width: expanded ? 250 : 150, height: expanded ? 62 : 30)

                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: [.orange, .pink],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: expanded ? 34 : 20, height: expanded ? 34 : 20)

                        if detailsIn {
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(.white.opacity(0.85)).frame(width: 78, height: 6)
                                Capsule().fill(.white.opacity(0.4)).frame(width: 52, height: 5)
                            }
                            .transition(.opacity.combined(with: .offset(x: -6)))
                        }

                        // Continuous by design: the equaliser reports playback
                        // state, it isn't decoration.
                        EqualizerBars(reduceMotion: reduceMotion)
                            .frame(width: 22, height: expanded ? 26 : 16)
                    }
                    .padding(.horizontal, 14)
                }
            }
            .frame(height: 150)

            // The lid's base, so the notch reads as a MacBook screen.
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.14))
                .frame(width: 300, height: 6)
        }
        .onAppear {
            // Stage 1: the pill widens out of the notch. Stage 2: its contents
            // arrive, once the space exists to hold them.
            play(reduceMotion, $expanded, .spring(response: 0.55, dampingFraction: 0.72), delay: 0.35)
            play(reduceMotion, $detailsIn, .easeOut(duration: 0.25), delay: 0.72)
        }
    }
}

private struct EqualizerBars: View {
    let reduceMotion: Bool
    @State private var tall = false

    private let heights: [CGFloat] = [0.45, 1.0, 0.65]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 3,
                               height: geo.size.height * (tall ? heights[index] : 0.3))
                        .animation(reduceMotion ? nil
                                   : .easeInOut(duration: 0.42).repeatForever(autoreverses: true)
                                       .delay(Double(index) * 0.14),
                                   value: tall)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { tall = true }
    }
}

// MARK: - Illustration 3 · offline

private struct OfflineArt: View {
    let reduceMotion: Bool
    @State private var rowsIn = false
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 8)

            VStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { row in
                    // Each row's ring fills a beat after the one above it, so
                    // the download reads as a queue working through itself.
                    let fill = min(max(progress - CGFloat(row) * 0.3, 0), 1)

                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: [.orange.opacity(0.9), .pink.opacity(0.75)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(.primary.opacity(0.55)).frame(width: 120, height: 6)
                            Capsule().fill(.primary.opacity(0.22)).frame(width: 74, height: 5)
                        }

                        Spacer(minLength: 26)

                        // Downloading: a white determinate ring filling round
                        // an unfilled track. Done: it swaps for the same badge
                        // the real library shows — white check on green.
                        let done = fill >= 1

                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 2)
                                .frame(width: 18, height: 18)
                                .opacity(done ? 0 : 1)
                            Circle()
                                .trim(from: 0, to: fill)
                                .stroke(.white, style: .init(lineWidth: 2, lineCap: .round))
                                .frame(width: 18, height: 18)
                                .rotationEffect(.degrees(-90))
                                .opacity(done ? 0 : 1)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(.white, .green)
                                .scaleEffect(done ? 1 : 0.4)
                                .opacity(done ? 1 : 0)
                        }
                        .animation(reduceMotion ? nil : .bouncy(duration: 0.36), value: done)
                    }
                    .opacity(rowsIn ? 1 : 0)
                    .offset(y: rowsIn ? 0 : 10)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.42, dampingFraction: 0.8)
                                   .delay(0.08 * Double(row)),
                               value: rowsIn)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            // Card is sized to its rows: stretched full-width it pushed the
            // status badges into the rounded corner.
            .fixedSize(horizontal: true, vertical: false)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .onAppear {
            rowsIn = true
            guard !reduceMotion else { progress = 1.6; return }
            // Linear: a determinate loader that eases would misreport its rate.
            withAnimation(.linear(duration: 2.2).delay(0.4)) { progress = 1.6 }
        }
    }
}

// MARK: - Illustration 4 · lyrics

private struct LyricsArt: View {
    let reduceMotion: Bool
    @State private var translated = false
    @State private var linesIn = false

    // Illustrative only — a line of Devanagari and its transliteration.
    private let original = ["तेरे इश्क़ में", "मैं डूब गया", "हर धड़कन में"]
    private let latin = ["Tere ishq mein", "Main doob gaya", "Har dhadkan mein"]

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(original.indices, id: \.self) { line in
                    Text(translated ? latin[line] : original[line])
                        .font(.system(size: line == 1 ? 21 : 17, weight: line == 1 ? .semibold : .regular))
                        .foregroundStyle(line == 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(linesIn ? 1 : 0)
                        .offset(y: linesIn ? 0 : 8)
                        .animation(reduceMotion ? nil
                                   : .spring(response: 0.4, dampingFraction: 0.85)
                                       .delay(0.09 * Double(line)),
                                   value: linesIn)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(width: 300, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 20))

            HStack(spacing: 7) {
                Image(systemName: "character.book.closed")
                    .font(.callout.weight(.bold))
                Text(translated ? "Hinglish" : "Original")
                    .contentTransition(.opacity)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .liquidGlass(in: Capsule())
            .scaleEffect(translated ? 1.04 : 1)
        }
        .onAppear {
            linesIn = true
            // One flip, not a loop — it shows what the control does, then stops.
            play(reduceMotion, $translated, .smooth(duration: 0.45), delay: 1.1)
        }
    }
}
