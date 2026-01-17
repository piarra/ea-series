#!/usr/bin/env python3
"""NM1.mq5 backtest on XAUUSD tick data.

Default range: last 30 days from latest available data in data/XAUUSD.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import os
from dataclasses import dataclass, field
from typing import Iterator, List, Optional, Tuple

# NM1 constants (from NM1.mq5)
K_MAX_LEVELS = 13
K_CORE_FLEX_SPLIT_LEVEL = 3
K_FLEX_COMMENT = "NM1_FLEX"
K_CORE_COMMENT = "NM1_CORE"
ATR_PERIOD = 14
CONTRACT_SIZE = 100.0
TOTAL_CAPITAL = 250000.0
START_BALANCE = 50000.0
OPTIMIZE_START_LOT = 0.04
OPTIMIZE_STEP = 0.01


def transfer_funds(
    balance: float,
    remaining_funds: float,
    amount: float,
    tick_time: dt.datetime,
    reason: str,
    log_mode: bool,
) -> Tuple[float, float]:
    if amount <= 0.0:
        return balance, remaining_funds
    amount = min(amount, balance)
    balance -= amount
    remaining_funds += amount
    if log_mode:
        print(
            f"{tick_time.isoformat()} "
            f"{reason} amount={amount:.2f} "
            f"balance={balance:.2f} "
            f"remaining_funds={remaining_funds:.2f}"
        )
    return balance, remaining_funds


def apply_fund_management(
    mode: int,
    balance: float,
    remaining_funds: float,
    tick_time: dt.datetime,
    log_mode: bool,
) -> Tuple[float, float]:
    if mode == 2:
        while balance > 100000.0:
            balance, remaining_funds = transfer_funds(
                balance,
                remaining_funds,
                50000.0,
                tick_time,
                "FUND_TRANSFER_MODE2",
                log_mode,
            )
    elif mode == 3:
        while balance > 60000.0:
            balance, remaining_funds = transfer_funds(
                balance,
                remaining_funds,
                10000.0,
                tick_time,
                "FUND_TRANSFER_MODE3",
                log_mode,
            )
    return balance, remaining_funds


@dataclass
class NM1Params:
    magic_number: int = 202507
    slippage_points: int = 4
    start_delay_seconds: int = 5
    atr_multiplier: float = 1.4
    min_atr: float = 1.6
    safety_mode: bool = True
    safe_stop_mode: bool = False
    safe_k: float = 2.0
    safe_slope_k: float = 0.3
    base_lot: float = 0.2
    profit_base: float = 1.0
    core_ratio: float = 0.7
    flex_ratio: float = 0.3
    flex_atr_profit_multiplier: float = 0.8
    max_levels: int = 12
    restart_delay_seconds: int = 1
    nanpin_sleep_seconds: int = 10
    stop_buy_limit_price: float = 4000.0
    stop_buy_limit_lot: float = 0.01


@dataclass
class Position:
    side: str  # "buy" or "sell"
    volume: float
    price: float
    comment: str
    level: int


@dataclass
class FlexRef:
    active: bool = False
    price: float = 0.0
    lot: float = 0.0
    level: int = 0


@dataclass
class BasketInfo:
    count: int = 0
    level_count: int = 0
    volume: float = 0.0
    avg_price: float = 0.0
    min_price: float = 0.0
    max_price: float = 0.0
    profit: float = 0.0


@dataclass
class Bar:
    start: dt.datetime
    open: float
    high: float
    low: float
    close: float


@dataclass
class SymbolState:
    params: NM1Params
    start_time: Optional[dt.datetime] = None
    initial_started: bool = False
    lot_seq: List[float] = field(default_factory=list)
    flex_buy_refs: List[FlexRef] = field(default_factory=list)
    flex_sell_refs: List[FlexRef] = field(default_factory=list)
    buy_level_price: List[float] = field(default_factory=list)
    sell_level_price: List[float] = field(default_factory=list)
    buy_grid_step: float = 0.0
    sell_grid_step: float = 0.0
    last_buy_close_time: Optional[dt.datetime] = None
    last_sell_close_time: Optional[dt.datetime] = None
    last_buy_nanpin_time: Optional[dt.datetime] = None
    last_sell_nanpin_time: Optional[dt.datetime] = None
    prev_buy_count: int = 0
    prev_sell_count: int = 0
    safety_active: bool = False
    realized_buy_profit: float = 0.0
    realized_sell_profit: float = 0.0
    has_partial_buy: bool = False
    has_partial_sell: bool = False


@dataclass
class Stats:
    closed_profit: float = 0.0
    closed_trades: int = 0
    opened_trades: int = 0


@dataclass
class AtrState:
    bars: List[Bar] = field(default_factory=list)  # closed bars
    tr_values: List[float] = field(default_factory=list)  # closed bars TR
    atr_values: List[float] = field(default_factory=list)  # closed bars ATR
    current_bar: Optional[Bar] = None


def normalize_lot(lot: float) -> float:
    step = 0.01
    minlot = 0.01
    maxlot = 100.0
    lot = max(minlot, min(maxlot, lot))
    steps = int(lot / step + 1e-7)
    return round(steps * step, 2)


def normalize_ratio(value: float, fallback: float) -> float:
    return value if value > 0.0 else fallback


def normalize_core_flex_lot(params: NM1Params, lot: float) -> Tuple[float, float]:
    core_ratio = normalize_ratio(params.core_ratio, 0.7)
    flex_ratio = normalize_ratio(params.flex_ratio, 0.3)
    ratio_sum = core_ratio + flex_ratio
    if ratio_sum <= 0.0:
        core_ratio = 0.7
        flex_ratio = 0.3
        ratio_sum = 1.0
    core_ratio /= ratio_sum
    flex_ratio /= ratio_sum
    raw_flex = lot * flex_ratio
    flex = normalize_lot(raw_flex)
    core = normalize_lot(lot - flex)
    if flex <= 0.0:
        flex = 0.0
        core = normalize_lot(lot)
    return core, flex


def effective_max_levels(params: NM1Params) -> int:
    levels = params.max_levels
    if levels < 1:
        levels = 1
    if levels > K_MAX_LEVELS:
        levels = K_MAX_LEVELS
    return levels


def build_lot_sequence(params: NM1Params) -> List[float]:
    levels = effective_max_levels(params)
    seq = [0.0] * levels
    seq[0] = params.base_lot
    if levels > 1:
        seq[1] = params.base_lot
    for i in range(2, levels):
        seq[i] = seq[i - 1] + seq[i - 2]
    for i in range(levels):
        seq[i] = normalize_lot(seq[i])
    return seq


def is_flex_comment(comment: str) -> bool:
    return comment.startswith(K_FLEX_COMMENT)


def make_level_comment(base: str, level: int) -> str:
    if level <= 0:
        return base
    return f"{base}_L{level}"


def extract_level_from_comment(comment: str) -> int:
    pos = comment.find("_L")
    if pos < 0:
        return 0
    tail = comment[pos + 2 :]
    try:
        level = int(tail)
    except ValueError:
        return 0
    return level if level >= 0 else 0


def infer_point(price: float) -> float:
    # XAUUSD tick size is typically 0.01; keep a simple heuristic.
    return 0.01 if price >= 10.0 else 0.00001


def collect_basket_info(positions: List[Position], bid: float, ask: float) -> Tuple[BasketInfo, BasketInfo]:
    buy = BasketInfo()
    sell = BasketInfo()
    buy_value = 0.0
    sell_value = 0.0
    for pos in positions:
        if pos.side == "buy":
            price = pos.price
            if buy.count == 0:
                buy.min_price = price
                buy.max_price = price
            else:
                buy.min_price = min(buy.min_price, price)
                buy.max_price = max(buy.max_price, price)
            buy.count += 1
            if not is_flex_comment(pos.comment):
                buy.level_count += 1
            buy.volume += pos.volume
            buy_value += pos.volume * price
            buy.profit += (bid - price) * pos.volume * CONTRACT_SIZE
        else:
            price = pos.price
            if sell.count == 0:
                sell.min_price = price
                sell.max_price = price
            else:
                sell.min_price = min(sell.min_price, price)
                sell.max_price = max(sell.max_price, price)
            sell.count += 1
            if not is_flex_comment(pos.comment):
                sell.level_count += 1
            sell.volume += pos.volume
            sell_value += pos.volume * price
            sell.profit += (price - ask) * pos.volume * CONTRACT_SIZE
    if buy.volume > 0.0:
        buy.avg_price = buy_value / buy.volume
    if sell.volume > 0.0:
        sell.avg_price = sell_value / sell.volume
    return buy, sell


def sync_level_prices_from_positions(state: SymbolState, positions: List[Position]) -> None:
    for pos in positions:
        if is_flex_comment(pos.comment):
            continue
        level = pos.level
        if level <= 0 or level > K_MAX_LEVELS:
            continue
        if pos.side == "buy":
            if state.buy_level_price[level - 1] <= 0.0:
                state.buy_level_price[level - 1] = pos.price
        else:
            if state.sell_level_price[level - 1] <= 0.0:
                state.sell_level_price[level - 1] = pos.price
    if state.buy_grid_step <= 0.0 and state.buy_level_price[0] > 0.0 and state.buy_level_price[1] > 0.0:
        state.buy_grid_step = abs(state.buy_level_price[0] - state.buy_level_price[1])
    if state.sell_grid_step <= 0.0 and state.sell_level_price[0] > 0.0 and state.sell_level_price[1] > 0.0:
        state.sell_grid_step = abs(state.sell_level_price[0] - state.sell_level_price[1])


def add_flex_ref(refs: List[FlexRef], price: float, lot: float, level: int) -> bool:
    for ref in refs:
        if ref.active and abs(ref.price - price) <= 1e-9 and abs(ref.lot - lot) <= 1e-9 and ref.level == level:
            return False
    for ref in refs:
        if not ref.active:
            ref.active = True
            ref.price = price
            ref.lot = lot
            ref.level = level
            return True
    return False


def update_atr_state(atr_state: AtrState, tick_time: dt.datetime, bid: float) -> Tuple[float, float, float]:
    bar_start = tick_time.replace(second=0, microsecond=0)
    if atr_state.current_bar is None:
        atr_state.current_bar = Bar(start=bar_start, open=bid, high=bid, low=bid, close=bid)
    elif atr_state.current_bar.start != bar_start:
        prev_close = atr_state.bars[-1].close if atr_state.bars else atr_state.current_bar.close
        tr = max(
            atr_state.current_bar.high - atr_state.current_bar.low,
            abs(atr_state.current_bar.high - prev_close),
            abs(atr_state.current_bar.low - prev_close),
        )
        atr_state.bars.append(atr_state.current_bar)
        atr_state.tr_values.append(tr)
        if len(atr_state.tr_values) >= ATR_PERIOD:
            atr = sum(atr_state.tr_values[-ATR_PERIOD:]) / ATR_PERIOD
        else:
            atr = 0.0
        atr_state.atr_values.append(atr)
        atr_state.current_bar = Bar(start=bar_start, open=bid, high=bid, low=bid, close=bid)
    else:
        atr_state.current_bar.high = max(atr_state.current_bar.high, bid)
        atr_state.current_bar.low = min(atr_state.current_bar.low, bid)
        atr_state.current_bar.close = bid

    if atr_state.current_bar is None:
        return 0.0, 0.0, 0.0

    prev_close = atr_state.bars[-1].close if atr_state.bars else atr_state.current_bar.close
    current_tr = max(
        atr_state.current_bar.high - atr_state.current_bar.low,
        abs(atr_state.current_bar.high - prev_close),
        abs(atr_state.current_bar.low - prev_close),
    )
    atr_current = 0.0
    if len(atr_state.tr_values) + 1 >= ATR_PERIOD:
        recent_tr = atr_state.tr_values[-(ATR_PERIOD - 1):] + [current_tr]
        atr_current = sum(recent_tr) / ATR_PERIOD

    atr_base = 0.0
    if atr_current > 0.0:
        temp = atr_state.atr_values + [atr_current]
    else:
        temp = atr_state.atr_values
    if len(temp) >= 55:
        window = temp[-55:-5]
        atr_base = sum(window) / 50.0

    atr_slope = 0.0
    if len(temp) >= 3:
        atr_slope = temp[-1] - temp[-3]

    return atr_current, atr_base, atr_slope


def can_restart(last_close: Optional[dt.datetime], now: dt.datetime, delay: int) -> bool:
    if last_close is None:
        return True
    return (now - last_close).total_seconds() >= delay


def can_nanpin(last_time: Optional[dt.datetime], now: dt.datetime, delay: int) -> bool:
    if last_time is None:
        return True
    return (now - last_time).total_seconds() >= delay


def open_position(
    positions: List[Position],
    stats: Stats,
    side: str,
    volume: float,
    price: float,
    comment: str,
    level: int,
    state: SymbolState,
) -> None:
    volume = normalize_lot(volume)
    if volume <= 0.0:
        return
    positions.append(Position(side=side, volume=volume, price=price, comment=comment, level=level))
    stats.opened_trades += 1
    if side == "buy" and not is_flex_comment(comment):
        if state.buy_level_price[level - 1] <= 0.0:
            state.buy_level_price[level - 1] = price
    if side == "sell" and not is_flex_comment(comment):
        if state.sell_level_price[level - 1] <= 0.0:
            state.sell_level_price[level - 1] = price


def close_positions(
    positions: List[Position],
    stats: Stats,
    side: str,
    bid: float,
    ask: float,
    tick_time: dt.datetime,
    debug: bool,
) -> None:
    remaining = []
    for pos in positions:
        if pos.side != side:
            remaining.append(pos)
            continue
        if side == "buy":
            profit = (bid - pos.price) * pos.volume * CONTRACT_SIZE
        else:
            profit = (pos.price - ask) * pos.volume * CONTRACT_SIZE
        if debug:
            print(
                f"{tick_time.isoformat()} "
                f"{side.upper()} "
                f"lot={pos.volume:.2f} "
                f"profit={profit:.2f} "
                f"comment={pos.comment} "
                f"level={pos.level}"
            )
        stats.closed_profit += profit
        stats.closed_trades += 1
    positions[:] = remaining


def process_flex_partial(
    state: SymbolState,
    positions: List[Position],
    stats: Stats,
    bid: float,
    ask: float,
    atr_now: float,
    tick_time: dt.datetime,
    debug: bool,
) -> None:
    params = state.params
    if atr_now <= 0.0 or params.flex_atr_profit_multiplier <= 0.0:
        return
    target = atr_now * params.flex_atr_profit_multiplier
    remaining = []
    for pos in positions:
        if not is_flex_comment(pos.comment):
            remaining.append(pos)
            continue
        if pos.side == "buy":
            profit = (bid - pos.price)
        else:
            profit = (pos.price - ask)
        if profit < target:
            remaining.append(pos)
            continue
        realized = profit * pos.volume * CONTRACT_SIZE
        if debug:
            print(
                f"{tick_time.isoformat()} "
                f"{pos.side.upper()} "
                f"lot={pos.volume:.2f} "
                f"profit={realized:.2f} "
                f"comment={pos.comment} "
                f"level={pos.level}"
            )
        stats.closed_profit += realized
        stats.closed_trades += 1
        if pos.side == "buy":
            state.realized_buy_profit += realized
            state.has_partial_buy = True
            add_flex_ref(state.flex_buy_refs, pos.price, pos.volume, pos.level)
        else:
            state.realized_sell_profit += realized
            state.has_partial_sell = True
            add_flex_ref(state.flex_sell_refs, pos.price, pos.volume, pos.level)
    positions[:] = remaining


def process_flex_refill(
    state: SymbolState,
    positions: List[Position],
    stats: Stats,
    side: str,
    trigger_price: float,
) -> None:
    point = infer_point(trigger_price)
    tol = point * 0.5
    refs = state.flex_buy_refs if side == "buy" else state.flex_sell_refs
    for ref in refs:
        if not ref.active:
            continue
        should_open = False
        if side == "buy":
            should_open = trigger_price <= ref.price + tol
            price = trigger_price
        else:
            should_open = trigger_price >= ref.price - tol
            price = trigger_price
        if not should_open:
            continue
        comment = make_level_comment(K_FLEX_COMMENT, ref.level)
        open_position(positions, stats, side, ref.lot, price, comment, ref.level, state)
        ref.active = False


def process_tick(
    state: SymbolState,
    positions: List[Position],
    stats: Stats,
    tick_time: dt.datetime,
    bid: float,
    ask: float,
    atr_current: float,
    atr_base: float,
    atr_slope: float,
    debug: bool,
) -> None:
    params = state.params
    buy, sell = collect_basket_info(positions, bid, ask)

    if state.prev_buy_count > 0 and buy.count == 0:
        state.last_buy_close_time = tick_time
        state.last_buy_nanpin_time = None
        state.realized_buy_profit = 0.0
        state.has_partial_buy = False
        state.flex_buy_refs = [FlexRef() for _ in range(K_MAX_LEVELS)]
        state.buy_level_price = [0.0 for _ in range(K_MAX_LEVELS)]
        state.buy_grid_step = 0.0
    if state.prev_sell_count > 0 and sell.count == 0:
        state.last_sell_close_time = tick_time
        state.last_sell_nanpin_time = None
        state.realized_sell_profit = 0.0
        state.has_partial_sell = False
        state.flex_sell_refs = [FlexRef() for _ in range(K_MAX_LEVELS)]
        state.sell_level_price = [0.0 for _ in range(K_MAX_LEVELS)]
        state.sell_grid_step = 0.0

    if buy.count > 0 or sell.count > 0:
        sync_level_prices_from_positions(state, positions)

    attempted_initial = False
    if not state.initial_started:
        if state.start_time is None:
            state.start_time = tick_time
        if (tick_time - state.start_time).total_seconds() >= params.start_delay_seconds:
            if buy.count == 0 and sell.count == 0:
                open_position(
                    positions,
                    stats,
                    "buy",
                    state.lot_seq[0],
                    ask,
                    make_level_comment(K_CORE_COMMENT, 1),
                    1,
                    state,
                )
                open_position(
                    positions,
                    stats,
                    "sell",
                    state.lot_seq[0],
                    bid,
                    make_level_comment(K_CORE_COMMENT, 1),
                    1,
                    state,
                )
                if positions:
                    state.initial_started = True
                attempted_initial = True

    if attempted_initial:
        state.prev_buy_count = buy.count
        state.prev_sell_count = sell.count
        return

    grid_step = 0.0
    atr_ref = atr_base
    if params.min_atr > atr_ref:
        atr_ref = params.min_atr
    if atr_ref > 0.0:
        grid_step = atr_ref * params.atr_multiplier

    if buy.count > 0:
        state.buy_grid_step = max(state.buy_grid_step, grid_step)
    if sell.count > 0:
        state.sell_grid_step = max(state.sell_grid_step, grid_step)

    allow_nanpin = True
    safety_triggered = False
    atr_now = atr_current
    if params.safety_mode and atr_base > 0.0:
        if atr_now >= atr_base * params.safe_k:
            safety_triggered = True
            if not params.safe_stop_mode:
                allow_nanpin = False
        if atr_slope > atr_base * params.safe_slope_k:
            safety_triggered = True
            if not params.safe_stop_mode:
                allow_nanpin = False
    if params.safety_mode:
        state.safety_active = safety_triggered or not allow_nanpin

    if params.safe_stop_mode and safety_triggered:
        if buy.count > 0:
            close_positions(positions, stats, "buy", bid, ask, tick_time, debug)
        if sell.count > 0:
            close_positions(positions, stats, "sell", bid, ask, tick_time, debug)
        state.prev_buy_count = buy.count
        state.prev_sell_count = sell.count
        return

    if atr_now <= 0.0:
        atr_now = atr_current
    process_flex_partial(state, positions, stats, bid, ask, atr_now, tick_time, debug)

    if buy.count > 0:
        if state.has_partial_buy:
            target_profit = buy.volume * params.profit_base * 0.5 * CONTRACT_SIZE
            if (buy.profit + state.realized_buy_profit) >= target_profit:
                close_positions(positions, stats, "buy", bid, ask, tick_time, debug)
        else:
            target = buy.avg_price + params.profit_base
            if bid >= target:
                close_positions(positions, stats, "buy", bid, ask, tick_time, debug)

    if sell.count > 0:
        if state.has_partial_sell:
            target_profit = sell.volume * params.profit_base * 0.5 * CONTRACT_SIZE
            if (sell.profit + state.realized_sell_profit) >= target_profit:
                close_positions(positions, stats, "sell", bid, ask, tick_time, debug)
        else:
            target = sell.avg_price - params.profit_base
            if ask <= target:
                close_positions(positions, stats, "sell", bid, ask, tick_time, debug)

    if state.initial_started:
        if buy.count == 0 and can_restart(state.last_buy_close_time, tick_time, params.restart_delay_seconds):
            open_position(
                positions,
                stats,
                "buy",
                state.lot_seq[0],
                ask,
                make_level_comment(K_CORE_COMMENT, 1),
                1,
                state,
            )
        if sell.count == 0 and can_restart(state.last_sell_close_time, tick_time, params.restart_delay_seconds):
            open_position(
                positions,
                stats,
                "sell",
                state.lot_seq[0],
                bid,
                make_level_comment(K_CORE_COMMENT, 1),
                1,
                state,
            )

    levels = effective_max_levels(params)
    point = infer_point(bid)
    tol = point * 0.5

    if buy.count > 0 and buy.level_count < levels:
        step = state.buy_grid_step if state.buy_grid_step > 0.0 else grid_step
        level_index = buy.level_count
        target = state.buy_level_price[level_index]
        if target <= 0.0:
            base = state.buy_level_price[level_index - 1] if level_index > 0 else buy.min_price
            if base <= 0.0:
                base = buy.min_price
            target = base - step
            state.buy_level_price[level_index] = target
        if allow_nanpin and can_nanpin(state.last_buy_nanpin_time, tick_time, params.nanpin_sleep_seconds):
            if ask <= target + tol:
                lot = state.lot_seq[buy.level_count]
                next_level = buy.level_count + 1
                if next_level >= K_CORE_FLEX_SPLIT_LEVEL:
                    core_lot, flex_lot = normalize_core_flex_lot(params, lot)
                    opened = False
                    if core_lot > 0.0:
                        open_position(
                            positions,
                            stats,
                            "buy",
                            core_lot,
                            ask,
                            make_level_comment(K_CORE_COMMENT, next_level),
                            next_level,
                            state,
                        )
                        opened = True
                    if flex_lot > 0.0:
                        open_position(
                            positions,
                            stats,
                            "buy",
                            flex_lot,
                            ask,
                            make_level_comment(K_FLEX_COMMENT, next_level),
                            next_level,
                            state,
                        )
                        opened = True
                    if opened:
                        state.last_buy_nanpin_time = tick_time
                else:
                    open_position(
                        positions,
                        stats,
                        "buy",
                        lot,
                        ask,
                        make_level_comment(K_CORE_COMMENT, next_level),
                        next_level,
                        state,
                    )
                    state.last_buy_nanpin_time = tick_time

    if sell.count > 0 and sell.level_count < levels:
        step = state.sell_grid_step if state.sell_grid_step > 0.0 else grid_step
        level_index = sell.level_count
        target = state.sell_level_price[level_index]
        if target <= 0.0:
            base = state.sell_level_price[level_index - 1] if level_index > 0 else sell.max_price
            if base <= 0.0:
                base = sell.max_price
            target = base + step
            state.sell_level_price[level_index] = target
        if allow_nanpin and can_nanpin(state.last_sell_nanpin_time, tick_time, params.nanpin_sleep_seconds):
            if bid >= target - tol:
                lot = state.lot_seq[sell.level_count]
                next_level = sell.level_count + 1
                if next_level >= K_CORE_FLEX_SPLIT_LEVEL:
                    core_lot, flex_lot = normalize_core_flex_lot(params, lot)
                    opened = False
                    if core_lot > 0.0:
                        open_position(
                            positions,
                            stats,
                            "sell",
                            core_lot,
                            bid,
                            make_level_comment(K_CORE_COMMENT, next_level),
                            next_level,
                            state,
                        )
                        opened = True
                    if flex_lot > 0.0:
                        open_position(
                            positions,
                            stats,
                            "sell",
                            flex_lot,
                            bid,
                            make_level_comment(K_FLEX_COMMENT, next_level),
                            next_level,
                            state,
                        )
                        opened = True
                    if opened:
                        state.last_sell_nanpin_time = tick_time
                else:
                    open_position(
                        positions,
                        stats,
                        "sell",
                        lot,
                        bid,
                        make_level_comment(K_CORE_COMMENT, next_level),
                        next_level,
                        state,
                    )
                    state.last_sell_nanpin_time = tick_time

    if allow_nanpin:
        if buy.count > 0:
            process_flex_refill(state, positions, stats, "buy", ask)
        if sell.count > 0:
            process_flex_refill(state, positions, stats, "sell", bid)

    state.prev_buy_count = buy.count
    state.prev_sell_count = sell.count


def iter_ticks(data_dir: str, start: dt.datetime, end: dt.datetime) -> Iterator[Tuple[dt.datetime, float, float]]:
    current = start.date()
    while current <= end.date():
        fname = f"XAUUSD_{current.isoformat()}.csv.gz"
        path = os.path.join(data_dir, str(current.year), fname)
        if os.path.exists(path):
            with gzip.open(path, "rt") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    ts = dt.datetime.fromisoformat(row["datetime"])
                    if ts < start or ts > end:
                        continue
                    yield ts, float(row["bid"]), float(row["ask"])
        current += dt.timedelta(days=1)


def parse_user_datetime(value: Optional[str], is_end: bool) -> Optional[dt.datetime]:
    if value is None:
        return None
    value = value.strip()
    if "T" in value or " " in value:
        return dt.datetime.fromisoformat(value)
    date = dt.date.fromisoformat(value)
    if is_end:
        return dt.datetime.combine(date, dt.time(23, 59, 59, 999000))
    return dt.datetime.combine(date, dt.time(0, 0, 0))


def find_latest_date(data_dir: str) -> Optional[dt.date]:
    latest = None
    for root, _, files in os.walk(data_dir):
        for name in files:
            if not name.startswith("XAUUSD_") or not name.endswith(".csv.gz"):
                continue
            date_str = name[len("XAUUSD_") : -len(".csv.gz")]
            try:
                d = dt.date.fromisoformat(date_str)
            except ValueError:
                continue
            if latest is None or d > latest:
                latest = d
    return latest


def build_default_range(data_dir: str) -> Tuple[dt.datetime, dt.datetime]:
    latest = find_latest_date(data_dir)
    if latest is None:
        raise RuntimeError(f"No data found under {data_dir}")
    end = dt.datetime.combine(latest, dt.time(23, 59, 59, 999000))
    start = dt.datetime.combine(latest - dt.timedelta(days=29), dt.time(0, 0, 0))
    return start, end


def init_symbol_state(params: NM1Params) -> SymbolState:
    state = SymbolState(params=params)
    state.lot_seq = build_lot_sequence(params)
    state.flex_buy_refs = [FlexRef() for _ in range(K_MAX_LEVELS)]
    state.flex_sell_refs = [FlexRef() for _ in range(K_MAX_LEVELS)]
    state.buy_level_price = [0.0 for _ in range(K_MAX_LEVELS)]
    state.sell_level_price = [0.0 for _ in range(K_MAX_LEVELS)]
    return state


def run_backtest(
    data_dir: str,
    start: dt.datetime,
    end: dt.datetime,
    debug: bool,
    base_lot_override: Optional[float],
    fund_mode: int,
    log_mode: bool = True,
) -> Tuple[float, bool]:
    params = NM1Params()
    if base_lot_override is not None:
        params.base_lot = base_lot_override
    state = init_symbol_state(params)

    positions: List[Position] = []
    stats = Stats()
    atr_state = AtrState()
    added_funds = 0.0
    reserve_funds = max(0.0, TOTAL_CAPITAL - START_BALANCE)

    max_lot = max(state.lot_seq) if state.lot_seq else params.base_lot
    profit_amount = params.base_lot * params.profit_base * CONTRACT_SIZE
    margin_call_detected = False
    if log_mode:
        print(
            "Backtest setup "
            f"base_lot={params.base_lot:.2f} "
            f"max_nanpin_lot={max_lot:.2f} "
            f"base_profit={params.profit_base:.8f} "
            f"profit_amount={profit_amount:.2f} "
            f"contract_size={CONTRACT_SIZE:.0f} "
            f"start_balance={START_BALANCE:.2f} "
            f"total_capital={TOTAL_CAPITAL:.2f} "
            f"reserve_funds={reserve_funds:.2f} "
            f"fund_mode={fund_mode}"
        )

    ticks = iter_ticks(data_dir, start, end)
    total_ticks = 0
    balance = START_BALANCE
    last_closed_profit = 0.0
    current_hour: Optional[dt.datetime] = None
    hour_peak_equity = balance
    hour_min_equity = balance
    last_balance = balance
    last_equity = balance
    total_funds = reserve_funds
    last_date: Optional[dt.date] = None
    peak_equity = balance
    max_drawdown_amount = 0.0
    max_drawdown_rate = 0.0
    max_drawdown_time: Optional[dt.datetime] = None
    over_50_count = 0
    over_50_active = False
    for tick_time, bid, ask in ticks:
        tick_date = tick_time.date()
        tick_hour = tick_time.replace(minute=0, second=0, microsecond=0)
        if last_date is not None and tick_date != last_date and fund_mode == 1:
            if balance > START_BALANCE:
                excess = balance - START_BALANCE
                balance, total_funds = transfer_funds(
                    balance,
                    total_funds,
                    excess,
                    tick_time,
                    "FUND_TRANSFER_MODE1",
                    log_mode,
                )
                last_balance = balance
                last_equity = max(0.0, last_equity - excess)
        if current_hour is None:
            current_hour = tick_hour
            hour_peak_equity = last_equity
            hour_min_equity = last_equity
            if log_mode:
                print(
                    f"{current_hour.isoformat()} "
                    f"balance={last_balance:.2f} "
                    f"remaining_funds={total_funds:.2f} "
                    f"dd_now=0.00 "
                    f"dd_max=0.00"
                )
        elif tick_hour != current_hour:
            drawdown_now = hour_peak_equity - last_equity
            max_drawdown = hour_peak_equity - hour_min_equity
            if log_mode:
                print(
                    f"{tick_hour.isoformat()} "
                    f"balance={last_balance:.2f} "
                    f"remaining_funds={total_funds:.2f} "
                    f"dd_now={drawdown_now:.2f} "
                    f"dd_max={max_drawdown:.2f}"
                )
            current_hour = tick_hour
            hour_peak_equity = last_equity
            hour_min_equity = last_equity

        total_ticks += 1
        atr_current, atr_base, atr_slope = update_atr_state(atr_state, tick_time, bid)
        process_tick(state, positions, stats, tick_time, bid, ask, atr_current, atr_base, atr_slope, debug)
        realized_delta = stats.closed_profit - last_closed_profit
        if abs(realized_delta) > 1e-12:
            balance += realized_delta
            last_closed_profit = stats.closed_profit
            if fund_mode in (2, 3):
                balance, total_funds = apply_fund_management(
                    fund_mode,
                    balance,
                    total_funds,
                    tick_time,
                    log_mode,
                )

        unrealized = 0.0
        for pos in positions:
            if pos.side == "buy":
                unrealized += (bid - pos.price) * pos.volume * CONTRACT_SIZE
            else:
                unrealized += (pos.price - ask) * pos.volume * CONTRACT_SIZE
        equity = balance + unrealized
        hour_peak_equity = max(hour_peak_equity, equity)
        hour_min_equity = min(hour_min_equity, equity)

        drawdown = hour_peak_equity - equity
        if equity > peak_equity:
            peak_equity = equity
        global_drawdown = peak_equity - equity
        if global_drawdown > max_drawdown_amount:
            max_drawdown_amount = global_drawdown
            max_drawdown_rate = global_drawdown / START_BALANCE if START_BALANCE > 0.0 else 0.0
            max_drawdown_time = tick_time
        current_rate = global_drawdown / START_BALANCE if START_BALANCE > 0.0 else 0.0
        if current_rate > 0.5:
            if not over_50_active:
                over_50_count += 1
                over_50_active = True
        else:
            over_50_active = False
        if balance > 0.0 and drawdown > balance:
            margin_call_detected = True
            loss = balance
            stats.closed_profit -= loss
            last_closed_profit = stats.closed_profit
            if log_mode:
                print(
                    f"{tick_time.isoformat()} "
                    f"MARGIN_CALL loss={loss:.2f} balance=0.00"
                )
            positions.clear()
            state = init_symbol_state(params)
            balance = 0.0
            if total_funds <= 0.0:
                if log_mode:
                    print(
                        f"{tick_time.isoformat()} "
                        f"NO_FUNDS remaining=0.00 backtest_stop"
                    )
                unrealized = 0.0
                equity = balance
                last_balance = balance
                last_equity = equity
                break
            added_funds += START_BALANCE
            total_funds = max(0.0, total_funds - START_BALANCE)
            balance = START_BALANCE
            if log_mode:
                print(
                    f"{tick_time.isoformat()} "
                    f"FUNDING +{START_BALANCE:.2f} total_added={added_funds:.2f} "
                    f"remaining_funds={total_funds:.2f}"
                )
            current_hour = tick_hour
            hour_peak_equity = balance
            hour_min_equity = balance
            unrealized = 0.0
            equity = balance
            peak_equity = max(peak_equity, equity)

        last_balance = balance
        last_equity = equity
        last_date = tick_date

    # Compute unrealized PnL at end
    unrealized = 0.0
    if positions:
        last_bid = bid
        last_ask = ask
        for pos in positions:
            if pos.side == "buy":
                unrealized += (last_bid - pos.price) * pos.volume * CONTRACT_SIZE
            else:
                unrealized += (pos.price - last_ask) * pos.volume * CONTRACT_SIZE

    final_funds = total_funds + balance
    if log_mode:
        print("Backtest result")
        print(f"Range: {start.isoformat()} -> {end.isoformat()}")
        print(f"Ticks: {total_ticks}")
        print(f"Opened trades: {stats.opened_trades}")
        print(f"Closed trades: {stats.closed_trades}")
        print(f"Realized PnL: {stats.closed_profit:.2f}")
        print(f"Unrealized PnL: {unrealized:.2f}")
        print(f"Open positions: {len(positions)}")
        print(f"Added funds: {added_funds:.2f}")
        print(f"Remaining funds: {total_funds:.2f}")
        print(f"Final funds: {final_funds:.2f}")
        if max_drawdown_time is not None:
            print(
                f"Max drawdown time: {max_drawdown_time.isoformat()} "
                f"amount={max_drawdown_amount:.2f} "
                f"rate={max_drawdown_rate:.2%}"
            )
        else:
            print("Max drawdown time: N/A amount=0.00 rate=0.00%")
        print(f"Drawdown over 50% count: {over_50_count}")
    return final_funds, margin_call_detected


def optimize_base_lot(
    data_dir: str,
    start: dt.datetime,
    end: dt.datetime,
    debug: bool,
    fund_mode: int,
    stop_on_margin_call: bool,
) -> None:
    lot = OPTIMIZE_START_LOT
    prev_final: Optional[float] = None
    best_lot = lot
    best_final = -1.0
    while True:
        final_funds, margin_call_detected = run_backtest(
            data_dir,
            start,
            end,
            debug,
            lot,
            fund_mode,
            log_mode=False,
        )
        print(f"Optimize lot={lot:.2f} final_funds={final_funds:.2f}")
        if final_funds > best_final:
            best_final = final_funds
            best_lot = lot
        if margin_call_detected and stop_on_margin_call:
            print(
                f"Optimization stop (margin call) at lot={lot:.2f} "
                f"final_funds={final_funds:.2f}"
            )
            break
        if prev_final is not None and final_funds < prev_final:
            print(
                f"Optimization stop at lot={lot:.2f} "
                f"prev_final={prev_final:.2f} "
                f"final_funds={final_funds:.2f}"
            )
            break
        prev_final = final_funds
        lot = round(lot + OPTIMIZE_STEP, 2)
    print(f"Best lot={best_lot:.2f} best_final_funds={best_final:.2f}")


def main() -> None:
    parser = argparse.ArgumentParser(description="NM1 backtest (XAUUSD)")
    parser.add_argument("--data-dir", default="data/XAUUSD", help="Root data directory")
    parser.add_argument("--from", dest="from_dt", help="Start date/time (YYYY-MM-DD or ISO)")
    parser.add_argument("--to", dest="to_dt", help="End date/time (YYYY-MM-DD or ISO)")
    parser.add_argument("--debug", action="store_true", help="Print trade-level debug logs")
    parser.add_argument("--base-lot", type=float, help="Override base lot size")
    parser.add_argument(
        "--fund-mode",
        type=int,
        choices=[0, 1, 2, 3],
        default=0,
        help="Fund management mode: 0=off, 1=daily sweep >50000, 2=transfer 50000 if >100000, 3=transfer 10000 if >60000",
    )
    parser.add_argument(
        "--optimize-lot",
        action="store_true",
        help="Run lot optimization from 0.04 in 0.01 steps until final funds decrease",
    )
    parser.add_argument(
        "--optimize-stop-on-margin-call",
        action="store_true",
        help="Stop lot optimization when a margin call occurs",
    )
    args = parser.parse_args()

    start = parse_user_datetime(args.from_dt, is_end=False)
    end = parse_user_datetime(args.to_dt, is_end=True)
    if start is None or end is None:
        default_start, default_end = build_default_range(args.data_dir)
        start = start or default_start
        end = end or default_end

    if start > end:
        raise SystemExit("--from must be <= --to")

    if args.optimize_lot:
        optimize_base_lot(
            args.data_dir,
            start,
            end,
            args.debug,
            args.fund_mode,
            args.optimize_stop_on_margin_call,
        )
    else:
        run_backtest(args.data_dir, start, end, args.debug, args.base_lot, args.fund_mode)


if __name__ == "__main__":
    main()
