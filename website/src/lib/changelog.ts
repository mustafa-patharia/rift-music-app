// Single source of truth for the changelog. Mirrored in /CHANGELOG.md.
export interface ChangeSection { label: "Added" | "Changed" | "Fixed" | "Coming"; items: string[]; }
export interface Release { version: string; date?: string; current?: boolean; sections: ChangeSection[]; }

export const CHANGELOG: Release[] = [
  {
    version: "Unreleased",
    sections: [
      { label: "Coming", items: ["More interesting things to come."] },
    ],
  },
  {
    version: "0.0.2",
    date: "2026-08-15",
    current: true,
    sections: [
      {
        label: "Added",
        items: [
          "Gapless crossfade for smooth transitions between songs.",
          "Multilingual lyrics AI support.",
          "Non-notch display settings for older Macs.",
          "Onboarding flow and Liquid Glass fallback.",
          "Website deployment moved to Vercel; added Terms, Privacy, and Chai support link."
        ],
      },
      {
        label: "Changed",
        items: [
          "Settings redesign for a cleaner, more intuitive interface.",
          "Gated top-artists on play count.",
          "Dropped redundant nav titles."
        ],
      },
      {
        label: "Fixed",
        items: [
          "Fixed a window sizing race condition.",
          "Fixed duration and scrollbar issues.",
          "OAuth cleanup and icon fixes."
        ]
      }
    ]
  },
  {
    version: "0.1.0",
    date: "2026-07-27",
    sections: [
      {
        label: "Added",
        items: [
          "Zero setup — the playback engine ships inside the app: no Homebrew, no Python, no admin password, nothing to download on first launch",
          "Native browse — search, artists, albums, charts and playlists in SwiftUI",
          "Dynamic Island in the notch, plus a menu-bar player",
          "Offline downloads with instant-replay stream caching",
          "Synced lyrics with optional on-device AI (Apple Intelligence / Ollama) for transliteration & translation",
          "Listening stats — top songs, top artists, clocks by hour and weekday, stored locally only",
          "YouTube Music sign-in — your playlists, likes, recommendations and two-way sync",
          "Radio / autoplay that keeps going, and resume-where-you-left-off across launches",
        ],
      },
    ],
  },
];
