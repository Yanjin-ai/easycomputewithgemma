import { Router } from "express";
import { schemaValidator } from "../middleware/schemaValidator";
import type { DeviceService } from "../services/DeviceService";

const registerDeviceSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    device_id: { $ref: "common.schema.json#/$defs/uuid" },
    device_name: { type: "string" },
    runtime_type: { type: "string", enum: ["mobile", "desktop", "cloud"] },
    permission_scope: { $ref: "common.schema.json#/$defs/permission_level" },
    rotate_api_key: { type: "boolean" }
  },
  required: ["device_name", "runtime_type", "permission_scope"]
};

export function devicesRouter(deviceService: DeviceService): Router {
  const router = Router();

  router.get("/", async (_req, res, next) => {
    try {
      const result = await deviceService.listDevices();
      res.json(result);
    } catch (error) {
      next(error);
    }
  });

  router.get("/:device_id", async (req, res, next) => {
    try {
      const device = await deviceService.getDevice(req.params.device_id);
      res.json({ device });
    } catch (error) {
      next(error);
    }
  });

  router.post("/", schemaValidator(registerDeviceSchema), async (req, res, next) => {
    try {
      const result = await deviceService.register(
        req.body.device_name,
        req.body.runtime_type,
        req.body.permission_scope,
        req.body.device_id,
        req.body.rotate_api_key
      );

      res.status(201).json({
        device: result.device,
        api_key: result.apiKey
      });
    } catch (error) {
      next(error);
    }
  });

  return router;
}
