import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const proxy = {
  "/api": {
    target: "http://127.0.0.1:3000",
    changeOrigin: false,
    rewrite: (path: string) => path.replace(/^\/api(?=\/|$)/, ""),
  },
};

export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    allowedHosts: ["localhost", "127.0.0.1"],
    cors: false,
    proxy,
  },
  preview: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    allowedHosts: ["localhost", "127.0.0.1"],
    cors: false,
    proxy,
  },
});
