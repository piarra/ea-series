import { EventEmitter } from "node:events";
import {
  Backtest,
  listenBacktestProgress,
  listenDoneBacktest,
  listenError,
  listenSignalBacktest,
} from "backtest-kit";
import { appendAnnotation } from "./annotation-store.mjs";

const emitter = new EventEmitter();

const history = [];
let sequence = 0;
let runningJob = null;

const MAX_HISTORY = 2_000;

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

const publish = (event) => {
  const payload = {
    id: ++sequence,
    createdAt: Date.now(),
    ...event,
  };

  history.push(payload);
  if (history.length > MAX_HISTORY) {
    history.shift();
  }

  emitter.emit("event", payload);
};

listenBacktestProgress((event) => {
  publish({
    type: "backtest_progress",
    payload: {
      ...event,
      progressPercent: Math.round(event.progress * 10_000) / 100,
    },
  });
});

listenDoneBacktest((event) => {
  if (
    runningJob &&
    runningJob.symbol === event.symbol &&
    runningJob.strategyName === event.strategyName &&
    runningJob.exchangeName === event.exchangeName &&
    runningJob.frameName === event.frameName
  ) {
    runningJob = null;
  }

  publish({
    type: "backtest_done",
    payload: event,
  });
});

listenSignalBacktest(async (event) => {
  const payload = {
    action: event.action,
    symbol: event.symbol,
    strategyName: event.strategyName,
    exchangeName: event.exchangeName,
    frameName: event.frameName,
    currentPrice: event.currentPrice,
    createdAt: event.createdAt,
    signalId: event.signal?.id || "",
  };

  publish({
    type: "backtest_signal",
    payload,
  });

  if (["opened", "scheduled", "closed", "cancelled"].includes(event.action)) {
    await appendAnnotation(
      {
        type: "signal",
        ...payload,
      },
      {
        dedupeKey: `signal:${payload.signalId}:${payload.action}`,
        dedupeMs: 500,
      },
    );
  }
});

listenError((error) => {
  publish({
    type: "backtest_error",
    payload: {
      message: toErrorMessage(error),
    },
  });
});

export const subscribeProjectEvents = (fn, options = {}) => {
  const replay = Math.max(0, options.replay || 0);

  if (replay > 0) {
    for (const event of history.slice(-replay)) {
      fn(event);
    }
  }

  emitter.on("event", fn);

  return () => {
    emitter.off("event", fn);
  };
};

export const getProjectHistory = (limit = 100) =>
  history.slice(-Math.max(1, limit));

export const getBacktestStatus = () => ({
  running: Boolean(runningJob),
  runningJob,
});

export const runBacktestJob = async ({
  symbol,
  strategyName,
  frameName,
  exchangeName,
  execution = "background",
}) => {
  if (runningJob) {
    throw new Error(
      `A backtest is already running: ${runningJob.symbol} / ${runningJob.strategyName}`,
    );
  }

  runningJob = {
    symbol,
    strategyName,
    frameName,
    exchangeName,
    requestedAt: Date.now(),
  };

  publish({
    type: "backtest_started",
    payload: runningJob,
  });

  try {
    const context = {
      strategyName,
      frameName,
      exchangeName,
    };

    if (execution === "run") {
      for await (const _ of Backtest.run(symbol, context)) {
        // Consume generator to ensure CLI waits until completion.
      }
      runningJob = null;
      return;
    }

    if (execution === "background") {
      Backtest.background(symbol, context);
      return;
    }

    throw new Error(`Unsupported backtest execution mode: ${execution}`);
  } catch (error) {
    publish({
      type: "backtest_error",
      payload: {
        message: toErrorMessage(error),
      },
    });
    runningJob = null;
    throw error;
  }
};
