import http from "node:http";
import https from "node:https";
import { URL } from "node:url";

const BASE_URL = process.env.CONTROL_PLANE_URL ?? "http://localhost:3000";
const REQUEST_TIMEOUT_MS = 10_000;
const POLL_TIMEOUT_MS = 10_000;
const SSE_TIMEOUT_MS = 10_000;

type JsonObject = Record<string, unknown>;

type HttpResponse<T = unknown> = {
  statusCode: number;
  headers: http.IncomingHttpHeaders;
  body: T;
};

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requestJson<T = unknown>(
  method: string,
  path: string,
  body?: unknown,
  headers: Record<string, string> = {}
): Promise<HttpResponse<T>> {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const payload = body === undefined ? undefined : JSON.stringify(body);
    const client = url.protocol === "https:" ? https : http;

    const req = client.request(
      url,
      {
        method,
        headers: {
          Accept: "application/json",
          ...(payload ? { "Content-Type": "application/json", "Content-Length": String(Buffer.byteLength(payload)) } : {}),
          ...headers
        },
        timeout: REQUEST_TIMEOUT_MS
      },
      (res) => {
        let raw = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          raw += chunk;
        });
        res.on("end", () => {
          const statusCode = res.statusCode ?? 0;
          let parsed: unknown = raw;

          if (raw.length > 0) {
            try {
              parsed = JSON.parse(raw);
            } catch {
              parsed = raw;
            }
          }

          if (statusCode < 200 || statusCode >= 300) {
            reject(new Error(`${method} ${path} failed with ${statusCode}: ${raw}`));
            return;
          }

          resolve({ statusCode, headers: res.headers, body: parsed as T });
        });
      }
    );

    req.on("timeout", () => {
      req.destroy(new Error(`${method} ${path} timed out after ${REQUEST_TIMEOUT_MS}ms`));
    });
    req.on("error", reject);

    if (payload) {
      req.write(payload);
    }
    req.end();
  });
}

async function waitFor<T>(description: string, load: () => Promise<T>, predicate: (value: T) => boolean): Promise<T> {
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  let lastValue: T | undefined;

  while (Date.now() < deadline) {
    lastValue = await load();
    if (predicate(lastValue)) {
      return lastValue;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error(`Timed out waiting for ${description}. Last value: ${JSON.stringify(lastValue)}`);
}

function authHeaders(apiKey: string): Record<string, string> {
  return { Authorization: `ApiKey ${apiKey}` };
}

function extractDeviceId(body: unknown): string {
  assert(isObject(body), "Device registration response must be an object");

  const directId = body.device_id;
  if (typeof directId === "string" && directId.length > 0) {
    return directId;
  }

  const device = body.device;
  assert(isObject(device), "Device registration response must contain device_id or device.device_id");
  assert(typeof device.device_id === "string" && device.device_id.length > 0, "Device registration response missing device_id");
  return device.device_id;
}

function extractTaskId(body: unknown): string {
  assert(isObject(body), "Task response must be an object");
  assert(typeof body.task_id === "string" && body.task_id.length > 0, "Task response missing task_id");
  return body.task_id;
}

function extractRunId(eventsBody: unknown): string | null {
  assert(isObject(eventsBody), "Events response must be an object");
  assert(Array.isArray(eventsBody.events), "Events response missing events array");

  const runCreated = eventsBody.events.find(
    (event) => isObject(event) && event.event_type === "run.created" && typeof event.run_id === "string"
  );

  return isObject(runCreated) && typeof runCreated.run_id === "string" ? runCreated.run_id : null;
}

function readExactlyTwoSseDataLines(path: string, headers: Record<string, string>): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const client = url.protocol === "https:" ? https : http;
    const dataLines: string[] = [];
    let buffer = "";
    let settled = false;

    const finish = (error?: Error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeout);
      req.destroy();
      if (error) {
        reject(error);
      } else {
        resolve(dataLines);
      }
    };

    const timeout = setTimeout(() => {
      finish(new Error(`SSE stream timed out after ${SSE_TIMEOUT_MS}ms with ${dataLines.length} data event(s)`));
    }, SSE_TIMEOUT_MS);

    const req = client.request(
      url,
      {
        method: "GET",
        headers: {
          Accept: "text/event-stream",
          ...headers
        }
      },
      (res) => {
        const statusCode = res.statusCode ?? 0;
        if (statusCode < 200 || statusCode >= 300) {
          let raw = "";
          res.setEncoding("utf8");
          res.on("data", (chunk) => {
            raw += chunk;
          });
          res.on("end", () => {
            finish(new Error(`GET ${path} failed with ${statusCode}: ${raw}`));
          });
          return;
        }

        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          buffer += chunk;
          const lines = buffer.split(/\r?\n/);
          buffer = lines.pop() ?? "";

          for (const line of lines) {
            if (!line.startsWith("data:")) {
              continue;
            }

            const data = line.slice("data:".length).trimStart();
            console.log(`SSE data: ${data}`);
            dataLines.push(data);

            if (dataLines.length === 2) {
              finish();
              return;
            }
          }
        });
        res.on("error", finish);
      }
    );

    req.on("error", (error) => {
      if (!settled) {
        finish(error);
      }
    });
    req.end();
  });
}

