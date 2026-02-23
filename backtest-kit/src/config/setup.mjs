import {
  Markdown,
  Notification,
  NotificationBacktest,
  Report,
  setLogger,
  Storage,
  StorageBacktest,
} from "backtest-kit";
import { createLogger } from "pinolog";

const logger = createLogger("backtest-kit.log");

setLogger({
  log: (...args) => logger.log(...args),
  debug: (...args) => logger.info(...args),
  info: (...args) => logger.info(...args),
  warn: (...args) => logger.warn(...args),
});

Storage.enable();
Notification.enable();
Report.enable();
Markdown.disable();

const usePersist = process.env.BACKTEST_USE_PERSIST !== "0";

if (usePersist) {
  StorageBacktest.usePersist();
  NotificationBacktest.usePersist();
} else {
  StorageBacktest.useMemory();
  NotificationBacktest.useMemory();
}
