// Generated from packages/schemas/*.schema.json via json-schema-to-typescript.
// Do not hand-write schema-derived types in this file.
export type {
  Approval,
  Device,
  HandoffPayload,
  Task,
  TaskDraft
} from "./generated";
import type {
  Event as GeneratedEvent,
  EventInput as GeneratedEventInput,
  Run as GeneratedRun,
  Task
} from "./generated";

export type PermissionLevel = "local_only" | "private_lan" | "cloud_ok";
export type Runtime = "mobile" | "desktop" | "cloud";
export type RunState = "pending" | "running" | "paused" | "completed" | "failed" | "handed_off" | "cancelled";
export type RunEventType = GeneratedEvent["event_type"] | "run.cancelled" | "task.retry_requested";
export type Run = Omit<GeneratedRun, "state"> & { state: RunState; output_summary?: string };
export type Event = Omit<GeneratedEvent, "event_type"> & { event_type: RunEventType };
export type EventInput = Omit<GeneratedEventInput, "event_type"> & { event_type: RunEventType };

// Derived from generated schema types — keeps callers from depending on nested generics.
export type TaskState = Task["current_state"];

// ⚠️ no-source: HeartbeatPayload and RuntimeHeartbeat have protocol fields
// but no dedicated schema file. Defined in routing_policy.md prose.
export interface HeartbeatPayload {
  device_id: string;
  is_online: boolean;
  battery_level?: number;
  network_type: "wifi" | "cellular" | "offline";
  cpu_load?: number;
  available_memory_mb?: number;
  active_run_count: number;
  supported_tools: string[];
  supported_capabilities: string[];
}

export interface RuntimeHeartbeat extends HeartbeatPayload {
  runtime_id: string;
  runtime_type: Runtime;
  permission_scope: PermissionLevel;
  last_heartbeat_at: string;
}

// ⚠️ no-source: RoutingDecision is defined in routing_policy.md prose, not a schema file.
export interface RoutingDecision {
  // Success path
  selected?: string;
  target_runtime?: Runtime;
  // Failure path
  failure_reason?: "no_runtime_online" | "permission_blocked" | "capability_gap" | "local_only_no_runtime";
  // Both paths
  decision_reason: string;
  considered_runtimes: unknown[];
  policy_version: string;
}
