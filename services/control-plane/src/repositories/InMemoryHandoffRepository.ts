import type { HandoffPayload, Runtime } from "../types";
import type { IHandoffRepository } from "./IHandoffRepository";

type StoredHandoff = {
  payload: HandoffPayload;
  delivered: boolean;
};

export class InMemoryHandoffRepository implements IHandoffRepository {
  private readonly store = new Map<string, StoredHandoff>();

  async save(payload: HandoffPayload): Promise<HandoffPayload> {
    this.store.set(payload.handoff_id, { payload, delivered: false });
    return payload;
  }

  async findPendingByRuntime(targetRuntime: Runtime): Promise<HandoffPayload[]> {
    return Array.from(this.store.values())
      .filter(
        ({ payload, delivered }) =>
          payload.target_runtime === targetRuntime && !delivered
      )
      .map(({ payload }) => payload);
  }

  async markDelivered(handoffId: string): Promise<void> {
    const stored = this.store.get(handoffId);
    if (stored) {
      stored.delivered = true;
    }
  }
}
