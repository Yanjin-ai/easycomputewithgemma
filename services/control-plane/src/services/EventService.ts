import * as crypto from "node:crypto";
import { NotFoundError } from "../middleware/errorHandler";
import type { IEventRepository } from "../repositories/IEventRepository";
import type { Event, EventInput, Run, RunState, Runtime, Task, TaskState } from "../types";
import type { RunService } from "./RunService";
import type { SchedulingOrchestrator } from "./SchedulingOrchestrator";
import type { SseBroadcaster } from "./SseBroadcaster";
import type { TaskService } from "./TaskService";

const TERMINAL_TASK_STATES: ReadonlySet<TaskState> = new Set(["completed", "failed", "cancelled"]);
const RUNTIMES: ReadonlySet<string> = new Set(["mobile", "desktop", "cloud"]);

export class EventService {
  constructor(
    private readonly repository: IEventRepository,
    private taskService?: TaskService,
    private runService?: RunService,
    private readonly broadcaster?: SseBroadcaster,
    private schedulingOrchestrator?: SchedulingOrchestrator
  ) {}

  setTaskAndRunServices(taskService: TaskService, runService: RunService): void {
    this.taskService = taskService;
    this.runService = runService;
  }

  setSchedulingOrchestrator(schedulingOrchestrator: SchedulingOrchestrator): void {
    this.schedulingOrchestrator = schedulingOrchestrator;
  }

  /**
   * Appends an immutable event to the event stream.
   */
  async append(body: EventInput): Promise<Event> {
    const event: Event = {
      ...body,
      schema_version: body.schema_version ?? "1.0.0",
      event_id: crypto.randomUUID(),
      recorded_at: new Date().toISOString()
    };

    return this.repository.save(event);
  }

  /**
   * Queries a Task event stream sorted by emitted_at with cursor-style pagination.
   */
  async queryByTaskId(taskId: string, limit: number, before?: string): Promise<Event[]> {
    return this.repository.findByTaskId(taskId, limit, before);
  }

