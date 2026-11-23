"use client";
// Together — the 1.1 listening-room stage, recreated for the web: a spinning
// record in the middle and listener bubbles pulled to it like magnets. Drag a
// bubble away and let go; it springs back. Mirrors MagnetSim in the app
// (pull 1100 + d·5, damping e^-5.5t, gap 4, bounce .35). Static ring when
// JS is off or Reduce Motion is on.
import { useEffect, useRef } from "react";

// Placeholder listeners, not invented people: "You" hosts, the rest are generic guests.
type Listener = { id: string; label: string; host?: boolean };
const LISTENERS: Listener[] = [
  { id: "you", label: "You", host: true }, { id: "g1", label: "" }, { id: "g2", label: "" },
  { id: "g3", label: "" }, { id: "g4", label: "" }, { id: "g5", label: "" },
];
const R = 30;      // bubble radius
const GAP = 4;

type Body = { x: number; y: number; vx: number; vy: number };

function ring(w: number, h: number, core: number): Body[] {
  return LISTENERS.map((_, i) => {
    const a = (i / LISTENERS.length) * Math.PI * 2 - Math.PI / 2;
    const d = core + R + GAP + 2;
    return { x: w / 2 + Math.cos(a) * d, y: h / 2 + Math.sin(a) * d, vx: 0, vy: 0 };
  });
}

// No-JS / first paint: the settled ring, in CSS units (core ≈ 22% of a 420px stage).
function ssrSpot(i: number) {
  const a = (i / LISTENERS.length) * Math.PI * 2 - Math.PI / 2, d = 92 + R + GAP + 2;
  return { left: `calc(50% + ${(Math.cos(a) * d).toFixed(1)}px - ${R}px)`, top: `calc(50% + ${(Math.sin(a) * d).toFixed(1)}px - ${R}px)` };
}

