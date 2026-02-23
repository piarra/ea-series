import { addActionSchema } from "backtest-kit";
import ActionName from "../../enum/ActionName.mjs";
import { BacktestPartialProfitTakingAction } from "../../classes/BacktestPartialProfitTakingAction.mjs";

addActionSchema({
  actionName: ActionName.BacktestPartialProfitTakingAction,
  handler: BacktestPartialProfitTakingAction,
  note: "Scale out at Kelly-optimized levels (33%, 33%, 34%)",
});
