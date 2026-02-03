import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "./style.css";

type LogEntry = {
  id?: string;
  ts?: string;
  message: string;
  level?: string;
  context?: unknown;
};

type ConnState = "connecting" | "live" | "waiting";

const LIMIT = 1000;
const INITIAL_DELAY = 1000;
const MAX_DELAY = 15000;

const trimLogs = (list: LogEntry[]) => (list.length > LIMIT ? list.slice(-LIMIT) : list);

const Status = ({ state }: { state: ConnState }) => {
  const label = state === "live" ? "LIVE" : state === "waiting" ? "再接続待機中…" : "接続中...";
  const dotClass = state === "live" ? "dot ok" : "dot";
  return (
    <div className="status">
      <span className={dotClass}></span>
      <span>{label}</span>
    </div>
  );
};

const LogItem = ({ log }: { log: LogEntry }) => {
  const level = (log.level || "info").toLowerCase();
  const contextText = useMemo(() => {
    if (log.context === undefined) return null;
    try {
      return JSON.stringify(log.context, null, 2);
    } catch {
      return String(log.context);
    }
  }, [log.context]);

  return (
    <li className="log">
      <div className="row">
        <span className="ts">{log.ts || ""}</span>
        <span className={`level ${level}`}>{level}</span>
      </div>
      <div className="message">{log.message || ""}</div>
      {contextText ? <div className="context">{contextText}</div> : null}
    </li>
  );
};

const App = () => {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [state, setState] = useState<ConnState>("connecting");
  const listRef = useRef<HTMLUListElement | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const timerRef = useRef<number | null>(null);
  const delayRef = useRef<number>(INITIAL_DELAY);

  const guide = useMemo(() => {
    const origin = location.origin;
    return [
      'curl -X POST -H "Content-Type: application/json" \\',
      `-d '{"message":"hello from curl","level":"info","source":"local"}' \\`,
      `${origin}/logs`,
    ].join("\n");
  }, []);

  const connect = useCallback(() => {
    setState("connecting");
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    const ws = new WebSocket(`${protocol}//${location.host}/ws`);
    socketRef.current = ws;

    ws.addEventListener("open", () => {
      setState("live");
      delayRef.current = INITIAL_DELAY;
    });

    const scheduleReconnect = () => {
      setState("waiting");
      if (timerRef.current) window.clearTimeout(timerRef.current);
      timerRef.current = window.setTimeout(connect, delayRef.current);
      delayRef.current = Math.min(delayRef.current * 1.8, MAX_DELAY);
    };

    ws.addEventListener("close", scheduleReconnect);
    ws.addEventListener("error", scheduleReconnect);

    ws.addEventListener("message", (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "init" && Array.isArray(data.logs)) {
          setLogs(trimLogs(data.logs));
        } else if (data.type === "log" && data.log) {
          setLogs((prev) => trimLogs([...prev, data.log]));
        }
      } catch (err) {
        console.error("failed to parse", err);
      }
    });
  }, []);

  useEffect(() => {
    connect();
    return () => {
      socketRef.current?.close();
      if (timerRef.current) window.clearTimeout(timerRef.current);
    };
  }, [connect]);

  useEffect(() => {
    const list = listRef.current;
    if (!list) return;
    list.lastElementChild?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [logs]);

  return (
    <div className="shell">
      <header>
        <div className="headline">
          <h1>Log Stream</h1>
          <Status state={state} />
        </div>
        <div className="guide">{guide}</div>
      </header>
      <section className="logs">
        <ul className="log-list" ref={listRef}>
          {logs.map((log) => (
            <LogItem key={log.id || log.ts || crypto.randomUUID()} log={log} />
          ))}
        </ul>
      </section>
    </div>
  );
};

const rootElement = document.getElementById("root");
if (rootElement) {
  const root = createRoot(rootElement);
  root.render(<App />);
}

export default App;
