import { addStrategySchema, getCandles } from "backtest-kit";
import {
  SILVER_SYMBOL,
  SIMPLE2_MIN_RR,
  SINGLE2_SWING_TP_MULTIPLIER,
  SINGLE2_SWING_TRAIL_DISTANCE_RATIO,
} from "../../config/params.mjs";
import ActionName from "../../enum/ActionName.mjs";
import RiskName from "../../enum/RiskName.mjs";
import StrategyName from "../../enum/StrategyName.mjs";
import { appendAnnotation } from "../../runtime/annotation-store.mjs";
import { checkTradingGuard } from "../shared/trading-guard.mjs";

const SetupDir = {
  None: 0,
  Buy: 1,
  Sell: -1,
};

const SMT_INTERVAL = "5m";
const ENTRY_INTERVAL = "1m";

const PIVOT_LEFT = 2;
const PIVOT_RIGHT = 2;
const LOOKBACK_BARS = 400;

const SETUP_EXPIRY_BARS = 12;
const SL_BUFFER_POINTS = 40;
const XAU_POINT_SIZE = 0.01;

const ENTRY_INTERVAL_MS = 60_000;
const SMT_INTERVAL_MS = 300_000;
const SMT_RETRY_COOLDOWN_MS = 24 * 60 * 60 * 1000;

const stateBySymbol = new Map();

const alignToInterval = (whenMs, intervalMs) =>
  Math.floor(whenMs / intervalMs) * intervalMs;

const toSeries = (candlesAsc) => {
  const list = Array.isArray(candlesAsc) ? candlesAsc : [];
  return list.slice().reverse();
};

const getState = (symbol) => {
  if (!stateBySymbol.has(symbol)) {
    stateBySymbol.set(symbol, {
      setupDir: SetupDir.None,
      setupTime: 0,
      lastSmtBarTime: 0,
      lastEntryBarTime: 0,
      smtRetryAfterTime: 0,
    });
  }
  return stateBySymbol.get(symbol);
};

const getPivotHighValue = (candlesSeries, shift) => candlesSeries[shift]?.high;
const getPivotLowValue = (candlesSeries, shift) => candlesSeries[shift]?.low;

const getLastTwoPivotHighs = (candlesSeries, left, right, lookback) => {
  let idx1 = -1;
  let idx2 = -1;

  const bars = candlesSeries.length;
  if (bars < left + right + 10) {
    return null;
  }

  const start = Math.min(lookback, bars - right - 1);

  for (let k = start; k >= right + left; k -= 1) {
    const hk = getPivotHighValue(candlesSeries, k);
    if (!Number.isFinite(hk)) {
      continue;
    }

    let ok = true;

    for (let j = 1; j <= left; j += 1) {
      const leftValue = getPivotHighValue(candlesSeries, k + j);
      if (!Number.isFinite(leftValue) || leftValue > hk) {
        ok = false;
        break;
      }
    }

    if (!ok) {
      continue;
    }

    for (let j = 1; j <= right; j += 1) {
      const rightValue = getPivotHighValue(candlesSeries, k - j);
      if (!Number.isFinite(rightValue) || rightValue >= hk) {
        ok = false;
        break;
      }
    }

    if (!ok) {
      continue;
    }

    if (idx1 === -1) {
      idx1 = k;
    } else {
      idx2 = idx1;
      idx1 = k;
    }

    if (idx2 !== -1) {
      return { idx1, idx2 };
    }
  }

  return null;
};

