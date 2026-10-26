#!/usr/bin/env python3
"""Build the demo SQLite database from schema.sql, views.sql and seed.sql."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "registry"
DEFAULT_DB = ROOT / "data" / "registry.db"


def read(name: str) -> str:
    return (REGISTRY / name).read_text(encoding="utf-8")


def build(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    for suffix in ("-wal", "-shm"):
        sidecar = Path(str(db_path) + suffix)
        if sidecar.exists():
            sidecar.unlink()

    connection = sqlite3.connect(db_path)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.executescript(read("schema.sql"))
        connection.executescript(read("views.sql"))
        connection.executescript(read("seed.sql"))
        connection.commit()

        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"integrity_check failed: {integrity}")
        foreign_keys = connection.execute("PRAGMA foreign_key_check").fetchall()
        if foreign_keys:
            raise RuntimeError(f"foreign_key_check failed: {foreign_keys[:5]}")
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="Output database path")
    args = parser.parse_args()
    build(args.db)
    print(f"built {args.db}")


if __name__ == "__main__":
    main()
