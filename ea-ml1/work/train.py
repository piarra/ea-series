import os
import lzma
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score
from xgboost import XGBClassifier

import onnxmltools
from onnxmltools.convert.common.data_types import FloatTensorType


# =========================
# Config
# =========================

@dataclass
class DukascopyConfig:
    symbol: str = "XAUUSD"              # Dukascopy symbol
    out_dir: str = "./dukascopy_cache"  # cache folder for bi5
    tz: timezone = timezone.utc         # Dukascopy URL is in GMT/UTC hours (common practice)
    user_agent: str = "Mozilla/5.0"

@dataclass
class BarConfig:
    bar_seconds: int = 10               # 10 or 15
    # XAUUSD pip/point convention (common): 0.01 = 1 pip/point.
    # TP40 pips = 0.40, SL30 pips = 0.30 (if your broker defines differently, change pip_size!)
    pip_size: float = 0.01
    tp_pips: int = 40
    sl_pips: int = 30
    horizon_bars: int = 6               # e.g. 10s * 6 = 60 seconds

@dataclass
class TrainConfig:
    test_size: float = 0.2
    random_state: int = 42
    n_estimators: int = 800
    max_depth: int = 5
    learning_rate: float = 0.03
    subsample: float = 0.9
    colsample_bytree: float = 0.9


# =========================
# Dukascopy download & decode
# =========================

DT_TICKS = np.dtype([
    ("time_ms", ">u4"),       # milliseconds from start of hour (big-endian u32)
    ("ask", ">u4"),           # price integer
    ("bid", ">u4"),           # price integer
    ("ask_vol", ">f4"),       # float32
    ("bid_vol", ">f4"),       # float32
])
# The above dtype layout matches a commonly documented Dukascopy .bi5 tick record structure
# (20 bytes fixed length, big-endian).  [oai_citation:1‡AIでFX](https://aifx.tech/dukascopy3/)


def dukascopy_hour_url(cfg: DukascopyConfig, dt_utc: datetime) -> str:
    """
    URL format example in docs/articles:
    http://datafeed.dukascopy.com/datafeed/EURUSD/2022/03/04/20h_ticks.bi5
    Note: month is 0-based in Dukascopy URL (00=Jan).  [oai_citation:2‡AIでFX](https://aifx.tech/dukascopy3/)
    """
    y = dt_utc.year
    m0 = dt_utc.month - 1  # 0-based month
    d = dt_utc.day
    h = dt_utc.hour
    return f"http://datafeed.dukascopy.com/datafeed/{cfg.symbol}/{y}/{m0:02d}/{d:02d}/{h:02d}h_ticks.bi5"


def download_bi5(cfg: DukascopyConfig, dt_utc: datetime) -> Path:
    out_base = Path(cfg.out_dir) / cfg.symbol / f"{dt_utc.year}" / f"{dt_utc.month:02d}" / f"{dt_utc.day:02d}"
    out_base.mkdir(parents=True, exist_ok=True)
    out_path = out_base / f"{dt_utc.hour:02d}h_ticks.bi5"

    if out_path.exists() and out_path.stat().st_size > 0:
        return out_path

    url = dukascopy_hour_url(cfg, dt_utc)

    req = urllib.request.Request(url, headers={"User-Agent": cfg.user_agent})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        # Some hours may not exist; Dukascopy may return 404.
        with open(out_path, "wb") as f:
            f.write(data)
    except Exception as e:
        # create empty marker so we don't retry endlessly
        with open(out_path, "wb") as f:
            f.write(b"")
        print(f"[WARN] failed download {url}: {e}")

    return out_path


def decode_bi5_to_df(bi5_path: Path, dt_hour_utc: datetime) -> pd.DataFrame:
    raw = bi5_path.read_bytes()
    if not raw:
        return pd.DataFrame(columns=["ts", "bid", "ask", "bid_vol", "ask_vol"])

    try:
        decomp = lzma.decompress(raw)
    except Exception:
        # sometimes a failed download produces html; treat as empty
        return pd.DataFrame(columns=["ts", "bid", "ask", "bid_vol", "ask_vol"])

    arr = np.frombuffer(decomp, dtype=DT_TICKS)
    if arr.size == 0:
        return pd.DataFrame(columns=["ts", "bid", "ask", "bid_vol", "ask_vol"])

    # Convert to timestamps
    base = dt_hour_utc.replace(minute=0, second=0, microsecond=0, tzinfo=timezone.utc)
    ts = pd.to_datetime(base) + pd.to_timedelta(arr["time_ms"].astype(np.int64), unit="ms")

    df = pd.DataFrame({
        "ts": ts,
        "bid": arr["bid"].astype(np.float64),
        "ask": arr["ask"].astype(np.float64),
        "bid_vol": arr["bid_vol"].astype(np.float64),
        "ask_vol": arr["ask_vol"].astype(np.float64),
    })

    # Dukascopy integer prices need scaling.
    # TickVault README notes assets have their own price scales and you need scaling factor.  [oai_citation:3‡GitHub](https://github.com/keyhankamyar/TickVault)
    # For XAUUSD, many dumps use 1e3 or 1e2 depending on feed. We infer a scale heuristically:
    # if bid is like 2000000 -> divide by 1000; if like 200000 -> divide by 100; etc.
    median = float(np.median(df["bid"].values))
    if median > 1_000_000:
        scale = 1000.0
    elif median > 100_000:
        scale = 100.0
    else:
        scale = 1.0

    df["bid"] /= scale
    df["ask"] /= scale

    return df.sort_values("ts")


