/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  trailingSlash: true,
  distDir: "out",
  basePath: "/stocks",
  assetPrefix: "/stocks/",
  compiler: {
    styledComponents: true,
  },
};

export default nextConfig;
