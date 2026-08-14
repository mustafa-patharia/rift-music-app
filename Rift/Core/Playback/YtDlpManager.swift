// SPDX-License-Identifier: GPL-3.0-only
//
// YtDlpManager — owns the yt-dlp the app actually runs.
//
// Everything playback needs ships INSIDE the app: a trimmed relocatable CPython
// (Resources/python-arm64.tar.gz) and the 3 MB zipimport yt-dlp
// (Resources/yt-dlp.zip), both built by Scripts/fetch-engine.sh. First launch
// unpacks them into Application Support (~0.5s) and that's the whole setup —
// no download, no Homebrew, no admin password, no button to press, and a Mac
// that has never had developer tools plays a song at the same speed as one that
// has. Resolve cost is ~0.5s per cold song.
//
// They ship as compressed DATA, not loose Mach-O inside the bundle, so the app
// signs with no nested-code handling — and the unpacked binaries keep the
// upstream ad-hoc signature that makes them runnable.
//
// A user who already has a Homebrew yt-dlp gets that instead (marginally
// faster, and it's the copy they maintain).
//
// The one thing still fetched from the network is an updated yt-dlp: when a
// resolve fails, YouTube has usually changed its cipher and the fix ships in a
// newer yt-dlp, so update() pulls one. Best-effort and silent — offline, the
// bundled copy keeps working.

import Foundation

