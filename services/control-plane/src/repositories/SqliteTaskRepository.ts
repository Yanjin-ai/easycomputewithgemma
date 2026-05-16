import type { Task } from "../types";
import type { ITaskRepository, TaskCounts } from "./ITaskRepository";
import { db } from "./db";

type TaskRow = {
  task_id: string;
  task_title: string;
  current_state: Task["current_state"];
  schema_version: string;
  intent: string;
  goal_description: string;
  required_tools: string;
  required_capabilities: string;
  complexity_hint: Task["complexity_hint"];
  permission_level: Task["permission_level"];
  raw_input: string;
  current_runtime: Task["current_runtime"] | null;
  pending_approval: 0 | 1;
  created_at: string;
  updated_at: string;
  account_id: string | null;
  intent_summary: string | null;
  submitted_by: string | null;
  last_updated_at: string | null;
  total_run_count: number;
};

type TaskCountRow = {
  current_state: string;
  count: number;
};

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

const selectColumns = `
  task_id,
  task_title,
  current_state,
  schema_version,
  intent,
  goal_description,
  required_tools,
  required_capabilities,
  complexity_hint,
  permission_level,
  raw_input,
  current_runtime,
  pending_approval,
  created_at,
  updated_at,
  account_id,
  intent_summary,
  submitted_by,
  last_updated_at,
  total_run_count
`;

const findByIdStatement = db.prepare(`SELECT ${selectColumns} FROM tasks WHERE task_id = ?`);
const countByStateStatement = db.prepare(
  "SELECT current_state, COUNT(*) AS count FROM tasks GROUP BY current_state"
);
const saveStatement = db.prepare(`
  INSERT OR REPLACE INTO tasks (
    task_id,
    task_title,
    current_state,
    schema_version,
    intent,
    goal_description,
    required_tools,
    required_capabilities,
    complexity_hint,
    permission_level,
    raw_input,
    current_runtime,
    current_run_id,
    pending_approval,
    created_at,
    updated_at,
    account_id,
    intent_summary,
    submitted_by,
    last_updated_at,
    total_run_count
  ) VALUES (
    @task_id,
    @task_title,
    @current_state,
    @schema_version,
    @intent,
    @goal_description,
    @required_tools,
    @required_capabilities,
    @complexity_hint,
    @permission_level,
    @raw_input,
    @current_runtime,
    @current_run_id,
    @pending_approval,
    @created_at,
    @updated_at,
    @account_id,
    @intent_summary,
    @submitted_by,
    @last_updated_at,
    @total_run_count
  )
`);

function toTask(row: TaskRow): Task {
  const raw = JSON.parse(row.raw_input) as Partial<Task>;
  return {
    ...raw,
    schema_version: row.schema_version,
    task_id: row.task_id,
    account_id: row.account_id ?? raw.account_id ?? "",
    task_title: row.task_title,
    intent_summary: row.intent_summary ?? row.intent,
    permission_level: row.permission_level,
    current_state: row.current_state,
    ...(row.current_runtime ? { current_runtime: row.current_runtime } : {}),
    required_tools: JSON.parse(row.required_tools) as string[],
    required_capabilities: JSON.parse(row.required_capabilities) as string[],
    complexity_hint: row.complexity_hint,
    submitted_by: row.submitted_by ?? raw.submitted_by ?? "",
    created_at: row.created_at,
    last_updated_at: row.last_updated_at ?? row.updated_at,
    pending_approval: row.pending_approval === 1,
    total_run_count: row.total_run_count
  };
}

function toRow(task: Task) {
  return {
    task_id: task.task_id,
    task_title: task.task_title,
    current_state: task.current_state,
    schema_version: task.schema_version,
    intent: task.intent_summary,
    goal_description: task.intent_summary,
    required_tools: JSON.stringify(task.required_tools),
    required_capabilities: JSON.stringify(task.required_capabilities),
    complexity_hint: task.complexity_hint,
    permission_level: task.permission_level,
    raw_input: JSON.stringify(task),
    current_runtime: task.current_runtime ?? null,
    current_run_id: null,
    pending_approval: task.pending_approval ? 1 : 0,
    created_at: task.created_at,
    updated_at: task.last_updated_at,
    account_id: task.account_id,
    intent_summary: task.intent_summary,
    submitted_by: task.submitted_by,
    last_updated_at: task.last_updated_at,
    total_run_count: task.total_run_count
  };
}

export class SqliteTaskRepository implements ITaskRepository {
  async findById(id: string): Promise<Task | null> {
    const row = findByIdStatement.get(id) as TaskRow | undefined;
    return Promise.resolve(row ? toTask(row) : null);
  }

  async findAll(limit: number, before?: string, state?: string): Promise<Task[]> {
    const whereClauses: string[] = [];
    const params: (number | string)[] = [];

    if (state) {
      whereClauses.push("current_state = ?");
      params.push(state);
    }

    if (before) {
      whereClauses.push(`(
        created_at < (SELECT created_at FROM tasks WHERE task_id = ?)
        OR (
          created_at = (SELECT created_at FROM tasks WHERE task_id = ?)
          AND task_id < ?
        )
      )`);
      params.push(before, before, before);
    }

    const where = whereClauses.length > 0 ? `WHERE ${whereClauses.join(" AND ")}` : "";
    const statement = db.prepare(
      `SELECT ${selectColumns} FROM tasks ${where} ORDER BY created_at DESC, task_id DESC LIMIT ?`
    );
    const rows = statement.all(...params, limit) as TaskRow[];
    return Promise.resolve(rows.map(toTask));
  }

  async countByState(): Promise<TaskCounts> {
    const counts = Object.fromEntries(COUNTED_TASK_STATES.map((state) => [state, 0])) as Omit<
      TaskCounts,
      "total"
    >;
    let total = 0;

    for (const row of countByStateStatement.all() as TaskCountRow[]) {
      total += row.count;
      if (row.current_state in counts) {
        counts[row.current_state as keyof typeof counts] = row.count;
      }
    }

    return Promise.resolve({
      ...counts,
      total
    });
  }

  async save(task: Task): Promise<Task> {
    saveStatement.run(toRow(task));
    return Promise.resolve(task);
  }

  async update(id: string, patch: Partial<Task>): Promise<Task> {
    const existing = await this.findById(id);
    if (!existing) {
      throw new Error(`Task not found: ${id}`);
    }

    const updated = { ...existing, ...patch };
    saveStatement.run(toRow(updated));
    return Promise.resolve(updated);
  }
}
