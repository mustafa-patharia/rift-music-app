// SPDX-License-Identifier: GPL-3.0-only
//
// NostrRelay — the smallest Nostr client Rift needs (NIP-01): publish and
// subscribe to ephemeral events (kind 20000–29999, which relays forward but
// never store) on a few public relays over WebSocket. Used by FriendRoom so
// friends anywhere can listen together without a Rift server.
//
// Evaluated: nostr-sdk-ios (MIT) — full SDK, no commits since Jan 2026;
// rust-nostr bindings — large binary. NIP-01 is JSON over a WebSocket, so
// only the BIP-340 Schnorr signature needs a library: swift-secp256k1
// (21-DOT-DEV, MIT, actively maintained), pinned to 0.24.0.

import CryptoKit
import Foundation
import P256K

@MainActor
final class NostrRelay {
    static let relays = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net"]

    /// Content of every matching event from someone else, deduplicated
    /// across relays.
    var onEvent: ((String) -> Void)?

    private let key: P256K.Schnorr.PrivateKey
    private let pubkey: String
    private let kind: Int
    private let topic: String
    private var sockets: [URLSessionWebSocketTask] = []
    private var seen = Set<String>()
    private var closed = false
    private let subID = UUID().uuidString.prefix(12).lowercased()

    init(kind: Int, topic: String) throws {
        // A fresh throwaway identity per room — nothing links it to the user.
        key = try P256K.Schnorr.PrivateKey()
        pubkey = Data(key.xonly.bytes).hex
        self.kind = kind
        self.topic = topic
        for r in Self.relays { if let url = URL(string: r) { connect(url, attempt: 0) } }
    }

    func close() {
        closed = true
        sockets.forEach { $0.cancel(with: .goingAway, reason: nil) }
        sockets = []
    }

    func publish(_ content: String) {
        guard let event = try? sign(content) else { return }
        seen.insert(event["id"] as? String ?? "")
        guard let data = try? JSONSerialization.data(withJSONObject: ["EVENT", event], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return }
        for s in sockets where s.state == .running { s.send(.string(text)) { _ in } }
    }

    // MARK: connection

    private func connect(_ url: URL, attempt: Int) {
        guard !closed else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        sockets.append(task)
        task.resume()
        let filter: [String: Any] = ["kinds": [kind], "#t": [topic], "since": Int(Date().timeIntervalSince1970) - 5]
        if let data = try? JSONSerialization.data(withJSONObject: ["REQ", String(subID), filter], options: [.withoutEscapingSlashes]),
           let text = String(data: data, encoding: .utf8) {
            task.send(.string(text)) { _ in }
        }
        receive(task, url: url, attempt: attempt)
    }

    private func receive(_ task: URLSessionWebSocketTask, url: URL, attempt: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(task, url: url, attempt: 0)
                case .failure:
                    // Dropped: back off (2, 4, 8… ≤ 60 s) and reconnect.
                    self.sockets.removeAll { $0 === task }
                    let delay = min(60.0, pow(2, Double(attempt + 1)))
                    try? await Task.sleep(for: .seconds(delay))
                    self.connect(url, attempt: attempt + 1)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return }
        // ["OK", id, accepted, reason] — log rejections (bad signature, rate limit).
        if msg.first as? String == "OK", msg.count >= 4, msg[2] as? Bool == false {
            Log.player.error("nostr relay rejected event: \(String(describing: msg[3]), privacy: .public)")
            return
        }
        guard msg.first as? String == "EVENT", msg.count >= 3,
              let event = msg[2] as? [String: Any],
              let id = event["id"] as? String, !seen.contains(id),
              event["pubkey"] as? String != pubkey,
              let content = event["content"] as? String else { return }
        seen.insert(id)
        if seen.count > 2000 { seen.removeAll() }
        onEvent?(content)
    }

    // MARK: NIP-01 event

    private func sign(_ content: String) throws -> [String: Any] {
        let created = Int(Date().timeIntervalSince1970)
        let tags = [["t", topic]]
        let serial: [Any] = [0, pubkey, created, kind, tags, content]
        let bytes = try JSONSerialization.data(withJSONObject: serial, options: [.withoutEscapingSlashes])
        var id = Array(CryptoKit.SHA256.hash(data: bytes))
        var aux = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, aux.count, &aux)
        let sig = try key.signature(message: &id, auxiliaryRand: &aux, strict: true)
        return ["id": Data(id).hex, "pubkey": pubkey, "created_at": created, "kind": kind,
                "tags": tags, "content": content, "sig": sig.dataRepresentation.hex]
    }
}

#if DEBUG
extension NostrRelay {
    /// `RIFT_NOSTR_SELFTEST=1`: two throwaway identities on one random topic;
    /// logs whether B receives A's event through the public relays.
    static func selfTest() {
        let topic = UUID().uuidString
        guard let a = try? NostrRelay(kind: 20_777, topic: topic),
              let b = try? NostrRelay(kind: 20_777, topic: topic) else { return }
        b.onEvent = { Log.player.info("nostr selftest RECEIVED: \($0, privacy: .public)") }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            a.publish("hello-\(topic.prefix(6))")
            Log.player.info("nostr selftest published")
            try? await Task.sleep(for: .seconds(10))
            a.close(); b.close()
        }
    }
}
#endif

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
