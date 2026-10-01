#!/usr/bin/env bash
# 一条命令完成全部准备动作：预检 → 配置 → 装依赖 → 建库灌数 →（构建）→ 启动 → 健康检查。
#
# 用法：
#   ./scripts/setup.sh                自动选择：有 docker compose 用容器，否则本地进程
#   ./scripts/setup.sh local          强制本地（venv + npm + 后台进程）
#   ./scripts/setup.sh docker         强制容器（docker compose up --build）
#   ./scripts/setup.sh --no-start     只做准备与构建，不启动服务
#   ./scripts/setup.sh doctor         只做环境预检（见 doctor.sh）
#
# 幂等：可随意重复执行。已有 .env、已装依赖、已灌数据、已构建镜像、已启动的服务都会跳过。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

MODE="auto"; START=1
for arg in "$@"; do
  case "$arg" in
    local|docker) MODE="$arg" ;;
    --no-start)   START=0 ;;
    doctor)       exec "$SCRIPT_DIR/doctor.sh" ;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0 ;;
    *) err "未知参数：$arg"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- 1. 预检
step "1/6 环境预检"
run_log "setup start mode=$MODE start=$START"
check_tool() { command -v "$1" >/dev/null 2>&1; }

COMPOSE=""
if check_tool docker && docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif check_tool docker-compose; then
  COMPOSE="docker-compose"
fi

if [ "$MODE" = "auto" ]; then
  MODE="$([ -n "$COMPOSE" ] && echo docker || echo local)"
fi
ok "运行模式：$MODE $([ -n "$COMPOSE" ] && echo "（检测到 compose）" || echo "（未检测到 docker compose）")"

if [ "$MODE" = "docker" ]; then
  if [ -z "$COMPOSE" ]; then
    err "未找到 docker compose。可选：安装 Docker，或改用 ./scripts/setup.sh local"
    exit 1
  fi
else
  missing=0
  for tool in python3 node npm; do
    if check_tool "$tool"; then ok "$tool：$($tool --version 2>&1 | head -1)"; else err "缺少 $tool，请先安装"; missing=1; fi
  done
  [ "$missing" = 1 ] && exit 1
fi

# ---------------------------------------------------------------- 2. 配置
step "2/6 配置文件（唯一来源：.env）"
ensure_env_file
load_env
ok "BACKEND ${BACKEND_HOST}:${BACKEND_PORT} / FRONTEND ${FRONTEND_HOST}:${FRONTEND_PORT} / APP_ENV=${APP_ENV}"

# ---------------------------------------------------------------- 3/4 分模式准备
if [ "$MODE" = "docker" ]; then
  step "3/6 构建镜像（失败会自动重试；也可直接重跑本命令，层缓存会复用）"
  warn_port_used "$BACKEND_PORT"; warn_port_used "$FRONTEND_PORT"
  retry 2 "镜像构建" -- $COMPOSE build
  ok "镜像构建完成"

  step "4/6 数据库准备"
  ok "容器启动时入口脚本会自动建库并幂等灌入示例数据（数据卷 backend-data 持久化）"

  if [ "$START" = 1 ]; then
    step "5/6 启动容器"
    $COMPOSE up -d
    ok "容器已后台启动：$COMPOSE logs -f 可查看实时日志"

    step "6/6 健康检查"
    if http_wait "http://127.0.0.1:${BACKEND_PORT}/api/health" 60; then
      ok "后端健康：http://127.0.0.1:${BACKEND_PORT}/api/health"
    else
      err "后端 60s 内未就绪，排查：$COMPOSE ps 与 $COMPOSE logs backend（环境变量见容器内 env）"
      exit 1
    fi
    if http_wait "http://127.0.0.1:${FRONTEND_PORT}/" 60; then
      ok "前端健康：http://127.0.0.1:${FRONTEND_PORT}/"
    else
      err "前端 60s 内未就绪，排查：$COMPOSE ps 与 $COMPOSE logs frontend"
      exit 1
    fi
    printf "\n${C_OK}全部就绪${C_OFF}：浏览器打开 http://127.0.0.1:${FRONTEND_PORT}/\n"
  else
    ok "已跳过启动（--no-start）。启动：$COMPOSE up -d"
  fi
  exit 0
fi

# ---- 本地模式 ----
step "3/6 准备后端虚拟环境与依赖（失效的旧 .venv 会自动重建；失败可重跑）"
ensure_venv "$ROOT_DIR/backend/.venv"
retry 3 "安装 Python 依赖" -- "$ROOT_DIR/backend/.venv/bin/pip" install -q --disable-pip-version-check -r "$ROOT_DIR/backend/requirements.txt"
ok "后端依赖就绪"

step "4/6 准备前端依赖（跨机器/架构不兼容的 node_modules 会自动重装；失败可重跑）"
ensure_node_modules "$ROOT_DIR/frontend"

step "5/6 建库与示例数据（幂等：已有数据的模块不会重复写入）"
(cd "$ROOT_DIR/backend" && .venv/bin/python -m app.bootstrap seed)
(cd "$ROOT_DIR/backend" && .venv/bin/python -m app.bootstrap status)

if [ "$START" = 1 ]; then
  step "6/6 启动本地服务（后台运行，日志在 logs/，PID 在 .run/）"
  warn_port_used "$BACKEND_PORT"; warn_port_used "$FRONTEND_PORT"
  "$SCRIPT_DIR/dev.sh" start
  printf "\n${C_OK}全部就绪${C_OFF}：http://127.0.0.1:${FRONTEND_PORT}/\n"
  echo "  查看状态：./scripts/dev.sh status | 日志：./scripts/dev.sh logs | 停止：./scripts/dev.sh stop"
else
  ok "已跳过启动（--no-start）。手动启动：make backend / make frontend（原习惯保留）"
fi
