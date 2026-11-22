// SPDX-License-Identifier: GPL-3.0-only
//
// WidgetBridge — feeds the RiftWidget extension. On every track / play-state /
// duration change (and on seeks) it writes a snapshot plus downscaled artwork
// into the shared App Group container and reloads the widget timeline; it
// also listens for the widget's transport buttons, which arrive as
// distributed notifications ("…widget.toggle" / ".next" / ".previous").

import AppKit
import Combine
import WidgetKit

@MainActor
final class WidgetBridge {
    /// Mirrors `Snapshot` in RiftWidget/RiftWidget.swift.
    struct Snapshot: Codable {
        var title: String
        var artist: String
        var playing: Bool
        var elapsed: Double
        var duration: Double
        var updated: Date
    }

    static let group = "RA6D2G5KXZ.com.mustafapatharia.riftmusicapp"
    private static let kind = "RiftNowPlaying"
    private static let commandPrefix = "com.mustafapatharia.riftmusicapp.widget."

    private let player: PlayerController
    private var bag = Set<AnyCancellable>()
    private var last: Snapshot?
    private var artURL: URL?
    private var observers: [NSObjectProtocol] = []

    private let dir: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.group)

    init(player: PlayerController) {
        self.player = player
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

        Publishers.CombineLatest3(player.$track, player.$state.map { $0 == .playing }, player.$duration)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.write() }
            .store(in: &bag)
        // A seek moves the bar off its projected position → refresh.
        player.$currentTime
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] t in self?.checkDrift(t) }
            .store(in: &bag)

        let dnc = DistributedNotificationCenter.default()
        for name in ["toggle", "next", "previous"] {
            observers.append(dnc.addObserver(forName: .init(Self.commandPrefix + name),
                                             object: nil, queue: .main) { [weak player] _ in
                MainActor.assumeIsolated {
                    Log.player.info("widget command: \(name, privacy: .public)")
                    switch name {
                    case "toggle": player?.togglePlayPause()
                    case "next":   player?.next()
                    default:       player?.previous()
                    }
                }
            })
        }
    }

    private func checkDrift(_ t: TimeInterval) {
        guard let last else { return }
        let projected = last.elapsed + (last.playing ? Date().timeIntervalSince(last.updated) : 0)
        if abs(projected - t) > 2 { write() }
    }

    private func write() {
        guard let dir else { return }
        let file = dir.appendingPathComponent("nowplaying.json")
        guard let t = player.track else {
            if last != nil { try? FileManager.default.removeItem(at: file); last = nil; reload() }
            return
        }
        let snap = Snapshot(title: t.title, artist: t.artist, playing: player.isPlaying,
                            elapsed: player.currentTime,
                            duration: player.duration > 0 ? player.duration : (t.duration ?? 0),
                            updated: Date())
        last = snap
        try? JSONEncoder().encode(snap).write(to: file, options: .atomic)
        if artURL != t.artworkURL {
            artURL = t.artworkURL
            saveArt(t.artworkURL, to: dir.appendingPathComponent("art.jpg"))
        } else {
            reload()
        }
    }

    /// Downscaled to 300 px — widgets have a tight memory limit.
    private func saveArt(_ url: URL?, to file: URL) {
        guard let url else {
            try? FileManager.default.removeItem(at: file); reload(); return
        }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let jpeg = Self.thumbnail(data), artURL == url {
                try? jpeg.write(to: file, options: .atomic)
            }
            reload()
        }
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let src = NSImage(data: data) else { return nil }
        let side: CGFloat = 300
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Aspect-fill into the square (YouTube thumbnails are often 16:9).
        let s = src.size, scale = max(side / s.width, side / s.height)
        let w = s.width * scale, h = s.height * scale
        src.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    private func reload() { WidgetCenter.shared.reloadTimelines(ofKind: Self.kind) }
}