def load_ticks(cfg: DukascopyConfig, start_utc: datetime, end_utc: datetime) -> pd.DataFrame:
    """
    Load ticks from start_utc (inclusive) to end_utc (exclusive).
    """
    assert start_utc.tzinfo is not None and end_utc.tzinfo is not None
    cur = start_utc.replace(minute=0, second=0, microsecond=0)
    end_hour = end_utc.replace(minute=0, second=0, microsecond=0)

    parts = []
    while cur <= end_hour:
        p = download_bi5(cfg, cur)
        dfh = decode_bi5_to_df(p, cur)
        if not dfh.empty:
            parts.append(dfh)
        cur += timedelta(hours=1)

    if not parts:
        return pd.DataFrame(columns=["ts", "bid", "ask", "bid_vol", "ask_vol"])

    df = pd.concat(parts, ignore_index=True)
    df = df[(df["ts"] >= pd.to_datetime(start_utc)) & (df["ts"] < pd.to_datetime(end_utc))]
    return df.reset_index(drop=True)


# =========================
# Resample to synthetic 10s / 15s bars
# =========================

def make_bars(ticks: pd.DataFrame, bar_seconds: int) -> pd.DataFrame:
    if ticks.empty:
        return pd.DataFrame()

    t = ticks.set_index("ts")
    # mid price and spread
    t["mid"] = (t["bid"] + t["ask"]) / 2.0
    t["spread"] = (t["ask"] - t["bid"])

    # Pandas 2.2+ no longer accepts upper-case "S" for seconds.
    rule = f"{bar_seconds}s"
    agg = {
        "mid": ["first", "max", "min", "last"],
        "bid_vol": "sum",
        "ask_vol": "sum",
        "spread": ["mean", "max"],
    }
    b = t.resample(rule).agg(agg)
    b.columns = [
        "open", "high", "low", "close",
        "bid_vol", "ask_vol",
        "spread_mean", "spread_max"
    ]
    b = b.dropna()
    b["tick_count"] = t["mid"].resample(rule).count().reindex(b.index).astype(np.float64)
    return b.reset_index().rename(columns={"ts": "time"})


# =========================
# Features + Triple-barrier label (TP/SL first-touch within H bars)
# =========================

def add_features(bars: pd.DataFrame) -> pd.DataFrame:
    df = bars.copy()
    # returns
    df["ret1"] = df["close"].pct_change()
    df["ret2"] = df["close"].pct_change(2)
    df["mom3"] = (df["close"] - df["close"].shift(3)) / df["close"].shift(3)

    # range + candle shape
    rng = (df["high"] - df["low"]).replace(0, np.nan)
    df["range"] = rng
    df["body_ratio"] = (df["close"] - df["open"]).abs() / rng
    df["upper_wick"] = (df["high"] - df[["open","close"]].max(axis=1)) / rng
    df["lower_wick"] = (df[["open","close"]].min(axis=1) - df["low"]) / rng

    # volatility proxy
    df["tr"] = np.maximum(df["high"] - df["low"],
                          np.maximum((df["high"] - df["close"].shift(1)).abs(),
                                     (df["low"] - df["close"].shift(1)).abs()))
    df["atr14"] = df["tr"].rolling(14).mean()

    # microstructure
    df["spread_mean"] = df["spread_mean"]
    df["spread_max"] = df["spread_max"]
    df["tick_vol"] = df["tick_count"]
    df["tick_vol_z"] = (df["tick_vol"] - df["tick_vol"].rolling(60).mean()) / (df["tick_vol"].rolling(60).std() + 1e-9)

    # time-of-day (UTC) cyclical
    hh = df["time"].dt.hour + df["time"].dt.minute / 60.0
    df["tod_sin"] = np.sin(2*np.pi*hh/24.0)
    df["tod_cos"] = np.cos(2*np.pi*hh/24.0)

    return df


