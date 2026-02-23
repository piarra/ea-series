import { parseArgs } from "backtest-kit";
import { CONTROL_HOST, CONTROL_PORT, DEFAULT_SYMBOL } from "../config/params.mjs";
import ExchangeName from "../enum/ExchangeName.mjs";
import FrameName from "../enum/FrameName.mjs";
import StrategyName from "../enum/StrategyName.mjs";

let cachedArgs = null;

const argv = process.argv.slice(2);

const hasFlag = (name) => argv.includes(`--${name}`);

const readOption = (names, fallback = "") => {
  for (const name of names) {
    const index = argv.indexOf(`--${name}`);
    if (index >= 0 && index < argv.length - 1) {
      return argv[index + 1];
    }
  }
  return fallback;
};

const toInt = (value, fallback) => {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

export const getArgs = () => {
  if (cachedArgs) {
    return cachedArgs;
  }

  const parsed = parseArgs({
    exchangeName: ExchangeName.DukascopyExchange,
    strategyName: StrategyName.Nm3PortV1,
    frameName: FrameName.DatasetWindow,
    symbol: DEFAULT_SYMBOL,
  });

  const resolved = {
    ...parsed,
    symbol: readOption(["symbol"], parsed.symbol),
    strategyName: readOption(["strategy", "strategyName"], parsed.strategyName),
    exchangeName: readOption(["exchange", "exchangeName"], parsed.exchangeName),
    frameName: readOption(["frame", "frameName"], parsed.frameName),
    ui: hasFlag("ui"),
    host: readOption(["host"], CONTROL_HOST),
    port: toInt(readOption(["port"], String(CONTROL_PORT)), CONTROL_PORT),
  };

  if (!resolved.backtest && !resolved.paper && !resolved.live && !resolved.ui) {
    resolved.backtest = true;
  }

  cachedArgs = resolved;
  return resolved;
};
