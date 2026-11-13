import { defineConfig } from "vite";
import { nodePolyfills } from "vite-plugin-node-polyfills";

export default defineConfig({
  base: "./",
  plugins: [
    nodePolyfills({
      globals: { Buffer: true, global: true, process: true },
    }),
  ],
  build: {
    outDir: "dist",
    target: "es2020",
  },
  server: { host: true, port: 5173 },
});
