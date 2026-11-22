// SPDX-License-Identifier: GPL-3.0-only
//
// FriendRoom — listen together with friends anywhere, over the internet.
// The host starts a room and shares its code (RIFT-XXXX-XXXX-XXXX); friends
// type it in and their Rift follows the host's track, position and
// play/pause. Everyone appears as a profile bubble on the room stage, can
// throw emoji reactions, and can send a song to the room.
//
// Transport: public Nostr relays (NostrRelay), ephemeral events only — the
// relays forward and forget. Privacy: the room code never leaves the Mac;
// the relay sees a hash of it (the topic) and AES-GCM ciphertext sealed with
// a key derived from it, so only people holding the code can read anything.
// Only track metadata + each member's name/photo travel; every Mac streams
// the audio itself.

import AppKit
import Combine
import CryptoKit
import Foundation

@MainActor
final class FriendRoom: ObservableObject {
    static let shared = FriendRoom()

    enum Role { case host, guest }

    struct Member: Identifiable, Equatable {
        var profile: ListenerProfile
        var isHost: Bool
        let joined: Date
        var id: String { profile.id }
    }

    struct Reaction: Identifiable, Equatable {
        let id = UUID()
        let from: String      // member id
        let emoji: String
    }

    struct Activity: Identifiable, Equatable {
        let id = UUID()
        let icon: String
        let text: String
        let date = Date()
    }

    @Published private(set) var code: String?
    @Published private(set) var role: Role?
    /// Everyone else in the room.
    @Published private(set) var members: [String: Member] = [:]
    @Published private(set) var reactions: [Reaction] = []
    @Published private(set) var activity: [Activity] = []
    /// What the room is playing (the host's track).
    @Published private(set) var nowPlaying: PlayableTrack?
    @Published var error: String?

    static let reactionEmoji = ["❤️", "🔥", "🎉", "👏", "😂", "🕺"]

    private enum Message: Codable {
        case hello(profile: ListenerProfile, isHost: Bool)
        case bye(id: String)
        case sync(track: PlayableTrack, position: Double, playing: Bool, sentAt: Date)
        case song(from: ListenerProfile, track: PlayableTrack)
        case react(from: String, emoji: String)
    }

    private static let kind = 20_777     // ephemeral range: relays never store it
    private var relay: NostrRelay?
    private var key: SymmetricKey?
    private var bag = Set<AnyCancellable>()
    private var timers: [Timer] = []
    private var lastSeen: [String: Date] = [:]
    private var player: PlayerController { AppServices.shared.player }

    var isActive: Bool { code != nil }
    var me: ListenerProfile { ListenerProfile.mine }
    var host: Member? { members.values.first(where: \.isHost) }
    /// Others in join order (host first).
    var sortedMembers: [Member] {
        members.values.sorted { ($0.isHost ? 0 : 1, $0.joined) < ($1.isHost ? 0 : 1, $1.joined) }
    }

    // MARK: lifecycle

