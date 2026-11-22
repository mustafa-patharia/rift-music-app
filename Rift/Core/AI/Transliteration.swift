// SPDX-License-Identifier: GPL-3.0-only
//
// Transliteration — rewrites lyrics in a writing system the listener can read,
// keeping the original words so they can sing the original song:
//   तुम ही हो → "tum hi ho" (Latin) · "Тум хи хо" (Cyrillic) · "トゥム ヒ ホ" (Japanese)
// Phonetic, not translated: "tum" never becomes "you".
//
// Two passes on the selected model (Apple Intelligence / your API key):
//   1. sound   — the lyrics as pronounced, in plain Latin letters
//                ("ज़िन्दगी" → "zindagi", "life" → "laif")
//   2. spell   — those sounds written in the target script, treated as
//                meaningless syllables
// Asked in one step, a 4B model (gemma3:4b, tested 2026-11-22) translates —
// "zindagi" became Russian "жизни…", English lines came out as Hindi. Seeing
// only sounds in pass 2, it stops.
//
// Evaluated: ICU transforms (`String.applyingTransform`) never translate but
// spell letter by letter ("chain" → "цхаин", Hindi without schwa deletion) and
// their Arabic/Hebrew/Thai output is unreadable — so ICU is only the safety
// net for a line the model skipped or left in the wrong script.
//
// Line-numbered in and out so the result maps 1:1 back onto the source lines —
// that keeps synced lyrics synced in the new script.

import Foundation
import NaturalLanguage

enum LyricScript: String, CaseIterable, Identifiable {
    case latin, devanagari, urdu, arabic, bengali, tamil, cyrillic, greek, hebrew, japanese, korean, thai

    var id: String { rawValue }

    /// Menu label: the script plus who reads it, in that script where it helps
    /// a reader recognise their own.
    var label: String {
        switch self {
        case .latin:      return "Roman letters (A–Z)"
        case .devanagari: return "Devanagari · देवनागरी"
        case .urdu:       return "Urdu · اردو"
        case .arabic:     return "Arabic · العربية"
        case .bengali:    return "Bengali · বাংলা"
        case .tamil:      return "Tamil · தமிழ்"
        case .cyrillic:   return "Cyrillic · Кириллица"
        case .greek:      return "Greek · Ελληνικά"
        case .hebrew:     return "Hebrew · עברית"
        case .japanese:   return "Japanese · カタカナ"
        case .korean:     return "Korean · 한글"
        case .thai:       return "Thai · ไทย"
        }
    }

    /// What pass 2 writes in, and whose reading habits it spells for.
    fileprivate var spelling: (script: String, reader: String) {
        switch self {
        case .latin:      return ("Latin letters", "English")
        case .devanagari: return ("Devanagari (use nukta and ऑ for sounds Hindi lacks)", "Hindi")
        case .urdu:       return ("Urdu script (Nastaliq)", "Urdu")
        case .arabic:     return ("Arabic script", "Arabic")
        case .bengali:    return ("Bengali script", "Bengali")
        case .tamil:      return ("Tamil script", "Tamil")
        case .cyrillic:   return ("Russian Cyrillic", "Russian")
        case .greek:      return ("the Greek alphabet", "Greek")
        case .hebrew:     return ("Hebrew script", "Hebrew")
        case .japanese:   return ("Japanese katakana (ー for long vowels, small kana like ゥ ィ for sounds Japanese lacks)", "Japanese")
        case .korean:     return ("Korean Hangul", "Korean")
        case .thai:       return ("Thai script", "Thai")
        }
    }

