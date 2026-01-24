#!/usr/bin/env python3
"""DCA1 backtest on tick data (BTCUSD).

Aggregates ticks into H1 bars for indicator calculations.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import json
import os
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, Iterator, List, Optional, Tuple

DEFAULT_SYMBOL = "XAUUSD"
DEFAULT_TIMEFRAME_MINUTES = 60 * 24
CONTRACT_SIZE_DEFAULT = 1.0
LEVERAGE_DEFAULT = 1000.0
SPREAD_DEFAULT = 2.0
PRICE_SCALE_DEFAULT = 1.0
MIN_LOT_DEFAULT = 0.01
LOT_STEP_DEFAULT = 0.01

try:
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)
except AttributeError:
    pass


@dataclass
class Params:
    symbol: str = DEFAULT_SYMBOL
    timeframe_minutes: int = DEFAULT_TIMEFRAME_MINUTES
    base_dca_pct_per_day: float = 1.0
    max_daily_invest_pct: float = 3.0
    max_symbol_exposure_pct: float = 25.0
    max_total_exposure_pct: float = 50.0
    max_margin_usage_pct: float = 10.0
    max_drawdown_cycle_invest_pct: float = 15.0
    min_notional_per_trade: float = 10.0
    atr_period: int = 14
    vol_low_threshold: float = 100.0
    vol_high_threshold: float = 300.0
    ema_len: int = 200
    vol_low_mult: float = 0.8
    vol_mid_mult: float = 1.0
    vol_high_mult: float = 1.2
    tp_low_vol_pct: float = 0.5
    tp_mid_vol_pct: float = 0.8
    tp_high_vol_pct: float = 1.2
    close_fraction_on_tp: float = 1.0
    max_hold_bars: int = 24
    max_adverse_pct: float = 5.0
    active_hours_per_day: int = 24
    recent_high_lookback_bars: int = 500
    daily_profit_target_pct: float = 3.0
    daily_loss_limit_pct: float = 5.0
    close_all_on_daily_loss: bool = True
    spread: float = SPREAD_DEFAULT
    contract_size: float = CONTRACT_SIZE_DEFAULT
    leverage: float = LEVERAGE_DEFAULT
    initial_balance: float = 50000.0
    price_scale: float = PRICE_SCALE_DEFAULT
    min_lot: float = MIN_LOT_DEFAULT
    lot_step: float = LOT_STEP_DEFAULT


@dataclass
class Position:
    volume: float
    entry_price: float
    entry_bar_index: int


@dataclass
class Bar:
    ts: dt.datetime
    open: float
    high: float
    low: float
    close: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbol", default=DEFAULT_SYMBOL)
    parser.add_argument("--data-dir", default="ea-nm1/data")
    parser.add_argument("--from", dest="from_date", required=True)
    parser.add_argument("--to", dest="to_date", required=True)
    parser.add_argument("--initial-balance", type=float, default=50000.0)
    parser.add_argument("--spread", type=float, default=SPREAD_DEFAULT)
    parser.add_argument("--contract-size", type=float, default=CONTRACT_SIZE_DEFAULT)
    parser.add_argument("--leverage", type=float, default=LEVERAGE_DEFAULT)
    parser.add_argument("--price-scale", type=float, default=None)
    parser.add_argument("--min-lot", type=float, default=MIN_LOT_DEFAULT)
    parser.add_argument("--lot-step", type=float, default=LOT_STEP_DEFAULT)
    parser.add_argument("--params", default=None)
    parser.add_argument("--debug", action="store_true")
    return parser.parse_args()


def iter_tick_files(data_dir: str, symbol: str, start: dt.date, end: dt.date) -> Iterator[str]:
    base = os.path.join(data_dir, symbol)
    current = start
    while current <= end:
        path = os.path.join(base, f"{current.year:04d}", f"{symbol}_{current.isoformat()}.csv.gz")
        if os.path.exists(path):
            yield path
        current += dt.timedelta(days=1)


def iter_ticks(
    files: Iterable[str],
    price_scale: float = 1.0,
) -> Iterator[Tuple[dt.datetime, float, float]]:
    scale = price_scale if price_scale > 0.0 else 1.0
    for path in files:
        with gzip.open(path, "rt") as f:
            reader = csv.DictReader(f)
            for row in reader:
                ts = dt.datetime.strptime(row["datetime"], "%Y-%m-%d %H:%M:%S.%f")
                ask = float(row["ask"]) * scale
                bid = float(row["bid"]) * scale
                yield ts, ask, bid


def build_bars(ticks: Iterable[Tuple[dt.datetime, float, float]], timeframe_minutes: int) -> Iterator[Bar]:
    bucket = None
    current_bar = None
    for ts, ask, bid in ticks:
        price = (ask + bid) / 2.0
        bar_time = ts.replace(minute=(ts.minute // timeframe_minutes) * timeframe_minutes, second=0, microsecond=0)
        if bucket is None or bar_time != bucket:
            if current_bar is not None:
                yield current_bar
            bucket = bar_time
            current_bar = Bar(ts=bucket, open=price, high=price, low=price, close=price)
        else:
            current_bar.high = max(current_bar.high, price)
            current_bar.low = min(current_bar.low, price)
            current_bar.close = price
    if current_bar is not None:
        yield current_bar


def calc_atr(bars: List[Bar], period: int) -> List[Optional[float]]:
    atr = [None] * len(bars)
    trs = []
    for i, bar in enumerate(bars):
        if i == 0:
            tr = bar.high - bar.low
        else:
            prev_close = bars[i - 1].close
            tr = max(bar.high - bar.low, abs(bar.high - prev_close), abs(bar.low - prev_close))
        trs.append(tr)
        if i + 1 >= period:
            atr[i] = sum(trs[i + 1 - period : i + 1]) / period
    return atr


def calc_ema(values: List[float], period: int) -> List[Optional[float]]:
    ema = [None] * len(values)
    if not values:
        return ema
    k = 2.0 / (period + 1.0)
    ema_val = values[0]
    for i, v in enumerate(values):
        if i == 0:
            ema_val = v
        else:
            ema_val = v * k + ema_val * (1.0 - k)
        if i + 1 >= period:
            ema[i] = ema_val
    return ema


def calc_recent_high(bars: List[Bar], lookback: int) -> List[Optional[float]]:
    highs = [None] * len(bars)
    for i in range(len(bars)):
        if i == 0:
            highs[i] = bars[i].high
            continue
        start = max(0, i - lookback)
        highs[i] = max(b.high for b in bars[start:i])
    return highs


def notional(volume: float, price: float, contract_size: float) -> float:
    return volume * contract_size * price


def margin_required(volume: float, price: float, contract_size: float, leverage: float) -> float:
    return notional(volume, price, contract_size) / leverage


def round_down_to_step(value: float, step: float) -> float:
    if step <= 0.0:
        return value
    return (value // step) * step


def select_tp_pct(atr: Optional[float], params: Params) -> float:
    if atr is None:
        return params.tp_mid_vol_pct
    if atr < params.vol_low_threshold:
        return params.tp_low_vol_pct
    if atr > params.vol_high_threshold:
        return params.tp_high_vol_pct
    return params.tp_mid_vol_pct


def dca_signal(
    equity: float,
    price: float,
    atr: Optional[float],
    ema: Optional[float],
    recent_high: Optional[float],
    params: Params,
) -> float:
    daily_budget = equity * params.base_dca_pct_per_day / 100.0
    hourly_base = daily_budget / float(params.active_hours_per_day)
    vol_mult = params.vol_mid_mult
    if atr is not None:
        if atr < params.vol_low_threshold:
            vol_mult = params.vol_low_mult
        elif atr > params.vol_high_threshold:
            vol_mult = params.vol_high_mult
    trend_mult = 0.8
    if ema is not None and price > ema:
        trend_mult = 1.2
    dd_mult = 1.0
    if recent_high and recent_high > 0.0:
        drawdown_pct = (recent_high - price) / recent_high * 100.0
        if drawdown_pct < 3.0:
            dd_mult = 0.7
        elif drawdown_pct < 7.0:
            dd_mult = 1.0
        elif drawdown_pct < 15.0:
            dd_mult = 1.3
        else:
            dd_mult = 1.5
    return hourly_base * vol_mult * trend_mult * dd_mult


def close_fraction(positions: List[Position], fraction: float) -> float:
    if fraction <= 0.0 or not positions:
        return 0.0
    total_volume = sum(p.volume for p in positions)
    if total_volume <= 0.0:
        return 0.0
    target = total_volume * fraction
    positions.sort(key=lambda p: p.entry_bar_index)
    closed_volume = 0.0
    remaining = target
    i = 0
    while i < len(positions) and remaining > 0.0:
        pos = positions[i]
        close_vol = min(pos.volume, remaining)
        pos.volume -= close_vol
        closed_volume += close_vol
        remaining -= close_vol
        if pos.volume <= 1e-9:
            positions.pop(i)
            continue
        i += 1
    return closed_volume


def run_backtest(bars: List[Bar], params: Params, debug: bool = False) -> Dict[str, float]:
    balance = params.initial_balance
    equity = balance
    positions: List[Position] = []
    today_invested = 0.0
    cycle_invested = 0.0
    cycle_high = 0.0
    daily_start_balance = balance
    daily_entry_blocked = False
    daily_trading_halted = False
    realized_profit = 0.0
    max_drawdown = 0.0
    peak_equity = equity

    def log(message: str) -> None:
        if debug:
            print(message, file=sys.stderr, flush=True)

    def log_skip(reason: str) -> None:
        if debug:
            print(f"[SKIP] ts={bar.ts.isoformat()} reason={reason}", file=sys.stderr, flush=True)

    def position_stats() -> Tuple[float, float]:
        total_volume = sum(p.volume for p in positions)
        avg_entry = (
            sum(p.volume * p.entry_price for p in positions) / total_volume
            if total_volume > 0.0
            else 0.0
        )
        return total_volume, avg_entry

    closes = [b.close for b in bars]
    atrs = calc_atr(bars, params.atr_period)
    emas = calc_ema(closes, params.ema_len)
    recent_highs = calc_recent_high(bars, params.recent_high_lookback_bars)

    last_day = None
    for i, bar in enumerate(bars):
        day_key = bar.ts.date()
        if last_day is None or day_key != last_day:
            today_invested = 0.0
            daily_start_balance = balance
            daily_entry_blocked = False
            daily_trading_halted = False
            last_day = day_key

        unrealized = sum(
            (bar.close - p.entry_price) * p.volume * params.contract_size for p in positions
        )
        equity = balance + unrealized
        peak_equity = max(peak_equity, equity)
        drawdown = (peak_equity - equity) / peak_equity * 100.0 if peak_equity > 0 else 0.0
        max_drawdown = max(max_drawdown, drawdown)

        daily_net = (balance - daily_start_balance) / daily_start_balance * 100.0
        if daily_net >= params.daily_profit_target_pct:
            daily_entry_blocked = True
            if daily_net <= -params.daily_loss_limit_pct:
                daily_trading_halted = True
                if params.close_all_on_daily_loss:
                    total_volume, avg_entry = position_stats()
                    balance += unrealized
                    realized_profit += unrealized
                    positions = []
                    today_invested = 0.0
                    cycle_invested = 0.0
                    equity = balance
                    if total_volume > 0.0:
                        log(
                            f"[CLOSE_ALL_DAILY_LOSS] ts={bar.ts.isoformat()} price={bar.close:.2f} "
                            f"total_lot={total_volume:.2f} avg_entry={avg_entry:.2f} "
                        f"pnl={unrealized:.2f}"
                    )

        total_volume, avg_entry = position_stats()
        if total_volume > 0.0 and avg_entry > 0.0:
            avg_entry_for_checks = avg_entry
            total_volume_for_checks = total_volume
            tp_pct = select_tp_pct(atrs[i], params)
            tp_price = avg_entry_for_checks * (1.0 + tp_pct / 100.0)
            if bar.close >= tp_price:
                pre_volume = total_volume_for_checks
                closed = close_fraction(positions, params.close_fraction_on_tp)
                if closed > 0.0:
                    profit = (bar.close - avg_entry_for_checks) * closed * params.contract_size
                    balance += profit
                    realized_profit += profit
                    equity = balance + sum(
                        (bar.close - p.entry_price) * p.volume * params.contract_size
                        for p in positions
                    )
                    if not positions:
                        today_invested = 0.0
                        cycle_invested = 0.0
                    total_volume_after, avg_entry_after = position_stats()
                    log(
                        f"[CLOSE_TP] ts={bar.ts.isoformat()} price={bar.close:.2f} "
                        f"closed_lot={closed:.2f} total_lot={total_volume_after:.2f} "
                        f"avg_entry={avg_entry_after:.2f} pnl={profit:.2f} "
                        f"balance={balance:.2f} equity={equity:.2f} "
                        f"prev_total_lot={pre_volume:.2f}"
                    )
            adverse_pct = (avg_entry_for_checks - bar.close) / avg_entry_for_checks * 100.0
            if adverse_pct >= params.max_adverse_pct:
                profit = (
                    (bar.close - avg_entry_for_checks)
                    * total_volume_for_checks
                    * params.contract_size
                )
                balance += profit
                realized_profit += profit
                positions = []
                total_volume = 0.0
                today_invested = 0.0
                cycle_invested = 0.0
                log(
                    f"[CLOSE_ADVERSE] ts={bar.ts.isoformat()} price={bar.close:.2f} "
                    f"total_lot=0.00 avg_entry=0.00 pnl={profit:.2f}"
                )

        if params.max_hold_bars > 0 and positions:
            for pos in list(positions):
                if i - pos.entry_bar_index >= params.max_hold_bars:
                    profit = (bar.close - pos.entry_price) * pos.volume * params.contract_size
                    balance += profit
                    realized_profit += profit
                    positions.remove(pos)
                    total_volume, avg_entry = position_stats()
                    if not positions:
                        today_invested = 0.0
                        cycle_invested = 0.0
                    log(
                        f"[CLOSE_MAX_HOLD] ts={bar.ts.isoformat()} price={bar.close:.2f} "
                        f"closed_lot={pos.volume:.2f} total_lot={total_volume:.2f} "
                        f"avg_entry={avg_entry:.2f} pnl={profit:.2f}"
                    )

        if cycle_high <= 0.0:
            cycle_high = bar.high
        prev_high = cycle_high
        if bar.high > cycle_high:
            cycle_high = bar.high
        if bar.high > prev_high * 1.05:
            cycle_high = bar.high
            cycle_invested = 0.0

        if daily_trading_halted or daily_entry_blocked:
            if daily_trading_halted:
                log_skip("daily_trading_halted")
            else:
                log_skip("daily_entry_blocked")
            continue

        raw_notional = dca_signal(
            equity=equity,
            price=bar.close,
            atr=atrs[i],
            ema=emas[i],
            recent_high=recent_highs[i],
            params=params,
        )
        if raw_notional < params.min_notional_per_trade:
            log_skip(f"min_notional raw={raw_notional:.2f} min={params.min_notional_per_trade:.2f}")
            continue

        daily_max = equity * params.max_daily_invest_pct / 100.0
        allowable_today = daily_max - today_invested
        if allowable_today <= 0.0:
            log_skip(f"daily_limit allowable={allowable_today:.2f}")
            continue
        raw_notional = min(raw_notional, allowable_today)

        symbol_budget = equity * params.max_symbol_exposure_pct / 100.0
        symbol_exposure = sum(
            notional(p.volume, bar.close, params.contract_size) for p in positions
        )
        allowable_sym = symbol_budget - symbol_exposure
        if allowable_sym <= 0.0:
            log_skip(f"symbol_limit allowable={allowable_sym:.2f}")
            continue
        raw_notional = min(raw_notional, allowable_sym)

        total_budget = equity * params.max_total_exposure_pct / 100.0
        allowable_total = total_budget - symbol_exposure
        if allowable_total <= 0.0:
            log_skip(f"total_limit allowable={allowable_total:.2f}")
            continue
        raw_notional = min(raw_notional, allowable_total)

        cycle_budget = equity * params.max_drawdown_cycle_invest_pct / 100.0
        allowable_cycle = cycle_budget - cycle_invested
        if allowable_cycle <= 0.0:
            log_skip(f"cycle_limit allowable={allowable_cycle:.2f}")
            continue
        raw_notional = min(raw_notional, allowable_cycle)

        ask_price = bar.close + params.spread / 2.0
        volume = raw_notional / (params.contract_size * ask_price)
        volume = round_down_to_step(volume, params.lot_step)
        if volume <= 0.0:
            log_skip(f"volume_nonpositive volume={volume:.6f}")
            continue
        if volume < params.min_lot:
            log_skip(f"min_lot volume={volume:.6f} min={params.min_lot:.6f}")
            continue

        margin_existing = sum(
            margin_required(p.volume, bar.close, params.contract_size, params.leverage)
            for p in positions
        )
        margin_new = margin_required(volume, ask_price, params.contract_size, params.leverage)
        margin_usage = (margin_existing + margin_new) / equity * 100.0
        if margin_usage > params.max_margin_usage_pct:
            log_skip(f"margin_usage usage={margin_usage:.2f} max={params.max_margin_usage_pct:.2f}")
            continue

        positions.append(Position(volume=volume, entry_price=ask_price, entry_bar_index=i))
        today_invested += raw_notional
        cycle_invested += raw_notional
        total_volume, avg_entry = position_stats()
        log(
            f"[ENTRY] ts={bar.ts.isoformat()} price={ask_price:.2f} "
            f"notional={raw_notional:.2f} lot={volume:.2f} "
            f"total_lot={total_volume:.2f} avg_entry={avg_entry:.2f}"
        )

    equity = balance + sum(
        (bars[-1].close - p.entry_price) * p.volume * params.contract_size for p in positions
    )
    return {
        "final_balance": balance,
        "final_equity": equity,
        "realized_profit": realized_profit,
        "max_drawdown_pct": max_drawdown,
        "open_positions": float(len(positions)),
    }


def load_params(path: Optional[str], base: Params) -> Params:
    if not path:
        return base
    with open(path, "r") as f:
        data = json.load(f)
    for k, v in data.items():
        if hasattr(base, k):
            setattr(base, k, v)
    return base


def main() -> None:
    args = parse_args()
    start = dt.date.fromisoformat(args.from_date)
    end = dt.date.fromisoformat(args.to_date)
    price_scale = args.price_scale
    if price_scale is None:
        price_scale = 100.0 if args.symbol == "BTCUSD" else 1.0
    params = Params(
        symbol=args.symbol,
        spread=args.spread,
        contract_size=args.contract_size,
        leverage=args.leverage,
        initial_balance=args.initial_balance,
        price_scale=price_scale,
        min_lot=args.min_lot,
        lot_step=args.lot_step,
    )
    params = load_params(args.params, params)
    files = list(iter_tick_files(args.data_dir, args.symbol, start, end))
    if not files:
        raise SystemExit("No data files found.")
    ticks = iter_ticks(files, params.price_scale)
    bars = list(build_bars(ticks, params.timeframe_minutes))
    if not bars:
        raise SystemExit("No bars constructed from data.")
    results = run_backtest(bars, params, debug=args.debug)
    print(json.dumps(results, indent=2), flush=True)


if __name__ == "__main__":
    main()
