import { getArgs } from "../utils/getArgs.mjs";
import { runBacktestJob } from "../runtime/backtest-manager.mjs";
import { startControlServer } from "../server/control-server.mjs";

export const main = async () => {
  const args = getArgs();

  if (args.ui) {
    startControlServer({
      host: args.host,
      port: args.port,
    });
    return;
  }

  if (args.paper) {
    throw new Error("Paper mode is not implemented yet.");
  }

  if (args.live) {
    throw new Error("Live mode is not implemented yet.");
  }

  if (!args.backtest) {
    throw new Error("Please specify --backtest or --ui");
  }

  await runBacktestJob({
    symbol: args.symbol,
    strategyName: args.strategyName,
    frameName: args.frameName,
    exchangeName: args.exchangeName,
    execution: "run",
  });

  process.exit(0);
};
