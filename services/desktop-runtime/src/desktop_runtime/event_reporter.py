from __future__ import annotations

import datetime
import uuid
from typing import Any

from desktop_runtime.client.control_plane_client import ControlPlaneClient


class EventReporter:
    """
    Wraps ControlPlaneClient.post_event with auto-filled server-side fields.
    Callers only provide event_type, task_id, payload, and optional run_id.
    """

    def __init__(self, client: ControlPlaneClient, device_id: str) -> None:
        self._client = client
        self._device_id = device_id

    async def report(
        self,
        event_type: str,
        task_id: str,
        payload: dict[str, Any],
        run_id: str | None = None,
    ) -> dict[str, Any]:
        event = {
            "event_type": event_type,
            "task_id": task_id,
            "source": self._device_id,
            "emitted_at": datetime.datetime.now(datetime.UTC).isoformat(),
            "payload": payload,
            "schema_version": "1.0.0",
        }
        if run_id is not None:
            event["run_id"] = run_id
        return await self._client.post_event(event)
