// SPDX-License-Identifier: GPL-3.0-only
//
// Showcase — DEBUG-only canvas previews of every main screen, all frozen on the
// same now-playing track, so marketing shots stay consistent. Each screen is a
// `#Preview` for Xcode's canvas, and launching with `-RiftShowcase` opens the
// same previews as real windows (so Liquid Glass and materials render exactly
// as in the app) for exporting with `screencapture -l`.
//
// Unlike the running app, the player pill is docked INSIDE the window here
// (the live app floats it in its own panel that hangs past the window edge).

#if DEBUG
import SwiftUI
import AppKit
import Combine

enum ShowcaseScreen: String, CaseIterable, Identifiable {
    case home, nowPlaying, queue, search, library, artist, stats
    var id: String { rawValue }

    var panel: Panel {
        switch self {
        case .search, .artist: return .search
        case .library: return .library
        case .stats: return .stats
        default: return .home
        }
    }
    var fullPlayer: Bool { self == .nowPlaying || self == .queue }
    var showsQueue: Bool { self == .queue }
}

/// The one track every screen is playing.
enum ShowcaseData {
    static func art(_ id: String) -> URL? {
        URL(string: "https://yt3.googleusercontent.com/\(id)=w544-h544-l90-rj")
    }
    static let nowPlaying = PlayableTrack(
        id: "yO8fk8FzpHA", title: "Safarnama", artist: "AUR",
        artworkURL: art("PMEPNYaZJN5_rnW5rA_ledKyWQb0Th6HgXD4hOcCcv8XUt4ys5It_MNzjnmB9oyw4cwCaBXhqh9t69ji"),
        duration: 224)
    static let upNext: [PlayableTrack] = [
        PlayableTrack(id: "i1IDh_ZoJgI", title: "Alag Aasmaan", artist: "Anuv Jain",
                      artworkURL: art("XSFFKq9eWgpI4jKsD7luwyqpCgAYkIapEAV-92HNIoOrFj7KfTySAmr8n0s_LJMXfDQFS370iVxN7fXg"), duration: 176),
        PlayableTrack(id: "r7Rn4ryE_w8", title: "Sunflower", artist: "Post Malone & Swae Lee",
                      artworkURL: art("IBwK4LOs4sO-Cd-_5YO4XC2B2N1hvyBvKfr60tT_ljIuwmOuVWWW2NypbcvzKgScVAbRsWEYbmsjfcm2cw"), duration: 257),
        PlayableTrack(id: "MX7FSAnRPug", title: "Loser", artist: "Tame Impala",
                      artworkURL: art("qHqGMmCC4LahCshElRTm8kuJQu4IyDClDx__HiqqydFVMUi2JOfEyZpqootNb1WswJwapw8c8SCmOMuMiQ"), duration: 159),
        PlayableTrack(id: "P-X-iHTe5PI", title: "Am I Dreaming", artist: "Metro Boomin, A$AP Rocky & Roisee",
                      artworkURL: art("rra9ajpG50BoWyxszMpVqMAloA83Q1p3V4ryNrtDhAriAqvxyNAEAKU0KDs0JoxgDKoSsiWe_GDWong"), duration: 257),
    ]
    static let artist = MusicCard(id: "UC0C-w0YjGpqDXGB8IHb662A", kind: .artist,
                                  title: "Ed Sheeran", subtitle: "Artist", artworkURL: nil)

    /// A player frozen mid-track (1:17 of 3:44), playing.
    @MainActor static func makePlayer() -> PlayerController {
        let source = ShowcaseSource()
        let player = PlayerController(source: source)
        player.play(nowPlaying, in: [nowPlaying] + upNext)
        source.durationSubject.send(224)
        source.timeSubject.send(77)
        source.stateSubject.send(.playing)
        return player
    }
}

