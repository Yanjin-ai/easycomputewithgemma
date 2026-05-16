import type { HandoffPayload, Runtime } from "../types";

export interface IHandoffRepository {
  save(payload: HandoffPayload): Promise<HandoffPayload>;
  findPendingByRuntime(targetRuntime: Runtime): Promise<HandoffPayload[]>;
  markDelivered(handoffId: string): Promise<void>;
}
