// SPDX-License-Identifier: GPL-3.0-only
//
// OnboardingView — the first-launch welcome. A cinematic opener (living ember
// aurora, the icon dropping in, the name writing itself), four feature
// chapters each with a live illustration of the real feature, and a sign-in
// finale. Shown once (gated by @AppStorage("hasOnboarded") in ContentView);
// Settings → About → "Replay Welcome Tour" brings it back. Signing in reuses
// the existing GoogleSignInView sheet, so this view only decides whether to
// open it.
//
// Every illustration is drawn in SwiftUI — no bundled screenshots or image
// assets, so the art stays sharp at any size and costs nothing in the bundle.
//
// Motion rules (ui-ux-pro-max: Animation / Accessibility):
//   · Each chapter plays a staged reveal on appear. Loops are reserved for
//     things that ARE motion — the aurora behind everything, the equaliser,
//     the sing-along script cycle (its point is showing many scripts).
//   · Springs for anything that travels; eased fades for opacity-only.
//   · Reduce Motion: every stage lands in its finished pose instantly and
//     every loop stops.
//   · ← / → (and Return) page through; one primary button per page.

import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var auth: AuthController
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var forward = true

    private enum Chapter: Int, CaseIterable { case hero, island, singAlong, yours, together, signIn }
    private var chapter: Chapter { Chapter(rawValue: page) ?? .hero }
    private let lastPage = Chapter.allCases.count - 1

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            Aurora(reduceMotion: reduceMotion, intensity: chapter == .hero || chapter == .signIn ? 1 : 0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    ForEach(Chapter.allCases, id: \.self) { c in
                        if chapter == c { content(c).transition(pageTransition) }
                    }
                }
                .frame(maxWidth: 720)
                Spacer(minLength: 0)
                if chapter != .hero && chapter != .signIn { footer }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)

            if chapter != .hero {
                Button { go(-1) } label: {
                    Label("Back", systemImage: "chevron.left").font(.callout.weight(.medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: page)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        page = min(max(page + delta, 0), lastPage)
    }

    // MARK: chapters

    @ViewBuilder
    private func content(_ c: Chapter) -> some View {
        switch c {
        case .hero:
            HeroPage(reduceMotion: reduceMotion) { go(1) }
        case .island:
            Chapter_(eyebrow: "Dynamic island", tint: .orange,
                     title: NotchDetector.hasNotch ? "Your notch, now a stage" : "A dynamic island on any Mac",
                     body: NotchDetector.hasNotch
                        ? "Now playing peeks out of the notch while the music runs. Hover, and it opens into the full player."
                        : "A slim black bar waits at the top of your screen. Hover, and it opens into the full player — no notch required.") {
                IslandArt(reduceMotion: reduceMotion)
            }
        case .singAlong:
            Chapter_(eyebrow: "Sing along", tint: .pink,
                     title: "Sing every word, in any script",
                     body: "Synced lyrics that keep time — and, with Apple Intelligence or your own AI key, the same words rewritten in letters you can read. Never translated, just sung.") {
                SingAlongArt(reduceMotion: reduceMotion)
            }
        case .yours:
            Chapter_(eyebrow: "Make it yours", tint: .purple,
                     title: "A library that looks like you",
                     body: "Give any playlist an emoji cover and colour. Download songs for offline. Put Now Playing on your desktop with the widget.") {
                CoversArt(reduceMotion: reduceMotion)
            }
        case .together:
            Chapter_(eyebrow: "Nearby", tint: .teal,
                     title: "Better with friends",
                     body: "Send the song you're playing to a Mac next to you, or listen together in perfect sync. Straight Mac to Mac — no account, no server.") {
                TogetherArt(reduceMotion: reduceMotion)
            }
        case .signIn:
            SignInPage(auth: auth, reduceMotion: reduceMotion, onDone: onDone)
        }
    }

    // MARK: chrome

    private var footer: some View {
        VStack(spacing: 18) {
            // Feature chapters only (1…4): the opener and finale are not steps.
            HStack(spacing: 6) {
                ForEach(1..<lastPage, id: \.self) { index in
                    Button { forward = index > page; page = index } label: {
                        Capsule()
                            .fill(index == page ? AnyShapeStyle(Ember.gradient) : AnyShapeStyle(.quaternary))
                            .frame(width: index == page ? 26 : 7, height: 7)
                            .contentShape(.rect.inset(by: -6))
                    }
                    .buttonStyle(.plain)
                    .help("Go to step \(index)")
                }
            }

            Button { go(1) } label: {
                Text(page == lastPage - 1 ? "Almost there" : "Continue").frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .background(Button("") { go(1) }.keyboardShortcut(.rightArrow, modifiers: []).hidden())

            Button("Skip") { forward = true; page = lastPage }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let dx: CGFloat = forward ? 60 : -60
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: dx)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .offset(x: -dx))
        )
    }
}

