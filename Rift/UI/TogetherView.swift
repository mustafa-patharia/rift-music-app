// SPDX-License-Identifier: GPL-3.0-only
//
// TogetherView — the "Together" tab: listening with other people. One mode
// at a time:
//  • Room (friends anywhere, FriendRoom) — the song spins as a disc in the
//    middle and everyone in the room is a profile bubble pulled onto it like
//    a magnet: newcomers fly in from the edge, snap against the disc and
//    nudge the others aside. Bubbles can be flicked and spring back. Emoji
//    reactions rise from whoever sent them.
//  • Nearby (PeerSession) — a radar; Macs running Rift close by appear as
//    bubbles around you. Tap one to connect, send a song or listen together.
//
// No cards: content sits on the app background; only controls get a fill.
// Reduce Motion stops the disc spin, idle drift and radar sweeps.

import AppKit
import SwiftUI

private let accent = Color.riftAccent

enum TogetherMode: String, CaseIterable, Identifiable {
    case room, nearby
    var id: String { rawValue }
    var title: String { self == .room ? "Room" : "Nearby" }
    var icon: String { self == .room ? "globe" : "antenna.radiowaves.left.and.right" }
}

struct TogetherView: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var room = FriendRoom.shared
    @ObservedObject private var peers = PeerSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: TogetherMode = .room

    /// The mode that's busy (a room open, or a nearby session going) and
    /// therefore can't be switched away from.
    private var locked: TogetherMode? {
        if room.isActive { return .room }
        if peers.following != nil || peers.hosting || !peers.connected.isEmpty { return .nearby }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                Group {
                    switch mode {
                    case .room:
                        if room.isActive { RoomStage() } else { RoomLobby() }
                    case .nearby:
                        NearbySection()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                if mode == .room && room.isActive && !room.activity.isEmpty { ActivityFeed() }
                Text("People in your room or connected nearby see your name and profile photo. Only song details travel — every Mac streams its own audio.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: mode)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: room.isActive)
        .onAppear { if let locked { mode = locked } }
        .onChange(of: locked) { _, l in if let l { mode = l } }
        .onChange(of: mode) { _, m in peers.visible = (m == .nearby) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Together").font(.largeTitle.bold())
                Text(mode == .room ? "Listen in sync with friends, wherever they are."
                                   : "Macs running Rift on your Wi-Fi or within Bluetooth range.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
            }
            Spacer()
            PillPicker(selection: $mode, options: TogetherMode.allCases, title: \.title, icon: \.icon) { m in
                guard let locked, locked != m else { return nil }
                return locked == .room ? "Leave the room to use Nearby" : "Stop the nearby session to start a room"
            }
        }
    }
}

// MARK: - Avatar

struct ListenerAvatar: View {
    let profile: ListenerProfile
    var size: CGFloat = 56
    var ring: Color? = nil

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hue: profile.hue, saturation: 0.55, brightness: 0.95),
                                                  Color(hue: profile.hue + 0.08, saturation: 0.7, brightness: 0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(profile.initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let url = profile.photo {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                    .clipShape(.circle)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(ring ?? .white.opacity(0.85), lineWidth: ring == nil ? 2 : 3))
        .shadow(color: .black.opacity(0.3), radius: size * 0.12, y: size * 0.06)
        .accessibilityLabel(profile.name)
    }
}

// MARK: - Lobby (no room yet)

private struct RoomLobby: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var room = FriendRoom.shared
    @State private var code = ""
    @FocusState private var codeFocused: Bool
    private static let pillWidth: CGFloat = 300
    private static let pillHeight: CGFloat = 46

    var body: some View {
        VStack(spacing: 20) {
            InviteCluster().frame(height: 240)

            VStack(spacing: 6) {
                Text("Start a listening room")
                    .font(.title2.bold())
                Text("Share a code and friends hear exactly what you play, in sync.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button { room.startRoom() } label: {
                Label("Start a Room", systemImage: "plus")
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: Self.pillWidth, height: Self.pillHeight)
                    .background(accent, in: .capsule)
                    .shadow(color: accent.opacity(0.35), radius: 12, y: 6)
                    .contentShape(.capsule)
            }
            .buttonStyle(PressableStyle())
            .disabled(player.track == nil)
            .opacity(player.track == nil ? 0.5 : 1)
            .help(player.track == nil ? "Play something first" : "Friends who join hear what you play")

            HStack(spacing: 10) {
                Rectangle().fill(.quaternary).frame(height: 1)
                Text("or join a friend").font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                    .fixedSize()
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .frame(width: Self.pillWidth)

            // Code field with the Join arrow inside it: one pill, same size as Start.
            let valid = FriendRoom.normalise(code) != nil
            HStack(spacing: 0) {
                TextField("", text: $code, prompt: Text("RIFT-XXXX-XXXX-XXXX"))
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .focused($codeFocused)
                    .onSubmit(join)
                    .padding(.leading, 18)
                Button(action: join) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(valid ? .white : .secondary)
                        .frame(width: Self.pillHeight - 8, height: Self.pillHeight - 8)
                        .background(valid ? accent : Color.white.opacity(0.08), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(PressableStyle())
                .disabled(!valid)
                .help("Join room")
                .padding(.trailing, 4)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: valid)
            }
            .frame(width: Self.pillWidth, height: Self.pillHeight)
            .background(.quaternary.opacity(codeFocused ? 0.9 : 0.5), in: .capsule)
            .overlay(Capsule().strokeBorder(codeFocused ? accent.opacity(0.7) : .clear, lineWidth: 1.5))
            .animation(.easeOut(duration: 0.15), value: codeFocused)
            if let e = room.error {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func join() {
        guard FriendRoom.normalise(code) != nil else { return }
        room.join(code)
        code = ""
    }
}

/// You in the middle, empty seats drifting around you, waiting for friends.
private struct InviteCluster: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let a = Double(i) / 6 * 2 * .pi + t * 0.12
                    let r = 92 + sin(t * 0.8 + Double(i)) * 6      // seats breathe in and out
                    Circle()
                        .strokeBorder(.secondary.opacity(0.5), style: .init(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: i.isMultiple(of: 2) ? 46 : 38)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(.tertiary))
                        .offset(x: cos(a) * r, y: sin(a) * r * 0.9)
                }
                ListenerAvatar(profile: .mine, size: 96)
                    .scaleEffect(1 + (reduceMotion ? 0 : sin(t * 1.4) * 0.02))
            }
        }
    }
}

