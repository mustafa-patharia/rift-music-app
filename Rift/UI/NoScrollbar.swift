// SPDX-License-Identifier: GPL-3.0-only
//
// NoScrollbar — belt-and-suspenders over .scrollIndicators(.hidden). On macOS,
// System Settings → Appearance → "Show scroll bars: Always" forces AVKit's
// NSScroller regardless of that SwiftUI modifier. Reaches into the enclosing
// NSScrollView and turns the scroller off directly so the app looks the same
// no matter what the user's system pref is.

import SwiftUI
import AppKit

private struct ScrollbarKiller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var v: NSView? = nsView.superview
            while let view = v {
                if let scrollView = view as? NSScrollView {
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                }
                v = view.superview
            }
        }
    }
}

extension View {
    func noScrollbar() -> some View {
        background(ScrollbarKiller())
    }
}
