import { addRiskSchema } from "backtest-kit";
import RiskName from "../../enum/RiskName.mjs";

const MIN_DISTANCE_RATIO = 0.0002;

addRiskSchema({
  riskName: RiskName.MinDistanceRisk,
  validations: [
    {
      note: "Reject signals whose SL/TP distance is too tight for XAUUSD spread and slippage.",
      validate: ({ currentSignal, currentPrice }) => {
        const open = currentSignal.priceOpen || currentPrice;
        if (!Number.isFinite(open) || open <= 0) {
          return;
        }

        const slDistance = Math.abs(open - currentSignal.priceStopLoss) / open;
        const tpDistance = Math.abs(currentSignal.priceTakeProfit - open) / open;

        if (slDistance < MIN_DISTANCE_RATIO) {
          throw new Error(`SL distance is too small: ${slDistance}`);
        }

        if (tpDistance < MIN_DISTANCE_RATIO) {
          throw new Error(`TP distance is too small: ${tpDistance}`);
        }

        if (currentSignal.minuteEstimatedTime < 5) {
          throw new Error("minuteEstimatedTime must be >= 5");
        }
      },
    },
  ],
});
