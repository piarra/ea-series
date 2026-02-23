import { addActionSchema } from "backtest-kit";
import ActionName from "../../enum/ActionName.mjs";
import { BacktestPositionMonitorAction } from "../../classes/BacktestPositionMonitorAction.mjs";

addActionSchema({
  actionName: ActionName.BacktestPositionMonitorAction,
  handler: BacktestPositionMonitorAction,
  note: "Monitors and logs position lifecycle events (open/close/scheduled)",
});
