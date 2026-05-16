from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from desktop_runtime.adapters.types import (
    CheckpointData,
    HandoffPayload,
    PermissionLevel,
    TaskContext,
)
from desktop_runtime.client.control_plane_client import ControlPlaneClient
from desktop_runtime.event_reporter import EventReporter
from desktop_runtime.worker import DesktopWorker

logger = logging.getLogger(__name__)

_CLOUD_ORIGINS = {"cloud"}
_RESTRICTED_LEVELS: set[PermissionLevel] = {"local_only", "private_lan"}


class HandoffReceiver:
    """
    Validates and dispatches an incoming HandoffPayload to DesktopWorker.
    Idempotency and permission checks happen before any execution starts.

    LiteRT-LM is single-threaded, so only one run may execute at a time.
    A Semaphore(1) enforces this; start_polling skips fetching new handoffs
    while a run is in progress so they remain queued on the control plane.
    """

    def __init__(
        self,
        worker: DesktopWorker,
        reporter: EventReporter,
        client: ControlPlaneClient,
    ) -> None:
        self._worker = worker
        self._reporter = reporter
        self._client = client
        self._processed: set[str] = set()
        self._run_semaphore = asyncio.Semaphore(1)
        self._active_run_count: int = 0

    async def start_polling(self) -> None:
        while True:
            try:
                # Only fetch from the control plane when no run is in progress.
                # Pending handoffs remain queued there until the runtime is free.
                if self._active_run_count == 0:
                    payloads = await self._client.get_pending_handoffs("desktop")
                    for raw_payload in payloads:
                        handoff_id = raw_payload.get("handoff_id")
                        if isinstance(handoff_id, str) and handoff_id in self._processed:
                            continue
                        # Fire-and-forget so the poll loop keeps sleeping while the
                        # run executes; at most one new run is started per cycle.
                        asyncio.create_task(
                            self.receive(_deserialize_handoff(raw_payload)),
                            name=f"handoff-{handoff_id}",
                        )
                        break
            except httpx.HTTPError:
                logger.exception("Failed to poll pending handoffs")
            except Exception:
                logger.exception("Unexpected error while polling pending handoffs")
            await asyncio.sleep(10)

    async def receive(self, payload: HandoffPayload) -> None:
        logger.info("Received handoff %s for task %s", payload.handoff_id, payload.task_id)

        if payload.handoff_id in self._processed:
            logger.info("Duplicate handoff %s ignored", payload.handoff_id)
            return

        if self._must_reject_for_permission(payload):
            await self._reject(
                payload,
                reason="permission_level blocks cloud-origin handoff on this device",
            )
            return

        self._processed.add(payload.handoff_id)

        await self._reporter.report(
            "handoff.accepted",
            task_id=payload.task_id,
            run_id=payload.run_id or payload.source_run_id,
            payload={"handoff_id": payload.handoff_id},
        )

        async with self._run_semaphore:
            self._active_run_count += 1
            try:
                await self._worker.execute_run(payload)
            finally:
                self._active_run_count -= 1

        logger.info("Handoff %s processing complete", payload.handoff_id)

    def _must_reject_for_permission(self, payload: HandoffPayload) -> bool:
        return (
            payload.permission_level in _RESTRICTED_LEVELS
            and payload.target_runtime in _CLOUD_ORIGINS
        )

    async def _reject(self, payload: HandoffPayload, reason: str) -> None:
        logger.warning("Rejecting handoff %s: %s", payload.handoff_id, reason)
        await self._reporter.report(
            "handoff.rejected",
            task_id=payload.task_id,
            run_id=payload.run_id or payload.source_run_id,
            payload={"handoff_id": payload.handoff_id, "reason": reason},
        )


def _deserialize_handoff(payload: dict[str, Any]) -> HandoffPayload:
    task_context = payload["task_context"]
    constraints = task_context.get("constraints", {})
    checkpoint_data = payload.get("checkpoint_data")
    return HandoffPayload(
        handoff_id=payload["handoff_id"],
        task_id=payload["task_id"],
        source_run_id=payload["source_run_id"],
        target_runtime=payload["target_runtime"],
        permission_level=payload["permission_level"],
        checkpoint_data=_deserialize_checkpoint(checkpoint_data),
        task_context=TaskContext(
            intent_summary=task_context.get("intent_summary", task_context.get("intent", "")),
            permission_level=task_context.get(
                "permission_level",
                constraints.get("permission_level", payload["permission_level"]),
            ),
            allowed_tools=task_context.get("allowed_tools", constraints.get("allowed_tools", [])),
        ),
        initiated_by=payload["initiated_by"],
        initiated_at=payload["initiated_at"],
        reason=payload["reason"],
        artifact_refs=payload.get("artifact_refs", []),
        run_id=payload.get("run_id"),
    )


def _deserialize_checkpoint(checkpoint_data: dict[str, Any] | None) -> CheckpointData | None:
    if checkpoint_data is None:
        return None
    return CheckpointData(
        conversation_history=checkpoint_data.get("conversation_history", []),
        step_index=checkpoint_data.get("step_index", len(checkpoint_data.get("steps_completed", []))),
        runtime_specific=checkpoint_data.get("runtime_specific", {}),
    )
