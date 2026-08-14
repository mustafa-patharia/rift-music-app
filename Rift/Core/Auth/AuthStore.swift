// SPDX-License-Identifier: GPL-3.0-only
//
// AuthStore — the persisted YT Music session: the cookie header plus the SAPISID
// used to sign InnerTube requests (SAPISIDHASH). Kept in the Keychain. Read from
// the network layer on every authenticated request. Seamless webview login — no
// OAuth client, nothing for the user to set up.

import Foundation

struct YTAuth: Codable, Equatable {
    var cookie: String   // full "Cookie:" header value
    var sapisid: String  // SAPISID / __Secure-3PAPISID value, for SAPISIDHASH
    var email: String?   // display only, optional
    var name: String?    // account display name
    var photo: String?   // account avatar URL
    var brandId: String? // brand account ID for onBehalfOfUser; nil for primary
}

enum AuthStore {
    private static let account = "ytmusic-session"

    static func save(_ auth: YTAuth) {
        guard let data = try? JSONEncoder().encode(auth) else { return }
        Keychain.set(data, account: account)
    }

    static func load() -> YTAuth? {
        Keychain.get(account: account).flatMap { try? JSONDecoder().decode(YTAuth.self, from: $0) }
    }

    static func clear() { Keychain.delete(account: account) }

    static var isAuthenticated: Bool { load() != nil }
}
