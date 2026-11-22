// SPDX-License-Identifier: GPL-3.0-only
//
// SyncedLyrics — finds lyrics for a track, trying sources in order until one
// answers, so a lyrical song is only bare when every source misses:
//
//   1. YouTube Music timed lyrics (LyricFind, via the Android app client)
//   2. LRCLIB (https://lrclib.net) — free, keyless, community LRC database
//   3. The song's official audio on YTM, when the playing video is an
//      upload/music video without its own Lyrics tab (matched by title,
//      artist and duration so a same-named song never leaks in)
//   Plain (untimed) text from any of these is the last resort.
//
// Measured one by one on 103 real played tracks (Nov 2026): 98 synced
// (YTM 91, LRCLIB 7), 2 plain-only (different-length cuts), 3 with nothing
// anywhere — two fan lofi covers/mashups and a re-upload credited to a channel.
//
// Evaluated: no maintained Swift LRCLIB/LRC package worth a dependency — the
// API is one GET and LRC is one regex, so it lives here.

import Foundation

struct LyricLine: Equatable, Identifiable {
    let time: TimeInterval
    let text: String
    var id: TimeInterval { time }
}

struct LyricsResult {
    var lines: [LyricLine]?
    var plain: String?
    var text: String? { plain ?? lines?.map(\.text).joined(separator: "\n") }
}

enum SyncedLyrics {
    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    /// Best lyrics for a track across every source; nil when none has any.
    static func resolve(_ track: PlayableTrack, duration: TimeInterval?) async -> LyricsResult? {
        var result = LyricsResult()

        // 1. YTM for the exact video.
        if let r = await ytm(videoId: track.id) {
            if r.lines != nil { return r }
            result.plain = r.plain
        }
        // 2. LRCLIB.
        let lrc = await lrclib(title: track.title, artist: track.artist, duration: duration)
        if let lines = lrc.lines { result.lines = lines; return result }
        result.plain = result.plain ?? lrc.plain

        // 3. Official audio of the same song on YTM. A different-length cut
        //    (radio edit, slowed upload) only lends its words, not its timing.
        let versions = await officialVersions(of: track, duration: duration)
        for v in versions {
            guard let r = await ytm(videoId: v.id) else { continue }
            if v.sameLength, let lines = r.lines { result.lines = lines; return result }
            result.plain = result.plain ?? r.plain ?? r.lines.map { $0.map(\.text).joined(separator: "\n") }
            if result.plain != nil && !versions.contains(where: \.sameLength) { break }
        }
        return result.text == nil ? nil : result
    }

    private static func ytm(videoId: String) async -> LyricsResult? {
        guard let bid = (try? await InnerTubeClient.lyricsBrowseId(videoId: videoId)) ?? nil else { return nil }
        if let lines = (try? await InnerTubeClient.timedLyrics(browseId: bid)) ?? nil {
            return LyricsResult(lines: lines, plain: nil)
        }
        let plain = (try? await InnerTubeClient.lyrics(browseId: bid)) ?? nil
        return plain.map { LyricsResult(lines: nil, plain: $0) }
    }

