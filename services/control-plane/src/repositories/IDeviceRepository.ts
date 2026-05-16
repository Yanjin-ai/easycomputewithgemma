import type { Device } from "../types";

export interface DeviceRegistration {
  device: Device;
  apiKey: string;
}

export interface IDeviceRepository {
  findById(id: string): Promise<Device | null>;
  findRegistrationById(id: string): Promise<DeviceRegistration | null>;
  findByApiKey(apiKey: string): Promise<Device | null>;
  findAll(): Promise<Device[]>;
  findOnline(): Promise<Device[]>;
  save(device: Device, apiKey: string): Promise<Device>;
  update(id: string, patch: Partial<Device>): Promise<Device>;
  markStaleDevicesOffline(): Promise<number>;
}
