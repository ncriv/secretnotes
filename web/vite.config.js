import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// The sync server (server/secretnotes_server.py) defaults to 127.0.0.1:8787.
// In dev, proxy the API to it so the app can run same-origin. In production the
// built app in dist/ is meant to be served by that same server.
const API = process.env.SECRETNOTES_API || 'http://127.0.0.1:8787';

export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: {
      '/v1': { target: API, changeOrigin: true },
      '/healthz': { target: API, changeOrigin: true },
    },
  },
  build: { outDir: 'dist', emptyOutDir: true },
});
