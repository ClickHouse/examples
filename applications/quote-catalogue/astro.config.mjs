import { defineConfig } from "astro/config";
import node from "@astrojs/node";
import preact from "@astrojs/preact";
import tailwindcss from "@tailwindcss/vite";
export default defineConfig({
  output: "server",
  adapter: node({ mode: "standalone" }),
  integrations: [preact()],
  vite: { plugins: [tailwindcss()] },
});
