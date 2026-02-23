import http from "node:http";
import { getRouter } from "@backtest-kit/ui";
import { CONTROL_HOST, CONTROL_PORT, DEFAULT_SYMBOL } from "../config/params.mjs";
import ExchangeName from "../enum/ExchangeName.mjs";
import FrameName from "../enum/FrameName.mjs";
import StrategyName from "../enum/StrategyName.mjs";
import { readAnnotations } from "../runtime/annotation-store.mjs";
import {
  getBacktestStatus,
  getProjectHistory,
  runBacktestJob,
  subscribeProjectEvents,
} from "../runtime/backtest-manager.mjs";

const sendJson = (res, statusCode, payload) => {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
};

const sendHtml = (res, html) => {
  res.statusCode = 200;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(html);
};

const readJsonBody = async (req) => {
  const chunks = [];

  for await (const chunk of req) {
    chunks.push(chunk);
  }

  if (chunks.length === 0) {
    return {};
  }

  const raw = Buffer.concat(chunks).toString("utf-8").trim();
  if (!raw) {
    return {};
  }

  return JSON.parse(raw);
};

const toErrorMessage = (error) => {
  if (error instanceof Error) {
    return error.stack || error.message;
  }
  if (typeof error === "string") {
    return error;
  }
  try {
    return JSON.stringify(error);
  } catch {
    return "Unknown error";
  }
};

const pageHtml = () => `<!doctype html>
<html lang="ja">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>backtest-kit control</title>
    <style>
      :root {
        color-scheme: light;
        --bg: #f6f7f3;
        --panel: #ffffff;
        --line: #d8d8cf;
        --ink: #1c2126;
        --accent: #244f7a;
      }
      body {
        margin: 0;
        font-family: "Trebuchet MS", "Segoe UI", sans-serif;
        color: var(--ink);
        background: linear-gradient(120deg, #ecefe4, #f8f6f0);
      }
      .layout {
        display: grid;
        grid-template-columns: minmax(320px, 420px) 1fr;
        gap: 12px;
        min-height: 100vh;
        padding: 12px;
        box-sizing: border-box;
      }
      .panel {
        background: var(--panel);
        border: 1px solid var(--line);
        border-radius: 14px;
        padding: 12px;
        box-sizing: border-box;
      }
      h1 {
        margin: 0 0 10px;
        font-size: 18px;
        letter-spacing: 0.02em;
      }
      label {
        display: block;
        font-size: 12px;
        margin: 10px 0 4px;
      }
      input, select, button {
        width: 100%;
        box-sizing: border-box;
        padding: 8px;
        border-radius: 8px;
        border: 1px solid var(--line);
        font-size: 14px;
      }
      button {
        margin-top: 12px;
        border: 0;
        background: var(--accent);
        color: #fff;
        font-weight: 700;
      }
      pre {
        margin: 6px 0 0;
        padding: 10px;
        border-radius: 8px;
        border: 1px solid var(--line);
        background: #f9faf8;
        font-size: 11px;
        line-height: 1.4;
        max-height: 220px;
        overflow: auto;
      }
      iframe {
        width: 100%;
        min-height: calc(100vh - 24px);
        border: 1px solid var(--line);
        border-radius: 14px;
        background: #fff;
      }
      .muted {
        color: #5f6470;
        font-size: 12px;
      }
      @media (max-width: 960px) {
        .layout {
          grid-template-columns: 1fr;
        }
        iframe {
          min-height: 70vh;
        }
      }
    </style>
  </head>
  <body>
    <div class="layout">
      <section class="panel">
        <h1>Backtest Control</h1>
        <div class="muted">/control からバックテストを起動。右側に @backtest-kit/ui を表示。</div>

        <label for="symbol">Symbol</label>
        <input id="symbol" value="${DEFAULT_SYMBOL}" />

        <label for="strategy">Strategy</label>
        <select id="strategy">
          <option value="${StrategyName.Nm3PortV1}">NM3 Port v1</option>
          <option value="${StrategyName.Single2PortV1}">SINGLE2 Port v1</option>
        </select>

        <label for="frame">Frame</label>
        <select id="frame">
          <option value="${FrameName.DatasetWindow}">Dataset Window</option>
          <option value="${FrameName.January2025}">January 2025</option>
          <option value="${FrameName.February2025}">February 2025</option>
        </select>

        <button id="run">Start Backtest</button>

        <label>Status</label>
        <pre id="status">loading...</pre>

        <label>Events (SSE)</label>
        <pre id="events"></pre>

        <label>Annotations</label>
        <pre id="annotations"></pre>
      </section>

      <section>
        <iframe src="/" title="backtest-kit dashboard"></iframe>
      </section>
    </div>

    <script>
      const statusEl = document.getElementById("status");
      const eventsEl = document.getElementById("events");
      const annotationsEl = document.getElementById("annotations");

      const appendEvent = (payload) => {
        const line = JSON.stringify(payload);
        eventsEl.textContent = (line + "\\n" + eventsEl.textContent).slice(0, 16000);
      };

      const fetchStatus = async () => {
        const response = await fetch("/api/project/status");
        const data = await response.json();
        statusEl.textContent = JSON.stringify(data, null, 2);
      };

      const fetchAnnotations = async () => {
        const response = await fetch("/api/project/annotations?limit=30");
        const data = await response.json();
        annotationsEl.textContent = JSON.stringify(data, null, 2);
      };

      document.getElementById("run").addEventListener("click", async () => {
        const symbol = document.getElementById("symbol").value.trim();
        const strategyName = document.getElementById("strategy").value;
        const frameName = document.getElementById("frame").value;

        const payload = {
          symbol,
          strategyName,
          frameName,
          exchangeName: "${ExchangeName.DukascopyExchange}",
        };

        const response = await fetch("/api/project/backtest/run", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
        });

        const data = await response.json();
        appendEvent({ local: true, type: "run_response", data });
        await fetchStatus();
      });

      const source = new EventSource("/api/project/backtest/events");
      source.onmessage = async (event) => {
        try {
          const data = JSON.parse(event.data);
          appendEvent(data);
          await fetchStatus();
          await fetchAnnotations();
        } catch (error) {
          appendEvent({ local: true, type: "parse_error", message: String(error) });
        }
      };

      setInterval(fetchStatus, 7000);
      setInterval(fetchAnnotations, 9000);

      fetchStatus();
      fetchAnnotations();
    </script>
  </body>
</html>`;

