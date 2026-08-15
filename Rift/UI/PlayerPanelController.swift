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
        // ends of the transition too. These notifications fire from inside AppKit's
        // own layout/resize pass, so (same reentrancy hazard as applyWindowSize in
        // ContentView) reposition() must not run until that pass has finished.
        for name in [NSWindow.didResizeNotification,
                     NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            let o = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in DispatchQueue.main.async { self?.reposition() } }
            observers.append(o)
        }

        // PlayerPanel.isKeyWindow mirrors the host, but AppKit only repaints the
        // window whose key state actually changed — so the pill would keep its
        // previous active/inactive look until something else dirtied it. Redraw
        // it whenever the host gains or loses key.
        for name in [NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification] {
            let label = name.rawValue
            let o = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] note in
                // Read off the notification BEFORE the async hop — NSNotification
                // isn't Sendable, so only plain values may cross.
                let hostKey = (note.object as? NSWindow)?.isKeyWindow ?? false
                DispatchQueue.main.async {
                    guard let self else { return }
                    Log.ui.info("""
                        host \(label, privacy: .public) — \
                        hostKey \(hostKey, privacy: .public), \
                        appActive \(NSApp.isActive, privacy: .public), \
                        panelAttached \(self.panel?.parent != nil, privacy: .public) \
                        — marking pill for redraw
                        """)
                    self.panel?.contentView?.needsDisplay = true
                }
            }
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
        let p = PlayerPanel(
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
        // The panel is .nonactivatingPanel and never key, so SwiftUI hands its
        // content an inactive window state and draws the Slider's fill in the
        // desaturated grey — the accent only shows in a key window (hence the
        // canvas preview looking right while the running app didn't). Pin it
        // active: the pill is always "live" chrome, never dimmed.
        // macOS 15 deprecated controlActiveState in favour of appearsActive;
        // on 26 only the new key is read, so set both for the 14/15 range.
        .modifier(AlwaysActive())
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hosting = NSHostingView(rootView: root)
        // NSHostingView otherwise publishes SwiftUI's measured size to AppKit as
        // real layout constraints, and re-invalidates them from inside its own
        // layout() whenever the content resizes — which throws
        // (NSInternalInconsistencyException) if that lands during a layout pass.
        // The pill is explicitly sized by the panel (autoresizingMask + the root's
        // .frame(maxWidth/maxHeight: .infinity)), so it never needs them.
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: maxPillWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        return p
    }

    // Callers are Combine sinks driven by @Published vars that can flip mid a
    // SwiftUI update pass (same reentrancy hazard applyWindowSize in ContentView
    // documents) — window/panel mutations below must wait for that pass to end.
    private func show() {
        Log.ui.info("panel show() deferred")
        DispatchQueue.main.async { [weak self] in
            guard let self, let host = self.host else { return }
            Log.ui.info("panel show() running")
            let p = self.panel ?? self.makePanel()
            self.panel = p
            self.reposition()
            if p.parent == nil { host.addChildWindow(p, ordered: .above) }
            p.alphaValue = 0
            p.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        }
    }

    private func hide() {
        Log.ui.info("panel hide() deferred")
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.panel else { return }
            Log.ui.info("panel hide() running")
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
    }

    private func reposition(animated: Bool = false) {
        guard let panel, let host else { return }
        Log.ui.info("panel reposition(animated: \(animated))")
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
        // display: false — NowPlayingBar's root GeometryReader drives STRUCTURAL
        // if/else branches (poster/name/skip/… appear or disappear, not just
        // resize). display: true forces AppKit to lay out the hosted view
        // synchronously inside this call; when that structural diff changes the
        // hosting view's constraints mid-layout, NSHostingView reenters
        // setNeedsUpdateConstraints on itself and AppKit crashes
        // (NSInternalInconsistencyException). Let the normal display cycle
        // flush the frame instead — same next frame, no forced reentrant layout.
        if animated {
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.32
                $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rect, display: false)
            }
        } else {
            panel.setFrame(rect, display: false)   // instant follow during live resize
        }
    }
}

/// Makes the pill's content draw in its active appearance even though its
/// window is never key. `appearsActive` is the macOS 15+ key; below that the
/// deprecated `controlActiveState` is the one SwiftUI reads.
private struct AlwaysActive: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.environment(\.appearsActive, true)
        } else {
            content.environment(\.controlActiveState, .key)
        }
    }
}

/// The pill's window.
///
/// AppKit renders accent-coloured control fills — the Slider's elapsed portion —
/// ONLY in the key window; every other window gets the inactive grey appearance.
/// This panel is a borderless, non-activating child window, so it is never key
/// and its scrubber drew grey while the byte-identical Slider in the main
/// window's full-screen player drew Rift red.
///
/// Reporting the panel as key makes its controls draw in their active
/// appearance. It does NOT make the panel take focus: the style mask is still
/// .nonactivatingPanel, so clicking the pill won't steal key status from the
/// main window or activate the app.
private final class PlayerPanel: NSPanel {
    /// Last value we logged. AppKit queries isKeyWindow on every draw pass, so
    /// logging unconditionally floods the log — only transitions are useful.
    private var lastLoggedKey: Bool?

    // A borderless panel refuses key status by default, and AppKit paints every
    // non-key window's controls in the inactive grey — that's what greyed the
    // scrubber. .nonactivatingPanel is kept, so taking key never activates the
    // app or pulls focus away from another application.
    override var canBecomeKey: Bool { true }

    override var isKeyWindow: Bool {
        // MIRROR the host window rather than hardcoding `true`: the pill should
        // look active exactly when the app does. Switch to another app and the
        // main window resigns key, so this returns false and the pill greys out
        // with the rest of the UI instead of staying stuck in the active look.
        let key = parent?.isKeyWindow ?? super.isKeyWindow
        if lastLoggedKey != key {
            lastLoggedKey = key
            Log.ui.info("""
                PlayerPanel.isKeyWindow -> \(key, privacy: .public) \
                [hasParent \(self.parent != nil, privacy: .public), \
                appActive \(NSApp.isActive, privacy: .public), \
                accent \(NSColor.controlAccentColor.description, privacy: .public)] \
                — true means the scrubber draws its ACCENT fill, false means grey
                """)
        }
        return key
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
