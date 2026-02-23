import { addStrategySchema, getCandles } from "backtest-kit";
import {
  NM3_SL_MULTIPLIER,
  NM3_TP_MULTIPLIER,
} from "../../config/params.mjs";
import RiskName from "../../enum/RiskName.mjs";
import StrategyName from "../../enum/StrategyName.mjs";
import { appendAnnotation } from "../../runtime/annotation-store.mjs";
import { atr, closes, lastFinite, rsi } from "../shared/indicators.mjs";
import { evaluateRegime, RegimeState } from "../shared/regime.mjs";
import { checkTradingGuard } from "../shared/trading-guard.mjs";

addStrategySchema({
  strategyName: StrategyName.Nm3PortV1,
  interval: "1m",
  note: "Phase-1 JS port of NM3.mq5 (regime + blackout aware)",
  riskList: [RiskName.MinDistanceRisk],
  getSignal: async (symbol, when) => {
    const candles = await getCandles(symbol, "1m", 240);
    if (candles.length < 120) {
      return null;
    }

    const currentPrice = candles[candles.length - 1]?.close;
    if (!Number.isFinite(currentPrice)) {
      return null;
    }

    const tradingGuard = await checkTradingGuard(when);
    if (tradingGuard.blocked) {
      await appendAnnotation(
        {
          type: "blackout",
          strategyName: StrategyName.Nm3PortV1,
          symbol,
          when: when.toISOString(),
          reason: tradingGuard.reason,
          detail: tradingGuard.detail || "",
        },
        {
          dedupeKey: `nm3:blackout:${tradingGuard.reason}:${symbol}`,
          dedupeMs: 60_000,
        },
      );
      return null;
    }

    const regime = evaluateRegime({
      key: `${StrategyName.Nm3PortV1}:${symbol}`,
      candles,
      when,
      interval: "1m",
    });

    if (regime.changed) {
      await appendAnnotation({
        type: "regime",
        strategyName: StrategyName.Nm3PortV1,
        symbol,
        when: when.toISOString(),
        regime: regime.rawRegime,
        score: regime.score,
      });
    }

    if (regime.regime === RegimeState.Cooling) {
      return null;
    }

    const closeList = closes(candles);
    const rsiList = rsi(closeList, 14);
    const atrList = atr(candles, 14);

    const rsiNow = lastFinite(rsiList);
    const atrNow = lastFinite(atrList);

    if (!Number.isFinite(rsiNow) || !Number.isFinite(atrNow)) {
      return null;
    }

    let position = null;

    if (regime.rawRegime === RegimeState.TrendUp) {
      if (rsiNow <= 45) {
        position = "long";
      }
    } else if (regime.rawRegime === RegimeState.TrendDown) {
      if (rsiNow >= 55) {
        position = "short";
      }
    } else if (rsiNow <= 30) {
      position = "long";
    } else if (rsiNow >= 70) {
      position = "short";
    }

    if (!position) {
      return null;
    }

    const minStopDistance = currentPrice * 0.006;
    const minTakeDistance = currentPrice * 0.008;
    const stopDistance = Math.max(minStopDistance, atrNow * NM3_SL_MULTIPLIER);
    const takeDistance = Math.max(minTakeDistance, stopDistance * NM3_TP_MULTIPLIER);

    const priceStopLoss =
      position === "long"
        ? currentPrice - stopDistance
        : currentPrice + stopDistance;

    const priceTakeProfit =
      position === "long"
        ? currentPrice + takeDistance
        : currentPrice - takeDistance;

    await appendAnnotation(
      {
        type: "signal_intent",
        strategyName: StrategyName.Nm3PortV1,
        symbol,
        when: when.toISOString(),
        position,
        regime: regime.rawRegime,
        rsi: Math.round(rsiNow * 100) / 100,
      },
      {
        dedupeKey: `nm3:intent:${symbol}:${position}`,
        dedupeMs: 15_000,
      },
    );

    return {
      position,
      note: `NM3 phase1 regime=${regime.rawRegime} rsi=${rsiNow.toFixed(2)}`,
      priceTakeProfit,
      priceStopLoss,
      minuteEstimatedTime: 240,
    };
  },
});
