// SPDX-License-Identifier: GPL-3.0-only
//
// Rift — native macOS YouTube Music player. App entry.
// Not affiliated with, endorsed by, or connected to Google LLC / YouTube.
//
// The AppDelegate owns the notch + menu-bar shells; the main window, notch, and
// menu bar all share the one PlayerController from AppServices. The main window
// opens at a fixed size and won't shrink below its content minimum.

import SwiftUI

/// Single source of truth for the main window's geometry. Both the SwiftUI
/// declaration below and the absolute NSWindow floor in ContentView read these,
/// so the default size and the minimum size can never drift apart.
enum RiftWindow {
    /// The main window is BOTH opened at and floored to this size.
    static let minSize = CGSize(width: 875, height: 600)
    /// Onboarding is a centred card, so the window shrinks to just fit it and
    /// grows back to `minSize` when the flow finishes.
    static let onboardingSize = CGSize(width: 600, height: 560)
}

extension Color {
    /// Rift's brand accent (the website's `--accent-crim`, #FF2F3A).
    ///
    /// Player chrome uses this rather than `.accentColor` because on macOS
    /// `.accentColor` resolves to the *system* accent from System Settings →
    /// Appearance; the app's own AccentColor asset only wins when the user has
    /// that set to "Multicolor". Keying off this constant means the played
    /// portion of a scrubber is Rift red on every machine.
    static let riftAccent = Color(red: 1.0, green: 0.184, blue: 0.227)
}

@main
struct RiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppServices.shared.player)
                .environmentObject(AppServices.shared.auth)
                .environmentObject(AppServices.shared.ui)
                .environmentObject(AppServices.shared.mode)
                .frame(minWidth: RiftWindow.minSize.width, maxWidth: .infinity,
                       minHeight: RiftWindow.minSize.height, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        // Opens at exactly the minimum — default and floor are the same size.
        .defaultSize(width: RiftWindow.minSize.width, height: RiftWindow.minSize.height)
        .defaultPosition(.center)
        // NOT .contentMinSize: that pins the window's floor to whatever the
        // content subtree computes, which silently overrode the minimum set
        // here. The real floor is applied to the NSWindow in ContentView's
        // WindowAccessor, which also shrinks the window for onboarding.
        .windowResizability(.automatic)
        .commands {
            CommandMenu("Playback") {
                let p = AppServices.shared.player
                Button(p.isPlaying ? "Pause" : "Play") { p.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(p.track == nil)
                Button("Next") { p.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { p.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Shuffle") { p.toggleShuffle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Repeat") { p.cycleRepeat() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Toggle Full Player") {
                    guard p.track != nil else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        AppServices.shared.ui.showFullPlayer.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Toggle Queue") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        AppServices.shared.ui.showQueue.toggle()
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
            }
        }

        // No separate Settings window — settings live in-app (sidebar → Settings).
    }
}
