// All page sections (server components → real HTML, no-JS safe).
import { Apple, Download, Lock } from "./icons";
import { StarButton } from "./Chrome";
import Showcase from "./Showcase";
import Turntable from "./Turntable";
import NotchDemo from "./NotchDemo";
import { RELEASE, REL_VERSION } from "@/lib/config";

// Dense scrolling waveform. Deterministic heights (no Math.random → no hydration
// mismatch). Bars rendered twice so the translateX(-50%) loop has no seam.
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

/* 01: HERO */
export function Hero() {
  return (
    <header className="hero" id="top">
      <div className="hero-copy">
      <h1 className="reveal">A player for all<br /> your music.</h1>
      <p className="hero-sub reveal">
        A native Mac app for YouTube Music. A Dynamic Island on every Mac, listening rooms
        with friends, lyrics you can sing along to, and downloads for when you&rsquo;re offline.
      </p>
      <div className="key-row reveal">
        <a className="cta" data-release-link href={RELEASE}><Apple /> Download for macOS</a>
      </div>
      <p className="install-caption reveal">Free and open source. Needs macOS 14 Sonoma or later.</p>
      </div>
      <div className="hero-deck reveal"><Turntable /></div>
    </header>
  );
}

/* 02: PROOF BAND */
export function ProofBand() {
  return (
    <section className="rail" aria-label="What's inside">
      <div className="proof reveal">
        <p><strong>Everything built in.</strong> <span className="muted">No extensions, no account required.</span></p>
        <div className="proof-list">
          <span>Dynamic Island</span><span>Listen together</span><span>Desktop widget</span>
          <span>Sing-along lyrics</span><span>Offline downloads</span>
        </div>
      </div>
    </section>
  );
}

/* 03: STATEMENT */
export function Statement() {
  return (
    <section className="rail verse statement" id="product">
      <h2 className="serif reveal">All your music. <span>One player.</span></h2>
      <p className="lede reveal" data-lightup>
        Sign in with Google and your YouTube Music library comes with you: playlists, likes and
        recommendations, in an app that feels like it shipped with your Mac.
      </p>
    </section>
  );
}

/* 04: PRODUCT SHOT (master-detail screen showcase) */
export function ProductShot() {
  return <Showcase />;
}

/* 05: FEATURES. Cells differ in size and in what they show; each visual is the feature itself. */
export function Features() {
  return (
    <section className="rail chorus features" id="features">
      <h2 className="reveal">What it does, and does well.</h2>
      <div className="grid stagger">
        <article className="cell span7 reveal">
          <div className="motif vu" aria-hidden><span className="vu-needle" /></div>
          <h3>Native, end to end</h3>
          <p>SwiftUI throughout, with real materials, native menus and media keys. It follows your system appearance on any macOS from Sonoma on.</p>
        </article>
        <article className="cell span5 reveal">
          <div className="motif eq" aria-hidden><i /><i /><i /><i /><i /></div>
          <h3>A living notch</h3>
          <p>Album art and an equalizer sit beside the camera while music plays. Hover, and the island opens into full controls. No notch? Rift draws one.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif cass" aria-hidden><span className="reel" /><span className="reel" /></div>
          <h3>Offline, properly</h3>
          <p>Download songs and keep them. Streams are cached for instant replay, so your library still works without Wi-Fi.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif lyric-lines" aria-hidden><span /><span /><span /><span /></div>
          <h3>Sing along in any script</h3>
          <p>Synced lyrics that keep time. Optional AI rewrites them in a script you can read, same words, so you can sing along.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif chart-mini" aria-hidden><i style={{ height: "40%" }} /><i style={{ height: "75%" }} /><i style={{ height: "55%" }} /><i style={{ height: "100%" }} /><i style={{ height: "65%" }} /></div>
          <h3>Your listening, charted</h3>
          <p>Top songs, top artists, and when you listen by hour and weekday. Worked out and stored on your Mac only.</p>
        </article>
        <article className="cell span5 reveal">
          <ol className="queue-mini" aria-label="Example up-next queue">
            <li><b>Alag Aasmaan</b><span>Anuv Jain</span></li>
            <li><b>Sunflower</b><span>Post Malone, Swae Lee</span></li>
            <li><b>Loser</b><span>Tame Impala</span></li>
          </ol>
          <h3>Never stops playing</h3>
          <p>When the queue runs out, Rift keeps going with recommendations based on what you play, and picks up where you left off next launch.</p>
        </article>
        <article className="cell span4 reveal">
          <div className="motif widget-mini" aria-hidden>
            <span className="wm-art" />
            <span className="wm-text"><b /><i /></span>
            <span className="wm-ctl"><i /><i className="play" /><i /></span>
          </div>
          <h3>On your desktop</h3>
          <p>A Now Playing widget with play, pause and skip, right on the desktop. No window needed.</p>
        </article>
        <article className="cell span3 reveal">
          <ul className="provider-list" aria-label="Supported AI providers">
            <li>Apple Intelligence</li><li>Gemini</li><li>Groq</li><li>OpenAI</li><li>Anthropic</li>
          </ul>
          <h3>AI, your choice</h3>
          <p>On-device, or your own key. Off until you turn it on.</p>
        </article>
      </div>
    </section>
  );
}

