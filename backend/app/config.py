"""运行配置：端口、监听地址、跨域、数据库都只从环境变量读取。

配置的唯一来源是仓库根目录的 ``.env``（由 scripts/lib.sh 注入进程，
容器里由 docker-compose 传入）；这里只负责解析并给出本地开发的默认值，
不再在代码里写死业务环境相关的地址。
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

_BACKEND_DIR = Path(__file__).resolve().parent.parent


def _default_db_path() -> str:
    return str(_BACKEND_DIR / "data" / "app.sqlite3")


def _parse_origins(raw: str | None) -> list[str]:
    """逗号/空白分隔的来源串；为空时回退到当前前端端口的本机地址。"""
    if raw and raw.strip():
        return [item.strip() for item in raw.replace(",", " ").split() if item.strip()]
    port = os.environ.get("FRONTEND_PORT", "5173")
    return [f"http://127.0.0.1:{port}", f"http://localhost:{port}"]


@dataclass(frozen=True)
class Settings:
    app_name: str = field(default_factory=lambda: os.environ.get("APP_NAME", "城市地下管网巡检养护平台"))
    env: str = field(default_factory=lambda: os.environ.get("APP_ENV", "local"))
    host: str = field(default_factory=lambda: os.environ.get("BACKEND_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: int(os.environ.get("BACKEND_PORT", "8000")))
    db_path: str = field(
        default_factory=lambda: os.environ.get("DATABASE_PATH") or _default_db_path()
    )
    allowed_origins: list[str] = field(default_factory=lambda: _parse_origins(os.environ.get("CORS_ORIGINS")))
    page_size_default: int = 20
    page_size_max: int = 200


settings = Settings()