// MARK: - Brand palette
//
// The app icon is warm (ember orange → coral). The system accent varies per
// machine and fights the artwork, so the welcome art keys off these.

private enum Ember {
    static let warm = Color(red: 0.98, green: 0.60, blue: 0.27)
    static let hot = Color(red: 0.93, green: 0.30, blue: 0.33)
    static let rose = Color(red: 0.88, green: 0.32, blue: 0.62)
    static var gradient: LinearGradient {
        LinearGradient(colors: [warm, hot], startPoint: .leading, endPoint: .trailing)
    }
}

/// One-shot reveal: lands straight in the finished pose under Reduce Motion.
private func play(_ reduceMotion: Bool, _ flag: Binding<Bool>,
                  _ animation: Animation, delay: Double = 0) {
    guard !reduceMotion else { flag.wrappedValue = true; return }
    withAnimation(animation.delay(delay)) { flag.wrappedValue = true }
}

// MARK: - Backdrop

/// Slow-drifting ember blobs — the "living" light behind the whole flow.
private struct Aurora: View {
    let reduceMotion: Bool
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    blob(Ember.hot, size: w * 0.55, x: -w * 0.22 + sin(t / 7) * w * 0.06,
                         y: -h * 0.18 + cos(t / 9) * h * 0.06, opacity: 0.28)
                    blob(Ember.warm, size: w * 0.5, x: w * 0.25 + cos(t / 8) * w * 0.07,
                         y: h * 0.2 + sin(t / 6) * h * 0.05, opacity: 0.22)
                    blob(Ember.rose, size: w * 0.4, x: sin(t / 10) * w * 0.15,
                         y: h * 0.32 + cos(t / 11) * h * 0.04, opacity: 0.16)
                }
                .frame(width: w, height: h)
            }
        }
        .opacity(intensity)
        .animation(.smooth(duration: 0.8), value: intensity)
        .allowsHitTesting(false)
    }

    private func blob(_ c: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle().fill(c.opacity(opacity)).frame(width: size, height: size)
            .blur(radius: size * 0.28).offset(x: x, y: y)
    }
}

// MARK: - Page scaffold

private struct Chapter_<Art: View>: View {
    let eyebrow: String
    let tint: Color
    let title: String
    let body_: String
    @ViewBuilder var art: Art
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(eyebrow: String, tint: Color, title: String, body: String, @ViewBuilder art: () -> Art) {
        self.eyebrow = eyebrow; self.tint = tint; self.title = title; self.body_ = body; self.art = art()
    }

    var body: some View {
        VStack(spacing: 36) {
            art.frame(height: 240)

            VStack(spacing: 12) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold)).tracking(1.6)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: .capsule)
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(body_)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
        }
        .onAppear { play(reduceMotion, $shown, .spring(response: 0.55, dampingFraction: 0.85), delay: 0.15) }
    }
}

// MARK: - Opener

private struct HeroPage: View {
    let reduceMotion: Bool
    let start: () -> Void
    @State private var iconIn = false
    @State private var ring = false
    @State private var letters = 0
    @State private var restIn = false

