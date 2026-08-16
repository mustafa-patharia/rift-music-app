// All page sections (server components → real HTML, no-JS safe).
import Image from "next/image";
import { asset } from "@/lib/asset";
import { Apple, Braces, Download, Lock, Star } from "./icons";
import { StarButton } from "./Chrome";
import ScrollDeck from "./ScrollDeck";
import { REPO, RELEASE, REL_VERSION } from "@/lib/config";

const DIM: Record<string, [number, number]> = {
  home_screen: [1080, 787],
  full_screen_player_screen: [1084, 761],
  player_with_lyrics_screen: [1080, 761],
  artist_screen: [1085, 790],
  search_screen: [1080, 786],
  library_screen: [1080, 786],
  top_notch: [394, 208],
};
function Shot({ name, alt, priority }: { name: keyof typeof DIM | string; alt: string; priority?: boolean }) {
  const [w, h] = DIM[name] ?? [1080, 760];
  return (
    <Image src={asset(`/img/shots/${name}.png`)} alt={alt} width={w} height={h} priority={priority}
      sizes="(max-width: 900px) 96vw, 880px" />
  );
}

// The screenshots already include the macOS window chrome (traffic lights + title),
// so we only add rounded corners + shadow — no extra title bar.
function RiftWindow({ children }: { children: React.ReactNode }) {
  return <figure className="rift-window">{children}</figure>;
}

// Dense scrolling waveform. Deterministic heights (no Math.random → no hydration
// mismatch). Bars rendered twice for a seamless translateX(-50%) loop.
function WaveStrip({ bars = 46 }: { bars?: number }) {
  const set = Array.from({ length: bars }, (_, i) => {
    // Deterministic pseudo-randomness to avoid hydration mismatch
    const seed = Math.sin(i * 9999) * 10000;
    const random = seed - Math.floor(seed);
    const h = 16 + Math.round(84 * random);
    return { h: Math.min(100, h), hot: true };
  });
  const row = (k: string) =>
    set.map((b, i) => <i key={`${k}-${i}`} className={b.hot ? "hot" : ""} style={{ height: `${b.h}%` }} />);
  return (
    <div className="wave" aria-hidden>
      <div className="wave-row">{row("a")}{row("b")}</div>
    </div>
  );
}

/* 01 — HERO */
export function Hero() {
  return (
    <header className="hero" id="top">
      <a className="eyebrow-chip reveal" href="#features"><span className="dot" /> v0.0.2 is active</a>
      <h1 className="reveal">A player for <span className="accent-word">all</span><br /> your music.</h1>
      <p className="hero-sub reveal">
        A native Mac YouTube Music client in SwiftUI — a Dynamic Island for your music,
        offline downloads, and on-device lyrics. Your entire library in one window.
      </p>
      <div className="key-row reveal">
        <a className="keycap" data-release-link href={RELEASE}><Apple /> Download for macOS</a>
        <a className="keycap ghost" href={REPO} target="_blank" rel="noreferrer"><Braces /> Build from source</a>
      </div>
      <p className="install-caption reveal">open source · GPL-3.0 · built in SwiftUI</p>

      <div className="hero-artwork">
        <RiftWindow>
          <Shot name="full_screen_player_screen" alt="Rift Music App full-screen player playing Tujh Mein Rab Dikhta Hai" priority />
        </RiftWindow>
      </div>

      <a className="ph-badge" href={REPO} target="_blank" rel="noreferrer" aria-label="Open source on GitHub">
        <Star />
        <span><b>Open source</b><em>★ Star on GitHub</em></span>
      </a>
    </header>
  );
}

/* 02 — PROOF BAND */
export function ProofBand() {
  return (
    <section className="rail" aria-label="What's inside">
      <div className="proof reveal">
        <p><strong>Everything built in.</strong> <span className="muted">No extensions. No cloud. No account required.</span></p>
        <div className="proof-list">
          <span>Native SwiftUI</span><span>Notch island</span><span>Offline downloads</span>
          <span>On-device lyrics</span><span>Local-only stats</span>
        </div>
      </div>
    </section>
  );
}

