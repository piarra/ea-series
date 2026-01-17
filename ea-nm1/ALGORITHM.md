NM1.mq5 実装アルゴリズム

目的
- `NM1.mq5` の現在実装されているロジックを整理し、仕様を明文化する。

概要
- 両建てグリッド + フィボナッチロットのナンピン。
- 方向別にバスケット決済を行う。
- 24時間稼働 (時間フィルタなし)。

初期化
- ロット列はフィボナッチで構築する。
  - `BaseLot` を 0番と1番に設定し、以降は直前2項の和。
  - シンボルのロットステップ/最小/最大で正規化。
  - 最大段数は `MaxLevels` を 1〜13 に丸める。
- `MagicNumber` と `SlippagePoints` を `CTrade` に設定。
- クローズ用トレードは `UseAsyncClose` を反映。

初期エントリー
- 起動後 `StartDelaySeconds` 経過で、買い/売りが共に 0 の場合に
  buy/sell を同時発注する。
- 初期ロットは `lot_seq[0]` (実質 `BaseLot`)。
- 起動時に既存ポジションがある場合は初期エントリーをスキップする。

再スタート
- 片側のバスケットが全決済された後、`RestartDelaySeconds` 経過で
  その方向のみ再エントリーする。

追加エントリー (ナンピン)
- グリッド幅は `max(ATR_base, MinAtr) * AtrMultiplier`。
  - `ATR_base = SMA(ATR(14)[5], 50)` (5本前から50本分の平均)。
- 既存ポジションがある間は、直近レベルの価格からグリッド幅分ずらしたターゲット価格で追加。
  - 初回のターゲットは buy は `buy.min_price - grid_step`、sell は `sell.max_price + grid_step`。
  - 以降は前回のレベル価格を基準に更新する。
- buy: `ask <= target_price` で追加。
- sell: `bid >= target_price` で追加。
- 段数上限は `MaxLevels`。
  - `SafetyMode = true` の場合、`ATR(14) >= ATR_base * SafeK` または
    `ATR(14) の傾き > ATR_base * SafeSlopeK` の間は
    ナンピン追加を停止する (初回エントリーや決済は継続)。
- ナンピンの連続発注は `NanpinSleepSeconds` で抑制する。
- レベル3以降のナンピンはロットを分離する。
  - `CoreRatio` と `FlexRatio` で分割 (デフォルト 70/30)。
  - Core/Flex は別々のポジションとして発注。
  - Flex は部分利確・補充の対象。

決済 (バスケット)
- buy: `bid >= buy.avg_price + ProfitBase` で全決済。
- sell: `ask <= sell.avg_price - ProfitBase` で全決済。
- クローズはリトライ付き (`CloseRetryCount`, `CloseRetryDelayMs`)。
- Flex 部分利確:
  - `ATR(14) * FlexAtrProfitMultiplier` (デフォルト 0.8) の利益で
    Flex ポジションのみをクローズ。
  - 部分利確した Flex は同一ロット・同一価格に戻ったら再補充。
  - バスケットの段数カウントは Core のみを対象 (Flex は段数に含めない)。
  - 部分利確が発生した方向は、バスケットPLに実現損益を加算し、
    `残存ロット * ProfitBase * 0.5` を目標利益としてバスケット決済を判定する。

停止条件
- `StopBuyLimitPrice` と `StopBuyLimitLot` に一致する buy limit が検出されたら、
  EA を停止する。
  - Magic が `MagicNumber` または 0 の注文を対象。

補足
- SL/TP は設定せず、内部ロジックでクローズ。
- `IsTradingTime()` は常に true で、時間フィルタは無効。
- SafetyMode:
  - `ATR(14) >= ATR_base * SafeK` または `ATR(14) の傾き > ATR_base * SafeSlopeK` の間は
    ナンピン追加を停止する。
  - `SafeStopMode = true` の場合、上記トリガーで保有バスケットを即時クローズする。
