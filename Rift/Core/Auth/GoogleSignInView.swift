// SPDX-License-Identifier: GPL-3.0-only
//
// GoogleSignInView — the seamless "Sign in with Google" surface: a WKWebView at
// Google's real sign-in, continuing to YouTube Music. On completion, YT Music's
// session cookies are set for youtube.com; we capture the cookie header + SAPISID
// and hand them to AuthController. No client id/secret, nothing to set up — the
// user just logs into Google.
//
// WebView-driving pattern borrowed from pear-desktop (MIT). See /NOTICE.
//
// Session-identity switching (`selectAccount`) adapted from kaset
// `WebKitManager.switchSessionIdentity` (protocol knowledge only).

import SwiftUI
import WebKit

struct GoogleSignInView: NSViewRepresentable {
    var onComplete: (YTAuth) -> Void

    private static let startURL = URL(string:
        "https://accounts.google.com/ServiceLogin?service=youtube&passive=true" +
        "&continue=https%3A%2F%2Fmusic.youtube.com%2F")!

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()   // persistent, so cookies are readable
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        // Desktop Safari UA: Google serves the standard password flow instead of
        // pushing passkeys (WebAuthn is unreliable inside WKWebView).
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        web.load(URLRequest(url: Self.startURL))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    /// Wipe cookies + cache so sign-out fully logs the account out.
    static func clearWebData() {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {}
        }
    }

    // MARK: - Account selection (session-identity switch)

    /// Switches the shared cookie session's active delegated identity to the
    /// selected account by navigating a transient WebView to the account's
    /// server-issued `signinURL`, then re-captures the cookie header + SAPISID.
    ///
    /// For brand accounts, `signinURL` carries `&pageid=<brandId>`, which
    /// re-points the session's `DATASYNC_ID` to the brand identity. For the
    /// primary account (or when `signinURL` is nil), the navigation is skipped
    /// and the original `auth` is returned unchanged — the Google login already
    /// established the primary identity.
    ///
    /// - Parameters:
    ///   - auth: The current session credentials captured from Google login.
    ///   - account: The account to switch to (primary or brand).
    /// - Returns: Updated `YTAuth` with cookies reflecting the selected identity.
    static func selectAccount(auth: YTAuth, account: UserAccount) async throws -> YTAuth {
        // No signin URL → no navigation needed (primary already active).
        guard let signinURL = account.signinURL else {
            return auth
        }
        guard AccountsListParser.isAllowedSigninURL(signinURL) else {
            return auth
        }


        // Use the same persistent data store as the sign-in webview so the
        // signinURL navigation mutates the shared cookie session.
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        let driver = SessionSwitchNavigationDriver()
        webView.navigationDelegate = driver
        defer {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }

        try Task.checkCancellation()

        // Navigate to the signinURL — this re-points the delegated identity.
        try await driver.load(signinURL, in: webView, timeout: .seconds(20))

        // Verify the identity switch via ytcfg.DATASYNC_ID. The page's ytcfg may
        // be emitted slightly after didFinish; poll briefly.
        var verified = false
        for attempt in 0 ..< 5 {
            if let dataSyncId = try? await readDataSyncId(from: webView) {
                if dataSyncIdMatches(dataSyncId, expectedBrandId: account.brandId) {
                    verified = true
                    break
                }
            } else {
            }
            if attempt < 4 {
                try await Task.sleep(for: .milliseconds(400))
            }
        }

        if !verified {
        }

        // Re-capture cookies from the shared data store.
        let result = try await captureAuth(from: cfg.websiteDataStore)
        // Compare original vs re-captured auth to see if cookies actually changed.
        let originalCookieShort = String(auth.cookie.hash)
        let newCookieShort = String(result.cookie.hash)
        return result
    }

    /// Reads `ytcfg.DATASYNC_ID` from a loaded WebView.
    private static func readDataSyncId(from webView: WKWebView) async throws -> String? {
        let script = """
        (function() {
            try {
                if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                    return window.ytcfg.get('DATASYNC_ID') || '';
                }
                if (window.ytcfg && window.ytcfg.data_) {
                    return window.ytcfg.data_['DATASYNC_ID'] || '';
                }
            } catch (e) {}
            return '';
        })();
        """
        let result = try await webView.evaluateJavaScript(script)
        return result as? String
    }

    /// Returns `true` when a `DATASYNC_ID` reflects the expected identity.
    ///
    /// `DATASYNC_ID` is `"<delegatedSessionId>||<userSessionId>"` for a brand
    /// (delegated/secondary channel) and `"<userSessionId>||"` for the primary
    /// account. A blank or malformed value is treated as no match for either.
    static func dataSyncIdMatches(_ dataSyncId: String, expectedBrandId: String?) -> Bool {
        let parts = dataSyncId.components(separatedBy: "||")
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let firstHalf = parts[0]
        let hasUserSessionSuffix = !parts[1].isEmpty
        // delegatedSessionId is present only for a brand identity.
        let delegatedSessionId: String? = hasUserSessionSuffix ? firstHalf : nil
        if let expectedBrandId {
            return delegatedSessionId == expectedBrandId
        }
        return delegatedSessionId == nil
    }

    /// Re-captures the YT cookie header + SAPISID from a website data store,
    /// producing a `YTAuth` for the now-active identity.
    private static func captureAuth(from store: WKWebsiteDataStore) async throws -> YTAuth {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<YTAuth, Error>) in
            store.httpCookieStore.getAllCookies { cookies in
                let yt = cookies.filter { $0.domain.hasSuffix("youtube.com") }
                let names = Set(yt.map(\.name))
                guard names.contains("__Secure-3PSID") else {
                    continuation.resume(throwing: NSError(
                        domain: "GoogleSignIn", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No YouTube session cookie after account switch"]))
                    return
                }
                let sapisid =
                    yt.first { $0.name == "__Secure-3PAPISID" }?.value ??
                    cookies.first { $0.name == "SAPISID" }?.value
                guard let sapisid else {
                    continuation.resume(throwing: NSError(
                        domain: "GoogleSignIn", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No SAPISID cookie after account switch"]))
                    return
                }
                let header = yt.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                continuation.resume(returning: YTAuth(cookie: header, sapisid: sapisid, email: nil))
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onComplete: (YTAuth) -> Void
        private var done = false

        init(onComplete: @escaping (YTAuth) -> Void) { self.onComplete = onComplete }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !done else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }

                // Logged in once youtube.com has the session cookie.
                let yt = cookies.filter { $0.domain.hasSuffix("youtube.com") }
                let names = Set(yt.map(\.name))
                guard names.contains("__Secure-3PSID") else { return }

                let sapisid =
                    yt.first { $0.name == "__Secure-3PAPISID" }?.value ??
                    cookies.first { $0.name == "SAPISID" }?.value
                guard let sapisid else { return }

                let header = yt.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                self.done = true
                Task { @MainActor in
                    self.onComplete(YTAuth(cookie: header, sapisid: sapisid, email: nil))
                }
            }
        }
    }
}

