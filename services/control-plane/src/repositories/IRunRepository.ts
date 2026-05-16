import type { Run } from "../types";

export interface IRunRepository {
  findById(id: string): Promise<Run | null>;
  findByTaskId(taskId: string): Promise<Run[]>;
  save(run: Run): Promise<Run>;
  update(id: string, patch: Partial<Run>): Promise<Run>;
}
