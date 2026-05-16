import { randomUUID } from "node:crypto";
import { NotFoundError } from "../middleware/errorHandler";
import type { IHandoffRepository } from "../repositories/IHandoffRepository";
import type { IRunRepository } from "../repositories/IRunRepository";
import type { ITaskRepository } from "../repositories/ITaskRepository";
import type { HandoffPayload, RunState, Runtime } from "../types";
import type { EventService } from "./EventService";

const TERMINAL_RUN_STATES: ReadonlySet<RunState> = new Set([
  "completed",
  "failed",
  "handed_off",
  "cancelled"
]);

export class HandoffService {
  constructor(
    private readonly taskRepo: ITaskRepository,
    private readonly runRepo: IRunRepository,
    private readonly eventService: EventService,
    private readonly handoffRepo: IHandoffRepository
  ) {}

  /**
   * Constructs a complete HandoffPayload from a Task, active Run, checkpoint, and routing target.
   */
  async create(
    taskId: string,
    targetRuntime: Runtime,
    reason: string,
    initiatedBy: "system" | "user"
  ): Promise<HandoffPayload> {
    const task = await this.taskRepo.findById(taskId);
    if (!task) {
      throw new NotFoundError(`Task not found: ${taskId}`);
    }

    const activeRun = (await this.runRepo.findByTaskId(taskId))
      .filter((run) => !TERMINAL_RUN_STATES.has(run.state))
      .sort((a, b) => {
        const createdOrder = b.created_at.localeCompare(a.created_at);
        return createdOrder === 0 ? b.attempt_index - a.attempt_index : createdOrder;
      })[0];

    if (!activeRun) {
      throw new NotFoundError(`Active Run not found for Task: ${taskId}`);
    }

    const initiatedAt = new Date().toISOString();
    const payload: HandoffPayload = {
      schema_version: "1.0.0",
      handoff_id: randomUUID(),
      task_id: task.task_id,
      source_run_id: activeRun.run_id,
      target_runtime: targetRuntime,
      permission_level: task.permission_level,
      checkpoint_data: {
        steps_completed: [],
        current_step: "",
        tool_call_history: [],
        variables: {},
        pending_actions: [],
        runtime_specific: {}
      },
      task_context: {
        intent: task.intent_summary,
        goal: {},
        constraints: {
          permission_level: task.permission_level,
          allowed_tools: task.required_tools
        }
      },
      initiated_by: initiatedBy,
      initiated_at: initiatedAt,
      reason
    };

    const initiatedEvent = await this.eventService.append({
      schema_version: "1.0.0",
      event_type: "handoff.initiated",
      task_id: task.task_id,
      run_id: activeRun.run_id,
      source: "control-plane",
      emitted_at: initiatedAt,
      payload: {
        handoff_id: payload.handoff_id,
        source_run_id: payload.source_run_id,
        target_runtime: payload.target_runtime,
        initiated_by: payload.initiated_by,
        reason: payload.reason
      }
    });
    await this.eventService.processStateTransition(initiatedEvent);

    return payload;
  }

  /**
   * Dispatches a HandoffPayload to the target runtime.
   * v1 delivery is HTTP polling: the target runtime drains pending handoffs.
   */
  async dispatch(payload: HandoffPayload): Promise<void> {
    const dispatchedAt = new Date().toISOString();
    await this.eventService.append({
      schema_version: "1.0.0",
      event_type: "handoff.dispatched",
      task_id: payload.task_id,
      run_id: payload.source_run_id,
      source: "control-plane",
      emitted_at: dispatchedAt,
      payload: {
        handoff_id: payload.handoff_id,
        dispatched_at: dispatchedAt
      }
    });
    await this.handoffRepo.save(payload);
  }

  async getPending(targetRuntime: Runtime): Promise<HandoffPayload[]> {
    const handoffs = await this.handoffRepo.findPendingByRuntime(targetRuntime);
    for (const handoff of handoffs) {
      await this.handoffRepo.markDelivered(handoff.handoff_id);
    }
    return handoffs;
  }
}
