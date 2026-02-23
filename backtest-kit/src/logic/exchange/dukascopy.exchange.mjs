import { addExchangeSchema, roundTicks } from "backtest-kit";
import {
  DUKASCOPY_DATA_PATH,
  DUKASCOPY_DEFAULT_SPREAD,
} from "../../config/params.mjs";
import ExchangeName from "../../enum/ExchangeName.mjs";
import { loadDukascopyCandles } from "../../data/dukascopy/loader.mjs";

addExchangeSchema({
  exchangeName: ExchangeName.DukascopyExchange,
  note: "Dukascopy CSV/CSV.GZ adapter for XAUUSD backtests",
  getCandles: async (symbol, interval, since, limit) => {
    return await loadDukascopyCandles({
      symbol,
      interval,
      since,
      limit,
      dataPath: DUKASCOPY_DATA_PATH,
      defaultSpread: DUKASCOPY_DEFAULT_SPREAD,
    });
  },
  formatPrice: async (_symbol, price) => roundTicks(price, 0.01),
  formatQuantity: async (_symbol, quantity) => roundTicks(quantity, 0.01),
  getOrderBook: async (symbol) => ({
    symbol,
    bids: [],
    asks: [],
  }),
});
