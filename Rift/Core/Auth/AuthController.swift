// SPDX-License-Identifier: GPL-3.0-only
//
// AuthController — observable auth state. Presents the seamless Google sign-in
// webview, persists the captured session, fetches the account name/photo, and
// signs out (clearing Keychain + webview cookies).
//
// Also orchestrates the login-time account chooser: after the Google login
// captures cookies, it fetches the accounts list and, if multiple accounts
// (primary + brand) are available, presents a chooser so the user can select
// which identity to authenticate as. The selected account's identity is then
// applied via a shared-cookie WebView navigation and persisted.

import Foundation

@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var email: String?
    @Published private(set) var name: String?
    @Published private(set) var photoURL: URL?
    @Published var showingLogin = false

    // Account chooser state (login-time only, cleared after selection or cancel).
    @Published private(set) var pendingAuth: YTAuth?
    @Published private(set) var accounts: [UserAccount] = []
    @Published private(set) var isFetchingAccounts = false
    @Published private(set) var accountsError: String?

    init() {
        let a = AuthStore.load()
        isAuthenticated = a != nil
        email = a?.email
        name = a?.name
        photoURL = a?.photo.flatMap(URL.init(string:))
        if isAuthenticated { Task { await refreshAccount() } }
    }

    /// Called by the sign-in webview once a YTM session is captured.
    ///
    /// Instead of immediately completing, fetches the accounts list. If only one
    /// account is available (no brands), completes directly. If multiple, sets
    /// `pendingAuth` + `accounts` so the chooser UI can present them.
    func loginCaptured(_ auth: YTAuth) {
        Task { await fetchAccountsAndPresentChooser(for: auth) }
    }

    /// Fetches the accounts list and decides whether to show the chooser.
    private func fetchAccountsAndPresentChooser(for auth: YTAuth) async {
        isFetchingAccounts = true
        accountsError = nil
        defer { isFetchingAccounts = false }

        do {
            let response = try await InnerTubeClient.fetchAccountsList(auth: auth)
            if response.hasMultipleAccounts {
                // Show the chooser — don't persist yet.
                pendingAuth = auth
                accounts = response.accounts
            } else {
                // Single account (or empty) — complete directly with the
                // Google login's primary identity.
                accounts = response.accounts
                completed(auth)
            }
        } catch {
            // Fetch failed — show the error in the chooser so the user can
            // either continue with the primary identity or cancel. This keeps
            // the user informed rather than silently logging them in.
            accountsError = error.localizedDescription
            pendingAuth = auth
        }
    }

    /// Called when the user selects an account from the chooser.
    func selectAccount(_ account: UserAccount) async {
        guard let auth = pendingAuth else {
            return
        }
        // Brand account without a signinURL — can't switch to it. Surface an
        // error so the user can pick another account instead of silently
        // getting the primary identity.
        if account.brandId != nil, account.signinURL == nil {
            accountsError = "This brand account cannot be selected (no switch URL available)."
            return
        }
        do {
            let switchedAuth = try await GoogleSignInView.selectAccount(auth: auth, account: account)
            clearChooserState()
            completed(switchedAuth, account: account)
        } catch {
            accountsError = error.localizedDescription
        }
    }

    /// Cancels the account chooser and completes with the primary identity.
    func continueWithPrimary() {
        guard let auth = pendingAuth else { return }
        clearChooserState()
        completed(auth)
    }

    /// Cancels the chooser without completing — returns to the login screen.
    func cancelChooser() {
        clearChooserState()
        showingLogin = false
    }

    private func clearChooserState() {
        pendingAuth = nil
        accounts = []
        accountsError = nil
        isFetchingAccounts = false
    }

    /// Called when auth is ready to persist (after account selection or directly
    /// for single-account sessions). Saves to Keychain, updates state, and
    /// fetches the account name + photo for the active identity.
    /// When `account` is provided (brand selection), uses its name/handle/thumbnail
    /// directly instead of calling `accountInfo()`, which returns the Google
    /// account name rather than the YouTube channel identity.
    func completed(_ auth: YTAuth, account: UserAccount? = nil) {
        var authToSave = auth
        if let account {
            authToSave.brandId = account.brandId
        }
        AuthStore.save(authToSave)
        isAuthenticated = true
        showingLogin = false
        if let account {
            // Use the selected account's info directly — account/account_menu
            // returns the Google account name, not the brand channel name.
            name = account.name
            email = account.handle ?? email
            photoURL = account.thumbnailURL
            if var a = AuthStore.load() {
                a.name = account.name
                a.email = account.handle ?? a.email
                a.photo = account.thumbnailURL?.absoluteString
                AuthStore.save(a)
            }
        } else {
            Task { await refreshAccount() }
        }
    }

    func signOut() {
        AuthStore.clear()
        GoogleSignInView.clearWebData()
        isAuthenticated = false
        email = nil; name = nil; photoURL = nil
        clearChooserState()
    }

    /// Pull the signed-in account's name + avatar and persist them.
    func refreshAccount() async {
        guard let acc = try? await InnerTubeClient.accountInfo() else {
            return
        }
        name = acc.name
        email = acc.email ?? email
        photoURL = acc.photoURL
        if var a = AuthStore.load() {
            a.name = acc.name
            a.email = acc.email ?? a.email
            a.photo = acc.photoURL?.absoluteString
            AuthStore.save(a)
        }
    }
}
