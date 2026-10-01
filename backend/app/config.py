"""运行配置：端口、跨域、数据文件。

所有取值只以仓库根目录的 .env 为准（进程环境变量优先，容器靠它注入），
本地开发、启动脚本与容器统一从这一处读，不再各自硬编码。
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT_DIR / ".env"


def _load_env_file(path: Path) -> dict[str, str]:
    """解析 KEY=VALUE 行，忽略注释与空行；不依赖第三方库，保证自检脚本也能用。"""
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        values[key.strip()] = raw.strip().strip('"').strip("'")
    return values


_FILE_ENV = _load_env_file(ENV_FILE)


def _env(key: str, default: str = "") -> str:
    """进程环境变量优先，其次根目录 .env，最后默认值。"""
    return os.environ.get(key) or _FILE_ENV.get(key) or default


def _env_int(key: str, default: int) -> int:
    raw = _env(key)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        raise ValueError(f"配置项 {key} 需要整数，当前值 {raw!r}（来源：环境变量或 {ENV_FILE}）") from None


def _split_csv(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    app_name: str = "城市地下管网巡检养护平台"
    env: str = "local"
    host: str = "127.0.0.1"
    port: int = 8000
    frontend_port: int = 5173
    allowed_origins: list[str] = field(default_factory=list)
    data_file: Path = Path("backend/data/store.json")
    page_size_default: int = 20
    page_size_max: int = 200


def load_settings() -> Settings:
    frontend_port = _env_int("FRONTEND_PORT", 5173)
    # 跨域白名单未显式配置时按前端端口自动生成，改端口不用同时改两处
    origins = _split_csv(_env("ALLOWED_ORIGINS")) or [
        f"http://127.0.0.1:{frontend_port}",
        f"http://localhost:{frontend_port}",
    ]
    data_file = Path(_env("DATA_FILE", "backend/data/store.json"))
    if not data_file.is_absolute():
        data_file = ROOT_DIR / data_file
    return Settings(
        env=_env("APP_ENV", "local"),
        host=_env("BACKEND_HOST", "127.0.0.1"),
        port=_env_int("BACKEND_PORT", 8000),
        frontend_port=frontend_port,
        allowed_origins=origins,
        data_file=data_file,
    )


settings = load_settings()
