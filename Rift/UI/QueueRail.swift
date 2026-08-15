// SPDX-License-Identifier: GPL-3.0-only
//
// QueueRail — the right column: big now-playing artwork plus the upcoming
// tracks. Up Next reorders via custom drag & drop: open-hand cursor on hover,
// the dragged row dims, and a dotted placeholder marks the insertion slot.
// Tapping an upcoming track jumps to it; hover ✕ removes it.

import SwiftUI

struct QueueRail: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var ui: UIState

    @State private var draggingId: String?
    // Visual copy of upNext during a drag: rows swap live here (smooth, no
    // height changes → no jitter); the real queue mutates once, on drop.
    @State private var visualOrder: [PlayableTrack]?

    private var upNext: [PlayableTrack] {
        guard player.index >= 0, player.index + 1 < player.queue.count else { return [] }
        return Array(player.queue[(player.index + 1)...])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Now Playing").font(.headline)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        ui.showQueue = false
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.ultraThinMaterial, in: .circle)
                        .overlay(Circle().strokeBorder(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Hide queue")
            }

            Artwork(url: player.track?.artworkURL, size: 228)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.track?.title ?? "—").font(.title3.bold()).lineLimit(2)
                Text(player.track?.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
            }

            if !upNext.isEmpty {
                Text("Up Next").font(.headline).padding(.top, 4)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visualOrder ?? upNext) { t in
                            queueRow(t)
                        }
                    }
                }
                .noScrollbar()
                // Drop anywhere in the rail (incl. below the rows) commits.
                .onDrop(of: [.text], delegate: QueueDropDelegate(
                    targetId: nil, draggingId: $draggingId,
                    visualOrder: $visualOrder, commit: commitMove))
            }
            Spacer(minLength: 0)
        }
        // Shared top line with the home hero + sidebar first section.
        .padding([.horizontal, .bottom], 18)
        .padding(.top, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(.white.opacity(0.08)), alignment: .leading)
    }

    // MARK: rows + drag pieces

    @ViewBuilder private func queueRow(_ t: PlayableTrack) -> some View {
        Group {
            if draggingId == t.id {
                // The dragged row's slot renders as the dotted ghost — same
                // height as a row, so nothing else shifts (that's what killed
                // the jitter: inserted placeholders moved rows under cursor).
                placeholder
            } else {
                QueueRowView(track: t,
                             play: { player.play(t, in: player.queue) },
                             remove: { remove(t) })
            }
        }
        .onDrag {
            visualOrder = upNext
            draggingId = t.id
            return NSItemProvider(object: t.id as NSString)
        }
        .onDrop(of: [.text], delegate: QueueDropDelegate(
            targetId: t.id, draggingId: $draggingId,
            visualOrder: $visualOrder, commit: commitMove))
    }

    /// Dotted ghost marking where the dragged row currently sits.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(.tint.opacity(0.8))
            .background(.tint.opacity(0.08), in: .rect(cornerRadius: 8))
            .frame(height: 46)
    }

    private func remove(_ t: PlayableTrack) {
        guard let i = upNext.firstIndex(where: { $0.id == t.id }) else { return }
        player.removeUpNext(atOffsets: IndexSet(integer: i))
    }

    /// Drop finished: apply the visual order to the real queue in one move.
    private func commitMove(id: String) {
        defer { visualOrder = nil; draggingId = nil }
        guard let order = visualOrder,
              let from = upNext.firstIndex(where: { $0.id == id }),
              let to = order.firstIndex(where: { $0.id == id }),
              from != to else { return }
        // Array.move semantics: moving down needs the slot AFTER the target.
        player.moveUpNext(fromOffsets: IndexSet(integer: from),
                          toOffset: to > from ? to + 1 : to)
    }
}

/// One upcoming track. Own view so hover state (✕ button, open-hand cursor)
/// stays per-row.
private struct QueueRowView: View {
    let track: PlayableTrack
    let play: () -> Void
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Artwork(url: track.artworkURL, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.callout).lineLimit(1)
                Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if hover {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(hover ? AnyShapeStyle(.white.opacity(0.06)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onTapGesture(perform: play)
        .onHover { h in
            hover = h
            // Grab-hand cursor signals the row is draggable.
            if h { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Live-reorder drop delegate: dragging over a row swaps the ghost into that
/// row's slot in the visual array (spring-animated); dropping commits the
/// final order to the real queue in one move.
private struct QueueDropDelegate: DropDelegate {
    let targetId: String?             // nil = the container (no swap, just commit)
    @Binding var draggingId: String?
    @Binding var visualOrder: [PlayableTrack]?
    let commit: (String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingId, let targetId, dragId != targetId,
              var order = visualOrder,
              let from = order.firstIndex(where: { $0.id == dragId }),
              let to = order.firstIndex(where: { $0.id == targetId }) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            order.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
            visualOrder = order
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let id = draggingId else { return false }
        commit(id)
        return true
    }
}
