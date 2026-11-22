/** @type {import('next').NextConfig} */
const nextConfig = {
  // static export -> the out/ folder uploads straight to a cPanel subdomain
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
