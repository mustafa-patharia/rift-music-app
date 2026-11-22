// SPDX-License-Identifier: GPL-3.0-only
//
// CloudAI — bring-your-own-key provider for Macs that can't run a local model.
// Every preset speaks the OpenAI-compatible `POST {base}/chat/completions`
// shape (every preset below ships that endpoint), so one
// request covers them all. The key lives in the Keychain, never in defaults.
//
// Evaluated: MacPaw/OpenAI (Swift) — maintained, but a whole SDK for a single
// POST; not worth the dependency.

import Foundation

enum CloudPreset: String, CaseIterable, Identifiable {
    case gemini, groq, openai, anthropic, xai, deepseek, mistral, cerebras, together, openrouter, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini:     return "Google Gemini"
        case .groq:       return "Groq"
        case .openai:     return "OpenAI"
        case .anthropic:  return "Anthropic"
        case .xai:        return "xAI (Grok)"
        case .deepseek:   return "DeepSeek"
        case .mistral:    return "Mistral"
        case .cerebras:   return "Cerebras"
        case .together:   return "Together AI"
        case .openrouter: return "OpenRouter"
        case .custom:     return "Custom"
        }
    }

    var baseURL: String {
        switch self {
        case .gemini:     return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .groq:       return "https://api.groq.com/openai/v1"
        case .openai:     return "https://api.openai.com/v1"
        case .anthropic:  return "https://api.anthropic.com/v1"
        case .xai:        return "https://api.x.ai/v1"
        case .deepseek:   return "https://api.deepseek.com/v1"
        case .mistral:    return "https://api.mistral.ai/v1"
        case .cerebras:   return "https://api.cerebras.ai/v1"
        case .together:   return "https://api.together.xyz/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom:     return ""
        }
    }

    /// Used until the live model list loads. Providers retire models (Google
    /// closed gemini-2.5-flash to new keys in late 2026), so Settings picks
    /// from `CloudAI.models` rather than trusting this.
    var defaultModel: String {
        switch self {
        case .gemini:     return "gemini-3.5-flash-lite"
        case .groq:       return "llama-3.3-70b-versatile"
        case .openai:     return "gpt-4.1-mini"
        case .anthropic:  return "claude-haiku-5-5"
        case .xai:        return "grok-3-mini"
        case .deepseek:   return "deepseek-chat"
        case .mistral:    return "mistral-small-latest"
        case .cerebras:   return "llama-3.3-70b"
        case .together:   return "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .openrouter: return "google/gemini-2.5-flash"
        case .custom:     return ""
        }
    }

    /// Where to get a key.
    var keyURL: URL? {
        switch self {
        case .gemini:     return URL(string: "https://aistudio.google.com/apikey")
        case .groq:       return URL(string: "https://console.groq.com/keys")
        case .openai:     return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic:  return URL(string: "https://console.anthropic.com/settings/keys")
        case .xai:        return URL(string: "https://console.x.ai")
        case .deepseek:   return URL(string: "https://platform.deepseek.com/api_keys")
        case .mistral:    return URL(string: "https://console.mistral.ai/api-keys")
        case .cerebras:   return URL(string: "https://cloud.cerebras.ai")
        case .together:   return URL(string: "https://api.together.ai/settings/api-keys")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        case .custom:     return nil
        }
    }

    var note: String {
        switch self {
        case .gemini, .groq, .mistral, .cerebras: return "Free tier available"
        case .openrouter: return "Some free models"
        case .custom:     return "Any OpenAI-compatible API over https"
        default:          return "Billed by the provider"
        }
    }
}

enum CloudAI {
    static let keychainAccount = "ai.cloudKey"

    static var key: String? {
        Keychain.get(account: keychainAccount).flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func setKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { Keychain.delete(account: keychainAccount) }
        else { Keychain.set(Data(k.utf8), account: keychainAccount) }
    }

    /// Chat-capable model ids from `GET {base}/models` — speech, image,
    /// embedding, realtime and agent models filtered out; "models/" dropped.
    static func models(baseURL: String) async throws -> [String] {
        guard let key else { throw fail("Add your API key first.") }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/models"), url.scheme == "https" else {
            throw fail("The API URL must start with https://")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(key, forHTTPHeaderField: "x-api-key")          // Anthropic
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = try? JSONSerialization.jsonObject(with: data)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let list = ((json as? [String: Any])?["data"] as? [[String: Any]])
                  ?? (json as? [[String: Any]])   // Together AI: bare array
        else {
            throw fail(errorMessage(json, resp))
        }
        let skip = ["tts", "embed", "image", "imagen", "veo", "lyria", "live", "audio", "transcribe",
                    "aqa", "robotics", "computer-use", "research", "genie", "banana", "whisper",
                    "dall-e", "moderation", "realtime", "search", "omni", "antigravity", "decision",
                    "guard", "compound"]
        return list.compactMap { $0["id"] as? String }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
            .filter { id in !skip.contains { id.lowercased().contains($0) } }
            .sorted()
    }

    /// The model to fall back on when the saved one isn't offered: a fast,
    /// cheap tier first (lyrics don't need a frontier model).
    static func preferred(in models: [String]) -> String? {
        // "versatile" = Groq's general Llama tier.
        for hint in ["flash-lite", "haiku", "mini", "flash", "versatile", "small", "deepseek-chat", "turbo"] {
            if let m = models.filter({ $0.contains(hint) && !$0.contains("preview") }).max() { return m }
        }
        return models.first
    }

    static func chat(system: String, user: String, baseURL: String, model: String) async throws -> String {
        guard let key else { throw fail("Add your API key in Settings → AI.") }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/chat/completions"), url.scheme == "https" else {
            throw fail("The API URL must start with https://")
        }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw fail(errorMessage(try? JSONSerialization.jsonObject(with: data), resp))
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// error.message, also when wrapped in an array (Gemini does that); never
    /// includes the key.
    private static func errorMessage(_ json: Any?, _ resp: URLResponse?) -> String {
        let obj = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
        return ((obj?["error"] as? [String: Any])?["message"] as? String)
            ?? (obj?["error"] as? String)
            ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
    }

    private static func fail(_ message: String) -> NSError {
        NSError(domain: "CloudAI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