// MARK: - Magnet physics

/// A tiny 2-D physics sim: every bubble is pulled toward the centre disc,
/// collides with it and with each other, and settles into a cluster. Drag a
/// bubble away and let go — it's pulled back and bumps the others.
@MainActor
final class MagnetSim: ObservableObject {
    struct Body { var p: CGPoint; var v: CGVector = .zero; let r: CGFloat; let phase: Double }

    @Published private(set) var bodies: [String: Body] = [:]
    @Published private(set) var spin: Double = 0

    var size: CGSize = .zero { didSet { reconcile() } }
    var core: CGFloat = 80
    var spinning = false
    var calm = false

    private var wanted: [(id: String, r: CGFloat)] = []
    private var dragging: String?
    private var lastDrag: (p: CGPoint, at: Date)?
    private var timer: Timer?
    private var t: Double = 0
    private let gap: CGFloat = 4
    private let bounce: CGFloat = 0.35

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    func start() {
        guard timer == nil else { return }
        let tm = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(1 / 60) }
        }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    func stop() { timer?.invalidate(); timer = nil }

    func sync(_ seats: [(id: String, r: CGFloat)]) {
        wanted = seats
        reconcile()
    }

    private func reconcile() {
        guard size.width > 0 else { return }
        let ids = Set(wanted.map(\.id))
        for id in bodies.keys where !ids.contains(id) { bodies[id] = nil }
        for s in wanted where bodies[s.id] == nil {
            let a = Double.random(in: 0..<(2 * .pi))
            // Fly in from just outside the stage (or appear in place with Reduce Motion).
            let d = calm ? core + s.r + gap : max(size.width, size.height) / 2 + s.r
            let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
            bodies[s.id] = Body(p: p, r: s.r, phase: Double.random(in: 0..<(2 * .pi)))
        }
    }

    func drag(_ id: String, to p: CGPoint) {
        guard var b = bodies[id] else { return }
        let now = Date()
        if let last = lastDrag, dragging == id {
            let dt = max(now.timeIntervalSince(last.at), 1 / 120)
            b.v = CGVector(dx: (p.x - last.p.x) / dt, dy: (p.y - last.p.y) / dt)
        } else {
            b.v = .zero
        }
        dragging = id
        lastDrag = (p, now)
        b.p = p
        bodies[id] = b
    }

    func release() {
        dragging = nil
        lastDrag = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func step(_ dt: CGFloat) {
        t += Double(dt)
        if spinning && !calm { spin = (spin + Double(dt) * 24).truncatingRemainder(dividingBy: 360) }
        guard size.width > 0, !bodies.isEmpty else { return }
        let c = center
        let keys = Array(bodies.keys)
        var bs = keys.map { bodies[$0]! }

        // Pull toward the disc (stronger when far), a little idle drift, damping.
        let damp = exp(-5.5 * dt)
        for i in bs.indices where keys[i] != dragging {
            var b = bs[i]
            let dx = c.x - b.p.x, dy = c.y - b.p.y
            let d = max(1, hypot(dx, dy))
            let pull: CGFloat = 1100 + d * 5
            b.v.dx += dx / d * pull * dt
            b.v.dy += dy / d * pull * dt
            if !calm {
                b.v.dx += CGFloat(sin(t * 0.9 + b.phase)) * 60 * dt
                b.v.dy += CGFloat(cos(t * 0.7 + b.phase)) * 60 * dt
            }
            b.v.dx *= damp; b.v.dy *= damp
            b.p.x += b.v.dx * dt; b.p.y += b.v.dy * dt
            bs[i] = b
        }

        // Resolve contacts a few times so stacks settle without jitter.
        for _ in 0..<4 {
            for i in bs.indices {
                let iFixed = keys[i] == dragging
                // Disc.
                let dx = bs[i].p.x - c.x, dy = bs[i].p.y - c.y
                let d = max(0.001, hypot(dx, dy))
                let minD = core + bs[i].r + gap
                if d < minD && !iFixed {
                    let nx = dx / d, ny = dy / d
                    bs[i].p = CGPoint(x: c.x + nx * minD, y: c.y + ny * minD)
                    let vn = bs[i].v.dx * nx + bs[i].v.dy * ny
                    if vn < 0 { bs[i].v.dx -= (1 + bounce) * vn * nx; bs[i].v.dy -= (1 + bounce) * vn * ny }
                }
                // Each other.
                for j in (i + 1)..<bs.count {
                    let jFixed = keys[j] == dragging
                    let ex = bs[j].p.x - bs[i].p.x, ey = bs[j].p.y - bs[i].p.y
                    let e = max(0.001, hypot(ex, ey))
                    let minE = bs[i].r + bs[j].r + gap
                    guard e < minE else { continue }
                    let nx = ex / e, ny = ey / e, o = minE - e
                    let (wi, wj): (CGFloat, CGFloat) = iFixed ? (0, 1) : jFixed ? (1, 0) : (0.5, 0.5)
                    bs[i].p.x -= nx * o * wi; bs[i].p.y -= ny * o * wi
                    bs[j].p.x += nx * o * wj; bs[j].p.y += ny * o * wj
                    let rv = (bs[j].v.dx - bs[i].v.dx) * nx + (bs[j].v.dy - bs[i].v.dy) * ny
                    if rv < 0 {
                        let imp = -(1 + bounce) * rv / 2
                        if !iFixed { bs[i].v.dx -= imp * nx; bs[i].v.dy -= imp * ny }
                        if !jFixed { bs[j].v.dx += imp * nx; bs[j].v.dy += imp * ny }
                    }
                }
            }
        }

        // Stay on stage once arrived (newcomers may start outside).
        for i in bs.indices {
            let r = bs[i].r
            let inside = bs[i].p.x > -r && bs[i].p.x < size.width + r && bs[i].p.y > -r && bs[i].p.y < size.height + r
            guard inside else { continue }
            bs[i].p.x = min(max(bs[i].p.x, r), size.width - r)
            bs[i].p.y = min(max(bs[i].p.y, r), size.height - r)
        }
        bodies = Dictionary(uniqueKeysWithValues: zip(keys, bs))
    }
}

