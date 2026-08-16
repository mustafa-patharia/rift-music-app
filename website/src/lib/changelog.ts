// Single source of truth for the changelog. Mirrored in /CHANGELOG.md.
export interface ChangeSection { label: "Added" | "Changed" | "Fixed" | "Coming"; items: string[]; }
export interface Release { version: string; date?: string; current?: boolean; sections: ChangeSection[]; }

export const CHANGELOG: Release[] = [
  {
    version: "1.0.0",
    date: "2026-08-16",
    current: true,
    sections: [
      {
        label: "Added",
        items: [
          "Zero setup — the playback engine ships inside the app: no Homebrew, no Python, no admin password, nothing to download on first launch",
          "Native browse — search, artists, albums, charts and playlists in SwiftUI",
          "Dynamic Island in the notch, plus a menu-bar player",
          "Offline downloads with instant-replay stream caching",
          "Gapless crossfade for smooth transitions between songs",
          "Synced lyrics with optional on-device AI (Apple Intelligence / Ollama) for transliteration & translation, with multilingual support",
          "Listening stats — top songs, top artists, clocks by hour and weekday, stored locally only",
          "YouTube Music sign-in — your playlists, likes, recommendations and two-way sync",
          "Radio / autoplay that keeps going, and resume-where-you-left-off across launches",
          "Onboarding flow, and a Liquid Glass fallback for Macs below macOS 26",
          "Display settings for non-notch Macs",
        ],
      },
    ],
  },
];
