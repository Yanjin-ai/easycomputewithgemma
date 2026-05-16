import type { EventInput, Runtime, Task } from "../types";
import type { DeviceService } from "./DeviceService";
import type { EventService } from "./EventService";
import type { HandoffService } from "./HandoffService";
import type { RoutingEngine } from "./RoutingEngine";
import type { RunService } from "./RunService";
import type { TaskService } from "./TaskService";

export class SchedulingOrchestrator {
  private readonly MAX_RETRIES = 3;
  private readonly RETRY_DELAYS_MS = [30_000, 60_000, 120_000] as const;
  private readonly TASK_TIMEOUT_MS = 10 * 60 * 1000;

  constructor(
    private readonly routingEngine: RoutingEngine,
    private readonly deviceService: DeviceService,
    private readonly runService: RunService,
    private readonly handoffService: HandoffService,
    private readonly eventService: EventService,
    private readonly taskService: TaskService
  ) {}

  async scheduleTask(task: Task): Promise<void> {
    try {
      await this.appendAndProcess({
        schema_version: "1.0.0",
        task_id: task.task_id,
        source: "control-plane",
        event_type: "route.started",
        emitted_at: new Date().toISOString(),
        payload: {
          policy_version: "1.0.0"
        }
      });

      const onlineRuntimes = await this.deviceService.getOnlineRuntimes();
      const decision = await this.routingEngine.route(task, onlineRuntimes);

      if (!decision.selected || !decision.target_runtime) {
        const failureReason = decision.failure_reason ?? "no_runtime_online";
        const routeFailedEvents = await this.eventService.queryByTaskId(task.task_id, 100);
        const retryAttempt = routeFailedEvents.filter((event) => event.event_type === "route.failed").length;

        await this.appendAndProcess({
          schema_version: "1.0.0",
          task_id: task.task_id,
          source: "control-plane",
          event_type: "route.failed",
          emitted_at: new Date().toISOString(),
          payload: {
            failure_reason: failureReason,
            decision_reason: decision.decision_reason,
            policy_version: decision.policy_version
          }
        });

        if (failureReason === "no_runtime_online" && retryAttempt < this.MAX_RETRIES) {
          await this.taskService.updateState(task.task_id, "pending");

          setTimeout(() => {
            void this.retryTask(task.task_id);
          }, this.RETRY_DELAYS_MS[retryAttempt]);
        }

        return;
      }

      const targetRuntime: Runtime = decision.target_runtime;
      await this.appendAndProcess({
        schema_version: "1.0.0",
        task_id: task.task_id,
        source: "control-plane",
        event_type: "route.decided",
        emitted_at: new Date().toISOString(),
        payload: {
          target_runtime: targetRuntime,
          selected_runtime_id: decision.selected,
          decision_reason: decision.decision_reason,
          policy_version: decision.policy_version
        }
      });

      await this.runService.create(task.task_id, targetRuntime, 1);

      const handoffPayload = await this.handoffService.create(
        task.task_id,
        targetRuntime,
        decision.decision_reason,
        "system"
      );
      await this.handoffService.dispatch(handoffPayload);
    } catch (error) {
      console.error(`Failed to schedule Task ${task.task_id}`, error);
    }
  }

  private async appendAndProcess(input: EventInput): Promise<void> {
    const event = await this.eventService.append(input);
    await this.eventService.processStateTransition(event);
  }

  async failStaleTasks(): Promise<void> {
    const runningTasks = await this.taskService.list(100, undefined, "running");
    const cutoff = new Date(Date.now() - this.TASK_TIMEOUT_MS).toISOString();

    for (const task of runningTasks) {
      if (task.last_updated_at < cutoff) {
        const runs = await this.runService.getRunsForTask(task.task_id);
        const activeRun = runs.find((run) => run.state === "running" || run.state === "handed_off");

        await this.appendAndProcess({
          schema_version: "1.0.0",
          task_id: task.task_id,
          ...(activeRun ? { run_id: activeRun.run_id } : {}),
          source: "control-plane",
          event_type: "run.failed",
          emitted_at: new Date().toISOString(),
          payload: {
            error_code: "watchdog_timeout",
            error_message: "Task exceeded maximum runtime of 10 minutes"
          }
        });
      }
    }
  }

  async recoverOrphanedRuns(): Promise<void> {
    const runningTasks = await this.taskService.list(100, undefined, "running");
    const runningCutoff = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    const handedOffCutoff = new Date(Date.now() - 5 * 60 * 1000).toISOString();

    for (const task of runningTasks) {
      const onlineRuntimes = await this.deviceService.getOnlineRuntimes();
      if (onlineRuntimes.length === 0) {
        continue;
      }

      const runs = await this.runService.getRunsForTask(task.task_id);
      const activeRun = runs.find((run) => run.state === "running");
      if (activeRun?.started_at && activeRun.started_at <= runningCutoff) {
        console.log(
          `[Recovery] Orphaned run ${activeRun.run_id} for task ${task.task_id}, re-dispatching`
        );

        const now = new Date().toISOString();
        const failEvent = await this.eventService.append({
          schema_version: "1.0.0",
          event_type: "run.failed",
          task_id: task.task_id,
          run_id: activeRun.run_id,
          source: "control-plane",
          emitted_at: now,
          payload: {
            error_code: "orphaned_run",
            error_message: "Runtime disconnected"
          }
        });
        await this.eventService.processStateTransition(failEvent);

        const retryEvent = await this.eventService.append({
          schema_version: "1.0.0",
          event_type: "task.submitted",
          task_id: task.task_id,
          source: "control-plane",
          emitted_at: now,
          payload: {
            resubmitted: true,
            reason: "orphan_recovery"
          }
        });
        await this.eventService.processStateTransition(retryEvent);

        continue;
      }

      const handedOffRun = runs.find((run) => run.state === "handed_off");
      if (!handedOffRun || handedOffRun.created_at > handedOffCutoff) {
        continue;
      }

      console.log(
        `[Recovery] Orphaned handed-off run ${handedOffRun.run_id} for task ${task.task_id}, re-dispatching`
      );

      const now = new Date().toISOString();
      const failEvent = await this.eventService.append({
        schema_version: "1.0.0",
        event_type: "run.failed",
        task_id: task.task_id,
        run_id: handedOffRun.run_id,
        source: "control-plane",
        emitted_at: now,
        payload: {
          error_code: "orphaned_run",
          error_message: "Runtime disconnected"
        }
      });
      await this.eventService.processStateTransition(failEvent);

      const retryEvent = await this.eventService.append({
        schema_version: "1.0.0",
        event_type: "task.submitted",
        task_id: task.task_id,
        source: "control-plane",
        emitted_at: now,
        payload: {
          resubmitted: true,
          reason: "orphan_recovery"
        }
      });
      await this.eventService.processStateTransition(retryEvent);
    }
  }

  private async retryTask(taskId: string): Promise<void> {
    try {
      const task = await this.taskService.getById(taskId);
      if (!task || task.current_state !== "pending") {
        return;
      }

      await this.scheduleTask(task);
    } catch (error) {
      console.error(`Failed to retry Task ${taskId}`, error);
    }
  }
}
