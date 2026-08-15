// SPDX-License-Identifier: GPL-3.0-only
//
// Log — unified logging (os.Logger). Visible in Console.app and via
//   log stream --predicate 'subsystem == "com.mustafapatharia.riftmusicapp"' --level debug
// Survives a normal `open` launch (unlike print, which needs a terminal launch).

import os

enum Log {
    static let subsystem = "com.mustafapatharia.riftmusicapp"
    static let player  = Logger(subsystem: subsystem, category: "player")
    static let resolve = Logger(subsystem: subsystem, category: "resolve")
    static let ytdlp   = Logger(subsystem: subsystem, category: "ytdlp")
    static let auth    = Logger(subsystem: subsystem, category: "auth")
    static let ui       = Logger(subsystem: subsystem, category: "ui")

    /// Milliseconds since a start instant — for "where did the time go" timing.
    static func ms(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
