import { Router } from "express";
import { schemaValidator } from "../middleware/schemaValidator";
import type { EventService } from "../services/EventService";

export function eventsRouter(eventService: EventService): Router {
  const router = Router();

  router.post("/", schemaValidator("event-input.schema.json"), async (req, res, next) => {
    try {
      const event = await eventService.append(req.body);
      await eventService.processStateTransition(event);

      res.status(201).json({
        event_id: event.event_id,
        recorded_at: event.recorded_at
      });
    } catch (error) {
      next(error);
    }
  });

  return router;
}
