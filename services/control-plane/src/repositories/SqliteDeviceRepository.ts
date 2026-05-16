import { NotFoundError } from "../middleware/errorHandler";
import type { Device } from "../types";
import type { DeviceRegistration, IDeviceRepository } from "./IDeviceRepository";
import { db } from "./db";

type DeviceRow = {
  device_id: string;
  account_id: string;
  device_name: string;
  runtime_type: Device["runtime_type"];
  permission_scope: Device["permission_scope"];
  registered_at: string;
  last_seen_at: string;
  is_online: 0 | 1;
  is_active: 0 | 1;
  schema_version: string;
  api_key: string;
};

const selectColumns = `
  device_id,
  account_id,
  device_name,
  runtime_type,
  permission_scope,
  registered_at,
  last_seen_at,
  is_online,
  is_active,
  schema_version,
  api_key
`;

const findByIdStatement = db.prepare(`SELECT ${selectColumns} FROM devices WHERE device_id = ?`);
const findByApiKeyStatement = db.prepare(`SELECT ${selectColumns} FROM devices WHERE api_key = ?`);
const findAllStatement = db.prepare(`
  SELECT ${selectColumns}
  FROM devices
  ORDER BY datetime(registered_at) DESC
`);
const findOnlineStatement = db.prepare(`
  SELECT ${selectColumns}
  FROM devices
  WHERE is_online = 1
    AND datetime(last_seen_at) >= datetime('now', '-90 seconds')
`);
const saveStatement = db.prepare(`
  INSERT OR REPLACE INTO devices (
    device_id,
    account_id,
    device_name,
    runtime_type,
    permission_scope,
    registered_at,
    last_seen_at,
    is_online,
    is_active,
    schema_version,
    api_key
  ) VALUES (
    @device_id,
    @account_id,
    @device_name,
    @runtime_type,
    @permission_scope,
    @registered_at,
    @last_seen_at,
    @is_online,
    @is_active,
    @schema_version,
    @api_key
  )
`);
const markStaleDevicesOfflineStatement = db.prepare(`
  UPDATE devices
  SET is_online = 0
  WHERE is_online = 1
    AND datetime(last_seen_at) < datetime('now', '-90 seconds')
`);

function toDevice(row: DeviceRow): Device {
  return {
    device_id: row.device_id,
    account_id: row.account_id,
    device_name: row.device_name,
    runtime_type: row.runtime_type,
    permission_scope: row.permission_scope,
    registered_at: row.registered_at,
    last_seen_at: row.last_seen_at,
    is_online: row.is_online === 1,
    is_active: row.is_active === 1,
    schema_version: row.schema_version
  };
}

function toRow(device: Device, apiKey: string): DeviceRow {
  return {
    device_id: device.device_id,
    account_id: device.account_id,
    device_name: device.device_name,
    runtime_type: device.runtime_type,
    permission_scope: device.permission_scope,
    registered_at: device.registered_at,
    last_seen_at: device.last_seen_at,
    is_online: device.is_online ? 1 : 0,
    is_active: device.is_active ? 1 : 0,
    schema_version: device.schema_version,
    // v1 stores api_key in plaintext; production should store a bcrypt hash instead.
    api_key: apiKey
  };
}

export class SqliteDeviceRepository implements IDeviceRepository {
  async findById(id: string): Promise<Device | null> {
    const row = findByIdStatement.get(id) as DeviceRow | undefined;
    return Promise.resolve(row ? toDevice(row) : null);
  }

  async findRegistrationById(id: string): Promise<DeviceRegistration | null> {
    const row = findByIdStatement.get(id) as DeviceRow | undefined;
    return Promise.resolve(row ? { device: toDevice(row), apiKey: row.api_key } : null);
  }

  async findByApiKey(apiKey: string): Promise<Device | null> {
    const row = findByApiKeyStatement.get(apiKey) as DeviceRow | undefined;
    return Promise.resolve(row ? toDevice(row) : null);
  }

  async findAll(): Promise<Device[]> {
    const rows = findAllStatement.all() as DeviceRow[];
    return Promise.resolve(rows.map(toDevice));
  }

  async findOnline(): Promise<Device[]> {
    const rows = findOnlineStatement.all() as DeviceRow[];
    return Promise.resolve(rows.map(toDevice));
  }

  async save(device: Device, apiKey: string): Promise<Device> {
    saveStatement.run(toRow(device, apiKey));
    return Promise.resolve(device);
  }

  async update(id: string, patch: Partial<Device>): Promise<Device> {
    const existing = await this.findById(id);
    if (!existing) {
      throw new NotFoundError(`Device not found: ${id}`);
    }

    const existingRow = findByIdStatement.get(id) as DeviceRow;
    const updated = { ...existing, ...patch };
    saveStatement.run(toRow(updated, existingRow.api_key));
    return Promise.resolve(updated);
  }

  async markStaleDevicesOffline(): Promise<number> {
    const result = markStaleDevicesOfflineStatement.run();
    return Promise.resolve(result.changes);
  }
}
