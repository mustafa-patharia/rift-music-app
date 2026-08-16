# Changelog

All notable changes to **Rift** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[SemVer](https://semver.org/). This file mirrors the on-site changelog at
`/changelog`.

## [Unreleased]

### Coming
- More interesting things to come.

## [0.0.2] — 2026-08-15

### Added
- **Gapless crossfade** for smooth transitions between songs.
- **Multilingual lyrics AI** support.
- **Non-notch display settings** for older Macs.
- **Onboarding flow** and Liquid Glass fallback.
- Website deployment moved to Vercel; added Terms, Privacy, and Chai support link.

### Changed
- Settings redesign for a cleaner, more intuitive interface.
- Gated top-artists on play count.
- Dropped redundant nav titles.

### Fixed
- Fixed a window sizing race condition.
- Fixed duration and scrollbar issues.
- OAuth cleanup and icon fixes.

## [0.1.0] — 2026-07-27

First public release. 🎉

### Added
- **Zero setup** — the playback engine ships inside the app. No Homebrew, no
  Python, no admin password, nothing to download on first launch; songs start
  in about half a second on a Mac that has never had developer tools.
- **Native browse** — search, artists, albums, charts and playlists in SwiftUI.
- **Dynamic Island** in the notch, plus a **menu-bar player**.
- **Offline downloads** with instant-replay stream caching (via `yt-dlp`).
- **Synced lyrics** with optional **on-device AI** (Apple Intelligence / Ollama)
  for transliteration & translation — nothing leaves your Mac.
- **Listening stats** — top songs, top artists, clocks by hour and weekday,
  stored **locally only**.
- **YouTube Music** sign-in — your playlists, likes, recommendations and
  two-way sync.
- **Radio / autoplay** that keeps going, and **resume-where-you-left-off**
  across launches. Anonymous mode with no account.

[Unreleased]: https://github.com/MustafaPatharia/rift-music-app/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MustafaPatharia/rift-music-app/releases/tag/v0.1.0
