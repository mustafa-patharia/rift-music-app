// SPDX-License-Identifier: GPL-3.0-only
// Rift — native macOS YouTube Music player.
//
// PlaybackSource: the sacred boundary. Nothing above this protocol knows whether
// audio comes from a WebView, native extraction, or a local file. Swap freely.

import Foundation
import Combine

/// A single playable item. Only what the transport needs — metadata lives elsewhere.
/// Codable so the queue survives relaunch (resume-where-you-left-off).
struct PlayableTrack: Equatable, Identifiable, Codable {
    let id: String          // YouTube videoId, or a local file URL string
    let title: String
    let artist: String
    let artworkURL: URL?
    let duration: TimeInterval?   // may be nil until the source reports it
}

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case error(String)
}

extension PlaybackSource {
    func preload(_ track: PlayableTrack) {}   // sources that don't cache opt out
    func reload() {}                          // re-attempt current track fresh (retry/self-heal)
    // Crossfade is an optional, source-specific capability (macOS 26+ native only —
    // a hidden WebView can't run two overlapping streams). Sources that don't
    // support it silently no-op and the controller falls back to its normal
    // .ended → next() advance.
    var advanced: AnyPublisher<PlayableTrack, Never> { Empty().eraseToAnyPublisher() }
    func beginCrossfade(to track: PlayableTrack) {}
    func cancelCrossfade() {}
}

/// The one interface the whole app plays through. Implementations:
/// WebViewPlayer (YTM JS), LocalPlayer (AVFoundation), future NativeExtractor.
/// Main-actor: playback drives UI + WebKit, both main-actor bound.
@MainActor
protocol PlaybackSource: AnyObject {
    // Reactive state the UI binds to.
    var state: AnyPublisher<PlaybackState, Never> { get }
    var currentTime: AnyPublisher<TimeInterval, Never> { get }
    var duration: AnyPublisher<TimeInterval, Never> { get }
    /// Fires when the source silently swapped to a new track on its own
    /// (crossfade completed) — the controller updates queue position/history
    /// without calling load(). Default: never fires.
    var advanced: AnyPublisher<PlayableTrack, Never> { get }

    func load(_ track: PlayableTrack)
    /// Warm any resolve/cache for a track likely to play next. Default no-op.
    func preload(_ track: PlayableTrack)
    /// Re-attempt the current track from a fresh resolve. Default no-op.
    func reload()
    /// Start crossfading into `track` ahead of the current track's natural end.
    /// Default no-op — sources without crossfade support just let .ended fire.
    func beginCrossfade(to track: PlayableTrack)
    /// Abort an in-flight crossfade (user manually skipped/changed track). Default no-op.
    func cancelCrossfade()
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setVolume(_ volume: Double)   // 0.0…1.0
}
