export const closes = (candles) => candles.map((candle) => candle.close);
export const highs = (candles) => candles.map((candle) => candle.high);
export const lows = (candles) => candles.map((candle) => candle.low);

export const sma = (values, period) => {
  if (period <= 0 || values.length === 0) {
    return [];
  }

  const output = new Array(values.length).fill(Number.NaN);
  let rolling = 0;

  for (let index = 0; index < values.length; index += 1) {
    rolling += values[index];

    if (index >= period) {
      rolling -= values[index - period];
    }

    if (index >= period - 1) {
      output[index] = rolling / period;
    }
  }

  return output;
};

export const ema = (values, period) => {
  if (period <= 0 || values.length === 0) {
    return [];
  }

  const output = new Array(values.length).fill(Number.NaN);
  const alpha = 2 / (period + 1);

  output[0] = values[0];

  for (let index = 1; index < values.length; index += 1) {
    output[index] = alpha * values[index] + (1 - alpha) * output[index - 1];
  }

  return output;
};

export const rsi = (values, period = 14) => {
  if (values.length <= period) {
    return [];
  }

  const output = new Array(values.length).fill(Number.NaN);

  let gain = 0;
  let loss = 0;

  for (let index = 1; index <= period; index += 1) {
    const change = values[index] - values[index - 1];
    if (change >= 0) {
      gain += change;
    } else {
      loss -= change;
    }
  }

  let avgGain = gain / period;
  let avgLoss = loss / period;

  output[period] = avgLoss === 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);

  for (let index = period + 1; index < values.length; index += 1) {
    const change = values[index] - values[index - 1];
    const up = change > 0 ? change : 0;
    const down = change < 0 ? -change : 0;

    avgGain = (avgGain * (period - 1) + up) / period;
    avgLoss = (avgLoss * (period - 1) + down) / period;

    if (avgLoss === 0) {
      output[index] = 100;
      continue;
    }

    const rs = avgGain / avgLoss;
    output[index] = 100 - 100 / (1 + rs);
  }

  return output;
};

export const atr = (candles, period = 14) => {
  if (candles.length <= period) {
    return [];
  }

  const output = new Array(candles.length).fill(Number.NaN);
  const trs = new Array(candles.length).fill(Number.NaN);

  for (let index = 1; index < candles.length; index += 1) {
    const current = candles[index];
    const previous = candles[index - 1];

    const tr = Math.max(
      current.high - current.low,
      Math.abs(current.high - previous.close),
      Math.abs(current.low - previous.close),
    );

    trs[index] = tr;
  }

  let sum = 0;
  for (let index = 1; index <= period; index += 1) {
    sum += trs[index];
  }

  output[period] = sum / period;

  for (let index = period + 1; index < candles.length; index += 1) {
    output[index] = (output[index - 1] * (period - 1) + trs[index]) / period;
  }

  return output;
};

export const lastFinite = (values) => {
  for (let index = values.length - 1; index >= 0; index -= 1) {
    if (Number.isFinite(values[index])) {
      return values[index];
    }
  }
  return Number.NaN;
};

export const highest = (values, lookback) => {
  if (values.length === 0) {
    return Number.NaN;
  }

  const from = Math.max(0, values.length - lookback);
  let result = Number.NEGATIVE_INFINITY;
  for (let index = from; index < values.length; index += 1) {
    result = Math.max(result, values[index]);
  }
  return result;
};

export const lowest = (values, lookback) => {
  if (values.length === 0) {
    return Number.NaN;
  }

  const from = Math.max(0, values.length - lookback);
  let result = Number.POSITIVE_INFINITY;
  for (let index = from; index < values.length; index += 1) {
    result = Math.min(result, values[index]);
  }
  return result;
};
