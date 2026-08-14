// SPDX-License-Identifier: GPL-3.0-only
//
// AuthController — observable auth state. Presents the seamless Google sign-in
// webview, persists the captured session, fetches the account name/photo, and
// signs out (clearing Keychain + webview cookies).

import Foundation

@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var email: String?
    @Published private(set) var name: String?
    @Published private(set) var photoURL: URL?
    @Published var showingLogin = false

    init() {
        let a = AuthStore.load()
        isAuthenticated = a != nil
        email = a?.email
        name = a?.name
        photoURL = a?.photo.flatMap(URL.init(string:))
        if isAuthenticated { Task { await refreshAccount() } }
    }

    /// Entry point for every "Sign In" button: opens the embedded cookie webview.
    func signIn() {
        showingLogin = true
    }

    /// Called by the sign-in webview once a YTM session is captured.
    func completed(_ auth: YTAuth) {
        AuthStore.save(auth)
        isAuthenticated = true
        showingLogin = false
        Task { await refreshAccount() }
    }

    func signOut() {
        AuthStore.clear()
        GoogleSignInView.clearWebData()
        isAuthenticated = false
        email = nil; name = nil; photoURL = nil
    }

    /// Pull the signed-in account's name + avatar and persist them.
    func refreshAccount() async {
        guard let acc = try? await InnerTubeClient.accountInfo() else { return }
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
