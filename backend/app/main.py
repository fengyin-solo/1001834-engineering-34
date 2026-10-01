"""城市地下管网巡检养护平台 后端服务入口。

启动（本地默认 127.0.0.1:8000，容器内由环境变量覆盖为 0.0.0.0）：
    uvicorn app.main:app --host 127.0.0.1 --port 8000
健康检查：GET /api/health

启动时会幂等建库并补示例数据：已有数据的模块一律跳过，重启不重复灌入。
"""
from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import bootstrap
from app.config import settings
from app.routers import ROUTERS
from app.store import store

logger = logging.getLogger("uvicorn.error")

app = FastAPI(title=settings.app_name, version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for module in ROUTERS:
    app.include_router(module.router)


@app.on_event("startup")
def _prepare_data() -> None:
    seeded, skipped = bootstrap.prepare()
    if seeded:
        logger.info("已灌入示例数据：%s 个模块；跳过 %s 个已有数据的模块", len(seeded), len(skipped))
    else:
        logger.info("示例数据检查完成：全部 %s 个模块已有数据，未重复写入", len(skipped))


@app.get("/api/health")
def health() -> dict[str, object]:
    """健康检查：确认服务已经监听、库表与示例数据已经就绪。"""
    return {
        "ok": True,
        "app": settings.app_name,
        "env": settings.env,
        "storage": "memory" if settings.db_path == ":memory:" else "sqlite",
        "modules": len(store.module_names()),
    }


@app.get("/api/overview")
def overview() -> dict[str, object]:
    """运营概览：把各业务模块的待处理量汇总成看板卡片。"""
    return store.overview()
