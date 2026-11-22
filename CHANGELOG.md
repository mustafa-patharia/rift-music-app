# Changelog

All notable changes to **Rift** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[SemVer](https://semver.org/). This file mirrors the on-site changelog at
`/changelog`.

## [1.1.0] — 2026-11-23

### Rift 1.1 — listen together.

### Added

- **Together.** Start a listening room and share its code: friends anywhere
  hear exactly what you play, in sync. Everyone appears as a profile bubble
  pulled onto a spinning record, with emoji reactions and a live activity
  feed. Rooms are end-to-end encrypted and need no account or server.
  **Nearby** finds Macs running Rift on the same Wi-Fi for one-tap send and
  listen-along.
- **Desktop widget.** Small and medium Now Playing widgets with play/pause
  and skip that work right from the desktop.
- **A Dynamic Island on every Mac.** Macs without a notch get a slim island
  at the top of the screen that blooms into the full player on hover.
- **Synced lyrics everywhere.** Timed lyrics from YouTube Music, then LRCLIB;
  the active line glows, the rest fade, and clicking a line seeks to it.
- **Sing along in any script.** Optional AI rewrites lyrics into the script
  you read (12 scripts, same words, still synced).
- **Bring your own AI.** Apple Intelligence on-device, or your own key for
  Gemini, Groq, OpenAI, Anthropic, xAI, DeepSeek, Mistral, Cerebras,
  Together AI, OpenRouter or any OpenAI-compatible API. Keys live in the
  Keychain.
- **Record player.** A Now Playing style with a spinning record and a
  tonearm that drops on while playing.
- **Custom playlist covers** and a new Liked Music cover.
- **Collapsible sidebar** (Ctrl-Cmd-S), remembered across launches.
- **A new welcome tour** — replay it any time from Settings › About.

### Changed

- Ollama support removed in favour of Apple Intelligence and API keys.
- Lyrics translation removed; sing-along transliteration stays.

### Fixed

- Hover zoom on cards no longer clipped.
- Pages no longer squeezed when the queue is open; narrow full player
  stacks lyrics instead of overlapping the artwork.

## [1.0.1] — 2026-08-28

### Fixed

- **Playback failing after a few days idle.** YouTube tightened requirements on
  the player client Rift's streaming engine defaulted to; the engine now checks
  for an update on every launch instead of only after a failed play, and no
  longer pins a client that YouTube (and the engine itself) had already moved
  away from.

### Added

- **Brand account support at sign-in.** If your Google account manages a brand
  channel, a chooser now appears after login so you can sign in as that channel
  instead of your personal account.

## [1.0.0] — 2026-08-16

### Rift 1.0 — the YouTube Music app the Mac never had.

For years the answer to "how do I play YouTube Music on my Mac?" was a browser
tab. Rift 1.0 is the other answer: a real Mac app, with your whole library, a
player that lives in your notch, and not one line of telemetry. Drag it to
Applications and sign in — or don't. It works either way.

### Added

- **Nothing to install but the app.** The playback engine ships inside it — no
  Homebrew, no Python, no admin password. Music starts in about half a second on
  a Mac that has never seen a developer tool.
- **Your notch, put to work.** Album art and an equalizer at a glance, a full
  transport on hover — the Dynamic Island the Mac was missing. Plus a menu-bar
  player.
- **Your whole YouTube Music world, natively.** Playlists, likes,
  recommendations and two-way sync, in SwiftUI instead of a web view. Or stay
  signed out entirely: anonymous browsing and playback just work.
- **Native browse** — search, artists, albums, charts, moods and radio, all fast.
- **Downloads that stay downloaded**, plus stream caching that makes a replay
  instant.
- **Lyrics that keep time**, and an optional on-device AI (Apple Intelligence or
  Ollama) that transliterates and translates them — nothing leaves your Mac.
- **Gapless crossfade** between tracks.
- **Your listening, charted** — top songs, top artists, clocks by hour and
  weekday. Computed locally, stored locally, shown to nobody.
- **Radio and autoplay that keep going**, and a queue that survives quitting the
  app.
- **Runs on every Mac from Sonoma up**, notch or no notch — it adopts whatever
  material the system provides. One app, no second-class Macs.
- **A first-run onboarding flow** that takes about fifteen seconds.

[1.1.0]: https://github.com/MustafaPatharia/rift-music-app/releases/tag/v1.1.0
[1.0.1]: https://github.com/MustafaPatharia/rift-music-app/releases/tag/v1.0.1
[1.0.0]: https://github.com/MustafaPatharia/rift-music-app/releases/tag/v1.0.0
