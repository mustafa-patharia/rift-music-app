// SPDX-License-Identifier: GPL-3.0-only
//
// AccountsListParser — parses the YouTube Music `account/accounts_list` API
// response to extract the user's available accounts (primary + brand accounts).
// Protocol knowledge only; parsing structure adapted from kaset
// `Sources/Kaset/Services/API/Parsers/AccountsListParser.swift`.

import Foundation

/// Response containing the list of available user accounts from
/// `account/accounts_list`.
struct AccountsListResponse {
    /// The Google email address associated with the primary account (optional).
    let googleEmail: String?
    /// All available accounts (primary + brand accounts).
    let accounts: [UserAccount]

    /// Whether multiple accounts are available for selection.
    var hasMultipleAccounts: Bool { accounts.count > 1 }
}

/// Parser for the YouTube Music accounts list API response.
///
/// Walks the multi-page menu renderer to extract each account's name, handle,
/// thumbnail, brand id (from `pageIdToken.pageId`), and switch URL (from
/// `accountSigninToken.signinUrl`).
enum AccountsListParser {
    // MARK: - Public API

    /// Parses the accounts list API response.
    ///
    /// - Parameter json: The raw JSON response from the accounts list API.
    /// - Returns: An `AccountsListResponse` containing parsed accounts,
    ///   or an empty response on failure.
    static func parse(_ json: [String: Any]) -> AccountsListResponse {
        // Navigate to the multi-page menu renderer.
        guard let actions = json["actions"] as? [[String: Any]],
              let firstAction = actions.first,
              let getMultiPageMenuAction = firstAction["getMultiPageMenuAction"] as? [String: Any],
              let menu = getMultiPageMenuAction["menu"] as? [String: Any],
              let multiPageMenuRenderer = menu["multiPageMenuRenderer"] as? [String: Any],
              let sections = multiPageMenuRenderer["sections"] as? [[String: Any]]
        else {
            return AccountsListResponse(googleEmail: nil, accounts: [])
        }

        var googleEmail: String?
        var accounts: [UserAccount] = []

        for section in sections {
            guard let accountSectionListRenderer =
                section["accountSectionListRenderer"] as? [String: Any]
            else { continue }

            // Extract Google email from header (once).
            if googleEmail == nil {
                googleEmail = extractGoogleEmail(from: accountSectionListRenderer)
            }

            // Parse account items from contents.
            if let contents =
                accountSectionListRenderer["contents"] as? [[String: Any]]
            {
                for content in contents {
                    guard
                        let accountItemSection =
                            content["accountItemSectionRenderer"] as? [String: Any],
                        let accountItems =
                            accountItemSection["contents"] as? [[String: Any]]
                    else { continue }

                    for accountItemWrapper in accountItems {
                        if let account = parseAccountItem(accountItemWrapper) {
                            accounts.append(account)
                        }
                    }
                }
            }
        }

        return AccountsListResponse(googleEmail: googleEmail, accounts: accounts)
    }

    // MARK: - URL helpers

    /// Resolves an `accountSigninToken.signinUrl` into an absolute URL.
    ///
    /// The API returns this as a root-relative path (`/signin?...`); it must be
    /// resolved against the YouTube origin. Also handles protocol-relative and
    /// already-absolute forms defensively.
    static func resolveSigninURL(
        _ urlString: String, origin: String = "https://www.youtube.com"
    ) -> URL? {
        let resolvedURL: URL? =
            if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                URL(string: urlString)
            } else if urlString.hasPrefix("//") {
                URL(string: "https:" + urlString)
            } else if urlString.hasPrefix("/") {
                URL(string: urlString, relativeTo: URL(string: origin))?.absoluteURL
            } else {
                URL(string: urlString)
            }
        guard let resolvedURL, isAllowedSigninURL(resolvedURL) else { return nil }
        return resolvedURL
    }

    /// Validates that a signin URL points to the YouTube signin endpoint over HTTPS.
    static func isAllowedSigninURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "www.youtube.com"
            && url.path == "/signin"
    }

    // MARK: - Private helpers

    /// Extracts the Google email from the account section header.
    private static func extractGoogleEmail(
        from accountSection: [String: Any]
    ) -> String? {
        guard let header = accountSection["header"] as? [String: Any],
              let googleAccountHeaderRenderer =
                  header["googleAccountHeaderRenderer"] as? [String: Any],
              let email = googleAccountHeaderRenderer["email"] as? [String: Any],
              let runs = email["runs"] as? [[String: Any]],
              let firstRun = runs.first,
              let emailText = firstRun["text"] as? String
        else { return nil }
        return emailText
    }

    /// Parses a single account item from the API response.
    private static func parseAccountItem(_ item: [String: Any]) -> UserAccount? {
        guard let accountItem = item["accountItem"] as? [String: Any] else {
            return nil
        }

        // Account name (required).
        guard let accountNameData = accountItem["accountName"] as? [String: Any],
              let nameRuns = accountNameData["runs"] as? [[String: Any]],
              let firstNameRun = nameRuns.first,
              let name = firstNameRun["text"] as? String,
              !name.isEmpty
        else { return nil }

        // Channel handle (optional).
        var handle: String?
        if let channelHandleData = accountItem["channelHandle"] as? [String: Any],
           let handleRuns = channelHandleData["runs"] as? [[String: Any]],
           let firstHandleRun = handleRuns.first,
           let handleText = firstHandleRun["text"] as? String
        {
            handle = handleText
        }

        // Thumbnail URL (optional).
        var thumbnailURL: URL?
        if let accountPhoto = accountItem["accountPhoto"] as? [String: Any],
           let thumbnails = accountPhoto["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let urlString = lastThumbnail["url"] as? String
        {
            thumbnailURL = URL(string: normalizeURL(urlString))
        }

        // Identity tokens: brandId + server-issued switch URL.
        let identity = extractIdentityTokens(from: accountItem)

        return UserAccount.from(
            name: name,
            handle: handle,
            brandId: identity.brandId,
            thumbnailURL: thumbnailURL,
            signinURL: identity.signinURL
        )
    }

    /// Extracts identity material from `selectActiveIdentityEndpoint.supportedTokens`.
    ///
    /// - `brandId`: from `pageIdToken.pageId` (nil for the primary account).
    /// - `signinURL`: from `accountSigninToken.signinUrl` — the server-issued
    ///   account-switch endpoint.
    private static func extractIdentityTokens(
        from accountItem: [String: Any]
    ) -> (brandId: String?, signinURL: URL?) {
        guard let serviceEndpoint = accountItem["serviceEndpoint"] as? [String: Any],
              let activeIdentity =
                  serviceEndpoint["selectActiveIdentityEndpoint"] as? [String: Any],
              let entries = activeIdentity["supportedTokens"] as? [[String: Any]]
        else { return (nil, nil) }

        var brandId: String?
        var signinURL: URL?
        for entry in entries {
            if brandId == nil,
               let pageIdToken = entry["pageIdToken"] as? [String: Any],
               let pageId = pageIdToken["pageId"] as? String
            {
                brandId = pageId
            }
            if signinURL == nil,
               let signinToken = entry["accountSigninToken"] as? [String: Any],
               let urlString = signinToken["signinUrl"] as? String
            {
                signinURL = resolveSigninURL(urlString)
            }
        }
        return (brandId, signinURL)
    }

    /// Normalizes a protocol-relative URL to https.
    private static func normalizeURL(_ urlString: String) -> String {
        urlString.hasPrefix("//") ? "https:" + urlString : urlString
    }
}
