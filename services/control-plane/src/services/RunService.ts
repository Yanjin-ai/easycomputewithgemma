import { randomUUID } from "crypto";
import { NotFoundError } from "../middleware/errorHandler";
import type { IRunRepository } from "../repositories/IRunRepository";
import type { Run, RunState, Runtime } from "../types";
import type { EventService } from "./EventService";

export class RunService {
  constructor(
    private readonly repository: IRunRepository,
    private eventService?: EventService
  ) {}

  setEventService(eventService: EventService): void {
    this.eventService = eventService;
  }

  /**
   * Creates a new bounded execution attempt for a Task on one runtime.
   */
  async create(
    taskId: string,
    runtime: Runtime,
    attemptIndex = 1,
    handoffPayloadId?: string
  ): Promise<Run> {
    const run: Run = {
      schema_version: "1.0.0",
      run_id: randomUUID(),
      task_id: taskId,
      runtime,
      state: "pending",
      attempt_index: attemptIndex,
      created_at: new Date().toISOString(),
      checkpoint_count: 0,
      ...(handoffPayloadId ? { handoff_payload_id: handoffPayloadId } : {})
    };

    const savedRun = await this.repository.save(run);
    const eventService = this.requireEventService();
    const event = await eventService.append({
      schema_version: "1.0.0",
      task_id: taskId,
      run_id: savedRun.run_id,
      source: "control-plane",
      event_type: "run.created",
      emitted_at: savedRun.created_at,
      payload: {
        attempt_index: savedRun.attempt_index
      }
    });
    await eventService.processStateTransition(event);

    return savedRun;
  }

  async getById(runId: string): Promise<Run | null> {
    return this.repository.findById(runId);
  }

  async getRunsForTask(taskId: string): Promise<Run[]> {
    return this.repository.findByTaskId(taskId);
  }

  /**
   * Updates Run.state from state-machine events only.
   * Route handlers must not call this directly except through EventService processing.
   */
  async updateState(
    runId: string,
    newState: RunState,
    patch: Partial<Omit<Run, "run_id" | "state">> = {}
  ): Promise<Run> {
    const existing = await this.repository.findById(runId);
    if (!existing) {
      throw new NotFoundError(`Run not found: ${runId}`);
    }

    return this.repository.update(runId, { ...patch, state: newState });
  }

  async incrementCheckpointCount(runId: string): Promise<Run> {
    const existing = await this.repository.findById(runId);
    if (!existing) {
      throw new NotFoundError(`Run not found: ${runId}`);
    }

    return this.repository.update(runId, {
      checkpoint_count: existing.checkpoint_count + 1
    });
  }

  async storeOutputSummary(runId: string, summary: string): Promise<Run> {
    const existing = await this.repository.findById(runId);
    if (!existing) {
      throw new NotFoundError(`Run not found: ${runId}`);
    }

    return this.repository.update(runId, { output_summary: summary });
  }

  /**
   * Returns the single active Run for a Task under the v1 no-concurrency constraint.
   */
  async getActiveRunForTask(taskId: string): Promise<Run | null> {
    const terminalStates: ReadonlySet<RunState> = new Set([
      "completed",
      "failed",
      "handed_off",
      "cancelled"
    ]);
    const runs = await this.repository.findByTaskId(taskId);

    return runs.find((run) => !terminalStates.has(run.state)) ?? null;
  }

  private requireEventService(): EventService {
    if (!this.eventService) {
      throw new Error("RunService requires EventService to create runs");
    }

    return this.eventService;
  }
}
