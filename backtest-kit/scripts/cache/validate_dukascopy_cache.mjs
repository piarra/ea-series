import "dotenv/config";

import { checkCandles } from "backtest-kit";
import { DEFAULT_SYMBOL } from "../../src/config/params.mjs";
import ExchangeName from "../../src/enum/ExchangeName.mjs";

const parseDate = (value, fallback) => {
  const date = new Date(value || fallback);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid date: ${value}`);
  }
  return date;
};

const symbol = process.env.CACHE_SYMBOL || DEFAULT_SYMBOL;
const from = parseDate(process.env.CACHE_FROM, "2025-01-01T00:00:00Z");
const to = parseDate(process.env.CACHE_TO, "2025-01-31T23:59:00Z");
const intervals = (process.env.CACHE_INTERVALS || "1m,5m,15m")
  .split(",")
  .map((value) => value.trim())
  .filter((value) => value.length > 0);

for (const interval of intervals) {
  console.log(`Validating cache: ${symbol} ${interval} ${from.toISOString()} -> ${to.toISOString()}`);
  await checkCandles({
    symbol,
    exchangeName: ExchangeName.DukascopyExchange,
    interval,
    from,
    to,
  });
}

console.log("Cache validation completed.");
