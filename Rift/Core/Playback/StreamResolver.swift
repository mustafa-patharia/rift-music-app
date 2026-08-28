// SPDX-License-Identifier: GPL-3.0-only
//
// StreamResolver — resolves a YouTube videoId to a direct, AVPlayer-playable
// audio stream URL by shelling out to yt-dlp (out of process). yt-dlp owns the
// sig/nsig cipher and ships fixes when YouTube changes it; nothing in the UI
// touches the web. Isolated behind PlaybackSource so cipher breakage never
// reaches native playback code.

import Foundation

enum StreamResolverError: Error, LocalizedError {
    case binaryNotFound
    case failed(String)
    case noURL
    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "yt-dlp not found"
        case .failed(let m):  return "yt-dlp: \(m)"
        case .noURL:          return "no audio stream returned"
        }
    }
}

struct StreamResolver {
    /// Resolved stream: the direct audio URL plus the *real* duration reported by
    /// yt-dlp. AVPlayer mis-reads some YouTube m4a containers as ~2× length, so we
    /// trust yt-dlp's duration for the transport instead.
    struct Resolved: Sendable, Codable { let url: URL; let duration: TimeInterval?; let headers: [String: String] }

    /// Prefer format 140 (m4a/AAC) — AVPlayer plays it natively. opus/webm won't.
    /// Print URL, duration, and the HTTP headers yt-dlp would use. googlevideo
    /// CDN URLs 403 without the right User-Agent, so AVPlayer MUST send these —
    /// that's the "unknown error" when they're missing.
    /// Client selection is left to yt-dlp's own default (don't pin one — YouTube's
    /// PO-token requirements shift which client works, and yt-dlp tracks that
    /// upstream faster than we can; pinning one here previously locked us onto a
    /// client yt-dlp itself had already dropped as broken).
    static func resolveAudio(videoId: String) async throws -> Resolved {
        guard let cmd = await YtDlpManager.shared.command(), let exec = cmd.first
        else { throw StreamResolverError.binaryNotFound }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exec)
        proc.arguments = Array(cmd.dropFirst()) + [
            "-f", "140/bestaudio[ext=m4a]/bestaudio",
            "--no-playlist", "--no-warnings",
        ]
        proc.arguments! += [
            // Three lines: URL, duration (seconds), headers (JSON).
            "--print", "urls",
            "--print", "%(duration)s",
            "--print", "%(http_headers)j",
            "https://www.youtube.com/watch?v=\(videoId)",
        ]
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        let t0 = ContinuousClock.now
        try proc.run()
        proc.waitUntilExit()
        let took = Log.ms(since: t0)
        Log.resolve.info("yt-dlp \(videoId, privacy: .public) → \(took)ms (\((cmd.last! as NSString).lastPathComponent, privacy: .public))")

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(proc.terminationStatus)"
            Log.resolve.error("yt-dlp fail \(videoId, privacy: .public): \(msg, privacy: .public)")
            throw StreamResolverError.failed(msg)
        }
        let lines = (String(data: outData, encoding: .utf8) ?? "")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first, let url = URL(string: first) else {
            throw StreamResolverError.noURL
        }
        let duration = lines.count > 1 ? Double(lines[1]) : nil
        let headers = lines.count > 2 ? parseHeaders(lines[2]) : [:]
        return Resolved(url: url, duration: duration, headers: headers)
    }

    private static func parseHeaders(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj.compactMapValues { $0 as? String }
    }
}
