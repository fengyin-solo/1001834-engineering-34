#!/usr/bin/env bash
# 容器入口：先建库/幂等灌示例数据，再起 API。
# 数据落在挂载卷里；灌数只补空模块，重启容器不会覆盖已有改动。
set -euo pipefail
cd /srv/app

echo "[backend] 检查数据库与示例数据（DATABASE_PATH=${DATABASE_PATH:-data/app.sqlite3}）"
python -m app.bootstrap seed

echo "[backend] 启动 uvicorn：${BACKEND_HOST:-0.0.0.0}:${BACKEND_PORT:-8000}"
exec uvicorn app.main:app --host "${BACKEND_HOST:-0.0.0.0}" --port "${BACKEND_PORT:-8000}"
