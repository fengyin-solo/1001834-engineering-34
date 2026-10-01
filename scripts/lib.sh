#!/usr/bin/env bash
# scripts/lib.sh —— 各编排脚本共用的工具函数：
#   彩色分步日志、命令重试、加载唯一配置源 .env、HTTP 健康检查、端口占用提示。
# 被 setup.sh / dev.sh / doctor.sh source 使用，不单独执行。

# 仓库根目录（本文件位于 <root>/scripts/）
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
mkdir -p "$LOG_DIR"

# 容器里挂载卷常触发 "detected dubious ownership"，自动登记为安全目录（仅本仓库）
if command -v git >/dev/null 2>&1 && [ -d "$ROOT_DIR/.git" ]; then
  git config --global --add safe.directory "$ROOT_DIR" >/dev/null 2>&1 || true
fi

# 终端不支持颜色时自动退化为纯文本
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_STEP="\033[1;36m"; C_OK="\033[1;32m"; C_WARN="\033[1;33m"; C_ERR="\033[1;31m"; C_OFF="\033[0m"
else
  C_STEP=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi

step() { printf "\n${C_STEP}▶ [%s] %s${C_OFF}\n" "$(date +%H:%M:%S)" "$*"; }
ok()   { printf "${C_OK}  ✓ %s${C_OFF}\n" "$*"; }
warn() { printf "${C_WARN}  ! %s${C_OFF}\n" "$*"; }
err()  { printf "${C_ERR}  ✗ %s${C_OFF}\n" "$*" >&2; }

# load_env：把根 .env 导出到当前进程；不覆盖已存在的环境变量，便于临时调试覆盖。
load_env() {
  local env_file="$ROOT_DIR/.env"
  if [ ! -f "$env_file" ]; then
    warn "未找到 .env，将使用 .env.example 的默认值；建议先执行: cp .env.example .env"
    env_file="$ROOT_DIR/.env.example"
  fi
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
  : "${BACKEND_PORT:=8000}"
  : "${FRONTEND_PORT:=5173}"
  : "${BACKEND_HOST:=127.0.0.1}"
  : "${FRONTEND_HOST:=127.0.0.1}"
  : "${APP_ENV:=local}"
}

# ensure_env_file：.env 不存在时从模板复制（幂等：已有 .env 绝不覆盖）
ensure_env_file() {
  if [ -f "$ROOT_DIR/.env" ]; then
    ok "配置文件 .env 已存在，保留现有内容不覆盖"
  else
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
    ok "已从 .env.example 创建 .env（可按需修改，重跑不会被覆盖）"
  fi
}

# ensure_venv <venv目录>：换机器/容器后旧 venv 的解释器往往是失效软链接，
# 检测到不可用就重建，避免把"环境损坏"误判成"缺依赖"。
ensure_venv() {
  local venv_dir="$1"
  if [ -x "$venv_dir/bin/python" ] && "$venv_dir/bin/python" -c "import sys" >/dev/null 2>&1; then
    ok "虚拟环境可用：$venv_dir（$($venv_dir/bin/python --version 2>&1)）"
    return 0
  fi
  if [ -e "$venv_dir" ]; then
    warn "检测到失效的 $venv_dir（常见于换机器/容器后软链接指向旧系统 Python），删除重建"
    rm -rf "$venv_dir"
  fi
  step "创建虚拟环境 $venv_dir"
  # 部分 Debian/Ubuntu 裁剪了 ensurepip：先常规建，失败则用 --without-pip + get-pip 兜底
  if ! python3 -m venv "$venv_dir"; then
    warn "常规 venv 创建失败（可能缺少 python3-venv/ensurepip），尝试 --without-pip + get-pip.py"
    python3 -m venv --without-pip "$venv_dir"
    local get_pip="$LOG_DIR/get-pip.py"
    if curl -fsS https://bootstrap.pypa.io/get-pip.py -o "$get_pip"; then
      "$venv_dir/bin/python" "$get_pip"
    else
      err "无法下载 get-pip.py（无网络？）。请安装系统包 python3-venv 后重试"
      return 1
    fi
  fi
  ok "虚拟环境已创建：$venv_dir"
}

