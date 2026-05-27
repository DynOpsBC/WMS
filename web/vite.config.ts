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
        lpBrowser: "src/lpBrowser/index.html",
      },
      output: {
        entryFileNames: (chunk) => chunk.name === "pickBoard" ? "pickBoard.js" : chunk.name === "lpBrowser" ? "lpBrowser.js" : "assets/[name].js",
        assetFileNames: (asset) => {
          if (asset.name?.includes("lpBrowser") && asset.name.endsWith(".css")) return "lpBrowser.css";
          if (asset.name?.endsWith(".css")) return "pickBoard.css";
          return "assets/[name][extname]";
        },
      },
    },
  },
});
