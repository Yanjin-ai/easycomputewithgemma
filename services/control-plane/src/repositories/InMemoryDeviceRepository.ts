import type { Device } from "../types";
import type { DeviceRegistration, IDeviceRepository } from "./IDeviceRepository";

export class InMemoryDeviceRepository implements IDeviceRepository {
  private readonly devices = new Map<string, { device: Device; apiKey: string }>();

  async findById(id: string): Promise<Device | null> {
    return this.devices.get(id)?.device ?? null;
  }

  async findRegistrationById(id: string): Promise<DeviceRegistration | null> {
    return this.devices.get(id) ?? null;
  }

  async findByApiKey(apiKey: string): Promise<Device | null> {
    for (const entry of this.devices.values()) {
      if (entry.apiKey === apiKey) {
        return entry.device;
      }
    }

    return null;
  }

  async findAll(): Promise<Device[]> {
    return Array.from(this.devices.values()).map((entry) => entry.device);
  }

  async findOnline(): Promise<Device[]> {
    const staleBefore = Date.now() - 90_000;

    return Array.from(this.devices.values())
      .map((entry) => entry.device)
      .filter((device) => device.is_online && Date.parse(device.last_seen_at) >= staleBefore);
  }

  async save(device: Device, apiKey: string): Promise<Device> {
    this.devices.set(device.device_id, { device, apiKey });
    return device;
  }

  async update(id: string, patch: Partial<Device>): Promise<Device> {
    const existing = this.devices.get(id);
    if (!existing) {
      throw new Error(`Device not found: ${id}`);
    }

    const updated = { ...existing.device, ...patch };
    this.devices.set(id, { ...existing, device: updated });
    return updated;
  }

  async markStaleDevicesOffline(): Promise<number> {
    const staleBefore = Date.now() - 90_000;
    let updatedCount = 0;

    for (const [id, entry] of this.devices) {
      if (entry.device.is_online && Date.parse(entry.device.last_seen_at) < staleBefore) {
        this.devices.set(id, {
          ...entry,
          device: {
            ...entry.device,
            is_online: false
          }
        });
        updatedCount += 1;
      }
    }

    return updatedCount;
  }
}
