import { REGIME_COOLING_BARS } from "../../config/params.mjs";
import { closes, ema, lastFinite } from "./indicators.mjs";

export const RegimeState = {
  Normal: "normal",
  TrendUp: "trend_up",
  TrendDown: "trend_down",
  Cooling: "cooling",
};

const regimeMemory = new Map();

const intervalToMs = {
  "1m": 60_000,
  "3m": 180_000,
  "5m": 300_000,
  "15m": 900_000,
  "30m": 1_800_000,
  "1h": 3_600_000,
};

export const evaluateRawRegime = (candles) => {
  const closeList = closes(candles);

  if (closeList.length < 64) {
    return {
      regime: RegimeState.Normal,
      score: 0,
    };
  }

  const fast = ema(closeList, 21);
  const slow = ema(closeList, 55);

  const fastNow = lastFinite(fast);
  const slowNow = lastFinite(slow);

  if (!Number.isFinite(fastNow) || !Number.isFinite(slowNow)) {
    return {
      regime: RegimeState.Normal,
      score: 0,
    };
  }

  const closeNow = closeList[closeList.length - 1];
  const fastPrevIndex = Math.max(0, fast.length - 6);
  const fastPrev = fast[fastPrevIndex];

  const diffRatio = (fastNow - slowNow) / closeNow;
  const slopeRatio = Number.isFinite(fastPrev)
    ? (fastNow - fastPrev) / closeNow
    : 0;

  const score = Math.abs(diffRatio) + Math.abs(slopeRatio);

  if (Math.abs(diffRatio) < 0.0006) {
    return {
      regime: RegimeState.Normal,
      score,
    };
  }

  return {
    regime: diffRatio > 0 ? RegimeState.TrendUp : RegimeState.TrendDown,
    score,
  };
};

export const evaluateRegime = ({
  key,
  candles,
  when,
  interval = "1m",
  coolingBars = REGIME_COOLING_BARS,
}) => {
  const intervalMs = intervalToMs[interval] || intervalToMs["1m"];
  const now = when.getTime();

  const raw = evaluateRawRegime(candles);
  const prev = regimeMemory.get(key);

  let changed = false;

  if (!prev || prev.rawRegime !== raw.regime) {
    changed = true;
    regimeMemory.set(key, {
      rawRegime: raw.regime,
      changedAt: now,
      coolingUntil: now + coolingBars * intervalMs,
    });
  }

  const state = regimeMemory.get(key);
  const inCooling = now < state.coolingUntil;

  return {
    rawRegime: raw.regime,
    regime: inCooling ? RegimeState.Cooling : state.rawRegime,
    changed,
    score: raw.score,
    coolingUntil: state.coolingUntil,
  };
};

export const clearRegimeState = () => {
  regimeMemory.clear();
};
