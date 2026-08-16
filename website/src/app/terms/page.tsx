import type { Metadata } from "next";
import { Nav, Scrubber, Footer } from "@/components/Chrome";

export const metadata: Metadata = {
  title: "Terms of Use — Rift Music App",
  description: "Terms of Use for Rift Music App, the native Mac YouTube Music client.",
  alternates: { canonical: "/terms" },
};

export default function TermsPage() {
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
        <section className="rail chorus" style={{ paddingTop: 140, paddingBottom: 100 }}>
          <p className="eyebrow accent">Terms</p>
          <h1 className="serif" style={{ fontSize: "clamp(2.6rem,6vw,4.4rem)" }}>Terms of Use.</h1>
          <p className="lede">Last updated: August 2026</p>

          <div className="prose" style={{ marginTop: 60, display: "flex", flexDirection: "column", gap: 24, fontSize: "1.1rem", lineHeight: 1.6, color: "var(--fg-dim)" }}>
            <p>
              Please read these Terms of Use (&quot;Terms&quot;) carefully before using the Rift Music App macOS application and website (collectively, the &quot;App&quot;). By downloading, accessing, or using the App, you agree to be bound by these Terms.
            </p>
            
            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>1. Description of Service</h3>
            <p>
              Rift Music App is an independent, third-party, open-source client application designed to interface with YouTube Music. It provides a native macOS experience for accessing content hosted and provided by YouTube.
            </p>

            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>2. No Affiliation</h3>
            <p>
              Rift Music App is an independent project and is <strong>not affiliated with, endorsed by, authorized by, or in any way officially connected to Google LLC, YouTube</strong>, or any of their subsidiaries or affiliates. All product and company names are the registered trademarks of their original owners. The use of any trade name or trademark is for identification and reference purposes only.
            </p>

            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>3. User Responsibilities and Acceptable Use</h3>
            <p>
              Because Rift Music App acts as a client for YouTube, your use of the App must also comply with <a href="https://www.youtube.com/t/terms" target="_blank" rel="noreferrer" style={{color: "var(--fg)", textDecoration: "underline", textUnderlineOffset: 4}}>YouTube&apos;s Terms of Service</a>. You agree not to use the App in any way that violates applicable laws or YouTube&apos;s terms. We are not responsible for any account limitations, suspensions, or bans resulting from your use of this third-party client. You use Rift Music App at your own risk.
            </p>

            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>4. Intellectual Property</h3>
            <p>
              The source code for Rift Music App is licensed under the GPL-3.0 License. You are free to view, modify, and distribute the source code in accordance with that license. However, the name &quot;Rift Music App&quot;, its logos, and related branding assets are the property of the developers and may not be used without permission.
            </p>

            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>5. Disclaimer of Warranties</h3>
            <p>
              The App is provided on an &quot;AS IS&quot; and &quot;AS AVAILABLE&quot; basis, without warranties of any kind, whether express or implied. We do not warrant that the App will be uninterrupted, error-free, secure, or that any defects will be corrected. Furthermore, we cannot guarantee continued compatibility with YouTube&apos;s APIs or infrastructure.
            </p>

            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>6. Limitation of Liability</h3>
            <p>
              To the maximum extent permitted by applicable law, in no event shall the developers of Rift Music App be liable for any indirect, punitive, incidental, special, consequential, or exemplary damages, including without limitation damages for loss of profits, goodwill, use, data, or other intangible losses, that result from the use of, or inability to use, this App.
            </p>

            <h3 style={{ color: "var(--fg)", fontSize: "1.3rem", marginTop: 24 }}>7. Changes to Terms</h3>
            <p>
              We reserve the right, at our sole discretion, to modify or replace these Terms at any time. By continuing to access or use our App after any revisions become effective, you agree to be bound by the revised terms.
            </p>
          </div>
        </section>
      </main>

      <Footer />
    </>
  );
}
