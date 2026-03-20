#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const { mkdirSync, readFileSync, writeFileSync } = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT_DIR = path.resolve(__dirname, "..");
const SSH_HOST = process.env.SSH_HOST || "vbox-win";
const SOURCE_FILE = process.env.MQ5_SOURCE || path.join(ROOT_DIR, "DCA2.mq5");
const EA_NAME = path.parse(path.basename(SOURCE_FILE)).name;

const FROM_DATE = process.env.BT_FROM || "2026.01.01";
const TO_DATE = process.env.BT_TO || "2026.01.31";
const PERIOD = process.env.BT_PERIOD || "M4";
const MODEL = process.env.BT_MODEL || "0";
const DEPOSIT = process.env.BT_DEPOSIT || "10000";
const CURRENCY = process.env.BT_CURRENCY || "USD";
const LEVERAGE = process.env.BT_LEVERAGE || "100";
const TIMEOUT_MS = Number(process.env.BT_TIMEOUT_MS || "1800000");
const LOG_RETENTION_DAYS = Number(process.env.BT_LOG_RETENTION_DAYS || "7");

function runChecked(command, args, label) {
  const result = spawnSync(command, args, { encoding: "utf8" });

  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);

  if (result.error) {
    throw new Error(`${label} failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`${label} failed with exit code ${result.status}`);
  }

  return (result.stdout || "").trim();
}

function ssh(remoteCommand, label) {
  return runChecked("ssh", [SSH_HOST, remoteCommand], label);
}

function powershell(script, label) {
  return ssh(`powershell -NoProfile -Command "${script}"`, label);
}

function normalizeLines(text) {
  return text
    .replace(/\r/g, "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function toSingleLine(value) {
  return normalizeLines(value)[0] || "";
}

function psQuote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function detectSourceSymbol(filePath) {
  const content = readFileSync(filePath, "utf8");
  const match = content.match(/input\s+string\s+InpSymbol\s*=\s*"([^"]+)"/);
  return match ? match[1] : "";
}

function buildSymbolCandidates() {
  if (process.env.BT_SYMBOL) {
    return [process.env.BT_SYMBOL];
  }

  const fromSource = detectSourceSymbol(SOURCE_FILE) || "XAUUSD";
  const candidates = [fromSource];
  const suffixTrim = fromSource.match(/^([A-Z]{6,})([a-z0-9]{1,4})$/);
  if (suffixTrim) {
    candidates.push(suffixTrim[1]);
  }
  candidates.push("XAUUSD", "GOLD");

  return [...new Set(candidates)];
}

function uploadTextFile(localName, text) {
  const localPath = path.join(os.tmpdir(), localName);
  writeFileSync(localPath, text, "utf8");
  runChecked("scp", [localPath, `${SSH_HOST}:${localName}`], `Upload ${localName}`);
}

function symbolSlug(symbol) {
  return symbol.replace(/[^A-Za-z0-9_-]/g, "_");
}

function collectTesterEvidence(terminalDataDir, symbol) {
  const raw = powershell(
    `$dir=${psQuote(
      `${terminalDataDir}\\Tester\\logs`
    )};$sym=[Regex]::Escape(${psQuote(
      symbol
    )});$log=Get-ChildItem -Path $dir -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1;if($log){Write-Output ('TESTER_LOG:'+ $log.FullName);$tail=Get-Content -Path $log.FullName -Tail 700;$missing=$tail | Select-String -Pattern ('symbol ' + $sym + ' (does not exist|not exist)') | Select-Object -Last 1;if($missing){Write-Output ('TESTER_MISSING:' + $missing.Line)};$summary=$tail | Select-String -Pattern ('final balance|' + $sym + ',M[0-9]+: .*Test passed in|' + $sym + ',M[0-9]+: total time from login to stop testing|last test passed') | Select-Object -Last 3;$summary | ForEach-Object { 'TESTER_SUMMARY:' + $_.Line }}`,
    "Collect tester evidence"
  );

  const lines = normalizeLines(raw);
  const logPathLine = lines.find((line) => line.startsWith("TESTER_LOG:")) || "";
  const logPath = logPathLine.replace(/^TESTER_LOG:/, "");
  const missingLine = (
    lines.find((line) => line.startsWith("TESTER_MISSING:")) || ""
  ).replace(/^TESTER_MISSING:/, "");
  const summaryLines = lines
    .filter((line) => line.startsWith("TESTER_SUMMARY:"))
    .map((line) => line.replace(/^TESTER_SUMMARY:/, ""));

  return { logPath, missingLine, summaryLines };
}

function cleanupOldWindowsLogs(terminalDataDir) {
  const retentionDays = Number.isFinite(LOG_RETENTION_DAYS) ? LOG_RETENTION_DAYS : 7;
  const script =
    `$days=${retentionDays};` +
    `$cutoff=(Get-Date).AddDays(-$days);` +
    `$removed=0;` +
    `$dirs=@(` +
    `${psQuote(`${terminalDataDir}\\Logs`)},` +
    `${psQuote(`${terminalDataDir}\\Tester\\logs`)},` +
    `${psQuote(`${terminalDataDir}\\MQL5\\Logs`)}` +
    `);` +
    `foreach($d in $dirs){` +
    ` if(Test-Path $d){` +
    `  $files=Get-ChildItem -Path $d -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff };` +
    `  if($files){ $files | Remove-Item -Force -ErrorAction SilentlyContinue; $removed += @($files).Count }` +
    ` }` +
    `};` +
    `$testerRoot=Join-Path $env:APPDATA 'MetaQuotes\\Tester';` +
    `if(Test-Path $testerRoot){` +
    ` $logDirs=Get-ChildItem -Path $testerRoot -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'logs' };` +
    ` foreach($ld in $logDirs){` +
    `  $files=Get-ChildItem -Path $ld.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff };` +
    `  if($files){ $files | Remove-Item -Force -ErrorAction SilentlyContinue; $removed += @($files).Count }` +
    ` }` +
    `};` +
    `Write-Output ('LOG_CLEANUP_REMOVED:' + $removed)`;

  const output = powershell(script, "Cleanup old Windows logs");
  const line = normalizeLines(output).find((v) => v.startsWith("LOG_CLEANUP_REMOVED:")) || "";
  return line.replace("LOG_CLEANUP_REMOVED:", "").trim() || "0";
}

function main() {
  console.log("[1/6] Building EA before backtest");
  runChecked("node", [path.join(ROOT_DIR, "scripts", "build-mt5.js")], "Pre-backtest build");

  console.log("[2/6] Discovering MT5 paths");
  const terminalPath = toSingleLine(
    powershell(
      "$candidates=@('C:\\Program Files\\MetaTrader 5\\terminal64.exe','C:\\Program Files\\MetaTrader 5\\terminal.exe','C:\\Program Files (x86)\\MetaTrader 5\\terminal.exe');$found=$candidates|Where-Object{Test-Path $_}|Select-Object -First 1;if(-not $found){$found=Get-ChildItem 'C:\\Program Files','C:\\Program Files (x86)' -Recurse -Filter 'terminal*.exe' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^terminal(64)?\\.exe$' } | Select-Object -ExpandProperty FullName -First 1};if(-not $found){Write-Error 'terminal.exe not found'; exit 1};Write-Output $found",
      "Terminal discovery"
    )
  );
  const expertsDir = toSingleLine(
    powershell(
      "$root=Join-Path $env:APPDATA 'MetaQuotes\\Terminal';$target=Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'MQL5\\Experts' } | Where-Object { Test-Path $_ } | Select-Object -First 1;if(-not $target){Write-Error 'MQL5 Experts directory not found'; exit 1};Write-Output $target",
      "Experts dir discovery"
    )
  );
  const userProfile = toSingleLine(
    powershell("[Environment]::GetFolderPath('UserProfile')", "User profile discovery")
  );
  const terminalDataDir = expertsDir.replace(/\\MQL5\\Experts$/i, "");
  const remoteEx5 = `${expertsDir}\\${EA_NAME}.ex5`;
  powershell(
    `if(-not (Test-Path ${psQuote(remoteEx5)})){Write-Error 'EX5 not found'; exit 1};Write-Output 'ex5-ok'`,
    "Remote EX5 check"
  );
  console.log(`Terminal: ${terminalPath}`);
  console.log(`Experts : ${expertsDir}`);

  console.log("[3/6] Preparing symbol candidates");
  const candidates = buildSymbolCandidates();
  console.log(`Candidates: ${candidates.join(", ")}`);

  let selectedSymbol = "";
  let selectedReportPrefix = "";
  let reportNames = [];
  let selectedSummaryLines = [];
  const failures = [];

  console.log("[4/6] Running MT5 backtest");
  for (const symbol of candidates) {
    const slug = symbolSlug(symbol);
    const reportPrefix = `${EA_NAME}-backtest-20260101-20260131-${slug}`;
    const remoteConfigName = `${EA_NAME}-backtest-${slug}.ini`;
    const remoteSetName = `${EA_NAME}-backtest-${slug}.set`;
    const remoteConfigPath = `${userProfile}\\${remoteConfigName}`;
    const remoteSetProfilePath = `${terminalDataDir}\\MQL5\\Profiles\\Tester\\${remoteSetName}`;
    const remoteReportBase = `${userProfile}\\${reportPrefix}`;

    console.log(`Trying symbol: ${symbol}`);
    powershell(
      `$f=Get-ChildItem -Path ${psQuote(
        userProfile
      )} -Filter ${psQuote(reportPrefix + "*")} -File -ErrorAction SilentlyContinue;if($f){$f|Remove-Item -Force -ErrorAction SilentlyContinue}`,
      `Cleanup old reports (${symbol})`
    );

    uploadTextFile(remoteSetName, `InpSymbol=${symbol}\r\n`);
    powershell(
      `New-Item -Path ${psQuote(
        `${terminalDataDir}\\MQL5\\Profiles\\Tester`
      )} -ItemType Directory -Force | Out-Null;Copy-Item -Path ${psQuote(
        `${userProfile}\\${remoteSetName}`
      )} -Destination ${psQuote(remoteSetProfilePath)} -Force`,
      `Stage tester set file (${symbol})`
    );
    const ini = [
      "[Tester]",
      `Expert=${EA_NAME}.ex5`,
      `ExpertParameters=${remoteSetName}`,
      `Symbol=${symbol}`,
      `Period=${PERIOD}`,
      `Model=${MODEL}`,
      "ExecutionMode=0",
      "Optimization=0",
      `FromDate=${FROM_DATE}`,
      `ToDate=${TO_DATE}`,
      "ForwardMode=0",
      `Deposit=${DEPOSIT}`,
      `Currency=${CURRENCY}`,
      `Leverage=${LEVERAGE}`,
      `Report=${remoteReportBase}`,
      "ReplaceReport=1",
      "ShutdownTerminal=1",
      "Visual=0",
      ""
    ].join("\r\n");
    uploadTextFile(remoteConfigName, ini);

    const runOutput = powershell(
      `$args='/config:${remoteConfigPath}';$p=Start-Process -FilePath ${psQuote(
        terminalPath
      )} -ArgumentList $args -PassThru;$ok=$p.WaitForExit(${TIMEOUT_MS});if(-not $ok){Stop-Process -Id $p.Id -Force;Write-Error 'Backtest timed out'; exit 1};Write-Output ('TERMINAL_EXIT:'+ $p.ExitCode)`,
      `Run backtest (${symbol})`
    );
    const exitLine = normalizeLines(runOutput).find((line) =>
      line.startsWith("TERMINAL_EXIT:")
    );
    const exitCode = exitLine ? Number(exitLine.split(":")[1]) : NaN;

    const reportListRaw = powershell(
      `$files=Get-ChildItem -Path ${psQuote(
        userProfile
      )} -Filter ${psQuote(reportPrefix + "*")} -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime; if($files){$files | Select-Object -ExpandProperty Name}`,
      `Report discovery (${symbol})`
    );
    const names = normalizeLines(reportListRaw);
    const evidence = collectTesterEvidence(terminalDataDir, symbol);
    const summaryLines = evidence.summaryLines;
    const symbolMissing = Boolean(evidence.missingLine);
    const successByLog = Number.isFinite(exitCode) && exitCode === 0 && summaryLines.length > 0;

    if (names.length > 0 || successByLog) {
      selectedSymbol = symbol;
      selectedReportPrefix = reportPrefix;
      reportNames = names;
      selectedSummaryLines = summaryLines;
      if (!Number.isFinite(exitCode) || exitCode !== 0) {
        console.log(`Warning: terminal exit code is ${exitCode}, but reports were generated.`);
      }
      break;
    }

    const reason = evidence.missingLine || "";
    failures.push(
      `${symbol}: exit=${Number.isFinite(exitCode) ? exitCode : "N/A"}${
        reason ? `, reason=${reason}` : ""
      }`
    );
    if (symbolMissing) {
      console.log(`Symbol not available on server: ${symbol}`);
      continue;
    }
    throw new Error(`Backtest failed for ${symbol}. ${failures[failures.length - 1]}`);
  }

  if (!selectedSymbol) {
    throw new Error(
      `No symbol candidate succeeded.\n${failures.map((line) => ` - ${line}`).join("\n")}`
    );
  }

  console.log("[5/6] Downloading backtest artifacts to local");
  const localResultDir = path.join(ROOT_DIR, "backtest-results");
  mkdirSync(localResultDir, { recursive: true });
  for (const reportName of reportNames) {
    runChecked(
      "scp",
      [`${SSH_HOST}:${reportName}`, path.join(localResultDir, reportName)],
      `Download report ${reportName}`
    );
  }
  const summaryFile = path.join(localResultDir, `${selectedReportPrefix}-summary.txt`);
  const summaryText = [
    `symbol=${selectedSymbol}`,
    `from=${FROM_DATE}`,
    `to=${TO_DATE}`,
    ...selectedSummaryLines
  ].join("\n");
  writeFileSync(summaryFile, summaryText + "\n", "utf8");

  console.log("[6/6] Cleaning old Windows logs");
  const removedCount = cleanupOldWindowsLogs(terminalDataDir);

  console.log("[7/7] Completed");
  console.log(`Range: ${FROM_DATE} -> ${TO_DATE}`);
  console.log(`Symbol: ${selectedSymbol}`);
  console.log(`Report prefix: ${selectedReportPrefix}`);
  console.log(`Removed old logs on Windows: ${removedCount} (retention ${LOG_RETENTION_DAYS} days)`);
  console.log(`Local artifacts: ${localResultDir}`);
  if (reportNames.length > 0) {
    reportNames.forEach((name) => console.log(` - ${path.join(localResultDir, name)}`));
  } else {
    console.log(" - report file not found; used tester log summary instead");
  }
  console.log(` - ${summaryFile}`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
