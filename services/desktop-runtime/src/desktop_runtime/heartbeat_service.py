from __future__ import annotations

import asyncio
import logging

from desktop_runtime.client.control_plane_client import ControlPlaneClient
from desktop_runtime.tool_registry import ToolRegistry

logger = logging.getLogger(__name__)

HEARTBEAT_INTERVAL_S = 15


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
        before = self._active_runs
        self._active_runs += 1
        if self._active_runs != before + 1:
            logger.warning(
                "active_run_count was not updated when a run started: before=%s after=%s",
                before,
                self._active_runs,
            )

    def decrement_active_runs(self) -> None:
        before = self._active_runs
        self._active_runs = max(0, self._active_runs - 1)
        if before <= 0:
            logger.warning(
                "active_run_count was not updated when a run ended: before=%s after=%s",
                before,
                self._active_runs,
            )
        elif self._active_runs != before - 1:
            logger.warning(
                "active_run_count was not updated when a run ended: before=%s after=%s",
                before,
                self._active_runs,
            )

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
            "network_type": "wifi",  # Phase 1: static; Phase 2: detect via system API
            "active_run_count": self._active_runs,
            "supported_tools": self._tool_registry.list_supported(),
            # Report both cpu_inference and gpu_inference — we run on GPU with CPU fallback.
            # Tasks submitted with required_capabilities:["cpu_inference"] will match.
            "supported_capabilities": ["cpu_inference", "gpu_inference"],
        }