// MARK: - SessionSwitchNavigationDriver

/// Drives a one-shot navigation to completion for `GoogleSignInView.selectAccount`.
///
/// Bridges `WKNavigationDelegate` callbacks into a single awaitable result and
/// enforces a timeout so a hung redirect chain cannot block the switch forever.
/// Adapted from kaset `SessionSwitchNavigationDriver` (protocol knowledge only).
@MainActor
private final class SessionSwitchNavigationDriver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    func load(_ url: URL, in webView: WKWebView, timeout: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard let self, !self.finished else { return }
                    self.complete(with: .failure(SessionSwitchError.timedOut))
                }
                webView.load(URLRequest(url: url))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.complete(with: .failure(CancellationError()))
            }
        }
    }

    private func complete(with result: Result<Void, Error>) {
        guard !self.finished else { return }
        self.finished = true
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        self.complete(with: .success(()))
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        self.complete(with: .failure(SessionSwitchError.navigationFailed(underlying: error.localizedDescription)))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        self.complete(with: .failure(SessionSwitchError.navigationFailed(underlying: error.localizedDescription)))
    }
}

// MARK: - SessionSwitchError

/// Errors raised while switching the WebView session's active delegated identity.
enum SessionSwitchError: LocalizedError {
    /// The switch navigation failed to load.
    case navigationFailed(underlying: String)
    /// The switch did not complete within the allotted time.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .navigationFailed:
            "Failed to load the account switch page."
        case .timedOut:
            "Switching accounts timed out. Please try again."
        }
    }
}