    /// "tum hi ho, ab tum hi ho" in this script — pass 2's worked example.
    fileprivate var example: String {
        switch self {
        case .latin:      return "tum hi ho, ab tum hi ho"
        case .devanagari: return "तुम ही हो, अब तुम ही हो"
        case .urdu:       return "تم ہی ہو، اب تم ہی ہو"
        case .arabic:     return "توم هي هو، اب توم هي هو"
        case .bengali:    return "তুম হি হো, অব তুম হি হো"
        case .tamil:      return "தும் ஹி ஹோ, அப் தும் ஹி ஹோ"
        case .cyrillic:   return "тум хи хо, аб тум хи хо"
        case .greek:      return "τουμ χι χο, αμπ τουμ χι χο"
        case .hebrew:     return "תום הי הו, אב תום הי הו"
        case .japanese:   return "トゥム ヒ ホ、アブ トゥム ヒ ホ"
        case .korean:     return "툼 히 호, 압 툼 히 호"
        case .thai:       return "ตุม ฮี โฮ, อับ ตุม ฮี โฮ"
        }
    }

    /// ICU fallback for a line the model left in Latin letters.
    fileprivate var icuFromLatin: String {
        switch self {
        case .latin:      return "Latin-ASCII"
        case .devanagari: return "Latin-Devanagari"
        case .urdu, .arabic: return "Latin-Arabic"
        case .bengali:    return "Latin-Bengali"
        case .tamil:      return "Latin-Tamil"
        case .cyrillic:   return "Latin-Cyrillic"
        case .greek:      return "Latin-Greek"
        case .hebrew:     return "Latin-Hebrew"
        case .japanese:   return "Latin-Katakana"
        case .korean:     return "Latin-Hangul"
        case .thai:       return "Latin-Thai"
        }
    }

    private var ranges: [ClosedRange<UInt32>] {
        switch self {
        case .latin:      return [0x0041...0x024F]
        case .devanagari: return [0x0900...0x097F]
        case .urdu:       return []                       // shares Arabic's block
        case .arabic:     return [0x0600...0x06FF, 0x0750...0x077F]
        case .bengali:    return [0x0980...0x09FF]
        case .tamil:      return [0x0B80...0x0BFF]
        case .cyrillic:   return [0x0400...0x04FF]
        case .greek:      return [0x0370...0x03FF]
        case .hebrew:     return [0x0590...0x05FF]
        case .japanese:   return [0x3040...0x30FF]
        case .korean:     return [0xAC00...0xD7AF, 0x1100...0x11FF]
        case .thai:       return [0x0E00...0x0E7F]
        }
    }