@MainActor
private final class ShowcaseSource: PlaybackSource {
    let stateSubject = CurrentValueSubject<PlaybackState, Never>(.playing)
    let timeSubject = CurrentValueSubject<TimeInterval, Never>(77)
    let durationSubject = CurrentValueSubject<TimeInterval, Never>(224)
    var state: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTime: AnyPublisher<TimeInterval, Never> { timeSubject.eraseToAnyPublisher() }
    var duration: AnyPublisher<TimeInterval, Never> { durationSubject.eraseToAnyPublisher() }
    func load(_ track: PlayableTrack) {}
    func play() { stateSubject.send(.playing) }
    func pause() { stateSubject.send(.paused) }
    func seek(to seconds: TimeInterval) { timeSubject.send(seconds) }
    func setVolume(_ volume: Double) {}
}

/// ContentView's shell, with the section fixed and the pill docked in-window.
struct ShowcaseShell: View {
    let screen: ShowcaseScreen
    @EnvironmentObject var player: PlayerController

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(panel: .constant(screen.panel)).frame(width: 189)

            ZStack(alignment: .bottom) {
                if screen.fullPlayer {
                    FullScreenPlayerView()
                } else {
                    NavigationStack { detail }
                        .contentMargins(.bottom, 124, for: .scrollContent)
                    NowPlayingBar(showQueue: .constant(false))
                        .frame(height: 124)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if screen.showsQueue { QueueRail().frame(width: 264) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Color(white: 0.11), Color(white: 0.05)],
                               startPoint: .top, endPoint: .bottom)
                if let art = player.track?.artworkURL { AmbientArtwork(url: art) }
            }
            .ignoresSafeArea()
        }
        .environment(\.controlActiveState, .key)
    }

    @ViewBuilder private var detail: some View {
        switch screen {
        case .search: SearchView()
        case .library: LibraryView()
        case .stats: StatsView()
        case .artist: ArtistDetailView(card: ShowcaseData.artist)
        default: HomeView()
        }
    }
}

/// One screen with its full environment — what both the canvas and the export windows show.
struct ShowcaseRoot: View {
    let screen: ShowcaseScreen
    let player: PlayerController
    @StateObject private var ui = UIState()

    var body: some View {
        ShowcaseShell(screen: screen)
            .environmentObject(player)
            .environmentObject(AppServices.shared.auth)
            .environmentObject(AppServices.shared.mode)
            .environmentObject(ui)
            .onAppear { ui.showQueue = screen.showsQueue; ui.showFullPlayer = screen.fullPlayer }
    }
}

enum Showcase {
    static let size = CGSize(width: 1180, height: 720)
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-RiftShowcase") }

    @MainActor private static var windows: [NSWindow] = []

    /// Opens every screen as a titled window ("RiftShowcase-<screen>") and hides the regular app windows.
    @MainActor static func open() {
        let player = ShowcaseData.makePlayer()
        for (i, screen) in ShowcaseScreen.allCases.enumerated() {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "RiftShowcase-\(screen.rawValue)"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ShowcaseRoot(screen: screen, player: player)
                .frame(width: size.width, height: size.height))
            w.setFrameOrigin(NSPoint(x: 40 + CGFloat(i) * 24, y: 80 + CGFloat(i) * 12))
            w.orderFront(nil)
            windows.append(w)
        }
        // The regular main window and floating pill would only clutter the desktop.
        for delay in [1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for w in NSApp.windows where !windows.contains(w) { w.orderOut(nil) }
            }
        }
    }
}

#Preview("Home") { ShowcaseRoot(screen: .home, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#Preview("Now playing") { ShowcaseRoot(screen: .nowPlaying, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#Preview("Queue") { ShowcaseRoot(screen: .queue, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#Preview("Search") { ShowcaseRoot(screen: .search, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#Preview("Library") { ShowcaseRoot(screen: .library, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#Preview("Artist") { ShowcaseRoot(screen: .artist, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#Preview("Stats") { ShowcaseRoot(screen: .stats, player: ShowcaseData.makePlayer()).frame(width: 1180, height: 720) }
#endif
