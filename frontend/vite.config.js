import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  // use an alias for base which should be replaced in built artifacts before production usage
  // This way URLs with path may become usable like for nginx locations
  base: process.env.NODE_ENV === 'production' ? '/REPLACE_PUBLIC_PATH_BEFORE/' : '/',
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    cssMinify: 'esbuild', // Lightning CSS fails on Bulma v1 media queries
    rolldownOptions: {
      output: {
        // Keep js/ and css/ directories so the Docker startup sed script (run-movex-cdc.sh) works unchanged
        entryFileNames: 'js/[name]-[hash].js',
        chunkFileNames: 'js/[name]-[hash].js',
        assetFileNames: 'css/[name]-[hash][extname]',
      },
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./tests/unit/vueSetup.js'],
  },
  server: {
    host: '0.0.0.0', // listen on all interfaces (required for Docker)
    port: 8080,
    strictPort: true, // fail if the configured port is already in use
    open: false, // do not open the default browser
  },
});
