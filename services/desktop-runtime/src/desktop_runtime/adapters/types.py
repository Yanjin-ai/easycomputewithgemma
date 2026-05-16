from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

PermissionLevel = Literal["local_only", "private_lan", "cloud_ok"]
Runtime = Literal["mobile", "desktop", "cloud"]
ArtifactType = Literal["file", "image", "audio", "document"]


@dataclass
class CheckpointData:
    steps_completed: list[str] = field(default_factory=list)
    current_step: str = ""
    tool_call_history: list[dict[str, Any]] = field(default_factory=list)
    variables: dict[str, Any] = field(default_factory=dict)
    pending_actions: list[Any] = field(default_factory=list)
    runtime_specific: dict[str, Any] = field(default_factory=dict)
    conversation_history: list[dict[str, Any]] = field(default_factory=list)
    step_index: int = 0


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
    run_id: str | None = None


@dataclass
class Event:
    event_id: str
    event_type: str
    task_id: str
    source: str
    emitted_at: str
    recorded_at: str
    payload: dict[str, Any]
    run_id: str | None = None
    schema_version: str = "1.0.0"


@dataclass
class Artifact:
    artifact_id: str
    task_id: str
    run_id: str
    artifact_type: ArtifactType
    filename: str
    artifact_state: Literal["created", "uploaded"] = "created"
    storage_ref: str | None = None
    size_bytes: int | None = None
    content_hash: str | None = None