    func startRoom() {
        open(Self.newCode(), as: .host)
        guard role == .host else { return }
        log("sparkles", "You started the room")
        Publishers.CombineLatest(player.$track, player.$state.map { $0 == .playing })
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] t, _ in self?.nowPlaying = t; self?.syncNow() }
            .store(in: &bag)
        repeatEvery(10) { [weak self] in self?.syncNow() }   // drift + late joiners
    }

    #if DEBUG
    func debugHost(code raw: String) {
        guard let c = Self.normalise(raw) else { return }
        open(c, as: .host)
        log("sparkles", "You started the room")
        repeatEvery(10) { [weak self] in self?.syncNow() }
    }
    #endif

    func join(_ raw: String) {
        guard let c = Self.normalise(raw) else {
            error = "That code doesn't look right — it's like RIFT-AB12-CD34-EF56."
            return
        }
        open(c, as: .guest)
        log("arrow.right.circle", "You joined the room")
    }

    func leave() {
        send(.bye(id: me.id))
        relay?.close()
        relay = nil; key = nil; code = nil; role = nil; nowPlaying = nil
        members = [:]; lastSeen = [:]; reactions = []; activity = []
        bag.removeAll()
        timers.forEach { $0.invalidate() }; timers = []
    }

    func sendCurrentSong() {
        guard let t = player.track else { return }
        send(.song(from: me, track: t))
        log("paperplane.fill", "You sent “\(t.title)”")
    }

    func react(_ emoji: String) {
        send(.react(from: me.id, emoji: emoji))
        show(Reaction(from: me.id, emoji: emoji))
    }

    private func open(_ c: String, as r: Role) {
        if isActive { leave() }
        PeerSession.shared.stopFollowing()   // one listen-along at a time
        do {
            let topic = Data(SHA256.hash(data: Data("rift-room:\(c)".utf8))).hex
            relay = try NostrRelay(kind: Self.kind, topic: topic)
        } catch {
            self.error = "Couldn't start the room: \(error.localizedDescription)"
            return
        }
        key = SymmetricKey(data: HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(c.utf8)),
            salt: Data("rift-room-v1".utf8), outputByteCount: 32))
        relay?.onEvent = { [weak self] in self?.receive($0) }
        code = c; role = r; error = nil
        Log.player.info("room opened \(c, privacy: .private(mask: .hash)) as \(r == .host ? "host" : "guest", privacy: .public)")
        // Presence: hello now and every 20 s; forget anyone silent for 60 s.
        sayHello()
        repeatEvery(20) { [weak self] in
            guard let self else { return }
            self.sayHello()
            let cutoff = Date().addingTimeInterval(-60)
            for (id, seen) in self.lastSeen where seen < cutoff { self.drop(id) }
        }
    }

    private func sayHello() { send(.hello(profile: me, isHost: role == .host)) }

    private func repeatEvery(_ s: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        timers.append(Timer.scheduledTimer(withTimeInterval: s, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        })
    }

    private func drop(_ id: String) {
        lastSeen[id] = nil
        if let m = members.removeValue(forKey: id) { log("arrow.left.circle", "\(m.profile.name) left") }
    }

    private func log(_ icon: String, _ text: String) {
        Log.player.info("room: \(text, privacy: .public)")
        activity.insert(Activity(icon: icon, text: text), at: 0)
        if activity.count > 20 { activity.removeLast() }
    }

    private func show(_ r: Reaction) {
        reactions.append(r)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            reactions.removeAll { $0.id == r.id }
        }
    }

    // MARK: messages

    private func syncNow() {
        guard role == .host, let t = player.track else { return }
        send(.sync(track: t, position: player.currentTime, playing: player.isPlaying, sentAt: Date()))
    }

    private func send(_ m: Message) {
        guard let relay, let key, let json = try? JSONEncoder().encode(m),
              let sealed = try? AES.GCM.seal(json, using: key).combined else { return }
        relay.publish(sealed.base64EncodedString())
    }

    private func receive(_ content: String) {
        guard let key, let data = Data(base64Encoded: content),
              let box = try? AES.GCM.SealedBox(combined: data),
              let json = try? AES.GCM.open(box, using: key),
              let m = try? JSONDecoder().decode(Message.self, from: json) else { return }
        switch m {
        case let .hello(profile, isHost):
            guard profile.id != me.id else { return }
            lastSeen[profile.id] = Date()
            if var existing = members[profile.id] {
                existing.profile = profile; existing.isHost = isHost
                members[profile.id] = existing
            } else {
                members[profile.id] = Member(profile: profile, isHost: isHost, joined: Date())
                log(isHost ? "crown.fill" : "person.crop.circle.badge.plus",
                    isHost ? "\(profile.name) is hosting" : "\(profile.name) joined")
                if role == .host { syncNow(); sayHello() }   // catch the newcomer up
            }
        case let .bye(id):
            drop(id)
        case let .sync(track, position, playing, sentAt):
            guard role == .guest else { return }
            if nowPlaying?.id != track.id {
                nowPlaying = track
                log("music.note", "Now playing “\(track.title)”")
            }
            let lag = playing ? max(0, min(10, Date().timeIntervalSince(sentAt))) : 0
            player.follow(track, at: position + lag, playing: playing)
        case let .song(from, track):
            log("paperplane.fill", "\(from.name) sent “\(track.title)”")
            SongPrompt.show(from: from.name, track: track, player: player)
        case let .react(from, emoji):
            show(Reaction(from: from, emoji: emoji))
        }
    }

    // MARK: codes

    /// 12 characters from a 31-symbol alphabet without look-alikes (~59 bits).
    private static func newCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let chars = bytes.map { alphabet[Int($0) % alphabet.count] }
        return "RIFT-" + stride(from: 0, to: 12, by: 4).map { String(chars[$0..<$0 + 4]) }.joined(separator: "-")
    }

    /// Forgiving: any case, spaces or missing dashes/prefix.
    static func normalise(_ raw: String) -> String? {
        var s = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        if s.hasPrefix("RIFT") { s.removeFirst(4) }
        guard s.count == 12 else { return nil }
        let a = Array(s)
        return "RIFT-" + stride(from: 0, to: 12, by: 4).map { String(a[$0..<$0 + 4]) }.joined(separator: "-")
    }
}

// MARK: - Shared listen-along helpers

extension PlayerController {
    /// Bring this player onto someone else's track/position/state (±2 s).
    func follow(_ t: PlayableTrack, at target: Double, playing: Bool) {
        if track?.id != t.id {
            play(t)                 // the next sync seeks it into place
            return
        }
        guard state != .loading else { return }
        if abs(currentTime - target) > 2 { seek(to: target) }
        if playing != isPlaying { togglePlayPause() }
    }
}

enum SongPrompt {
    @MainActor
    static func show(from: String, track t: PlayableTrack, player: PlayerController) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "\(from) sent you a song"
        a.informativeText = "\(t.title) — \(t.artist)"
        a.addButton(withTitle: "Play Now")
        a.addButton(withTitle: "Play Next")
        a.addButton(withTitle: "Ignore")
        switch a.runModal() {
        case .alertFirstButtonReturn:  player.play(t)
        case .alertSecondButtonReturn: player.playNext(t)
        default: break
        }
    }
}
