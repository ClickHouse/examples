import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
const proxy = {
  "/collab": {
    target: "ws://127.0.0.1:1234",
    ws: true,
    changeOrigin: false,
    rewrite: () => "/",
  },
};
export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    allowedHosts: ["127.0.0.1"],
    cors: false,
    proxy,
  },
  preview: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    allowedHosts: ["127.0.0.1"],
    cors: false,
    proxy,
  },
});
