"use client";
// Scroll-pinned card swap. Heading (feature title + subtitle) centered on top,
// the app screen centered below. Section pins; scrolling steps through cards
// one-by-one; after the last card the section unpins and the page continues.
//
// No scrub, no ScrollTrigger snap — both fight Lenis (double-easing lag + snap
// freeze that strands the deck mid-crossfade). Instead: Lenis drives smooth
// scroll, onUpdate maps progress → a discrete card index, and each index change
// runs one fixed tween. Resting anywhere shows exactly one clean card.
// Reduced-motion → static vertical stack with captions.
import { useEffect, useRef } from "react";
import Image from "next/image";
import { asset } from "@/lib/asset";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

const SHOTS = [
  { n: "home_screen", l: "Home", title: "Your whole library, home.", sub: "Featured playlists, recently played, and your top artists — the moment you open Rift Music App." },
  { n: "full_screen_player_screen", l: "Now Playing", title: "Now Playing, in full.", sub: "Full-window album art, a live scrubber, and transport — Liquid Glass on Tahoe." },
  { n: "player_with_lyrics_screen", l: "Lyrics", title: "Lyrics that keep time.", sub: "Synced lyrics with optional on-device transliteration and translation — even non-Latin scripts." },
  { n: "artist_screen", l: "Artist", title: "Every artist, in depth.", sub: "Bio, monthly listeners, top songs, albums, and one-tap radio — all native." },
  { n: "search_screen", l: "Search", title: "Search all of YouTube Music.", sub: "Trending charts, your recents, and top artists — the full catalog, one field." },
  { n: "library_screen", l: "Library", title: "Your playlists, your way.", sub: "Liked Music, your playlists and downloads — local-first, synced when you sign in." },
];

export default function ScrollDeck() {
  const sec = useRef<HTMLElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const copy = useRef<HTMLDivElement>(null);
  const dots = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const stageEl = stage.current, copyEl = copy.current;
    if (!stageEl || !copyEl) return;
    const cards = Array.from(stageEl.querySelectorAll<HTMLElement>(".sd-card"));
    const texts = Array.from(copyEl.querySelectorAll<HTMLElement>(".sd-text"));
    const dotEls = dots.current ? (Array.from(dots.current.children) as HTMLElement[]) : [];
    const n = cards.length;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (reduced || n < 2) {
      sec.current?.classList.add("sd-reduced");
      gsap.set([...cards, ...texts], { opacity: 1, clearProps: "transform" });
      return;
    }

    gsap.registerPlugin(ScrollTrigger);

    const ctx = gsap.context(() => {
      gsap.set([...cards, ...texts], { opacity: 0, scale: 0.96, y: 30 });
      gsap.set([cards[0], texts[0]], { opacity: 1, scale: 1, y: 0 });
      dotEls.forEach((d, i) => d.classList.toggle("on", i === 0));

      let cur = 0;
      const show = (idx: number) => {
        idx = Math.max(0, Math.min(n - 1, idx));
        if (idx === cur) return;
        const dir = idx > cur ? 1 : -1;
        gsap.to([cards[cur], texts[cur]], { opacity: 0, scale: 0.96, y: -30 * dir, duration: 0.4, ease: "power2.out", overwrite: true });
        gsap.fromTo([cards[idx], texts[idx]], { opacity: 0, scale: 0.96, y: 30 * dir }, { opacity: 1, scale: 1, y: 0, duration: 0.5, ease: "power2.out", overwrite: true });
        cur = idx;
        dotEls.forEach((d, i) => d.classList.toggle("on", i === idx));
      };

      // ~0.7 viewport of scroll per card — long enough to feel deliberate, short
      // enough that it never feels like "scroll forever, nothing happens".
      const step = Math.round(window.innerHeight * 0.7);
      ScrollTrigger.create({
        trigger: sec.current!,
        start: "top top",
        end: `+=${(n - 1) * step}`,
        pin: inner.current!,
        anticipatePin: 1,
        invalidateOnRefresh: true,
        onUpdate: (self) => show(Math.round(self.progress * (n - 1))),
      });
    }, sec);

    ScrollTrigger.refresh();
    return () => ctx.revert();
  }, []);

  return (
    <section className="scrolldeck" ref={sec} id="inside" aria-label="Inside Rift Music App">
      <div className="scrolldeck-inner" ref={inner}>
        <p className="eyebrow accent">Inside Rift Music App</p>
        <div className="sd-copy" ref={copy}>
          {SHOTS.map((s) => (
            <div className="sd-text" key={s.n}>
              <h2 className="serif">{s.title}</h2>
              <p className="lede">{s.sub}</p>
            </div>
          ))}
        </div>
        <div className="sd-stage" ref={stage}>
          {SHOTS.map((s) => (
            <figure className="sd-card" key={s.n}>
              <Image src={asset(`/img/shots/${s.n}.png`)} alt={`Rift Music App — ${s.l}`} fill sizes="(max-width: 820px) 92vw, 780px" style={{ objectFit: "cover", objectPosition: "top left" }} />
              <span className="swap-card-label">{s.l}</span>
              <figcaption className="sd-cap"><b>{s.title}</b> {s.sub}</figcaption>
            </figure>
          ))}
        </div>
        <div className="sd-dots" ref={dots} aria-hidden>
          {SHOTS.map((s) => <span key={s.n} />)}
        </div>
      </div>
    </section>
  );
}
