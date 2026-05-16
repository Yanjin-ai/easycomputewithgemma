from __future__ import annotations

import pytest

from desktop_runtime.adapters.inference_adapter import LiteRTConversationSession
from desktop_runtime.adapters.types import HandoffPayload, TaskContext
from desktop_runtime.tool_registry import ToolRegistry
from desktop_runtime.worker import DesktopWorker


class FakeSession:
    def __init__(self, response: str) -> None:
        self.response = response
        self.messages: list[str] = []

    def send(self, message: str) -> str:
        self.messages.append(message)
        return self.response


class FakeInference:
    def __init__(self, response: str) -> None:
        self.session = FakeSession(response)

    def new_session(self) -> FakeSession:
        return self.session


class FakeCheckpointStore:
    def __init__(self) -> None:
        self.cleared: list[str] = []

    def load(self, run_id: str) -> None:
        return None

    def clear(self, run_id: str) -> None:
        self.cleared.append(run_id)


class FakeReporter:
    def __init__(self) -> None:
        self.events: list[dict] = []

    async def report(self, event_type: str, task_id: str, payload: dict, run_id=None):
        self.events.append(
            {
                "event_type": event_type,
                "task_id": task_id,
                "run_id": run_id,
                "payload": payload,
            }
        )
        return {}


class FakeEngineConversation:
    def __init__(self) -> None:
        self.messages: list[dict] = []

    def send_message(self, message: dict) -> dict:
        self.messages.append(message)
        return {"content": [{"text": "ok"}]}


class FakeEngine:
    def __init__(self) -> None:
        self.conversation = FakeEngineConversation()

    def create_conversation(self) -> FakeEngineConversation:
        return self.conversation


def make_payload(intent: str = "What is 2+2?") -> HandoffPayload:
    return HandoffPayload(
        handoff_id="handoff-1",
        task_id="task-1",
        source_run_id="run-1",
        target_runtime="desktop",
        permission_level="local_only",
        checkpoint_data=None,
        task_context=TaskContext(
            intent_summary=intent,
            permission_level="local_only",
            allowed_tools=["echo"],
        ),
        initiated_by="user",
        initiated_at="2026-05-16T00:00:00+00:00",
        reason="test",
        run_id="run-1",
    )


def test_litert_session_sends_plain_user_content() -> None:
    engine = FakeEngine()
    session = LiteRTConversationSession(engine)

    assert session.send("What is 2+2?") == "ok"
    assert engine.conversation.messages == [
        {"role": "user", "content": "What is 2+2?"}
    ]


def test_parse_native_gemma_tool_call_with_string_arg() -> None:
    worker = DesktopWorker.__new__(DesktopWorker)

    call = worker._parse_function_call(
        '<|tool_call>call:task_completed{summary:<|"|>done<|"|>}<tool_call|>'
    )

    assert call == {"name": "task_completed", "arguments": {"summary": "done"}}


def test_parse_native_gemma_tool_call_with_numeric_arg() -> None:
    worker = DesktopWorker.__new__(DesktopWorker)

    call = worker._parse_function_call(
        '<|tool_call>call:set_volume{level:42,enabled:true}<tool_call|>'
    )

    assert call == {
        "name": "set_volume",
        "arguments": {"level": 42, "enabled": True},
    }


def test_parse_json_tool_call_format_still_works() -> None:
    worker = DesktopWorker.__new__(DesktopWorker)

    call = worker._parse_function_call(
        '[TOOL_CALL] {"name": "echo", "arguments": {"message": "hello"}}'
    )

    assert call == {"name": "echo", "arguments": {"message": "hello"}}


def test_parse_malformed_tool_call_returns_none() -> None:
    worker = DesktopWorker.__new__(DesktopWorker)

    assert (
        worker._parse_function_call(
            "<|tool_call>call:echo{message:oops}<tool_call|>"
        )
        is None
    )


@pytest.mark.anyio
async def test_plain_text_response_is_reported_as_summary() -> None:
    inference = FakeInference("  4  ")
    reporter = FakeReporter()
    checkpoints = FakeCheckpointStore()
    worker = DesktopWorker(
        inference=inference,
        tool_registry=ToolRegistry(),
        checkpoint_store=checkpoints,
        reporter=reporter,
        model_path="model.litertlm",
    )

    await worker._execute_run(make_payload())

    completed = [
        event for event in reporter.events if event["event_type"] == "run.completed"
    ]
    assert completed[0]["payload"]["summary"] == "4"
    assert checkpoints.cleared == ["run-1"]
    assert len(inference.session.messages) == 1
    assert "Task: What is 2+2?" in inference.session.messages[0]


@pytest.mark.anyio
async def test_gemma_thinking_tokens_are_stripped_from_summary() -> None:
    inference = FakeInference(
        "<|channel>thought scratch work<|channel>final  The answer is 4.  "
    )
    reporter = FakeReporter()
    worker = DesktopWorker(
        inference=inference,
        tool_registry=ToolRegistry(),
        checkpoint_store=FakeCheckpointStore(),
        reporter=reporter,
        model_path="model.litertlm",
    )

    await worker._execute_run(make_payload())

    completed = [
        event for event in reporter.events if event["event_type"] == "run.completed"
    ]
    assert completed[0]["payload"]["summary"] == "The answer is 4."
