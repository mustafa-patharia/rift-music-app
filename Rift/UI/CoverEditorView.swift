// SPDX-License-Identifier: GPL-3.0-only
//
// CoverEditorView — "Customize Cover…" sheet: pick an emoji and a colour,
// optionally print the playlist name on it, with a live preview. Plus
// CustomCoverArt, the renderer every playlist tile/header uses.

import AppKit
import SwiftUI

/// Gradient + soft light + big emoji (+ optional title). Pure vector, so it's
/// crisp from a 44pt row icon to the 300pt detail banner.
struct CustomCoverArt: View {
    let cover: CustomCover
    var title: String = ""
    var size: CGFloat = 150
    /// nil → square tile; set for a banner (width fills, height fixed).
    var height: CGFloat? = nil

    var body: some View {
        let h = height ?? size
        let emojiSize = min(size, h) * (cover.showTitle ? 0.38 : 0.46)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: cover.palette.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft light from the top-left gives the flat gradient some depth.
            RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topLeading,
                           startRadius: 0, endRadius: max(size, h) * 0.9)
                .blendMode(.softLight)
            Text(cover.emoji)
                .font(.system(size: emojiSize))
                .shadow(color: .black.opacity(0.25), radius: emojiSize * 0.08, y: emojiSize * 0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: cover.showTitle ? -h * 0.08 : 0)
            if cover.showTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: max(10, min(size, h) * 0.11), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(min(size, h) * 0.09)
            }
        }
        .frame(width: height == nil ? size : nil, height: h)
        .frame(maxWidth: height == nil ? nil : .infinity)
        .clipShape(.rect(cornerRadius: height == nil ? (size > 80 ? 10 : 6) : 0))
        .overlay {
            if height == nil {
                RoundedRectangle(cornerRadius: size > 80 ? 10 : 6).strokeBorder(.white.opacity(0.12))
            }
        }
        .accessibilityHidden(true)
    }
}

struct CoverEditorView: View {
    let target: CoverStore.Target
    @ObservedObject private var store = CoverStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CustomCover
    @State private var emojiField = ""
    @FocusState private var emojiFocused: Bool

    /// Music-and-mood picks; "More…" opens the system emoji picker for the rest.
    private static let quickEmoji = [
        "🎧", "🎵", "🎶", "🎸", "🎹", "🥁", "🎤", "💿",
        "🔥", "💜", "💔", "✨", "🌙", "☀️", "🌊", "🌸",
        "🍂", "❄️", "🚗", "☕️", "😌", "🕺", "🏋️", "📚",
    ]

    init(target: CoverStore.Target) {
        self.target = target
        _draft = State(initialValue: CoverStore.shared.cover(for: target.id)
            ?? CustomCover(emoji: "🎧", palette: .dusk))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Customize Cover").font(.title2.bold())
                Text(target.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 14) {
                    CustomCoverArt(cover: draft, title: target.title, size: 200)
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: draft)
                    Toggle("Show name on cover", isOn: $draft.showTitle)
                        .toggleStyle(.switch).controlSize(.small)
                }
                .frame(width: 200)

                VStack(alignment: .leading, spacing: 18) {
                    emojiPicker
                    colourPicker
                }
            }

            HStack {
                if store.covers[target.id] != nil {
                    Button("Use Artwork") { store.set(nil, for: target.id); dismiss() }
                        .help("Remove the custom cover and show the playlist's artwork again")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { store.set(draft, for: target.id); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emoji").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                ForEach(Self.quickEmoji, id: \.self) { e in
                    Button { draft.emoji = e } label: {
                        Text(e).font(.system(size: 20))
                            .frame(width: 36, height: 36)
                            .background(draft.emoji == e ? AnyShapeStyle(.tint.opacity(0.35))
                                                         : AnyShapeStyle(.quaternary.opacity(0.5)),
                                        in: .rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(draft.emoji == e ? Color.accentColor : .clear, lineWidth: 1.5))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(e)
                }
            }
            HStack(spacing: 8) {
                // Captures whatever the system picker (or the keyboard) types;
                // only the last emoji is kept.
                TextField("Any emoji", text: $emojiField)
                    .textFieldStyle(.roundedBorder).frame(width: 120)
                    .focused($emojiFocused)
                    .onChange(of: emojiField) { _, new in
                        if let e = new.last(where: \.isEmojiLike) { draft.emoji = String(e) }
                        if new.count > 1 { emojiField = new.last.map(String.init) ?? "" }
                    }
                Button("More…") {
                    emojiFocused = true
                    DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                }
                .help("Open the emoji picker (⌃⌘Space)")
            }
        }
    }

    private var colourPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                ForEach(CoverPalette.allCases) { p in
                    Button { draft.palette = p } label: {
                        Circle()
                            .fill(LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                            .padding(3)
                            .overlay(Circle().strokeBorder(draft.palette == p ? Color.primary : .clear, lineWidth: 2))
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help(p.name)
                    .accessibilityLabel(p.name)
                }
            }
        }
    }
}

private extension Character {
    var isEmojiLike: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) }
    }
}
