import type { Response } from "express";

export class SseBroadcaster {
  private readonly clients = new Map<string, Set<Response>>();
  private readonly heartbeats = new Map<Response, NodeJS.Timeout>();
  private readonly wsClients = new Map<string, Set<import("ws").WebSocket>>();

  subscribe(taskId: string, res: Response): void {
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.write(": connected\n\n");

    const taskClients = this.clients.get(taskId) ?? new Set<Response>();
    taskClients.add(res);
    this.clients.set(taskId, taskClients);

    const heartbeat = setInterval(() => {
      res.write(": ping\n\n");
    }, 25_000);
    this.heartbeats.set(res, heartbeat);

    res.on("close", () => {
      this.unsubscribe(taskId, res);
    });
  }

  unsubscribe(taskId: string, res: Response): void {
    const heartbeat = this.heartbeats.get(res);
    if (heartbeat) {
      clearInterval(heartbeat);
      this.heartbeats.delete(res);
    }

    const taskClients = this.clients.get(taskId);
    if (!taskClients) {
      return;
    }

    taskClients.delete(res);
    if (taskClients.size === 0) {
      this.clients.delete(taskId);
    }
  }

  subscribeWs(taskId: string, ws: import("ws").WebSocket): void {
    const taskClients = this.wsClients.get(taskId) ?? new Set<import("ws").WebSocket>();
    taskClients.add(ws);
    this.wsClients.set(taskId, taskClients);
  }

  unsubscribeWs(taskId: string, ws: import("ws").WebSocket): void {
    const taskClients = this.wsClients.get(taskId);
    if (!taskClients) {
      return;
    }

    taskClients.delete(ws);
    if (taskClients.size === 0) {
      this.wsClients.delete(taskId);
    }
  }

  broadcast(taskId: string, data: object): void {
    const serializedData = JSON.stringify(data);
    const taskClients = this.clients.get(taskId);
    if (taskClients) {
      const message = `data: ${serializedData}\n\n`;
      for (const client of taskClients) {
        client.write(message);
      }
    }

    const taskWsClients = this.wsClients.get(taskId);
    if (taskWsClients) {
      for (const ws of taskWsClients) {
        ws.send(serializedData);
      }
    }
  }
}
