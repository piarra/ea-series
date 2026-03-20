#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const { existsSync } = require("node:fs");
const path = require("node:path");

const ROOT_DIR = path.resolve(__dirname, "..");
const SOURCE_FILE = process.env.MQ5_SOURCE || path.join(ROOT_DIR, "DCA2.mq5");
const SSH_HOST = process.env.SSH_HOST || "vbox-win";
const REMOTE_TEMP_FILE = process.env.REMOTE_TEMP_FILE || path.basename(SOURCE_FILE);

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

function assertFileExists(filePath) {
  if (!existsSync(filePath)) {
    throw new Error(`Source file not found: ${filePath}`);
  }
}

function toSingleLine(value) {
  return value.replace(/\r/g, "").split("\n")[0].trim();
}

function main() {
  assertFileExists(SOURCE_FILE);
  const fileName = path.basename(SOURCE_FILE);
  const baseName = path.parse(fileName).name;
  const remoteOutputFile = process.env.REMOTE_OUTPUT_FILE || `${baseName}.ex5`;
  const localOutputFile =
    process.env.LOCAL_OUTPUT_FILE || path.join(ROOT_DIR, `${baseName}.ex5`);

  console.log(`[1/8] Checking SSH connectivity to ${SSH_HOST}`);
  ssh("cmd /c echo connected", "SSH connectivity check");

  console.log("[2/8] Locating MetaEditor");
  const metaEditorPath = toSingleLine(
    powershell(
      "$candidates=@('C:\\Program Files\\MetaTrader 5\\MetaEditor64.exe','C:\\Program Files\\MetaTrader 5\\MetaEditor.exe','C:\\Program Files (x86)\\MetaTrader 5\\MetaEditor.exe');$found=$candidates|Where-Object{Test-Path $_}|Select-Object -First 1;if(-not $found){$found=Get-ChildItem 'C:\\Program Files','C:\\Program Files (x86)' -Recurse -Filter 'MetaEditor*.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1};if(-not $found){Write-Error 'MetaEditor not found'; exit 1};Write-Output $found",
      "MetaEditor discovery"
    )
  );
  console.log(`MetaEditor: ${metaEditorPath}`);

  console.log("[3/8] Locating MQL5 Experts directory");
  const expertsDir = toSingleLine(
    powershell(
      "$root=Join-Path $env:APPDATA 'MetaQuotes\\Terminal';$target=Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'MQL5\\Experts' } | Where-Object { Test-Path $_ } | Select-Object -First 1;if(-not $target){Write-Error 'MQL5 Experts directory not found'; exit 1};Write-Output $target",
      "Experts directory discovery"
    )
  );
  console.log(`Experts dir: ${expertsDir}`);

  console.log("[4/8] Uploading MQ5 via SCP");
  runChecked("scp", [SOURCE_FILE, `${SSH_HOST}:${REMOTE_TEMP_FILE}`], "SCP upload");

  const remoteMq5 = `${expertsDir}\\${fileName}`;
  const remoteEx5 = `${expertsDir}\\${baseName}.ex5`;

  console.log("[5/8] Copying uploaded file into Experts");
  powershell(
    `$src=Join-Path $env:USERPROFILE '${REMOTE_TEMP_FILE}';Copy-Item -Path $src -Destination '${remoteMq5}' -Force;Write-Output 'copied'`,
    "Copy into Experts"
  );

  console.log("[6/8] Compiling in MetaEditor");
  const logPath = toSingleLine(
    powershell(
      `$log=Join-Path $env:TEMP 'compile-${baseName}.log';Write-Output $log`,
      "Compile log path discovery"
    )
  );
  ssh(
    `cmd /c ""${metaEditorPath}" /compile:"${remoteMq5}" /log:"${logPath}" & echo EXIT:%errorlevel%"`,
    "MetaEditor compile"
  );

  console.log("[7/8] Verifying build result");
  const resultLine = toSingleLine(
    powershell(
      `(Get-Content -Path '${logPath}' | Select-String -Pattern 'Result:' | Select-Object -First 1).Line`,
      "Result line extraction"
    )
  );
  console.log(resultLine);

  const match = resultLine.match(/Result:\s*(\d+)\s+errors,\s*(\d+)\s+warnings/i);
  if (!match) {
    throw new Error(`Could not parse compile result: ${resultLine}`);
  }
  if (Number(match[1]) > 0) {
    throw new Error(`Compile failed: ${resultLine}`);
  }

  const ex5Bytes = Number(
    toSingleLine(
      powershell(
        `if(Test-Path '${remoteEx5}'){(Get-Item '${remoteEx5}').Length}else{Write-Error 'EX5 not found'; exit 1}`,
        "EX5 existence check"
      )
    )
  );

  if (!Number.isFinite(ex5Bytes) || ex5Bytes <= 0) {
    throw new Error(`Invalid EX5 size: ${ex5Bytes}`);
  }

  console.log("[8/8] Downloading EX5 back to local");
  powershell(
    `$src='${remoteEx5}';$dst=Join-Path $env:USERPROFILE '${remoteOutputFile}';Copy-Item -Path $src -Destination $dst -Force;Write-Output $dst`,
    "Prepare EX5 for SCP download"
  );
  runChecked(
    "scp",
    [`${SSH_HOST}:${remoteOutputFile}`, localOutputFile],
    "SCP download EX5"
  );

  console.log(`Build succeeded: ${remoteEx5} (${ex5Bytes} bytes)`);
  console.log(`Downloaded to local: ${localOutputFile}`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