    private let name = Array("Rift")

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                // Pulse rings that fire once as the icon lands.
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(Ember.gradient, lineWidth: 2)
                        .frame(width: 150, height: 150)
                        .scaleEffect(ring ? 2.1 + Double(i) * 0.5 : 0.9)
                        .opacity(ring ? 0 : 0.7)
                        .animation(reduceMotion ? nil : .easeOut(duration: 1.6).delay(Double(i) * 0.25), value: ring)
                }
                Circle()
                    .fill(RadialGradient(colors: [Ember.hot.opacity(0.6), .clear],
                                         center: .center, startRadius: 10, endRadius: 150))
                    .frame(width: 320, height: 320)
                    .blur(radius: 30)
                    .opacity(iconIn ? 1 : 0)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 148, height: 148)
                    .shadow(color: Ember.hot.opacity(0.5), radius: 40, y: 14)
                    .scaleEffect(iconIn ? 1 : 0.4)
                    .rotationEffect(.degrees(iconIn ? 0 : -18))
                    .offset(y: iconIn ? 0 : -60)
                    .opacity(iconIn ? 1 : 0)
            }
            .frame(height: 260)

            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    ForEach(name.indices, id: \.self) { i in
                        Text(String(name[i]))
                            .opacity(i < letters ? 1 : 0)
                            .offset(y: i < letters ? 0 : 18)
                            .blur(radius: i < letters ? 0 : 6)
                    }
                }
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.75)],
                                                startPoint: .top, endPoint: .bottom))

                Text("YouTube Music, finally at home on your Mac.")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(restIn ? 1 : 0)
                    .offset(y: restIn ? 0 : 10)
            }

            VStack(spacing: 12) {
                Button(action: start) {
                    HStack(spacing: 8) {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 240, height: 46)
                    .background(Ember.gradient, in: .capsule)
                    .shadow(color: Ember.hot.opacity(0.45), radius: 18, y: 8)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .background(Button("", action: start).keyboardShortcut(.rightArrow, modifiers: []).hidden())

                Text("Free and open source")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .opacity(restIn ? 1 : 0)
            .scaleEffect(restIn ? 1 : 0.94)
        }
        .onAppear(perform: run)
    }

    private func run() {
        guard !reduceMotion else { iconIn = true; letters = name.count; restIn = true; return }
        withAnimation(.spring(response: 0.75, dampingFraction: 0.62).delay(0.2)) { iconIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { ring = true }
        for i in 1...name.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.75 + Double(i) * 0.09)) {
                letters = i
            }
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(1.35)) { restIn = true }
    }
}

// MARK: - Chapter · dynamic island

private struct IslandArt: View {
    let reduceMotion: Bool
    @State private var peek = false
    @State private var open = false

