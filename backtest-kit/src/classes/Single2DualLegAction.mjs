import {
  ActionBase,
  commitPartialProfit,
  commitTrailingStop,
  getAveragePrice,
} from "backtest-kit";
import {
  SIMPLE2_MIN_RR,
  SINGLE2_SWING_TRAIL_DISTANCE_RATIO,
} from "../config/params.mjs";
import { appendAnnotation } from "../runtime/annotation-store.mjs";

const stateBySignalId = new Map();

const toFinite = (value, fallback = Number.NaN) => {
  const parsed = Number.parseFloat(String(value ?? ""));
  return Number.isFinite(parsed) ? parsed : fallback;
};

const parseMetaNote = (note) => {
  const result = {};

  if (typeof note !== "string" || note.length === 0) {
    return result;
  }

  for (const token of note.split("|")) {
    const [key, value] = token.split("=");
    if (!key || value === undefined) {
      continue;
    }

    result[key.trim()] = value.trim();
  }

  return result;
};

const createSignalState = (signal) => {
  const meta = parseMetaNote(signal.note || "");

  const entry = toFinite(signal.priceOpen);
  const originalStop = toFinite(signal.originalPriceStopLoss, signal.priceStopLoss);
  const originalTake = toFinite(signal.originalPriceTakeProfit, signal.priceTakeProfit);

  if (!Number.isFinite(entry) || !Number.isFinite(originalStop)) {
    return null;
  }

  const risk = Math.abs(entry - originalStop);

  const fallbackScalpTp =
    signal.position === "long"
      ? entry + risk * SIMPLE2_MIN_RR
      : entry - risk * SIMPLE2_MIN_RR;

  const scalpTp = toFinite(meta.scalpTp, fallbackScalpTp);

  const fallbackTrailDistance =
    Math.abs(scalpTp - entry) * SINGLE2_SWING_TRAIL_DISTANCE_RATIO;

  const trailDistance = toFinite(meta.trailDist, fallbackTrailDistance);

  return {
    signalId: signal.id,
    symbol: signal.symbol,
    position: signal.position,
    entry,
    originalStop,
    originalTake,
    scalpTp,
    trailDistance,
    scalpClosed: false,
    trailingArmed: false,
    lastTrailShift: Number.NaN,
  };
};

const reachedScalpTarget = (state, currentPrice) => {
  if (state.position === "long") {
    return currentPrice >= state.scalpTp;
  }

  return currentPrice <= state.scalpTp;
};

const calcDistancePercent = (entry, stop, position) => {
  if (position === "long") {
    return ((entry - stop) / entry) * 100;
  }

  return ((stop - entry) / entry) * 100;
};

const calcTargetStop = (state, currentPrice) => {
  if (state.position === "long") {
    return currentPrice - state.trailDistance;
  }

  return currentPrice + state.trailDistance;
};

/**
 * SINGLE2 pseudo dual-leg manager.
 * 1) Close 50% at SCALP TP.
 * 2) Trail remaining leg with fixed swing distance.
 * @implements {bt.IPublicAction}
 */
export class Single2DualLegAction extends ActionBase {
  async signalBacktest(event) {
    if (event.action === "opened") {
      const state = createSignalState(event.signal);
      if (!state) {
        return;
      }

      stateBySignalId.set(event.signal.id, state);

      await appendAnnotation(
        {
          type: "dual_leg_opened",
          strategyName: event.strategyName,
          symbol: event.symbol,
          signalId: event.signal.id,
          position: state.position,
          scalpTp: state.scalpTp,
          swingTp: state.originalTake,
          trailDistance: state.trailDistance,
          createdAt: event.createdAt,
        },
        {
          dedupeKey: `single2:dual_opened:${event.signal.id}`,
          dedupeMs: 10_000,
        },
      );
      return;
    }

    if (event.action === "closed" || event.action === "cancelled") {
      if (event.signal?.id) {
        stateBySignalId.delete(event.signal.id);
      }
    }
  }

  async pingActive(event) {
    const signal = event.data;
    if (!signal?.id) {
      return;
    }

    let state = stateBySignalId.get(signal.id);

    if (!state) {
      state = createSignalState(signal);
      if (!state) {
        return;
      }
      stateBySignalId.set(signal.id, state);
    }

    const currentPrice = await getAveragePrice(event.symbol);
    if (!Number.isFinite(currentPrice)) {
      return;
    }

    if (!state.scalpClosed && reachedScalpTarget(state, currentPrice)) {
      const partialOk = await commitPartialProfit(event.symbol, 50);

      if (partialOk) {
        state.scalpClosed = true;
        state.trailingArmed = true;

        await appendAnnotation(
          {
            type: "dual_scalp_closed",
            strategyName: event.strategyName,
            symbol: event.symbol,
            signalId: signal.id,
            currentPrice,
            scalpTp: state.scalpTp,
            timestamp: event.timestamp,
          },
          {
            dedupeKey: `single2:dual_scalp_closed:${signal.id}`,
            dedupeMs: 60_000,
          },
        );
      }
    }

    if (!state.trailingArmed) {
      return;
    }

    const targetStop = calcTargetStop(state, currentPrice);

    const originalDistancePercent = calcDistancePercent(
      state.entry,
      state.originalStop,
      state.position,
    );

    const targetDistancePercent = calcDistancePercent(
      state.entry,
      targetStop,
      state.position,
    );

    let percentShift = targetDistancePercent - originalDistancePercent;

    if (!Number.isFinite(percentShift)) {
      return;
    }

    percentShift = Math.max(-99.9, Math.min(99.9, percentShift));

    if (Math.abs(percentShift) < 0.05) {
      return;
    }

    if (
      Number.isFinite(state.lastTrailShift) &&
      Math.abs(percentShift - state.lastTrailShift) < 0.05
    ) {
      return;
    }

    const trailingOk = await commitTrailingStop(
      event.symbol,
      percentShift,
      currentPrice,
    );

    if (!trailingOk) {
      return;
    }

    state.lastTrailShift = percentShift;

    await appendAnnotation(
      {
        type: "dual_swing_trailing",
        strategyName: event.strategyName,
        symbol: event.symbol,
        signalId: signal.id,
        currentPrice,
        targetStop,
        percentShift,
        timestamp: event.timestamp,
      },
      {
        dedupeKey: `single2:dual_trailing:${signal.id}`,
        dedupeMs: 5_000,
      },
    );
  }
}

export default Single2DualLegAction;