// MARK: - Room stage

private struct RoomStage: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var room = FriendRoom.shared
    @StateObject private var sim = MagnetSim()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    private struct Seat: Identifiable {
        let profile: ListenerProfile; let isHost: Bool; let isMe: Bool
        var id: String { profile.id }
        var size: CGFloat { isHost ? 76 : 64 }
        /// Collision radius: the bubble plus its name tag.
        var radius: CGFloat { size / 2 + 10 }
    }

    private var everyone: [Seat] {
        let me = Seat(profile: room.me, isHost: room.role == .host, isMe: true)
        return [me] + room.sortedMembers.map { Seat(profile: $0.profile, isHost: $0.isHost, isMe: false) }
    }

    private var track: PlayableTrack? { room.nowPlaying ?? player.track }

    var body: some View {
        VStack(spacing: 8) {
            topBar
            stage.frame(height: 440)
            bottomBar
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 8, height: 8).shadow(color: .green, radius: 4)
                    Text(room.role == .host ? "Your room" : "\(room.host?.profile.name.components(separatedBy: " ").first ?? "Friend")'s room")
                        .font(.title3.bold())
                    Text("· \(room.members.count + 1) listening")
                        .font(.callout).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring, value: room.members.count)
                }
                if let track {
                    Text("\(track.title) — \(track.artist)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer()
            codeChip
        }
    }

    private var codeChip: some View {
        HStack(spacing: 10) {
            Text(room.code ?? "")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(room.code ?? "", forType: .string)
                withAnimation(.spring(response: 0.3)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { copied = false } }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help("Copy code")
            if let code = room.code {
                ShareLink(item: "Listen with me on Rift — open Together and enter \(code)") {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Share invite")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.quaternary.opacity(0.6), in: .capsule)
    }

    private var stage: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let people = everyone
            ZStack {
                Disc(track: track, spin: sim.spin, diameter: sim.core * 2)
                    .position(c)

                ForEach(people) { s in
                    if let b = sim.bodies[s.id] {
                        MemberBubble(profile: s.profile, size: s.size,
                                     label: s.isMe ? "You" : s.profile.name.components(separatedBy: " ").first ?? "",
                                     isHost: s.isHost, isMe: s.isMe)
                            .position(b.p)
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("stage"))
                                .onChanged { sim.drag(s.id, to: $0.location) }
                                .onEnded { _ in sim.release() })
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                    }
                }

                ForEach(room.reactions) { r in
                    FloatingEmoji(emoji: r.emoji)
                        .position(sim.bodies[r.from]?.p ?? c)
                }

                if room.members.isEmpty {
                    Text(room.role == .host ? "Waiting for friends — share the code" : "Connecting to the room…")
                        .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        .position(x: c.x, y: geo.size.height - 14)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "stage")
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: people.map(\.id))
            .onAppear {
                sim.calm = reduceMotion
                sim.size = geo.size
                sim.sync(people.map { ($0.id, $0.radius) })
                sim.spinning = player.isPlaying
                sim.start()
            }
            .onChange(of: geo.size) { _, s in sim.size = s }
            .onChange(of: people.map(\.id)) { _, _ in sim.sync(everyone.map { ($0.id, $0.radius) }) }
            .onChange(of: player.isPlaying) { _, p in sim.spinning = p }
            .onDisappear { sim.stop() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(FriendRoom.reactionEmoji, id: \.self) { e in
                    ReactionButton(emoji: e) { room.react(e) }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: .capsule)

            Spacer()

            Button { room.sendCurrentSong() } label: {
                Label("Send Song", systemImage: "paperplane.fill")
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(player.track == nil)
            .help("Send what you're playing to everyone in the room")

            Button(role: .destructive) { room.leave() } label: {
                Text(room.role == .host ? "End Room" : "Leave")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }
}

/// The song as a spinning record: round artwork, faint grooves, a spindle,
/// and a fixed sheen so the spin reads as light moving over vinyl.
private struct Disc: View {
    let track: PlayableTrack?
    let spin: Double
    let diameter: CGFloat

    var body: some View {
        ZStack {
            // Soft colour bloom from the artwork.
            AsyncImage(url: track?.artworkURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                .frame(width: diameter * 1.3, height: diameter * 1.3)
                .clipShape(.circle)
                .blur(radius: 50).saturation(1.6).opacity(0.55)

            ZStack {
                Circle().fill(.black)
                AsyncImage(url: track?.artworkURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary) }
                    .frame(width: diameter, height: diameter)
                    .clipShape(.circle)
                ForEach(1..<5, id: \.self) { i in
                    Circle().stroke(.black.opacity(0.12), lineWidth: 0.75)
                        .frame(width: diameter * (0.42 + CGFloat(i) * 0.13))
                }
                Circle().fill(.black.opacity(0.85)).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(spin))
            .overlay(
                AngularGradient(colors: [.white.opacity(0.0), .white.opacity(0.22), .white.opacity(0.0),
                                         .white.opacity(0.0), .white.opacity(0.16), .white.opacity(0.0)],
                                center: .center)
                    .clipShape(.circle)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
            .id(track?.id)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: track?.id)
        .accessibilityElement()
        .accessibilityLabel(track.map { "Now playing \($0.title) by \($0.artist)" } ?? "Nothing playing")
    }
}

/// A member: avatar, a name tag tucked under it, a crown for the host, a
/// ripple the moment they arrive and a lift on hover.
private struct MemberBubble: View {
    let profile: ListenerProfile
    let size: CGFloat
    let label: String
    let isHost: Bool
    let isMe: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripple = false
    @State private var hover = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(isMe ? accent : .white, lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(ripple ? 2 : 1)
                .opacity(ripple ? 0 : 0.8)
            ListenerAvatar(profile: profile, size: size, ring: isMe ? accent : nil)
                .overlay(alignment: .topTrailing) {
                    if isHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: size * 0.17, weight: .bold))
                            .foregroundStyle(.black.opacity(0.75))
                            .padding(size * 0.07)
                            .background(Color.yellow, in: .circle)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: .capsule)
                .offset(y: size / 2 + 4)
        }
        .scaleEffect(hover ? 1.07 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
        .onHover { hover = $0 }
        .help(profile.name)
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {   // as it lands
                withAnimation(.easeOut(duration: 1.0)) { ripple = true }
            }
        }
    }
}

