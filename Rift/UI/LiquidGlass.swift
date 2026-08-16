// SPDX-License-Identifier: GPL-3.0-only
//
// LiquidGlass — drop-in replacements for `.glassEffect` / `GlassEffectContainer`
// that fall back to plain material blur pre-macOS 26 instead of failing to
// compile (or, if force-called, crashing) below the real Liquid Glass API.

import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(_ interactive: Bool = false, in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

/// Groups glass views so they can morph together on 26+; a no-op passthrough below.
struct LiquidGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
