import fsPromises from "node:fs/promises";
import path from "node:path";

const annotationsDir = path.join(process.cwd(), "dump", "project");
const annotationsFile = path.join(annotationsDir, "annotations.jsonl");

const dedupeMap = new Map();

let ensurePromise = null;

const ensureStorage = async () => {
  if (!ensurePromise) {
    ensurePromise = fsPromises.mkdir(annotationsDir, { recursive: true });
  }
  await ensurePromise;
};

export const appendAnnotation = async (annotation, options = {}) => {
  const dedupeKey = options.dedupeKey || "";
  const dedupeMs = options.dedupeMs ?? 60_000;

  if (dedupeKey) {
    const now = Date.now();
    const lastAt = dedupeMap.get(dedupeKey) || 0;

    if (now - lastAt < dedupeMs) {
      return;
    }

    dedupeMap.set(dedupeKey, now);
  }

  await ensureStorage();

  const payload = {
    ...annotation,
    createdAt: annotation.createdAt ?? Date.now(),
  };

  await fsPromises.appendFile(annotationsFile, `${JSON.stringify(payload)}\n`, "utf-8");
};

export const readAnnotations = async (limit = 300) => {
  try {
    const raw = await fsPromises.readFile(annotationsFile, "utf-8");
    const lines = raw
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0)
      .slice(-Math.max(1, limit));

    return lines
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
};

export const getAnnotationFilePath = () => annotationsFile;
