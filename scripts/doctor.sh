#!/usr/bin/env bash
# 环境体检：容器里起不来时，先用它分清是"缺工具/依赖"还是"环境变量/端口"问题。
# 用法：./scripts/setup.sh doctor  或  ./scripts/doctor.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

fail=0
step "工具链"
for tool in python3 node npm curl; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool -> $($tool --version 2>&1 | head -1)"
  else
    warn "$tool 未安装（本地模式需要 python3/node/npm；健康检查需要 curl）"; fail=1
  fi
done
if docker info >/dev/null 2>&1; then
  ok "docker 守护进程可用（$(docker --version)）"
  docker compose version >/dev/null 2>&1 && ok "docker compose 可用（$(docker compose version | head -1)）" \
    || warn "docker compose 插件不可用，容器模式将无法使用"
else
  warn "docker 不可用或守护进程未运行（只能走 local 模式，不影响本地开发）"
fi

step "配置文件（唯一来源 .env）"
if [ -f "$ROOT_DIR/.env" ]; then
  ok ".env 存在"
  load_env
  # 检查后端自己能否解析到关键变量
  ( cd "$ROOT_DIR/backend" && python3 - <<'PY'
import os, sys
sys.path.insert(0, ".")
from app.config import settings
print(f"  后端解析：host={settings.host} port={settings.port} db={settings.db_path}")
print(f"  CORS 放行：{', '.join(settings.allowed_origins)}")
PY
  ) 2>/dev/null || warn "后端配置解析失败（可能依赖未安装，先跑 setup）"
else
  warn ".env 不存在（setup.sh 会自动从 .env.example 复制）"; fail=1
fi

step "依赖目录"
[ -d "$ROOT_DIR/backend/.venv" ] && ok "backend/.venv 已就绪" || warn "backend/.venv 缺失（setup local 会创建）"
[ -d "$ROOT_DIR/frontend/node_modules" ] && ok "frontend/node_modules 已就绪" || warn "frontend/node_modules 缺失（setup local 会安装）"

step "数据持久化"
if [ -d "$ROOT_DIR/backend/.venv" ]; then
  ( cd "$ROOT_DIR/backend" && .venv/bin/python -m app.bootstrap status )
else
  warn "跳过数据库检查（.venv 未就绪）"
fi

step "端口占用"
load_env
for port in "$BACKEND_PORT" "$FRONTEND_PORT"; do
  if port_in_use "$port"; then
    warn "$port 已被监听（ss -ltnp 可查看具体进程）"
  else
    ok "端口 $port 空闲"
  fi
done

step "运行中的服务"
"$SCRIPT_DIR/dev.sh" status || true

if [ "$fail" = 0 ]; then
  printf "\n${C_OK}体检通过${C_OFF}：可执行 ./scripts/setup.sh 一键准备并启动\n"
else
  printf "\n${C_WARN}体检有告警项（见上），修复后重跑本命令${C_OFF}\n"
fi
