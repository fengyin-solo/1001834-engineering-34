#!/usr/bin/env bash
# 本地起后端的标准方式：依赖就绪后按根目录 .env 的地址端口起 uvicorn。
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
.venv/bin/pip install -q -r requirements.txt
# 地址端口只从配置读，不在这里写死
read -r HOST PORT <<< "$(.venv/bin/python -c 'from app.config import settings; print(settings.host, settings.port)')"
exec .venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT"
