from __future__ import annotations

from typing import Any

import httpx


class ControlPlaneClient:
    """
    Thin async HTTP wrapper around the control plane REST API.
    All runtime state changes are reported as events via POST /v1/events.
    """

    def __init__(self, base_url: str, api_key: str | None = None) -> None:
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key

    def set_api_key(self, api_key: str) -> None:
        self._api_key = api_key

    @property
    def _headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self._api_key:
            headers["Authorization"] = f"ApiKey {self._api_key}"
        return headers

    async def register_device(self, device_name: str) -> dict[str, Any]:
        """POST /v1/devices — register this process as a cloud runtime."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self._base_url}/v1/devices",
                json={
                    "device_name": device_name,
                    "runtime_type": "cloud",
                    "permission_scope": "cloud_ok",
                },
                headers={"Content-Type": "application/json"},
                timeout=10.0,
            )
            response.raise_for_status()
            return response.json()

    async def post_event(self, event: dict[str, Any]) -> dict[str, Any]:
        """POST /v1/events — the only path for reporting runtime state changes."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self._base_url}/v1/events",
                json=event,
                headers=self._headers,
                timeout=10.0,
            )
            response.raise_for_status()
            return response.json()

    async def post_heartbeat(self, payload: dict[str, Any]) -> None:
        """POST /v1/heartbeat — runtime liveness signal every 30 s."""
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
