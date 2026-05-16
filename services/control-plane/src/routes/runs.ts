import { type NextFunction, type Request, type Response, Router } from "express";
import { ValidationError } from "../middleware/errorHandler";
import { schemaValidator } from "../middleware/schemaValidator";
import type { EventService } from "../services/EventService";
import type { RunService } from "../services/RunService";
import type { EventInput, Runtime } from "../types";

const RUNTIMES: ReadonlySet<string> = new Set(["mobile", "desktop", "cloud"]);
const EVENT_SOURCES: ReadonlySet<string> = new Set(["control-plane", "mobile", "desktop", "cloud"]);

export function runsRouter(runService: RunService, eventService: EventService): Router {
  const router = Router();

  router.post("/", async (req, res, next) => {
    try {
      const taskId = typeof req.body.task_id === "string" ? req.body.task_id : undefined;
      const runtimeInput = typeof req.body.runtime === "string" ? req.body.runtime : req.body.device_id;
      const runtime = typeof runtimeInput === "string" && RUNTIMES.has(runtimeInput) ? runtimeInput : undefined;
      const attemptIndex =
        typeof req.body.attempt_index === "number" && Number.isInteger(req.body.attempt_index)
          ? req.body.attempt_index
          : 1;

      if (!taskId || !runtime) {
        throw new ValidationError("task_id and runtime are required");
      }

      const run = await runService.create(taskId, runtime as Runtime, attemptIndex);
      res.status(201).json(run);
    } catch (error) {
      next(error);
    }
  });

  router.get("/:run_id", async (req, res, next) => {
    try {
      const run = await runService.getById(req.params.run_id);
      if (!run) {
        res.status(404).json({ error: "not_found", message: "Run not found" });
        return;
      }

      res.json(run);
    } catch (error) {
      next(error);
    }
  });

  router.post(
    "/:run_id/events",
    normalizeRuntimeEventSource,
    schemaValidator("event-input.schema.json"),
    async (req, res, next) => {
      try {
        if (req.body.run_id && req.body.run_id !== req.params.run_id) {
          throw new ValidationError("Body run_id must match route run_id");
        }

        const input: EventInput = {
          ...req.body,
          run_id: req.params.run_id
        };
        const event = await eventService.append(input);
        await eventService.processStateTransition(event);

        res.status(201).json({
          event_id: event.event_id,
          recorded_at: event.recorded_at
        });
      } catch (error) {
        next(error);
      }
    }
  );

  return router;
}

function normalizeRuntimeEventSource(req: Request, _res: Response, next: NextFunction): void {
  if (typeof req.body.source === "string" && !EVENT_SOURCES.has(req.body.source)) {
    req.body.source = "desktop";
  }
  next();
}
