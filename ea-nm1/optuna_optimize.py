#!/usr/bin/env python3
"""Optuna optimizer for NM1 backtest parameters."""

from __future__ import annotations

import argparse
import sys
from typing import Dict

try:
    import optuna
except ImportError as exc:  # pragma: no cover - optuna is optional
    raise SystemExit(
        "optuna is not installed. Install with: pip install optuna"
    ) from exc

from backtest_nm1 import (
    K_MAX_LEVELS,
    TOTAL_CAPITAL,
    build_default_range,
    parse_user_datetime,
    run_backtest,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Optimize NM1 parameters with Optuna")
    parser.add_argument("--data-dir", default="data/XAUUSD", help="Root data directory")
    parser.add_argument("--from", dest="from_dt", help="Start date/time (YYYY-MM-DD or ISO)")
    parser.add_argument("--to", dest="to_dt", help="End date/time (YYYY-MM-DD or ISO)")
    parser.add_argument(
        "--fund-mode",
        type=int,
        choices=[0, 1, 2, 3],
        default=0,
        help="Fund management mode: 0=off, 1=daily sweep >50000, 2=transfer 50000 if >100000, 3=transfer 10000 if >60000",
    )
    parser.add_argument("--trials", type=int, default=50, help="Number of trials")
    parser.add_argument("--jobs", type=int, default=1, help="Parallel jobs")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--study-name", default="nm1_optuna", help="Study name")
    parser.add_argument("--storage", help="Optuna storage URL (e.g. sqlite:///result/optuna.db)")
    parser.add_argument("--optimize-safety-mode", action="store_true", help="Include safety_mode in search")

    parser.add_argument("--base-lot-min", type=float, default=0.03)
    parser.add_argument("--base-lot-max", type=float, default=0.03)
    parser.add_argument("--base-lot-step", type=float, default=0.01)

    parser.add_argument("--atr-multiplier-min", type=float, default=1.3)
    parser.add_argument("--atr-multiplier-max", type=float, default=1.3)
    parser.add_argument("--min-atr-min", type=float, default=0.5)
    parser.add_argument("--min-atr-max", type=float, default=3.0)
    parser.add_argument("--safe-k-min", type=float, default=2.0)
    parser.add_argument("--safe-k-max", type=float, default=2.0)
    parser.add_argument("--safe-slope-k-min", type=float, default=0.3)
    parser.add_argument("--safe-slope-k-max", type=float, default=0.3)
    parser.add_argument("--profit-base-min", type=float, default=1.4)
    parser.add_argument("--profit-base-max", type=float, default=3.0)
    parser.add_argument("--profit-base-step", type=float, default=0.1)
    parser.add_argument("--profit-base-level-step-min", type=float, default=0.0)
    parser.add_argument("--profit-base-level-step-max", type=float, default=0.2)
    parser.add_argument("--profit-base-level-min-min", type=float, default=0.0)
    parser.add_argument("--profit-base-level-min-max", type=float, default=1.0)
    parser.add_argument("--core-ratio-min", type=float, default=1)
    parser.add_argument("--core-ratio-max", type=float, default=1)
    parser.add_argument("--flex-atr-profit-mult-min", type=float, default=1.0)
    parser.add_argument("--flex-atr-profit-mult-max", type=float, default=1.0)
    parser.add_argument("--max-levels-min", type=int, default=5)
    parser.add_argument("--max-levels-max", type=int, default=12)
    parser.add_argument("--core-flex-split-level-min", type=int, default=4)
    parser.add_argument("--core-flex-split-level-max", type=int, default=4)

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    start = parse_user_datetime(args.from_dt, is_end=False)
    end = parse_user_datetime(args.to_dt, is_end=True)
    if start is None or end is None:
        default_start, default_end = build_default_range(args.data_dir)
        start = start or default_start
        end = end or default_end
    if start > end:
        raise SystemExit("--from must be <= --to")

    max_levels_max = min(args.max_levels_max, K_MAX_LEVELS)
    if args.max_levels_min > max_levels_max:
        raise SystemExit("--max-levels-min must be <= --max-levels-max")
    if args.core_flex_split_level_min > args.core_flex_split_level_max:
        raise SystemExit(
            "--core-flex-split-level-min must be <= --core-flex-split-level-max"
        )

    def objective(trial: optuna.Trial) -> float:
        params: Dict[str, object] = {}
        base_lot_step = args.base_lot_step if args.base_lot_step > 0 else None
        params["base_lot"] = trial.suggest_float(
            "base_lot",
            args.base_lot_min,
            args.base_lot_max,
            step=base_lot_step,
        )
        params["atr_multiplier"] = trial.suggest_float(
            "atr_multiplier",
            args.atr_multiplier_min,
            args.atr_multiplier_max,
        )
        params["min_atr"] = trial.suggest_float(
            "min_atr",
            args.min_atr_min,
            args.min_atr_max,
        )
        params["safe_k"] = trial.suggest_float(
            "safe_k",
            args.safe_k_min,
            args.safe_k_max,
            step=0.01,
        )
        params["safe_slope_k"] = trial.suggest_float(
            "safe_slope_k",
            args.safe_slope_k_min,
            args.safe_slope_k_max,
            step=0.01,
        )
        params["profit_base"] = trial.suggest_float(
            "profit_base",
            args.profit_base_min,
            args.profit_base_max,
            step=args.profit_base_step if args.profit_base_step > 0 else None,
        )
        params["profit_base_level_mode"] = trial.suggest_categorical(
            "profit_base_level_mode", [True, False]
        )
        params["profit_base_level_step"] = trial.suggest_float(
            "profit_base_level_step",
            args.profit_base_level_step_min,
            args.profit_base_level_step_max,
        )
        params["profit_base_level_min"] = trial.suggest_float(
            "profit_base_level_min",
            args.profit_base_level_min_min,
            args.profit_base_level_min_max,
        )
        core_ratio = trial.suggest_float(
            "core_ratio",
            args.core_ratio_min,
            args.core_ratio_max,
            step=0.1,
        )
        params["core_ratio"] = core_ratio
        params["flex_ratio"] = max(0.0, 1.0 - core_ratio)
        params["flex_atr_profit_multiplier"] = trial.suggest_float(
            "flex_atr_profit_multiplier",
            args.flex_atr_profit_mult_min,
            args.flex_atr_profit_mult_max,
        )
        params["max_levels"] = trial.suggest_int(
            "max_levels",
            args.max_levels_min,
            max_levels_max,
        )
        params["core_flex_split_level"] = trial.suggest_int(
            "core_flex_split_level",
            args.core_flex_split_level_min,
            args.core_flex_split_level_max,
            step=1,
        )
        if args.optimize_safety_mode:
            params["safety_mode"] = trial.suggest_categorical(
                "safety_mode", [True, False]
            )

        final_funds, margin_call, max_drawdown_rate = run_backtest(
            args.data_dir,
            start,
            end,
            debug=False,
            base_lot_override=None,
            fund_mode=args.fund_mode,
            log_mode=False,
            params_override=params,
        )
        profit = final_funds - TOTAL_CAPITAL
        if margin_call or max_drawdown_rate >= 0.8:
            profit = 0.0
        trial.set_user_attr("final_funds", final_funds)
        trial.set_user_attr("margin_call", margin_call)
        trial.set_user_attr("max_drawdown_rate", max_drawdown_rate)
        return profit

    def log_best(study: optuna.Study, trial: optuna.trial.FrozenTrial) -> None:
        if study.best_trial.number != trial.number:
            return
        max_dd_rate = trial.user_attrs.get("max_drawdown_rate")
        if isinstance(max_dd_rate, (int, float)):
            max_dd_text = f"{max_dd_rate * 100:.2f}%"
        else:
            max_dd_text = "N/A"
        print(
            f"best is trial {trial.number} with value: {trial.value}. "
            f"max_dd_percent: {max_dd_text}"
        )

    optuna.logging.set_verbosity(optuna.logging.WARNING)
    sampler = optuna.samplers.TPESampler(seed=args.seed)
    study = optuna.create_study(
        study_name=args.study_name,
        sampler=sampler,
        storage=args.storage,
        load_if_exists=bool(args.storage),
        direction="maximize",
    )
    study.optimize(
        objective,
        n_trials=args.trials,
        n_jobs=args.jobs,
        show_progress_bar=True,
        callbacks=[log_best],
    )

    best = study.best_trial
    print("Best trial")
    print(f"  profit: {best.value:.2f}")
    print(f"  params: {best.params}")
    print(f"  final_funds: {best.user_attrs.get('final_funds')}")
    print(f"  margin_call: {best.user_attrs.get('margin_call')}")
    max_dd_rate = best.user_attrs.get("max_drawdown_rate")
    print(f"  max_drawdown_rate: {max_dd_rate}")
    if isinstance(max_dd_rate, (int, float)):
        print(f"  max_dd_percent: {max_dd_rate * 100:.2f}")


if __name__ == "__main__":
    main()
