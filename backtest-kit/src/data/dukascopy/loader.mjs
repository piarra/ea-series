import fs from "node:fs";
import fsPromises from "node:fs/promises";
import path from "node:path";
import readline from "node:readline";
import { createGunzip } from "node:zlib";

const INTERVAL_MS = {
  "1m": 60_000,
  "3m": 180_000,
  "5m": 300_000,
  "15m": 900_000,
  "30m": 1_800_000,
  "1h": 3_600_000,
  "2h": 7_200_000,
  "4h": 14_400_000,
  "6h": 21_600_000,
  "8h": 28_800_000,
  "12h": 43_200_000,
  "1d": 86_400_000,
  "3d": 259_200_000,
};

const SUPPORTED_SUFFIXES = [".csv", ".gz", ".csv.gz"];

const symbolIntervalCache = new Map();

const stripQuotes = (value) => value.replace(/^"|"$/g, "").trim();

const toNumber = (value) => {
  const normalized = stripQuotes(String(value ?? "")).replace(/,/g, "");
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
};

const parseTimestamp = (value) => {
  const raw = stripQuotes(String(value ?? ""));
  if (!raw) {
    return Number.NaN;
  }

  if (/^\d{13}$/.test(raw)) {
    return Number(raw);
  }

  if (/^\d{10}$/.test(raw)) {
    return Number(raw) * 1_000;
  }

  const normalized = raw
    .replace(/\//g, "-")
    .replace(/^(\d{4})\.(\d{2})\.(\d{2})/, "$1-$2-$3")
    .replace(" ", "T");

  const withZone = /Z$|[+-]\d{2}:?\d{2}$/.test(normalized)
    ? normalized
    : `${normalized}Z`;

  const parsed = Date.parse(withZone);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
};

const normalizeSymbol = (value) =>
  value
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");

const isSupportedFile = (filePath) => {
  const lower = filePath.toLowerCase();
  return SUPPORTED_SUFFIXES.some((suffix) => lower.endsWith(suffix));
};

const tokenizeCsv = (line) =>
  line
    .split(/[;,\t]/)
    .map(stripQuotes)
    .filter((value) => value.length > 0);

const parseHeaderMap = (columns) => {
  const lower = columns.map((column) => column.toLowerCase());
  const find = (pattern) => lower.findIndex((item) => pattern.test(item));

  const header = {
    timestamp: find(/time|date/),
    open: find(/^open$/),
    high: find(/^high$/),
    low: find(/^low$/),
    close: find(/^close$/),
    bid: find(/^bid$/),
    ask: find(/^ask$/),
    volume: find(/volume|tickvol|vol/),
    bidVolume: find(/bid\s*volume|bidvol/),
    askVolume: find(/ask\s*volume|askvol/),
  };

  if (header.timestamp < 0) {
    return null;
  }

  return header;
};

const createBucket = (timestamp) => ({
  timestamp,
  open: Number.NaN,
  high: Number.NEGATIVE_INFINITY,
  low: Number.POSITIVE_INFINITY,
  close: Number.NaN,
  volume: 0,
});

const mergePrice = (bucket, price, volume = 0) => {
  if (!Number.isFinite(price)) {
    return;
  }

  if (!Number.isFinite(bucket.open)) {
    bucket.open = price;
  }

  bucket.high = Math.max(bucket.high, price);
  bucket.low = Math.min(bucket.low, price);
  bucket.close = price;
  bucket.volume += Number.isFinite(volume) ? volume : 0;
};

const mergeOhlc = (bucket, row) => {
  if (!Number.isFinite(bucket.open)) {
    bucket.open = row.open;
  }

  bucket.high = Math.max(bucket.high, row.high, row.open, row.close);
  bucket.low = Math.min(bucket.low, row.low, row.open, row.close);
  bucket.close = row.close;
  bucket.volume += Number.isFinite(row.volume) ? row.volume : 0;
};

const parseTickRow = (columns, header, defaultSpread) => {
  const ts = parseTimestamp(columns[header.timestamp]);
  if (!Number.isFinite(ts)) {
    return null;
  }

  const bidIndex = header.bid >= 0 ? header.bid : 1;
  const askIndex = header.ask >= 0 ? header.ask : 2;

  const bid = toNumber(columns[bidIndex]);
  const ask = toNumber(columns[askIndex]);

  if (!Number.isFinite(bid) && !Number.isFinite(ask)) {
    return null;
  }

  const price = Number.isFinite(bid)
    ? Number.isFinite(ask)
      ? (bid + ask) / 2
      : bid + defaultSpread / 2
    : ask - defaultSpread / 2;

  let volume = 0;

  if (header.volume >= 0) {
    volume = toNumber(columns[header.volume]);
  } else {
    const bidVolume = header.bidVolume >= 0 ? toNumber(columns[header.bidVolume]) : 0;
    const askVolume = header.askVolume >= 0 ? toNumber(columns[header.askVolume]) : 0;
    volume = (Number.isFinite(bidVolume) ? bidVolume : 0) +
      (Number.isFinite(askVolume) ? askVolume : 0);
  }

  return {
    type: "tick",
    timestamp: ts,
    price,
    volume,
  };
};

const parseOhlcRow = (columns, header) => {
  const ts = parseTimestamp(columns[header.timestamp]);
  if (!Number.isFinite(ts)) {
    return null;
  }

  const open = toNumber(columns[header.open]);
  const high = toNumber(columns[header.high]);
  const low = toNumber(columns[header.low]);
  const close = toNumber(columns[header.close]);
  const volume = header.volume >= 0 ? toNumber(columns[header.volume]) : 0;

  if (![open, high, low, close].every(Number.isFinite)) {
    return null;
  }

  return {
    type: "ohlc",
    timestamp: ts,
    open,
    high,
    low,
    close,
    volume,
  };
};

const parseHeuristicRow = (columns, defaultSpread) => {
  const ts = parseTimestamp(columns[0]);
  if (!Number.isFinite(ts)) {
    return null;
  }

  if (columns.length >= 5) {
    const open = toNumber(columns[1]);
    const high = toNumber(columns[2]);
    const low = toNumber(columns[3]);
    const close = toNumber(columns[4]);

    const looksLikeOhlc = [open, high, low, close].every(Number.isFinite) &&
      high >= Math.max(open, close) &&
      low <= Math.min(open, close);

    if (looksLikeOhlc) {
      const volume = columns.length > 5 ? toNumber(columns[5]) : 0;
      return {
        type: "ohlc",
        timestamp: ts,
        open,
        high,
        low,
        close,
        volume,
      };
    }
  }

  const bid = toNumber(columns[1]);
  const ask = toNumber(columns[2]);

  if (!Number.isFinite(bid) && !Number.isFinite(ask)) {
    return null;
  }

  const price = Number.isFinite(bid)
    ? Number.isFinite(ask)
      ? (bid + ask) / 2
      : bid + defaultSpread / 2
    : ask - defaultSpread / 2;

  const volumeA = toNumber(columns[3]);
  const volumeB = toNumber(columns[4]);

  return {
    type: "tick",
    timestamp: ts,
    price,
    volume:
      (Number.isFinite(volumeA) ? volumeA : 0) +
      (Number.isFinite(volumeB) ? volumeB : 0),
  };
};

const lowerBoundByTimestamp = (candles, timestamp) => {
  let left = 0;
  let right = candles.length;

  while (left < right) {
    const mid = left + ((right - left) >> 1);
    if (candles[mid].timestamp < timestamp) {
      left = mid + 1;
    } else {
      right = mid;
    }
  }

  return left;
};

const sliceAlignedCandles = (candles, sinceMs, limit, intervalMs) => {
  if (limit <= 0 || candles.length === 0) {
    return [];
  }

  const aligned = [];
  const startIndex = lowerBoundByTimestamp(candles, sinceMs);

  let scanIndex = startIndex;
  let prevIndex = Math.max(0, startIndex - 1);
  let lastClose =
    candles[prevIndex] && candles[prevIndex].timestamp < sinceMs
      ? candles[prevIndex].close
      : Number.NaN;

  for (let offset = 0; offset < limit; offset += 1) {
    const targetTs = sinceMs + offset * intervalMs;

    while (scanIndex < candles.length && candles[scanIndex].timestamp < targetTs) {
      lastClose = candles[scanIndex].close;
      scanIndex += 1;
    }

    if (scanIndex < candles.length && candles[scanIndex].timestamp === targetTs) {
      const exact = candles[scanIndex];
      aligned.push(exact);
      lastClose = exact.close;
      scanIndex += 1;
      continue;
    }

    const seedPrice = Number.isFinite(lastClose)
      ? lastClose
      : scanIndex < candles.length
        ? candles[scanIndex].open
        : Number.NaN;

    if (!Number.isFinite(seedPrice)) {
      break;
    }

    aligned.push({
      timestamp: targetTs,
      open: seedPrice,
      high: seedPrice,
      low: seedPrice,
      close: seedPrice,
      volume: 0,
    });
  }

  return aligned;
};

const streamFileRows = async (filePath, onLine) => {
  const source = fs.createReadStream(filePath);
  const input = filePath.toLowerCase().endsWith(".gz")
    ? source.pipe(createGunzip())
    : source;

  const reader = readline.createInterface({
    input,
    crlfDelay: Number.POSITIVE_INFINITY,
  });

  try {
    for await (const line of reader) {
      await onLine(line);
    }
  } finally {
    reader.close();
    source.destroy();
  }
};

const walkFiles = async (rootPath) => {
  const stat = await fsPromises.stat(rootPath);

  if (stat.isFile()) {
    return isSupportedFile(rootPath) ? [rootPath] : [];
  }

  const queue = [rootPath];
  const files = [];

  while (queue.length > 0) {
    const current = queue.pop();
    if (!current) {
      continue;
    }

    const entries = await fsPromises.readdir(current, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        queue.push(fullPath);
        continue;
      }

      if (entry.isFile() && isSupportedFile(fullPath)) {
        files.push(fullPath);
      }
    }
  }

  files.sort();
  return files;
};

