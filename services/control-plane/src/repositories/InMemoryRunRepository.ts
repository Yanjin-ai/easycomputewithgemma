import type { Run } from "../types";
import type { IRunRepository } from "./IRunRepository";

export class InMemoryRunRepository implements IRunRepository {
  private readonly runs = new Map<string, Run>();

  async findById(id: string): Promise<Run | null> {
    return this.runs.get(id) ?? null;
  }

  async findByTaskId(taskId: string): Promise<Run[]> {
    return Array.from(this.runs.values())
      .filter((run) => run.task_id === taskId)
      .sort((a, b) => a.attempt_index - b.attempt_index);
  }

  async save(run: Run): Promise<Run> {
    this.runs.set(run.run_id, run);
    return run;
  }

  async update(id: string, patch: Partial<Run>): Promise<Run> {
    const existing = this.runs.get(id);
    if (!existing) {
      throw new Error(`Run not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    this.runs.set(id, updated);
    return updated;
  }
}