    /// The script most of the lyrics' letters are in — that one is left out of
    /// the menu (Arabic-block text hides both Arabic and Urdu).
    static func dominant(in text: String) -> LyricScript? {
        var counts: [LyricScript: Int] = [:]
        for s in text.unicodeScalars where s.properties.isAlphabetic {
            if let script = allCases.first(where: { $0.ranges.contains { $0.contains(s.value) } }) {
                counts[script, default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    func isSource(of dominant: LyricScript?) -> Bool {
        dominant == self || (dominant == .arabic && self == .urdu)
    }
}

extension AI {
    /// Each line rewritten in `script`, same count and order as `lines`.
    /// Blank lines pass through; a line the model drops or leaves unconverted
    /// is filled by ICU so the result always lines up with the source (and
    /// its timestamps) and is never left in the wrong script.
    @MainActor
    static func transliterate(_ lines: [String], into script: LyricScript) async throws -> [String] {
        // Naming the language stops a model reading Japanese kanji as Chinese
        // or guessing Korean spelling ("salang-" for 사랑).
        let language = languageName(of: lines.joined(separator: "\n"))
        let context = language.map { "The lyrics are in \($0) (some lines may mix in other languages). " } ?? ""
        let format = """
        Input lines look like "7| text". Output every line in the same format \
        with the same number, one per line, and nothing else.
        """
        // Pass 1 — the sounds, in Latin letters.
        let sound = script == .latin
            ? """
              \(context)You romanize song lyrics so they can be sung by someone who cannot \
              read the original script. Write them the casual way fans post \
              lyrics online (Hindi/Urdu → Hinglish style, Japanese → Hepburn \
              romaji, Korean → Revised Romanization, Mandarin → pinyin without \
              tone marks), plain a–z with no accents. Follow how the words are \
              actually sung (Hindi drops the final inherent vowel: "कमल" → \
              "kamal"). Never translate: Hindi "तुम" is "tum", never "you". Keep \
              punctuation and repetitions.
              \(format)
              Example: "1| तुम ही हो, अब तुम ही हो" → "1| tum hi ho, ab tum hi ho"
              """
            : """
              \(context)You write how song lyrics SOUND, in simple phonetic Latin letters \
              (a–z, no accents), so they can later be respelled in another \
              script. Spell the pronunciation as sung, not the original \
              spelling: Hindi "ज़िन्दगी" → "zindagi", English "life" → "laif", \
              "the" → "dha", Japanese "夜" → "yoru". Never translate. Keep \
              punctuation and repetitions.
              \(format)
              Example: "1| Is this the real life?" → "1| iz dhis dha reel laif?"
              """
        let latin = try await numbered(lines, instructions: sound) { line in
            // Still holds non-Latin letters → ICU romanizes what's left.
            line.hasNonLatinLetters ? line.icu("Any-Latin; Latin-ASCII") : line
        }
        if script == .latin { return latin }

        // Pass 2 — those sounds, spelled in the target script.
        let (target, reader) = script.spelling
        let spell = """
        You are a phonetic spelling converter. The input is song lyrics written \
        as SOUNDS in Latin letters. Write the exact same sounds in \(target).
        Treat every word as a meaningless sequence of syllables. Never replace \
        a word with a \(reader) word — read aloud by a \(reader) reader, the \
        output must sound the same as the input read aloud.
        \(format)
        Example: "1| tum hi ho, ab tum hi ho" → "1| \(script.example)"
        """
        return try await numbered(latin, instructions: spell) { line in
            line.isMostlyLatin ? line.icu(script.icuFromLatin) : line
        }
    }

    /// Sends non-blank lines ~30 at a time as "n| text", reads them back by
    /// number, and runs `repair` on every line (a skipped line arrives as its
    /// input, so repair converts it).
    @MainActor
    static func numbered(_ lines: [String], instructions: String,
                                 repair: (String) -> String) async throws -> [String] {
        var out = lines
        let todo = lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        var firstError: Error?
        var answered = 0
        // ~30 lines a call keeps small on-device models inside their context.
        for start in stride(from: 0, to: todo.count, by: 30) {
            let batch = Array(todo[start..<min(start + 30, todo.count)])
            let prompt = batch.enumerated().map { "\($0.offset + 1)| \(lines[$0.element])" }
                .joined(separator: "\n")
            do {
                let reply = try await respond(instructions: instructions, to: prompt)
                for (n, text) in numberedLines(reply) where n >= 1 && n <= batch.count {
                    out[batch[n - 1]] = text
                    answered += 1
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        if answered == 0, let firstError { throw firstError }
        for i in todo { out[i] = repair(out[i]) }
        return out
    }

    /// English name of the lyrics' dominant language, e.g. "Japanese".
    private static func languageName(of text: String) -> String? {
        guard let code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
              code != "und" else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }

    /// "12| text" (also "12." "12:" "12)") → (12, "text").
    private static func numberedLines(_ reply: String) -> [(Int, String)] {
        let pattern = #/^\s*(\d+)\s*[|:.)\]]\s?(.*)$/#
        return reply.split(whereSeparator: \.isNewline).compactMap { raw in
            guard let m = String(raw).wholeMatch(of: pattern), let n = Int(m.output.1) else { return nil }
            let text = String(m.output.2).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (n, text)
        }
    }
}

private extension String {
    func icu(_ transform: String) -> String {
        applyingTransform(StringTransform(transform), reverse: false) ?? self
    }

    private var letters: [Unicode.Scalar] { unicodeScalars.filter { $0.properties.isAlphabetic } }

    var hasNonLatinLetters: Bool { letters.contains { $0.value > 0x024F } }

    /// More Latin letters than any other — the model didn't convert it.
    var isMostlyLatin: Bool {
        let l = letters
        return !l.isEmpty && l.filter { $0.value <= 0x024F }.count * 2 > l.count
    }
}
