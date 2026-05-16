from __future__ import annotations

import asyncio
import logging
import json
import inspect
import re
from dataclasses import asdict
from typing import Any

from desktop_runtime.adapters.inference_adapter import InferenceAdapter, ToolSpec
from desktop_runtime.adapters.types import CheckpointData, HandoffPayload
from desktop_runtime.checkpoint_store import SqliteCheckpointStore
from desktop_runtime.event_reporter import EventReporter
from desktop_runtime.heartbeat_service import HeartbeatService
from desktop_runtime.memory_store import MemoryStore
from desktop_runtime.tool_registry import ToolRegistry

logger = logging.getLogger(__name__)

# Tool calling protocol: prompts still advertise JSON [TOOL_CALL] calls, while
# tool results are returned using Gemma 4 native tool_response feedback format.
# FunctionGemma signals task completion with this sentinel function name.
_TASK_DONE_SIGNAL = "task_completed"
_INVALID_NATIVE_GEMMA_VALUE = object()


class DesktopWorker:
    """
    Executes a single Run on the desktop runtime.

    Inference loop:
      1. Restore conversation history from checkpoint (if any)
      2. For each step: call FunctionGemma → parse function call → dispatch to ToolRegistry
      3. Emit run.step_completed after each successful tool execution
      4. Save checkpoint after each step
      5. Emit run.completed or run.failed when done
    """

    def __init__(
        self,
        inference: InferenceAdapter,
        tool_registry: ToolRegistry,
        checkpoint_store: SqliteCheckpointStore,
        reporter: EventReporter,
        model_path: str,
        backend: str = "cpu",
        heartbeat_service: HeartbeatService | None = None,
        memory_store: MemoryStore | None = None,
    ) -> None:
        self._inference = inference
        self._tools = tool_registry
        self._checkpoints = checkpoint_store
        self._reporter = reporter
        self._model_path = model_path
        self._backend = backend
        self._heartbeat = heartbeat_service
        self._memory = memory_store
        self._running = False

    async def start(self) -> None:
        await self._inference.load(self._model_path, self._backend)
        self._running = True
        logger.info("DesktopWorker started, model loaded from %s", self._model_path)

    async def stop(self) -> None:
        self._running = False
        await self._inference.unload()
        logger.info("DesktopWorker stopped")

    async def execute_run(self, payload: HandoffPayload) -> None:
        """
        Entry point for receiving a handoff and running the task to completion.
        All state changes are reported as events — never by mutating Task/Run directly.
        """
        if self._heartbeat:
            self._heartbeat.increment_active_runs()
        try:
            await self._execute_run(payload)
        finally:
            if self._heartbeat:
                self._heartbeat.decrement_active_runs()

    async def _execute_run(self, payload: HandoffPayload) -> None:
        task_id = payload.task_id
        run_id = payload.run_id or payload.source_run_id

        tool_specs = self._tools.as_tool_specs()
        session = self._inference.new_session()
        step_index = 0

        checkpoint = self._checkpoints.load(run_id)
        prior_context = ""
        if checkpoint:
            step_index = checkpoint.get("step_index", 0) or len(
                checkpoint.get("steps_completed", [])
            )
            prior_steps = checkpoint.get("conversation_history", []) or checkpoint.get(
                "tool_call_history", []
            )
            if prior_steps:
                prior_context = "\nPrevious steps:\n" + "\n".join(
                    str(h) for h in prior_steps
                )

        initial_message = self._build_initial_message(payload, tool_specs, prior_context)

        try:
            await self._reporter.report(
                "run.started",
                task_id=task_id,
                run_id=run_id,
                payload={},
            )
            logger.info(
                "Sending initial prompt (%d chars, %d tools)",
                len(initial_message),
                len(tool_specs),
            )
            loop = asyncio.get_event_loop()
            logger.info("Calling inference for run %s (step %d)", run_id, step_index)
            response = await loop.run_in_executor(None, session.send, initial_message)
            logger.info("Inference returned %d chars for run %s", len(response), run_id)

            while True:
                call = self._parse_function_call(response)

                if call is None:
                    text = await self._report_completed(task_id, run_id, response)
                    if self._memory:
                        intent = getattr(
                            payload.task_context, "intent", payload.task_context.intent_summary
                        )
                        self._memory.append(intent, text[:150])
                    self._checkpoints.clear(run_id)
                    return

                if call["name"] == _TASK_DONE_SIGNAL:
                    text = await self._report_completed(
                        task_id,
                        run_id,
                        call.get("arguments", {}).get("summary"),
                    )
                    if self._memory:
                        intent = getattr(
                            payload.task_context, "intent", payload.task_context.intent_summary
                        )
                        self._memory.append(intent, text[:150])
                    self._checkpoints.clear(run_id)
                    return

                handler = self._tools.get(call["name"])
                if handler is None:
                    raise ValueError(f"Unknown tool: {call['name']}")

                logger.info(
                    "Tool call: %s(%s)",
                    call["name"],
                    json.dumps(call.get("arguments", {})),
                )
                tool_result = await _invoke(handler, call.get("arguments", {}))
                logger.info("Tool result: %.200s", str(tool_result))
                step_index += 1

                self._checkpoints.save(
                    run_id,
                    asdict(
                        CheckpointData(
                            steps_completed=[
                                *(
                                    checkpoint.get("steps_completed", [])
                                    if checkpoint
                                    else []
                                ),
                                call["name"],
                            ],
                            current_step=call["name"],
                            tool_call_history=[
                                *(
                                    checkpoint.get("tool_call_history", [])
                                    if checkpoint
                                    else []
                                ),
                                {
                                    "step": step_index,
                                    "tool": call["name"],
                                    "arguments": call.get("arguments", {}),
                                    "result": str(tool_result),
                                },
                            ],
                            variables=checkpoint.get("variables", {}) if checkpoint else {},
                            pending_actions=(
                                checkpoint.get("pending_actions", [])
                                if checkpoint
                                else []
                            ),
                            runtime_specific=(
                                checkpoint.get("runtime_specific", {})
                                if checkpoint
                                else {}
                            ),
                            conversation_history=[
                                *(
                                    checkpoint.get("conversation_history", [])
                                    if checkpoint
                                    else []
                                ),
                                {
                                    "step": step_index,
                                    "tool": call["name"],
                                    "result": str(tool_result),
                                },
                            ],
                            step_index=step_index,
                        )
                    ),
                )
                checkpoint = self._checkpoints.load(run_id)
                await self._reporter.report(
                    "run.step_completed",
                    task_id=task_id,
                    run_id=run_id,
                    payload={"step_index": step_index, "tool": call["name"]},
                )

                logger.info("Calling inference for run %s (step %d)", run_id, step_index)
                tool_name = call["name"]
                native_result = (
                    f'<|tool_response>response:{tool_name}'
                    f'{{value:"{tool_result}"}}<tool_response|>'
                )
                response = await loop.run_in_executor(
                    None,
                    session.send,
                    native_result,
                )
                logger.info("Inference returned %d chars for run %s", len(response), run_id)

        except Exception as exc:
            logger.exception("Run %s failed", run_id)
            await self._reporter.report(
                "run.failed",
                task_id=task_id,
                run_id=run_id,
                payload={
                    "error_code": "inference_error",
                    "error_message": str(exc),
                },
            )

    def _build_initial_message(
        self,
        payload: HandoffPayload,
        tool_specs: list[ToolSpec],
        prior_context: str = "",
    ) -> str:
        intent = getattr(
            payload.task_context,
            "intent",
            payload.task_context.intent_summary,
        )
        message = (
            "You are a helpful AI assistant running on a Mac. Complete the following task\n"
            "and respond with a clear, direct answer. Do not include any preamble or\n"
            "explanation of what you are doing — just provide the result.\n\n"
            f"Task: {intent}\n\n"
        )
        if prior_context:
            message += prior_context

        if self._memory:
            mem_context = self._memory.recent_context()
            if mem_context:
                message += f"\n\n{mem_context}"

        if tool_specs:
            message += (
                "\n\nAvailable tools (JSON schema):\n"
                f"{self._build_tools_json(tool_specs)}\n\n"
                "To call a tool, output ONLY this JSON on its own line (no other text):\n"
                '[TOOL_CALL] {"name": "<tool_name>", "arguments": {"param": "value"}}\n\n'
                "After each tool result you will receive the result in tool_response format.\n\n"
                "When the task is fully done, call task_completed with a summary:\n"
                '[TOOL_CALL] {"name": "task_completed", "arguments": {"summary": "<answer>"}}\n\n'
                "If no tool is needed, just respond with the answer directly.\n\n"
                'Tip: for run_applescript, write complete AppleScript. Example: tell application "Calendar" to make new event at end of (first calendar whose name is "Home") with properties {summary:"Meeting", start date:(current date), end date:(current date) + 3600}'
            )
        else:
            message += "\n\nOtherwise, answer directly."

        return message

    def _build_tools_json(self, tool_specs: list[ToolSpec]) -> str:
        tools = [
            {
                "type": "function",
                "function": {
                    "name": spec.name,
                    "description": getattr(spec.handler, "__doc__", None) or spec.name,
                    "parameters": self._build_parameters_json(spec.handler),
                },
            }
            for spec in tool_specs
        ]
        tools.append(
            {
                "type": "function",
                "function": {
                    "name": _TASK_DONE_SIGNAL,
                    "description": "Signal that the task is fully complete.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "summary": {
                                "type": "string",
                                "description": "What was accomplished",
                            }
                        },
                        "required": ["summary"],
                    },
                },
            }
        )
        return json.dumps(tools)

    def _build_parameters_json(self, handler: Any) -> dict[str, Any]:
        properties: dict[str, dict[str, str]] = {}
        required: list[str] = []
        signature = inspect.signature(handler)
        for name, parameter in signature.parameters.items():
            properties[name] = {"type": _json_type_for(parameter.annotation)}
            if parameter.default is inspect.Signature.empty:
                required.append(name)
        parameters: dict[str, Any] = {"type": "object", "properties": properties}
        if required:
            parameters["required"] = required
        return parameters

    def _parse_function_call(self, raw_output: str) -> dict[str, Any] | None:
        try:
            raw = raw_output.strip()
            native_call = _parse_native_gemma_tool_call(raw)
            if native_call is not None:
                return native_call

            marker = "[TOOL_CALL]"
            if marker in raw:
                raw = raw[raw.index(marker) + len(marker):].strip()

            start = raw.find("{")
            end = raw.rfind("}") + 1
            if start != -1 and end > start:
                call = json.loads(raw[start:end])
                if isinstance(call, dict) and isinstance(call.get("name"), str):
                    return call
            return None
        except Exception:
            logger.debug("Could not parse function call from raw output: %r", raw_output)
            return None

    async def _report_completed(
        self,
        task_id: str,
        run_id: str,
        summary: Any,
    ) -> str:
        if isinstance(summary, str):
            text = _strip_gemma_thinking_tokens(summary)
        elif summary is None:
            text = ""
        else:
            text = _strip_gemma_thinking_tokens(str(summary))

        if not text:
            logger.warning("Run %s completed with no text output", run_id)
            text = "Task completed (no output)"

        logger.info("Run %s completed, summary length: %d chars", run_id, len(text))

        await self._reporter.report(
            "run.completed",
            task_id=task_id,
            run_id=run_id,
            payload={
                "summary": text,
                "output_type": "text",
            },
        )
        return text


