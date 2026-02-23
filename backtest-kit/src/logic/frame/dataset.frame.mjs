import { addFrameSchema } from "backtest-kit";
import {
  BACKTEST_FRAME_END,
  BACKTEST_FRAME_START,
} from "../../config/params.mjs";
import FrameName from "../../enum/FrameName.mjs";

addFrameSchema({
  frameName: FrameName.DatasetWindow,
  interval: "1m",
  startDate: BACKTEST_FRAME_START,
  endDate: BACKTEST_FRAME_END,
  note: "Frame generated from BACKTEST_FRAME_START/BACKTEST_FRAME_END",
});

addFrameSchema({
  frameName: FrameName.January2025,
  interval: "1m",
  startDate: new Date("2025-01-01T00:00:00Z"),
  endDate: new Date("2025-01-31T23:59:00Z"),
  note: "Reference frame for XAUUSD January 2025",
});

addFrameSchema({
  frameName: FrameName.February2025,
  interval: "1m",
  startDate: new Date("2025-02-01T00:00:00Z"),
  endDate: new Date("2025-02-28T23:59:00Z"),
  note: "Reference frame for XAUUSD February 2025",
});
