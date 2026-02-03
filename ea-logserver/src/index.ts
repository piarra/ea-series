export interface Env {
  LOG_HUB: DurableObjectNamespace;
  LOG_HISTORY_LIMIT?: string;
  ASSETS: Fetcher;
}

const DEFAULT_LIMIT = 1000;

type IncomingLog = {
  message: string;
  level?: string;
  context?: Record<string, unknown>;
  source?: string;
};

type LogEntry = IncomingLog & {
  id: string;
  ts: string;
};

type LogRow = {
  id: string;
  ts: string;
  level: string | null;
  message: string;
  context: string | null;
  source: string | null;
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/ws") {
      const id = env.LOG_HUB.idFromName("global-log-hub");
      const stub = env.LOG_HUB.get(id);
      return stub.fetch(request);
    }

    if (url.pathname === "/logs" && request.method === "POST") {
      return handleLogIngress(request, env);
    }

    if (url.pathname === "/logs" && request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }

    if (url.pathname === "/health") {
      return new Response("ok", { status: 200 });
    }

    // Fallback to static assets built by Vite
    if (request.method === "GET" || request.method === "HEAD") {
      const assetResponse = await env.ASSETS.fetch(request);
      if (assetResponse.status !== 404) return assetResponse;
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleLogIngress(request: Request, env: Env): Promise<Response> {
  try {
    const normalized = await normalizeLogPayload(request);
    const id = env.LOG_HUB.idFromName("global-log-hub");
    const stub = env.LOG_HUB.get(id);

    const forwardRequest = new Request("https://log-hub.internal/broadcast", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ entry: normalized }),
    });

    const res = await stub.fetch(forwardRequest);
    if (!res.ok) {
      const text = await res.text();
      return new Response(text || "failed to publish log", {
        status: res.status,
        headers: corsHeaders(),
      });
    }

    return new Response(JSON.stringify({ ok: true, id: normalized.id }), {
      status: 202,
      headers: { ...corsHeaders(), "content-type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "invalid payload";
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 400,
      headers: { ...corsHeaders(), "content-type": "application/json" },
    });
  }
}

function corsHeaders(): Record<string, string> {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "Content-Type, Authorization, X-Source, X-Level",
  };
}

async function normalizeLogPayload(request: Request): Promise<LogEntry> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  let body: any;

  if (contentType.includes("application/json")) {
    body = await request.json();
  } else {
    const text = (await request.text()).trim();
    body = { message: text };
  }

  if (!body || typeof body.message !== "string" || body.message.trim().length === 0) {
    throw new Error("message is required");
  }

  const levelHeader = request.headers.get("x-level");
  const sourceHeader = request.headers.get("x-source");

  const entry: LogEntry = {
    id: crypto.randomUUID(),
    ts: new Date().toISOString(),
    message: body.message.trim(),
    level: String(body.level ?? levelHeader ?? "info").toLowerCase(),
    context: isRecord(body.context) ? body.context : undefined,
    source: typeof body.source === "string" ? body.source : sourceHeader ?? undefined,
  };

  return entry;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export class LogHub {
  private sockets: Set<WebSocket>;
  private logBuffer: LogEntry[];
  private limit: number;
  private sql: SqlStorage;
  private ready: Promise<void>;

  constructor(private state: DurableObjectState, private env: Env) {
    this.sockets = new Set();
    this.logBuffer = [];
    this.limit = Number(env.LOG_HISTORY_LIMIT) || DEFAULT_LIMIT;
    this.sql = this.state.storage.sql;

    this.ready = this.state.blockConcurrencyWhile(async () => {
      this.initializeDatabase();
      this.logBuffer = this.loadRecentLogs();
    });
  }

  async fetch(request: Request): Promise<Response> {
    await this.ready;
    const url = new URL(request.url);
    const isWebSocket = request.headers.get("upgrade") === "websocket";

    if (isWebSocket && url.pathname === "/ws") {
      return this.handleWebSocket();
    }

    if (url.pathname === "/broadcast" && request.method === "POST") {
      try {
        const body = await request.json<any>();
        if (!body?.entry) {
          return new Response("missing entry", { status: 400 });
        }
        return this.broadcast(body.entry as LogEntry);
      } catch (err) {
        const msg = err instanceof Error ? err.message : "invalid json";
        return new Response(msg, { status: 400 });
      }
    }

    return new Response("Not found", { status: 404 });
  }

  private handleWebSocket(): Response {
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    server.accept();
    this.sockets.add(server);

    // Send current buffer to new client
    server.send(JSON.stringify({ type: "init", logs: this.logBuffer }));

    const cleanup = () => this.sockets.delete(server);
    server.addEventListener("close", cleanup);
    server.addEventListener("error", cleanup);

    return new Response(null, { status: 101, webSocket: client });
  }

  private async broadcast(entry: LogEntry): Promise<Response> {
    this.persistEntry(entry);
    this.logBuffer.push(entry);
    if (this.logBuffer.length > this.limit) {
      this.logBuffer.splice(0, this.logBuffer.length - this.limit);
    }

    const payload = JSON.stringify({ type: "log", log: entry });
    for (const socket of Array.from(this.sockets)) {
      try {
        if (socket.readyState === WebSocket.OPEN) {
          socket.send(payload);
        } else {
          this.sockets.delete(socket);
        }
      } catch {
        this.sockets.delete(socket);
      }
    }

    return new Response("published", { status: 202 });
  }

  private initializeDatabase(): void {
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS logs (
        id TEXT PRIMARY KEY,
        ts TEXT NOT NULL,
        level TEXT,
        message TEXT NOT NULL,
        context TEXT,
        source TEXT
      );
    `);
    this.sql.exec(`CREATE INDEX IF NOT EXISTS logs_ts_idx ON logs (ts DESC, id DESC);`);
  }

  private loadRecentLogs(): LogEntry[] {
    const rows = this.sql
      .exec<LogRow>(
        `SELECT id, ts, level, message, context, source
         FROM logs
         ORDER BY ts DESC, id DESC
         LIMIT ?`,
        this.limit
      )
      .toArray();

    return rows
      .reverse()
      .map((row) => ({
        id: row.id,
        ts: row.ts,
        level: row.level ?? undefined,
        message: row.message,
        context: row.context ? this.parseContext(row.context) : undefined,
        source: row.source ?? undefined,
      }))
      .filter(Boolean);
  }

  private parseContext(payload: string): Record<string, unknown> | undefined {
    try {
      const parsed = JSON.parse(payload);
      return isRecord(parsed) ? parsed : undefined;
    } catch {
      return undefined;
    }
  }

  private persistEntry(entry: LogEntry): void {
    this.sql.exec(
      `INSERT OR REPLACE INTO logs (id, ts, level, message, context, source)
       VALUES (?, ?, ?, ?, ?, ?);`,
      entry.id,
      entry.ts,
      entry.level ?? null,
      entry.message,
      entry.context ? JSON.stringify(entry.context) : null,
      entry.source ?? null
    );

    this.sql.exec(
      `DELETE FROM logs
       WHERE id NOT IN (
         SELECT id FROM logs
         ORDER BY ts DESC, id DESC
         LIMIT ?
       );`,
      this.limit
    );
  }
}
