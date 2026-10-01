#!/usr/bin/env bash
# 本地前后端进程管理（开发者也可以继续用 make backend / make frontend 各自前台启动）。
#
# 用法：
#   ./scripts/dev.sh start    幂等启动（已在运行的服务不会重复拉起）
#   ./scripts/dev.sh status   查看进程与健康检查
#   ./scripts/dev.sh logs     跟随输出前后端日志（Ctrl-C 只退出查看，不停服务）
#   ./scripts/dev.sh stop     停止两个服务
#   ./scripts/dev.sh restart  重启
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

RUN_DIR="$ROOT_DIR/.run"
mkdir -p "$RUN_DIR"
BACKEND_PID="$RUN_DIR/backend.pid"
FRONTEND_PID="$RUN_DIR/frontend.pid"

load_env

is_alive() { local pidfile="$1"; [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

# 在独立进程组里运行命令并后台化，记录的 PID 即进程组长（=实际服务/ npm 进程），
# stop 时按 -PID 整组回收，避免 vite 子进程成孤儿继续占用端口。
spawn_grouped() {
  local pidfile="$1"; shift
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
  else
    "$@" &
  fi
  echo $! > "$pidfile"
}

start_backend() {
  if is_alive "$BACKEND_PID"; then
    ok "后端已在运行（PID $(cat "$BACKEND_PID")），跳过"
    return 0
  fi
  step "启动后端 ${BACKEND_HOST}:${BACKEND_PORT}"
  spawn_grouped "$BACKEND_PID" bash -c '
    cd "$1"
    set -a; [ -f "$2" ] && . "$2"; set +a
    exec .venv/bin/uvicorn app.main:app --host "$3" --port "$4"
  ' _ "$ROOT_DIR/backend" "$ROOT_DIR/.env" "$BACKEND_HOST" "$BACKEND_PORT" \
    >"$LOG_DIR/backend.log" 2>&1
}

start_frontend() {
  if is_alive "$FRONTEND_PID"; then
    ok "前端已在运行（PID $(cat "$FRONTEND_PID")），跳过"
    return 0
  fi
  step "启动前端 ${FRONTEND_HOST}:${FRONTEND_PORT}（代理 /api → ${VITE_PROXY_TARGET:-http://127.0.0.1:${BACKEND_PORT}}）"
  spawn_grouped "$FRONTEND_PID" bash -c '
    cd "$1"
    set -a; [ -f "$2" ] && . "$2"; set +a
    exec npm run dev
  ' _ "$ROOT_DIR/frontend" "$ROOT_DIR/.env" \
    >"$LOG_DIR/frontend.log" 2>&1
}

cmd_start() {
  [ -d "$ROOT_DIR/backend/.venv" ] || { err "后端依赖未安装，请先运行 ./scripts/setup.sh local"; exit 1; }
  [ -d "$ROOT_DIR/frontend/node_modules" ] || { err "前端依赖未安装，请先运行 ./scripts/setup.sh local"; exit 1; }
  start_backend
  if http_wait "http://127.0.0.1:${BACKEND_PORT}/api/health" 30; then
    ok "后端就绪：http://127.0.0.1:${BACKEND_PORT}/api/health"
  else
    err "后端 30s 内未就绪，见日志：$LOG_DIR/backend.log"; exit 1
  fi
  start_frontend
  if http_wait "http://127.0.0.1:${FRONTEND_PORT}/" 30; then
    ok "前端就绪：http://127.0.0.1:${FRONTEND_PORT}/"
  else
    err "前端 30s 内未就绪，见日志：$LOG_DIR/frontend.log"; exit 1
  fi
}

cmd_stop() {
  for name in backend frontend; do
    pidfile="$RUN_DIR/$name.pid"
    if is_alive "$pidfile"; then
      pid="$(cat "$pidfile")"
      # npm 会派生 vite 子进程，按进程组停止，避免孤儿占用端口
      kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
      ok "$name 已停止（PID $pid）"
    else
      ok "$name 未在运行"
    fi
    rm -f "$pidfile"
  done
}

cmd_status() {
  for pair in "backend:$BACKEND_PID:http://127.0.0.1:${BACKEND_PORT}/api/health" \
              "frontend:$FRONTEND_PID:http://127.0.0.1:${FRONTEND_PORT}/"; do
    name="${pair%%:*}"; rest="${pair#*:}"; pidfile="${rest%%:*}"; url="${rest#*:}"
    if is_alive "$pidfile"; then
      if curl -fsS "$url" >/dev/null 2>&1; then
        printf "${C_OK}● %-8s PID %-6s 健康  %s${C_OFF}\n" "$name" "$(cat "$pidfile")" "$url"
      else
        printf "${C_WARN}● %-8s PID %-6s 进程在但健康检查未通过${C_OFF}\n" "$name" "$(cat "$pidfile")"
      fi
    else
      printf "${C_ERR}○ %-8s 未运行${C_OFF}\n" "$name"
    fi
  done
}

case "${1:-start}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  restart) cmd_stop; cmd_start ;;
  logs)
    echo "跟随输出前后端日志（Ctrl-C 退出查看，不影响服务）："
    tail -n 40 -f "$LOG_DIR/backend.log" "$LOG_DIR/frontend.log"
    ;;
  *) err "用法：$0 [start|stop|status|restart|logs]"; exit 2 ;;
esac