    var body: some View {
        ZStack(alignment: .top) {
            // A screen with a menu bar.
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo").font(.system(size: 10))
                        ForEach([26, 20, 30, 22], id: \.self) {
                            Capsule().fill(.white.opacity(0.25)).frame(width: CGFloat($0), height: 5)
                        }
                        Spacer()
                        ForEach([14, 14, 30], id: \.self) {
                            Capsule().fill(.white.opacity(0.25)).frame(width: CGFloat($0), height: 5)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 14).frame(height: 22)
                }
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
                .frame(width: 520, height: 230)

            // The island.
            VStack(spacing: 0) {
                if open {
                    HStack(spacing: 12) {
                        cover(44)
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(.white.opacity(0.9)).frame(width: 110, height: 7)
                            Capsule().fill(.white.opacity(0.4)).frame(width: 70, height: 6)
                        }
                        Spacer(minLength: 0)
                        EqualizerBars(reduceMotion: reduceMotion).frame(width: 22, height: 24)
                    }
                    .padding(.top, 26)
                    VStack(spacing: 8) {
                        Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                            .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 90, height: 4) }
                        HStack(spacing: 26) {
                            Image(systemName: "backward.fill")
                            Image(systemName: "pause.fill").font(.system(size: 18))
                            Image(systemName: "forward.fill")
                        }
                        .foregroundStyle(.white)
                        .font(.system(size: 13))
                    }
                    .padding(.top, 12)
                    .transition(.opacity)
                } else if peek {
                    HStack {
                        cover(16)
                        Spacer()
                        EqualizerBars(reduceMotion: reduceMotion).frame(width: 14, height: 12)
                    }
                    .frame(height: 22)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, open ? 18 : 8)
            .padding(.bottom, open ? 14 : 0)
            .frame(width: open ? 300 : peek ? 150 : 84, height: open ? nil : 22, alignment: .top)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: open ? 26 : 11,
                                                           bottomTrailingRadius: open ? 26 : 11))
            .shadow(color: .black.opacity(open ? 0.5 : 0), radius: 20, y: 10)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 20)).foregroundStyle(.white)
                    .shadow(radius: 2)
                    .offset(x: open ? -40 : 30, y: open ? -30 : 40)
                    .opacity(peek && !open ? 1 : open ? 0.0 : 0)
            }
        }
        .onAppear {
            play(reduceMotion, $peek, .spring(response: 0.5, dampingFraction: 0.75), delay: 0.4)
            play(reduceMotion, $open, .spring(response: 0.6, dampingFraction: 0.72), delay: 1.4)
        }
    }

    private func cover(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.22)
            .fill(LinearGradient(colors: [Ember.warm, Ember.rose], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: s, height: s)
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
                        .frame(width: 3, height: geo.size.height * (tall ? heights[index] : 0.3))
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

// MARK: - Chapter · sing along

private struct SingAlongArt: View {
    let reduceMotion: Bool
    @State private var index = 0
    @State private var cardIn = false
    @State private var loop: Task<Void, Never>?

    // An original line (not from any song): Hindi "दिल से गाओ" — "sing from
    // the heart" — the same SOUNDS in each script, exactly what the feature
    // does. Nothing here is translated.
    private let source = "दिल से गाओ"
    private let scripts: [(label: String, text: String)] = [
        ("Roman", "Dil se gaao"),
        ("Cyrillic", "Дил се гаао"),
        ("Japanese", "ディル セ ガーオ"),
        ("Korean", "딜 세 가오"),
        ("Urdu", "دل سے گاؤ"),
        ("Greek", "Ντιλ σε γκάο"),
        ("Bengali", "দিল সে গাও"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                Text("Line you hear").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                Text(source).font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)

                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Ember.gradient)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)

                Text(scripts[index].text)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.9)),
                                            removal: .opacity.combined(with: .offset(y: -14))))
                    .frame(height: 52)
            }
            .padding(.vertical, 22).padding(.horizontal, 40)
            .frame(width: 440)
            .liquidGlass(in: .rect(cornerRadius: 24))
            .opacity(cardIn ? 1 : 0)
            .scaleEffect(cardIn ? 1 : 0.95)

            HStack(spacing: 6) {
                ForEach(scripts.indices, id: \.self) { i in
                    Text(scripts[i].label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(i == index ? .white : .secondary)
                        .background(i == index ? AnyShapeStyle(Ember.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                    in: .capsule)
                }
            }
        }
        .onAppear {
            play(reduceMotion, $cardIn, .spring(response: 0.55, dampingFraction: 0.8), delay: 0.1)
            guard !reduceMotion else { return }
            loop = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.8))
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        index = (index + 1) % scripts.count
                    }
                }
            }
        }
        .onDisappear { loop?.cancel(); loop = nil }
    }
}

// MARK: - Chapter · make it yours

private struct CoversArt: View {
    let reduceMotion: Bool
    @State private var shown = 0
    @State private var widgetIn = false

    private let covers: [(String, CoverPalette, String)] = [
        ("🌙", .ocean, "Late night"), ("🔥", .ember, "Gym"), ("☕️", .citrus, "Morning"),
        ("❤️", .midnight, "Liked"), ("🌊", .lagoon, "Chill"), ("🎸", .dusk, "Rock"),
    ]