/* 03 — STATEMENT */
export function Statement() {
  return (
    <section className="rail verse statement" id="product">
      <p className="eyebrow reveal">The idea</p>
      <h2 className="serif reveal">All your music. <span>One player.</span></h2>
      <p className="lede reveal" data-lightup>
        Sign in with your Google account and your whole YouTube Music world — playlists, likes,
        recommendations — flows straight into a native Mac app. One library, one queue, one beautiful player.
      </p>
    </section>
  );
}

/* 04 — PRODUCT SHOT (scroll-pinned swap deck) */
export function ProductShot() {
  return <ScrollDeck />;
}

/* 05 — FEATURES */
export function Features() {
  return (
    <section className="rail chorus features" id="features">
      <p className="eyebrow reveal">Built like it belongs</p>
      <h2 className="reveal">Everything a player should be.</h2>
      <div className="grid stagger">
        <article className="cell span7 reveal">
          <div className="motif vu" aria-hidden><span className="vu-needle" /></div>
          <h3>Native, end to end</h3>
          <p>SwiftUI throughout — real materials, real vibrancy, native menus and media keys. Liquid Glass on macOS 26 Tahoe. Built for the Mac, head to toe.</p>
        </article>
        <article className="cell span5 reveal">
          <div className="motif eq" aria-hidden><i /><i /><i /><i /><i /></div>
          <h3>A living notch</h3>
          <p>Album art and an equalizer peek beside the camera while music plays. Hover, and the island blooms into a full transport.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif cass" aria-hidden><span className="reel" /><span className="reel" /></div>
          <h3>Offline, properly</h3>
          <p>Download songs and keep them. Streams cache for instant replay. Your library doesn&rsquo;t vanish with your Wi-Fi.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif lyric-lines" aria-hidden><span /><span /><span /><span /></div>
          <h3>Lyrics, translated on-device</h3>
          <p>Built-in synced lyrics — and optional local AI (Apple Intelligence or Ollama) that transliterates and translates them. Nothing leaves your Mac.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif chart-mini" aria-hidden><i style={{ height: "40%" }} /><i style={{ height: "75%" }} /><i style={{ height: "55%" }} /><i style={{ height: "100%" }} /><i style={{ height: "65%" }} /></div>
          <h3>Your listening, charted</h3>
          <p>Top songs, top artists, listening clocks by hour and weekday — computed and stored on your Mac only.</p>
        </article>
        <article className="cell span6 invert reveal">
          <div className="feat-copy">
          <h3 className="serif">Never stops playing.</h3>
          <p>Queue runs out? Rift Music App keeps going with recommendations seeded by what you actually play — and resumes where you left off across launches.</p>
        </div>
        </article>
        <article className="cell span6 reveal">
          <div className="motif sparkle" aria-hidden>✦</div>
          <h3>On-device AI</h3>
          <p>Understand and translate lyrics with local models. No API key. No account. No data leaving your machine.</p>
        </article>
      </div>
    </section>
  );
}

/* 06 — NOTCH */
export function Notch() {
  return (
    <section className="rail verse" aria-label="The notch">
      <p className="eyebrow accent reveal">The notch</p>
      <h2 className="serif reveal">It lives in the notch.</h2>
      <p className="lede reveal">
        A Dynamic Island beside your camera: album art and a dancing equalizer while you play. Hover, and it
        expands into a full transport — scrub, skip, like, all without leaving what you&rsquo;re doing.
      </p>
      <div className="notch-stage reveal">
        <div className="artboard-img">
          <Shot name="top_notch" alt="Rift Music App Dynamic Island expanded with full transport controls" />
        </div>
      </div>
      <p className="notch-cap reveal">The island lives in the notch when you have one, and tucks away when you don&rsquo;t.</p>
    </section>
  );
}

