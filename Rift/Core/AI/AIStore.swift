// SPDX-License-Identifier: GPL-3.0-only
//
// AIStore — which AI backend powers the app's AI features (sing-along
// transliteration, lyric translation, future playlist builder). Off by default: the user picks a provider in
// Settings first. Apple Intelligence = the built-in macOS 26 on-device system
// model (no download, nothing leaves the Mac); API Key = the user's own key
// for a hosted model (Gemini / OpenAI / Anthropic / OpenRouter / custom).

import Foundation
import NaturalLanguage

@MainActor
final class AIStore: ObservableObject {
    static let shared = AIStore()

    enum Provider: String, CaseIterable, Identifiable {
        case off, apple, cloud
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Off"
            case .apple: return "Apple Intelligence"
            case .cloud: return "API Key"
            }
        }
    }

    @Published var provider: Provider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider") }
    }
    // Bring-your-own-key (CloudAI). The key itself is in the Keychain.
    @Published var cloudPreset: CloudPreset {
        didSet {
            UserDefaults.standard.set(cloudPreset.rawValue, forKey: "ai.cloudPreset")
            if cloudPreset != .custom { cloudBaseURL = cloudPreset.baseURL; cloudModel = cloudPreset.defaultModel }
        }
    }
    @Published var cloudModel: String {
        didSet { UserDefaults.standard.set(cloudModel, forKey: "ai.cloudModel") }
    }
    @Published var cloudBaseURL: String {
        didSet { UserDefaults.standard.set(cloudBaseURL, forKey: "ai.cloudBaseURL") }
    }
    @Published private(set) var hasCloudKey = CloudAI.key != nil

    func setCloudKey(_ key: String) {
        CloudAI.setKey(key)
        hasCloudKey = CloudAI.key != nil
    }

    private init() {
        provider = Provider(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "") ?? .off
        let preset = CloudPreset(rawValue: UserDefaults.standard.string(forKey: "ai.cloudPreset") ?? "") ?? .gemini
        cloudPreset = preset
        cloudModel = UserDefaults.standard.string(forKey: "ai.cloudModel") ?? preset.defaultModel
        cloudBaseURL = UserDefaults.standard.string(forKey: "ai.cloudBaseURL") ?? preset.baseURL
    }

    /// Feature gates (the lyrics "Aa" button etc.) key off this.
    var isReady: Bool {
        switch provider {
        case .off: return false
        case .apple: return AppleAI.isAvailable
        case .cloud: return hasCloudKey && !cloudModel.isEmpty && !cloudBaseURL.isEmpty
        }
    }
}

/// The feature-facing facade — routes each task to the selected provider.
enum AI {

    /// Each line in English, same count and order as `lines` — so synced
    /// lyrics stay synced in translation. Keeps the poetic register; not a
    /// word-by-word gloss.
    @MainActor
    static func translate(_ lines: [String]) async throws -> [String] {
        let instructions = """
        You translate song lyrics into natural English. Preserve the poetic \
        tone and meaning — do not explain, annotate, or add anything. Lines \
        already in English stay unchanged.
        Input lines look like "7| text". Output every line in the same format \
        with the same number, one per line, and nothing else.
        """
        return try await numbered(lines, instructions: instructions) { $0 }
    }

    /// Dominant language isn't English → offer the translate action.
    static func isNonEnglish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(400)))
        guard let lang = recognizer.dominantLanguage else { return false }
        return lang != .english
    }

    @MainActor
    static func respond(instructions: String, to chunk: String) async throws -> String {
        switch AIStore.shared.provider {
        case .apple:
            return try await AppleAI.respond(instructions: instructions, to: chunk)
        case .cloud:
            let ai = AIStore.shared
            return try await CloudAI.chat(system: instructions, user: chunk,
                                          baseURL: ai.cloudBaseURL, model: ai.cloudModel)
        case .off:
            throw NSError(domain: "AI", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AI is off — pick a model in Settings."])
        }
    }

    private static func stanzaChunks(_ text: String, limit: Int = 1500) -> [String] {
        var chunks: [String] = []
        var current = ""
        for stanza in text.components(separatedBy: "\n\n") {
            if !current.isEmpty && current.count + stanza.count > limit {
                chunks.append(current); current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + stanza
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
