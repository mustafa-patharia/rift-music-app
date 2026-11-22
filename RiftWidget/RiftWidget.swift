// SPDX-License-Identifier: GPL-3.0-only
//
// RiftWidget — desktop / Notification Center "Now Playing" widget with
// transport buttons. The app writes a snapshot (nowplaying.json + art.jpg)
// into the shared App Group container and reloads the timeline on every
// change (Rift/Core/Player/WidgetBridge.swift); the buttons post a
// distributed notification the app turns into play/pause/next/previous.
// Sandboxed extensions can post those (userInfo is stripped, so the command
// travels in the notification name).

import AppIntents
import AppKit
import SwiftUI
import WidgetKit
import os

private let log = Logger(subsystem: "com.mustafapatharia.riftmusicapp.widget", category: "intent")

// MARK: - Shared snapshot (mirrors WidgetBridge.Snapshot in the app)

struct Snapshot: Codable, Sendable {
    var title: String
    var artist: String
    var playing: Bool
    var elapsed: Double
    var duration: Double
    var updated: Date
}

enum SharedStore {
    static let group = "RA6D2G5KXZ.com.mustafapatharia.riftmusicapp"
    static var dir: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    static func load() -> (Snapshot?, Data?) {
        guard let dir else { return (nil, nil) }
        let snap = (try? Data(contentsOf: dir.appendingPathComponent("nowplaying.json")))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let art = try? Data(contentsOf: dir.appendingPathComponent("art.jpg"))
        return (snap, art)
    }
}

// MARK: - Transport intent

struct RiftCommand: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Control Rift playback"
    static let isDiscoverable = false

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    func perform() async throws -> some IntentResult {
        log.info("perform \(command, privacy: .public)")
        // Flip play/pause in the snapshot right away: the widget redraws as
        // soon as perform() returns, before the app has written its new state
        // — without this the button looks dead and a second tap undoes it.
        if command == "toggle", let dir = SharedStore.dir {
            let file = dir.appendingPathComponent("nowplaying.json")
            if let data = try? Data(contentsOf: file),
               var snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
                let now = Date()
                if snap.playing { snap.elapsed += now.timeIntervalSince(snap.updated) }
                snap.playing.toggle()
                snap.updated = now
                try? JSONEncoder().encode(snap).write(to: file, options: .atomic)
            }
        }
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.mustafapatharia.riftmusicapp.widget.\(command)"),
            object: nil, userInfo: nil, deliverImmediately: true)
        return .result()
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let art: Data?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: Snapshot(title: "Song title", artist: "Artist", playing: false,
                                             elapsed: 0, duration: 0, updated: .now), art: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let (s, a) = SharedStore.load()
        completion(Entry(date: .now, snapshot: s ?? placeholder(in: context).snapshot, art: a))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let (s, a) = SharedStore.load()
        // The app reloads us on every change; no polling needed.
        completion(Timeline(entries: [Entry(date: .now, snapshot: s, art: a)], policy: .never))
    }
}

// MARK: - Views

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var artImage: Image? {
        entry.art.flatMap(NSImage.init(data:)).map(Image.init(nsImage:))
    }

    var body: some View {
        Group {
            if let s = entry.snapshot {
                family == .systemSmall ? AnyView(small(s)) : AnyView(medium(s))
            } else {
                idle
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color.black
                artImage?.resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 40).saturation(1.4).opacity(0.55)
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.system(size: 28, weight: .semibold))
            Text("Nothing playing").font(.headline)
            Text("Open Rift to start").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }

    private func art(_ size: CGFloat) -> some View {
        Group {
            if let artImage {
                artImage.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack { Color.white.opacity(0.12); Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.14))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }

    private func titles(_ s: Snapshot, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.title).font(compact ? .callout.weight(.semibold) : .headline)
                .lineLimit(compact ? 2 : 1)
            Text(s.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
    }

    private func button(_ symbol: String, _ command: String, size: CGFloat) -> some View {
        Button(intent: RiftCommand(command)) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 2, height: size * 2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func progress(_ s: Snapshot) -> some View {
        if s.duration > 0 {
            let start = s.updated.addingTimeInterval(-s.elapsed)
            let end = start.addingTimeInterval(s.duration)
            if s.playing, end > .now {
                ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: min(s.elapsed, s.duration), total: s.duration)
                    .progressViewStyle(.linear)
            }
        }
    }

    private func small(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                art(54)
                Spacer(minLength: 0)
                button(s.playing ? "pause.fill" : "play.fill", "toggle", size: 15)
                    .background(.white.opacity(0.18), in: .circle)
            }
            Spacer(minLength: 0)
            titles(s, compact: true)
        }
        .tint(.white)
    }

    private func medium(_ s: Snapshot) -> some View {
        HStack(spacing: 14) {
            art(118)
            VStack(alignment: .leading, spacing: 8) {
                titles(s, compact: false)
                progress(s).tint(.white)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    button("backward.fill", "previous", size: 14)
                    button(s.playing ? "pause.fill" : "play.fill", "toggle", size: 18)
                        .background(.white.opacity(0.18), in: .circle)
                    button("forward.fill", "next", size: 14)
                }
            }
        }
    }
}

// MARK: - Widget

struct RiftNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RiftNowPlaying", provider: Provider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing in Rift, with play/pause and skip.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RiftWidgetBundle: WidgetBundle {
    var body: some Widget { RiftNowPlayingWidget() }
}