    var body: some View {
        HStack(spacing: 28) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 12), count: 3), spacing: 12) {
                ForEach(covers.indices, id: \.self) { i in
                    let (emoji, palette, title) = covers[i]
                    CustomCoverArt(cover: CustomCover(emoji: emoji, palette: palette, showTitle: true),
                                   title: title, size: 92)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .scaleEffect(i < shown ? 1 : 0.5)
                        .rotationEffect(.degrees(i < shown ? 0 : (i.isMultiple(of: 2) ? -12 : 12)))
                        .opacity(i < shown ? 1 : 0)
                }
            }
            .frame(width: 300)

            // A desktop widget.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    CustomCoverArt(cover: CustomCover(emoji: "🌙", palette: .ocean), size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(.white.opacity(0.9)).frame(width: 74, height: 6)
                        Capsule().fill(.white.opacity(0.45)).frame(width: 48, height: 5)
                    }
                }
                Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 60, height: 4) }
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill").font(.system(size: 16))
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 11)).foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .frame(width: 168)
            .background(LinearGradient(colors: [Color(hex: 0x1B2B4A), Color(hex: 0x0F1E3A)],
                                       startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .overlay(alignment: .topTrailing) {
                Text("Widget").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Ember.gradient, in: .capsule)
                    .offset(x: 8, y: -8)
            }
            .opacity(widgetIn ? 1 : 0)
            .offset(x: widgetIn ? 0 : 30)
        }
        .onAppear {
            guard !reduceMotion else { shown = covers.count; widgetIn = true; return }
            for i in 1...covers.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.15 + Double(i) * 0.09)) { shown = i }
            }
            play(reduceMotion, $widgetIn, .spring(response: 0.6, dampingFraction: 0.8), delay: 0.85)
        }
    }
}

// MARK: - Chapter · nearby

private struct TogetherArt: View {
    let reduceMotion: Bool
    @State private var linked = false
    @State private var flying = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !linked)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 0) {
                mac(name: "You")
                ZStack {
                    // Waves travelling left → right between the Macs.
                    ForEach(0..<4, id: \.self) { i in
                        let phase = reduceMotion ? 0.5 : (t * 0.6 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .trim(from: 0.38, to: 0.62)
                            .stroke(Ember.gradient, style: .init(lineWidth: 3, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90 + 90))
                            .offset(x: -90 + phase * 180)
                            .opacity(linked ? sin(phase * .pi) : 0)
                    }
                    Text("🎵")
                        .font(.system(size: 26))
                        .offset(x: flying ? 80 : -80, y: flying ? -6 : 0)
                        .opacity(flying ? 0 : 1)
                        .opacity(linked ? 1 : 0)
                }
                .frame(width: 220, height: 120)
                mac(name: "Friend")
            }
        }
        .onAppear {
            play(reduceMotion, $linked, .easeOut(duration: 0.4), delay: 0.3)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.6)) { flying = true }
        }
    }

    private func mac(name: String) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [Ember.warm, Ember.rose], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 40, height: 40)
                            EqualizerBars(reduceMotion: reduceMotion || !linked).frame(width: 22, height: 14)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)))
                    .frame(width: 130, height: 90)
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(Color(white: 0.3)).frame(width: 156, height: 7)
            }
            Text(name).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Finale · sign in

private struct SignInPage: View {
    let auth: AuthController
    let reduceMotion: Bool
    let onDone: () -> Void
    @State private var spin = false
    @State private var shown = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                // Slowly turning ember halo around the icon.
                Circle()
                    .fill(AngularGradient(colors: [Ember.warm, Ember.hot, Ember.rose, Ember.warm], center: .center))
                    .frame(width: 150, height: 150)
                    .blur(radius: 24)
                    .opacity(0.75)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 12).repeatForever(autoreverses: false), value: spin)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            }
            .frame(height: 170)

            VStack(spacing: 12) {
                Text("Bring your music with you")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Sign in and Rift picks up right where YouTube Music left off.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                perk("music.note.list", "Your playlists")
                perk("heart.fill", "Your likes")
                perk("sparkles", "Your mixes")
            }

            VStack(spacing: 12) {
                Button {
                    onDone()
                    auth.signIn()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                        Text("Sign in with Google")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 280, height: 46)
                    .background(Ember.gradient, in: .capsule)
                    .shadow(color: Ember.hot.opacity(0.45), radius: 18, y: 8)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Button("Start listening without an account") { onDone() }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
            }

            Text("Not affiliated with, endorsed by, or connected to Google LLC / YouTube.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .onAppear {
            spin = true
            play(reduceMotion, $shown, .spring(response: 0.6, dampingFraction: 0.85), delay: 0.1)
        }
    }

    private func perk(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Ember.gradient)
            Text(title).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .liquidGlass(in: .capsule)
    }
}
