#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const rootDir = path.resolve(__dirname, "..", "..");
const sharedBuildScript = path.join(rootDir, "scripts", "build-mt5.js");
const defaultSource = path.join(__dirname, "..", "DCA2.mq5");

const args = [sharedBuildScript, ...process.argv.slice(2)];
const hasSourceArg = process.argv.slice(2).some((arg) => /^--source(?:=|$)/.test(arg));
if (!process.env.MQ5_SOURCE && !hasSourceArg) {
  args.push("--source", defaultSource);
}

const result = spawnSync("node", args, { stdio: "inherit" });
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 1);
