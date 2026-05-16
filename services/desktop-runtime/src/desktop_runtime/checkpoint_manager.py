from __future__ import annotations

from desktop_runtime.adapters.types import CheckpointData


class CheckpointManager:
    """
    In-process checkpoint store (Phase 1).
    Phase 2: replace with upload to control plane artifact store.
    """

    def __init__(self) -> None:
        self._store: dict[str, CheckpointData] = {}

    def save(self, run_id: str, data: CheckpointData) -> None:
        self._store[run_id] = data

    def load(self, run_id: str) -> CheckpointData | None:
        return self._store.get(run_id)

    def clear(self, run_id: str) -> None:
        self._store.pop(run_id, None)
