# Changelog

All notable changes to **Rift** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[SemVer](https://semver.org/). This file mirrors the on-site changelog at
`/changelog`.

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

[1.0.1]: https://github.com/MustafaPatharia/rift-music-app/releases/tag/v1.0.1
[1.0.0]: https://github.com/MustafaPatharia/rift-music-app/releases/tag/v1.0.0
