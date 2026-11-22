// SPDX-License-Identifier: GPL-3.0-only
//
// PillPicker — Rift's segmented control: a soft capsule track with a pill
// that slides to the selected option. Used instead of the stock segmented
// Picker everywhere so the switch looks and moves the same across the app.
// Options can carry an icon, and individual options can be disabled with a
// reason shown on hover.

import SwiftUI

struct PillPicker<Value: Hashable>: View {
    enum Size { case regular, small }

    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var icon: ((Value) -> String)? = nil
    var size: Size = .regular
    var disabledReason: (Value) -> String? = { _ in nil }

    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme

    private var height: CGFloat { size == .regular ? 32 : 24 }
    private var font: Font { size == .regular ? .callout.weight(.semibold) : .subheadline.weight(.medium) }
    private var hPad: CGFloat { size == .regular ? 16 : 11 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { v in
                let reason = disabledReason(v)
                let on = v == selection
                Button { selection = v } label: {
                    Group {
                        if let icon { Label(title(v), systemImage: icon(v)) } else { Text(title(v)) }
                    }
                    .font(font)
                    .lineLimit(1)
                    .foregroundStyle(on ? .primary : .secondary)
                    .padding(.horizontal, hPad).frame(height: height)
                    .background {
                        if on {
                            Capsule()
                                .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.12), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(reason != nil)
                .opacity(reason != nil ? 0.4 : 1)
                .help(reason ?? title(v))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.6), in: .capsule)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
        .fixedSize()
    }
}
