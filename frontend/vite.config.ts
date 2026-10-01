import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'

// 配置只以仓库根目录的 .env 为准：npm run dev、npm run build、容器启动都读这一份。
// 取值优先级：进程环境变量（容器注入）> 根目录 .env > 默认值。
const envDir = fileURLToPath(new URL('..', import.meta.url))

export default defineConfig(({ mode }) => {
  const fileEnv = loadEnv(mode, envDir, '')
  const read = (key: string, fallback = ''): string =>
    process.env[key] || fileEnv[key] || fallback

  // 代理目标未显式配置时按后端端口自动生成，改端口不用同时改两处
  const proxyTarget = read('VITE_PROXY_TARGET') || `http://127.0.0.1:${read('BACKEND_PORT', '8000')}`

  return {
    // import.meta.env（如 VITE_API_BASE）同样从根目录 .env 读取
    envDir,
    plugins: [vue()],
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
      },
    },
    server: {
      host: read('FRONTEND_HOST', '127.0.0.1'),
      port: Number(read('FRONTEND_PORT', '5173')),
      // 关掉自动打开页面：起服务时只打印地址，不拉起浏览器
      open: false,
      strictPort: false,
      proxy: {
        '/api': {
          target: proxyTarget,
          changeOrigin: true,
        },
      },
    },
    build: {
      outDir: 'dist',
      sourcemap: false,
    },
  }
})
