// SPDX-License-Identifier: GPL-3.0-only
//
// PlayerController — SwiftUI-facing ObservableObject over any PlaybackSource.
// Owns the queue, drives next/prev + auto-advance, and mirrors state to the
// system Now Playing UI. The UI binds here; never touches the source directly.

import Foundation
import Combine
import AppKit

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var track: PlayableTrack?

    @Published private(set) var queue: [PlayableTrack] = []
    @Published private(set) var index: Int = -1

    enum RepeatMode { case off, all, one }
    @Published var volume: Double = 1
    @Published var autoplay = true      // queue ends → continue with radio (YTM default)
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    private var preShuffleQueue: [PlayableTrack] = []

    private let source: PlaybackSource
    private var nowPlaying: NowPlayingCenter!
    private var bag = Set<AnyCancellable>()

    // Listening-history session for the current track (stats dashboard).
    // maxTime = furthest playback point observed; closed on track change / end.
    private var sessionStart: Date?
    private var sessionMaxTime: TimeInterval = 0

    // Resume-where-you-left-off: queue + position persisted to disk (saved
    // every ~5s while playing + on quit), restored PAUSED on next launch.
    private struct ResumeSnapshot: Codable {
        let queue: [PlayableTrack]
        let index: Int
        let time: TimeInterval
    }
    private var pendingSeek: TimeInterval?
    private var sourceStarted = false     // false until the first load() this launch

    // App Nap guard. Once audio stops at a track boundary the process becomes
    // nap-eligible INSTANTLY — macOS froze us between `ended` and starting the
    // next song (auto-advance only ran when a click woke the app; the notch eq
    // bars kept bouncing because repeatForever animations live in the render
    // server, not the napped process). Holding a userInitiated activity while
    // a session is live (playing/loading — including the gap between tracks)
    // keeps the scheduler away. Released on pause/error/idle so an idle app
    // can nap normally.
    private var napActivity: NSObjectProtocol?
    private var lastResumeSave = Date.distantPast
    private static var resumeFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.mustafapatharia.riftmusicapp/resume.json")
    }

    init(source: PlaybackSource) {
        self.source = source
        source.state.receive(on: DispatchQueue.main).sink { [weak self] in self?.onState($0) }.store(in: &bag)
        source.currentTime.receive(on: DispatchQueue.main).sink { [weak self] in self?.onTime($0) }.store(in: &bag)
        source.duration.receive(on: DispatchQueue.main).sink { [weak self] in self?.onDuration($0) }.store(in: &bag)

        nowPlaying = NowPlayingCenter(.init(
            play: { [weak self] in self?.source.play() },
            pause: { [weak self] in self?.source.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] in self?.seek(to: $0) }
        ))

        restoreSession()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveResume(force: true) }
        }
    }

    // MARK: resume across launches
    /// Restore the last session PAUSED at the saved position. Nothing is
    /// loaded/resolved yet — the first play tap starts the source and seeks.
    private func restoreSession() {
        // First run — or a reset back to onboarding — starts clean. Restoring
        // a previous session would leave a stale track sitting in the player
        // behind the welcome flow (the same @AppStorage key ContentView gates
        // onboarding on).
        guard UserDefaults.standard.bool(forKey: "hasOnboarded") else {
            if let url = Self.resumeFile { try? FileManager.default.removeItem(at: url) }
            return
        }
        guard let url = Self.resumeFile, let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(ResumeSnapshot.self, from: data),
              s.queue.indices.contains(s.index) else { return }
        queue = s.queue
        index = s.index
        track = s.queue[s.index]
        duration = track?.duration ?? 0
        currentTime = min(s.time, duration > 0 ? duration : .infinity)
        pendingSeek = currentTime > 2 ? currentTime : nil
        state = .paused
        pushNowPlaying()
    }

    private func saveResume(force: Bool = false) {
        guard let url = Self.resumeFile else { return }
        guard force || Date().timeIntervalSince(lastResumeSave) > 5 else { return }
        lastResumeSave = Date()
        guard !queue.isEmpty, index >= 0 else {
            try? FileManager.default.removeItem(at: url); return
        }
        let snap = ResumeSnapshot(queue: queue, index: index, time: currentTime)
        try? JSONEncoder().encode(snap).write(to: url)
    }

    var isPlaying: Bool { state == .playing }
    var hasNext: Bool { index >= 0 && index < queue.count - 1 }
    var hasPrevious: Bool { index > 0 }

    // MARK: transport
    /// Play `t`. If it belongs to `list`, that list becomes the queue so
    /// next/prev walk the search results the user was looking at.
    func play(_ t: PlayableTrack, in list: [PlayableTrack] = []) {
        if let i = list.firstIndex(of: t) {
            queue = list
            index = i
        } else {
            queue = [t]
            index = 0
        }
        start(t)
    }

    func next() {
        guard hasNext else { return }
        index += 1
        start(queue[index])
    }

    func previous() {
        // Restart current track if past ~3s, else go to previous.
        if currentTime > 3 { seek(to: 0); return }
        guard hasPrevious else { seek(to: 0); return }
        index -= 1
        start(queue[index])
    }

    // MARK: queue editing
    /// Append to the end of the queue (starts playback if nothing is queued).
    func addToQueue(_ t: PlayableTrack) {
        if queue.isEmpty { play(t); return }
        queue.append(t)
    }

    /// Insert right after the current track (starts playback if queue is empty).
    func playNext(_ t: PlayableTrack) {
        if queue.isEmpty || index < 0 { play(t); return }
        queue.insert(t, at: min(index + 1, queue.count))
        source.preload(t)   // it's next now — warm it
    }

    /// Reorder within the "Up Next" region (offsets are relative to index+1).
    func moveUpNext(fromOffsets: IndexSet, toOffset: Int) {
        guard index >= 0 else { return }
        let base = index + 1
        let current = queue[index]
        queue.move(fromOffsets: IndexSet(fromOffsets.map { base + $0 }), toOffset: base + toOffset)
        index = queue.firstIndex(of: current) ?? index   // keep pointing at the playing track
    }

    /// Remove upcoming tracks (offsets relative to index+1).
    func removeUpNext(atOffsets: IndexSet) {
        let base = index + 1
        for o in atOffsets.sorted(by: >) where queue.indices.contains(base + o) {
            queue.remove(at: base + o)
        }
    }

    func togglePlayPause() {
        // Cold resume: a restored session has a track but no loaded source yet —
        // the first play starts it and seeks back to where the user left off.
        if !sourceStarted, let t = track {
            let resumeAt = pendingSeek
            start(t)
            pendingSeek = resumeAt
            return
        }
        isPlaying ? source.pause() : source.play()
    }
    /// User tapped "retry" after an error → re-resolve current track fresh.
    func retry() { guard track != nil else { return }; source.reload() }
    func seek(to s: TimeInterval) { source.seek(to: s); pushNowPlaying() }
    func setVolume(_ v: Double) { volume = v; source.setVolume(v) }

    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off
    }

    /// Shuffle the queue (keeping the current track in place); toggling off
    /// restores the original order.
    func toggleShuffle() {
        isShuffled.toggle()
        let current = (index >= 0 && index < queue.count) ? queue[index] : nil
        if isShuffled {
            preShuffleQueue = queue
            var rest = queue
            if let c = current, let i = rest.firstIndex(of: c) { rest.remove(at: i) }
            rest.shuffle()
            queue = (current.map { [$0] } ?? []) + rest
            index = current == nil ? index : 0
        } else if !preShuffleQueue.isEmpty {
            queue = preShuffleQueue
            index = current.flatMap { queue.firstIndex(of: $0) } ?? max(index, 0)
        }
    }

    private func start(_ t: PlayableTrack) {
        closeHistorySession()               // log the outgoing track's listen
        sessionStart = Date()
        sessionMaxTime = 0
        pendingSeek = nil                   // a fresh start plays from 0
        sourceStarted = true
        track = t
        source.load(t)   // NativePlayer.load auto-plays once resolved
        source.setVolume(volume)
        pushNowPlaying()
        saveResume(force: true)
        // Warm the next track so skip-forward is instant (near-gapless).
        if hasNext { source.preload(queue[index + 1]) }
    }

    /// Close the current listening session and append it to local history.
    /// ponytail: seconds = furthest point reached (not summed play time); a quit
    /// mid-song loses that one session. Fine for local stats.
    private func closeHistorySession() {
        guard let t = track, let started = sessionStart, sessionMaxTime > 0 else { return }
        sessionStart = nil
        // Some yt-dlp m4a report doubled timestamps in AVPlayer (see NativePlayer
        // duration note) — raw player time can run past the real duration. Cap,
        // or full plays log 2× the track length and stats inflate.
        let dur = duration > 0 ? duration : t.duration
        let secs = dur.map { min(sessionMaxTime, $0) } ?? sessionMaxTime
        let e = PlayEvent(trackId: t.id, title: t.title, artist: t.artist,
                          artworkURL: t.artworkURL?.absoluteString,
                          ts: started, seconds: secs, duration: dur)
        Task.detached { await PlayHistoryStore.shared.log(e) }
    }

    // MARK: source callbacks
    private func onState(_ s: PlaybackState) {
        // Before the first load() the source's initial subject values (idle/0)
        // arrive AFTER restoreSession and would clobber the restored snapshot.
        guard sourceStarted else { return }
        state = s
        // Restored session: the item is attached the moment playback starts —
        // jump back to where the user left off (seek in onDuration would fire
        // too early: NativePlayer reports the yt-dlp duration before setItem).
        if s == .playing, let p = pendingSeek {
            pendingSeek = nil
            source.seek(to: p)
        }
        if s == .ended {   // auto-advance, honoring repeat mode
            closeHistorySession()   // full listen — log before advancing
            switch repeatMode {
            case .one: if let t = track { start(t) }
            case .all: hasNext ? next() : restartQueue()
            case .off: hasNext ? next() : autoplayMore()
            }
        }
        updateNapGuard()
        pushNowPlaying()
    }

    /// Hold off App Nap while a playback session is live; let go when idle.
    private func updateNapGuard() {
        let live: Bool
        switch state {
        case .playing, .loading: live = true
        case .ended: live = true   // the between-tracks gap — advance is in flight
        default: live = false
        }
        if live, napActivity == nil {
            napActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated, reason: "Music playback")
        } else if !live, let a = napActivity {
            ProcessInfo.processInfo.endActivity(a)
            napActivity = nil
        }
    }

    /// Queue exhausted with repeat off → extend it with YT Music radio picks
    /// based on the last track, so the music never just stops (autoplay).
    private func autoplayMore() {
        guard autoplay, let t = track, URL(string: t.id)?.isFileURL != true else {
            releaseNapGuard()   // nothing more will play — allow App Nap again
            return
        }
        Task { [weak self] in
            guard let self,
                  let more = try? await InnerTubeClient.radio(videoId: t.id), !more.isEmpty
            else { self?.releaseNapGuard(); return }
            let existing = Set(self.queue.map(\.id))
            let fresh = more.filter { !existing.contains($0.id) }
            guard !fresh.isEmpty else { self.releaseNapGuard(); return }
            self.queue.append(contentsOf: fresh)
            if self.hasNext { self.next() }
        }
    }

    private func releaseNapGuard() {
        if let a = napActivity {
            ProcessInfo.processInfo.endActivity(a)
            napActivity = nil
        }
    }

    private func restartQueue() {
        guard !queue.isEmpty else { return }
        index = 0
        start(queue[0])
    }
    private func onTime(_ t: TimeInterval) {
        guard sourceStarted else { return }   // see onState — protects the restored position
        currentTime = t
        if t > sessionMaxTime { sessionMaxTime = t }
        saveResume()   // throttled to ~5s inside
        // AVPlayer mis-reads some YouTube m4a containers as ~2× their length, so
        // DidPlayToEndTime fires at the FAKE end — playback sailed past the real
        // one into silence (3:33 / 2:50 on the transport). yt-dlp's duration is
        // the truth: past it (+grace for rounding), the song is over — end it.
        if state == .playing, duration > 0, t >= duration + 0.75 {
            onState(.ended)   // same path as a natural end: log history, advance
            return
        }
        // Cheap: only refresh elapsed on the system UI, not the whole payload.
        nowPlaying.update(track: track, duration: duration, elapsed: t, playing: isPlaying)
    }
    private func onDuration(_ d: TimeInterval) {
        guard sourceStarted else { return }   // see onState
        duration = d; pushNowPlaying()
    }

    private func pushNowPlaying() {
        nowPlaying.update(track: track, duration: duration, elapsed: currentTime, playing: isPlaying)
    }
}
