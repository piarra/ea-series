import path from "path";

const toInt = (value, fallback) => {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

const toFloat = (value, fallback) => {
  const parsed = Number.parseFloat(value ?? "");
  return Number.isFinite(parsed) ? parsed : fallback;
};

const toDate = (value, fallbackIso) => {
  const raw = value || fallbackIso;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid date value: ${raw}`);
  }
  return date;
};

export const PROJECT_ROOT = process.cwd();

export const DEFAULT_SYMBOL = process.env.DEFAULT_SYMBOL || "XAUUSD";
export const SILVER_SYMBOL = process.env.SILVER_SYMBOL || "XAGUSD";

export const DUKASCOPY_DATA_PATH =
  process.env.DUKASCOPY_DATA_PATH || path.join(PROJECT_ROOT, "data", "dukascopy");

export const DUKASCOPY_DEFAULT_SPREAD = toFloat(
  process.env.DUKASCOPY_DEFAULT_SPREAD,
  0,
);

export const BACKTEST_FRAME_START = toDate(
  process.env.BACKTEST_FRAME_START,
  "2025-01-01T00:00:00Z",
);

export const BACKTEST_FRAME_END = toDate(
  process.env.BACKTEST_FRAME_END,
  "2025-01-31T23:59:00Z",
);

export const NM3_TP_MULTIPLIER = toFloat(process.env.NM3_TP_MULTIPLIER, 1.6);
export const NM3_SL_MULTIPLIER = toFloat(process.env.NM3_SL_MULTIPLIER, 1.0);

export const SIMPLE2_MIN_RR = toFloat(process.env.SIMPLE2_MIN_RR, 2.1);
export const SINGLE2_SWING_TRAIL_DISTANCE_RATIO = toFloat(
  process.env.SINGLE2_SWING_TRAIL_DISTANCE_RATIO,
  0.55,
);
export const SINGLE2_SWING_TP_MULTIPLIER = toFloat(
  process.env.SINGLE2_SWING_TP_MULTIPLIER,
  12.0,
);

export const NEWS_CALENDAR_FILE = process.env.NEWS_CALENDAR_FILE || "";
export const NEWS_MINUTES_BEFORE = toInt(process.env.NEWS_MINUTES_BEFORE, 5);
export const NEWS_MINUTES_AFTER = toInt(process.env.NEWS_MINUTES_AFTER, 30);

export const BLACKOUT_WINDOWS =
  process.env.BLACKOUT_WINDOWS || "21:55-22:10";

export const REGIME_COOLING_BARS = toInt(process.env.REGIME_COOLING_BARS, 3);

export const CONTROL_HOST = process.env.CONTROL_HOST || "0.0.0.0";
export const CONTROL_PORT = toInt(process.env.CONTROL_PORT, 60050);
