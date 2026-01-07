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
  - 最大段数は `MaxLevels` を 1〜20 に丸める。
- `MagicNumber` と `SlippagePoints` を `CTrade` に設定。
- クローズ用トレードは `UseAsyncClose` を反映。

初期エントリー
- 起動後 `StartDelaySeconds` 経過で、買い/売りが共に 0 の場合に
  buy/sell を同時発注する。
- 初期ロットは `lot_seq[0]` (実質 `BaseLot`)。

再スタート
- 片側のバスケットが全決済された後、`RestartDelaySeconds` 経過で
  その方向のみ再エントリーする。

追加エントリー (ナンピン)
- グリッド幅は以下のいずれか。
  - `GridStepAuto = false`: `GridStepPoints * PipPointSize()`。
  - `GridStepAuto = true`: `ATR_base * AtrMultiplier`。
    - `ATR_base = SMA(ATR(14)[5], 50)` (5本前から50本分の平均)。
- buy: `ask <= buy.min_price - grid_step` で追加。
- sell: `bid >= sell.max_price + grid_step` で追加。
- 段数上限は `MaxLevels`。
  - `SafetyMode = true` の場合、`ATR(14) >= ATR_base * SafeK` の間は
    ナンピン追加を停止する (初回エントリーや決済は継続)。
- 3回目以降のナンピンはロットを分離する。
  - `CoreRatio` と `FlexRatio` で分割 (デフォルト 70/30)。
  - Core/Flex は別々のポジションとして発注。
  - Flex は部分利確・補充の対象。

決済 (バスケット)
- buy: `bid >= buy.avg_price + ProfitOffsetByCount(count)` で全決済。
- sell: `ask <= sell.avg_price - ProfitOffsetByCount(count)` で全決済。
- `ProfitOffsetByCount` は `count <= 2` なら `ProfitBase`、
  それ以降は `ProfitBase + (count - 2) * ProfitStep`。
- クローズはリトライ付き (`CloseRetryCount`, `CloseRetryDelayMs`)。
- Flex 部分利確:
  - `ATR(14) * FlexAtrProfitMultiplier` (デフォルト 0.5) の利益で
    Flex ポジションのみをクローズ。
  - 部分利確した Flex は同一ロット・同一価格に戻ったら再補充。
  - バスケットの段数カウントは Core のみを対象 (Flex は段数に含めない)。

停止条件
- `StopBuyLimitPrice` と `StopBuyLimitLot` に一致する buy limit が検出されたら、
  EA を停止する。
  - Magic が `MagicNumber` または 0 の注文を対象。

補足
- SL/TP は設定せず、内部ロジックでクローズ。
- `IsTradingTime()` は常に true で、時間フィルタは無効。
