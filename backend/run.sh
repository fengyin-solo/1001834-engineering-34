#!/usr/bin/env bash
# 后端本地启动脚本（开发者原有习惯保留：cd backend && ./run.sh）。
# 会自动加载仓库根目录 .env；跨机器/容器后失效的 .venv 会自动重建；依赖安装失败可重复执行。
set -euo pipefail
cd "$(dirname "$0")"

# 加载唯一配置来源：仓库根目录 .env（不存在时使用 config.py 里的默认值）
if [ -f ../.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ../.env
  set +a
fi

BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-8000}"

# 自检虚拟环境：解释器软链接失效（换机器/容器后常见）则自动重建
if [ ! -x .venv/bin/python ] || ! .venv/bin/python -c "import sys" >/dev/null 2>&1; then
  if [ -e .venv ]; then
    echo "[backend] 检测到失效的 .venv（软链接指向旧系统 Python），删除重建"
    rm -rf .venv
  fi
  echo "[backend] 首次运行，创建虚拟环境 .venv"
  if ! python3 -m venv .venv; then
    # Debian/Ubuntu 裁剪了 ensurepip 时的兜底
    python3 -m venv --without-pip .venv
    tmp_pip="$(mktemp)"
    curl -fsS https://bootstrap.pypa.io/get-pip.py -o "$tmp_pip"
    .venv/bin/python "$tmp_pip"; rm -f "$tmp_pip"
  fi
fi

# 幂等且可重试：装失败再跑一次本脚本即可，不会污染已装好的依赖
echo "[backend] 同步依赖 requirements.txt"
.venv/bin/pip install -q --disable-pip-version-check -r requirements.txt

# 启动前幂等建库/补示例数据（也可手工：.venv/bin/python -m app.bootstrap status）
.venv/bin/python -m app.bootstrap seed

exec .venv/bin/uvicorn app.main:app --host "${BACKEND_HOST}" --port "${BACKEND_PORT}"
