// SPDX-License-Identifier: GPL-3.0-only
//
// AppModeController — the notch / menu-bar display setting, persisted in
// UserDefaults. `onChange` lets the AppDelegate re-apply window visibility.
// Pure state; no AppKit here (NotchDetector.hasNotch reads only public
// screen geometry).

import Foundation

@MainActor
final class AppModeController: ObservableObject {
    /// Every Mac can pick: non-notch Macs get a virtual notch (a small black
    /// bar at the top centre) — see NotchDetector.island.
    enum Mode: String, CaseIterable, Identifiable {
        case notch, menuBar
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notch:   return NotchDetector.hasNotch ? "Notch (dynamic island)" : "Dynamic island"
            case .menuBar: return "Menu bar"
            }
        }
    }

    private let modeKey = "appDisplayMode"

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
            onChange?()
        }
    }

    /// Set by the AppDelegate; fired on every change (already on the main actor).
    var onChange: (() -> Void)?

    init() {
        let storedMode = UserDefaults.standard.string(forKey: modeKey)
        mode = storedMode.flatMap(Mode.init(rawValue:)) ?? .notch
    }
}