# ensure_node_modules <前端目录>：跨机器残留的 node_modules 里原生二进制
# （esbuild/rollup）常是别的平台/架构，表现为 Exec format error / MODULE_NOT_FOUND。
# 用 esbuild 自检，不可用就整体重装。
ensure_node_modules() {
  local web_dir="$1"
  if [ -d "$web_dir/node_modules" ] && [ -x "$web_dir/node_modules/.bin/esbuild" ] \
     && (cd "$web_dir" && node_modules/.bin/esbuild --version >/dev/null 2>&1); then
    ok "node_modules 可用（esbuild 自检通过）"
    return 0
  fi
  if [ -d "$web_dir/node_modules" ]; then
    warn "node_modules 与当前系统不兼容（跨机器/架构残留，原生二进制失效），删除重装"
    rm -rf "$web_dir/node_modules"
  fi
  # 旧机器留下的 package-lock.json 可能锁定别的平台可选依赖（npm bug #4828）。
  # 只有"锁文件确实未纳入版本库"时才删除；git 不可用/状态不明时保守保留，避免误删。
  local lock_rel="${web_dir#$ROOT_DIR/}/package-lock.json"
  if [ -f "$web_dir/package-lock.json" ]; then
    if git -C "$ROOT_DIR" ls-files --error-unmatch "$lock_rel" >/dev/null 2>&1; then
      ok "保留已纳入版本库的 $lock_rel"
    else
      warn "删除未纳入版本库、可能锁定其他平台原生包的 $lock_rel"
      rm -f "$web_dir/package-lock.json"
    fi
  fi
  step "安装前端依赖（npm install，失败自动重试）"
  (cd "$web_dir" && retry 3 "npm install" -- npm install --no-audit --no-fund)
  if ! (cd "$web_dir" && node_modules/.bin/esbuild --version >/dev/null 2>&1); then
    err "前端原生依赖在当前平台仍不可用，请检查 node 架构：$(node -p 'process.platform+\"-\"+process.arch')"
    return 1
  fi
  ok "前端依赖就绪"
}

# retry <次数> <描述> -- <命令...>：失败按指数退避重试，用于装依赖/构建等易抖动步骤
retry() {
  local tries="$1"; shift
  local desc="$1"; shift
  [ "$1" = "--" ] && shift
  local n=1 delay=3
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$n" -ge "$tries" ]; then
      err "$desc 失败，已重试 $tries 次仍未成功"
      return 1
    fi
    warn "$desc 第 $n/$tries 次失败，${delay}s 后重试（构建失败可随时中断后重跑 setup，步骤可续）"
    sleep "$delay"
    n=$((n + 1)); delay=$((delay * 2))
  done
}

# http_wait <url> <秒数> [curl额外参数...]：轮询健康检查端点
http_wait() {
  local url="$1" timeout_s="$2"; shift 2
  local elapsed=0
  while [ "$elapsed" -lt "$timeout_s" ]; do
    if curl -fsS "$@" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1; elapsed=$((elapsed + 1))
  done
  return 1
}

# warn_port_used <端口>：端口已被占用时给出可读提示（不阻断，vite 可能自动换端口）
warn_port_used() {
  local port="$1"
  if port_in_use "$port"; then
    warn "端口 $port 已被占用（ss -ltnp / lsof -iTCP:$port 可查看）"
  fi
}

# port_in_use <端口>：优先用 python 自检（容器里常没有 lsof/ss），再退 ss
port_in_use() {
  local port="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$port" <<'PY'
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(0)
finally:
    s.close()
sys.exit(1)
PY
    return
  fi
  command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk '{print $4}' | grep -q "[:.]$port\$"
}

# 写一条带时间戳的运行日志
run_log() { printf "[%s] %s\n" "$(date '+%F %T')" "$*" >> "$LOG_DIR/setup.log"; }
