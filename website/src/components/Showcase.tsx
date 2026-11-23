"use client";
// Showcase: "Inside Rift". A list of screens beside one large screenshot
// (master-detail); on phones the list becomes a row of tabs above it. No
// scroll pinning, so the page scrolls normally and nothing can stack.
// Advances on its own every few seconds (with a progress line on the active
// screen), pauses on hover/focus, off screen, when motion is paused, and
// never auto-advances under Reduce Motion. Arrow keys move between tabs.
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { asset } from "@/lib/asset";

type Shot = { file: string; w: number; h: number; tab: string; title: string; sub: string };

// Captured from the app's DEBUG showcase mode (-RiftShowcase): frozen on one
// track, no account shown. 2x captures, 1600 px wide.
const SHOTS: Shot[] = [
  { file: "v11_home.png", w: 1600, h: 1019, tab: "Home", title: "Your music, the moment you open it.", sub: "Liked Music up top, then what you played recently and your top artists." },
  { file: "v11_nowPlaying.png", w: 1600, h: 1019, tab: "Now Playing", title: "A record player for every song.", sub: "The cover becomes the label of a spinning record. Or keep the classic full-window artwork." },
  { file: "v11_queue.png", w: 1600, h: 1019, tab: "Up Next", title: "See what's coming.", sub: "The queue slides in beside the player, with the current song up top." },
  { file: "v11_artist.png", w: 1600, h: 1019, tab: "Artist", title: "Every artist, in depth.", sub: "Bio, monthly audience, top songs, albums and one-tap radio." },
];
const DWELL = 6000;

export default function Showcase() {
  const [i, setI] = useState(0);
  const [paused, setPaused] = useState(false);
  const [visible, setVisible] = useState(false);
  const [cycle, setCycle] = useState(0);          // restarts the progress line
  const root = useRef<HTMLElement>(null);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);

  useEffect(() => {
    const io = new IntersectionObserver(([e]) => setVisible(e.isIntersecting), { threshold: 0.35 });
    if (root.current) io.observe(root.current);
    return () => io.disconnect();
  }, []);

  const auto = visible && !paused;
  useEffect(() => {
    if (!auto || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const t = window.setTimeout(() => {
      if (document.documentElement.classList.contains("still")) { setCycle((c) => c + 1); return; }
      setI((x) => (x + 1) % SHOTS.length); setCycle((c) => c + 1);
    }, DWELL);
    return () => clearTimeout(t);
  }, [auto, i, cycle]);

  const pick = (n: number) => { setI(n); setCycle((c) => c + 1); };
  const onKey = (e: React.KeyboardEvent) => {
    const d = e.key === "ArrowDown" || e.key === "ArrowRight" ? 1 : e.key === "ArrowUp" || e.key === "ArrowLeft" ? -1 : 0;
    if (!d) return;
    e.preventDefault();
    const n = (i + d + SHOTS.length) % SHOTS.length;
    pick(n); tabs.current[n]?.focus();
  };

  const s = SHOTS[i];
  return (
    <section
      className="rail chorus showcase"
      id="inside"
      ref={root}
      aria-label="Inside Rift"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocus={() => setPaused(true)}
      onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node)) setPaused(false); }}
    >
      <div className="sc-head">
        <p className="eyebrow reveal">Inside Rift</p>
        <h2 className="serif reveal">Every screen, made for the Mac.</h2>
      </div>

      <div className="sc-grid">
        <div className="sc-list" role="tablist" aria-label="Screens" aria-orientation="vertical" onKeyDown={onKey}>
          {SHOTS.map((x, n) => (
            <button
              key={x.file}
              ref={(el) => { tabs.current[n] = el; }}
              role="tab"
              id={`sc-tab-${n}`}
              aria-selected={n === i}
              aria-controls="sc-panel"
              tabIndex={n === i ? 0 : -1}
              className={n === i ? "sc-tab on" : "sc-tab"}
              onClick={() => pick(n)}
            >
              <span className="sc-tab-name">{x.tab}</span>
              <span className="sc-tab-title">{x.title}</span>
              <span className="sc-tab-sub">{x.sub}</span>
              {n === i && <span key={cycle} className={auto ? "sc-progress run" : "sc-progress"} aria-hidden />}
            </button>
          ))}
        </div>

        <figure className="sc-frame" id="sc-panel" role="tabpanel" aria-labelledby={`sc-tab-${i}`} style={{ aspectRatio: `${s.w} / ${s.h}` }}>
          {SHOTS.map((x, n) => (
            <Image
              key={x.file}
              src={asset(`/img/shots/${x.file}`)}
              alt={`Rift Music App, ${x.tab} screen`}
              width={x.w}
              height={x.h}
              sizes="(max-width: 900px) 94vw, 760px"
              priority={n === 0}
              className={n === i ? "on" : ""}
              aria-hidden={n !== i}
            />
          ))}
        </figure>
        <p className="sc-caption" aria-live="polite"><b>{s.title}</b> {s.sub}</p>
      </div>
    </section>
  );
}
