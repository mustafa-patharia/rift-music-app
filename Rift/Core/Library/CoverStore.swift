// SPDX-License-Identifier: GPL-3.0-only
//
// CoverStore — custom playlist covers (emoji + colour gradient), keyed by the
// playlist's id: a local playlist's UUID or a YouTube Music card id, so any
// playlist in Library can get one. Stored locally in covers.json; YouTube
// Music has no custom-thumbnail API, so covers never sync and never touch the
// account.

import SwiftUI

struct CustomCover: Codable, Equatable {
    var emoji: String
    var palette: CoverPalette
    var showTitle: Bool = false
}

/// Curated two-stop gradients — picked to stay readable behind white text
/// and an emoji, in light and dark mode.
enum CoverPalette: String, Codable, CaseIterable, Identifiable {
    case dusk, cherry, ember, citrus, gold, forest, mint, lagoon, ocean, lavender, rose, midnight
    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .dusk:     return [Color(hex: 0x6A5AE0), Color(hex: 0xF25F9A)]
        case .cherry:   return [Color(hex: 0xEB3349), Color(hex: 0xF45C43)]
        case .ember:    return [Color(hex: 0xF28C28), Color(hex: 0xD54C15)]
        case .citrus:   return [Color(hex: 0xF6D365), Color(hex: 0xFDA085)]
        case .gold:     return [Color(hex: 0xD4A437), Color(hex: 0x7A4E10)]
        case .forest:   return [Color(hex: 0x185844), Color(hex: 0x8FB996)]
        case .mint:     return [Color(hex: 0x2BC48A), Color(hex: 0x38D9D7)]
        case .lagoon:   return [Color(hex: 0x488B7E), Color(hex: 0x52D1DC)]
        case .ocean:    return [Color(hex: 0x0F1E3A), Color(hex: 0x4A7BD0)]
        case .lavender: return [Color(hex: 0xA18CD1), Color(hex: 0xFBC2EB)]
        case .rose:     return [Color(hex: 0xB05A7A), Color(hex: 0xE8B4BC)]
        case .midnight: return [Color(hex: 0x141418), Color(hex: 0x3E3E52)]
        }
    }

    var name: String { rawValue.capitalized }
}

@MainActor
final class CoverStore: ObservableObject {
    static let shared = CoverStore()

    /// Playlist whose cover is being edited — ContentView presents one
    /// app-level editor sheet for every entry point.
    struct Target: Identifiable { let id: String; let title: String }
    @Published var editing: Target?

    @Published private(set) var covers: [String: CustomCover] = [:]

    private let file: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("com.mustafapatharia.riftmusicapp/covers.json")

    private init() {
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: CustomCover].self, from: data) {
            covers = saved
        }
    }

    /// The user's cover, else a built-in one — Liked Music gets a red heart
    /// on midnight instead of YouTube Music's flat thumbs-up thumbnail.
    func cover(for id: String) -> CustomCover? { covers[id] ?? Self.builtIn[id] }

    private static let liked = CustomCover(emoji: "❤️", palette: .midnight)
    private static let builtIn: [String: CustomCover] = ["LM": liked, "VLLM": liked]

    func set(_ cover: CustomCover?, for id: String) {
        covers[id] = cover
        if let file { try? JSONEncoder().encode(covers).write(to: file) }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
