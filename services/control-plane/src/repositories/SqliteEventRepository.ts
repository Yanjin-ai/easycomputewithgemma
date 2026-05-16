import type { Event } from "../types";
import type { IEventRepository } from "./IEventRepository";
import { db } from "./db";

type EventRow = {
  event_id: string;
  task_id: string;
  run_id: string | null;
  event_type: Event["event_type"];
  source: Event["source"];
  emitted_at: string;
  recorded_at: string;
  schema_version: string;
  payload: string;
};

const selectColumns = `
  event_id,
  task_id,
  run_id,
  event_type,
  source,
  emitted_at,
  recorded_at,
  schema_version,
  payload
`;

const findByIdStatement = db.prepare(`SELECT ${selectColumns} FROM events WHERE event_id = ?`);
const findByTaskIdStatement = db.prepare(`
  SELECT ${selectColumns}
  FROM events
  WHERE task_id = ?
  ORDER BY recorded_at ASC, event_id ASC
  LIMIT ?
`);
const findByTaskIdAfterCursorStatement = db.prepare(`
  SELECT ${selectColumns}
  FROM events
  WHERE task_id = ?
    AND (
      recorded_at > (SELECT recorded_at FROM events WHERE event_id = ?)
      OR (
        recorded_at = (SELECT recorded_at FROM events WHERE event_id = ?)
        AND event_id > ?
      )
    )
  ORDER BY recorded_at ASC, event_id ASC
  LIMIT ?
`);
const saveStatement = db.prepare(`
  INSERT OR REPLACE INTO events (
    event_id,
    task_id,
    run_id,
    event_type,
    source,
    emitted_at,
    recorded_at,
    schema_version,
    payload
  ) VALUES (
    @event_id,
    @task_id,
    @run_id,
    @event_type,
    @source,
    @emitted_at,
    @recorded_at,
    @schema_version,
    @payload
  )
`);

function toEvent(row: EventRow): Event {
  return {
    schema_version: row.schema_version,
    event_id: row.event_id,
    event_type: row.event_type,
    task_id: row.task_id,
    ...(row.run_id ? { run_id: row.run_id } : {}),
    source: row.source,
    emitted_at: row.emitted_at,
    recorded_at: row.recorded_at,
    payload: JSON.parse(row.payload) as Event["payload"]
  };
}

function toRow(event: Event) {
  return {
    event_id: event.event_id,
    task_id: event.task_id,
    run_id: event.run_id ?? null,
    event_type: event.event_type,
    source: event.source,
    emitted_at: event.emitted_at,
    recorded_at: event.recorded_at,
    schema_version: event.schema_version,
    payload: JSON.stringify(event.payload)
  };
}

export class SqliteEventRepository implements IEventRepository {
  async findById(id: string): Promise<Event | null> {
    const row = findByIdStatement.get(id) as EventRow | undefined;
    return Promise.resolve(row ? toEvent(row) : null);
  }

  async findByTaskId(taskId: string, limit: number, cursor?: string): Promise<Event[]> {
    const rows = (cursor
      ? findByTaskIdAfterCursorStatement.all(taskId, cursor, cursor, cursor, limit)
      : findByTaskIdStatement.all(taskId, limit)) as EventRow[];
    return Promise.resolve(rows.map(toEvent));
  }

  async save(event: Event): Promise<Event> {
    saveStatement.run(toRow(event));
    return Promise.resolve(event);
  }

  async update(id: string, patch: Partial<Event>): Promise<Event> {
    const existing = await this.findById(id);
    if (!existing) {
      throw new Error(`Event not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    saveStatement.run(toRow(updated));
    return Promise.resolve(updated);
  }
}
