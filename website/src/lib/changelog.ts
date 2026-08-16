// Single source of truth for the changelog. Mirrored in /CHANGELOG.md.
export interface ChangeSection { label: "Added" | "Changed" | "Fixed" | "Coming"; items: string[]; }
export interface Release {
  version: string;
  date?: string;
  current?: boolean;
  headline?: string;
  blurb?: string;
  sections: ChangeSection[];
}

export const CHANGELOG: Release[] = [
  {
    version: "1.0.0",
    date: "2026-08-16",
    current: true,
    headline: "Rift 1.0 — the YouTube Music app the Mac never had.",
    blurb:
      "For years the answer to “how do I play YouTube Music on my Mac?” was a browser tab. Rift 1.0 is the other answer: a real Mac app, with your whole library, a player that lives in your notch, and not one line of telemetry. Drag it to Applications and sign in — or don’t. It works either way.",
    sections: [
      {
        label: "Added",
        items: [
          "Nothing to install but the app — the playback engine ships inside it. No Homebrew, no Python, no admin password. Music starts in about half a second on a Mac that has never seen a developer tool.",
          "Your notch, put to work — album art and an equalizer at a glance, a full transport on hover. The Dynamic Island the Mac was missing.",
          "Your whole YouTube Music world, natively — playlists, likes, recommendations and two-way sync, in SwiftUI instead of a web view. Or stay signed out entirely: anonymous browsing and playback just work.",
          "Search, artists, albums, charts, moods and radio — all native, all fast.",
          "Downloads that stay downloaded, plus stream caching that makes a replay instant.",
          "Lyrics that keep time, and an optional on-device AI (Apple Intelligence or Ollama) that transliterates and translates them — nothing leaves your Mac.",
          "Gapless crossfade between tracks.",
          "Your listening, charted — top songs, top artists, clocks by hour and weekday. Computed locally, stored locally, shown to nobody.",
          "Radio and autoplay that keep going, and a queue that survives quitting the app.",
          "Liquid Glass on macOS 26 Tahoe, a material-blur fallback on Sonoma and Sequoia, and display settings for Macs without a notch. One app, no second-class Macs.",
          "A first-run onboarding flow that takes about fifteen seconds.",
        ],
      },
    ],
  },
];