  /**
   * Applies Task/Run state-machine transitions based on event_type.
   * This is the only allowed path for Task.current_state and Run.state changes.
   */
  async processStateTransition(event: Event): Promise<void> {
    const taskService = this.requireTaskService();
    const runService = this.requireRunService();

    const task = await taskService.getById(event.task_id);
    if (!task) {
      throw new NotFoundError(`Task not found: ${event.task_id}`);
    }

    const isFailedResubmission = event.event_type === "task.submitted" && task.current_state === "failed";
    const isRetryRequest = event.event_type === "task.retry_requested";
    if (TERMINAL_TASK_STATES.has(task.current_state) && !isFailedResubmission && !isRetryRequest) {
      console.warn(
        `Ignoring ${event.event_type} for terminal Task ${event.task_id} in state ${task.current_state}`
      );
      return;
    }

    const run = event.run_id ? await runService.getById(event.run_id) : null;
    if (event.run_id && !run) {
      throw new NotFoundError(`Run not found: ${event.run_id}`);
    }

    const now = new Date().toISOString();

    switch (event.event_type) {
      case "task.submitted":
        if (task.current_state !== "pending" && task.current_state !== "failed") {
          console.warn(
            `Ignoring task.submitted for Task ${task.task_id} in state ${task.current_state}`
          );
          return;
        }
        await this.updateTaskIfState(task, undefined, "pending");
        void this.schedulingOrchestrator?.scheduleTask({ ...task, current_state: "pending" });
        break;

      case "route.started":
        await this.updateTaskIfState(task, "pending", "routing");
        break;

      case "route.decided":
        await this.updateTaskIfState(task, "routing", "scheduled", {
          current_runtime: this.getTargetRuntime(event)
        });
        break;

      case "route.failed":
        await this.updateTaskIfState(task, "routing", "failed");
        break;

      case "run.created":
        await this.updateTaskIfState(task, "scheduled", "running");
        await this.updateRunIfState(run, undefined, "pending");
        break;

      case "run.started":
        if (run && (run.state === "pending" || run.state === "handed_off")) {
          await this.requireRunService().updateState(run.run_id, "running", { started_at: now });
        }
        break;

      case "run.step_completed":
        break;

      case "run.checkpoint_saved":
        if (run) {
          await runService.incrementCheckpointCount(run.run_id);
        }
        break;

      case "run.paused":
        await this.updateTaskIfState(task, "running", "paused");
        await this.updateRunIfState(run, "running", "paused");
        break;

      case "run.resumed":
        await this.updateTaskIfState(task, "paused", "running");
        await this.updateRunIfState(run, "paused", "running");
        break;

      case "run.completed":
        await this.updateTaskIfState(task, undefined, "completed");
        await this.updateRunIfState(run, "running", "completed", { ended_at: now });
        {
          const summary = this.getPayloadString(event, "summary");
          if (summary && run) {
            await runService.storeOutputSummary(run.run_id, summary);
          }
        }
        break;

      case "run.failed":
        await this.updateTaskIfState(task, "running", "failed");
        await this.updateRunIfState(run, "running", "failed", {
          ended_at: now,
          error_detail:
            this.getPayloadString(event, "error_message") ?? this.getPayloadString(event, "error")
        });
        break;

      case "run.cancelled":
        if (run && run.state !== "completed" && run.state !== "failed" && run.state !== "cancelled") {
          await runService.updateState(run.run_id, "cancelled", { ended_at: now });
        }
        break;

      case "task.cancelled": {
        await this.updateTaskIfState(task, undefined, "cancelled");
        const activeRun = await runService.getActiveRunForTask(event.task_id);
        if (activeRun) {
          await runService.updateState(activeRun.run_id, "cancelled", { ended_at: now });
        }
        break;
      }

      case "task.retry_requested":
        if (task.current_state === "failed" || task.current_state === "cancelled") {
          await this.updateTaskIfState(task, task.current_state, "pending");
          setImmediate(() => {
            void this.schedulingOrchestrator?.scheduleTask({
              ...task,
              current_state: "pending"
            });
          });
        }
        break;

      case "handoff.initiated":
        if (run && (run.state === "pending" || run.state === "running")) {
          await this.requireRunService().updateState(run.run_id, "handed_off");
        }
        break;

      case "approval.requested":
        await this.updateTaskIfState(task, "running", "paused", { pending_approval: true });
        await this.updateRunIfState(run, "running", "paused");
        break;

      case "approval.granted":
        await this.updateTaskIfState(task, "paused", "running", { pending_approval: false });
        await this.updateRunIfState(run, "paused", "running");
        break;

      case "approval.rejected":
      case "approval.expired":
        await this.updateTaskIfState(task, "paused", "failed");
        await this.updateRunIfState(run, "paused", "failed", { ended_at: now });
        break;

      default:
        return;
    }

    const updatedTask = await taskService.getById(event.task_id);
    if (updatedTask) {
      this.broadcaster?.broadcast(updatedTask.task_id, updatedTask);
    }
  }

  private requireTaskService(): TaskService {
    if (!this.taskService) {
      throw new Error("EventService requires TaskService for state transitions");
    }

    return this.taskService;
  }

  private requireRunService(): RunService {
    if (!this.runService) {
      throw new Error("EventService requires RunService for state transitions");
    }

    return this.runService;
  }

  private async updateTaskIfState(
    task: Task,
    expectedState: TaskState | undefined,
    nextState: TaskState,
    patch: Partial<Omit<Task, "task_id" | "current_state">> = {}
  ): Promise<void> {
    if (expectedState !== undefined && task.current_state !== expectedState) {
      console.warn(
        `Ignoring Task transition ${task.task_id}: expected ${expectedState}, got ${task.current_state}`
      );
      return;
    }

    await this.requireTaskService().updateState(task.task_id, nextState, patch);
  }

  private async updateRunIfState(
    run: Run | null,
    expectedState: RunState | undefined,
    nextState: RunState,
    patch: Partial<Omit<Run, "run_id" | "state">> = {}
  ): Promise<void> {
    if (!run) {
      return;
    }

    if (expectedState !== undefined && run.state !== expectedState) {
      console.warn(`Ignoring Run transition ${run.run_id}: expected ${expectedState}, got ${run.state}`);
      return;
    }

    await this.requireRunService().updateState(run.run_id, nextState, patch);
  }

  private getTargetRuntime(event: Event): Runtime | undefined {
    const targetRuntime = event.payload.target_runtime;
    return typeof targetRuntime === "string" && RUNTIMES.has(targetRuntime)
      ? (targetRuntime as Runtime)
      : undefined;
  }

  private getPayloadString(event: Event, key: string): string | undefined {
    const value = event.payload[key];
    return typeof value === "string" ? value : undefined;
  }
}
