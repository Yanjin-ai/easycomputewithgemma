import type { Run } from "../types";
import type { IRunRepository } from "./IRunRepository";
import { db } from "./db";

type RunRow = {
  run_id: string;
  task_id: string;
  state: Run["state"];
  runtime: Run["runtime"];
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
  schema_version: string;
  attempt_index: number;
  model_id: string | null;
  ended_at: string | null;
  checkpoint_count: number;
  handoff_payload_id: string | null;
  error_detail: string | null;
  output_summary: string | null;
};

const selectColumns = `
  run_id,
  task_id,
  state,
  runtime,
  started_at,
  completed_at,
  created_at,
  schema_version,
  attempt_index,
  model_id,
  ended_at,
  checkpoint_count,
  handoff_payload_id,
  error_detail,
  output_summary
`;

const findByIdStatement = db.prepare(`SELECT ${selectColumns} FROM runs WHERE run_id = ?`);
const findByTaskIdStatement = db.prepare(
  `SELECT ${selectColumns} FROM runs WHERE task_id = ? ORDER BY attempt_index ASC`
);
const saveStatement = db.prepare(`
  INSERT OR REPLACE INTO runs (
    run_id,
    task_id,
    state,
    runtime,
    started_at,
    completed_at,
    created_at,
    schema_version,
    attempt_index,
    model_id,
    ended_at,
    checkpoint_count,
    handoff_payload_id,
    error_detail,
    output_summary
  ) VALUES (
    @run_id,
    @task_id,
    @state,
    @runtime,
    @started_at,
    @completed_at,
    @created_at,
    @schema_version,
    @attempt_index,
    @model_id,
    @ended_at,
    @checkpoint_count,
    @handoff_payload_id,
    @error_detail,
    @output_summary
  )
`);

function toRun(row: RunRow): Run {
  return {
    schema_version: row.schema_version,
    run_id: row.run_id,
    task_id: row.task_id,
    runtime: row.runtime,
    state: row.state,
    attempt_index: row.attempt_index,
    ...(row.model_id ? { model_id: row.model_id } : {}),
    created_at: row.created_at,
    ...(row.started_at ? { started_at: row.started_at } : {}),
    ...(row.ended_at ?? row.completed_at ? { ended_at: row.ended_at ?? row.completed_at ?? undefined } : {}),
    checkpoint_count: row.checkpoint_count,
    ...(row.handoff_payload_id ? { handoff_payload_id: row.handoff_payload_id } : {}),
    ...(row.error_detail ? { error_detail: row.error_detail } : {}),
    ...(row.output_summary ? { output_summary: row.output_summary } : {})
  };
}

function toRow(run: Run) {
  return {
    run_id: run.run_id,
    task_id: run.task_id,
    state: run.state,
    runtime: run.runtime,
    started_at: run.started_at ?? null,
    completed_at: run.ended_at ?? null,
    created_at: run.created_at,
    schema_version: run.schema_version,
    attempt_index: run.attempt_index,
    model_id: run.model_id ?? null,
    ended_at: run.ended_at ?? null,
    checkpoint_count: run.checkpoint_count,
    handoff_payload_id: run.handoff_payload_id ?? null,
    error_detail: run.error_detail ?? null,
    output_summary: run.output_summary ?? null
  };
}

export class SqliteRunRepository implements IRunRepository {
  async findById(id: string): Promise<Run | null> {
    const row = findByIdStatement.get(id) as RunRow | undefined;
    return Promise.resolve(row ? toRun(row) : null);
  }

  async findByTaskId(taskId: string): Promise<Run[]> {
    const rows = findByTaskIdStatement.all(taskId) as RunRow[];
    return Promise.resolve(rows.map(toRun));
  }

  async save(run: Run): Promise<Run> {
    saveStatement.run(toRow(run));
    return Promise.resolve(run);
  }

  async update(id: string, patch: Partial<Run>): Promise<Run> {
    const existing = await this.findById(id);
    if (!existing) {
      throw new Error(`Run not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    saveStatement.run(toRow(updated));
    return Promise.resolve(updated);
  }
}
