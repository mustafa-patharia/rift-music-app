<div align="center">

<img src="assets/readme/hero.png" alt="Rift — All your music. One beautiful, Mac-native player." width="100%">

<br><br>

<!-- brand-crimson badges -->
![macOS](https://img.shields.io/badge/macOS-14_Sonoma+-ff2f3a?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift_6-SwiftUI-ff6b4a?style=flat-square&logo=swift&logoColor=white)
![YouTube Music](https://img.shields.io/badge/YouTube_Music-client-ffb347?style=flat-square&logo=youtubemusic&logoColor=white)
![License](https://img.shields.io/badge/License-GPL--3.0-3a3a3a?style=flat-square)
![Status](https://img.shields.io/badge/status-in_development-ff2f3a?style=flat-square)

### A native Mac **YouTube Music** client — a Dynamic Island, Liquid Glass on Tahoe, private by default.

**[⬇ Download](../../releases/latest)** · **[📓 Changelog](CHANGELOG.md)** · **[🌐 Website](website/)** · **[🗺 Roadmap](#-roadmap)** · **[⚖ License](LICENSE)**

</div>

---

## The idea

**Rift is a pure player.** Sign in with your Google account and your whole YouTube
Music world — playlists, likes, recommendations, two-way sync — flows into a native
SwiftUI app with a Dynamic Island in your notch, Liquid Glass on macOS 26 Tahoe, and stats that never
leave your Mac. No cloud, no telemetry, no account required for anonymous mode.

One library. One queue. One beautiful player. And **more interesting things to come.**

---

## 📸 See it

<table>
  <tr>
    <td width="50%" align="center"><b>Home</b><br><sub>Featured playlists · recently played · top artists</sub><br><br><img src="website/public/img/shots/home_screen.png" alt="Rift Home" width="100%"></td>
    <td width="50%" align="center"><b>Now Playing</b><br><sub>Full-window art · live scrubber · transport</sub><br><br><img src="website/public/img/shots/full_screen_player_screen.png" alt="Rift Now Playing" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><b>Lyrics</b><br><sub>Synced · on-device transliteration & translation</sub><br><br><img src="website/public/img/shots/player_with_lyrics_screen.png" alt="Rift Lyrics" width="100%"></td>
    <td width="50%" align="center"><b>Artist</b><br><sub>Bio · monthly listeners · top songs · radio</sub><br><br><img src="website/public/img/shots/artist_screen.png" alt="Rift Artist page" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><b>Search</b><br><sub>Trending charts · recents · top artists</sub><br><br><img src="website/public/img/shots/search_screen.png" alt="Rift Search" width="100%"></td>
    <td width="50%" align="center"><b>Library</b><br><sub>Your playlists · likes · downloads</sub><br><br><img src="website/public/img/shots/library_screen.png" alt="Rift Library" width="100%"></td>
  </tr>
</table>

<div align="center"><sub>The Dynamic Island, expanded — album art, scrubber and transport in the notch.</sub><br><br><img src="website/public/img/shots/top_notch.png" alt="Rift Dynamic Island expanded" width="420"></div>

---

## ✨ What Rift does

| | |
|---|---|
| 🎧 **Full catalog, native UI** | Search, albums, artists, playlists, moods and charts — all SwiftUI. |
| 🌟 **Real recommendations** | Home feed, radio & autoplay, *"More like…"* and *"Because you liked…"* seeded by what you actually play. |
| 🏝 **A living notch** | A Dynamic Island for album art + equalizer; hover to a full transport. |
| ⬇ **Offline, properly** | Download tracks and keep them; streams cache for instant replay. |
| 🎤 **Lyrics + on-device AI** | Synced lyrics; optional local AI (Apple Intelligence / Ollama) transliterates & translates. |
| 📊 **Your listening, charted** | Top songs, top artists, listening clocks — computed and stored **locally only**. |
| 🔒 **Private by default** | No telemetry, no analytics, no cloud middleman. Credentials live in the Keychain. |

---

## 🚀 Get Rift

> **In active development** — expect rough edges while we head to 1.0.

**Download** — grab the latest from **[Releases](../../releases/latest)**, drag to
Applications, done. *Requires macOS 14 Sonoma or later — Liquid Glass kicks in
automatically on macOS 26 Tahoe, older Macs get a material-blur fallback.
Streaming uses `yt-dlp` under the hood.*

**From source:**

```bash
git clone https://github.com/MustafaPatharia/rift-music-app
open rift-music-app/Rift.xcodeproj   # Xcode 26+ · macOS 14 Sonoma+
```

**The website** (marketing / this repo's `website/`) is a static Next.js app:

```bash
cd website && npm install && npm run dev
```

---

## 🧱 Under the hood

<img src="assets/readme/architecture.png" alt="Rift architecture — interface, coordinator, PlaybackSource seam, sources, data & services" width="100%">

> **The core rule:** nothing above `PlaybackSource` knows where audio comes from.
> That seam is what keeps Rift clean and lets it keep getting better.

*[Interactive diagram →](Docs/architecture.html)* (open in a browser)

---

## 🗺 Roadmap

- [x] Native browse — search, artists, albums, charts, moods
- [x] Notch Dynamic Island + menu-bar player
- [x] Likes, playlists, downloads, stats, lyrics + local AI
- [x] YouTube Music sign-in, recommendations, two-way sync
- [ ] Signed & notarized releases, auto-update
- [ ] More interesting things to come

See **[CHANGELOG.md](CHANGELOG.md)** for release history.

---

<div align="center">

<img src="assets/readme/foot.png" alt="License & fine print" width="100%">

</div>

**[GPL-3.0](LICENSE)** — free as in freedom. Attributions in [NOTICE](NOTICE).

Rift is an independent open-source project — **not affiliated with, endorsed by, or
connected to Google LLC, YouTube, or any music service it connects to.** All
trademarks belong to their owners. No ads, no resale, no bundled credentials;
downloading content may conflict with a service's terms — use responsibly where
permitted.

Protocol & design references: [ytmusicapi](https://github.com/sigma67/ytmusicapi) ·
[OuterTune](https://github.com/OuterTune/OuterTune) ·
[Atoll](https://github.com/Ebullioscopic/Atoll) ·
[pear-desktop](https://github.com/pear-devs/pear-desktop)