export const startControlServer = ({
  host = CONTROL_HOST,
  port = CONTROL_PORT,
} = {}) => {
  const uiRouter = getRouter();

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);

    if (url.pathname.startsWith("/api/project/")) {
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");
      res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
    }

    if (req.method === "OPTIONS") {
      res.statusCode = 204;
      res.end();
      return;
    }

    try {
      if (req.method === "GET" && url.pathname === "/control") {
        sendHtml(res, pageHtml());
        return;
      }

      if (req.method === "GET" && url.pathname === "/api/project/status") {
        sendJson(res, 200, {
          status: "ok",
          data: {
            ...getBacktestStatus(),
            recentEvents: getProjectHistory(20),
          },
        });
        return;
      }

      if (req.method === "GET" && url.pathname === "/api/project/annotations") {
        const limit = Number.parseInt(url.searchParams.get("limit") || "30", 10);
        const data = await readAnnotations(Number.isFinite(limit) ? limit : 30);
        sendJson(res, 200, {
          status: "ok",
          data,
        });
        return;
      }

      if (req.method === "POST" && url.pathname === "/api/project/backtest/run") {
        const body = await readJsonBody(req);
        const status = getBacktestStatus();

        if (status.running) {
          sendJson(res, 409, {
            status: "error",
            error: "Backtest already running",
            data: status,
          });
          return;
        }

        const payload = {
          symbol: body.symbol || DEFAULT_SYMBOL,
          strategyName: body.strategyName || StrategyName.Nm3PortV1,
          frameName: body.frameName || FrameName.DatasetWindow,
          exchangeName: body.exchangeName || ExchangeName.DukascopyExchange,
        };

        void runBacktestJob(payload).catch((error) => {
          console.error(toErrorMessage(error));
        });

        sendJson(res, 202, {
          status: "ok",
          data: {
            accepted: true,
            payload,
          },
        });
        return;
      }

      if (req.method === "GET" && url.pathname === "/api/project/backtest/events") {
        res.writeHead(200, {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        });

        const send = (event) => {
          res.write(`data: ${JSON.stringify(event)}\n\n`);
        };

        send({
          type: "initial_status",
          payload: getBacktestStatus(),
        });

        for (const event of getProjectHistory(30)) {
          send(event);
        }

        const unsubscribe = subscribeProjectEvents(send);
        const pingTimer = setInterval(() => {
          res.write(`: ping ${Date.now()}\n\n`);
        }, 15_000);

        req.on("close", () => {
          clearInterval(pingTimer);
          unsubscribe();
          res.end();
        });

        return;
      }

      return uiRouter(req, res);
    } catch (error) {
      sendJson(res, 500, {
        status: "error",
        error: toErrorMessage(error),
      });
    }
  });

  server.listen(port, host, () => {
    console.log(`Control + UI server listening on http://${host}:${port}`);
    console.log(`Control page: http://${host}:${port}/control`);
  });

  return () => {
    server.close();
  };
};
