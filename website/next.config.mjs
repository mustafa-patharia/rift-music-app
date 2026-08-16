/** @type {import('next').NextConfig} */
// Deployed on Vercel. No static export, no basePath, no telemetry.
const nextConfig = {
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default nextConfig;
