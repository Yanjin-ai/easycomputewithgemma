import { Router } from "express";
import { ValidationError } from "../middleware/errorHandler";
import { schemaValidator } from "../middleware/schemaValidator";
import type { EventService } from "../services/EventService";
import type { RunService } from "../services/RunService";
import type { SchedulingOrchestrator } from "../services/SchedulingOrchestrator";
import type { SseBroadcaster } from "../services/SseBroadcaster";
import type { TaskService } from "../services/TaskService";
import type { EventInput, Task, TaskState } from "../types";

const TERMINAL_TASK_STATES: ReadonlySet<TaskState> = new Set(["completed", "failed", "cancelled"]);

export function tasksRouter(
  taskService: TaskService,
  runService: RunService,
  eventService: EventService,
  schedulingOrchestrator: SchedulingOrchestrator,
  broadcaster: SseBroadcaster
): Router {
  const router = Router();

  async function attachOutputSummary(task: Task): Promise<Task & { output_summary?: string }> {
    const runs = await runService.getRunsForTask(task.task_id);
    const completedRun = runs.find((run) => run.state === "completed" && run.output_summary);
    return completedRun?.output_summary
      ? { ...task, output_summary: completedRun.output_summary }
      : task;
  }

  async function computeQueuePosition(task: Task): Promise<number | null> {
    if (task.current_state !== "pending") return null;
    const queuedTasks = await taskService.list(500, undefined, "pending");
    // list() returns DESC; sort ASC so earliest created_at = position 1
    const sorted = queuedTasks
      .slice()
      .sort((a, b) => a.created_at.localeCompare(b.created_at));
    const index = sorted.findIndex((t) => t.task_id === task.task_id);
    return index === -1 ? null : index + 1;
  }

  router.post("/", schemaValidator("task-draft.schema.json"), async (req, res, next) => {
    try {
      const submittedBy =
        (req as typeof req & { deviceId?: string }).deviceId ??
        req.header("x-device-id") ??
        "unknown";
      const task = await taskService.createFromDraft(req.body, submittedBy);
      void schedulingOrchestrator;
      res.status(201).json(task);
    } catch (error) {
      next(error);
    }
  });

  router.get("/", async (req, res, next) => {
    try {
      const limit = Number.parseInt(String(req.query.limit ?? "50"), 10);
      const before = req.query.before ? String(req.query.before) : undefined;
      let state: string | undefined;

      if (req.query.state !== undefined) {
        const trimmedState = typeof req.query.state === "string" ? req.query.state.trim() : "";
        if (!trimmedState) {
          throw new ValidationError("state must be a non-empty string");
        }
        state = trimmedState;
      }

      const tasks = await Promise.all(
        (await taskService.list(limit, before, state)).map((task) => attachOutputSummary(task))
      );

      res.json({
        tasks,
        next_cursor: tasks.length === limit ? tasks.at(-1)?.task_id ?? null : null
      });
    } catch (error) {
      next(error);
    }
  });

  router.get("/counts", async (_req, res, next) => {
    try {
      res.json(await taskService.countByState());
    } catch (error) {
      next(error);
    }
  });

  router.get("/:task_id", async (req, res, next) => {
    try {
      const task = await taskService.getById(req.params.task_id);
      if (!task) {
        res.status(404).json({ error: "not_found", message: "Task not found" });
        return;
      }
      const [enriched, queuePosition] = await Promise.all([
        attachOutputSummary(task),
        computeQueuePosition(task),
      ]);
      res.json({ ...enriched, queue_position: queuePosition });
    } catch (error) {
      next(error);
    }
  });

  router.get("/:task_id/stream", async (req, res, next) => {
    try {
      const task = await taskService.getById(req.params.task_id);
      if (!task) {
        res.status(404).json({ error: "not_found", message: "Task not found" });
        return;
      }

      if (TERMINAL_TASK_STATES.has(task.current_state)) {
        res.setHeader("Content-Type", "text/event-stream");
        res.setHeader("Cache-Control", "no-cache");
        res.setHeader("Connection", "keep-alive");
        res.write(`data: ${JSON.stringify(task)}\n\n`);
        res.end();
        return;
      }

      broadcaster.subscribe(task.task_id, res);
    } catch (error) {
      next(error);
    }
  });

  router.get("/:task_id/events", async (req, res, next) => {
    try {
      const limit = Number.parseInt(String(req.query.limit ?? "50"), 10);
      const before = req.query.before ? String(req.query.before) : undefined;
      const events = await eventService.queryByTaskId(req.params.task_id, limit, before);

      res.json({
        events,
        next_cursor: events.length === limit ? events.at(-1)?.event_id ?? null : null
      });
    } catch (error) {
      next(error);
    }
  });

  router.post(
    "/:task_id/events",
    schemaValidator("event-input.schema.json"),
    async (req, res, next) => {
      try {
        const input: EventInput = {
          ...req.body,
          task_id: req.params.task_id
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
