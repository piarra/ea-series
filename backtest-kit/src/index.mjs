import "dotenv/config";

import "./config/setup.mjs";
import "./logic/index.mjs";

import { listenError } from "backtest-kit";
import { validateSchemas } from "./config/validate.mjs";
import { main } from "./main/bootstrap.mjs";

listenError((error) => {
  const message = error instanceof Error ? error.stack || error.message : String(error);
  console.error(message);
});

await validateSchemas();
await main();
