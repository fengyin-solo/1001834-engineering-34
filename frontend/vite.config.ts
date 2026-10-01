import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'

// 配置只有一个来源：仓库根目录 .env（envDir 指向仓库根）。
// - 本地开发：根 .env 由 dev.sh / run.sh 注入，也由 Vite 直接读取；
// - 容器：docker-compose 用 env_file 注入根 .env；
// - 直接跑 npm run dev 且根 .env 缺失时，用与 .env.example 一致的默认值兜底。
export default defineConfig(({ mode }) => {
  const rootDir = fileURLToPath(new URL('..', import.meta.url))
  // loadEnv 会合并根 .env、.env.<mode> 与已存在的 process.env
  const env = { ...loadEnv(mode, rootDir), ...process.env }
  // ".env 里 KEY=" 得到空串，空串等价于"未配置"，回退默认值
  const pick = (...vals: Array<string | undefined>) => vals.find(v => v !== undefined && v !== '')

  const port = Number(pick(env.FRONTEND_PORT) ?? '5173')
  const proxyTarget = pick(env.VITE_PROXY_TARGET) ?? `http://127.0.0.1:${pick(env.BACKEND_PORT) ?? '8000'}`
  const host = pick(env.FRONTEND_HOST) ?? '127.0.0.1'

  return {
    // 让 import.meta.env.VITE_* 也从仓库根 .env 读取，避免出现第二份前端配置
    envDir: rootDir,
    plugins: [vue()],
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
      },
    },
    server: {
      host,
      port,
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
