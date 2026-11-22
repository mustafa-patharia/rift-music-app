// SPDX-License-Identifier: GPL-3.0-only
//
// AppServices — the single source of truth for app-lifetime singletons the
// SwiftUI scenes and the AppKit AppDelegate both need: the PlayerController and
// the display-mode setting. One player instance drives the main window, the
// notch, and the menu bar alike.

import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let player = PlayerController(source: NativePlayer())
    let mode = AppModeController()
    let auth = AuthController()
    let ui = UIState()
    lazy var playerPanel = PlayerPanelController(player: player, ui: ui)
    lazy var widget = WidgetBridge(player: player)

    private init() {
        // Unpack the bundled playback engine (python + yt-dlp, both inside the
        // app) so it's ready before the first play. No network, no prompt —
        // after the first launch this is a no-op.
        Task { await YtDlpManager.shared.prepare() }
    }
}
