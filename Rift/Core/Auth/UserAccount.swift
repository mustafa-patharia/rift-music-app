// SPDX-License-Identifier: GPL-3.0-only
//
// UserAccount — a YouTube Music identity (primary Google account or a brand
// account). Used by the login-time account chooser to let the user pick which
// identity to authenticate as. Protocol knowledge only; no code ported.
//
// Ref: kaset `Sources/Kaset/Models/UserAccount.swift` (model concept, simplified).

import Foundation

/// Represents a YouTube Music user account (primary or brand account).
///
/// YouTube Music allows users to have multiple accounts:
/// - **Primary account**: The main Google account (no `brandId`)
/// - **Brand accounts**: Managed channel accounts associated with the primary
///
/// The `signinURL` is a server-issued endpoint (from `accountSigninToken.signinUrl`)
/// that, when navigated to in a shared-cookie WebView, re-points the session's
/// active delegated identity. Brand accounts carry a `pageid` in this URL; the
/// primary's URL omits it.
struct UserAccount: Identifiable, Equatable {
    /// Unique identifier: `brandId` for brand accounts, "primary" for the main account.
    let id: String

    /// Display name of the account.
    let name: String

    /// Channel handle (e.g., "@username"), if available.
    let handle: String?

    /// Brand account identifier, nil for primary accounts.
    let brandId: String?

    /// Server-issued account-switch endpoint. Navigating a shared-cookie WebView
    /// to this URL re-points the active delegated identity for the session.
    /// Credential-bearing: never log the raw value.
    let signinURL: URL?

    /// URL for the account's profile photo thumbnail.
    let thumbnailURL: URL?

    /// Returns `true` if this is the primary Google account (not a brand account).
    var isPrimary: Bool { brandId == nil }

    /// Human-readable label: "Personal" for primary, "Brand" for brand accounts.
    var typeLabel: String { isPrimary ? "Personal" : "Brand" }

    /// Creates a UserAccount from API response fields, auto-deriving the id.
    ///
    /// - Parameters:
    ///   - name: Display name from `accountName.runs[0].text`.
    ///   - handle: Optional handle from `channelHandle.runs[0].text`.
    ///   - brandId: Brand ID from `pageIdToken.pageId`, nil for primary account.
    ///   - thumbnailURL: Thumbnail URL from `accountPhoto.thumbnails.last.url`.
    ///   - signinURL: Switch URL from `accountSigninToken.signinUrl`.
    static func from(
        name: String,
        handle: String?,
        brandId: String?,
        thumbnailURL: URL?,
        signinURL: URL? = nil
    ) -> UserAccount {
        UserAccount(
            id: brandId ?? "primary",
            name: name,
            handle: handle,
            brandId: brandId,
            signinURL: signinURL,
            thumbnailURL: thumbnailURL
        )
    }
}
