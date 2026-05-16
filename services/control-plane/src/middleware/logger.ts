import { NextFunction, Request, Response } from "express";

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();
  const { method, path: reqPath, body } = req;

  res.on("finish", () => {
    const ms = Date.now() - start;
    const eventType = typeof body?.event_type === "string" ? ` [${body.event_type}]` : "";
    const taskId = typeof body?.task_id === "string" ? ` task=${body.task_id.slice(0, 8)}` : "";
    const status = res.statusCode;
    const color = status >= 500 ? "\x1b[31m" : status >= 400 ? "\x1b[33m" : "\x1b[32m";
    console.log(`${color}${method} ${reqPath}${eventType}${taskId} → ${status} (${ms}ms)\x1b[0m`);
  });

  next();
}
