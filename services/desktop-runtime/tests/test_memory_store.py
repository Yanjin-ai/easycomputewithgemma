from __future__ import annotations

import pytest

from desktop_runtime.memory_store import MemoryStore


def _make_store(tmp_path, max_entries=20, max_inject_entries=5):
    return MemoryStore(
        memory_file=str(tmp_path / "memory.txt"),
        max_entries=max_entries,
        max_inject_entries=max_inject_entries,
    )


def test_append_and_read(tmp_path):
    store = _make_store(tmp_path)
    store.append("task one", "result one")
    store.append("task two", "result two")
    store.append("task three", "result three")

    ctx = store.recent_context()
    assert ctx.startswith("Recent task history:")
    assert "task one" in ctx
    assert "task two" in ctx
    assert "task three" in ctx
    assert "result one" in ctx
    assert "→" in ctx


def test_rolling_limit(tmp_path):
    store = _make_store(tmp_path, max_entries=5)
    for i in range(8):
        store.append(f"intent {i}", f"result {i}")

    memory_file = tmp_path / "memory.txt"
    lines = memory_file.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 5
    # Oldest entries (0,1,2) are gone; newest (3-7) are kept
    assert "intent 3" in lines[0]
    assert "intent 7" in lines[-1]


def test_inject_limit(tmp_path):
    store = _make_store(tmp_path, max_entries=20, max_inject_entries=5)
    for i in range(10):
        store.append(f"intent {i}", f"result {i}")

    ctx = store.recent_context()
    lines = [ln for ln in ctx.splitlines() if ln.startswith("- ")]
    assert len(lines) == 5
    # Must be the 5 most recent
    assert "intent 5" in ctx
    assert "intent 9" in ctx
    assert "intent 4" not in ctx


def test_length_cap(tmp_path):
    store = _make_store(tmp_path, max_entries=20, max_inject_entries=5)
    long_intent = "A" * 80
    long_result = "B" * 150
    for _ in range(5):
        store.append(long_intent, long_result)

    ctx = store.recent_context()
    assert len(ctx) <= 600


def test_empty_file(tmp_path):
    store = _make_store(tmp_path)
    # File does not exist yet
    assert store.recent_context() == ""

    # File exists but is empty
    (tmp_path / "memory.txt").write_text("", encoding="utf-8")
    assert store.recent_context() == ""
