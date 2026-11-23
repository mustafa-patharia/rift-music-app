"use client";
// Turntable: the hero's one standout element, and a real 1.1 feature (Rift's
// record-player Now Playing style). Drop the needle and the record spins up
// while an original lo-fi loop is generated live with Web Audio: no audio
// files, no licensed music. Grab the record to drag it faster or slower and
// the sound bends with it. The level is published on window.__riftLevel so
// the background waves move with the music, and a "rift:play" event lets the
// hero island show it's playing. No buttons: you pick up the tonearm and
// put it on the record (or press Enter on it). Sound only starts from that.
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { asset } from "@/lib/asset";

const BPM = 84;
const BEAT = 60 / BPM;
const RPM_DEG = 110;            // a lazy spin; slower than a real 33⅓ (200°/s), easier on the eye
// Dm9, G13, Cmaj9, Am7: voiced low and close, the lo-fi staple.
const CHORDS = [
  [146.83, 174.61, 220.0, 261.63, 329.63],
  [98.0, 174.61, 246.94, 329.63, 349.23],
  [130.81, 164.81, 196.0, 246.94, 293.66],
  [110.0, 164.81, 196.0, 261.63, 329.63],
];
const MELODY = [659.25, 587.33, 523.25, 440.0, 523.25, 587.33, 392.0, 440.0]; // one note every two beats

type Engine = {
  ctx: AudioContext; master: GainNode; tone: BiquadFilterNode; analyser: AnalyserNode;
  noise: AudioBuffer; timer: number; step: number; next: number;
};

declare global { interface Window { __riftLevel?: number } }

function makeEngine(): Engine {
  const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
  const ctx = new AC();
  const master = ctx.createGain(); master.gain.value = 0;
  const tone = ctx.createBiquadFilter(); tone.type = "lowpass"; tone.frequency.value = 2400; tone.Q.value = 0.7;
  const analyser = ctx.createAnalyser(); analyser.fftSize = 256;
  tone.connect(master); master.connect(analyser); analyser.connect(ctx.destination);
  const noise = ctx.createBuffer(1, ctx.sampleRate * 1, ctx.sampleRate);
  const d = noise.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  return { ctx, master, tone, analyser, noise, timer: 0, step: 0, next: 0 };
}

function voice(e: Engine, freq: number, t: number, dur: number, type: OscillatorType, gain: number, attack = 0.02) {
  const o = e.ctx.createOscillator(), g = e.ctx.createGain();
  o.type = type; o.frequency.value = freq; o.detune.value = (Math.random() - 0.5) * 8; // tape wobble
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g); g.connect(e.tone);
  o.start(t); o.stop(t + dur + 0.05);
}

function hit(e: Engine, t: number, kind: "kick" | "snare" | "hat") {
  const g = e.ctx.createGain();
  if (kind === "kick") {
    const o = e.ctx.createOscillator();
    o.frequency.setValueAtTime(120, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.18);
    g.gain.setValueAtTime(0.55, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.32);
    o.connect(g); g.connect(e.tone); o.start(t); o.stop(t + 0.35);
    return;
  }
  const n = e.ctx.createBufferSource(); n.buffer = e.noise;
  const f = e.ctx.createBiquadFilter();
  f.type = kind === "hat" ? "highpass" : "bandpass";
  f.frequency.value = kind === "hat" ? 7000 : 1800;
  const peak = kind === "hat" ? 0.035 : 0.12, len = kind === "hat" ? 0.04 : 0.16;
  g.gain.setValueAtTime(peak, t); g.gain.exponentialRampToValueAtTime(0.0001, t + len);
  n.connect(f); f.connect(g); g.connect(e.tone); n.start(t, Math.random() * 0.5); n.stop(t + len + 0.02);
}

function crackle(e: Engine, t: number) {
  const n = e.ctx.createBufferSource(), g = e.ctx.createGain(), f = e.ctx.createBiquadFilter();
  n.buffer = e.noise; f.type = "highpass"; f.frequency.value = 3000;
  g.gain.setValueAtTime(0.02 + Math.random() * 0.03, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.01);
  n.connect(f); f.connect(g); g.connect(e.master); n.start(t, Math.random() * 0.9); n.stop(t + 0.02);
}

