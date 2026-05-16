from __future__ import annotations

import datetime
import inspect
import logging
from dataclasses import dataclass, field
from typing import Any, Literal

from cloud_runtime.adapters.gemini_adapter import GeminiAdapter, build_gemini_tools
from cloud_runtime.client.control_plane_client import ControlPlaneClient
from cloud_runtime.heartbeat_service import HeartbeatService
from cloud_runtime.tool_registry import ToolRegistry, ToolSpec

logger = logging.getLogger(__name__)

PermissionLevel = Literal["local_only", "private_lan", "cloud_ok"]
Runtime = Literal["mobile", "desktop", "cloud"]

# Sentinel — Gemini calls this to signal the task is done.
_TASK_DONE_SIGNAL = "task_completed"


@dataclass
class CheckpointData:
    conversation_history: list[dict[str, Any]]
    step_index: int
    runtime_specific: dict[str, Any] = field(default_factory=dict)


@dataclass
class TaskContext:
    intent_summary: str
    permission_level: PermissionLevel
    allowed_tools: list[str] = field(default_factory=list)


@dataclass
class HandoffPayload:
    handoff_id: str
    task_id: str
    source_run_id: str
    target_runtime: Runtime
    permission_level: PermissionLevel
    checkpoint_data: CheckpointData | None
    task_context: TaskContext
    initiated_by: Literal["system", "user"]
    initiated_at: str
    reason: str
    artifact_refs: list[str] = field(default_factory=list)


class CheckpointManager:
    """In-process checkpoint store (phase-1: memory only)."""

    def __init__(self) -> None:
        self._store: dict[str, CheckpointData] = {}

    def save(self, run_id: str, data: CheckpointData) -> None:
        self._store[run_id] = data

    def load(self, run_id: str) -> CheckpointData | None:
        return self._store.get(run_id)

    def clear(self, run_id: str) -> None:
        self._store.pop(run_id, None)


class CloudWorker:
    """
    Executes a single Run on the cloud runtime using Gemini's native
    function-calling API (not the FunctionGemma text-based format).

    Inference loop:
      1. Build Gemini Tool definitions from ToolRegistry
      2. Create a GeminiSession with those tools
      3. Send the task intent as the opening message
      4. Loop: Gemini returns a function_call → execute tool → send result back
      5. When Gemini calls task_completed, emit run.completed and return
      6. On any exception, emit run.failed
    """

    def __init__(
        self,
        inference: GeminiAdapter,
        tool_registry: ToolRegistry,
        checkpoint_manager: CheckpointManager,
        client: ControlPlaneClient,
        heartbeat_service: HeartbeatService | None = None,
    ) -> None:
        self._inference = inference
        self._tools = tool_registry
        self._checkpoints = checkpoint_manager
        self._client = client
        self._heartbeat = heartbeat_service

    async def start(self) -> None:
        logger.info("CloudWorker started")

    async def stop(self) -> None:
        logger.info("CloudWorker stopped")

    async def execute_run(self, payload: HandoffPayload) -> None:
        if self._heartbeat:
            self._heartbeat.increment_active_runs()
        try:
            await self._execute_run(payload)
        finally:
            if self._heartbeat:
                self._heartbeat.decrement_active_runs()

    async def _execute_run(self, payload: HandoffPayload) -> None:
        task_id = payload.task_id
        run_id = payload.source_run_id

        # Build Gemini-native tool definitions from the registry
        tool_specs = self._tools.as_tool_specs()
        gemini_tools = build_gemini_tools(tool_specs)
        session = self._inference.new_session(tools=gemini_tools)

        step_index = 0

        # Restore prior context from checkpoint if resuming
        prior_context = ""
        checkpoint = self._checkpoints.load(run_id)
        if checkpoint and checkpoint.conversation_history:
            prior_context = "\n\nPrevious steps completed:\n" + "\n".join(
                f"  {h['step']}. [{h['tool']}] → {h['result'][:120]}"
                for h in checkpoint.conversation_history
            )

        opening_message = (
            f"Task: {payload.task_context.intent_summary}\n\n"
            f"Complete this task step by step using the tools available to you. "
            f"When the task is fully done, call task_completed with a summary of what you accomplished."
            f"{prior_context}"
        )

        try:
            await self._report("run.started", task_id=task_id, run_id=run_id, payload={})
            logger.info("Run %s started — sending opening message to Gemini", run_id)

            result = await session.send(opening_message)

            while True:
                if result["type"] == "text":
                    # Model returned plain text instead of a function call.
                    # Treat this as an implicit completion (Gemini summarised without calling the sentinel).
                    logger.info("Run %s: model returned text, treating as completion", run_id)
                    self._checkpoints.clear(run_id)
                    await self._report(
                        "run.completed",
                        task_id=task_id,
                        run_id=run_id,
                        payload={"summary": result["text"]},
                    )
                    return

                # function_call
                name = result["name"]
                arguments = result.get("arguments", {})
                logger.info("Run %s: Gemini called %s(%s)", run_id, name, arguments)

                if name == _TASK_DONE_SIGNAL:
                    self._checkpoints.clear(run_id)
                    await self._report(
                        "run.completed",
                        task_id=task_id,
                        run_id=run_id,
                        payload={"summary": arguments.get("summary", "")},
                    )
                    logger.info("Run %s completed", run_id)
                    return

                handler = self._tools.get(name)
                if handler is None:
                    raise ValueError(f"Unknown tool requested by model: {name!r}")

                tool_result = await _invoke(handler, arguments)
                step_index += 1
                logger.info("Run %s: step %d tool=%s result=%s", run_id, step_index, name, str(tool_result)[:120])

                self._checkpoints.save(
                    run_id,
                    CheckpointData(
                        conversation_history=[
                            {"step": step_index, "tool": name, "result": str(tool_result)}
                        ],
                        step_index=step_index,
                    ),
                )

                await self._report(
                    "run.step_completed",
                    task_id=task_id,
                    run_id=run_id,
                    payload={"step_index": step_index, "tool": name},
                )

                # Feed the tool result back to Gemini using the native protocol
                result = await session.send_tool_result(name, tool_result)

        except Exception as exc:
            logger.exception("Run %s failed: %s", run_id, exc)
            await self._report(
                "run.failed",
                task_id=task_id,
                run_id=run_id,
                payload={"error": str(exc)},
            )

    async def _report(
        self,
        event_type: str,
        task_id: str,
        payload: dict[str, Any],
        run_id: str | None = None,
    ) -> dict[str, Any]:
        event: dict[str, Any] = {
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


async def _invoke(handler: Any, arguments: dict[str, Any]) -> Any:
    if inspect.iscoroutinefunction(handler):
        return await handler(**arguments)
    return handler(**arguments)
