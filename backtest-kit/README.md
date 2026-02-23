# backtest-kit XAUUSD Project

`PLAN.md`に沿って開始した、`backtest-kit`ベースのXAUUSDバックテスト基盤です。

現時点は**Phase 1**として、以下を実装しています。

- Node.jsコマンドでXAUUSDバックテストを実行
- Dukascopy `csv` / `csv.gz`を読み込む独自Exchangeアダプタ
- `NM3` / `SINGLE2` のJS移植先（初期版ロジック）
- UI上でバックテスト起動できる`/control`ページ
- バックテスト進捗・シグナル・regime/blackout注釈の可視化API

## 1. セットアップ

```bash
cp .env.example .env
npm install
```

Dukascopyデータ配置例:

```text
data/dukascopy/
  XAUUSD_2025_01.csv.gz
  XAUUSD_2025_02.csv.gz
  XAGUSD_2025_01.csv.gz
```

`DUKASCOPY_DATA_PATH`はファイル単体でもディレクトリでも指定できます。

## 2. 実行

CLIバックテスト:

```bash
npm run backtest
npm run backtest:nm3
npm run backtest:single2
```

UI + コントロール:

```bash
npm run ui
```

起動後:

- `http://0.0.0.0:60050/control` : バックテスト実行/進捗
- `http://0.0.0.0:60050/` : `@backtest-kit/ui` ダッシュボード

## 3. 主な環境変数

- `DUKASCOPY_DATA_PATH`: Dukascopy CSV/CSV.GZの配置先
- `BACKTEST_FRAME_START` / `BACKTEST_FRAME_END`: `dataset_window`の期間
- `BACKTEST_USE_PERSIST`: `0`でバックテスト通知/ストレージをメモリ化（`.tmp`破損回避）
- `BLACKOUT_WINDOWS`: 取引停止時間帯（UTC、`HH:MM-HH:MM`のカンマ区切り）
- `NEWS_CALENDAR_FILE`: 任意の経済指標CSV（1列目が時刻）
- `DEFAULT_SYMBOL`: 既定シンボル（初期値 `XAUUSD`）
- `SILVER_SYMBOL`: SMT比較先（初期値 `XAGUSD`）
- `SINGLE2_SWING_TRAIL_DISTANCE_RATIO`: SWINGトレーリング距離比率（初期値 `0.55`）
- `SINGLE2_SWING_TP_MULTIPLIER`: SWING側TP倍率（初期値 `12`）

## 4. キャッシュ補助

```bash
npm run cache:dukascopy
npm run cache:validate
```

- `cache:dukascopy`: candleキャッシュを事前作成
- `cache:validate`: キャッシュ欠損チェック

## 5. 移植ステータス

- `NM3.mq5`: 完全移植前のPhase 1実装（regime/cooling/blackoutを含む初期ロジック）
- `SINGLE2.mq5`: SMT + PVT + Structure Break + 擬似dual-entry（50% SCALP利確 + SWINGトレーリング）まで実装

完全移植は次フェーズで、MQLのパラメータ・状態遷移・注文管理を段階的に一致させます。

## 6. 出力

バックテスト出力は`dump/`以下に保存されます。

- `dump/report/*` : backtest-kit標準レポート
- `dump/data/*` : ストレージ/通知/キャッシュ
- `dump/project/annotations.jsonl` : regime/blackout/signal注釈
