// SPDX-License-Identifier: GPL-3.0-only
//
// NativePlayer — pure-native audio path. AVPlayer (AVFoundation) plays a direct
// stream URL resolved by StreamResolver (yt-dlp, out of process). No WebView.
// Also plays local files: a file:// PlayableTrack.id skips resolution.

import Foundation
import Combine
import AVFoundation

@MainActor
final class NativePlayer: NSObject, PlaybackSource {

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let timeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let advancedSubject = PassthroughSubject<PlayableTrack, Never>()

    var state: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTime: AnyPublisher<TimeInterval, Never> { timeSubject.eraseToAnyPublisher() }
    var duration: AnyPublisher<TimeInterval, Never> { durationSubject.eraseToAnyPublisher() }
    var advanced: AnyPublisher<PlayableTrack, Never> { advancedSubject.eraseToAnyPublisher() }

    private var player = AVPlayer()
    private var timeObserver: Any?
    private var itemObservers = Set<AnyCancellable>()
    private var resolveTask: Task<Void, Never>?
    private var current: PlayableTrack?     // for self-heal reloads
    private var triedFresh = false          // one forced re-resolve per load

    // MARK: crossfade (macOS 26+ only — see beginCrossfade)
    private static let crossfadeDuration: TimeInterval = 5
    private var crossfadePlayer: AVPlayer?
    private var crossfadeTask: Task<Void, Never>?

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true

