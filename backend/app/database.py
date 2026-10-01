"""SQLite 连接管理：示例数据与运行期改动都落到这里，重启或换机器不丢。

设计上只用标准库：建库即建表，写入统一走同一把锁，保证 uvicorn 多线程下安全。
内存模式（``:memory:``）保留给临时测试，此时重启数据仍然消失，仅作调试用途。
"""
from __future__ import annotations

import json
import sqlite3
import threading
from pathlib import Path

_SCHEMA = """
CREATE TABLE IF NOT EXISTS entries (
    module TEXT NOT NULL,
    entry_id INTEGER NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (module, entry_id)
);
CREATE TABLE IF NOT EXISTS seed_meta (
    module TEXT PRIMARY KEY,
    rows INTEGER NOT NULL,
    seeded_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"""

_write_lock = threading.Lock()


def connect(db_path: str | Path) -> sqlite3.Connection:
    """打开（必要时创建）数据库文件并初始化表结构。"""
    if str(db_path) != ":memory:":
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    if str(db_path) != ":memory:":
        conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(_SCHEMA)
    conn.commit()
    return conn


def load_all(conn: sqlite3.Connection) -> dict[str, list[dict]]:
    """一次性读出全部记录，按模块分组，模块内按 id 升序。

    必须显式排序：写入走 INSERT OR REPLACE，更新会改变物理 rowid 顺序，
    不排序的话重启后被修改过的记录会"跳到"列表末尾。
    """
    tables: dict[str, list[dict]] = {}
    for row in conn.execute("SELECT module, data FROM entries ORDER BY module, entry_id"):
        tables.setdefault(row["module"], []).append(json.loads(row["data"]))
    return tables


def insert_entry(conn: sqlite3.Connection, module: str, entry: dict) -> None:
    """写入一条记录（主键冲突时覆盖），调用方负责持锁/事务。"""
    entry_id = int(entry.get("id", 0))
    payload = json.dumps(entry, ensure_ascii=False)
    conn.execute(
        "INSERT OR REPLACE INTO entries(module, entry_id, data) VALUES (?, ?, ?)",
        (module, entry_id, payload),
    )


def delete_entry(conn: sqlite3.Connection, module: str, entry_id: int) -> None:
    conn.execute("DELETE FROM entries WHERE module = ? AND entry_id = ?", (module, entry_id))


def clear_module(conn: sqlite3.Connection, module: str) -> None:
    conn.execute("DELETE FROM entries WHERE module = ?", (module,))
    conn.execute("DELETE FROM seed_meta WHERE module = ?", (module,))


def seeded_modules(conn: sqlite3.Connection) -> dict[str, int]:
    """已经灌过示例数据的模块及其行数；用于保证 seed 幂等。"""
    return {row["module"]: row["rows"] for row in conn.execute("SELECT module, rows FROM seed_meta")}


def write_lock() -> threading.Lock:
    """对外暴露写锁，Store 在 flush 时持有。"""
    return _write_lock
