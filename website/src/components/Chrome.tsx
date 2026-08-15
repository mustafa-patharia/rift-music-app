// Server components: pill nav, top scrubber, footer. No-JS safe.
// Interactive bits (theme/ambient toggle) are wired by <Enhancements/> via id/class.
import Link from "next/link";
import Image from "next/image";
import { asset } from "@/lib/asset";
import { Bolt, Github, Download, SunMoon, Speaker, Star, Coffee } from "./icons";
import { REPO, RELEASE, REL_VERSION } from "@/lib/config";

export function Nav() {
  return (
    <nav className="pillnav" aria-label="Main">
      <Link className="pn-logo" href="/" aria-label="Rift Music App home">
        <Image src={asset("/brand/rift-128.png")} alt="Rift Music App logo" width={18} height={18} className="pn-bolt" /> Rift Music App
      </Link>
      <div className="pn-links">
        <Link href="/#features">Features</Link>
        <Link href="/#privacy">Privacy</Link>
        <Link href="/#more">More</Link>
        <Link href="/changelog">Changelog</Link>
      </div>
      <div className="pn-right">
        <button className="pn-icon" id="theme-toggle" type="button" aria-label="Switch color theme" title="Switch theme">
          <SunMoon />
        </button>
        <div className="chai-wrap">
          <button className="pn-cta pn-cta-chai" type="button" aria-label="Buy me a chai" aria-haspopup="true">
            <Coffee /> <span className="chai-text">Support</span>
          </button>
          <div className="chai-popover">
            <Image src={asset("/img/qr-chai.png")} alt="Buy me a chai QR Code" width={160} height={160} className="chai-qr" style={{ width: 'auto', height: 'auto' }} />
            <a href="https://buymeachai.in/mustafapatharia" target="_blank" rel="noreferrer" className="chai-btn">
              <Coffee /> Buy me a chai
            </a>
          </div>
        </div>
        <a className="pn-cta" data-release-link href={RELEASE}>
          <Download /> Download
        </a>
      </div>
    </nav>
  );
}

// Deterministic-ish waveform bars so base + fill line up.
function bars() {
  const n = 120, w = 1080, h = 16, gap = w / n, bw = gap * 0.55;
  const out = [];
  for (let i = 0; i < n; i++) {
    const env = 0.32 + 0.42 * Math.abs(Math.sin(i * 0.14)) + 0.22 * Math.abs(Math.sin(i * 0.37));
    const bh = Math.max(2, env * h);
    out.push(
      <rect key={i} x={(i * gap).toFixed(2)} y={((h - bh) / 2).toFixed(2)} width={bw.toFixed(2)} height={bh.toFixed(2)} rx={(bw / 2).toFixed(2)} />
    );
  }
  return out;
}

export function Scrubber() {
  const b = bars();
  return (
    <div className="scrubber" aria-hidden>
      <div className="scrub-rail" role="progressbar" aria-label="Page progress">
        <svg viewBox="0 0 1080 16" preserveAspectRatio="none">
          <g className="base">{b}</g>
          <g className="fill">{b}</g>
        </svg>
        <span className="playhead" />
      </div>
    </div>
  );
}

export function Footer() {
  return (
    <footer className="footer">
      <div className="brand"><Image src={asset("/brand/rift-128.png")} alt="Rift Music App logo" width={18} height={18} /> Rift Music App</div>
      <p className="pos">A native macOS YouTube Music client for your whole library.</p>
      <div className="footer-links">
        <Link href="/changelog">Changelog</Link>
        <a href={REPO} target="_blank" rel="noreferrer">GitHub</a>
        <a href={`${REPO}/releases`} target="_blank" rel="noreferrer">Releases</a>
        <a href={`${REPO}/blob/main/LICENSE`} target="_blank" rel="noreferrer">License</a>
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
        <a href="https://mustafapatharia.vercel.app" target="_blank" rel="noreferrer">Meet the Developer</a>
      </div>
      <p className="release-meta">GPL-3.0 — free as in freedom · <span className="release-version">{REL_VERSION}</span></p>
      <p className="disclaimer">
        Rift Music App is an independent open-source project — not affiliated with, endorsed by, or connected to
        Google LLC, YouTube, or any music service it connects to. All trademarks belong to their owners.
        No ads, no resale, no bundled credentials; downloading content may conflict with a service&rsquo;s
        terms — use responsibly where permitted.
      </p>
    </footer>
  );
}

export function StarButton() {
  return (
    <a className="star" href={REPO} target="_blank" rel="noreferrer">
      <Star /> Star on GitHub
    </a>
  );
}
