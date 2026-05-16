from __future__ import annotations

from typing import Any

import httpx


class ControlPlaneClient:
    """
    Thin async HTTP wrapper around the control plane REST API.
    Run state changes are reported as events via POST /v1/runs/:run_id/events.
    """

    def __init__(self, base_url: str, api_key: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._headers = {"Authorization": f"ApiKey {api_key}", "Content-Type": "application/json"}

    async def post_event(self, event: dict[str, Any]) -> dict[str, Any]:
        """POST /v1/runs/:run_id/events to report runtime state changes."""
        run_id = event.get("run_id")
        if not isinstance(run_id, str) or not run_id:
            raise ValueError("run_id is required when posting a run event")

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self._base_url}/v1/runs/{run_id}/events",
                json=event,
                headers=self._headers,
                timeout=10.0,
            )
            response.raise_for_status()
            return response.json()

    async def post_heartbeat(self, payload: dict[str, Any]) -> None:
        """POST /v1/heartbeat — runtime liveness signal every 15 s."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self._base_url}/v1/heartbeat",
                json=payload,
                headers=self._headers,
                timeout=5.0,
            )
            response.raise_for_status()

    async def get_pending_handoffs(self, runtime_type: str) -> list[dict[str, Any]]:
        """GET /v1/handoffs/pending — handoffs waiting for this runtime type."""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self._base_url}/v1/handoffs/pending",
                params={"runtime_type": runtime_type},
                headers=self._headers,
                timeout=10.0,
            )
            response.raise_for_status()
            return response.json()["handoffs"]

    async def get_task(self, task_id: str) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self._base_url}/v1/tasks/{task_id}",
                headers=self._headers,
                timeout=10.0,
            )
            response.raise_for_status()
            return response.json()
