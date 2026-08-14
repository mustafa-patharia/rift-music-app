// SPDX-License-Identifier: GPL-3.0-only
//
// GoogleSignInView — the seamless "Sign in with Google" surface: a WKWebView at
// Google's real sign-in, continuing to YouTube Music. On completion, YT Music's
// session cookies are set for youtube.com; we capture the cookie header + SAPISID
// and hand them to AuthController. No client id/secret, nothing to set up — the
// user just logs into Google.
//
// WebView-driving pattern borrowed from pear-desktop (MIT). See /NOTICE.

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
                    self.onComplete(YTAuth(cookie: header, sapisid: sapisid))
                }
            }
        }
    }
}
