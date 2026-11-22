// SPDX-License-Identifier: GPL-3.0-only
//
// UIState — small shared UI flags that live outside any single view because
// both the main window and the detached player panel need to read/write them
// (the player panel is a separate NSWindow, so it can't share ContentView's
// @State). Currently just the Queue-rail toggle.

import SwiftUI

@MainActor
final class UIState: ObservableObject {
    @Published var showQueue = false
    @Published var showFullPlayer = false
    /// First-launch onboarding is covering the window. The floating player
    /// panel is a separate NSWindow, so it would otherwise sit on top of the
    /// welcome flow — a restored (paused) track is enough to summon it.
    @Published var onboarding = false
    /// Left nav rail hidden (titlebar button / ⌃⌘S). Persisted across launches.
    @Published var sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed") {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }

    func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sidebarCollapsed.toggle() }
    }
}
