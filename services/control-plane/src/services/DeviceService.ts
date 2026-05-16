import { randomBytes, randomUUID } from "crypto";
import { NotFoundError } from "../middleware/errorHandler";
import type { IDeviceRepository } from "../repositories/IDeviceRepository";
import type {
  Device,
  HeartbeatPayload,
  PermissionLevel,
  Runtime,
  RuntimeHeartbeat
} from "../types";

export class DeviceService {
  private readonly heartbeats = new Map<string, RuntimeHeartbeat>();

  constructor(private readonly repository: IDeviceRepository) {}

  /**
   * Registers a mobile, desktop, or cloud device, assigns a device_id, and returns its API key.
   */
  async register(
    name: string,
    runtimeType: Runtime,
    permissionScope: PermissionLevel,
    requestedDeviceId?: string,
    rotateApiKey = false
  ): Promise<{ device: Device; apiKey: string }> {
    if (requestedDeviceId) {
      const existing = await this.repository.findRegistrationById(requestedDeviceId);
      if (existing && !rotateApiKey) {
        return existing;
      }

      if (existing && rotateApiKey) {
        const apiKey = this.generateApiKey();
        const savedDevice = await this.repository.save(existing.device, apiKey);
        return { device: savedDevice, apiKey };
      }
    }

    const deviceId = requestedDeviceId ?? randomUUID();
    const now = new Date().toISOString();
    const apiKey = this.generateApiKey();

    const device: Device = {
      schema_version: "1.0.0",
      device_id: deviceId,
      account_id: deviceId,
      device_name: name,
      runtime_type: runtimeType,
      permission_scope: permissionScope,
      registered_at: now,
      last_seen_at: now,
      is_online: false,
      is_active: true
    };

    const savedDevice = await this.repository.save(device, apiKey);

    return { device: savedDevice, apiKey };
  }

  async getDevice(deviceId: string): Promise<Device> {
    const device = await this.repository.findById(deviceId);
    if (!device) {
      throw new NotFoundError(`Device not found: ${deviceId}`);
    }

    return device;
  }

  async listDevices(): Promise<{
    devices: Array<{
      device_id: string;
      device_name: string;
      runtime_type: Runtime;
      is_online: boolean;
      last_seen_at: string;
      supported_tools: string[];
      supported_capabilities: string[];
    }>;
    total: number;
  }> {
    const devices = await this.repository.findAll();

    return {
      devices: devices.map((device) => {
        const heartbeat = this.heartbeats.get(device.device_id);

        return {
          device_id: device.device_id,
          device_name: device.device_name,
          runtime_type: device.runtime_type,
          is_online: device.is_online,
          last_seen_at: device.last_seen_at,
          supported_tools: heartbeat?.supported_tools ?? [],
          supported_capabilities: heartbeat?.supported_capabilities ?? []
        };
      }),
      total: devices.length
    };
  }

  async validateApiKey(apiKey: string): Promise<Device | null> {
    return this.repository.findByApiKey(apiKey);
  }

  /**
   * Records runtime liveness and capacity data and refreshes persisted online status.
   */
  async recordHeartbeat(deviceId: string, heartbeat: HeartbeatPayload): Promise<void> {
    const device = await this.repository.findById(deviceId);
    if (!device) {
      throw new NotFoundError(`Device not found: ${deviceId}`);
    }

    const now = new Date().toISOString();
    this.heartbeats.set(deviceId, {
      ...heartbeat,
      runtime_id: deviceId,
      runtime_type: device.runtime_type,
      permission_scope: device.permission_scope,
      last_heartbeat_at: now
    });

    await this.repository.update(deviceId, { last_seen_at: now, is_online: true });
  }

  /**
   * Returns runtimes whose persisted device status is online with a heartbeat seen in the last 90 seconds.
   */
  async getOnlineRuntimes(): Promise<RuntimeHeartbeat[]> {
    const onlineDevices = await this.repository.findOnline();
    const onlineDeviceIds = new Set(onlineDevices.map((device) => device.device_id));

    return Array.from(this.heartbeats.values()).filter((heartbeat) =>
      onlineDeviceIds.has(heartbeat.runtime_id)
    );
  }

  async markStaleDevicesOffline(): Promise<number> {
    return this.repository.markStaleDevicesOffline();
  }

  private generateApiKey(): string {
    return randomBytes(32).toString("hex");
  }
}