private struct ReactionButton: View {
    let emoji: String
    let action: () -> Void
    @State private var hover = false
    @State private var pop = false

    var body: some View {
        Button {
            action()
            pop = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { pop = false }
        } label: {
            Text(emoji).font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(hover ? 0.14 : 0)))
                .scaleEffect(pop ? 1.35 : hover ? 1.12 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pop)
                .animation(.spring(response: 0.25), value: hover)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("React \(emoji)")
    }
}

/// Rises, wobbles and fades — one per reaction.
private struct FloatingEmoji: View {
    let emoji: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    private let drift = CGFloat.random(in: -30...30)

    var body: some View {
        Text(emoji)
            .font(.system(size: 34))
            .scaleEffect(up ? 1.25 : 0.4)
            .offset(x: up ? drift : 0, y: up ? -130 : -20)
            .opacity(up ? 0 : 1)
            .rotationEffect(.degrees(up ? Double(drift) / 2 : 0))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 1.2) : .easeOut(duration: 2.4)) { up = true }
            }
    }
}

// MARK: - Activity

private struct ActivityFeed: View {
    @ObservedObject private var room = FriendRoom.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity").font(.title3.bold()).padding(.bottom, 4)
            ForEach(room.activity.prefix(6)) { a in
                HStack(spacing: 12) {
                    Image(systemName: a.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.quaternary.opacity(0.6), in: .circle)
                    Text(a.text).font(.callout).lineLimit(1)
                    Spacer()
                    Text(a.date, style: .relative).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: room.activity.map(\.id))
    }
}

