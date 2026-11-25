// All page sections (server components → real HTML, no-JS safe).
import { Apple, Download, Lock } from "./icons";
import { StarButton } from "./Chrome";
import Showcase from "./Showcase";
import Turntable from "./Turntable";
import NotchDemo from "./NotchDemo";
import { RELEASE, REL_VERSION } from "@/lib/config";

/* 01: HERO */
export function Hero() {
  return (
    <header className="hero" id="top">
      <div className="hero-copy">
      <h1 className="reveal">YouTube Music,<br /> made for the Mac.</h1>
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
        <article className="cell span12 privacy-cell reveal" id="privacy">
          <Lock className="lock" />
          <div>
            <h3>Private by default</h3>
            <p>History, stats, likes and playlists stay on your Mac. Credentials live only in the macOS Keychain, and listening rooms are end-to-end encrypted.</p>
            <ul className="privacy-points">
              <li>No telemetry</li><li>No analytics</li><li>Keychain-only credentials</li><li>Encrypted rooms</li>
            </ul>
          </div>
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

/* 08b: COMPARE. Feature matrix. Others are marked only from what their own
   README/site states ("—" = not listed there), never guessed. */
type Mark = "yes" | "plugin" | "no";
const COLS = ["Rift", "Kaset", "Tubemac", "YTM Desktop", "Pear Desktop"];
const ROWS: { f: string; d: string; m: Mark[] }[] = [
  { f: "Dynamic Island", d: "In the notch, or drawn on Macs without one", m: ["yes", "no", "no", "no", "no"] },
  { f: "Listen together", d: "End-to-end encrypted rooms, no account", m: ["yes", "no", "no", "no", "plugin"] },
  { f: "Offline downloads", d: "Keep songs on your Mac", m: ["yes", "no", "no", "no", "plugin"] },
  { f: "Desktop widget", d: "Now Playing with controls on the desktop", m: ["yes", "no", "no", "no", "no"] },
  { f: "Synced lyrics", d: "Line-by-line, in time with the song", m: ["yes", "yes", "no", "no", "plugin"] },
  { f: "AI sing-along lyrics", d: "Same words, rewritten in a script you can read", m: ["yes", "no", "no", "no", "no"] },
  { f: "Listening stats", d: "Top songs, artists and hours, kept on your Mac", m: ["yes", "no", "no", "no", "no"] },
  { f: "Play without signing in", d: "Anonymous mode, browse and play", m: ["yes", "no", "no", "no", "no"] },
];

function MarkCell({ m }: { m: Mark }) {
  if (m === "yes")
    return (
      <td className="mk yes">
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" /></svg>
        <span className="sr-only">Yes</span>
      </td>
    );
  if (m === "plugin") return <td className="mk plugin">Plugin</td>;
  return <td className="mk no"><span aria-hidden>—</span><span className="sr-only">Not listed</span></td>;
}

export function Compare() {
  return (
    <section className="rail chorus compare" id="compare">
      <p className="eyebrow reveal">Compare</p>
      <h2 className="serif reveal">More in the box than any other Mac client.</h2>
      <p className="lede reveal">
        Google doesn&rsquo;t make a YouTube Music app for macOS. Here&rsquo;s what the open-source options
        give you, feature by feature. With Rift, it&rsquo;s all built in: nothing to add on.
      </p>
      <div className="compare-wrap reveal">
        <table className="compare-table">
          <caption className="sr-only">Features of YouTube Music apps for Mac</caption>
          <thead>
            <tr>
              <th scope="col">Feature</th>
              {COLS.map((c, i) => <th scope="col" key={c} className={i === 0 ? "is-self" : undefined}>{c}</th>)}
            </tr>
          </thead>
          <tbody>
            {ROWS.map((r) => (
              <tr key={r.f}>
                <th scope="row"><b>{r.f}</b><span>{r.d}</span></th>
                {r.m.map((m, i) => <MarkCell key={COLS[i]} m={m} />)}
              </tr>
            ))}
            <tr className="row-meta">
              <th scope="row"><b>Runs on</b><span>Minimum macOS</span></th>
              <td className="mk yes-text">14 Sonoma</td><td className="mk">15.4</td><td className="mk">14 Sonoma</td><td className="mk">—</td><td className="mk">—</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p className="compare-note reveal">
        &ldquo;Plugin&rdquo; means an add-on you install and set up. &ldquo;—&rdquo; means the feature isn&rsquo;t
        listed on that project&rsquo;s own README or website (checked November 2026).
      </p>
      <div className="key-row reveal" style={{ marginTop: 32 }}>
        <a className="cta" data-release-link href={RELEASE}><Download /> Get Rift free</a>
      </div>
    </section>
  );
}

/* 08c: FAQ (native <details>, mirrored in FAQPage structured data) */
const FAQ = [
  { q: "Is there a YouTube Music app for Mac?",
    a: "Google doesn't offer a native YouTube Music app for macOS, only the website. Rift Music App is an independent, free and open-source native Mac app for YouTube Music." },
  { q: "Is Rift Music App free?",
    a: "Yes. It's free and open source under the GPL-3.0 license, with no ads and no in-app purchases." },
  { q: "Do I need a Google account?",
    a: "No. Anonymous mode lets you search and play without signing in. Sign in with Google to bring your playlists, likes and recommendations, with two-way sync." },
  { q: "Which macOS version do I need?",
    a: "macOS 14 Sonoma or later." },
  { q: "Does the Dynamic Island work on Macs without a notch?",
    a: "Yes. It lives in the notch when your Mac has one. On other Macs, Rift draws a slim island at the top of the screen." },
  { q: "Can I listen offline?",
    a: "Yes. Download songs to keep them on your Mac, and recently played streams are cached for instant replay." },
  { q: "Does Rift collect my data?",
    a: "No. There's no telemetry or analytics. History and stats are stored on your Mac, and credentials live only in the macOS Keychain." },
  { q: "Is Rift affiliated with Google or YouTube?",
    a: "No. Rift Music App is an independent open-source project and is not affiliated with, endorsed by, or connected to Google LLC or YouTube." },
];

const faqLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: FAQ.map(({ q, a }) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })),
};

export function Faq() {
  return (
    <section className="rail chorus faq" id="faq">
      <p className="eyebrow reveal">FAQ</p>
      <h2 className="serif reveal">Questions, answered.</h2>
      <div className="faq-list reveal">
        {FAQ.map(({ q, a }) => (
          <details key={q}>
            <summary>{q}</summary>
            <p>{a}</p>
          </details>
        ))}
      </div>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(faqLd) }} />
    </section>
  );
}

/* 10: DOWNLOAD (the one ending: get it, or star it) */
export function Install() {
  return (
    <section className="rail chorus" id="download">
      <div className="install-card reveal">
        <h2 className="serif" style={{ maxWidth: "18ch", marginInline: "auto" }}>Get Rift. It&rsquo;s free.</h2>
        <p className="lede" style={{ marginInline: "auto" }}>Open source, no ads, no account needed. Version 1.1 adds listening rooms, a desktop widget and an island on every Mac.</p>
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
