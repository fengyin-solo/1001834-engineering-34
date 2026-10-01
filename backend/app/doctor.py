"""启动前自检：把"服务起不来"的可能原因分类列清楚，逐条给出修复建议。

检查分四类：运行环境、依赖、配置、数据与端口。
本地用 `make doctor`，容器启动时也会先跑这一段（见 backend/Dockerfile），
出现 ✗ 时以非 0 退出码结束，日志里能直接看到原因，不用再猜是缺依赖还是配置没对。
"""
from __future__ import annotations

import importlib
import json
import socket
import sys
from pathlib import Path
from typing import Any

ROOT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT_DIR / ".env"

PASS, WARN, FAIL = "✓", "!", "✗"


class Reporter:
    def __init__(self) -> None:
        self.failures = 0
        self.warnings = 0

    def report(self, level: str, message: str, hint: str | None = None) -> None:
        if level == FAIL:
            self.failures += 1
        elif level == WARN:
            self.warnings += 1
        print(f"  {level} {message}")
        if hint:
            print(f"    → {hint}")


def check_python(rep: Reporter) -> None:
    version = sys.version_info
    text = f"Python {version.major}.{version.minor}.{version.micro}"
    if version >= (3, 10):
        rep.report(PASS, text)
    else:
        rep.report(FAIL, f"{text}（需要 >= 3.10）", "升级 Python 后删掉 backend/.venv 重跑 make setup")


def check_dependencies(rep: Reporter) -> None:
    for name in ("fastapi", "uvicorn", "pydantic"):
        try:
            module = importlib.import_module(name)
            version = getattr(module, "__version__", "已安装")
            rep.report(PASS, f"依赖 {name} {version}")
        except ImportError:
            rep.report(
                FAIL,
                f"缺少依赖 {name}",
                "cd backend && .venv/bin/pip install -r requirements.txt（或重跑 make setup）",
            )


def check_config(rep: Reporter) -> Any:
    """返回解析成功的 settings；解析失败时报告并返回 None。"""
    if ENV_FILE.exists():
        rep.report(PASS, "配置文件 .env 已就绪（唯一配置来源）")
    else:
        rep.report(
            WARN,
            ".env 不存在，当前使用内置默认值",
            "cp .env.example .env 后按需修改；重跑 make setup 也会自动生成",
        )
    try:
        from app.config import settings
    except Exception as exc:  # 配置解析失败要单独分类报出来
        rep.report(FAIL, f"配置解析失败：{exc}", "检查 .env 中端口是否为整数、跨域名单是否用逗号分隔")
        return None
    rep.report(PASS, f"后端地址 {settings.host}:{settings.port}（环境 {settings.env}）")
    rep.report(PASS, f"跨域白名单 {len(settings.allowed_origins)} 条：{'、'.join(settings.allowed_origins)}")
    return settings


def check_data(rep: Reporter, settings: Any) -> None:
    path: Path = settings.data_file
    if path.exists():
        try:
            with path.open(encoding="utf-8") as fh:
                data = json.load(fh)
            total = sum(len(rows) for rows in data.values())
            rep.report(PASS, f"数据文件 {path}（{len(data)} 个模块 / {total} 条记录）")
        except (json.JSONDecodeError, OSError) as exc:
            rep.report(
                FAIL,
                f"数据文件损坏：{exc}",
                "修复或删除该文件后重跑 make seed；要整体重建可执行 python -m app.seed --reset",
            )
    else:
        rep.report(PASS, f"数据文件尚未生成，首次启动会自动初始化到 {path}")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        probe = path.parent / ".write-probe"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink()
        rep.report(PASS, f"数据目录可写：{path.parent}")
    except OSError as exc:
        rep.report(FAIL, f"数据目录不可写：{exc}", "检查目录权限；容器里确认数据卷挂载正确")


def check_port(rep: Reporter, settings: Any) -> None:
    sock = socket.socket()
    try:
        sock.bind((settings.host, settings.port))
    except OSError:
        rep.report(
            WARN,
            f"端口 {settings.host}:{settings.port} 已被占用",
            "若是本服务已在运行可忽略；否则改 .env 的 BACKEND_PORT 或停掉占用进程",
        )
    else:
        rep.report(PASS, f"端口 {settings.port} 可用")
    finally:
        sock.close()


def main() -> int:
    rep = Reporter()
    print("[自检] 运行环境与依赖")
    check_python(rep)
    check_dependencies(rep)

    print("[自检] 配置")
    settings = check_config(rep)

    if settings is not None:
        print("[自检] 数据与端口")
        check_data(rep, settings)
        check_port(rep, settings)

    if rep.failures:
        print(f"\n自检未通过：{rep.failures} 项必须处理，{rep.warnings} 项提醒。")
        return 1
    if rep.warnings:
        print(f"\n自检通过（{rep.warnings} 项提醒）。")
    else:
        print("\n自检全部通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
