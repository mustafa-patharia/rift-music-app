// SPDX-License-Identifier: GPL-3.0-only
//
// AppleAI — on-device Apple Intelligence (FoundationModels, macOS 26): the
// built-in ~3B system model, no download, nothing leaves the machine. One of
// the providers behind the AI facade (AIStore picks); OFF until the user
// enables it in Settings.

import Foundation
import FoundationModels

enum AppleAI {

    static var isAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
    }

    /// One instruction-guided completion. Fresh session per call — no
    /// accumulated transcript, no drift between chunks.
    static func respond(instructions: String, to prompt: String) async throws -> String {
        guard #available(macOS 26, *) else {
            throw NSError(domain: "AppleAI", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence requires macOS 26 or later."])
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
