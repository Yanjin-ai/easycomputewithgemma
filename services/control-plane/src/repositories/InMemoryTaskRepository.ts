import type { Task } from "../types";
import type { ITaskRepository, TaskCounts } from "./ITaskRepository";

const COUNTED_TASK_STATES = [
  "pending",
  "routing",
  "scheduled",
  "running",
  "paused",
  "completed",
  "failed",
  "cancelled"
] as const;

export class InMemoryTaskRepository implements ITaskRepository {
  private readonly tasks = new Map<string, Task>();

  async findById(id: string): Promise<Task | null> {
    return this.tasks.get(id) ?? null;
  }

  async findAll(limit: number, before?: string, state?: string): Promise<Task[]> {
    const cursorTask = before ? this.tasks.get(before) : undefined;

    return Array.from(this.tasks.values())
      .filter((task) => !state || task.current_state === state)
      .filter(
        (task) =>
          !cursorTask ||
          task.created_at < cursorTask.created_at ||
          (task.created_at === cursorTask.created_at && task.task_id < cursorTask.task_id)
      )
      .sort(
        (a, b) => b.created_at.localeCompare(a.created_at) || b.task_id.localeCompare(a.task_id)
      )
      .slice(0, limit);
  }

  async countByState(): Promise<TaskCounts> {
    const counts = Object.fromEntries(COUNTED_TASK_STATES.map((state) => [state, 0])) as Omit<
      TaskCounts,
      "total"
    >;

    for (const task of this.tasks.values()) {
      if (task.current_state in counts) {
        counts[task.current_state as keyof typeof counts] += 1;
      }
    }

    return {
      ...counts,
      total: this.tasks.size
    };
  }

  async save(task: Task): Promise<Task> {
    this.tasks.set(task.task_id, task);
    return task;
  }

  async update(id: string, patch: Partial<Task>): Promise<Task> {
    const existing = this.tasks.get(id);
    if (!existing) {
      throw new Error(`Task not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    this.tasks.set(id, updated);
    return updated;
  }
}
