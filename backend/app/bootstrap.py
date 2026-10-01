"""建库、灌示例数据与状态查询。

幂等约定（重复执行不污染已有数据）：
- ``init``：只建表，不动数据；
- ``seed``：已有数据或已灌过的模块一律跳过，只给空模块补示例数据；
- ``status``：打印库文件、各模块行数与 seed 标记；
- ``reset``：清空全部数据重新灌数，必须显式带 ``--yes``，防止误删。

用法：
    python -m app.bootstrap init
    python -m app.bootstrap seed
    python -m app.bootstrap status
    python -m app.bootstrap reset --yes
"""
from __future__ import annotations

import sys

from app import database
from app.config import settings
from app.seed import SEED_ROWS


def prepare(*, seed: bool = True) -> tuple[list[str], list[str]]:
    """启动前准备：确保库表存在，按需补示例数据。返回 (已灌模块, 跳过模块)。"""
    if settings.db_path == ":memory:":
        return [], [f"{name}（内存模式已内置示例数据）" for name in SEED_ROWS]
    conn = database.connect(settings.db_path)
    return _seed_missing(conn)


def _seed_missing(conn) -> tuple[list[str], list[str]]:
    """只给空表补示例数据；模块已有行或已标记灌数则跳过。"""
    already = database.seeded_modules(conn)
    loaded = database.load_all(conn)
    seeded: list[str] = []
    skipped: list[str] = []
    with database.write_lock():
        for module, rows in SEED_ROWS.items():
            if module in already or loaded.get(module):
                skipped.append(module)
                continue
            for row in rows:
                database.insert_entry(conn, module, row)
            conn.execute(
                "INSERT OR REPLACE INTO seed_meta(module, rows) VALUES (?, ?)",
                (module, len(rows)),
            )
            seeded.append(module)
        conn.commit()
    return seeded, skipped


def _status() -> int:
    if settings.db_path == ":memory:":
        print("存储模式：内存（重启数据消失，仅供临时调试）")
        print(f"示例模块：{len(SEED_ROWS)} 个，共 {sum(len(v) for v in SEED_ROWS.values())} 行")
        return 0
    conn = database.connect(settings.db_path)
    marked = database.seeded_modules(conn)
    loaded = database.load_all(conn)
    print(f"数据库文件：{settings.db_path}")
    print(f"{'模块':<14}{'当前行数':>8}  {'示例数据':>8}")
    print("-" * 36)
    for module in sorted(set(SEED_ROWS) | set(loaded) | set(marked)):
        tag = f"{marked[module]} 行" if module in marked else "—"
        print(f"{module:<14}{len(loaded.get(module, [])):>8}  {tag:>8}")
    return 0


def _reset() -> int:
    if settings.db_path == ":memory:":
        print("内存模式无需重置，重启进程即恢复示例数据")
        return 0
    conn = database.connect(settings.db_path)
    with database.write_lock():
        conn.execute("DELETE FROM entries")
        conn.execute("DELETE FROM seed_meta")
        conn.commit()
    seeded, _ = _seed_missing(conn)
    print(f"已重置数据库 {settings.db_path}，重新灌入 {len(seeded)} 个模块的示例数据")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    command = args[0] if args else "seed"
    if command == "init":
        if settings.db_path == ":memory:":
            print("内存模式，无需建库文件")
        else:
            database.connect(settings.db_path)
            print(f"已就绪：数据库文件 {settings.db_path}")
        return 0
    if command == "seed":
        seeded, skipped = prepare(seed=True)
        if seeded:
            print(f"已灌入示例数据：{len(seeded)} 个模块（{'、'.join(seeded)}）")
        else:
            print("所有模块已有数据或已灌过，本次跳过（不会重复写入）")
        if skipped and seeded:
            print(f"跳过：{len(skipped)} 个模块（已有数据）")
        return 0
    if command == "status":
        return _status()
    if command == "reset":
        if "--yes" not in args:
            print("拒绝执行：reset 会清空全部数据，请加 --yes 确认")
            return 2
        return _reset()
    print(f"不支持的命令：{command}；可用：init | seed | status | reset")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
