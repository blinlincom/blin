import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: { port: 5173 },
  build: { outDir: 'dist', sourcemap: false },
  test: { environment: 'jsdom' },
})
