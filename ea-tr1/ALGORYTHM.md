# TR1 アルゴリズム詳細

- **タイプ**: トレンドフォロー／ヘッジ口座向け。BUY / SELL の単方向運用（`SCALP<=1`、`SWING<=MaxSwingPositions`）。
- **内部時間足**: `SyntheticBarSec` 秒（初期 10 秒）でオンメモリ生成するバーチャートを使用。各バーは Bid 価格から高値/安値/終値を更新し、スロットが進んだタイミングで確定する。
- **トレンド判定**: バー確定ごとに FastEMA / SlowEMA（デフォルト 20 / 50）を終値で更新し、`fast >= slow` → BUY、`fast < slow` → SELL。最新バーの方向をそのまま採用（ヒストリ平均などは未使用）。
- **ボラ計測**: 確定した内部バーで TR を計算し、`AtrPeriod`（初期 20）の EMA 平滑で ATR を保持。価格単位 → ポイント換算して各種閾値に利用。

## エントリー
- **起動後の待機条件**: `EnterOnInit=true` かつ ATR が正、内部バー本数が `max(FastEmaPeriod, SlowEmaPeriod, ConfirmBarsStartup)`（初期 50 本）に達してからエントリーエンジンを有効化。
- **共通ゲート**: スプレッドが `MaxSpreadPoints`（初期 40pt）以下、ATR>0、`MinTradeIntervalMs`（初期 300ms）を満たし、1 tick で 1 アクションのみ実行。クローズ直後は 1 秒クールダウン、新規ペア開始試行後は 2 秒ロック。
- **初動ペア生成（ノーポジ時）**: 検知したトレンド方向で 1 tick 目に `SCALP`、次 tick で `SWING_1` を建てる（`SWING` は初期SL/TPを同時設定）。
- **SCALP 再補充**: `SWING` が残り `SCALP` が消失した場合、`ScalpRefillIntervalSec` 経過後に `SCALP` のみ補充する（補充経路では `SWING` を増やさない）。
- **条件付きSWING追加（Phase 1.5）**: `EnableSwingPyramiding=true` 時のみ `SWING_2...` を段階追加。必須条件は `+1R` 含み益、`0.8ATR` 進行、`abs(fast-slow)/ATR` 閾値、`総SWINGリスク<=1.5R`。

## 決済ロジック
- **共通ストップ**: 含み損が `ATR × StopAtrMult`（初期 1.0）に達したポジションは成行クローズ。
- **SCALP 利確**: 含み益が `ATR × ScalpAtrTpMult`（初期 0.32）に達したら成行クローズ。TP/SL は価格指定しない。
- **SWING 管理**:
  - 参照価格が建値からブローカー要求の最小距離 `stopLevel` を超えた後、SL を建値±バッファへ引き上げ/下げ。バッファは `max(BreakevenBufferPoints, 現在スプレッド)`（初期 30pt）。
  - トレーリング距離は `ATR × SwingTrailMult`（初期 1.0）。前回更新価格から 20pips 以上動いたときのみ再計算し、ブローカー最小距離を満たす場合に SL を更新。
  - 初期 TP は `ATR × SwingAtrTpMult`（初期 1.05）を建値から設定。建値到達後かつトレーリング更新時には TP を外し、SL トレールに任せる。
  - SL/TP 変更はフリーズレベル/ストップレベルを事前チェックし、要変更時のみ `OrderSend(TRADE_ACTION_SLTP)` で発行。

## 補足・制約
- MagicNumber とシンボル一致を確認して自 EA のポジションだけを操作。コメントは `SCALP` / `SWING_1..N`（旧 `SWING` も互換扱い）。
- エントリー前に整合性チェックを実施し、不整合（方向混在・過剰本数・未知タグ・孤立SCALP）は復旧を優先して新規を停止。
- トレンド反転シグナル時は既存ポジションを即時解消方針（1tick=1actionで順次クローズ）。
- スプレッドが上限を超える場合は新規エントリーを行わない。決済系はスプレッドに依存せず実行。
- 各 tick で `整合性チェック → 反転対応 → ポジション管理 → 条件付きSWING追加 → SCALP補充 → 新規ペア` の順で処理し、1 tick で複数 OrderSend を行わない設計。