    /// Same title (version tag included) + artist, different video. Same-length
    /// (±10s) matches first; those are the only ones trusted for timing.
    private static func officialVersions(of track: PlayableTrack, duration: TimeInterval?) async -> [(id: String, sameLength: Bool)] {
        let title = cleanTitle(track.title), artist = primaryArtist(track.artist)
        guard !title.isEmpty,
              let hits = try? await InnerTubeClient.searchSongs("\(title) \(artist)") else { return [] }
        let t = norm(title), a = norm(artist)
        return hits.prefix(5).compactMap { h -> (id: String, sameLength: Bool)? in
            guard h.id != track.id, norm(cleanTitle(h.title)) == t,
                  a.isEmpty || norm(h.artist).contains(a) else { return nil }
            let same = duration.flatMap { d in h.duration.map { abs($0 - d) <= 10 } } ?? true
            return (h.id, same)
        }.sorted { $0.sameLength && !$1.sameLength }
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// LRCLIB: exact signature first, then progressively looser searches.
    private static func lrclib(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult {
        let t = cleanTitle(title), a = primaryArtist(artist)
        guard !t.isEmpty else { return LyricsResult() }
        var plain: String?

        if let d = duration, d > 0,
           let rec: Record = await get("get", ["track_name": t, "artist_name": a, "duration": String(Int(d.rounded()))]) {
            if let lines = parse(rec.syncedLyrics) { return LyricsResult(lines: lines, plain: nil) }
            plain = rec.plainLyrics?.nilIfBlank
        }
        // Title-only search catches uploads credited to a channel instead of
        // the artist; it's only trusted at a tight ±3s.
        let queries: [([String: String], Double)] = [
            (["track_name": t, "artist_name": a], 8), (["q": "\(t) \(a)"], 8), (["track_name": t], 3),
        ]
        for (q, tolerance) in queries {
            guard let results: [Record] = await get("search", q), !results.isEmpty else { continue }
            // Duration guards against a different song with the same name.
            let near = duration.map { d in results.filter { abs(($0.duration ?? 0) - d) <= tolerance } } ?? results
            let byCloseness = near.sorted {
                abs(($0.duration ?? 0) - (duration ?? 0)) < abs(($1.duration ?? 0) - (duration ?? 0))
            }
            if let lines = byCloseness.lazy.compactMap({ parse($0.syncedLyrics) }).first {
                return LyricsResult(lines: lines, plain: nil)
            }
            plain = plain ?? byCloseness.lazy.compactMap({ $0.plainLyrics?.nilIfBlank }).first
            // Same song, different cut (edit / slowed upload): words only.
            if plain == nil {
                let tn = norm(t), an = norm(a)
                plain = results.lazy.filter {
                    norm(cleanTitle($0.trackName ?? "")) == tn && (an.isEmpty || norm($0.artistName ?? "").contains(an))
                }.compactMap {
                    $0.plainLyrics?.nilIfBlank ?? parse($0.syncedLyrics)?.map(\.text).joined(separator: "\n")
                }.first
            }
        }
        return LyricsResult(lines: nil, plain: plain)
    }

    private static func get<T: Decodable>(_ path: String, _ query: [String: String]) async -> T? {
        var c = URLComponents(string: "https://lrclib.net/api/\(path)")!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Rift (macOS music player)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// `[mm:ss.xx] text` → lines. Multiple stamps on one line are expanded.
    static func parse(_ lrc: String?) -> [LyricLine]? {
        guard let lrc, !lrc.isEmpty else { return nil }
        let stamp = #/\[(\d+):(\d+(?:\.\d+)?)\]/#
        var out: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let stamps = line.matches(of: stamp)
            guard let last = stamps.last else { continue }
            let text = String(line[last.range.upperBound...]).trimmingCharacters(in: .whitespaces)
            for m in stamps {
                let t = (Double(m.output.1) ?? 0) * 60 + (Double(m.output.2) ?? 0)
                out.append(LyricLine(time: t, text: text))
            }
        }
        out.sort { $0.time < $1.time }
        return out.isEmpty ? nil : out
    }

    /// YouTube titles carry noise: "Song (Official Video) | Album || Label".
    /// Drops only noise brackets — "(Official Video)", "[Lyrics]", "(From "Film")",
    /// "(feat. X)". Version tags like "(Reprise)", "(Acoustic)", "(Hindi)" stay:
    /// they're different songs with different lyrics.
    static func cleanTitle(_ s: String) -> String {
        var t = s.components(separatedBy: "|").first ?? s
        let noise = #"(?i)\s*[\(\[][^\)\]]*\b(official|video|lyrics?|lyrical|audio|visuali[sz]er|full song|hd|4k|from|feat\.?|ft\.?|with|prod\.?)\b[^\)\]]*[\)\]]"#
        t = t.replacingOccurrences(of: noise, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)\s*-\s*(official|lyric|lyrics|audio|video).*$"#, with: "",
                                   options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func primaryArtist(_ s: String) -> String {
        let first = s.components(separatedBy: CharacterSet(charactersIn: "&,")).first ?? s
        return first.replacingOccurrences(of: #"(?i)\s+(feat\.?|ft\.?|x)\s+.*$"#, with: "",
                                          options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Index of the line being sung at `time` (last line whose stamp has passed).
    static func activeIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        var lo = 0, hi = lines.count - 1, ans: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
