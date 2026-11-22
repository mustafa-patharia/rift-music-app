// SPDX-License-Identifier: GPL-3.0-only
//
// RiftCommand — the widget's play/pause/next/previous action. The SAME type
// is compiled into RiftWidget (RiftWidget/RiftWidget.swift): macOS routes a
// widget button's intent to the containing app (AudioPlaybackIntent → run in
// the app's process), so the app must define it too. Here it drives the
// player directly; in the extension it falls back to a distributed
// notification that WidgetBridge handles.

import AppIntents

struct RiftCommand: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Control Rift playback"
    static let isDiscoverable = false

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.player.info("widget intent in app: \(command, privacy: .public)")
        let player = AppServices.shared.player
        switch command {
        case "toggle": player.togglePlayPause()
        case "next":   player.next()
        default:       player.previous()
        }
        return .result()
    }
}
