import { Router } from "express";
import { schemaValidator } from "../middleware/schemaValidator";
import type { DeviceService } from "../services/DeviceService";

const heartbeatSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    device_id: { $ref: "common.schema.json#/$defs/uuid" },
    is_online: { type: "boolean" },
    battery_level: { type: "integer", minimum: 0, maximum: 100 },
    network_type: { type: "string", enum: ["wifi", "cellular", "offline"] },
    cpu_load: { type: "number", minimum: 0 },
    available_memory_mb: { type: "integer", minimum: 0 },
    active_run_count: { type: "integer", minimum: 0 },
    supported_tools: { type: "array", items: { type: "string" } },
    supported_capabilities: { type: "array", items: { type: "string" } }
  },
  required: [
    "device_id",
    "is_online",
    "network_type",
    "active_run_count",
    "supported_tools",
    "supported_capabilities"
  ]
};

export function heartbeatRouter(deviceService: DeviceService): Router {
  const router = Router();

  router.post("/", schemaValidator(heartbeatSchema), async (req, res, next) => {
    try {
      await deviceService.recordHeartbeat(req.body.device_id, req.body);
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  return router;
}
