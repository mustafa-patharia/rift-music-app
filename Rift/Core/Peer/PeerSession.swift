// SPDX-License-Identifier: GPL-3.0-only
//
// PeerSession — Rift-to-Rift over the local network / Bluetooth, no server:
//   • Send a song   — the current track lands on a nearby Mac as
//                     "Play now / Play next / Ignore".
//   • Listen together — the host's track, position and play/pause stream to
//                     every Mac that accepted; they follow in sync (±2 s).
// Only track metadata travels (YouTube id, title, artist, artwork URL); each
// Mac streams the audio itself. Nothing is visible to others until the user
// turns on "Visible to nearby Macs", and every connection and listen-along
// request is accepted on the receiving Mac first.
//
// Evaluated: MultipeerConnectivity (Apple, built in) — discovery, invites and
// encrypted sessions over Wi-Fi / peer-to-peer Wi-Fi / Bluetooth in one API;
// no dependency or relay needed. Nostr/WebRTC would add internet reach but
// need relays/servers — later, if ever (PLAN #54).

import AppKit
import Combine
@preconcurrency import MultipeerConnectivity

@MainActor
final class PeerSession: NSObject, ObservableObject {
    static let shared = PeerSession()

    struct Peer: Identifiable, Hashable {
        let id: MCPeerID
        /// From the peer's discovery info (name + photo); falls back to the
        /// Mac's name.
        var profile: ListenerProfile
        var name: String { profile.name }
    }

    @Published var visible = false { didSet { visible ? start() : stop() } }
    @Published private(set) var nearby: [Peer] = []
    @Published private(set) var connected: [Peer] = []
    @Published private(set) var inviting: Set<MCPeerID> = []
    /// Streaming my playback to everyone connected.
    @Published private(set) var hosting = false
    /// The peer whose playback I follow.
    @Published private(set) var following: MCPeerID?

    private enum Message: Codable {
        case song(PlayableTrack)
        case listenInvite
        case listenAccepted
        case sync(track: PlayableTrack, position: Double, playing: Bool, sentAt: Date)
        case listenStop
    }

    private static let service = "rift-p2p"      // ≤15 chars, Bonjour _rift-p2p._tcp
    private let me = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var bag = Set<AnyCancellable>()
    private var heartbeat: Timer?
    private var player: PlayerController { AppServices.shared.player }

    // MARK: lifecycle