export default function Together() {
  const stage = useRef<HTMLDivElement>(null);
  const els = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const el = stage.current;
    if (!el) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let w = el.clientWidth, h = el.clientHeight;
    let core = Math.min(w, h) * 0.22;
    let bodies = ring(w, h, core);
    // Start scattered so the first view shows them snapping in.
    if (!reduced) bodies = bodies.map((b, i) => ({ ...b, x: b.x + Math.cos(i * 2.1) * 140, y: b.y + Math.sin(i * 1.7) * 120 }));
    let drag: { i: number; px: number; py: number; t: number } | null = null;
    let raf = 0, last = 0, visible = false;

    const paint = () => bodies.forEach((b, i) => {
      const n = els.current[i];
      if (n) { n.style.left = "0"; n.style.top = "0"; n.style.transform = `translate(${b.x - R}px, ${b.y - R}px)`; }
    });

    const step = (dt: number) => {
      const cx = w / 2, cy = h / 2;
      const damp = Math.exp(-5.5 * dt);
      bodies.forEach((b, i) => {
        if (drag?.i === i) return;
        const dx = cx - b.x, dy = cy - b.y, d = Math.hypot(dx, dy) || 1;
        const acc = 1100 + d * 5;
        b.vx = (b.vx + (dx / d) * acc * dt) * damp;
        b.vy = (b.vy + (dy / d) * acc * dt) * damp;
        b.x += b.vx * dt; b.y += b.vy * dt;
      });
      for (let pass = 0; pass < 4; pass++) {
        bodies.forEach((b, i) => {
          // keep off the record
          const dx = b.x - cx, dy = b.y - cy, d = Math.hypot(dx, dy) || 1, min = core + R + GAP;
          if (d < min && drag?.i !== i) {
            b.x = cx + (dx / d) * min; b.y = cy + (dy / d) * min;
            const vn = (b.vx * dx + b.vy * dy) / d;
            if (vn < 0) { b.vx -= 1.35 * vn * dx / d; b.vy -= 1.35 * vn * dy / d; }
          }
          for (let j = i + 1; j < bodies.length; j++) {
            const o = bodies[j];
            const ex = o.x - b.x, ey = o.y - b.y, e = Math.hypot(ex, ey) || 1, m = 2 * R + GAP;
            if (e >= m) continue;
            const push = (m - e) / 2, nx = ex / e, ny = ey / e;
            const bFixed = drag?.i === i, oFixed = drag?.i === j;
            if (!bFixed) { b.x -= nx * push * (oFixed ? 2 : 1); b.y -= ny * push * (oFixed ? 2 : 1); }
            if (!oFixed) { o.x += nx * push * (bFixed ? 2 : 1); o.y += ny * push * (bFixed ? 2 : 1); }
            const rv = (o.vx - b.vx) * nx + (o.vy - b.vy) * ny;
            if (rv < 0) {
              const k = -(1.35) * rv / 2;
              if (!bFixed) { b.vx -= k * nx; b.vy -= k * ny; }
              if (!oFixed) { o.vx += k * nx; o.vy += k * ny; }
            }
          }
          // stay inside the stage
          b.x = Math.min(w - R, Math.max(R, b.x)); b.y = Math.min(h - R, Math.max(R, b.y));
        });
      }
    };

    const tick = (t: number) => {
      const dt = Math.min(1 / 30, last ? (t - last) / 1000 : 1 / 60);
      last = t;
      step(dt); paint();
      raf = visible ? requestAnimationFrame(tick) : 0;
    };
    const run = () => { if (!raf && !reduced) { last = 0; raf = requestAnimationFrame(tick); } };

    if (reduced) { for (let k = 0; k < 240; k++) step(1 / 60); }
    paint();

    const io = new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible) run(); });
    io.observe(el);
    const ro = new ResizeObserver(() => {
      w = el.clientWidth; h = el.clientHeight; core = Math.min(w, h) * 0.22;
      if (reduced) { bodies = ring(w, h, core); for (let k = 0; k < 240; k++) step(1 / 60); }
      paint(); run();
    });
    ro.observe(el);

    const local = (e: PointerEvent) => { const r = el.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    const down = (e: PointerEvent) => {
      const i = els.current.findIndex((n) => n === (e.target as HTMLElement).closest(".bubble"));
      if (i < 0) return;
      e.preventDefault();
      (e.target as HTMLElement).setPointerCapture(e.pointerId);
      const [px, py] = local(e);
      drag = { i, px, py, t: performance.now() };
      els.current[i]?.classList.add("held");
      run();
    };
    const move = (e: PointerEvent) => {
      if (!drag) return;
      const [px, py] = local(e), now = performance.now(), dt = Math.max(1, now - drag.t) / 1000;
      const b = bodies[drag.i];
      b.vx = (px - drag.px) / dt; b.vy = (py - drag.py) / dt;
      b.x = px; b.y = py;
      drag = { ...drag, px, py, t: now };
      if (reduced) paint();
    };
    const up = () => {
      if (!drag) return;
      els.current[drag.i]?.classList.remove("held");
      drag = null;
      if (reduced) { for (let k = 0; k < 240; k++) step(1 / 60); paint(); }
    };
    el.addEventListener("pointerdown", down);
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    window.addEventListener("pointercancel", up);
    return () => {
      cancelAnimationFrame(raf); io.disconnect(); ro.disconnect();
      el.removeEventListener("pointerdown", down);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      window.removeEventListener("pointercancel", up);
    };
  }, []);

  return (
    <section className="rail verse together" id="together" aria-label="Listen together">
      <p className="eyebrow reveal">New in 1.1</p>
      <h2 className="serif reveal">Listen together.</h2>
      <p className="lede reveal">
        Start a room, share the code, and friends anywhere hear what you play, in sync to within a couple of
        seconds. Everyone gathers around the record. React, send a song, or let someone else pick.
      </p>

      <div className="room reveal">
        <div className="room-bar">
          <span className="room-live"><span className="dot" /> Your room</span>
          <span className="room-code" title="Example code">RIFT-XXXX-XXXX-XXXX</span>
        </div>
        <div className="room-stage" ref={stage}>
          <div className="disc" aria-hidden><span className="disc-label" /></div>
          {LISTENERS.map((l, i) => (
            <div
              key={l.id}
              ref={(n) => { els.current[i] = n; }}
              className={l.host ? "bubble host" : "bubble"}
              style={ssrSpot(i)}
            >
              {l.host && <svg className="crown" viewBox="0 0 24 24" aria-hidden><path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z" /></svg>}
              {l.label || <svg className="guest" viewBox="0 0 24 24" aria-hidden><circle cx="12" cy="9" r="4" /><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" /></svg>}
            </div>
          ))}
          <p className="room-hint" aria-hidden>Drag a listener away. They snap back.</p>
        </div>
      </div>

      <div className="together-cols">
        <div className="reveal">
          <h3>Rooms, anywhere</h3>
          <p>A 12-character code is all it takes. No account and no Rift server: every Mac streams the music itself.</p>
        </div>
        <div className="reveal">
          <h3>Nearby, instantly</h3>
          <p>Turn on Visible and Macs running Rift close by find each other over Wi-Fi or Bluetooth. Send a song or follow along, and they accept first.</p>
        </div>
        <div className="reveal">
          <h3>Private by design</h3>
          <p>Rooms are end-to-end encrypted with a key from the code. The relays in between only see ciphertext.</p>
        </div>
      </div>
    </section>
  );
}
