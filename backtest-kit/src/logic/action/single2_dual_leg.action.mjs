import { addActionSchema } from "backtest-kit";
import ActionName from "../../enum/ActionName.mjs";
import { Single2DualLegAction } from "../../classes/Single2DualLegAction.mjs";

addActionSchema({
  actionName: ActionName.Single2DualLegAction,
  handler: Single2DualLegAction,
  note: "Pseudo dual-entry manager for SINGLE2: scalp partial + swing trailing",
});