async function main(): Promise<void> {
  const registered = await requestJson("POST", "/v1/devices", {
    device_name: `smoke-${Date.now()}`,
    runtime_type: "desktop",
    permission_scope: "private_lan"
  });
  assert(registered.statusCode === 201, "Device registration must return 201");

  const deviceId = extractDeviceId(registered.body);
  assert(isObject(registered.body) && typeof registered.body.api_key === "string", "Device registration response missing api_key");
  const apiKey = registered.body.api_key;

  await requestJson(
    "POST",
    "/v1/heartbeat",
    {
      device_id: deviceId,
      is_online: true,
      network_type: "wifi",
      active_run_count: 0,
      supported_tools: ["shell"],
      supported_capabilities: ["cpu_inference"]
    },
    authHeaders(apiKey)
  );

  const submitted = await requestJson(
    "POST",
    "/v1/tasks",
    {
      schema_version: "1.0.0",
      intent: "smoke test task",
      goal: {},
      permission_level: "private_lan",
      required_tools: ["shell"],
      required_capabilities: ["cpu_inference"],
      complexity_hint: "light",
      raw_input: "smoke test task"
    },
    authHeaders(apiKey)
  );
  assert(submitted.statusCode === 201, "Task submission must return 201");

  const taskId = extractTaskId(submitted.body);
  const routedTask = await waitFor(
    "task to enter routing or scheduled",
    async () => (await requestJson("GET", `/v1/tasks/${taskId}`, undefined, authHeaders(apiKey))).body,
    (task) => isObject(task) && (task.current_state === "routing" || task.current_state === "scheduled" || task.current_state === "running")
  );
  assert(
    isObject(routedTask) &&
      (routedTask.current_state === "routing" || routedTask.current_state === "scheduled" || routedTask.current_state === "running"),
    `Expected task state routing, scheduled, or running; got ${JSON.stringify(routedTask)}`
  );

  const submittedEvents = await requestJson("GET", `/v1/tasks/${taskId}/events`, undefined, authHeaders(apiKey));
  assert(isObject(submittedEvents.body), "Events response must be an object");
  assert(Array.isArray(submittedEvents.body.events), "Events response missing events array");
  assert(submittedEvents.body.events.length > 0, "Expected at least one task event");
  assert(
    submittedEvents.body.events.some((event) => isObject(event) && event.event_type === "task.submitted"),
    "Expected task.submitted event"
  );

  const eventsWithRun = await waitFor(
    "run.created event",
    async () => (await requestJson("GET", `/v1/tasks/${taskId}/events`, undefined, authHeaders(apiKey))).body,
    (body) => extractRunId(body) !== null
  );
  const runId = extractRunId(eventsWithRun);
  assert(runId, "Expected run.created event with run_id before SSE state updates");

  const ssePromise = readExactlyTwoSseDataLines(`/v1/tasks/${taskId}/stream`, authHeaders(apiKey));
  await new Promise((resolve) => setTimeout(resolve, 100));

  await requestJson(
    "POST",
    `/v1/runs/${runId}/events`,
    {
      schema_version: "1.0.0",
      event_type: "run.started",
      task_id: taskId,
      source: "desktop",
      emitted_at: new Date().toISOString(),
      payload: {}
    },
    authHeaders(apiKey)
  );

  await requestJson(
    "POST",
    `/v1/runs/${runId}/events`,
    {
      schema_version: "1.0.0",
      event_type: "run.completed",
      task_id: taskId,
      source: "desktop",
      emitted_at: new Date().toISOString(),
      payload: {}
    },
    authHeaders(apiKey)
  );

  const sseDataLines = await ssePromise;
  assert(sseDataLines.length === 2, `Expected exactly 2 SSE data lines, got ${sseDataLines.length}`);

  console.log("SMOKE TEST PASSED");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
