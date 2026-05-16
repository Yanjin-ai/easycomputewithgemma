from __future__ import annotations

import sqlite3
import json
import pathlib


class SqliteCheckpointStore:
    def __init__(self, db_path: str = "checkpoints.db"):
        path = pathlib.Path(db_path)
        if path.parent != pathlib.Path("."):
            path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.execute("""
            CREATE TABLE IF NOT EXISTS checkpoints (
                run_id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        self._conn.commit()

    def load(self, run_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT data FROM checkpoints WHERE run_id = ?", (run_id,)
        ).fetchone()
        return json.loads(row[0]) if row else None

    def save(self, run_id: str, data: dict) -> None:
        self._conn.execute(
            (
                "INSERT OR REPLACE INTO checkpoints "
                "(run_id, data, updated_at) VALUES (?, ?, datetime('now'))"
            ),
            (run_id, json.dumps(data)),
        )
        self._conn.commit()

    def clear(self, run_id: str) -> None:
        self._conn.execute("DELETE FROM checkpoints WHERE run_id = ?", (run_id,))
        self._conn.commit()
