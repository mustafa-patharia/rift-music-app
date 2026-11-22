// SPDX-License-Identifier: GPL-3.0-only
//
// NotchDetector — is there a physical notch, and where is it? Uses public
// AppKit geometry (safeAreaInsets + auxiliaryTopLeftArea/RightArea), not private
// APIs. On non-notch Macs (M1 Air, external displays) `island` returns a
// virtual notch instead: a black bar about half a real notch's width, drawn at
// the top centre of the main screen — the same dynamic island, just painted
// rather than merged into a camera housing (Atoll and boring.notch do the
// same on non-notch Macs).

import AppKit

enum NotchDetector {
    /// The built-in display carrying a notch, if any.
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static var hasNotch: Bool { notchScreen != nil }

    /// Physical notch rect in global (bottom-left origin) screen coordinates.
    /// Width is derived from the auxiliary areas flanking the notch; height is
    /// the top safe-area inset. Falls back to a sane default width if the
    /// auxiliary areas aren't reported.
    /// Where the island lives: the physical notch, else a virtual one on the
    /// menu-bar screen. `virtual` tells NotchView it must paint the bar.
    static var island: (screen: NSScreen, rect: CGRect, virtual: Bool)? {
        if let s = notchScreen { return (s, notchRect(on: s), false) }
        guard let s = NSScreen.screens.first else { return nil }   // [0] = menu-bar screen
        let menuBar = max(s.frame.maxY - s.visibleFrame.maxY, 24)
        let size = CGSize(width: 100, height: min(menuBar, 32) - 2)
        return (s, CGRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
                          width: size.width, height: size.height), true)
    }

    static func notchRect(on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let height = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32

        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let width: CGFloat = (left > 0 && right > 0) ? (frame.width - left - right) : 200

        let x = frame.minX + (frame.width - width) / 2
        let y = frame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
