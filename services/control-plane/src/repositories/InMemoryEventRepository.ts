import type { Event } from "../types";
import type { IEventRepository } from "./IEventRepository";

export class InMemoryEventRepository implements IEventRepository {
  private readonly events = new Map<string, Event>();

  async findById(id: string): Promise<Event | null> {
    return this.events.get(id) ?? null;
  }

  async findByTaskId(taskId: string, limit: number, before?: string): Promise<Event[]> {
    return [...this.events.values()]
      .filter((event) => event.task_id === taskId)
      .filter((event) => before === undefined || event.event_id < before)
      .sort((a, b) => a.emitted_at.localeCompare(b.emitted_at))
      .slice(0, limit);
  }

  async save(event: Event): Promise<Event> {
    this.events.set(event.event_id, event);
    return event;
  }

  async update(id: string, patch: Partial<Event>): Promise<Event> {
    const existing = this.events.get(id);
    if (!existing) {
      throw new Error(`Event not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    this.events.set(id, updated);
    return updated;
  }
}