async def _invoke(handler, arguments: dict[str, Any]) -> Any:
    import asyncio, inspect
    if asyncio.iscoroutinefunction(handler):
        return await handler(**arguments)
    return handler(**arguments)


def _strip_gemma_thinking_tokens(text: str) -> str:
    cleaned = text.strip()
    lowered = cleaned.lower()
    thought_prefixes = ("<|channel>thought", "<|channel|>thought")
    if not lowered.startswith(thought_prefixes):
        return cleaned

    final_markers = ("<|channel>final", "<|channel|>final")
    for marker in final_markers:
        index = lowered.find(marker)
        if index != -1:
            cleaned = cleaned[index + len(marker):]
            break
    else:
        cleaned = re.sub(
            r"^\s*<\|channel\|?>\s*thought\s*",
            "",
            cleaned,
            count=1,
            flags=re.IGNORECASE,
        )

    return re.sub(
        r"^(?:\s*<\|(?:message|channel)\|?>\s*)+",
        "",
        cleaned,
        flags=re.IGNORECASE,
    ).strip()


def _parse_native_gemma_tool_call(raw: str) -> dict[str, Any] | None:
    match = re.search(
        r'<\|tool_call>call:(\w+)\{(.*?)\}<tool_call\|>',
        raw,
        re.DOTALL,
    )
    if not match:
        return None

    name = match.group(1)
    args_raw = match.group(2)
    arguments: dict[str, Any] = {}

    for arg_match in re.finditer(r'(\w+):<\|"\|>(.*?)<\|"\|>', args_raw, re.DOTALL):
        arguments[arg_match.group(1)] = arg_match.group(2)

    for arg_match in re.finditer(r"(\w+):([^,}]+)", args_raw):
        key = arg_match.group(1)
        if key in arguments:
            continue
        value = _parse_native_gemma_bare_value(arg_match.group(2).strip())
        if value is _INVALID_NATIVE_GEMMA_VALUE:
            return None
        arguments[key] = value

    if args_raw.strip() and not arguments:
        return None

    return {"name": name, "arguments": arguments}


def _parse_native_gemma_bare_value(value: str) -> Any:
    lower_value = value.lower()
    if lower_value == "true":
        return True
    if lower_value == "false":
        return False

    try:
        return int(value)
    except ValueError:
        pass

    try:
        return float(value)
    except ValueError:
        return _INVALID_NATIVE_GEMMA_VALUE


def _json_type_for(annotation: Any) -> str:
    if annotation is str:
        return "string"
    if annotation is int:
        return "integer"
    if annotation is float:
        return "number"
    if annotation is bool:
        return "boolean"
    if annotation in (list, tuple):
        return "array"
    if annotation is dict:
        return "object"
    return "string"
