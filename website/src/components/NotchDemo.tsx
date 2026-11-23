"use client";
// NotchDemo: Rift's Dynamic Island, coded instead of screenshotted. The top
// of a Mac screen with its notch; the island grows out of the notch with the
// record art and an equalizer, and opens into full controls on hover, focus,
// or by itself when the section scrolls into view. Its play button is real:
// it drives the hero turntable ("rift:toggle"), and it follows the deck's
// state ("rift:play"), so both ends of the page play the same music.
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { asset } from "@/lib/asset";

export default function NotchDemo() {
  const [open, setOpen] = useState(false);
  const [hover, setHover] = useState(false);
  const [playing, setPlaying] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onPlay = (e: Event) => setPlaying((e as CustomEvent<boolean>).detail);
    window.addEventListener("rift:play", onPlay);
    // Peek open once each time the section comes into view.
    let t = 0;
    const io = new IntersectionObserver(([en]) => {
      if (!en.isIntersecting || document.documentElement.classList.contains("still")) return;
      clearTimeout(t);
      t = window.setTimeout(() => {
        setOpen(true);
        t = window.setTimeout(() => setOpen(false), 4200);
      }, 600);
    }, { threshold: 0.6 });
    if (ref.current) io.observe(ref.current);
    return () => { window.removeEventListener("rift:play", onPlay); io.disconnect(); clearTimeout(t); };
  }, []);

  const expanded = open || hover || playing;

  return (
    <div className="nd-screen" ref={ref}>
      <div className="nd-menubar" aria-hidden>
        <span className="nd-menus"><b>Rift</b><span>File</span><span>Edit</span><span>View</span><span>Window</span></span>
        <span className="nd-status">
          <svg viewBox="0 0 24 24"><path d="M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0" /><circle cx="12" cy="19.5" r="1" /></svg>
          <svg viewBox="0 0 28 14"><rect x="1" y="1.5" width="22" height="11" rx="3" /><rect x="3" y="3.5" width="15" height="7" rx="1.5" className="fill" /><path d="M25 5.5v3" /></svg>
        </span>
      </div>

      <div
        className={expanded ? "nd-island open" : "nd-island"}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        onFocus={() => setHover(true)}
        onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node)) setHover(false); }}
      >
        <div className="nd-row">
          <span className={playing ? "nd-art spin" : "nd-art"} aria-hidden>
            <span className="nd-art-label"><Image src={asset("/brand/rift-128.png")} alt="" width={128} height={128} /></span>
          </span>
          <span className="nd-meta">
            <b>Rift Radio</b>
            <em>{playing ? "Playing from the record player above" : "An original loop, made in your browser"}</em>
          </span>
          <span className={playing ? "nd-eq live" : "nd-eq"} aria-hidden><i /><i /><i /><i /></span>
        </div>
        <div className="nd-controls">
          <span className="nd-bar" aria-hidden><span className={playing ? "run" : ""} /></span>
          <div className="nd-buttons">
            <span className="nd-skip prev" aria-hidden />
            <button
              type="button"
              className="nd-play"
              aria-pressed={playing}
              aria-label={playing ? "Pause Rift Radio" : "Play Rift Radio"}
              onClick={() => window.dispatchEvent(new Event("rift:toggle"))}
            >
              {playing
                ? <svg viewBox="0 0 24 24" aria-hidden><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>
                : <svg viewBox="0 0 24 24" aria-hidden><path d="M8 5.5v13l10-6.5z" /></svg>}
            </button>
            <span className="nd-skip next" aria-hidden />
          </div>
        </div>
      </div>
      <p className="nd-hint" aria-hidden>{expanded ? "" : "Hover the notch"}</p>
    </div>
  );
}
