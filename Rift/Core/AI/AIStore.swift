// SPDX-License-Identifier: GPL-3.0-only
//
// AIStore — which AI backend powers the app's AI features (Hinglish lyrics,
// future playlist builder). Off by default: the user picks a provider in
// Settings first. Apple Intelligence = the built-in macOS 26 on-device system
// model (no download); Ollama = user-installed local models. Everything runs
// on this Mac either way.

import Foundation
import NaturalLanguage

@MainActor
final class AIStore: ObservableObject {
    static let shared = AIStore()

    enum Provider: String, CaseIterable, Identifiable {
        case off, apple, ollama
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Off"
            case .apple: return "Apple Intelligence"
            case .ollama: return "Ollama"
            }
        }
    }

    @Published var provider: Provider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider") }
    }
    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "ai.ollamaModel") }
    }

    private init() {
        provider = Provider(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "") ?? .off
        ollamaModel = UserDefaults.standard.string(forKey: "ai.ollamaModel") ?? ""
    }

    /// Feature gates (the lyrics "Aa" button etc.) key off this.
    var isReady: Bool {
        switch provider {
        case .off: return false
        case .apple: return AppleAI.isAvailable
        case .ollama: return !ollamaModel.isEmpty
        }
    }
}

/// The feature-facing facade — routes each task to the selected provider.
enum AI {

    /// Lyrics in ANY non-Latin script → their standard Latin-letter
    /// romanization (Hindi → Hinglish, Korean → Revised Romanization,
    /// Mandarin → Pinyin, Russian → BGN/PCGN, Malayalam → the transliteration
    /// fans post online, etc.) — singable, not translated. Stanza-chunked so
    /// long lyrics fit small local models' context windows; fresh
    /// session/request per chunk.
    @MainActor
    static func romanize(_ lyrics: String) async throws -> String {
        let instructions = """
        You transliterate song lyrics into the Latin alphabet, using \
        whichever romanization convention native speakers and fans actually \
        use for that language online (e.g. Hindi Devanagari → Hinglish like \
        "तेरे इश्क़ में" → "tere ishq mein"; Korean Hangul → Revised \
        Romanization; Mandarin Hanzi → Pinyin; Russian Cyrillic → standard \
        transliteration; Malayalam script → common fan transliteration). Do \
        NOT translate the meaning into English — only convert the script so \
        it can be sung. Keep every line break exactly where it is. Lines \
        already in Latin letters stay unchanged. Output only the \
        transliterated lyrics, nothing else.
        """
        var out: [String] = []
        for chunk in stanzaChunks(lyrics) {
            out.append(try await respond(instructions: instructions, to: chunk))
        }
        return out.joined(separator: "\n\n")
    }

    /// Lyrics in ANY language → English. Keeps line breaks and the poetic
    /// register; not a word-by-word gloss.
    @MainActor
    static func translate(_ lyrics: String) async throws -> String {
        let instructions = """
        You translate song lyrics into natural English. Preserve the poetic \
        tone and meaning — do not explain, annotate, or add anything. Keep \
        every line break exactly where it is; translate line by line. Lines \
        already in English stay unchanged. Output only the translated lyrics.
        """
        var out: [String] = []
        for chunk in stanzaChunks(lyrics) {
            out.append(try await respond(instructions: instructions, to: chunk))
        }
        return out.joined(separator: "\n\n")
    }

    /// Dominant language isn't English → offer the translate action.
    static func isNonEnglish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(400)))
        guard let lang = recognizer.dominantLanguage else { return false }
        return lang != .english
    }

    /// Any character outside Latin/common-punctuation blocks → offer
    /// romanization (Hindi, Korean, Chinese, Russian, Malayalam, etc. all
    /// qualify; this is a script check, independent of `isNonEnglish`'s
    /// language check, so e.g. romanized Hindi already in Latin letters
    /// correctly does NOT re-offer romanization).
    static func hasNonLatinScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0000...0x024F,   // Basic Latin, Latin-1 Supplement, Latin Extended A/B
                 0x2000...0x206F:   // general punctuation (dashes, quotes, etc.)
                return false
            default:
                return scalar.properties.isAlphabetic
            }
        }
    }

    @MainActor
    private static func respond(instructions: String, to chunk: String) async throws -> String {
        switch AIStore.shared.provider {
        case .apple:
            return try await AppleAI.respond(instructions: instructions, to: chunk)
        case .ollama:
            return try await OllamaClient.chat(system: instructions, user: chunk,
                                               model: AIStore.shared.ollamaModel)
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
