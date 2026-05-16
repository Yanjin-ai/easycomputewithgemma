import type { Approval } from "../types";

export interface IApprovalRepository {
  save(approval: Approval): Promise<Approval>;
  findById(id: string): Promise<Approval | null>;
  update(id: string, patch: Partial<Approval>): Promise<Approval>;
  findPendingExpiredBefore(cutoff: string): Promise<Approval[]>;
}
