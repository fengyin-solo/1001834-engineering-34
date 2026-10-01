"""城市地下管网巡检养护平台 后端服务入口。

启动：cd backend && ./run.sh（地址端口以根目录 .env 为准）
健康检查：GET /api/health
"""
from __future__ import annotations

from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import ROUTERS
from app.store import store

app = FastAPI(title="城市地下管网巡检养护平台", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


@app.middleware("http")
async def persist_store_after_write(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """写请求完成后把数据落盘：重启、换机器、重建容器都不丢已录入的数据。"""
    response = await call_next(request)
    if request.method in _WRITE_METHODS and response.status_code < 500:
        store.persist()
    return response

for module in ROUTERS:
    app.include_router(module.router)


@app.get("/api/health")
def health() -> dict[str, object]:
    """健康检查：确认服务已经监听、示例数据已经就绪。"""
    return {"ok": True, "app": settings.app_name, "modules": len(store.module_names())}


@app.get("/api/overview")
def overview() -> dict[str, object]:
    """运营概览：把各业务模块的待处理量汇总成看板卡片。"""
    return store.overview()
