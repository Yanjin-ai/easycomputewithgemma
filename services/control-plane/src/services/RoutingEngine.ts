import { NotImplementedError } from "../middleware/errorHandler";
import type { RoutingDecision, RuntimeHeartbeat, Task } from "../types";

export class RoutingEngine {
  /**
   * Pure routing decision function: consumes a Task and runtime heartbeat snapshot,
   * returns a deterministic routing decision, and performs no persistence or side effects.
   */
  async route(task: Task, availableRuntimes: RuntimeHeartbeat[]): Promise<RoutingDecision> {
    const policyVersion = "1.0.0";
    const heartbeatFreshnessMs = 90_000;
    const now = Date.now();

    type ConsideredRuntime = {
      runtime_id: string;
      runtime_type: RuntimeHeartbeat["runtime_type"];
      result: "selected" | "excluded";
      reason: string;
      exclusion_reason?: string;
    };

    const hasAll = (required: string[], supported: string[]): boolean => {
      const supportedSet = new Set(supported);
      return required.every((item) => supportedSet.has(item));
    };

    const isFreshHeartbeat = (runtime: RuntimeHeartbeat): boolean => {
      const heartbeatTime = Date.parse(runtime.last_heartbeat_at);
      return Number.isFinite(heartbeatTime) && now - heartbeatTime <= heartbeatFreshnessMs;
    };

    const isAllowedByPermission = (runtime: RuntimeHeartbeat): boolean => {
      if (task.permission_level === "local_only") {
        return runtime.runtime_type === "mobile" || runtime.runtime_type === "desktop";
      }

      if (task.permission_level === "private_lan") {
        return runtime.runtime_type !== "cloud";
      }

      return true;
    };

    const getExclusionReason = (runtime: RuntimeHeartbeat): string | undefined => {
      if (!runtime.is_online || !isFreshHeartbeat(runtime)) {
        return "no_runtime_online";
      }

      if (!isAllowedByPermission(runtime)) {
        return task.permission_level === "local_only"
          ? "local_only_no_runtime"
          : "permission_blocked";
      }

      if (!hasAll(task.required_tools, runtime.supported_tools)) {
        return "capability_gap";
      }

      if (!hasAll(task.required_capabilities, runtime.supported_capabilities)) {
        return "capability_gap";
      }

      if (runtime.active_run_count !== 0) {
        return "runtime_busy";
      }

      return undefined;
    };

    const evaluated = availableRuntimes.map((runtime) => ({
      runtime,
      exclusionReason: getExclusionReason(runtime)
    }));

    const candidates = evaluated
      .filter((entry) => entry.exclusionReason === undefined)
      .map((entry) => entry.runtime);

    const runtimeTypeRank = (runtime: RuntimeHeartbeat): number => {
      // Desktop is always preferred for execution (has Gemma weights).
      // Mobile is a task-submitter, not an executor; it ranks last so it
      // is only selected when no desktop/cloud runtime is available.
      // Cloud ranks second as a fallback for heavy tasks.
      if (task.complexity_hint === "heavy") {
        return runtime.runtime_type === "cloud"
          ? 0
          : runtime.runtime_type === "desktop"
            ? 1
            : 2; // mobile
      }

      // light / medium: prefer desktop, then cloud, mobile last
      return runtime.runtime_type === "desktop"
        ? 0
        : runtime.runtime_type === "cloud"
          ? 1
          : 2; // mobile
    };

    const batteryRank = (runtime: RuntimeHeartbeat): number => {
      if (runtime.battery_level === undefined) {
        return 0;
      }

      return runtime.battery_level >= 20 ? 0 : 1;
    };

    const cpuLoadRank = (runtime: RuntimeHeartbeat): number =>
      runtime.cpu_load === undefined ? Number.POSITIVE_INFINITY : runtime.cpu_load;

    const cloudFallbackRank = (runtime: RuntimeHeartbeat): number =>
      runtime.runtime_type === "cloud" ? 1 : 0;

    const runtimeIdTieBreak = (left: RuntimeHeartbeat, right: RuntimeHeartbeat): number => {
      const typeOrder = left.runtime_type.localeCompare(right.runtime_type);
      return typeOrder === 0 ? left.runtime_id.localeCompare(right.runtime_id) : typeOrder;
    };

    const sortedCandidates = [...candidates].sort((left, right) => {
      const priorityComparisons = [
        runtimeTypeRank(left) - runtimeTypeRank(right),
        batteryRank(left) - batteryRank(right),
        cpuLoadRank(left) - cpuLoadRank(right),
        cloudFallbackRank(left) - cloudFallbackRank(right),
        runtimeIdTieBreak(left, right)
      ];

      return priorityComparisons.find((comparison) => comparison !== 0) ?? 0;
    });

    const buildConsideredRuntimes = (
      selectedRuntime?: RuntimeHeartbeat
    ): ConsideredRuntime[] =>
      evaluated.map(({ runtime, exclusionReason }) => {
        if (selectedRuntime?.runtime_id === runtime.runtime_id) {
          return {
            runtime_id: runtime.runtime_id,
            runtime_type: runtime.runtime_type,
            result: "selected",
            reason: "selected by routing policy v1"
          };
        }

        const reason = exclusionReason ?? "not_highest_priority";

        return {
          runtime_id: runtime.runtime_id,
          runtime_type: runtime.runtime_type,
          result: "excluded",
          reason,
          exclusion_reason: reason
        };
      });

    if (sortedCandidates.length > 0) {
      const selected = sortedCandidates[0];

      return {
        selected: selected.runtime_id,
        target_runtime: selected.runtime_type,
        decision_reason: `${selected.runtime_type} runtime selected by routing policy v1`,
        considered_runtimes: buildConsideredRuntimes(selected),
        policy_version: policyVersion
      } as RoutingDecision;
    }

    const onlineRuntimes = evaluated.filter(
      ({ runtime }) => runtime.is_online && isFreshHeartbeat(runtime)
    );
    const permissionAllowedRuntimes = onlineRuntimes.filter(({ runtime }) =>
      isAllowedByPermission(runtime)
    );
    const capabilityMatchedRuntimes = permissionAllowedRuntimes.filter(
      ({ runtime }) =>
        hasAll(task.required_tools, runtime.supported_tools) &&
        hasAll(task.required_capabilities, runtime.supported_capabilities)
    );

    let failureReason:
      | "no_runtime_online"
      | "permission_blocked"
      | "capability_gap"
      | "local_only_no_runtime";

    if (onlineRuntimes.length === 0) {
      failureReason = "no_runtime_online";
    } else if (permissionAllowedRuntimes.length === 0) {
      failureReason =
        task.permission_level === "local_only"
          ? "local_only_no_runtime"
          : "permission_blocked";
    } else if (capabilityMatchedRuntimes.length === 0) {
      failureReason = "capability_gap";
    } else {
      failureReason = "no_runtime_online";
    }

    return {
      failure_reason: failureReason,
      decision_reason: `routing failed: ${failureReason}`,
      considered_runtimes: buildConsideredRuntimes(),
      policy_version: policyVersion
    } as unknown as RoutingDecision;
  }
}
