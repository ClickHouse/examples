import { defineConfig } from "vite";
import { sveltekit } from "@sveltejs/kit/vite";
import adapter from "@sveltejs/adapter-node";
export default defineConfig({ plugins: [sveltekit({ adapter: adapter() })] });
