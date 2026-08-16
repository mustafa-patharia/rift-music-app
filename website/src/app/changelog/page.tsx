import type { Metadata } from "next";
import { Nav, Scrubber, Footer } from "@/components/Chrome";
import { CHANGELOG } from "@/lib/changelog";

export const metadata: Metadata = {
  title: "Changelog — Rift Music App",
  description: "What's new in Rift Music App, the native Mac YouTube Music client.",
  alternates: { canonical: "/changelog" },
};

export default function ChangelogPage() {
  return (
    <>
      <div className="aurora" aria-hidden>
        <div className="glow-wrap wrap-a"><div className="glow glow-a" /></div>
        <div className="glow-wrap wrap-b"><div className="glow glow-b" /></div>
        <div className="glow-wrap wrap-c"><div className="glow glow-c" /></div>
      </div>

      <Nav />
      <Scrubber />

      <main>
        <section className="rail chorus" style={{ paddingTop: 140 }}>
          <p className="eyebrow accent">Changelog</p>
          <h1 className="serif" style={{ fontSize: "clamp(2.6rem,6vw,4.4rem)" }}>What&rsquo;s new in Rift Music App.</h1>
          <p className="lede">Every release, in the open. Rift Music App is GPL-3.0 and in active development.</p>

          <ol className="changelog">
            {CHANGELOG.map((rel) => (
              <li className="cl-entry" key={rel.version}>
                <div className="cl-meta">
                  <span className="cl-ver">
                    {rel.version}
                    {rel.current && <span className="cl-current">current</span>}
                  </span>
                  {rel.date && <time className="cl-date">{rel.date}</time>}
                </div>
                <div className="cl-body">
                  {rel.sections.map((sec) => (
                    <div className="cl-section" key={sec.label}>
                      <span className={`cl-tag cl-${sec.label.toLowerCase()}`}>{sec.label}</span>
                      <ul>
                        {sec.items.map((it, i) => <li key={i}>{it}</li>)}
                      </ul>
                    </div>
                  ))}
                </div>
              </li>
            ))}
          </ol>
        </section>
      </main>

      <Footer />
    </>
  );
}
