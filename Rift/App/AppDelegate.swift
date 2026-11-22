// SPDX-License-Identifier: GPL-3.0-only
//
// AppDelegate — owns the AppKit shells (notch panel + menu-bar item) and shows
// or hides them per the display-mode setting. Non-notch Macs get a virtual
// notch (NotchDetector.island), so the mode picker decides on every Mac.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var notch: NotchController?
    private var mode: AppModeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installCrashLogging()

        #if DEBUG
        // Marketing screenshots: open the canvas previews as windows and skip the notch/menu-bar shells.
        if Showcase.isRequested { Showcase.open(); return }
        #endif

        let s = AppServices.shared
        menuBar = MenuBarController(player: s.player)
        notch = NotchController(player: s.player)
        mode = s.mode

        s.mode.onChange = { [weak self] in self?.apply() }
        apply()
        _ = s.widget   // start feeding the Now Playing widget
        #if DEBUG
        if ProcessInfo.processInfo.environment["RIFT_NOSTR_SELFTEST"] == "1" { NostrRelay.selfTest() }
        // Two-copy room test: RIFT_ROOM_HOST=CODE starts a room with that code,
        // RIFT_ROOM_JOIN=CODE joins it.
        if let c = ProcessInfo.processInfo.environment["RIFT_ROOM_HOST"] { FriendRoom.shared.debugHost(code: c) }
        if let c = ProcessInfo.processInfo.environment["RIFT_ROOM_JOIN"] { FriendRoom.shared.join(c) }
        #endif

        // YouTube's extraction requirements shift often (client/PO-token changes)
        // and yt-dlp ships fixes fast — check for a newer copy on every launch
        // instead of waiting for a play to fail first. Throttled inside update()
        // so a quick relaunch doesn't redownload.
        Task.detached { await YtDlpManager.shared.update() }
    }

    // The system crash report captures the NSException's name/reason (e.g. AppKit's
    // "recursive layout" NSInternalInconsistencyException) but that never reaches
    // Console.app on its own — log it ourselves right before the process dies so
    // `log show --predicate 'subsystem == "com.mustafapatharia.riftmusicapp"'` has
    // the actual reason string, not just a bare EXC_BREAKPOINT address.
    private func installCrashLogging() {
        NSSetUncaughtExceptionHandler { exception in
            Log.ui.fault("""
                uncaught exception: \(exception.name.rawValue, privacy: .public) \
                — \(exception.reason ?? "no reason", privacy: .public)
                \(exception.callStackSymbols.joined(separator: "\n"), privacy: .public)
                """)
        }
    }

    private func apply() {
        guard let mode else { return }
        let notchOK = notch?.isNotchAvailable ?? false
        let showNotch = mode.mode == .notch && notchOK
        // No screen at all (headless) → menu bar so controls stay reachable.
        let showMenuBar = mode.mode == .menuBar || !notchOK

        Log.player.info("display mode → \(mode.mode.rawValue, privacy: .public) (notch available \(notchOK)) ⇒ notch \(showNotch) menuBar \(showMenuBar)")
        showNotch ? notch?.show() : notch?.hide()
        showMenuBar ? menuBar?.install() : menuBar?.remove()
    }
}
