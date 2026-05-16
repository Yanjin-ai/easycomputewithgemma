from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from cloud_runtime.client.control_plane_client import ControlPlaneClient
from cloud_runtime.worker import (
    CheckpointData,
    CloudWorker,
    HandoffPayload,
    PermissionLevel,
    TaskContext,
)

logger = logging.getLogger(__name__)

_NON_CLOUD_LEVELS: set[PermissionLevel] = {"local_only", "private_lan"}


class HandoffReceiver:
    """
    Validates and dispatches pending cloud HandoffPayloads to CloudWorker.
    Idempotency and permission checks happen before execution starts.
    """

    def __init__(
        self,
        worker: CloudWorker,
        client: ControlPlaneClient,
        poll_interval_s: float,
    ) -> None:
        self._worker = worker
        self._client = client
        self._poll_interval_s = poll_interval_s
        self._processed: set[str] = set()
        self._running_tasks: set[asyncio.Task[None]] = set()

    async def start_polling(self) -> None:
        while True:
            try:
                payloads = await self._client.get_pending_handoffs("cloud")
                for raw_payload in payloads:
                    handoff_id = raw_payload.get("handoff_id")
                    if isinstance(handoff_id, str) and handoff_id in self._processed:
                        continue
                    await self.receive(_deserialize_handoff(raw_payload))
            except httpx.HTTPError:
                logger.exception("Failed to poll pending handoffs")
            except Exception:
                logger.exception("Unexpected error while polling pending handoffs")
            await asyncio.sleep(self._poll_interval_s)

    async def stop(self) -> None:
        for task in self._running_tasks:
            task.cancel()
        if self._running_tasks:
            await asyncio.gather(*self._running_tasks, return_exceptions=True)
        self._running_tasks.clear()

    async def receive(self, payload: HandoffPayload) -> None:
        if payload.handoff_id in self._processed:
            logger.info("Duplicate handoff %s ignored", payload.handoff_id)
            return

        if payload.permission_level in _NON_CLOUD_LEVELS:
            await self._reject(
                payload,
                reason="permission_level blocks handoff on cloud runtime",
            )
            return

        self._processed.add(payload.handoff_id)

        await self._report(
            "handoff.accepted",
            task_id=payload.task_id,
            run_id=payload.source_run_id,
            payload={"handoff_id": payload.handoff_id},
        )
        task = asyncio.create_task(self._worker.execute_run(payload))
        self._running_tasks.add(task)
        task.add_done_callback(self._running_tasks.discard)

    async def _reject(self, payload: HandoffPayload, reason: str) -> None:
        logger.warning("Rejecting handoff %s: %s", payload.handoff_id, reason)
        await self._report(
            "handoff.rejected",
            task_id=payload.task_id,
            run_id=payload.source_run_id,
            payload={"handoff_id": payload.handoff_id, "reason": reason},
        )

    async def _report(
        self,
        event_type: str,
        task_id: str,
        payload: dict[str, Any],
        run_id: str | None = None,
    ) -> dict[str, Any]:
        import datetime

        event = {
            "event_type": event_type,
            "task_id": task_id,
            "source": "cloud",
            "emitted_at": datetime.datetime.now(datetime.UTC).isoformat(),
            "payload": payload,
            "schema_version": "1.0.0",
        }
        if run_id is not None:
            event["run_id"] = run_id
        return await self._client.post_event(event)


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
    )


def _deserialize_checkpoint(checkpoint_data: dict[str, Any] | None) -> CheckpointData | None:
    if checkpoint_data is None:
        return None
    return CheckpointData(
        conversation_history=checkpoint_data.get("conversation_history", []),
        step_index=checkpoint_data.get("step_index", len(checkpoint_data.get("steps_completed", []))),
        runtime_specific=checkpoint_data.get("runtime_specific", {}),
    )
