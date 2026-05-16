import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";

export const dbPath = process.env.DB_PATH ?? "./data/gemma4all.db";
const dbDirectory = path.dirname(dbPath);

fs.mkdirSync(dbDirectory, { recursive: true });

export const db = new Database(dbPath);

db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS tasks (
    task_id TEXT PRIMARY KEY,
    task_title TEXT NOT NULL,
    current_state TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    intent TEXT NOT NULL,
    goal_description TEXT NOT NULL,
    required_tools TEXT NOT NULL,
    required_capabilities TEXT NOT NULL,
    complexity_hint TEXT NOT NULL,
    permission_level TEXT NOT NULL,
    raw_input TEXT NOT NULL,
    current_runtime TEXT,
    current_run_id TEXT,
    pending_approval INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    account_id TEXT,
    intent_summary TEXT,
    submitted_by TEXT,
    last_updated_at TEXT,
    total_run_count INTEGER NOT NULL DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS runs (
    run_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    state TEXT NOT NULL,
    runtime TEXT NOT NULL,
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL,
    schema_version TEXT NOT NULL DEFAULT '1.0.0',
    attempt_index INTEGER NOT NULL DEFAULT 0,
    model_id TEXT,
    ended_at TEXT,
    checkpoint_count INTEGER NOT NULL DEFAULT 0,
    handoff_payload_id TEXT,
    error_detail TEXT,
    output_summary TEXT
  );

  CREATE TABLE IF NOT EXISTS events (
    event_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    run_id TEXT,
    event_type TEXT NOT NULL,
    source TEXT NOT NULL,
    emitted_at TEXT NOT NULL,
    recorded_at TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    payload TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS handoffs (
    handoff_id TEXT PRIMARY KEY,
    source_run_id TEXT NOT NULL,
    target_runtime TEXT NOT NULL,
    task_context TEXT NOT NULL,
    delivered INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    raw_payload TEXT NOT NULL
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS approvals (
    approval_id   TEXT PRIMARY KEY,
    task_id       TEXT NOT NULL,
    run_id        TEXT NOT NULL,
    state         TEXT NOT NULL,
    trigger_type  TEXT NOT NULL,
    trigger_detail TEXT NOT NULL DEFAULT '{}',
    action_description TEXT NOT NULL,
    requested_at  TEXT NOT NULL,
    expires_at    TEXT NOT NULL,
    responded_at  TEXT,
    response_note TEXT,
    schema_version TEXT NOT NULL DEFAULT '1.0.0'
  );
`);

// v1 stores api_key in plaintext; production should store a bcrypt hash instead.
db.exec(`
  CREATE TABLE IF NOT EXISTS devices (
    device_id       TEXT PRIMARY KEY,
    account_id      TEXT NOT NULL,
    device_name     TEXT NOT NULL,
    runtime_type    TEXT NOT NULL,
    permission_scope TEXT NOT NULL,
    registered_at   TEXT NOT NULL,
    last_seen_at    TEXT NOT NULL,
    is_online       INTEGER NOT NULL DEFAULT 0,
    is_active       INTEGER NOT NULL DEFAULT 1,
    schema_version  TEXT NOT NULL DEFAULT '1.0.0',
    api_key         TEXT NOT NULL
  );
`);

const deviceColumns = db.prepare("PRAGMA table_info(devices)").all() as Array<{ name: string }>;
const deviceColumnNames = new Set(deviceColumns.map((column) => column.name));

if (!deviceColumnNames.has("last_seen_at")) {
  db.exec("ALTER TABLE devices ADD COLUMN last_seen_at TEXT NOT NULL DEFAULT '';");
}

if (!deviceColumnNames.has("is_online")) {
  db.exec("ALTER TABLE devices ADD COLUMN is_online INTEGER NOT NULL DEFAULT 0;");
}

try {
  db.exec("ALTER TABLE runs ADD COLUMN output_summary TEXT");
} catch {
  // Existing databases may already have this migration applied.
}
