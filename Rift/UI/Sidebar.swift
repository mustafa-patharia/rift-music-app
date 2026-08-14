// SPDX-License-Identifier: GPL-3.0-only
//
// Sidebar — glass navigation rail: grouped sections with a sliding selection
// pill (matchedGeometry) and a profile chip that opens sign-in. No wordmark,
// no collapse — a fixed 189pt rail (owner's call). Structure borrows from the
// reference dashboards (grouped Menu / Library nav).

import SwiftUI

enum Panel: String, CaseIterable, Identifiable {
    case home = "Home", search = "Search", library = "Library", stats = "Stats",
         settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .search:   return "magnifyingglass"
        case .library:  return "square.stack.fill"
        case .stats:    return "chart.bar.fill"
        case .settings: return "gearshape"
        }
    }
}

struct Sidebar: View {
    @Binding var panel: Panel
    @EnvironmentObject var auth: AuthController
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            group("Menu", [.home, .search])
            group("Library", [.library, .stats]).padding(.top, 18)
            appGroup.padding(.top, 18)

            Spacer(minLength: 12)
            profileChip
        }
        // Same shared top line as the home hero and the queue rail header
        // (title-bar safe area + 16).
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Own frosted panel so text stays readable over any poster/wallpaper.
        .background(.regularMaterial)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(.white.opacity(0.08)), alignment: .trailing)
    }

    private func group(_ title: String, _ panels: [Panel]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 20).padding(.bottom, 2)
            ForEach(panels) { p in
                NavRow(panel: p, selection: $panel, ns: ns).padding(.horizontal, 14)
            }
        }
    }

    // Queue lives on the player (pill + full player) — it only makes sense
    // while something is playing, so no sidebar entry.
    private var appGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("APP").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 20).padding(.bottom, 2)

            NavRow(panel: .settings, selection: $panel, ns: ns).padding(.horizontal, 14)
        }
    }

    @ViewBuilder private var avatar: some View {
        if let url = auth.photoURL {
            AsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(.tint.opacity(0.9))
            }
            .frame(width: 34, height: 34).clipShape(.circle)
        } else {
            ZStack {
                Circle().fill(.tint.opacity(0.9)).frame(width: 34, height: 34)
                Image(systemName: auth.isAuthenticated ? "person.fill" : "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }

    private var profileChip: some View {
        Button {
            if !auth.isAuthenticated { auth.signIn() }
        } label: {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(auth.isAuthenticated ? (auth.name ?? "Signed in") : "Sign in")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(auth.isAuthenticated ? (auth.email ?? "YouTube Music") : "with Google")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10)))
            .padding(.horizontal, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct NavRow: View {
    let panel: Panel
    @Binding var selection: Panel
    var ns: Namespace.ID
    @EnvironmentObject var ui: UIState
    @State private var hover = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { selection = panel }
            // Navigating away = clicking outside the player — close it so the
            // chosen tab is actually visible, not hidden behind Now Playing.
            if ui.showFullPlayer {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { ui.showFullPlayer = false }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: panel.icon)
                    .font(.system(size: 15, weight: .medium)).frame(width: 22)
                Text(panel.rawValue)
                    .font(.system(size: 14, weight: selection == panel ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selection == panel ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.72)))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                if selection == panel {
                    RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
                        .matchedGeometryEffect(id: "sidebar.selection", in: ns)
                } else if hover {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
