import type { ErrorRequestHandler } from "express";

export class NotFoundError extends Error {
  constructor(message = "Resource not found", public readonly details?: unknown) {
    super(message);
    this.name = "NotFoundError";
  }
}

export class ValidationError extends Error {
  constructor(message = "Validation failed", public readonly details?: unknown) {
    super(message);
    this.name = "ValidationError";
  }
}

export class NotImplementedError extends Error {
  constructor(message = "Not implemented", public readonly details?: unknown) {
    super(message);
    this.name = "NotImplementedError";
  }
}

export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof NotFoundError) {
    res.status(404).json({ error: "not_found", message: err.message, details: err.details });
    return;
  }

  if (err instanceof ValidationError) {
    res.status(400).json({ error: "validation_failed", message: err.message, details: err.details });
    return;
  }

  if (err instanceof NotImplementedError) {
    res.status(501).json({ error: "not_implemented", message: err.message, details: err.details });
    return;
  }

  res.status(500).json({
    error: "internal_server_error",
    message: err instanceof Error ? err.message : "Unexpected error",
    details: err instanceof Error ? undefined : err
  });
};
