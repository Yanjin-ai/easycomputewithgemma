import { Router } from "express";
import { schemaValidator } from "../middleware/schemaValidator";
import type { ApprovalService } from "../services/ApprovalService";

const approvalResponseSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    response: { type: "string", enum: ["approved", "rejected"] },
    response_note: { type: "string" }
  },
  required: ["response"]
};

export function approvalsRouter(approvalService: ApprovalService): Router {
  const router = Router();

  router.get("/:approval_id", async (req, res, next) => {
    try {
      const approval = await approvalService.getById(req.params.approval_id);
      if (!approval) {
        res.status(404).json({ error: "not_found", message: "Approval not found" });
        return;
      }
      res.json(approval);
    } catch (error) {
      next(error);
    }
  });

  router.post(
    "/:approval_id/respond",
    schemaValidator(approvalResponseSchema),
    async (req, res, next) => {
      try {
        const approval = await approvalService.respond(
          req.params.approval_id,
          req.body.response,
          req.body.response_note
        );
        res.json(approval);
      } catch (error) {
        next(error);
      }
    }
  );

  return router;
}