const getLastTwoPivotLows = (candlesSeries, left, right, lookback) => {
  let idx1 = -1;
  let idx2 = -1;

  const bars = candlesSeries.length;
  if (bars < left + right + 10) {
    return null;
  }

  const start = Math.min(lookback, bars - right - 1);

  for (let k = start; k >= right + left; k -= 1) {
    const lk = getPivotLowValue(candlesSeries, k);
    if (!Number.isFinite(lk)) {
      continue;
    }

    let ok = true;

    for (let j = 1; j <= left; j += 1) {
      const leftValue = getPivotLowValue(candlesSeries, k + j);
      if (!Number.isFinite(leftValue) || leftValue < lk) {
        ok = false;
        break;
      }
    }

    if (!ok) {
      continue;
    }

    for (let j = 1; j <= right; j += 1) {
      const rightValue = getPivotLowValue(candlesSeries, k - j);
      if (!Number.isFinite(rightValue) || rightValue <= lk) {
        ok = false;
        break;
      }
    }

    if (!ok) {
      continue;
    }

    if (idx1 === -1) {
      idx1 = k;
    } else {
      idx2 = idx1;
      idx1 = k;
    }

    if (idx2 !== -1) {
      return { idx1, idx2 };
    }
  }

  return null;
};

const buildPvtSeries = (candlesSeries, n) => {
  if (n <= 10 || candlesSeries.length < n) {
    return null;
  }

  const closeSeries = candlesSeries.slice(0, n).map((candle) => candle.close);
  const volumeSeries = candlesSeries
    .slice(0, n)
    .map((candle) =>
      Number.isFinite(candle.volume) && candle.volume > 0 ? candle.volume : 0,
    );

  const closeNs = new Array(n);
  const volNs = new Array(n);

  for (let index = 0; index < n; index += 1) {
    closeNs[index] = closeSeries[n - 1 - index];
    volNs[index] = volumeSeries[n - 1 - index];
  }

  const pvtNs = new Array(n).fill(0);

  for (let index = 1; index < n; index += 1) {
    const prev = closeNs[index - 1];

    if (!Number.isFinite(prev) || prev === 0) {
      pvtNs[index] = pvtNs[index - 1];
      continue;
    }

    const delta = (closeNs[index] - prev) / prev;
    pvtNs[index] = pvtNs[index - 1] + delta * volNs[index];
  }

  const pvtSeries = new Array(n);
  for (let index = 0; index < n; index += 1) {
    pvtSeries[index] = pvtNs[n - 1 - index];
  }

  return pvtSeries;
};

const pvtAt = (pvtSeries, shift) => {
  if (!Array.isArray(pvtSeries)) {
    return 0;
  }
  if (shift < 0 || shift >= pvtSeries.length) {
    return 0;
  }
  const value = pvtSeries[shift];
  return Number.isFinite(value) ? value : 0;
};

const checkSmt = (goldSmtSeries, silverSmtSeries) => {
  const gH = getLastTwoPivotHighs(goldSmtSeries, PIVOT_LEFT, PIVOT_RIGHT, LOOKBACK_BARS);
  const gL = getLastTwoPivotLows(goldSmtSeries, PIVOT_LEFT, PIVOT_RIGHT, LOOKBACK_BARS);
  const sH = getLastTwoPivotHighs(silverSmtSeries, PIVOT_LEFT, PIVOT_RIGHT, LOOKBACK_BARS);
  const sL = getLastTwoPivotLows(silverSmtSeries, PIVOT_LEFT, PIVOT_RIGHT, LOOKBACK_BARS);

  if (!gH || !gL || !sH || !sL) {
    return SetupDir.None;
  }

  const gHighNew = getPivotHighValue(goldSmtSeries, gH.idx1);
  const gHighOld = getPivotHighValue(goldSmtSeries, gH.idx2);
  const sHighNew = getPivotHighValue(silverSmtSeries, sH.idx1);
  const sHighOld = getPivotHighValue(silverSmtSeries, sH.idx2);

  const gLowNew = getPivotLowValue(goldSmtSeries, gL.idx1);
  const gLowOld = getPivotLowValue(goldSmtSeries, gL.idx2);
  const sLowNew = getPivotLowValue(silverSmtSeries, sL.idx1);
  const sLowOld = getPivotLowValue(silverSmtSeries, sL.idx2);

  if (
    ![
      gHighNew,
      gHighOld,
      sHighNew,
      sHighOld,
      gLowNew,
      gLowOld,
      sLowNew,
      sLowOld,
    ].every(Number.isFinite)
  ) {
    return SetupDir.None;
  }

  const goldHH = gHighNew > gHighOld;
  const silverHH = sHighNew > sHighOld;

  const goldLL = gLowNew < gLowOld;
  const silverLL = sLowNew < sLowOld;

  if (goldHH && !silverHH) {
    return SetupDir.Sell;
  }

  if (goldLL && !silverLL) {
    return SetupDir.Buy;
  }

  return SetupDir.None;
};

