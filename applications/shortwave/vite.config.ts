import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import { nitro } from "nitro/vite";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig(({ mode }) => ({
  plugins: mode === "workers"
    ? [cloudflare({ viteEnvironment: { name: "ssr" } }), tanstackStart(), viteReact()]
    : [tanstackStart(), nitro(), viteReact()],
  // Click UI's ESM entry imports CSS; Vite must transform it during SSR in dev.
  ssr: { noExternal: ["@clickhouse/click-ui"] },
}));
