import type { HandoffPayload, Runtime } from "../types";
import type { IHandoffRepository } from "./IHandoffRepository";
import { db } from "./db";

type HandoffRow = {
  handoff_id: string;
  source_run_id: string;
  target_runtime: Runtime;
  task_context: string;
  delivered: 0 | 1;
  created_at: string;
  raw_payload: string;
};

const selectColumns = `
  handoff_id,
  source_run_id,
  target_runtime,
  task_context,
  delivered,
  created_at,
  raw_payload
`;

const saveStatement = db.prepare(`
  INSERT OR REPLACE INTO handoffs (
    handoff_id,
    source_run_id,
    target_runtime,
    task_context,
    delivered,
    created_at,
    raw_payload
  ) VALUES (
    @handoff_id,
    @source_run_id,
    @target_runtime,
    @task_context,
    @delivered,
    @created_at,
    @raw_payload
  )
`);
const findPendingByRuntimeStatement = db.prepare(`
  SELECT ${selectColumns}
  FROM handoffs
  WHERE target_runtime = ? AND delivered = 0
  ORDER BY created_at ASC, handoff_id ASC
`);
const markDeliveredStatement = db.prepare(
  `UPDATE handoffs SET delivered = 1 WHERE handoff_id = ?`
);

const drainPendingByRuntime = db.transaction((targetRuntime: Runtime): HandoffPayload[] => {
  const rows = findPendingByRuntimeStatement.all(targetRuntime) as HandoffRow[];
  for (const row of rows) {
    markDeliveredStatement.run(row.handoff_id);
  }
  return rows.map(toHandoff);
});

function toHandoff(row: HandoffRow): HandoffPayload {
  return JSON.parse(row.raw_payload) as HandoffPayload;
}

function toRow(payload: HandoffPayload) {
  return {
    handoff_id: payload.handoff_id,
    source_run_id: payload.source_run_id,
    target_runtime: payload.target_runtime,
    task_context: JSON.stringify(payload.task_context),
    delivered: 0,
    created_at: payload.initiated_at,
    raw_payload: JSON.stringify(payload)
  };
}

export class SqliteHandoffRepository implements IHandoffRepository {
  async save(payload: HandoffPayload): Promise<HandoffPayload> {
    saveStatement.run(toRow(payload));
    return Promise.resolve(payload);
  }

  async findPendingByRuntime(targetRuntime: Runtime): Promise<HandoffPayload[]> {
    return Promise.resolve(drainPendingByRuntime(targetRuntime));
  }

  async markDelivered(handoffId: string): Promise<void> {
    markDeliveredStatement.run(handoffId);
    return Promise.resolve();
  }
}
