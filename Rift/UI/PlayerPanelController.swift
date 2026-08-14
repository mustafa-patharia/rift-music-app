// SPDX-License-Identifier: GPL-3.0-only
//
// PlayerPanelController — the detached "floating" player. An NSWindow can never
// draw outside its own rectangle, so the CleanMyMac/Spotlight-style pill that
// visually spills past the main window's bottom edge is a SEPARATE borderless
// NSPanel, added as a child window of the main window (moves/closes with it).
//
// It hosts the SwiftUI NowPlayingBar, shows when a track is playing, hides when
// stopped, and re-centers itself on the main window's bottom edge on resize.

import AppKit
import SwiftUI
import Combine

@MainActor
final class PlayerPanelController {
    private let player: PlayerController
    private let ui: UIState

    private var panel: NSPanel?
    private weak var host: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var bag = Set<AnyCancellable>()

    // Pill size + how far it pokes below the window's bottom edge. Width is
    // adaptive (see reposition): it scales with the window but stays capped and
    // is centered over the CONTENT area, right of the sidebar, so it never
    // overlaps the sidebar.
    private let maxPillWidth: CGFloat = 1600  // cap; 80% of content wins below this
    private let contentFraction: CGFloat = 0.8
    private let pillHeight: CGFloat = 124
    private let popupHeadroom: CGFloat = 172   // transparent space ABOVE the pill for the
                                               // volume popup (click-through when empty)
    private let sidebarWidth: CGFloat = 189   // must match ContentView's sidebar
    private let queueWidth: CGFloat = 264      // must match ContentView's QueueRail
    private let overhang: CGFloat = 34        // points of the pill hanging outside
    private let screenMargin: CGFloat = 12    // keep this much of the screen below the pill

    private var panelHeight: CGFloat { pillHeight + popupHeadroom }

    init(player: PlayerController, ui: UIState) {
        self.player = player
        self.ui = ui
    }

    /// Bind to the main window. Idempotent — safe to call from updateNSView.
    func attach(to window: NSWindow) {
        guard host !== window else { return }
        host = window

        // Show/hide as the current track comes and goes.
        player.$track
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                guard let self else { return }
                self.shouldShow(track: track, full: self.ui.showFullPlayer,
                                onboarding: self.ui.onboarding) ? self.show() : self.hide()
            }
            .store(in: &bag)

        // Child windows follow moves automatically but NOT resizes — recenter.
        // Full-screen transitions land the final frame AFTER their animation, so
        // the resize notification alone leaves the pill a step behind; catch both
        // ends of the transition too.
        for name in [NSWindow.didResizeNotification,
                     NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            let o = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
            observers.append(o)
        }

        // Queue rail opening/closing changes the content area — recenter. @Published
        // fires in willSet, so reading ui.showQueue now gives the OLD value; hop to
        // the next runloop tick so it's committed, then read it live (same path the
        // resize handler uses, which is always correct). Animate so the shift glides.
        ui.$showQueue
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reposition(animated: true) }
            }
            .store(in: &bag)

        // Hide the floating pill while the full-screen player is up (it has its own
        // transport, and the pill's NSPanel floats above an in-window overlay) or
        // while onboarding covers the window.
        Publishers.CombineLatest(ui.$showFullPlayer, ui.$onboarding)
            .receive(on: RunLoop.main)
            .sink { [weak self] full, onboarding in
                guard let self else { return }
                self.shouldShow(full: full, onboarding: onboarding) ? self.show() : self.hide()
            }
            .store(in: &bag)

        if shouldShow(full: ui.showFullPlayer, onboarding: ui.onboarding) { show() }
    }

    /// Single rule for whether the pill belongs on screen — every subscription
    /// routes through it so they can't disagree about visibility.
    private func shouldShow(track: PlayableTrack? = nil, full: Bool, onboarding: Bool) -> Bool {
        let current = track ?? player.track
        return current != nil && !full && !onboarding
    }

    // MARK: panel

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: maxPillWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false                 // pill draws its own soft shadow
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.level = .floating

        // Fill the hosting view (which resizes with the panel) instead of a fixed
        // width, so the pill adapts when reposition() resizes the panel.
        let root = NowPlayingBar(
            showQueue: Binding(get: { [ui] in ui.showQueue },
                               set: { [ui] in ui.showQueue = $0 })
        )
        .environmentObject(player)
        .environmentObject(ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: maxPillWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        return p
    }

    private func show() {
        guard let host else { return }
        let p = panel ?? makePanel()
        panel = p
        reposition()
        if p.parent == nil { host.addChildWindow(p, ordered: .above) }
        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
    }

    private func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.2
            p.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {   // animation completions fire on the main thread
                self?.host?.removeChildWindow(p)
                p.orderOut(nil)
            }
        }
    }

    private func reposition(animated: Bool = false) {
        guard let panel, let host else { return }
        let f = host.frame
        // Content area = window minus the left sidebar and (when open) the right
        // queue rail. Pill = 80% of that, capped, centered inside — never over
        // either sidebar. Reads ui.showQueue live (callers defer past willSet).
        let rightInset = (ui.showQueue && player.track != nil) ? queueWidth : 0
        let contentX = f.minX + sidebarWidth
        let contentW = max(f.width - sidebarWidth - rightInset, 0)
        let width = min(maxPillWidth, max(contentW * contentFraction, 260))
        let x = contentX + (contentW - width) / 2
        // The pill's bottom edge hangs BELOW the window (panel extends up by the
        // headroom). That only works while there's screen left underneath: full
        // screen — and a window dragged to the bottom of the display — put the
        // window's bottom edge on the screen's, so the overhang falls off and the
        // pill gets clipped. Clamp to the screen instead of special-casing full
        // screen, which fixes both.
        var y = f.minY - overhang
        if let screen = host.screen {
            y = max(y, screen.frame.minY + screenMargin)
        }
        let rect = NSRect(x: x, y: y, width: width, height: panelHeight)
        if animated {
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.32
                $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rect, display: true)
            }
        } else {
            panel.setFrame(rect, display: true)   // instant follow during live resize
        }
    }
}

/// Captures the enclosing NSWindow and hands it to the player panel controller.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { onWindow(w) }
    }
}
