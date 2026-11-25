// SPDX-License-Identifier: GPL-3.0-or-later
// 1200×630 social card, generated at build time by Next's ImageResponse.
import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const dynamic = "force-static";
export const alt = "Rift Music App: the native YouTube Music app for Mac";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage() {
  const icon = await readFile(join(process.cwd(), "public/brand/rift-256.png"));
  const src = `data:image/png;base64,${icon.toString("base64")}`;
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%", height: "100%", display: "flex", flexDirection: "column",
          justifyContent: "center", padding: "0 96px", color: "#fff",
          background: "radial-gradient(900px 520px at 85% 15%, rgba(255,90,60,.45), transparent 60%), radial-gradient(700px 480px at 10% 110%, rgba(255,47,58,.30), transparent 60%), #07080a",
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={src} width={128} height={128} alt="" style={{ borderRadius: 28 }} />
        <div style={{ marginTop: 44, display: "flex", flexDirection: "column", fontSize: 76, fontWeight: 700, letterSpacing: -2, lineHeight: 1.05 }}>
          <span>YouTube Music,</span>
          <span>made for the Mac.</span>
        </div>
        <div style={{ marginTop: 24, fontSize: 32, color: "rgba(245,245,247,.64)" }}>
          Rift Music App · native · free · open source
        </div>
      </div>
    ),
    size,
  );
}
