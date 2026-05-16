import type { Task } from "../types";

export type TaskCounts = {
  pending: number;
  routing: number;
  scheduled: number;
  running: number;
  paused: number;
  completed: number;
  failed: number;
  cancelled: number;
  total: number;
};

export interface ITaskRepository {
  findById(id: string): Promise<Task | null>;
  findAll(limit: number, before?: string, state?: string): Promise<Task[]>;
  countByState(): Promise<TaskCounts>;
  save(task: Task): Promise<Task>;
  update(id: string, patch: Partial<Task>): Promise<Task>;
}
