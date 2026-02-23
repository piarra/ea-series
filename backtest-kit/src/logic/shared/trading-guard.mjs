import fsPromises from "node:fs/promises";
import {
  BLACKOUT_WINDOWS,
  NEWS_CALENDAR_FILE,
  NEWS_MINUTES_AFTER,
  NEWS_MINUTES_BEFORE,
} from "../../config/params.mjs";

const parseClock = (value) => {
  const [hour, minute] = value.split(":").map((item) => Number.parseInt(item, 10));
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
};

const parseBlackoutWindowList = (value) => {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
    .map((item) => {
      const [from, to] = item.split("-").map((chunk) => chunk.trim());
      const fromMinute = parseClock(from);
      const toMinute = parseClock(to);
      if (fromMinute === null || toMinute === null) {
        return null;
      }
      return { fromMinute, toMinute, raw: item };
    })
    .filter(Boolean);
};

const blackoutWindowList = parseBlackoutWindowList(BLACKOUT_WINDOWS);

const parseTimestamp = (value) => {
  const raw = value.trim().replace(/^"|"$/g, "");
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

const lowerBound = (list, target) => {
  let left = 0;
  let right = list.length;

  while (left < right) {
    const mid = left + ((right - left) >> 1);
    if (list[mid] < target) {
      left = mid + 1;
    } else {
      right = mid;
    }
  }

  return left;
};

const isInBlackoutWindow = (when) => {
  if (blackoutWindowList.length === 0) {
    return null;
  }

  const minuteOfDay = when.getUTCHours() * 60 + when.getUTCMinutes();

  for (const window of blackoutWindowList) {
    const { fromMinute, toMinute } = window;

    const inRange = fromMinute <= toMinute
      ? minuteOfDay >= fromMinute && minuteOfDay <= toMinute
      : minuteOfDay >= fromMinute || minuteOfDay <= toMinute;

    if (inRange) {
      return window.raw;
    }
  }

  return null;
};

let newsEventTimePromise = null;

const loadNewsEventTimes = async () => {
  if (!NEWS_CALENDAR_FILE) {
    return [];
  }

  const content = await fsPromises.readFile(NEWS_CALENDAR_FILE, "utf-8");
  const rows = content.split(/\r?\n/);
  const times = [];

  for (const row of rows) {
    const trimmed = row.trim();
    if (!trimmed) {
      continue;
    }

    const firstColumn = trimmed.split(",")[0] || "";
    if (/server_time|timestamp|date|time/i.test(firstColumn) && /[A-Za-z]/.test(firstColumn)) {
      continue;
    }

    const timestamp = parseTimestamp(firstColumn);
    if (Number.isFinite(timestamp)) {
      times.push(timestamp);
    }
  }

  times.sort((a, b) => a - b);
  return times;
};

const getNewsEventTimes = async () => {
  if (!newsEventTimePromise) {
    newsEventTimePromise = loadNewsEventTimes().catch((error) => {
      newsEventTimePromise = null;
      throw error;
    });
  }
  return await newsEventTimePromise;
};

const findNewsEvent = async (when) => {
  const events = await getNewsEventTimes();
  if (events.length === 0) {
    return null;
  }

  const from = when.getTime() - NEWS_MINUTES_BEFORE * 60_000;
  const to = when.getTime() + NEWS_MINUTES_AFTER * 60_000;

  const index = lowerBound(events, from);
  if (index < events.length && events[index] <= to) {
    return events[index];
  }

  return null;
};

export const checkTradingGuard = async (when) => {
  const blackout = isInBlackoutWindow(when);
  if (blackout) {
    return {
      blocked: true,
      reason: "blackout_window",
      detail: blackout,
    };
  }

  if (!NEWS_CALENDAR_FILE) {
    return {
      blocked: false,
      reason: "ok",
    };
  }

  const newsTimestamp = await findNewsEvent(when);
  if (Number.isFinite(newsTimestamp)) {
    return {
      blocked: true,
      reason: "news_window",
      detail: new Date(newsTimestamp).toISOString(),
    };
  }

  return {
    blocked: false,
    reason: "ok",
  };
};