        // Poll playback time (250ms) on the main queue → publish.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            MainActor.assumeIsolated {   // observer scheduled on .main
                self?.timeSubject.send(t.seconds)
            }
        }
    }

    // No deinit cleanup needed: single app-lifetime instance; the observer is
    // released with the player. (nonisolated deinit can't touch main-actor state.)

    // MARK: PlaybackSource
    func load(_ track: PlayableTrack) {
        current = track
        triedFresh = false
        resolve(track, forceFresh: false)
    }

    /// Re-attempt the current track from scratch (user "retry" or self-heal).
    func reload() {
        guard let t = current else { return }
        triedFresh = false
        resolve(t, forceFresh: true)
    }

    private func resolve(_ track: PlayableTrack, forceFresh: Bool) {
        resolveTask?.cancel()
        // Silence the outgoing track NOW — otherwise it keeps playing until the new
        // stream resolves (~1s of yt-dlp). Tear down its item + observers immediately.
        itemObservers.removeAll()
        player.replaceCurrentItem(with: nil)
        timeSubject.send(0)
        durationSubject.send(0)
        stateSubject.send(.loading)

        // Local file → play directly, no resolution (AVPlayer duration is fine here).
        if let fileURL = URL(string: track.id), fileURL.isFileURL {
            setItem(fileURL, knownDuration: nil); return
        }
        // YouTube videoId → cache hit plays instantly; otherwise resolve out of
        // process, cache, then play. forceFresh evicts a stale (403'd) cache entry.
        let t0 = ContinuousClock.now
        resolveTask = Task { [weak self] in
            guard let self else { return }
            if forceFresh {
                await StreamCache.shared.evict(track.id)
                await AudioFileCache.shared.remove(track.id)   // purge a bad local copy
            }
            // Offline: if the bytes are on disk, play them — no network, no yt-dlp.
            if !forceFresh, let local = await AudioFileCache.shared.localFile(for: track.id) {
                if Task.isCancelled { return }
                // Real duration: track metadata → the one we saved with the bytes →
                // else nil (AVPlayer's, which may double). Never trust AVPlayer here.
                var known = track.duration
                if known == nil { known = await AudioFileCache.shared.duration(for: track.id) }
                if known == nil { known = await StreamCache.shared.get(track.id)?.duration }
                Log.player.info("▶︎ \(track.title, privacy: .public) — instant (offline file, \(Log.ms(since: t0))ms)")
                if let d = known, d > 0 { self.durationSubject.send(d) }
                self.setItem(local, knownDuration: known)
                return
            }
            do {
                let r: StreamResolver.Resolved
                if !forceFresh, let cached = await StreamCache.shared.get(track.id) {
                    r = cached
                    Log.player.info("▶︎ \(track.title, privacy: .public) — fast (stream cache, \(Log.ms(since: t0))ms)")
                } else {
                    r = try await StreamResolver.resolveAudio(videoId: track.id)
                    await StreamCache.shared.put(track.id, r)
                    Log.player.info("▶︎ \(track.title, privacy: .public) — cold (resolved by yt-dlp, \(Log.ms(since: t0))ms)")
                }
                if Task.isCancelled { return }
                if let d = r.duration, d > 0 { self.durationSubject.send(d) }
                self.setItem(r.url, knownDuration: r.duration, headers: r.headers)
                // Save the audio for true-offline replay (best-effort, background).
                let id = track.id
                Task.detached { await AudioFileCache.shared.save(id, from: r.url, headers: r.headers, duration: r.duration) }
            } catch {
                if Task.isCancelled { return }
                self.stateSubject.send(.error(error.localizedDescription))
            }
        }
    }

    /// Warm the cache for a track we're likely to play next (skip-forward),
    /// without touching current playback. Cheap no-op if already cached/local.
    func preload(_ track: PlayableTrack) {
        if let u = URL(string: track.id), u.isFileURL { return }
        Task {
            if await StreamCache.shared.get(track.id) != nil { return }
            if let r = try? await StreamResolver.resolveAudio(videoId: track.id) {
                await StreamCache.shared.put(track.id, r)
            }
        }
    }

    private func setItem(_ url: URL, knownDuration: TimeInterval?, headers: [String: String] = [:]) {
        itemObservers.removeAll()   // drop the previous item's KVO/notification subs (leak fix)
        let item = Self.makeItem(url: url, headers: headers)
        wireObservers(item, knownDuration: knownDuration, into: &itemObservers)
        player.replaceCurrentItem(with: item)
        play()
    }

    private static func makeItem(url: URL, headers: [String: String]) -> AVPlayerItem {
        // googlevideo CDN URLs require yt-dlp's headers (User-Agent etc.) or they
        // 403 → AVPlayer reports a generic "unknown error". Pass them through.
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        return AVPlayerItem(asset: asset)
    }

    /// Duration + status/end-of-track KVO → Combine, shared by the normal load path
    /// and a completed crossfade's newly-active item.
    private func wireObservers(_ item: AVPlayerItem, knownDuration: TimeInterval?, into bag: inout Set<AnyCancellable>) {
        // For YouTube streams we already have the real duration from yt-dlp;
        // ignore AVPlayer's (it doubles some m4a).
        item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] status in
            guard let self else { return }
            switch status {
            case .readyToPlay:
                if knownDuration == nil {
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self.durationSubject.send(d) }
                }
            case .failed:
                // A cached googlevideo URL that expired mid-life 403s here. Self-heal
                // once: evict + re-resolve fresh before surfacing an error.
                if !self.triedFresh, let t = self.current, URL(string: t.id)?.isFileURL != true {
                    self.triedFresh = true
                    self.resolve(t, forceFresh: true)
                } else {
                    self.stateSubject.send(.error(item.error?.localizedDescription ?? "playback failed"))
                }
            default: break
            }
        }.store(in: &bag)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.stateSubject.send(.ended) }
            .store(in: &bag)
    }

    // MARK: crossfade (macOS 26+ only)
    //
    // Below macOS 26 this stays a no-op via the protocol default — the single-
    // AVPlayer swap above is untouched and keeps its existing reliability.
    // Only triggers when `track`'s stream is already warm in StreamCache (the
    // controller preloads the next track when a song starts) — crossfading into
    // a cold resolve would just stutter, so skip it and let .ended → next() run.
    func beginCrossfade(to track: PlayableTrack) {
        guard #available(macOS 26, *), crossfadePlayer == nil else { return }
        if let fileURL = URL(string: track.id), fileURL.isFileURL {
            startCrossfade(to: track, url: fileURL, headers: [:])
            return
        }
        crossfadeTask = Task { [weak self] in
            guard let self, let cached = await StreamCache.shared.get(track.id) else { return }
            self.startCrossfade(to: track, url: cached.url, headers: cached.headers)
        }
    }

    func cancelCrossfade() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        crossfadePlayer?.pause()
        crossfadePlayer = nil
    }

    private func startCrossfade(to track: PlayableTrack, url: URL, headers: [String: String]) {
        let item = Self.makeItem(url: url, headers: headers)
        let fadeIn = AVPlayer(playerItem: item)
        fadeIn.volume = 0
        fadeIn.play()
        crossfadePlayer = fadeIn

        let startVolume = player.volume
        let steps = 20
        let stepNanos = UInt64(Self.crossfadeDuration / Double(steps) * 1_000_000_000)
        crossfadeTask = Task { [weak self] in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: stepNanos)
                guard let self, self.crossfadePlayer === fadeIn else { return }   // canceled/superseded
                let progress = Float(i) / Float(steps)
                self.player.volume = startVolume * (1 - progress)
                fadeIn.volume = progress
            }
            self?.completeCrossfade(to: track, item: item, newPlayer: fadeIn)
        }
    }

    private func completeCrossfade(to track: PlayableTrack, item: AVPlayerItem, newPlayer: AVPlayer) {
        guard crossfadePlayer === newPlayer else { return }   // canceled mid-flight
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        itemObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)

        player = newPlayer
        current = track
        triedFresh = false
        crossfadePlayer = nil
        crossfadeTask = nil
        wireObservers(item, knownDuration: track.duration, into: &itemObservers)
        // Trust yt-dlp's metadata duration only — same rule as the normal load
        // path (see setItem/wireObservers). item.duration here may not be
        // ready yet (NaN) or double-reported for some m4a containers; if we
        // don't have the real one, let wireObservers' readyToPlay handler send
        // a validated one once the item actually settles.
        if let d = track.duration, d > 0 { durationSubject.send(d) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] t in
            MainActor.assumeIsolated { self?.timeSubject.send(t.seconds) }
        }
        advancedSubject.send(track)
    }

    func play() {
        player.play()
        stateSubject.send(.playing)
    }
    func pause() {
        player.pause()
        stateSubject.send(.paused)
    }
    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }
    func setVolume(_ volume: Double) {
        player.volume = Float(max(0, min(1, volume)))
    }
}