    private func start() {
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        // Discovery info (≤ 400 bytes) carries who we are, for the radar bubbles.
        var info = ["n": String(ListenerProfile.mine.name.prefix(60))]
        if let p = ListenerProfile.mine.photo?.absoluteString, p.count < 300 { info["p"] = p }
        let a = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: info, serviceType: Self.service)
        a.delegate = self; a.startAdvertisingPeer(); advertiser = a
        let b = MCNearbyServiceBrowser(peer: me, serviceType: Self.service)
        b.delegate = self; b.startBrowsingForPeers(); browser = b
    }

    private func stop() {
        stopHosting()
        following = nil
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil; browser = nil; session = nil
        nearby = []; connected = []; inviting = []
    }

    // MARK: actions

    func connect(_ peer: Peer) {
        guard let session, let browser else { return }
        inviting.insert(peer.id)
        browser.invitePeer(peer.id, to: session, withContext: nil, timeout: 30)
    }

    func disconnectAll() { session?.disconnect(); connected = []; hosting = false; following = nil }

    func sendCurrentSong(to peer: Peer) {
        guard let t = player.track else { return }
        send(.song(t), to: [peer.id])
    }

    func inviteToListen(_ peer: Peer) {
        send(.listenInvite, to: [peer.id])
    }

    func stopHosting() {
        guard hosting else { return }
        hosting = false
        heartbeat?.invalidate(); heartbeat = nil
        bag.removeAll()
        send(.listenStop, to: connected.map(\.id))
    }

    func stopFollowing() {
        if let f = following { send(.listenStop, to: [f]) }
        following = nil
    }

    private func startHosting() {
        guard !hosting else { syncNow(); return }
        hosting = true
        // Push on every track / play-state change, plus a heartbeat that
        // also corrects drift and catches seeks.
        Publishers.CombineLatest(player.$track, player.$state.map { $0 == .playing })
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncNow() }
            .store(in: &bag)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
    }

    private func syncNow() {
        guard hosting, let t = player.track else { return }
        send(.sync(track: t, position: player.currentTime, playing: player.isPlaying, sentAt: Date()),
             to: connected.map(\.id), reliable: false)
    }

    private func send(_ m: Message, to peers: [MCPeerID], reliable: Bool = true) {
        guard let session, !peers.isEmpty, let data = try? JSONEncoder().encode(m) else { return }
        try? session.send(data, toPeers: peers, with: reliable ? .reliable : .unreliable)
    }

    // MARK: incoming

    private func receive(_ m: Message, from peer: MCPeerID) {
        switch m {
        case .song(let t):
            SongPrompt.show(from: peer.displayName, track: t, player: player)
        case .listenInvite:
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Listen together with \(peer.displayName)?"
            a.informativeText = "Rift will play what \(peer.displayName) plays, in sync, until you stop."
            a.addButton(withTitle: "Listen Together")
            a.addButton(withTitle: "Not Now")
            if a.runModal() == .alertFirstButtonReturn {
                if FriendRoom.shared.role == .guest { FriendRoom.shared.leave() }   // one at a time
                following = peer
                send(.listenAccepted, to: [peer])
            }
        case .listenAccepted:
            startHosting()
        case .listenStop:
            if following == peer { following = nil }
        case let .sync(track, position, playing, sentAt):
            guard following == peer else { return }
            player.follow(track, at: position + (playing ? max(0, Date().timeIntervalSince(sentAt)) : 0),
                   playing: playing)
        }
    }

    private func peerChanged(_ peer: MCPeerID, _ state: MCSessionState) {
        inviting.remove(peer)
        connected.removeAll { $0.id == peer }
        if state == .connected {
            connected.append(nearby.first { $0.id == peer } ?? Peer(id: peer, profile: Self.profile(peer, nil)))
            if hosting { syncNow() }
        } else if following == peer {
            following = nil
        }
        if connected.isEmpty, hosting { stopHosting() }
    }

    private func found(_ peer: MCPeerID, _ info: [String: String]?) {
        guard peer != me, !nearby.contains(where: { $0.id == peer }) else { return }
        nearby.append(Peer(id: peer, profile: Self.profile(peer, info)))
    }

    private static func profile(_ peer: MCPeerID, _ info: [String: String]?) -> ListenerProfile {
        ListenerProfile(id: peer.displayName + "#\(peer.hash)",
                        name: info?["n"] ?? peer.displayName,
                        photo: info?["p"].flatMap(URL.init(string:)))
    }

    private func lost(_ peer: MCPeerID) { nearby.removeAll { $0.id == peer } }

    private func invited(by peer: MCPeerID, reply: @escaping (Bool, MCSession?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "\(peer.displayName) wants to connect"
        a.informativeText = "Connected Macs can send you songs and invite you to listen together."
        a.addButton(withTitle: "Connect")
        a.addButton(withTitle: "Decline")
        reply(a.runModal() == .alertFirstButtonReturn, session)
    }
}

// MARK: - MultipeerConnectivity delegates (called off the main thread)

extension PeerSession: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.peerChanged(peerID, state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let m = try? JSONDecoder().decode(Message.self, from: data) else { return }
        Task { @MainActor in self.receive(m, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let reply = invitationHandler
        Task { @MainActor in self.invited(by: peerID, reply: reply) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        nonisolated(unsafe) let info = info
        Task { @MainActor in self.found(peerID, info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.lost(peerID) }
    }
}
