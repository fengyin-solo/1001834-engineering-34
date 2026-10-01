"""数据仓库：示例数据落在 JSON 文件里，重启、换机器、进容器都不用重录。

- 文件位置由配置 DATA_FILE 决定（默认 backend/data/store.json，已加入 .gitignore）。
- 文件不存在时用内置样例初始化；已存在时原样加载，启动过程绝不重置已有数据。
- 写请求处理后由 main.py 的中间件统一落盘；命令行可用 python -m app.seed 幂等补齐。
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from app.config import settings
from app.seed import SEED_ROWS


def _seed_tables() -> dict[str, list[dict[str, Any]]]:
    return {name: [dict(row) for row in rows] for name, rows in SEED_ROWS.items()}


class Store:
    def __init__(self, path: Path) -> None:
        self._path = path
        # 标记本次启动是否新建了数据文件，供 seed 命令打印准确的初始化结果
        self.created_on_load = False
        if path.exists():
            self._tables = self._read()
        else:
            self._tables = _seed_tables()
            self.created_on_load = True
            self.persist()

    @property
    def path(self) -> Path:
        return self._path

    def _read(self) -> dict[str, list[dict[str, Any]]]:
        with self._path.open(encoding="utf-8") as fh:
            data = json.load(fh)
        return {str(name): [dict(row) for row in rows] for name, rows in data.items()}

    def persist(self) -> None:
        """原子落盘：先写临时文件再替换，避免中途异常留下半个文件。"""
        self._path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_name(self._path.name + ".tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(self._tables, fh, ensure_ascii=False, indent=2)
        os.replace(tmp, self._path)

    def reset_to_seed(self) -> None:
        """显式重建：只有 python -m app.seed --reset 会走到，启动流程不会调用。"""
        self._tables = _seed_tables()

    def ensure_seeded(self) -> dict[str, bool]:
        """幂等补齐缺失模块：已有模块原样保留。返回 {模块: 是否本次新建}。"""
        report: dict[str, bool] = {}
        changed = False
        for name, rows in SEED_ROWS.items():
            if name in self._tables:
                report[name] = False
            else:
                self._tables[name] = [dict(row) for row in rows]
                report[name] = True
                changed = True
        if changed:
            self.persist()
        return report

    def module_names(self) -> list[str]:
        return sorted(self._tables)

    def rows(self, module: str) -> list[dict[str, Any]]:
        return self._tables.setdefault(module, [])

    def find(self, module: str, entry_id: int) -> dict[str, Any] | None:
        for row in self.rows(module):
            if int(row.get("id", 0)) == entry_id:
                return row
        return None

    def overview(self) -> dict[str, object]:
        modules: list[dict[str, object]] = []
        for name in self.module_names():
            rows = self.rows(name)
            modules.append({
                "name": name,
                "created": len(rows),
                "pending": sum(1 for row in rows if row.get("pending")),
                "abnormal": sum(1 for row in rows if row.get("abnormal")),
            })
        cards = [
            {"label": "业务模块", "value": len(modules)},
            {"label": "今日新增", "value": sum(int(item["created"]) for item in modules)},
            {"label": "待处理", "value": sum(int(item["pending"]) for item in modules)},
            {"label": "异常量", "value": sum(int(item["abnormal"]) for item in modules)},
        ]
        return {"cards": cards, "modules": modules}


store = Store(settings.data_file)
