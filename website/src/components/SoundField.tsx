"use client";
// SoundField: the page's one background motif, faint sound-wave lines in
// the ink colour, flowing slowly (Rift is a music player; the waves say so).
// The cursor gently swells the waves near it. 30 fps, stops when the tab is
// hidden or the visitor pauses motion (html.still), one still frame under
// Reduce Motion.
import { useEffect, useRef } from "react";

const LINES = 18;
export default function SoundField() {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const c = ref.current;
    const ctx = c?.getContext("2d");
    if (!c || !ctx) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let w = 0, h = 0, raf = 0, last = 0, t = 0;
    const mouse = { x: -9999, y: -9999, tx: -9999, ty: -9999 };
    const root = document.documentElement;
    const resize = () => {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      w = window.innerWidth; h = window.innerHeight;
      c.width = w * dpr; c.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    const draw = () => {
      ctx.clearRect(0, 0, w, h);
      ctx.lineWidth = 1;
      const ink = getComputedStyle(root).getPropertyValue("--ink").trim() || "#fff";
      ctx.strokeStyle = ink;
      const mid = h * 0.55, spread = h * 0.5;
      const level = Math.min(1, (window.__riftLevel ?? 0) * 2.2);
      for (let l = 0; l < LINES; l++) {
        const p = l / (LINES - 1);                 // 0 … 1 through the stack
        const base = mid + (p - 0.5) * spread;
        const amp = 18 + 46 * Math.sin(p * Math.PI);  // fuller in the middle
        const freq = 0.0016 + p * 0.0011;
        const speed = 0.35 + p * 0.25;
        ctx.globalAlpha = (0.04 + 0.07 * Math.sin(p * Math.PI)) * (1 + level * 1.2);
        ctx.beginPath();
        for (let x = -10; x <= w + 10; x += 8) {
          const dx = x - mouse.x, dy = base - mouse.y;
          const near = Math.exp(-(dx * dx) / 52000 - (dy * dy) / 30000);  // cursor swell
          const lvl = level * (0.6 + 0.8 * Math.sin(p * Math.PI));        // music swell
          const y = base
            + Math.sin(x * freq + t * speed + l * 0.55) * amp * (1 + near * 1.4 + lvl * 2.6)
            + Math.sin(x * freq * 2.7 - t * speed * 1.3 + l) * amp * 0.25;
          if (x === -10) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    };

    const tick = (now: number) => {
      raf = requestAnimationFrame(tick);
      if (now - last < 33 || root.classList.contains("still")) return;              // ~30 fps is plenty for a backdrop
      const dt = last ? Math.min(0.1, (now - last) / 1000) : 0.033;
      last = now;
      t += dt;
      mouse.x += (mouse.tx - mouse.x) * 0.08;
      mouse.y += (mouse.ty - mouse.y) * 0.08;
      draw();
    };

    const onMove = (e: PointerEvent) => {
      if (mouse.x < -9000) { mouse.x = e.clientX; mouse.y = e.clientY; }
      mouse.tx = e.clientX; mouse.ty = e.clientY;
    };
    const onVis = () => {
      cancelAnimationFrame(raf); raf = 0;
      if (!document.hidden && !reduced) { last = 0; raf = requestAnimationFrame(tick); }
    };

    resize();
    draw();
    const onResize = () => { resize(); draw(); };
    window.addEventListener("resize", onResize);
    if (!reduced) {
      window.addEventListener("pointermove", onMove, { passive: true });
      document.addEventListener("visibilitychange", onVis);
      raf = requestAnimationFrame(tick);
    }
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", onResize);
      window.removeEventListener("pointermove", onMove);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, []);

  return <canvas ref={ref} className="sound-field" aria-hidden />;
}
