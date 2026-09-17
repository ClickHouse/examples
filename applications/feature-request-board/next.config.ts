import type { NextConfig } from "next";

const config: NextConfig = {
  poweredByHeader: false,
  experimental: { serverActions: { bodySizeLimit: "64kb" } },
};
export default config;