def triple_barrier_label(df: pd.DataFrame, bar_cfg: BarConfig) -> pd.Series:
    """
    Binary label for LONG-only example:
      y=1 if within H bars high reaches entry+tp first
      y=0 if within H bars low  reaches entry-sl first
    You can train separate models for BUY and SELL, or include direction as feature.
    """
    tp = bar_cfg.tp_pips * bar_cfg.pip_size
    sl = bar_cfg.sl_pips * bar_cfg.pip_size
    H = bar_cfg.horizon_bars

    close = df["close"].values
    high = df["high"].values
    low  = df["low"].values

    n = len(df)
    y = np.full(n, np.nan)

    for i in range(n - H):
        entry = close[i]
        up = entry + tp
        dn = entry - sl

        hit = None
        for k in range(1, H+1):
            # if both touch same bar: be conservative -> count as loss (or drop). Here: loss.
            if high[i+k] >= up and low[i+k] <= dn:
                hit = 0
                break
            if high[i+k] >= up:
                hit = 1
                break
            if low[i+k] <= dn:
                hit = 0
                break

        y[i] = hit  # may remain NaN if neither touched

    return pd.Series(y, index=df.index, name="y")


# =========================
# Train XGBoost + export ONNX
# =========================

def train_xgb_and_export_onnx(data: pd.DataFrame, onnx_path: str):
    # choose features
    feature_cols = [
        "ret1","ret2","mom3",
        "range","body_ratio","upper_wick","lower_wick",
        "atr14",
        "spread_mean","spread_max",
        "tick_vol","tick_vol_z",
        "tod_sin","tod_cos",
    ]

    ds = data.dropna(subset=feature_cols + ["y"]).copy()
    X = ds[feature_cols].astype(np.float32).values
    y = ds["y"].astype(np.int64).values

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=TRAIN.test_size, random_state=TRAIN.random_state, shuffle=False
    )

    clf = XGBClassifier(
        n_estimators=TRAIN.n_estimators,
        max_depth=TRAIN.max_depth,
        learning_rate=TRAIN.learning_rate,
        subsample=TRAIN.subsample,
        colsample_bytree=TRAIN.colsample_bytree,
        reg_lambda=1.0,
        objective="binary:logistic",
        tree_method="hist",
        eval_metric="auc",
        random_state=TRAIN.random_state,
    )
    clf.fit(X_train, y_train)

    p = clf.predict_proba(X_test)[:, 1]
    auc = roc_auc_score(y_test, p)
    print(f"AUC={auc:.4f}  test_samples={len(y_test)}")

    # Export to ONNX (onnxmltools supports XGBoost conversion; see ONNX tutorial examples)  [oai_citation:4‡onnx.ai](https://onnx.ai/sklearn-onnx/auto_examples/plot_pipeline_xgboost.html?utm_source=chatgpt.com)
    initial_types = [("input", FloatTensorType([None, X.shape[1]]))]
    onx = onnxmltools.convert_xgboost(clf, initial_types=initial_types)

    with open(onnx_path, "wb") as f:
        f.write(onx.SerializeToString())
    print("saved:", onnx_path, "features:", feature_cols)

    return clf, feature_cols


# =========================
# Main
# =========================

if __name__ == "__main__":
    DUKA = DukascopyConfig(symbol="XAUUSD", out_dir="./dukascopy_cache")
    BAR = BarConfig(bar_seconds=10, tp_pips=40, sl_pips=30, horizon_bars=6)
    TRAIN = TrainConfig()

    # Example range (UTC)
    start = datetime(2025, 1, 1, 0, 0, tzinfo=timezone.utc)
    end   = datetime(2025, 2, 1, 0, 0, tzinfo=timezone.utc)

    ticks = load_ticks(DUKA, start, end)
    print("ticks:", len(ticks))

    bars = make_bars(ticks, BAR.bar_seconds)
    print("bars:", len(bars))

    feat = add_features(bars)
    feat["y"] = triple_barrier_label(feat, BAR)

    # (optional) drop "no-touch" cases
    feat = feat.dropna(subset=["y"]).reset_index(drop=True)

    model, feature_cols = train_xgb_and_export_onnx(
        feat, onnx_path=f"xgb_xau_{BAR.bar_seconds}s_tp{BAR.tp_pips}_sl{BAR.sl_pips}.onnx"
    )
