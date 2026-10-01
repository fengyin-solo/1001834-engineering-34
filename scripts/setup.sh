#!/usr/bin/env bash
# 一条命令完成全部准备动作：工具链检查、配置文件、前后端依赖、示例数据、自检。
#
# 设计原则：
#   - 幂等：重复执行不覆盖 .env、不重置已有数据、已装好的依赖自动跳过
#   - 可续跑：任何一步失败，修复后重跑 make setup 即可，已完成步骤不会重做
#   - 可读懂：每一步都打印做了什么、结果如何；失败时给出可能原因与处理建议
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STEP_TOTAL=6
step_no=0

step() {
  step_no=$((step_no + 1))
  echo ""
  echo "==> [${step_no}/${STEP_TOTAL}] $1"
}

ok()   { echo "  ✓ $1"; }
skip() { echo "  - $1（跳过）"; }
fail() {
  echo "  ✗ $1" >&2
  if [ $# -ge 2 ]; then
    echo "    处理建议：$2" >&2
  fi
  echo "" >&2
  echo "准备流程未完成。修复上面的问题后重新运行 make setup 即可，已完成的步骤会自动跳过。" >&2
  exit 1
}

# 依赖安装类命令允许重试，抵御网络抖动；重试都失败才报错
retry() {
  local desc="$1"
  shift
  local attempt
  for attempt in 1 2 3; do
    if "$@"; then
      return 0
    fi
    echo "  ! ${desc}：第 ${attempt} 次尝试失败" >&2
    [ "$attempt" -lt 3 ] && sleep 2
  done
  return 1
}

# ---------- 1. 工具链 ----------
step "检查工具链"
missing=0
for tool in python3 node npm; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool 就绪（$(command -v "$tool")）"
  else
    echo "  ✗ 未找到 $tool" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || fail "缺少必要工具" "安装 python3(>=3.10)、node(>=18)、npm 后重跑 make setup"

# ---------- 2. 配置文件 ----------
step "准备配置文件（唯一配置来源：.env）"
if [ -f .env ]; then
  skip ".env 已存在，保留现有配置"
else
  cp .env.example .env
  ok "已从 .env.example 生成 .env，后续改配置只动这一个文件"
fi

# 创建 venv；系统缺 ensurepip（如 Debian 未装 python3-venv）时退化为手动引导 pip
create_venv() {
  if python3 -m venv backend/.venv 2>/dev/null; then
    return 0
  fi
  echo "  ! 标准方式创建 venv 失败（系统缺 ensurepip），改用 --without-pip + get-pip.py 引导"
  rm -rf backend/.venv
  python3 -m venv --without-pip backend/.venv || return 1
  local get_pip
  get_pip="$(mktemp)"
  if curl -fsSL --retry 2 --max-time 60 https://bootstrap.pypa.io/get-pip.py -o "$get_pip" \
    && backend/.venv/bin/python "$get_pip" -q; then
    rm -f "$get_pip"
    return 0
  fi
  rm -f "$get_pip"
  return 1
}

# ---------- 3. 后端依赖 ----------
step "准备后端依赖（backend/.venv）"
if [ -d backend/.venv ] && backend/.venv/bin/python -m pip --version >/dev/null 2>&1; then
  skip "backend/.venv 已存在且可用"
else
  if [ -d backend/.venv ]; then
    echo "  ! 现有 backend/.venv 无法运行或不完整（可能是在别的机器上创建的），自动重建"
    rm -rf backend/.venv
  fi
  if create_venv; then
    ok "已创建 backend/.venv"
  else
    fail "创建 Python 虚拟环境失败" "Debian/Ubuntu 可装 python3-venv 后重跑；或检查网络（引导 pip 需要访问 bootstrap.pypa.io）"
  fi
fi
if retry "安装后端依赖" backend/.venv/bin/pip install -q -r backend/requirements.txt; then
  ok "后端依赖就绪"
else
  fail "后端依赖安装失败" "检查网络或 pip 源配置后重跑 make setup"
fi

# ---------- 4. 前端依赖 ----------
step "准备前端依赖（frontend/node_modules）"

# node_modules 不能跨平台复用：从别的机器拷贝来时平台相关的原生模块（如 rollup）会缺失，
# 且 npm 对可选依赖有已知缺陷（npm/cli#4828），光跑 npm install 修不好。
# 所以健康检查不看目录是否存在，而是让关键依赖真的加载一次。
rollup_loadable() { (cd frontend && node -e "require('rollup')") >/dev/null 2>&1; }

frontend_deps_healthy() {
  [ -d frontend/node_modules ] || return 1
  [ frontend/package.json -ot frontend/node_modules ] || return 1
  rollup_loadable
}

if frontend_deps_healthy; then
  skip "node_modules 已存在且可用"
else
  if [ -d frontend/node_modules ]; then
    echo "  ! 现有 node_modules 不可用（可能是在别的平台安装的），自动修复"
  fi
  if retry "安装前端依赖" npm --prefix frontend install && rollup_loadable; then
    ok "前端依赖就绪"
  else
    echo "  ! 常规安装后依赖仍不可用，按 npm 官方建议清理后重装"
    rm -rf frontend/node_modules
    # lock 文件若被 git 跟踪则保留，只删本机生成的
    git ls-files --error-unmatch frontend/package-lock.json >/dev/null 2>&1 || rm -f frontend/package-lock.json
    if retry "重装前端依赖" npm --prefix frontend install && rollup_loadable; then
      ok "前端依赖就绪（已清理重装）"
    else
      fail "前端依赖安装失败" "检查网络或 npm registry 配置后重跑 make setup"
    fi
  fi
fi

# ---------- 5. 示例数据 ----------
step "初始化示例数据（幂等，不覆盖已有数据）"
if (cd backend && .venv/bin/python -m app.seed); then
  :
else
  fail "示例数据初始化失败" "查看上方输出；确认要重建时可执行 cd backend && .venv/bin/python -m app.seed --reset"
fi

# ---------- 6. 自检 ----------
step "启动前自检（缺依赖、配置错误、数据异常会分类列出）"
if (cd backend && .venv/bin/python -m app.doctor); then
  :
else
  fail "自检未通过" "按上方每条 ✗ 的建议逐项处理"
fi

echo ""
echo "全部准备完成 ✓"
echo "  后端：make backend   （或 cd backend && ./run.sh）"
echo "  前端：make frontend  （或 cd frontend && npm run dev）"
