// SPDX-License-Identifier: GPL-3.0-only
//
// AppModeController — the notch / menu-bar display setting, plus the
// menu-bar icon's own visibility. Persisted in UserDefaults. `onChange` lets
// the AppDelegate re-apply window visibility when either setting changes.
// Pure state; no AppKit here (NotchDetector.hasNotch reads only public
// screen geometry).

import Foundation

@MainActor
final class AppModeController: ObservableObject {
    /// Only meaningful on a notch Mac — a non-notch Mac has nothing to pick
    /// between, so Settings shows a menu-bar-icon toggle instead of this.
    enum Mode: String, CaseIterable, Identifiable {
        case notch, menuBar
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notch:   return "Notch (dynamic island)"
            case .menuBar: return "Menu bar"
            }
        }
    }

    private let modeKey = "appDisplayMode"
    private let menuBarIconKey = "menuBarIconVisible"

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
            onChange?()
        }
    }

    /// Non-notch Macs have no fallback surface to switch to, so instead they
    /// get a plain on/off for the menu-bar icon — playback controls stay
    /// reachable from the main window either way.
    @Published var menuBarIconVisible: Bool {
        didSet {
            UserDefaults.standard.set(menuBarIconVisible, forKey: menuBarIconKey)
            onChange?()
        }
    }

    /// Set by the AppDelegate; fired on every change (already on the main actor).
    var onChange: (() -> Void)?

    init() {
        let storedMode = UserDefaults.standard.string(forKey: modeKey)
        mode = storedMode.flatMap(Mode.init(rawValue:)) ?? (NotchDetector.hasNotch ? .notch : .menuBar)
        menuBarIconVisible = (UserDefaults.standard.object(forKey: menuBarIconKey) as? Bool) ?? true
    }
}
