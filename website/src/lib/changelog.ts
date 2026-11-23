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
    version: "1.1.0",
    date: "2026-11-23",
    current: true,
    headline: "Rift 1.1: listen together.",
    blurb:
      "Music is better with people. Rift 1.1 lets you start a room, share a code, and have friends anywhere hear exactly what you play, in sync, end-to-end encrypted, no account or server. Plus a desktop widget, a Dynamic Island on every Mac, and lyrics you can sing in any script.",
    sections: [
      {
        label: "Added",
        items: [
          "Together: start a listening room and share its code; friends anywhere hear what you play, in sync. Everyone floats as a profile bubble pulled onto a spinning record, with emoji reactions and a live activity feed. Nearby finds Macs running Rift on the same Wi-Fi.",
          "Desktop widget: small and medium Now Playing widgets with play/pause and skip.",
          "A Dynamic Island on every Mac: no notch? Rift draws a slim island at the top of the screen that blooms into the full player on hover.",
          "Synced lyrics: timed lyrics from YouTube Music, then LRCLIB; the active line glows and clicking a line seeks to it.",
          "Sing along in any script: optional AI rewrites lyrics into the script you read, same words, still synced.",
          "Bring your own AI: Apple Intelligence on-device, or your own key for Gemini, Groq, OpenAI, Anthropic, xAI, DeepSeek, Mistral, Cerebras, Together AI, OpenRouter or any OpenAI-compatible API.",
          "Record player Now Playing style, custom playlist covers, a collapsible sidebar and a new welcome tour.",
        ],
      },
      {
        label: "Changed",
        items: [
          "Ollama removed in favour of Apple Intelligence and API keys; lyrics translation removed, sing-along stays.",
        ],
      },
      {
        label: "Fixed",
        items: [
          "Card hover zoom no longer clipped; pages no longer squeezed when the queue is open.",
        ],
      },
    ],
  },
  {
    version: "1.0.1",
    date: "2026-08-28",
    current: false,
    sections: [
      {
        label: "Fixed",
        items: [
          "Playback failing after a few days idle: YouTube tightened requirements on the player client Rift's streaming engine defaulted to. The engine now checks for an update on every launch instead of only after a failed play, and no longer pins a client that YouTube (and the engine itself) had already moved away from.",
        ],
      },
      {
        label: "Added",
        items: [
          "Brand account support at sign-in: if your Google account manages a brand channel, a chooser now appears after login so you can sign in as that channel instead of your personal account.",
        ],
      },
    ],
  },
  {
    version: "1.0.0",
    date: "2026-08-16",
    current: false,
    headline: "Rift 1.0: the YouTube Music app the Mac never had.",
    blurb:
      "For years the answer to “how do I play YouTube Music on my Mac?” was a browser tab. Rift 1.0 is the other answer: a real Mac app, with your whole library, a player that lives in your notch, and not one line of telemetry. Drag it to Applications and sign in, or don’t. It works either way.",
    sections: [
      {
        label: "Added",
        items: [
          "Nothing to install but the app: the playback engine ships inside it. No Homebrew, no Python, no admin password. Music starts in about half a second on a Mac that has never seen a developer tool.",
          "Your notch, put to work: album art and an equalizer at a glance, a full transport on hover. The Dynamic Island the Mac was missing.",
          "Your whole YouTube Music world, natively: playlists, likes, recommendations and two-way sync, in SwiftUI instead of a web view. Or stay signed out entirely: anonymous browsing and playback just work.",
          "Search, artists, albums, charts, moods and radio: all native, all fast.",
          "Downloads that stay downloaded, plus stream caching that makes a replay instant.",
          "Lyrics that keep time, and an optional on-device AI (Apple Intelligence or Ollama) that transliterates and translates them, nothing leaves your Mac.",
          "Gapless crossfade between tracks.",
          "Your listening, charted: top songs, top artists, clocks by hour and weekday. Computed locally, stored locally, shown to nobody.",
          "Radio and autoplay that keep going, and a queue that survives quitting the app.",
          "Runs on every Mac from Sonoma up, notch or no notch: it adopts whatever material the system provides. One app, no second-class Macs.",
          "A first-run onboarding flow that takes about fifteen seconds.",
        ],
      },
    ],
  },
];
