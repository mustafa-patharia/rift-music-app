// SPDX-License-Identifier: GPL-3.0-only
//
// ListenerProfile — who someone is in a room or nearby: a name, an optional
// photo (the signed-in Google account's picture) and a colour for the
// initials bubble when there's no photo. Shared only with people in the same
// room / connected nearby — the Together tab says so.

import AppKit

struct ListenerProfile: Codable, Equatable, Identifiable, Hashable {
    let id: String
    var name: String
    var photo: URL?

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "♪" : s.uppercased()
    }

    /// Stable 0…1 hue from the name (Swift's hashValue is randomised per
    /// launch, so it can't be used — everyone must see the same colour).
    var hue: Double {
        let h = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Double(h % 360) / 360
    }

    /// This Mac's listener: the YouTube Music account if signed in, else the
    /// macOS user's name. A fresh id per launch keeps rooms anonymous.
    private static let myID = UUID().uuidString

    @MainActor
    static var mine: ListenerProfile {
        let auth = AppServices.shared.auth
        let fallback = NSFullUserName().isEmpty ? "Listener" : NSFullUserName()
        return ListenerProfile(id: myID, name: auth.name ?? fallback, photo: auth.photoURL)
    }
}
