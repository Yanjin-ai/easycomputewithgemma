import { Router } from "express";
import { ValidationError } from "../middleware/errorHandler";
import { schemaValidator } from "../middleware/schemaValidator";
import type { HandoffService } from "../services/HandoffService";
import type { Runtime } from "../types";

const RUNTIMES: ReadonlySet<string> = new Set(["mobile", "desktop", "cloud"]);

const initiateHandoffSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    task_id: { $ref: "common.schema.json#/$defs/uuid" },
    target_runtime: { $ref: "common.schema.json#/$defs/runtime" },
    reason: { type: "string" },
    initiated_by: { type: "string", enum: ["system", "user"] }
  },
  required: ["task_id", "target_runtime", "reason", "initiated_by"]
};

export function handoffsRouter(handoffService: HandoffService): Router {
  const router = Router();

  router.get("/pending", async (req, res, next) => {
    try {
      const runtimeType = req.query.runtime_type;
      if (typeof runtimeType !== "string") {
        throw new ValidationError("runtime_type query parameter is required");
      }
      if (!RUNTIMES.has(runtimeType)) {
        throw new ValidationError("runtime_type must be one of mobile, desktop, cloud");
      }

      const handoffs = await handoffService.getPending(runtimeType as Runtime);
      res.json({ handoffs });
    } catch (error) {
      next(error);
    }
  });

  router.post("/", schemaValidator(initiateHandoffSchema), async (req, res, next) => {
    try {
      const payload = await handoffService.create(
        req.body.task_id,
        req.body.target_runtime,
        req.body.reason,
        req.body.initiated_by
      );
      await handoffService.dispatch(payload);
      res.status(201).json(payload);
    } catch (error) {
      next(error);
    }
  });

  return router;
}