// MARK: - Nearby

private struct NearbySection: View {
    @EnvironmentObject var player: PlayerController
    @ObservedObject private var peers = PeerSession.shared
    @State private var selected: PeerSession.Peer?

    var body: some View {
        VStack(spacing: 16) {
            if let f = peers.following {
                banner("Listening with \(peers.connected.first { $0.id == f }?.name ?? f.displayName)",
                       icon: "headphones") { peers.stopFollowing() }
            } else if peers.hosting {
                banner("Sharing your music live with nearby Macs", icon: "dot.radiowaves.left.and.right") {
                    peers.stopHosting()
                }
            }

            Radar(selected: $selected)
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    Toggle("Visible", isOn: $peers.visible)
                        .toggleStyle(.switch).controlSize(.small)
                        .font(.subheadline.weight(.medium))
                        .help("Let nearby Macs running Rift see this Mac")
                }

            if let p = selected, peers.visible {
                actions(for: p)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selected)
        .onChange(of: peers.visible) { _, on in if !on { selected = nil } }
    }

    private func actions(for p: PeerSession.Peer) -> some View {
        let isConnected = peers.connected.contains { $0.id == p.id }
        return HStack(spacing: 12) {
            ListenerAvatar(profile: p.profile, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.headline)
                Text(isConnected ? "Connected" : peers.inviting.contains(p.id) ? "Waiting for them to accept…" : "Not connected")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isConnected {
                Button { peers.sendCurrentSong(to: p) } label: { Label("Send Song", systemImage: "paperplane.fill") }
                    .disabled(player.track == nil)
                Button { peers.inviteToListen(p) } label: { Label("Listen Together", systemImage: "headphones") }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(player.track == nil || peers.following != nil)
            } else {
                Button { peers.connect(p) } label: { Label("Connect", systemImage: "link") }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(peers.inviting.contains(p.id))
            }
        }
        .controlSize(.large)
    }