/** Schedules eighth notes ~120 ms ahead (the standard Web Audio lookahead pattern). */
function schedule(e: Engine) {
  while (e.next < e.ctx.currentTime + 0.12) {
    const t = e.next, s = e.step % 32, beat = Math.floor(s / 2);
    if (s % 8 === 0) CHORDS[Math.floor(s / 8)].forEach((f, i) => voice(e, f, t, BEAT * 4.2, i < 1 ? "triangle" : "sine", i < 1 ? 0.09 : 0.045, 0.25));
    if (s % 4 === 0) voice(e, MELODY[(e.step / 4) % 8 | 0], t + 0.02, BEAT * 1.6, "triangle", 0.05, 0.03);
    if (s % 8 === 0 || s % 8 === 5) hit(e, t, "kick");
    if (beat % 2 === 1 && s % 2 === 0) hit(e, t, "snare");
    hit(e, t + (s % 2 ? BEAT * 0.08 : 0), "hat");   // a little swing on the off-beats
    for (let k = 0; k < 3; k++) if (Math.random() < 0.5) crackle(e, t + Math.random() * BEAT / 2);
    e.next += BEAT / 2; e.step++;
  }
}

export default function Turntable() {
  const [playing, setPlaying] = useState(false);
  const rec = useRef<HTMLDivElement>(null);
  const arm = useRef<HTMLDivElement>(null);
  const engine = useRef<Engine | null>(null);
  const st = useRef({ angle: 0, speed: 0, target: 0, drag: null as null | { a: number; t: number }, raf: 0, last: 0, progress: 0, arm: 0, armDrag: false });

  // render loop: platter physics, tonearm, audio tone follows platter speed
  useEffect(() => {
    const s = st.current;
    const tick = (now: number) => {
      const real = s.last ? Math.min(0.5, (now - s.last) / 1000) : 0.016;
      const dt = Math.min(0.05, real);
      s.last = now;
      if (!s.drag) s.speed += (s.target - s.speed) * Math.min(1, dt * (s.target ? 2.2 : 1.4)); // motor spin-up, slower run-down
      s.angle = (s.angle + s.speed * dt) % 360;
      if (rec.current) rec.current.style.transform = `rotate(${s.angle}deg)`;
      if (s.target) s.progress = Math.min(1, s.progress + dt / 240);
      // tonearm eases onto the outer groove (22°), then tracks inward as the side plays
      const armTarget = s.target ? 22 + s.progress * 12 : 0;
      if (!s.armDrag) s.arm += (armTarget - s.arm) * Math.min(1, real * 3);
      if (arm.current) arm.current.style.transform = `rotate(${s.arm}deg)`;
      const e = engine.current;
      if (e) {
        const ratio = Math.max(0, Math.min(2, s.speed / RPM_DEG));
        // slow platter = muffled and sagging, fast = bright: the "bend" when you drag
        e.tone.frequency.setTargetAtTime(300 + 2400 * Math.min(1.4, ratio), e.ctx.currentTime, 0.05);
        const buf = new Uint8Array(e.analyser.frequencyBinCount);
        e.analyser.getByteFrequencyData(buf);
        let sum = 0; for (let i = 0; i < 24; i++) sum += buf[i];
        window.__riftLevel = sum / (24 * 255);
      } else window.__riftLevel = 0;
      s.raf = requestAnimationFrame(tick);
    };
    s.raf = requestAnimationFrame(tick);
    return () => { cancelAnimationFrame(s.raf); window.__riftLevel = 0; engine.current?.ctx.close(); };
  }, []);

  const playingRef = useRef(false);

  const play = async () => {
    if (playingRef.current) return;
    playingRef.current = true;
    if (!engine.current) engine.current = makeEngine();
    const e = engine.current;
    await e.ctx.resume();
    e.next = e.ctx.currentTime + 0.35; e.step = 0;            // needle lands, then the music
    e.master.gain.cancelScheduledValues(e.ctx.currentTime);
    e.master.gain.setTargetAtTime(0.7, e.ctx.currentTime + 0.3, 0.3);
    clearInterval(e.timer);
    e.timer = window.setInterval(() => schedule(e), 25);
    st.current.target = RPM_DEG;
    setPlaying(true);
    window.dispatchEvent(new CustomEvent("rift:play", { detail: true }));
  };

  const stop = () => {
    if (!playingRef.current) return;
    playingRef.current = false;
    const e = engine.current;
    if (e) {
      e.master.gain.setTargetAtTime(0, e.ctx.currentTime, 0.15);
      const timer = e.timer;
      setTimeout(() => { if (!playingRef.current) { clearInterval(timer); e.ctx.suspend(); } }, 700);
    }
    st.current.target = 0;
    st.current.progress = 0;
    setPlaying(false);
    window.dispatchEvent(new CustomEvent("rift:play", { detail: false }));
  };

  const toggle = () => (playingRef.current ? stop() : void play());

  // the Notch section's play button drives the same deck
  const toggleRef = useRef(toggle);
  toggleRef.current = toggle;
  useEffect(() => {
    const onToggle = () => { void toggleRef.current(); };
    window.addEventListener("rift:toggle", onToggle);
    return () => window.removeEventListener("rift:toggle", onToggle);
  }, []);

  // grab the record: drag rotates it; letting go hands it back to the motor
  const angleAt = (ev: React.PointerEvent) => {
    const r = rec.current!.getBoundingClientRect();
    return Math.atan2(ev.clientY - (r.top + r.height / 2), ev.clientX - (r.left + r.width / 2)) * 180 / Math.PI;
  };
  const onDown = (ev: React.PointerEvent) => {
    (ev.target as HTMLElement).setPointerCapture(ev.pointerId);
    st.current.drag = { a: angleAt(ev), t: performance.now() };
  };
  const onMove = (ev: React.PointerEvent) => {
    const s = st.current;
    if (!s.drag) return;
    const a = angleAt(ev), now = performance.now();
    let d = a - s.drag.a; if (d > 180) d -= 360; if (d < -180) d += 360;
    const dt = Math.max(8, now - s.drag.t) / 1000;
    s.speed = s.speed * 0.6 + (d / dt) * 0.4;
    s.angle += d;
    s.drag = { a, t: now };
  };
  const onUp = () => { st.current.drag = null; };

  // pick up the tonearm: it swings about its pivot under the pointer.
  // Let go over the grooves (≥ 18°) and the needle drops; anywhere else it rests.
  const ON = 18, MAX = 38;
  const armAngle = (ev: React.PointerEvent) => {
    const p = arm.current!.querySelector(".tt-pivot")!.getBoundingClientRect();
    const cx = p.left + p.width / 2, cy = p.top + p.height / 2;
    const deg = Math.atan2(cx - ev.clientX, ev.clientY - cy) * 180 / Math.PI;   // 0 = hanging straight down
    return Math.max(0, Math.min(MAX, deg));
  };
  const armDown = (ev: React.PointerEvent) => {
    ev.preventDefault();
    (ev.currentTarget as HTMLElement).setPointerCapture(ev.pointerId);
    st.current.armDrag = true;
    arm.current?.classList.add("held");
  };
  const armMove = (ev: React.PointerEvent) => {
    if (!st.current.armDrag) return;
    st.current.arm = armAngle(ev);
  };
  const armUp = () => {
    const s = st.current;
    if (!s.armDrag) return;
    s.armDrag = false;
    arm.current?.classList.remove("held");
    if (s.arm >= ON) {
      s.progress = Math.max(0, Math.min(1, (s.arm - 22) / 12));   // play from where you set it down
      void play();
    } else stop();
  };
  const armKey = (ev: React.KeyboardEvent) => {
    if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); toggle(); }
  };

  return (
    <div className={playing ? "turntable playing" : "turntable"}>
      <div className="tt-plinth">
        <div className="tt-platter">
          <div
            className="tt-record"
            ref={rec}
            onPointerDown={onDown}
            onPointerMove={onMove}
            onPointerUp={onUp}
            onPointerCancel={onUp}
            role="img"
            aria-label="A record on the platter. Drag it to spin it."
          >
            <div className="tt-label"><Image src={asset("/brand/rift-256.png")} alt="" width={256} height={256} draggable={false} /></div>
          </div>
          <div className="tt-sheen" aria-hidden />
          <div className="tt-spindle" aria-hidden />
        </div>
        <div
          className="tt-arm"
          ref={arm}
          role="switch"
          tabIndex={0}
          aria-checked={playing}
          aria-label="Tonearm. Drag it onto the record to play, off to stop, or press Enter."
          onPointerDown={armDown}
          onPointerMove={armMove}
          onPointerUp={armUp}
          onPointerCancel={armUp}
          onKeyDown={armKey}
        >
          <span className="tt-pivot" />
          <span className="tt-rod" />
          <span className="tt-head" />
        </div>
        <span className="tt-light" aria-hidden />
      </div>
      <p className="tt-note">{playing
        ? "An original loop, made live in your browser. Grab the record to bend it, or lift the arm to stop."
        : "Sound on. Pick up the tonearm and set it on the record."}</p>
    </div>
  );
}
