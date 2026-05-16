from __future__ import annotations

import asyncio
import logging

from cloud_runtime.client.control_plane_client import ControlPlaneClient
from cloud_runtime.tool_registry import ToolRegistry

logger = logging.getLogger(__name__)

HEARTBEAT_INTERVAL_S = 30


class HeartbeatService:
    def __init__(
        self,
        client: ControlPlaneClient,
        device_id: str,
        tool_registry: ToolRegistry,
    ) -> None:
        self._client = client
        self._device_id = device_id
        self._tool_registry = tool_registry
        self._task: asyncio.Task[None] | None = None
        self._active_runs: int = 0

    def increment_active_runs(self) -> None:
        self._active_runs += 1

    def decrement_active_runs(self) -> None:
        self._active_runs = max(0, self._active_runs - 1)

    def start(self) -> None:
        if self._task is not None:
            return
        self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    async def _loop(self) -> None:
        while True:
            try:
                await self._client.post_heartbeat(self._collect_payload())
            except Exception:
                logger.exception("Heartbeat failed")
            await asyncio.sleep(HEARTBEAT_INTERVAL_S)

    def _collect_payload(self) -> dict:
        return {
            "device_id": self._device_id,
            "is_online": True,
            "network_type": "wifi",
            "active_run_count": self._active_runs,
            "supported_tools": self._tool_registry.list_supported(),
            "supported_capabilities": [],
        }
