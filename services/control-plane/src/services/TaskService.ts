import { randomUUID } from "node:crypto";
import { NotFoundError } from "../middleware/errorHandler";
import type { ITaskRepository, TaskCounts } from "../repositories/ITaskRepository";
import type { Task, TaskDraft, TaskState } from "../types";
import type { EventService } from "./EventService";
import type { RoutingEngine } from "./RoutingEngine";

type DraftSubmissionFields = TaskDraft & {
  account_id?: string;
  task_title?: string;
  intent_summary?: string;
};

export class TaskService {
  constructor(
    private readonly repository: ITaskRepository,
    private readonly routingEngine: RoutingEngine,
    private readonly eventService: EventService
  ) {}

  /**
   * Accepts a schema-valid TaskDraft and creates a Task with initial state `pending`.
   * Routing is intentionally not performed here; RoutingEngine is triggered asynchronously.
   */
  async createFromDraft(draft: TaskDraft, submittedBy: string): Promise<Task> {
    void this.routingEngine;

    const submission = draft as DraftSubmissionFields;
    const now = new Date().toISOString();
    const task: Task = {
      schema_version: "1.0.0",
      task_id: randomUUID(),
      account_id: submission.account_id ?? submittedBy,
      task_title: submission.task_title ?? draft.intent,
      intent_summary: submission.intent_summary ?? draft.intent,
      permission_level: draft.permission_level,
      current_state: "pending",
      required_tools: draft.required_tools,
      required_capabilities: draft.required_capabilities,
      complexity_hint: draft.complexity_hint,
      submitted_by: submittedBy,
      created_at: now,
      last_updated_at: now,
      pending_approval: false,
      total_run_count: 0
    };

    const saved = await this.repository.save(task);
    const event = await this.eventService.append({
      schema_version: "1.0.0",
      event_type: "task.submitted",
      task_id: saved.task_id,
      source: "control-plane",
      emitted_at: now,
      payload: {
        task_title: saved.task_title,
        intent_summary: saved.intent_summary,
        permission_level: saved.permission_level,
        submitted_by: saved.submitted_by
      }
    });

    await this.eventService.processStateTransition(event);

    return saved;
  }

  /**
   * Lists Tasks with cursor-style pagination, sorted by created_at descending.
   */
  async list(limit: number, before?: string, state?: string): Promise<Task[]> {
    return this.repository.findAll(limit, before, state);
  }

  async countByState(): Promise<TaskCounts> {
    return this.repository.countByState();
  }

  /**
   * Loads the current Task snapshot for API reads and observability views.
   */
  async getById(taskId: string): Promise<Task | null> {
    return this.repository.findById(taskId);
  }

  /**
   * Updates Task.current_state from state-machine events only.
   * Route handlers must not call this directly except through EventService processing.
   */
  async updateState(
    taskId: string,
    newState: TaskState,
    patch: Partial<Omit<Task, "task_id" | "current_state">> = {}
  ): Promise<Task> {
    const existing = await this.repository.findById(taskId);
    if (!existing) {
      throw new NotFoundError(`Task not found: ${taskId}`);
    }

    return this.repository.update(taskId, {
      ...patch,
      current_state: newState,
      last_updated_at: new Date().toISOString()
    });
  }
}
