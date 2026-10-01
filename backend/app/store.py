"""数据仓库：对外保持 ``rows / find / module_names / overview`` 这一套接口不变。

底层默认是 SQLite 文件（见 ``app.config.settings.db_path``）：
- 读出来的每一行是 :class:`Row`，字段一改就落库；
- ``rows(module)`` 返回 :class:`RowList`，``append`` 一条也立刻落库。
业务层（services）依旧按普通 dict/list 使用，不需要感知持久化。

``db_path`` 取 ``:memory:`` 时退回纯内存模式，行为与历史版本一致，仅用于临时调试。
"""
from __future__ import annotations

import sqlite3
from typing import Any

from app import database
from app.config import settings


class Row(dict):
    """普通 dict 的持久化版本：任何字段变更都同步写回 SQLite。"""

    def __init__(self, module: str, conn: sqlite3.Connection, data: dict[str, Any]) -> None:
        object.__setattr__(self, "_module", module)
        object.__setattr__(self, "_conn", conn)
        object.__setattr__(self, "_live", False)
        super().__init__(data)
        object.__setattr__(self, "_live", True)

    def _flush(self) -> None:
        if not object.__getattribute__(self, "_live"):
            return
        conn = object.__getattribute__(self, "_conn")
        with database.write_lock():
            database.insert_entry(conn, object.__getattribute__(self, "_module"), dict(self))
            conn.commit()

    def __setitem__(self, key: str, value: Any) -> None:
        super().__setitem__(key, value)
        self._flush()

    def __delitem__(self, key: str) -> None:
        super().__delitem__(key)
        self._flush()

    def update(self, *args: Any, **kwargs: Any) -> None:  # type: ignore[override]
        super().update(*args, **kwargs)
        self._flush()

    def setdefault(self, key: str, default: Any = None) -> Any:
        existed = key in self
        value = super().setdefault(key, default)
        if not existed:
            self._flush()
        return value

    def pop(self, *args: Any) -> Any:
        result = super().pop(*args)
        self._flush()
        return result


class RowList(list):
    """普通 list 的持久化版本：新增记录立刻写回 SQLite。"""

    def __init__(self, module: str, conn: sqlite3.Connection, rows: list[dict[str, Any]]) -> None:
        super().__init__(Row(module, conn, row) for row in rows)
        self._module = module
        self._conn = conn

    def _persist(self, item: dict[str, Any]) -> Row:
        row = item if isinstance(item, Row) else Row(self._module, self._conn, dict(item))
        with database.write_lock():
            database.insert_entry(self._conn, self._module, dict(row))
            self._conn.commit()
        return row

    def append(self, item: dict[str, Any]) -> None:
        super().append(self._persist(item))

    def extend(self, items: list[dict[str, Any]]) -> None:  # type: ignore[override]
        for item in items:
            self.append(item)

    def insert(self, index: int, item: dict[str, Any]) -> None:
        row = self._persist(item)
        super().insert(index, row)


class Store:
    def __init__(self) -> None:
        self._memory: bool = settings.db_path == ":memory:"
        if self._memory:
            self._conn: sqlite3.Connection | None = None
            self._tables: dict[str, list[dict[str, Any]]] = {}
            self._reset_memory()
        else:
            self._conn = database.connect(settings.db_path)
            self._tables = {
                name: RowList(name, self._conn, rows)
                for name, rows in database.load_all(self._conn).items()
            }

    def _reset_memory(self) -> None:
        from app.seed import SEED_ROWS

        self._tables = {name: [dict(row) for row in rows] for name, rows in SEED_ROWS.items()}

    def connection(self) -> sqlite3.Connection | None:
        """供 bootstrap 等需要直接操作数据库的模块使用。"""
        return self._conn

    def is_memory(self) -> bool:
        return self._memory

    def module_names(self) -> list[str]:
        if self._memory:
            return sorted(self._tables)
        assert self._conn is not None
        names = {row[0] for row in self._conn.execute("SELECT DISTINCT module FROM entries")}
        names.update(self._tables)
        return sorted(names)

    def rows(self, module: str) -> list[dict[str, Any]]:
        if self._memory:
            return self._tables.setdefault(module, [])
        assert self._conn is not None
        if module not in self._tables:
            self._tables[module] = RowList(module, self._conn, [])
        return self._tables[module]

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


store = Store()
