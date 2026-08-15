// SPDX-License-Identifier: GPL-3.0-only
//
// NotchController — owns the notch panel: builds it, positions it over the
// physical notch (top-centered, expanded size so the pill can grow downward),
// hosts NotchView, and joins the max-level Spaces window so it floats over the
// menu bar. show()/hide() are driven by AppModeController.

import AppKit
import SwiftUI

@MainActor
final class NotchController {
    private let player: PlayerController
    private var window: NotchWindow?

    init(player: PlayerController) {
        self.player = player
    }

    var isNotchAvailable: Bool { NotchDetector.hasNotch }

    func show() {
        guard let screen = NotchDetector.notchScreen else { return }
        let notch = NotchDetector.notchRect(on: screen)

        // Window is sized for the LARGEST the card can be tuned to (Settings →
        // Notch Tuning writes "notch.*" defaults read live by NotchView); the
        // card itself sizes to notch.width + notch.extraWidth inside it.
        let expandedW = max(notch.width + 620, 820)
        let expandedH: CGFloat = 240 + notch.height
        let originX = notch.midX - expandedW / 2
        let originY = screen.frame.maxY - expandedH   // top edge aligned to screen top
        let frame = CGRect(x: originX, y: originY, width: expandedW, height: expandedH)

        let win = window ?? NotchWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        win.setFrame(frame, display: true)

        let root = NotchView(
            notchSize: CGSize(width: notch.width, height: notch.height),
            expandedSize: CGSize(width: expandedW, height: expandedH)
        ).environmentObject(player)
        // sizingOptions = []: the notch card is explicitly sized by this window, so
        // NSHostingView must not publish (and mid-layout re-invalidate) SwiftUI's
        // measured size as window constraints. See PlayerPanelController.makePanel.
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        win.contentView = hosting

        win.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(win)
        window = win
    }

    func hide() {
        guard let win = window else { return }
        NotchSpaceManager.shared.notchSpace.windows.remove(win)
        win.orderOut(nil)
    }
}