/* 07 — NATIVE */
export function Native() {
  const wins = [
    "Media keys & Control Center", "Menu-bar player", "Background playback", "System share sheet",
    "Global shortcuts", "Resume across launches", "Near-gapless preloading", "Anonymous mode, no account",
  ];
  return (
    <section className="rail chorus" aria-label="Made for macOS">
      <div className="native">
        <div className="reveal">
          <p className="eyebrow">Made for macOS</p>
          <h2 className="serif">It behaves like a Mac app because it is one.</h2>
        </div>
        <div className="reveal">
          <p className="lede" style={{ marginTop: 0 }}>Swift and SwiftUI throughout, with system integration wherever it counts — Liquid Glass materials on macOS 26 Tahoe.</p>
          <div className="native-list">{wins.map((w) => <span key={w}>{w}</span>)}</div>
        </div>
      </div>
    </section>
  );
}

/* 08 — PRIVACY */
export function Privacy() {
  return (
    <section className="rail verse" id="privacy">
      <Lock className="lock reveal" />
      <h2 className="serif reveal">Your listening stays<br /> on your Mac.</h2>
      <p className="lede reveal" data-lightup>
        History, stats, likes, playlists — stored locally, computed locally. No telemetry, no analytics,
        no cloud middleman. Credentials live in the macOS Keychain and nowhere else.
      </p>
      <div className="chips reveal">
        <span className="chip">No telemetry</span><span className="chip">No analytics</span><span className="chip">Keychain-only credentials</span>
      </div>
    </section>
  );
}

/* 09 — MORE TO COME */
export function MoreToCome() {
  return (
    <section className="rail chorus mtc" id="more">
      <p className="eyebrow reveal">Where this is going</p>
      <h2 className="serif reveal">The YouTube Music client the Mac deserved.</h2>
      <p className="value reveal">
        Your full catalog, your playlists and likes, real recommendations, two-way sync — all in a native
        Mac app that behaves like one.
      </p>
      <div className="reveal"><span className="live-tag"><span className="dot" /> Connected — YouTube Music</span></div>
      <p className="teaser reveal">More interesting things to come.</p>
      <div className="teaser-wave reveal"><WaveStrip /></div>
    </section>
  );
}

/* 10 — INSTALL */
export function Install() {
  return (
    <section className="rail chorus" id="download">
      <div className="install-card reveal">
        <p className="eyebrow accent">Install in a minute</p>
        <h2 className="serif" style={{ maxWidth: "18ch", marginInline: "auto" }}>Download, drag to Applications, done.</h2>
        <p className="lede" style={{ marginInline: "auto" }}>Free and open source, in active development on the way to 1.0 — expect sparks.</p>
        <div className="key-row">
          <a className="keycap" data-release-link href={RELEASE}><Download /> Download for macOS <span className="release-version" style={{ opacity: .7 }}>{REL_VERSION}</span></a>
          <a className="ghost-pill" href={REPO} target="_blank" rel="noreferrer">Build from source <span>→</span></a>
        </div>
        <p className="req">Requires macOS 14 Sonoma+ (Liquid Glass on macOS 26 Tahoe) · Streaming uses yt-dlp under the hood.</p>
      </div>
    </section>
  );
}

/* 11 — SUPPORT */
export function Support() {
  return (
    <section className="rail chorus" aria-label="Open source">
      <div className="support-card reveal">
        <p className="eyebrow accent">Built in the open</p>
        <h2 className="serif">Free. Open source. Built for people who love Mac apps.</h2>
        <StarButton />
        <p className="credits">
          Protocol &amp; design references —{" "}
          <a href="https://github.com/sigma67/ytmusicapi" target="_blank" rel="noreferrer">ytmusicapi</a> ·{" "}
          <a href="https://github.com/OuterTune/OuterTune" target="_blank" rel="noreferrer">OuterTune</a> ·{" "}
          <a href="https://github.com/Ebullioscopic/Atoll" target="_blank" rel="noreferrer">Atoll</a> ·{" "}
          <a href="https://github.com/pear-devs/pear-desktop" target="_blank" rel="noreferrer">pear-desktop</a>.
        </p>
      </div>
    </section>
  );
}