const checkPvtDivergence = (dir, goldSmtSeries) => {
  if (dir === SetupDir.None) {
    return false;
  }

  const highPivot = getLastTwoPivotHighs(
    goldSmtSeries,
    PIVOT_LEFT,
    PIVOT_RIGHT,
    LOOKBACK_BARS,
  );

  const lowPivot = getLastTwoPivotLows(
    goldSmtSeries,
    PIVOT_LEFT,
    PIVOT_RIGHT,
    LOOKBACK_BARS,
  );

  if (!highPivot || !lowPivot) {
    return false;
  }

  const n = Math.min(LOOKBACK_BARS, goldSmtSeries.length);
  if (n < 50) {
    return false;
  }

  const pvtSeries = buildPvtSeries(goldSmtSeries, n);
  if (!pvtSeries) {
    return false;
  }

  if (dir === SetupDir.Sell) {
    const priceNew = getPivotHighValue(goldSmtSeries, highPivot.idx1);
    const priceOld = getPivotHighValue(goldSmtSeries, highPivot.idx2);

    if (!(priceNew > priceOld)) {
      return false;
    }

    const pvtNew = pvtAt(pvtSeries, highPivot.idx1);
    const pvtOld = pvtAt(pvtSeries, highPivot.idx2);

    return pvtNew <= pvtOld;
  }

  const priceNew = getPivotLowValue(goldSmtSeries, lowPivot.idx1);
  const priceOld = getPivotLowValue(goldSmtSeries, lowPivot.idx2);

  if (!(priceNew < priceOld)) {
    return false;
  }

  const pvtNew = pvtAt(pvtSeries, lowPivot.idx1);
  const pvtOld = pvtAt(pvtSeries, lowPivot.idx2);

  return pvtNew >= pvtOld;
};

