# 前端构建与开发容器。配置只来自环境变量（docker-compose 从根 .env 注入）。
FROM node:20-alpine
WORKDIR /srv/web

# 优先只拷清单，利用镜像层缓存；安装失败（--fetch-retries）重跑 docker build 可续装
COPY package.json ./
RUN npm install --fetch-retries=5 --fetch-retry-maxtimeout=60000

COPY . .

ENV FRONTEND_HOST=0.0.0.0 \
    FRONTEND_PORT=5173

EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# Vite dev server 就绪检查：alpine 自带 wget，不需要额外装 curl
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=5 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${FRONTEND_PORT:-5173}/" || exit 1