    private func banner(_ text: String, icon: String, stop: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text(text).font(.callout.weight(.medium))
            Spacer()
            Button("Stop", action: stop)
        }
        .padding(12)
        .background(accent.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}

private struct Radar: View {
    @Binding var selected: PeerSession.Peer?
    @ObservedObject private var peers = PeerSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var everyone: [PeerSession.Peer] {
        peers.connected + peers.nearby.filter { p in !peers.connected.contains { $0.id == p.id } }
    }

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let R = min(geo.size.width, geo.size.height) / 2 - 20
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !peers.visible)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(1...3, id: \.self) { i in
                        Circle().stroke(.secondary.opacity(0.18), lineWidth: 1)
                            .frame(width: R * 2 * CGFloat(i) / 3, height: R * 2 * CGFloat(i) / 3)
                            .position(c)
                    }
                    if peers.visible && !reduceMotion {
                        ForEach(0..<3, id: \.self) { i in
                            let p = (t / 2.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                            Circle().stroke(.white, lineWidth: 1.5)
                                .frame(width: R * 2 * p, height: R * 2 * p)
                                .opacity((1 - p) * 0.35)
                                .position(c)
                        }
                        AngularGradient(colors: [.white.opacity(0.14), .clear, .clear],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360))
                            .clipShape(.circle)
                            .frame(width: R * 2, height: R * 2)
                            .rotationEffect(.degrees(t * 50))
                            .position(c)
                    }

                    ListenerAvatar(profile: .mine, size: 64, ring: accent)
                        .position(c)

                    ForEach(Array(everyone.enumerated()), id: \.element.id) { i, p in
                        let angle = Double(abs(p.profile.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % 360) * .pi / 180
                        let r = R * 0.68
                        let bob = reduceMotion ? 0 : sin(t * 0.9 + Double(i)) * 4
                        let isConnected = peers.connected.contains { $0.id == p.id }
                        Button { selected = (selected == p ? nil : p) } label: {
                            VStack(spacing: 5) {
                                ListenerAvatar(profile: p.profile, size: 52,
                                               ring: isConnected ? .green : selected == p ? accent : nil)
                                    .overlay {
                                        if peers.inviting.contains(p.id) {
                                            Circle().trim(from: 0, to: 0.3)
                                                .stroke(accent, style: .init(lineWidth: 3, lineCap: .round))
                                                .frame(width: 60, height: 60)
                                                .rotationEffect(.degrees(t * 240))
                                        }
                                    }
                                Text(p.name.components(separatedBy: " ").first ?? p.name)
                                    .font(.caption.weight(.semibold)).lineLimit(1)
                            }
                            .scaleEffect(selected == p ? 1.08 : 1)
                        }
                        .buttonStyle(.plain)
                        .position(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r * 0.85 + bob)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }

                    if !peers.visible {
                        VStack(spacing: 10) {
                            Text("Turn on Visible to look for Macs nearby")
                                .font(.callout.weight(.medium))
                            Button("Turn On") { peers.visible = true }
                                .buttonStyle(.borderedProminent).tint(accent)
                        }
                        .position(x: c.x, y: geo.size.height - 40)
                    } else if everyone.isEmpty {
                        Text("Looking for Macs running Rift…")
                            .font(.callout).foregroundStyle(.secondary)
                            .position(x: c.x, y: geo.size.height - 12)
                    }
                }
                .animation(.spring(response: 0.55, dampingFraction: 0.7), value: everyone.map(\.id))
            }
        }
        .opacity(peers.visible ? 1 : 0.6)
    }
}

/// Subtle press-down for custom buttons.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
