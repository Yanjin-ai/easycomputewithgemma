import type { NextFunction, Request, RequestHandler, Response } from "express";
import type { DeviceService } from "../services/DeviceService";

type AuthedRequest = Request & { deviceId: string };

export function createAuthMiddleware(deviceService: DeviceService): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    if (process.env.DEV_BYPASS_AUTH === "true") {
      next();
      return;
    }

    const authorization = req.header("authorization");

    if (!authorization?.startsWith("ApiKey ")) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    const apiKey = authorization.slice("ApiKey ".length);
    const device = await deviceService.validateApiKey(apiKey);

    if (!device) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    (req as AuthedRequest).deviceId = device.device_id;
    next();
  };
}