const filterFilesForSymbol = (files, symbol) => {
  const normalizedSymbol = normalizeSymbol(symbol);
  return files.filter((filePath) =>
    normalizeSymbol(path.basename(filePath)).includes(normalizedSymbol),
  );
};

const loadSymbolIntervalCandles = async ({
  symbol,
  interval,
  dataPath,
  defaultSpread,
}) => {
  const intervalMs = INTERVAL_MS[interval];

  if (!intervalMs) {
    throw new Error(`Unsupported interval: ${interval}`);
  }

  const allFiles = await walkFiles(dataPath);

  if (allFiles.length === 0) {
    throw new Error(`No Dukascopy CSV files found at: ${dataPath}`);
  }

  const files = filterFilesForSymbol(allFiles, symbol);
  if (files.length === 0) {
    throw new Error(
      `No Dukascopy CSV files matched symbol "${symbol}" at: ${dataPath}`,
    );
  }

  const buckets = new Map();

  for (const filePath of files) {
    const parserState = {
      header: null,
    };

    await streamFileRows(filePath, async (line) => {
      const trimmed = line.trim();
      if (!trimmed) {
        return;
      }

      const columns = tokenizeCsv(trimmed);
      if (columns.length < 2) {
        return;
      }

      if (!parserState.header) {
        const guessedHeader = parseHeaderMap(columns);
        const containsLetters = columns.some((column) => /[A-Za-z]/.test(column));

        if (guessedHeader && containsLetters) {
          parserState.header = guessedHeader;
          return;
        }
      }

      let row = null;

      if (parserState.header) {
        const canUseOhlc =
          parserState.header.open >= 0 &&
          parserState.header.high >= 0 &&
          parserState.header.low >= 0 &&
          parserState.header.close >= 0;

        row = canUseOhlc
          ? parseOhlcRow(columns, parserState.header)
          : parseTickRow(columns, parserState.header, defaultSpread);
      } else {
        row = parseHeuristicRow(columns, defaultSpread);
      }

      if (!row) {
        return;
      }

      const bucketTimestamp = Math.floor(row.timestamp / intervalMs) * intervalMs;
      const bucket = buckets.get(bucketTimestamp) || createBucket(bucketTimestamp);

      if (row.type === "ohlc") {
        mergeOhlc(bucket, row);
      } else {
        mergePrice(bucket, row.price, row.volume);
      }

      buckets.set(bucketTimestamp, bucket);
    });
  }

  const candles = Array.from(buckets.values())
    .filter((row) =>
      Number.isFinite(row.open) &&
      Number.isFinite(row.high) &&
      Number.isFinite(row.low) &&
      Number.isFinite(row.close),
    )
    .sort((a, b) => a.timestamp - b.timestamp);

  return candles;
};

export const clearDukascopyCache = () => {
  symbolIntervalCache.clear();
};

export const loadDukascopyCandles = async ({
  symbol,
  interval,
  since,
  limit,
  dataPath,
  defaultSpread = 0,
}) => {
  const intervalMs = INTERVAL_MS[interval];
  if (!intervalMs) {
    throw new Error(`Unsupported interval: ${interval}`);
  }

  const key = `${dataPath}|${normalizeSymbol(symbol)}|${interval}|${defaultSpread}`;

  if (!symbolIntervalCache.has(key)) {
    symbolIntervalCache.set(
      key,
      loadSymbolIntervalCandles({
        symbol,
        interval,
        dataPath,
        defaultSpread,
      }),
    );
  }

  const candles = await symbolIntervalCache.get(key);

  if (!Array.isArray(candles) || candles.length === 0) {
    return [];
  }

  return sliceAlignedCandles(candles, since.getTime(), limit, intervalMs);
};
