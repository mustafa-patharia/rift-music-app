// SPDX-License-Identifier: GPL-3.0-only
//
// UIState — small shared UI flags that live outside any single view because
// both the main window and the detached player panel need to read/write them
// (the player panel is a separate NSWindow, so it can't share ContentView's
// @State). Currently just the Queue-rail toggle.

import Foundation

@MainActor
final class UIState: ObservableObject {
    @Published var showQueue = false
    @Published var showFullPlayer = false
    /// First-launch onboarding is covering the window. The floating player
    /// panel is a separate NSWindow, so it would otherwise sit on top of the
    /// welcome flow — a restored (paused) track is enough to summon it.
    @Published var onboarding = false
}
