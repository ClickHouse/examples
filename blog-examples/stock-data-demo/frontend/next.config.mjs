import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("..", import.meta.url));
const development = process.env.NODE_ENV === "development";
/** @type {import('next').NextConfig} */
const nextConfig = {
  ...(!development ? { output: "export" } : {}),
  trailingSlash: !development,
  agentRules: false,
  basePath: "/stocks",
  turbopack: { root },
  compiler: { styledComponents: true },
  ...(development ? { async rewrites() {
    const backend = `http://127.0.0.1:${process.env.BACKEND_PORT || 34567}`;
    return [
      { source: "/api/:path*", destination: `${backend}/api/:path*`, basePath: false },
      { source: "/metrics", destination: `${backend}/metrics`, basePath: false },
      { source: "/control/:path*", destination: `${backend}/control/:path*`, basePath: false },
    ];
  } } : {}),
};
export default nextConfig;
