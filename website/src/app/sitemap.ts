import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const base = "https://rift-music-app.vercel.app";
  return [
    { url: `${base}/`, changeFrequency: "monthly", priority: 1 },
    { url: `${base}/changelog`, changeFrequency: "monthly", priority: 0.8 },
    { url: `${base}/privacy`, changeFrequency: "yearly", priority: 0.5 },
    { url: `${base}/terms`, changeFrequency: "yearly", priority: 0.5 },
  ];
}