actor YtDlpManager {
    static let shared = YtDlpManager()

    // Platform-independent zipimport build — same flavor we bundle, so an update
    // is a drop-in replacement for the bundled copy.
    private static let zipDownloadURL = URL(string:
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    private static let updateThrottle: TimeInterval = 6 * 3600   // don't re-pull more than this often
    private static let lastUpdateKey = "ytdlp.lastUpdate"
    /// Which bundled engine build is unpacked — re-unpack when the app updates.
    private static let unpackedStampKey = "ytdlp.unpackedStamp"

    private let zipURL: URL           // …/bin/yt-dlp.zip (zipimport, run via python3)
    private let pyRootURL: URL        // …/bin/python (unpacked CPython)
    private var inFlight: Task<Bool, Never>?   // dedup concurrent downloads (actor reentrancy)
    private var preparing: Task<Bool, Never>?  // dedup concurrent prepare() calls (actor reentrancy)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.mustafapatharia.riftmusicapp/bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        zipURL = base.appendingPathComponent("yt-dlp.zip")
        pyRootURL = base.appendingPathComponent("python", isDirectory: true)
    }

    // MARK: unpacking the bundled engine

    /// Unpack the bundled engine if it isn't already. Called at launch; cheap and
    /// idempotent after the first run. Returns false only if the app bundle is
    /// damaged or the disk is full — playback then falls back to a system yt-dlp
    /// if the user happens to have one.
    @discardableResult
    func prepare() async -> Bool {
        if let t = preparing { return await t.value }
        let t = Task { await self.performPrepare() }
        preparing = t
        let ok = await t.value
        preparing = nil
        return ok
    }

    private func performPrepare() async -> Bool {
        let stamp = Self.bundleStamp()
        let unpacked = FileManager.default.isExecutableFile(atPath: pythonExecURL.path)
            && FileManager.default.fileExists(atPath: zipURL.path)
        if unpacked, UserDefaults.standard.string(forKey: Self.unpackedStampKey) == stamp {
            return true
        }
        guard let tar = Bundle.main.url(forResource: "python-arm64", withExtension: "tar.gz"),
              let zip = Bundle.main.url(forResource: "yt-dlp", withExtension: "zip")
        else {
            Log.ytdlp.error("bundled engine missing from app resources")
            return false
        }
        Log.ytdlp.info("unpacking bundled engine…")
        guard await unpackPython(tar) else { return false }
        // Only replace the yt-dlp copy from the bundle on a fresh unpack —
        // otherwise an app update would undo a newer yt-dlp update() pulled.
        do {
            try? FileManager.default.removeItem(at: zipURL)
            try FileManager.default.copyItem(at: zip, to: zipURL)
        } catch {
            Log.ytdlp.error("copying bundled yt-dlp failed")
            return false
        }
        // Verify the UNPACKED engine specifically — not command(), which would
        // hand back a Homebrew yt-dlp on a dev Mac and stamp success without
        // ever proving the copy we ship to everyone else works.
        guard Self.runsOK([pythonExecURL.path, zipURL.path]) else {
            Log.ytdlp.error("unpacked engine won't run")
            return false
        }
        UserDefaults.standard.set(stamp, forKey: Self.unpackedStampKey)
        Log.ytdlp.info("bundled engine ready")
        return true
    }

    /// Identifies the engine build inside the current app bundle, so a Rift
    /// update ships a new python/yt-dlp and we notice.
    private static func bundleStamp() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(s)-\(v)"
    }

    private var pythonExecURL: URL { pyRootURL.appendingPathComponent("bin/python3") }

    /// Untar into a staging dir and swap it in, so a half-extracted archive can
    /// never be mistaken for a working python.
    private func unpackPython(_ tar: URL) async -> Bool {
        let fm = FileManager.default
        let staging = pyRootURL.appendingPathExtension("new")
        try? fm.removeItem(at: staging)
        do { try fm.createDirectory(at: staging, withIntermediateDirectories: true) }
        catch { return false }
        guard await Self.run("/usr/bin/tar", ["xzf", tar.path, "-C", staging.path]) else {
            try? fm.removeItem(at: staging); return false
        }
        guard Self.pythonVersionOK(staging.appendingPathComponent("bin/python3").path) else {
            try? fm.removeItem(at: staging); return false
        }
        try? fm.removeItem(at: pyRootURL)
        do { try fm.moveItem(at: staging, to: pyRootURL) } catch { return false }
        return true
    }

    // MARK: running it

    /// The argv to run yt-dlp with: a user's own Homebrew copy if they maintain
    /// one, else the bundled engine (unpacking it if launch hasn't yet).
    func command() async -> [String]? {
        if let sys = Self.brewFallback() { return [sys] }
        if let python = pythonPath(), FileManager.default.fileExists(atPath: zipURL.path) {
            return [python, zipURL.path]
        }
        // A play that beat prepare() to it, or a wiped support folder.
        guard await prepare(), let python = pythonPath() else { return nil }
        return [python, zipURL.path]
    }

    /// Pull the latest yt-dlp (the cipher-breakage self-heal). Throttled so a burst
    /// of transient failures doesn't re-download each time. Homebrew installs are
    /// updated through brew; ours by replacing the zip.
    @discardableResult
    func update(force: Bool = false) async -> Bool {
        if !force {
            let last = UserDefaults.standard.double(forKey: Self.lastUpdateKey)
            if last > 0, Date().timeIntervalSince1970 - last < Self.updateThrottle { return false }
        }
        let ok: Bool
        if Self.brewFallback() != nil, let brew = Self.brewPath() {
            let upgraded = await Self.run(brew, ["upgrade", "yt-dlp"])
            // `upgrade` exits non-zero when already newest — that's still "ok".
            ok = upgraded || Self.brewFallback() != nil
        } else {
            ok = await downloadZip()
        }
        if ok { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastUpdateKey) }
        Log.ytdlp.info("update yt-dlp \(ok ? "ok" : "no-op/failed", privacy: .public)")
        return ok
    }

    /// Single in-flight download shared by all callers.
    private func downloadZip() async -> Bool {
        if let t = inFlight { return await t.value }
        let t = Task { await self.performDownload() }
        inFlight = t
        let ok = await t.value
        inFlight = nil
        return ok
    }

    private func performDownload() async -> Bool {
        let fm = FileManager.default
        let staging = zipURL.appendingPathExtension("new")
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: Self.zipDownloadURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            try? fm.removeItem(at: staging)
            try fm.moveItem(at: tmp, to: staging)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
            // Verify the download actually runs before trusting it — a truncated
            // fetch must never replace the working bundled copy.
            guard let python = pythonPath(), Self.runsOK([python, staging.path]) else {
                try? fm.removeItem(at: staging); return false
            }
            try? fm.removeItem(at: zipURL)
            try fm.moveItem(at: staging, to: zipURL)   // atomic swap
            Log.ytdlp.info("downloaded newer yt-dlp")
            return true
        } catch {
            try? fm.removeItem(at: staging)
            return false
        }
    }

    private static func runsOK(_ argv: [String]) -> Bool { version(argv) != nil }

    /// `yt-dlp --version` output, or nil if it doesn't run — doubles as the
    /// "is this binary actually usable" check.
    private static func version(_ argv: [String]) -> String? {
        guard let exec = argv.first else { return nil }
        let out = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = Array(argv.dropFirst()) + ["--version"]
        p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    /// Our unpacked python first. The system candidates stay only as a safety net
    /// for a damaged unpack — never /usr/bin/python3, which is a shim that pops
    /// the Command Line Tools install dialog on Macs without developer tools.
    /// Result cached: the probe spawns a process per candidate.
    private var cachedPython: String??
    private func pythonPath() -> String? {
        if let c = cachedPython { return c }
        let candidates = [
            pythonExecURL.path,                                                  // bundled, unpacked
            "/opt/homebrew/bin/python3", "/usr/local/bin/python3",               // Homebrew
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", // python.org
        ]
        let found = candidates.first { Self.pythonVersionOK($0) }
        if found != nil { cachedPython = .some(found) }   // don't cache "missing" before unpack
        return found
    }

    /// Runs `python3 --version` and checks ≥3.10 (yt-dlp's floor).
    private static func pythonVersionOK(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let out = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--version"]
        p.standardOutput = out; p.standardError = out
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let ver = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").last
        else { return false }
        let parts = ver.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 10)
    }

    /// Run an executable to completion. Async so the blocking wait runs off the actor.
    private static func run(_ path: String, _ args: [String]) async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
    }

    private static func brewFallback() -> String? {
        ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
