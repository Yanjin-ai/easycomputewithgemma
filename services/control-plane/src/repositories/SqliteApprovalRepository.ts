import type { Approval } from "../types";
import type { IApprovalRepository } from "./IApprovalRepository";
import { db } from "./db";

type ApprovalRow = {
  approval_id: string;
  task_id: string;
  run_id: string;
  state: Approval["state"];
  trigger_type: Approval["trigger_type"];
  trigger_detail: string;
  action_description: string;
  requested_at: string;
  expires_at: string;
  responded_at: string | null;
  response_note: string | null;
  schema_version: string;
};

const selectColumns = `
  approval_id,
  task_id,
  run_id,
  state,
  trigger_type,
  trigger_detail,
  action_description,
  requested_at,
  expires_at,
  responded_at,
  response_note,
  schema_version
`;

const findByIdStatement = db.prepare(`SELECT ${selectColumns} FROM approvals WHERE approval_id = ?`);
const findPendingExpiredBeforeStatement = db.prepare(
  `SELECT ${selectColumns} FROM approvals WHERE state = 'pending' AND expires_at < ?`
);
const saveStatement = db.prepare(`
  INSERT OR REPLACE INTO approvals (
    approval_id,
    task_id,
    run_id,
    state,
    trigger_type,
    trigger_detail,
    action_description,
    requested_at,
    expires_at,
    responded_at,
    response_note,
    schema_version
  ) VALUES (
    @approval_id,
    @task_id,
    @run_id,
    @state,
    @trigger_type,
    @trigger_detail,
    @action_description,
    @requested_at,
    @expires_at,
    @responded_at,
    @response_note,
    @schema_version
  )
`);

function toApproval(row: ApprovalRow): Approval {
  return {
    schema_version: row.schema_version,
    approval_id: row.approval_id,
    task_id: row.task_id,
    run_id: row.run_id,
    state: row.state,
    trigger_type: row.trigger_type,
    trigger_detail: JSON.parse(row.trigger_detail) as Approval["trigger_detail"],
    action_description: row.action_description,
    requested_at: row.requested_at,
    expires_at: row.expires_at,
    ...(row.responded_at !== null ? { responded_at: row.responded_at } : {}),
    ...(row.response_note !== null ? { response_note: row.response_note } : {})
  };
}

function toRow(approval: Approval): ApprovalRow {
  return {
    approval_id: approval.approval_id,
    task_id: approval.task_id,
    run_id: approval.run_id,
    state: approval.state,
    trigger_type: approval.trigger_type,
    trigger_detail: JSON.stringify(approval.trigger_detail),
    action_description: approval.action_description,
    requested_at: approval.requested_at,
    expires_at: approval.expires_at,
    responded_at: approval.responded_at ?? null,
    response_note: approval.response_note ?? null,
    schema_version: approval.schema_version
  };
}

export class SqliteApprovalRepository implements IApprovalRepository {
  async save(approval: Approval): Promise<Approval> {
    saveStatement.run(toRow(approval));
    return Promise.resolve(approval);
  }

  async findById(id: string): Promise<Approval | null> {
    const row = findByIdStatement.get(id) as ApprovalRow | undefined;
    return Promise.resolve(row ? toApproval(row) : null);
  }

  async update(id: string, patch: Partial<Approval>): Promise<Approval> {
    const existing = await this.findById(id);
    if (!existing) {
      throw new Error(`Approval not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    saveStatement.run(toRow(updated));
    return Promise.resolve(updated);
  }

  async findPendingExpiredBefore(cutoff: string): Promise<Approval[]> {
    const rows = findPendingExpiredBeforeStatement.all(cutoff) as ApprovalRow[];
    return Promise.resolve(rows.map(toApproval));
  }
}
