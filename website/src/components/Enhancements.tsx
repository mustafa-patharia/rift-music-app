"use client";
// One client enhancer. Ports the vanilla main.js behavior to Next.
// Content is already visible without this — it only adds motion.
import { useEffect } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { REPO } from "@/lib/config";

export default function Enhancements() {
  useEffect(() => {
    const root = document.documentElement;
    root.classList.add("js");
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    /* ---- theme toggle ---- */
    const sys = window.matchMedia("(prefers-color-scheme: dark)");
    const resolved = () =>
      root.dataset.theme === "dark" || root.dataset.theme === "light"
        ? root.dataset.theme
        : sys.matches ? "dark" : "light";
    const btn = document.getElementById("theme-toggle");
    const relabel = () => {
      const next = resolved() === "dark" ? "light" : "dark";
      btn?.setAttribute("aria-label", `Switch to ${next} mode`);
      btn?.setAttribute("title", `Switch to ${next} mode`);
    };
    const onTheme = () => {
      const next = resolved() === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      try { localStorage.setItem("rift-theme", next); } catch {}
      relabel();
    };
    btn?.addEventListener("click", onTheme);
    sys.addEventListener("change", relabel);
    relabel();

    /* ---- reveals (no-JS safe: IO adds is-visible) ---- */
    const reveals = Array.from(document.querySelectorAll<HTMLElement>(".reveal"));
    if (reduced || !("IntersectionObserver" in window)) {
      reveals.forEach((el) => el.classList.add("is-visible"));
    } else {
      const io = new IntersectionObserver(
        (entries) => entries.forEach((e) => {
          if (e.isIntersecting) {
            const el = e.target as HTMLElement;
            const group = el.closest(".stagger");
            if (group) {
              const kids = Array.from(group.querySelectorAll<HTMLElement>(".reveal"));
              kids.forEach((k, i) => k.style.transitionDelay = `${i * 70}ms`);
            }
            el.classList.add("is-visible");
            io.unobserve(el);
          }
        }),
        { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
      );
      reveals.forEach((el) => io.observe(el));
    }

    /* ---- nav Download shows only once the hero's Download is off screen ---- */
    const heroEl = document.querySelector(".hero");
    const heroIO = heroEl && "IntersectionObserver" in window
      ? new IntersectionObserver(([e]) => root.classList.toggle("past-hero", !e.isIntersecting), { rootMargin: "-120px 0px 0px 0px" })
      : null;
    if (heroEl && heroIO) heroIO.observe(heroEl); else root.classList.add("past-hero");

    /* ---- pause all looping motion (WCAG 2.2.2); remembered per visitor ---- */
    const motionBtn = document.getElementById("motion-toggle");
    const setStill = (on: boolean) => {
      root.classList.toggle("still", on);
      motionBtn?.setAttribute("aria-pressed", String(on));
      if (motionBtn) motionBtn.textContent = on ? "Play animations" : "Pause animations";
    };
    try { setStill(localStorage.getItem("rift-still") === "1"); } catch { setStill(false); }
    const onMotion = () => {
      const on = !root.classList.contains("still");
      setStill(on);
      try { localStorage.setItem("rift-still", on ? "1" : "0"); } catch {}
    };
    motionBtn?.addEventListener("click", onMotion);

    /* ---- top scrubber ↔ scroll ---- */
    const scrub = document.querySelector<HTMLElement>(".scrubber");
    let ticking = false;
    const drawScrub = () => {
      ticking = false;
      if (!scrub) return;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const p = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      scrub.style.setProperty("--p", `${(p * 100).toFixed(2)}%`);
    };
    const reqScrub = () => { if (!ticking) { ticking = true; requestAnimationFrame(drawScrub); } };
    addEventListener("scroll", reqScrub, { passive: true });
    addEventListener("resize", reqScrub, { passive: true });
    drawScrub();

    const cleanups: Array<() => void> = [];


    /* ---- GSAP: word light-up, tilt, magnetic ---- */
    let ctx: gsap.Context | undefined;
    if (!reduced) {
      gsap.registerPlugin(ScrollTrigger);
      ctx = gsap.context(() => {
        document.querySelectorAll<HTMLElement>("[data-lightup]").forEach((lede) => {
          const words = (lede.textContent || "").trim().split(/\s+/);
          lede.innerHTML = words.map((w) => `<span class="wd">${w}</span>`).join(" ");
          gsap.to(lede.querySelectorAll(".wd"), {
            color: "var(--ink)", stagger: 0.3, ease: "none",
            scrollTrigger: { trigger: lede, start: "top 80%", end: "top 35%", scrub: 0.6 },
          });
        });

        // hero/product-shot rise on entry
        gsap.utils.toArray<HTMLElement>("[data-tilt]").forEach((el) => {
          gsap.fromTo(el, { y: 40, scale: 0.97 }, {
            y: 0, scale: 1, ease: "power3.out", duration: 1,
            scrollTrigger: { trigger: el, start: "top 88%" },
          });
        });

        // pointer tilt
        const tilts = gsap.utils.toArray<HTMLElement>("[data-tilt]");
        tilts.forEach((el) => gsap.set(el, { transformPerspective: 1100 }));
        const onTilt = (e: MouseEvent) => {
          tilts.forEach((el) => {
            const r = el.getBoundingClientRect();
            if (r.bottom < -80 || r.top > innerHeight + 80) return;
            const nx = (e.clientX - r.left - r.width / 2) / r.width;
            const ny = (e.clientY - r.top - r.height / 2) / r.height;
            gsap.to(el, { rotationX: -ny * 3, rotationY: nx * 3, duration: 0.6, ease: "power2.out" });
          });
        };
        addEventListener("mousemove", onTilt, { passive: true });
        cleanups.push(() => removeEventListener("mousemove", onTilt));

        // card glare
        document.querySelectorAll<HTMLElement>(".cell").forEach((card) => {
          const onCardMove = (e: MouseEvent) => {
            const r = card.getBoundingClientRect();
            card.style.setProperty("--mx", `${e.clientX - r.left}px`);
            card.style.setProperty("--my", `${e.clientY - r.top}px`);
          };
          card.addEventListener("mousemove", onCardMove, { passive: true });
          cleanups.push(() => card.removeEventListener("mousemove", onCardMove));
        });

        // magnetic primary buttons
        document.querySelectorAll<HTMLElement>(".pn-cta, .keycap:not(.ghost)").forEach((b) => {
          const onBtnMove = (e: MouseEvent) => {
            const r = b.getBoundingClientRect();
            gsap.to(b, { x: (e.clientX - r.left - r.width / 2) * 0.2, y: (e.clientY - r.top - r.height / 2) * 0.3, duration: 0.3, ease: "power2.out" });
          };
          const onBtnLeave = () => gsap.to(b, { x: 0, y: 0, duration: 0.5, ease: "elastic.out(1,0.45)" });
          b.addEventListener("mousemove", onBtnMove);
          b.addEventListener("mouseleave", onBtnLeave);
          cleanups.push(() => {
            b.removeEventListener("mousemove", onBtnMove);
            b.removeEventListener("mouseleave", onBtnLeave);
          });
        });
      });
      ScrollTrigger.refresh();
    }

    /* ---- live release info ---- */
    (async () => {
      try {
        const owner = REPO.split("/").slice(-2).join("/");
        const res = await fetch(`https://api.github.com/repos/${owner}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } });
        if (!res.ok) return;
        const rel = await res.json();
        if (rel.tag_name) document.querySelectorAll(".release-version").forEach((el) => (el.textContent = rel.tag_name));
        const asset = rel.assets?.find((a: { name: string }) => /\.(dmg|zip)$/i.test(a.name));
        if (asset?.browser_download_url) document.querySelectorAll<HTMLAnchorElement>("[data-release-link]").forEach((a) => (a.href = asset.browser_download_url));
      } catch {}
    })();

    return () => {
      heroIO?.disconnect();
      motionBtn?.removeEventListener("click", onMotion);
      btn?.removeEventListener("click", onTheme);
      sys.removeEventListener("change", relabel);
      removeEventListener("scroll", reqScrub);
      removeEventListener("resize", reqScrub);
      cleanups.forEach((fn) => fn());
      ctx?.revert();
    };
  }, []);

  return null;
}