const checkStructureBreak = (dir, entrySeries) => {
  if (dir === SetupDir.None || entrySeries.length < 20) {
    return null;
  }

  const highPivot = getLastTwoPivotHighs(
    entrySeries,
    PIVOT_LEFT,
    PIVOT_RIGHT,
    LOOKBACK_BARS,
  );

  const lowPivot = getLastTwoPivotLows(
    entrySeries,
    PIVOT_LEFT,
    PIVOT_RIGHT,
    LOOKBACK_BARS,
  );

  if (!highPivot || !lowPivot) {
    return null;
  }

  const lastClose = entrySeries[1]?.close;
  const currentPrice = entrySeries[0]?.close;

  if (!Number.isFinite(lastClose) || !Number.isFinite(currentPrice)) {
    return null;
  }

  const buffer = SL_BUFFER_POINTS * XAU_POINT_SIZE;

  if (dir === SetupDir.Sell) {
    const pivotLow = getPivotLowValue(entrySeries, lowPivot.idx1);
    const highNew = getPivotHighValue(entrySeries, highPivot.idx1);
    const highOld = getPivotHighValue(entrySeries, highPivot.idx2);

    if (![pivotLow, highNew, highOld].every(Number.isFinite)) {
      return null;
    }

    const brokeLow = lastClose < pivotLow;
    const lowerHigh = highNew < highOld;

    if (!brokeLow || !lowerHigh) {
      return null;
    }

    let priceStopLoss = highNew + buffer;
    const priceOpen = currentPrice;

    if (priceStopLoss <= priceOpen) {
      priceStopLoss = priceOpen + buffer;
    }

    const risk = priceStopLoss - priceOpen;
    const scalpTakeProfit = priceOpen - SIMPLE2_MIN_RR * risk;
    const swingTakeProfit =
      priceOpen - SIMPLE2_MIN_RR * SINGLE2_SWING_TP_MULTIPLIER * risk;
    const swingTrailDistance =
      Math.abs(scalpTakeProfit - priceOpen) * SINGLE2_SWING_TRAIL_DISTANCE_RATIO;

    return {
      position: "short",
      priceOpen,
      priceStopLoss,
      scalpTakeProfit,
      swingTakeProfit,
      swingTrailDistance,
      structure: "sell_break",
    };
  }

  const pivotHigh = getPivotHighValue(entrySeries, highPivot.idx1);
  const lowNew = getPivotLowValue(entrySeries, lowPivot.idx1);
  const lowOld = getPivotLowValue(entrySeries, lowPivot.idx2);

  if (![pivotHigh, lowNew, lowOld].every(Number.isFinite)) {
    return null;
  }

  const brokeHigh = lastClose > pivotHigh;
  const higherLow = lowNew > lowOld;

  if (!brokeHigh || !higherLow) {
    return null;
  }

  let priceStopLoss = lowNew - buffer;
  const priceOpen = currentPrice;

  if (priceStopLoss >= priceOpen) {
    priceStopLoss = priceOpen - buffer;
  }

  const risk = priceOpen - priceStopLoss;
  const scalpTakeProfit = priceOpen + SIMPLE2_MIN_RR * risk;
  const swingTakeProfit =
    priceOpen + SIMPLE2_MIN_RR * SINGLE2_SWING_TP_MULTIPLIER * risk;
  const swingTrailDistance =
    Math.abs(scalpTakeProfit - priceOpen) * SINGLE2_SWING_TRAIL_DISTANCE_RATIO;

  return {
    position: "long",
    priceOpen,
    priceStopLoss,
    scalpTakeProfit,
    swingTakeProfit,
    swingTrailDistance,
    structure: "buy_break",
  };
};

const setupStillValid = (state, currentEntryBarTime) => {
  if (state.setupDir === SetupDir.None || state.setupTime <= 0) {
    return false;
  }

  if (currentEntryBarTime < state.setupTime) {
    return false;
  }

  const barsSinceSetup = Math.floor((currentEntryBarTime - state.setupTime) / ENTRY_INTERVAL_MS);

  return barsSinceSetup <= SETUP_EXPIRY_BARS;
};

const clearSetup = (state) => {
  state.setupDir = SetupDir.None;
  state.setupTime = 0;
};

const setupDirLabel = (dir) => {
  if (dir === SetupDir.Buy) {
    return "BUY";
  }
  if (dir === SetupDir.Sell) {
    return "SELL";
  }
  return "NONE";
};

