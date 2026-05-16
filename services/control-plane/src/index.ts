import express from "express";
import fs from "fs";
import path from "path";
import { WebSocketServer } from "ws";
import { approvalsRouter } from "./routes/approvals";
import { devicesRouter } from "./routes/devices";
import { eventsRouter } from "./routes/events";
import { handoffsRouter } from "./routes/handoffs";
import { heartbeatRouter } from "./routes/heartbeat";
import { runsRouter } from "./routes/runs";
import { tasksRouter } from "./routes/tasks";
import { createAuthMiddleware } from "./middleware/auth";
import { errorHandler } from "./middleware/errorHandler";
import { requestLogger } from "./middleware/logger";
import { SqliteApprovalRepository } from "./repositories/SqliteApprovalRepository";
import { dbPath } from "./repositories/db";
import { SqliteDeviceRepository } from "./repositories/SqliteDeviceRepository";
import { SqliteEventRepository } from "./repositories/SqliteEventRepository";
import { SqliteHandoffRepository } from "./repositories/SqliteHandoffRepository";
import { SqliteRunRepository } from "./repositories/SqliteRunRepository";
import { SqliteTaskRepository } from "./repositories/SqliteTaskRepository";
import { ApprovalService } from "./services/ApprovalService";
import { DeviceService } from "./services/DeviceService";
import { EventService } from "./services/EventService";
import { HandoffService } from "./services/HandoffService";
import { RoutingEngine } from "./services/RoutingEngine";
import { RunService } from "./services/RunService";
import { SchedulingOrchestrator } from "./services/SchedulingOrchestrator";
import { SseBroadcaster } from "./services/SseBroadcaster";
import { TaskService } from "./services/TaskService";

const app = express();

const taskRepo = new SqliteTaskRepository();
const runRepo = new SqliteRunRepository();
const eventRepo = new SqliteEventRepository();
const deviceRepo = new SqliteDeviceRepository();
const handoffRepo = new SqliteHandoffRepository();
const approvalRepo = new SqliteApprovalRepository();

const routingEngine = new RoutingEngine();
const sseBroadcaster = new SseBroadcaster();
const eventService = new EventService(eventRepo, undefined, undefined, sseBroadcaster);
const taskService = new TaskService(taskRepo, routingEngine, eventService);
const runService = new RunService(runRepo, eventService);
eventService.setTaskAndRunServices(taskService, runService);
const handoffService = new HandoffService(taskRepo, runRepo, eventService, handoffRepo);
const approvalService = new ApprovalService(runRepo, eventService, approvalRepo);
const deviceService = new DeviceService(deviceRepo);
const schedulingOrchestrator = new SchedulingOrchestrator(
  routingEngine,
  deviceService,
  runService,
  handoffService,
  eventService,
  taskService
);
eventService.setSchedulingOrchestrator(schedulingOrchestrator);

app.use(express.json());
app.use(requestLogger);

app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.use("/v1/devices", devicesRouter(deviceService));
app.use(createAuthMiddleware(deviceService));
app.use("/v1/tasks", tasksRouter(taskService, runService, eventService, schedulingOrchestrator, sseBroadcaster));
app.use("/v1/runs", runsRouter(runService, eventService));
app.use("/v1/events", eventsRouter(eventService));
app.use("/v1/handoffs", handoffsRouter(handoffService));
app.use("/v1/approvals", approvalsRouter(approvalService));
app.use("/v1/heartbeat", heartbeatRouter(deviceService));

setInterval(() => {
  void approvalService.checkAndExpireOverdue();
}, 60_000);

setInterval(() => {
  void deviceService.markStaleDevicesOffline();
}, 60_000);

setInterval(() => {
  void schedulingOrchestrator.failStaleTasks();
}, 120_000);

setInterval(() => {
  void schedulingOrchestrator.recoverOrphanedRuns();
}, 30_000);

app.use(errorHandler);

const port = Number.parseInt(process.env.PORT ?? "3000", 10);
const desktopApiKeyPath = path.resolve(__dirname, "../../desktop-runtime/.desktop_api_key");

function readDesktopApiKey(): string | null {
  const candidatePaths = [
    process.env.API_KEY_PATH,
    path.resolve(process.cwd(), ".desktop_api_key"),
    desktopApiKeyPath
  ].filter((candidate): candidate is string => Boolean(candidate));

  for (const candidatePath of candidatePaths) {
    if (fs.existsSync(candidatePath)) {
      const apiKey = fs.readFileSync(candidatePath, "utf8").trim();
      if (apiKey) {
        return apiKey;
      }
    }
  }

  return null;
}

const server = app.listen(port, "0.0.0.0", () => {
  const curlApiKey = readDesktopApiKey() ?? "YOUR_API_KEY";

  console.log("━━ Gemma4all Control Plane ━━━━━━━━━━━━━━");
  console.log(`   Port:     ${port}`);
  console.log(`   DB:       ${dbPath}`);
  if (process.env.DEV_BYPASS_AUTH === "true") {
    console.log("   ⚠️  Auth: BYPASSED (DEV_BYPASS_AUTH=true)");
  }
  console.log(`   Started:  ${new Date().toISOString()}`);
  console.log("");
  console.log("   Test curl:");
  console.log(`   curl -H "Authorization: ApiKey ${curlApiKey}" http://localhost:${port}/v1/tasks`);
  console.log("");
  console.log("   To test with curl: DEV_BYPASS_AUTH=true npm start");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
});

const wss = new WebSocketServer({ server });
wss.on("connection", (ws, req) => {
  const match = req.url?.match(/\/v1\/tasks\/([^/]+)\/ws/);
  if (!match) {
    ws.close(4000, "invalid path");
    return;
  }

  const taskId = match[1];
  sseBroadcaster.subscribeWs(taskId, ws);
  ws.on("close", () => {
    sseBroadcaster.unsubscribeWs(taskId, ws);
  });
});
