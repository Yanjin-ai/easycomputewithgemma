import type { Event } from "../types";

export interface IEventRepository {
  findById(id: string): Promise<Event | null>;
  findByTaskId(taskId: string, limit: number, before?: string): Promise<Event[]>;
  save(event: Event): Promise<Event>;
  update(id: string, patch: Partial<Event>): Promise<Event>;
}
