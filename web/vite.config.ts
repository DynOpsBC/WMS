import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "../al/src/ControlAddIn/Resources/",
    emptyOutDir: true,
    sourcemap: true,
    rollupOptions: {
      input: {
        main: "index.html",
        pickBoard: "src/pickBoard/index.html",
      },
      output: {
        entryFileNames: (chunk) => chunk.name === "pickBoard" ? "pickBoard.js" : "assets/[name].js",
        assetFileNames: (asset) => asset.name?.endsWith(".css") ? "pickBoard.css" : "assets/[name][extname]",
      },
    },
  },
});
