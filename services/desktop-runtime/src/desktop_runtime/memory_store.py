from __future__ import annotations

import fcntl
import os
from datetime import datetime
from pathlib import Path


class MemoryStore:
    """
    Appends task summaries to ~/gemma4all_memory.txt after each task completes.
    Provides recent summaries for injection into new task prompts.
    Format per line: [YYYY-MM-DD HH:MM] <intent_summary> → <result_summary>
    """

    def __init__(
        self,
        memory_file: str | None = None,
        max_entries: int = 20,
        max_inject_entries: int = 5,
    ) -> None:
        self._path = Path(memory_file) if memory_file else Path.home() / "gemma4all_memory.txt"
        self._max_entries = max_entries
        self._max_inject = max_inject_entries

    def append(self, intent: str, summary: str) -> None:
        intent_clipped = intent[:80]
        summary_clipped = summary[:150]
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
        line = f"[{timestamp}] {intent_clipped} → {summary_clipped}\n"

        with open(self._path, "a+", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            try:
                f.seek(0)
                lines = f.readlines()
                lines.append(line)
                if len(lines) > self._max_entries:
                    lines = lines[len(lines) - self._max_entries:]
                f.seek(0)
                f.truncate()
                f.writelines(lines)
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)

    def recent_context(self) -> str:
        if not self._path.exists():
            return ""

        with open(self._path, "r", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            try:
                lines = f.readlines()
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)

        if not lines:
            return ""

        recent = lines[-self._max_inject:]
        items = [f"- {line.rstrip()}" for line in recent]

        header = "Recent task history:"
        result = header + "\n" + "\n".join(items)

        if len(result) > 600:
            # Drop oldest entries until we fit
            while items and len(header + "\n" + "\n".join(items)) > 600:
                items.pop(0)
            result = header + "\n" + "\n".join(items)

        return result if items else ""
