// SPDX-License-Identifier: GPL-3.0-only
//
// GlassPillButton — the app's one capsule button. Liquid Glass with an
// interactive highlight; `prominent` fills the capsule white (black label)
// for the primary action. Every pill button in the app uses this so they
// all look and feel identical.

import SwiftUI

struct GlassPillButton: View {
    let title: String
    var icon: String? = nil
    var prominent: Bool = false
    var loading: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, icon: String? = nil, prominent: Bool = false,
         loading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.prominent = prominent
        self.loading = loading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().controlSize(.small) }
                else if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.subheadline.bold())
            .foregroundStyle(prominent ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background { if prominent { Capsule().fill(.white.opacity(0.92)) } }
            .liquidGlass(true, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.18)))
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
