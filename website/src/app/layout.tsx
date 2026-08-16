import type { Metadata, Viewport } from "next";
import { Fraunces, Space_Grotesk } from "next/font/google";
import "./globals.css";
import Enhancements from "@/components/Enhancements";
import { asset } from "@/lib/asset";

const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-fraunces",
  display: "swap",
});
const grotesk = Space_Grotesk({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-grotesk",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://rift-music-app.vercel.app"),
  title: "Rift Music App — the Mac-native YouTube Music client",
  description:
    "Rift Music App is a beautiful, fully native macOS YouTube Music client. A Dynamic Island for your music, offline downloads, on-device lyrics, and local-only stats — the YouTube Music app the Mac never had.",
  icons: {
    icon: [
      { url: asset("/brand/favicon-32.png"), sizes: "32x32", type: "image/png" },
      { url: asset("/brand/favicon-16.png"), sizes: "16x16", type: "image/png" },
      { url: asset("/brand/rift-128.png"), sizes: "128x128", type: "image/png" },
    ],
    apple: asset("/brand/apple-touch-icon.png"),
  },
  alternates: { canonical: "/" },
  robots: { index: true, follow: true },
  keywords: ["Rift Music App", "YouTube Music", "macOS", "Mac music player", "SwiftUI", "Dynamic Island", "native"],
  applicationName: "Rift Music App",
  openGraph: {
    title: "Rift Music App — the Mac-native YouTube Music client",
    description: "All your music. One native Mac player.",
    type: "website",
    url: "https://rift-music-app.vercel.app",
    siteName: "Rift Music App",
    images: ["/brand/rift-256.png"],
  },
  twitter: {
    card: "summary_large_image",
    title: "Rift Music App — the Mac-native YouTube Music client",
    description: "All your music. One native Mac player.",
    images: ["/brand/rift-256.png"],
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f1ec" },
    { media: "(prefers-color-scheme: dark)", color: "#07080a" },
  ],
};

// pre-paint theme (no flash) + mark JS present
const themeScript = `(()=>{try{var t=localStorage.getItem("rift-theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t;}catch(e){}document.documentElement.classList.add("js");})();`;

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Rift Music App",
  applicationCategory: "MultimediaApplication",
  operatingSystem: "macOS 14+",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  description:
    "A native macOS YouTube Music client with a Dynamic Island, offline downloads, on-device lyrics and local-only stats.",
  url: "https://rift-music-app.vercel.app",
  license: "https://www.gnu.org/licenses/gpl-3.0.html",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-theme="auto" suppressHydrationWarning className={`${fraunces.variable} ${grotesk.variable}`}>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      </head>
      <body>
        {children}
        <Enhancements />
      </body>
    </html>
  );
}