/* 06: NOTCH */
export function Notch() {
  return (
    <section className="rail verse" aria-label="The notch">
      <p className="eyebrow reveal">The notch</p>
      <h2 className="serif reveal">A Dynamic Island on every Mac.</h2>
      <p className="lede reveal">
        Album art and a moving equalizer at the top of the screen while you play. Hover, and it opens
        into full controls without leaving what you&rsquo;re doing. Try it below: it plays the record from the top of the page.
      </p>
      <div className="notch-stage reveal"><NotchDemo /></div>
      <p className="notch-cap reveal">It lives in the notch when you have one. On Macs without one, Rift draws a slim island at the top of the screen.</p>
    </section>
  );
}

/* 07: NATIVE */
export function Native() {
  const wins = [
    "Media keys and Control Center", "Menu-bar player", "Background playback", "System share sheet",
    "Global shortcuts", "Resume across launches", "Near-gapless preloading", "Anonymous mode, no account",
    "Desktop widget", "Nearby Macs over Wi-Fi and Bluetooth",
  ];
  return (
    <section className="rail chorus" aria-label="Made for macOS">
      <div className="native">
        <div className="reveal">
          <p className="eyebrow">Made for macOS</p>
          <h2 className="serif">It behaves like a Mac app because it is one.</h2>
        </div>
        <div className="reveal">
          <p className="lede" style={{ marginTop: 0 }}>Swift and SwiftUI throughout, wired into the system wherever it counts.</p>
          <div className="native-list">{wins.map((w) => <span key={w}>{w}</span>)}</div>
        </div>
      </div>
    </section>
  );
}

/* 08: PRIVACY */
export function Privacy() {
  return (
    <section className="rail verse" id="privacy">
      <Lock className="lock reveal" />
      <h2 className="serif reveal">Your listening stays<br /> on your Mac.</h2>
      <p className="lede reveal" data-lightup>
        History, stats, likes and playlists are stored and worked out locally. No telemetry, no analytics.
        Credentials live in the macOS Keychain and nowhere else. Listening rooms are end-to-end encrypted,
        so the relays in between only ever see ciphertext.
      </p>
      <ul className="privacy-points reveal">
        <li>No telemetry</li><li>No analytics</li><li>Keychain-only credentials</li><li>Encrypted rooms</li>
      </ul>
    </section>
  );
}

/* 09: WHERE IT'S GOING */
export function MoreToCome() {
  return (
    <section className="rail chorus mtc" id="more">
      <p className="eyebrow reveal">Where this is going</p>
      <h2 className="serif reveal">The YouTube Music app the Mac deserved.</h2>
      <p className="value reveal">
        Your full catalog, your playlists and likes, real recommendations and two-way sync, in a Mac app
        that behaves like one. More is on the way.
      </p>
      <div className="teaser-wave reveal"><WaveStrip /></div>
    </section>
  );
}

/* 10: DOWNLOAD (the one ending: get it, or star it) */
export function Install() {
  return (
    <section className="rail chorus" id="download">
      <div className="install-card reveal">
        <h2 className="serif" style={{ maxWidth: "18ch", marginInline: "auto" }}>Download, drag to Applications, done.</h2>
        <p className="lede" style={{ marginInline: "auto" }}>Free and open source. Version 1.1 adds listening rooms, a desktop widget and an island on every Mac.</p>
        <div className="key-row">
          <a className="cta" data-release-link href={RELEASE}><Download /> Download for macOS <span className="release-version">{REL_VERSION}</span></a>
          <StarButton />
        </div>
        <p className="req">Needs macOS 14 Sonoma or later.</p>
        <p className="credits">
          Built in the open, with thanks to{" "}
          <a href="https://github.com/sigma67/ytmusicapi" target="_blank" rel="noreferrer">ytmusicapi</a>,{" "}
          <a href="https://github.com/OuterTune/OuterTune" target="_blank" rel="noreferrer">OuterTune</a>,{" "}
          <a href="https://github.com/Ebullioscopic/Atoll" target="_blank" rel="noreferrer">Atoll</a> and{" "}
          <a href="https://github.com/pear-devs/pear-desktop" target="_blank" rel="noreferrer">pear-desktop</a>.
        </p>
      </div>
    </section>
  );
}
