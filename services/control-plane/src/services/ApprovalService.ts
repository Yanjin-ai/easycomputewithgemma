import { randomUUID } from "crypto";
import { NotFoundError, ValidationError } from "../middleware/errorHandler";
import type { IApprovalRepository } from "../repositories/IApprovalRepository";
import type { IRunRepository } from "../repositories/IRunRepository";
import type { Approval, EventInput } from "../types";
import type { EventService } from "./EventService";

type ApprovalTriggerType = Approval["trigger_type"];
type ApprovalEventService = Pick<EventService, "append" | "processStateTransition">;

const SCHEMA_VERSION = "1.0.0";
const APPROVAL_TIMEOUT_MS = 24 * 60 * 60 * 1000;
const CONTROL_PLANE_SOURCE = "control-plane";
const SYSTEM_RESPONDER_ID = "00000000-0000-4000-8000-000000000000";

const APPROVAL_TRIGGER_TYPES = new Set<ApprovalTriggerType>([
  "tool",
  "routing",
  "task_attribute",
  "user"
]);

export class ApprovalService {
  constructor(
    private readonly runRepository?: IRunRepository,
    private readonly eventService?: ApprovalEventService,
    private readonly approvalRepository?: IApprovalRepository
  ) {}

  /**
   * Returns a single Approval by ID.
   */
  async getById(approvalId: string): Promise<Approval | null> {
    const { approvalRepository } = this.getDependencies();
    return approvalRepository.findById(approvalId);
  }

  /**
   * Creates a pending Approval request and drives the associated Run/Task into paused via events.
   */
  async create(runId: string, triggerType: string, actionDescription: string): Promise<Approval> {
    const { runRepository, approvalRepository } = this.getDependencies();
    const run = await runRepository.findById(runId);
    if (!run) {
      throw new NotFoundError("Run not found");
    }

    if (!APPROVAL_TRIGGER_TYPES.has(triggerType as ApprovalTriggerType)) {
      throw new ValidationError("Invalid approval trigger type");
    }

    const requestedAt = new Date();
    const expiresAt = new Date(requestedAt.getTime() + APPROVAL_TIMEOUT_MS).toISOString();
    const approval: Approval = {
      schema_version: SCHEMA_VERSION,
      approval_id: randomUUID(),
      task_id: run.task_id,
      run_id: run.run_id,
      state: "pending",
      trigger_type: triggerType as ApprovalTriggerType,
      trigger_detail: {},
      action_description: actionDescription,
      requested_at: requestedAt.toISOString(),
      expires_at: expiresAt
    };

    await approvalRepository.save(approval);
    await this.appendApprovalEvent(approval, "approval.requested", {
      approval_id: approval.approval_id,
      trigger_type: approval.trigger_type,
      trigger_reason: approval.trigger_type,
      action_description: approval.action_description,
      expires_at: approval.expires_at
    });

    return approval;
  }

  /**
   * Records a user approval response and drives the Approval state machine.
   */
  async respond(
    approvalId: string,
    response: "approved" | "rejected",
    note?: string
  ): Promise<Approval> {
    const { approvalRepository } = this.getDependencies();
    const approval = await approvalRepository.findById(approvalId);
    if (!approval) {
      throw new NotFoundError("Approval not found");
    }

    if (approval.state !== "pending") {
      throw new ValidationError("Approval is not in pending state");
    }

    const now = new Date();
    if (now.getTime() > new Date(approval.expires_at).getTime()) {
      const expired = await approvalRepository.update(approval.approval_id, { state: "expired" });
      await this.appendExpiredEvent(expired, now.toISOString());
      throw new ValidationError("Approval has expired");
    }

    const respondedAt = now.toISOString();
    const updated = await approvalRepository.update(approval.approval_id, {
      state: response,
      responded_at: respondedAt,
      ...(note !== undefined ? { response_note: note } : {})
    });

    if (response === "approved") {
      await this.appendApprovalEvent(updated, "approval.granted", {
        approval_id: updated.approval_id,
        granted_by: SYSTEM_RESPONDER_ID,
        granted_at: respondedAt,
        ...(note !== undefined ? { note } : {})
      });
    } else {
      await this.appendApprovalEvent(updated, "approval.rejected", {
        approval_id: updated.approval_id,
        rejected_by: SYSTEM_RESPONDER_ID,
        rejection_reason: note ?? "",
        ...(note !== undefined ? { note } : {})
      });
    }

    return updated;
  }

  /**
   * Expires approvals older than the v1 24-hour timeout and emits approval.expired events.
   */
  async checkAndExpireOverdue(): Promise<void> {
    const { approvalRepository } = this.getDependencies();
    const now = new Date().toISOString();
    const expiredApprovals = await approvalRepository.findPendingExpiredBefore(now);

    for (const approval of expiredApprovals) {
      const expired = await approvalRepository.update(approval.approval_id, { state: "expired" });
      await this.appendExpiredEvent(expired, now);
    }
  }

  private async appendExpiredEvent(approval: Approval, expiredAt: string): Promise<void> {
    await this.appendApprovalEvent(approval, "approval.expired", {
      approval_id: approval.approval_id,
      expired_at: expiredAt
    });
  }

  private async appendApprovalEvent(
    approval: Approval,
    eventType: EventInput["event_type"],
    payload: Record<string, unknown>
  ): Promise<void> {
    const { eventService } = this.getDependencies();
    const event = await eventService.append({
      schema_version: SCHEMA_VERSION,
      event_type: eventType,
      task_id: approval.task_id,
      run_id: approval.run_id,
      source: CONTROL_PLANE_SOURCE,
      emitted_at: new Date().toISOString(),
      payload
    });
    await eventService.processStateTransition(event);
  }

  private getDependencies(): {
    runRepository: IRunRepository;
    eventService: ApprovalEventService;
    approvalRepository: IApprovalRepository;
  } {
    if (!this.runRepository || !this.eventService || !this.approvalRepository) {
      throw new Error(
        "ApprovalService requires IRunRepository, EventService, and IApprovalRepository dependencies"
      );
    }

    return {
      runRepository: this.runRepository,
      eventService: this.eventService,
      approvalRepository: this.approvalRepository
    };
  }
}