addStrategySchema({
  strategyName: StrategyName.Single2PortV1,
  interval: ENTRY_INTERVAL,
  note: "SINGLE2 strict condition port (SMT + PVT + entry structure break)",
  riskList: [RiskName.MinDistanceRisk],
  actions: [ActionName.Single2DualLegAction],
  getSignal: async (symbol, when) => {
    const state = getState(symbol);

    const whenMs = when.getTime();
    const entryBarTime = alignToInterval(whenMs, ENTRY_INTERVAL_MS);
    const smtBarTime = alignToInterval(whenMs, SMT_INTERVAL_MS);

    const isNewSmtBar = smtBarTime > state.lastSmtBarTime;
    const isNewEntryBar = entryBarTime > state.lastEntryBarTime;

    if (isNewSmtBar) {
      state.lastSmtBarTime = smtBarTime;

      if (state.smtRetryAfterTime > whenMs) {
        return null;
      }

      try {
        const [goldSmtAsc, silverSmtAsc] = await Promise.all([
          getCandles(symbol, SMT_INTERVAL, LOOKBACK_BARS + 32),
          getCandles(SILVER_SYMBOL, SMT_INTERVAL, LOOKBACK_BARS + 32),
        ]);

        const goldSmtSeries = toSeries(goldSmtAsc);
        const silverSmtSeries = toSeries(silverSmtAsc);

        const smtDir = checkSmt(goldSmtSeries, silverSmtSeries);

        if (smtDir !== SetupDir.None && checkPvtDivergence(smtDir, goldSmtSeries)) {
          state.setupDir = smtDir;
          state.setupTime = entryBarTime;

          await appendAnnotation(
            {
              type: "setup_armed",
              strategyName: StrategyName.Single2PortV1,
              symbol,
              when: when.toISOString(),
              dir: setupDirLabel(smtDir),
              setupTime: new Date(entryBarTime).toISOString(),
            },
            {
              dedupeKey: `single2:setup:${symbol}:${setupDirLabel(smtDir)}`,
              dedupeMs: 15_000,
            },
          );
        }
      } catch {
        state.smtRetryAfterTime = whenMs + SMT_RETRY_COOLDOWN_MS;

        await appendAnnotation(
          {
            type: "warning",
            strategyName: StrategyName.Single2PortV1,
            symbol,
            when: when.toISOString(),
            reason: "smt_data_unavailable",
            detail: SILVER_SYMBOL,
            retryAfter: new Date(state.smtRetryAfterTime).toISOString(),
          },
          {
            dedupeKey: `single2:no_smt_data:${SILVER_SYMBOL}`,
            dedupeMs: 300_000,
          },
        );
      }
    }

    if (!isNewEntryBar) {
      return null;
    }

    state.lastEntryBarTime = entryBarTime;

    if (state.setupDir === SetupDir.None) {
      return null;
    }

    if (!setupStillValid(state, entryBarTime)) {
      await appendAnnotation(
        {
          type: "setup_expired",
          strategyName: StrategyName.Single2PortV1,
          symbol,
          when: when.toISOString(),
          dir: setupDirLabel(state.setupDir),
        },
        {
          dedupeKey: `single2:setup_expired:${symbol}`,
          dedupeMs: 5_000,
        },
      );

      clearSetup(state);
      return null;
    }

    const entryAsc = await getCandles(symbol, ENTRY_INTERVAL, LOOKBACK_BARS + 32);
    const entrySeries = toSeries(entryAsc);

    const structure = checkStructureBreak(state.setupDir, entrySeries);
    if (!structure) {
      return null;
    }

    const tradingGuard = await checkTradingGuard(when);
    if (tradingGuard.blocked) {
      await appendAnnotation(
        {
          type: "entry_blocked",
          strategyName: StrategyName.Single2PortV1,
          symbol,
          when: when.toISOString(),
          reason: tradingGuard.reason,
          detail: tradingGuard.detail || "",
        },
        {
          dedupeKey: `single2:entry_blocked:${symbol}:${tradingGuard.reason}`,
          dedupeMs: 60_000,
        },
      );
      return null;
    }

    clearSetup(state);

    await appendAnnotation(
      {
        type: "structure_break",
        strategyName: StrategyName.Single2PortV1,
        symbol,
        when: when.toISOString(),
        dir: structure.position === "long" ? "BUY" : "SELL",
        mode: structure.structure,
      },
      {
        dedupeKey: `single2:structure_break:${symbol}:${structure.structure}`,
        dedupeMs: 15_000,
      },
    );

    return {
      position: structure.position,
      note: [
        "S2",
        `mode=${structure.structure}`,
        `scalpTp=${structure.scalpTakeProfit}`,
        `swingTp=${structure.swingTakeProfit}`,
        `trailDist=${structure.swingTrailDistance}`,
      ].join("|"),
      priceStopLoss: structure.priceStopLoss,
      priceTakeProfit: structure.swingTakeProfit,
      minuteEstimatedTime: 720,
    };
  },
});
