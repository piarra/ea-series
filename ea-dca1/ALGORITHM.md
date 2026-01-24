# MT5 EA設計書  
## 名称：BTCUSD 高回転DCAスキャルグリッドEA

---

## 1. 概要

### 1.1 目的

- 対象：BTCUSD（Exness CFD 想定）
- 目的：
  - **保有枚数を増やすことではなく、短期の利確を積み重ねること**
  - ポジションの「回転数」を重視し、**長期保有・塩漬けを避ける**
  - 含み損は口座 Equity の **20% 以内**を目安とする

### 1.2 戦略コンセプト

- 基本方針：  
  - DCA（時間分散エントリー）＋**小さめの利確グリッド**で高回転
  - ポジションは **短期〜中期の値動きで完結させる**（時間制限＋損切りあり）
- 特徴：
  - エントリーは Equity ベースの少額を**時間分散**して積み上げ
  - 価格が平均建値から一定幅戻れば **グループで利確（できればフルクローズ）**
  - **最大保有時間**と **最大逆行幅**を超えたら、損切りも行う
  - 「含み損抱えて数週間耐える」ような投資モードは避ける

---

## 2. 運用前提・仕様

### 2.1 環境

- プラットフォーム：MetaTrader 5（MQL5 EA）
- ブローカー：Exness
- シンボル：`BTCUSD`（ブローカー仕様名をパラメータで指定可能）
- レバレッジ：最大 1:400（ただし実効レバは 10〜15倍程度に抑制）

### 2.2 稼働条件

- 稼働時間：24時間
- 判定時間足：H1（1時間足）
- ロジックは **確定足ベース**で判定（ティックでトリガー検知）

---

## 3. 目的に合わせた設計ポイント

- ✅ **高回転・短期完結のためのルール**
  - `MaxHoldBars`（最大保有バー数）で**時間切れクローズ**を実装
  - `MaxAdversePct`（最大許容逆行率）で**価格ベース損切り**
  - 利確時は原則 **ポジションの大半〜全てをクローズ**（枚数の積み増しは狙わない）

- ✅ **含み損 20% 制御のためのルール**
  - `MaxSymbolExposurePct`（BTCUSD のノッチ上限）を 25% 程度に制限
  - `MaxDrawdownCycleInvestPct` で「1下げサイクルに突っ込む量」を抑制
  - `MaxMarginUsagePct` で証拠金使用率を制限（ロスカット余裕を確保）

---

## 4. パラメータ定義

### 4.1 外部入力パラメータ（input）

| 項目名 | 型 | 推奨初期値 | 説明 |
|--------|----|------------|------|
| SymbolName | string | `"BTCUSD"` | 取引シンボル名 |
| Timeframe | ENUM_TIMEFRAMES | PERIOD_H1 | 判定時間足 |
| BaseDcaPctPerDay | double | 1.0 | 1日あたりの基準DCA予算（% of Equity） |
| MaxDailyInvestPct | double | 3.0 | 1日あたり新規建て上限（% of Equity） |
| MaxSymbolExposurePct | double | 25.0 | BTCUSDノッチ総量上限（% of Equity） |
| MaxTotalExposurePct | double | 50.0 | 口座全体ノッチ総量上限（% of Equity） |
| MaxMarginUsagePct | double | 10.0 | 必要証拠金使用率上限（% of Equity） |
| MaxDrawdownCycleInvestPct | double | 15.0 | 1下落サイクルで投入する新規ノッチ上限（% of Equity） |
| AtrPeriod | int | 14 | ATR計算期間（H1） |
| VolLowThreshold | double | 100.0 | ATRがこの値未満なら低ボラ |
| VolHighThreshold | double | 300.0 | ATRがこの値超なら高ボラ |
| EmaLen | int | 200 | トレンド判定用EMA期間（H1） |
| TpLowVolPct | double | 0.5 | 低ボラ時の利確幅（%） |
| TpMidVolPct | double | 0.8 | 中ボラ時の利確幅（%） |
| TpHighVolPct | double | 1.2 | 高ボラ時の利確幅（%） |
| CloseFractionOnTP | double | 0.7〜1.0 | 利確時にクローズするポジション割合（1.0なら全決済） |
| MaxHoldBars | int | 24 | 最大保有バー数（H1×24=最大約1日保有） |
| MaxAdversePct | double | 5.0 | 平均建値から逆行を許容する最大率（%） |
| ActiveHoursPerDay | int | 24 | 稼働時間数 |
| RecentHighLookbackBars | int | 500 | 直近高値探索のバー本数 |
| Slippage | int | 50 | 発注スリッページ許容値 |
| MagicNumber | int | 223344 | EA識別用Magic |
| CommentTag | string | `"DCA_SCALP_BTC"` | 注文コメントタグ |
| DailyProfitTargetPct | double | 3.0 | 1日の確定損益がEquityの何%に達したらEA停止するか |
| DailyLossLimitPct | double | 5.0 | 1日の損失がEquityの何%に達したらEA停止するか |

※ 利確幅は「スプレッド＋手数料」を考慮し、**純利益が残る最小幅＋α**に調整が必要。

### 4.2 内部状態変数（グローバル）

| 変数名 | 型 | 説明 |
|--------|----|------|
| lastProcessedBarTime | datetime | 最後にロジックを実行したバー時間 |
| todayInvestedNotional | double | 当日分の新規建てノッチ合計 |
| cycleInvestedNotional | double | 現在下落サイクルでの新規建て合計 |
| cycleRecentHigh | double | サイクル中の直近高値 |
| avgEntryPrice | double | BTCUSDロングの平均建値 |
| barCountSinceEntry | int | 各ポジションごとの保有バー数（ポジション属性として管理 or 配列管理） |
| dailyStartEquity | double | 当日開始時点のEquity |
| dailyNetProfitPct | double | 当日確定損益 / dailyStartEquity（%） |

---

## 5. ロジック詳細

### 5.1 メインフロー（OnTick）

1. 新バー検出（H1）：
   - `iTime(SymbolName, Timeframe, 0)` が `lastProcessedBarTime` より新しければ処理。
2. 日付変更チェック：
   - 日付が変わった場合：
     - `todayInvestedNotional = 0;`
     - `dailyStartEquity = 現在Equity;`
3. 当日損益状況チェック：
   - 当日確定損益率 `dailyNetProfitPct` を計算
   - `dailyNetProfitPct >= DailyProfitTargetPct` → その日は**新規エントリー停止**（既存ポジのみ決済OK）
   - `dailyNetProfitPct <= -DailyLossLimitPct` → 既存ポジも含め EA 停止 or 強制クローズ（運用方針に応じて）

4. インジケータ・口座・ポジション情報更新：
   - ATR, EMA200
   - Equity, Margin, Symbol別／全体エクスポージャ
   - avgEntryPrice / 保有量 / 各ポジション保有バー数更新

5. 2つのロジックを順に評価：
   - `① 利確・損切り／時間切れクローズ`
   - `② 新規エントリー判定`

---

### 5.2 利確・損切り・時間切れクローズ

#### 5.2.1 平均建値と利確基準価格

- ロングポジションの平均建値 `avgEntryPrice` を算出（ノッチ加重平均）。

```text
if totalVolume == 0:
    avgEntryPrice = 0;  // ノーポジ時

	•	ボラ状態に応じて利確幅を決定：

if ATR < VolLowThreshold      → tpPct = TpLowVolPct;
else if ATR > VolHighThreshold→ tpPct = TpHighVolPct;
else                           tpPct = TpMidVolPct;

	•	利確トリガー価格：

tpPrice = avgEntryPrice * (1.0 + tpPct / 100.0);

5.2.2 利確条件・クローズ量
	•	条件：Bid >= tpPrice
	•	利確量：

totalVolumeLots = BTCUSDロングの合計ロット;
lotsToClose = totalVolumeLots * CloseFractionOnTP;
lotsToClose = 最小ロット以上かつ最大ロット以下に丸める;

	•	CloseFractionOnTP = 0.7〜1.0
回転重視の場合は 1.0（フルクローズ）推奨
	•	実装上は、古い順にポジションをクローズ（FIFO）
または、一括部分決済（複数ポジ対応関数）を実装。

5.2.3 最大逆行率による損切り
	•	価格が平均建値から MaxAdversePct 以上逆行した場合：

adversePct = (avgEntryPrice - Bid) / avgEntryPrice * 100.0;  // ロング前提

if adversePct >= MaxAdversePct:
    全ロングポジションを成行決済（または一定割合クローズ）;
    cycleInvestedNotional を 0 にリセットするか、別ルールで管理;

※ 含み損上限（Equity DD 20%）と整合を取るため、MaxAdversePct と MaxSymbolExposurePct はセットで調整。

5.2.4 最大保有バー数による時間切れクローズ
	•	各ポジションに「エントリー時のバー番号 or 時刻」を保持。
	•	現在バーとの比較で保有バー数を算出。

if holdBars >= MaxHoldBars:
    当該ポジションを成行クローズ（損益問わず）;

	•	これにより、「長期保有・塩漬け」を明確に禁止。

⸻

5.3 新規エントリーロジック

5.3.1 ボラ・トレンド・下落状態の判定（概要）
	•	ATR → VolState（LOW / MID / HIGH）
	•	EMA200 → TrendState（UP / DOWN）
	•	直近高値 → drawdownPct（押し目度合い）

if price > EMA200 → TrendState = UP
if price < EMA200 → TrendState = DOWN

drawdownPct = (recentHigh - price) / recentHigh * 100.0
	•	DCA を厚くする倍率 DdMult は「押し目時のみやや増やす」程度に抑える：

if drawdownPct < 3    → DdMult = 0.7
else if < 7           → DdMult = 1.0
else if < 15          → DdMult = 1.3
else                  → DdMult = 1.5

※あくまで「高回転ロング」であり、「大幅下落で全力ナンピン」は避ける。

5.3.2 基準DCAノッチ（Equityベース）
	1.	Equity取得：

equity = AccountInfoDouble(ACCOUNT_EQUITY);

	2.	1日分の基準DCA予算：

dailyBudget = equity * BaseDcaPctPerDay / 100.0;

	3.	1時間あたり基準：

hourlyBase = dailyBudget / ActiveHoursPerDay;

	4.	ボラ＋トレンド＋下落倍率を掛け合わせ：

// トレンド倍率：強い上昇中は若干厚く、下降中は薄く
if TrendState == UP:   TrendMult = 1.2;
else:                  TrendMult = 0.8;

rawNotional = hourlyBase * VolMult * TrendMult * DdMult;

5.3.3 各種制約（新規エントリー前）
	1.	当日上限（MaxDailyInvestPct）

dailyMax      = equity * MaxDailyInvestPct / 100.0;
allowableToday = dailyMax - todayInvestedNotional;

if allowableToday <= 0:
    rawNotional = 0;
else
    rawNotional = MathMin(rawNotional, allowableToday);

	2.	シンボル別上限（MaxSymbolExposurePct）

symbolExposure = BTCUSDロングのノッチ総額;
symbolBudget   = equity * MaxSymbolExposurePct / 100.0;
allowableSym   = symbolBudget - symbolExposure;

if allowableSym <= 0:
    rawNotional = 0;
else
    rawNotional = MathMin(rawNotional, allowableSym);

	3.	全体エクスポージャ上限（MaxTotalExposurePct）

口座全体ノッチに対して同様のチェック。
	4.	証拠金使用率上限（MaxMarginUsagePct）

OrderCalcMargin() で新規ポジション分の必要証拠金を試算し、
発注後の margin / equity * 100 が上限を超えるなら rawNotional = 0。
	5.	最低ノッチ（MinNotionalPerTrade）

if rawNotional < MinNotionalPerTrade:
    rawNotional = 0;

5.3.4 ロット計算と注文発注
	•	BTCUSDの仕様に従って、名目額→ロットへ変換。

price       = SymbolInfoDouble(SymbolName, SYMBOL_ASK);
contractSize= SymbolInfoDouble(SymbolName, SYMBOL_TRADE_CONTRACT_SIZE);

// notional ≒ volume * contractSize * price
volume = rawNotional / (contractSize * price);
volume = ロット最小単位に丸める;

	•	MqlTradeRequest を用いて BUY 成行注文。
	•	MagicNumber, CommentTag を設定。
	•	約定成功時：
	•	todayInvestedNotional += rawNotional;
	•	cycleInvestedNotional += rawNotional;
	•	ポジションごとの entryBarIndex を記録（MaxHoldBars 用）。

⸻

6. サイクル管理（任意・簡略）
	•	「下落サイクルごとに突っ込む量」を抑えるため、以下を管理：
	•	cycleRecentHigh：サイクル中の高値
	•	cycleInvestedNotional：そのサイクルでの新規合計
	•	price が cycleRecentHigh を明確に更新したタイミング（例：5%以上上抜け）でサイクルリセット：

if price > cycleRecentHigh * 1.05:
    cycleRecentHigh = price;
    cycleInvestedNotional = 0;


⸻

7. 例外処理・フェイルセーフ
	•	スプレッド異常拡大時（シンボルの SYMBOL_SPREAD が閾値以上）：
	•	新規エントリーは禁止、既存ポジ決済のみ許可。
	•	エラーコード（リクオート、接続切れ等）はログ出力＋リトライ回数制限付きで処理。
	•	必要に応じて、ニュース時間帯（FOMC、CPIなど）は外部パラメータで「新規禁止時間帯」として設定可能。

⸻

8. バックテスト指針
	•	期間：2020〜直近までの BTCUSD H1 データ
	•	評価指標：
	•	最大DD（Equity、20%以内が目標）
	•	年率／月次リターン（確定損益ベース）
	•	平均保有時間（短期完結になっているか）
	•	1日あたりトレード回数（回転率）

⸻

9. まとめ

本EAは、
「BTCを長期保有して増やす」のではなく、
「DCA×グリッドで細かく利確しながら、とにかく回転させる」 ための設計とする。
	•	長期保有を避けるために MaxHoldBars / MaxAdversePct / 損益による日次ストップ を明示的に導入。
	•	含み損20%以内に収めるため、エクスポージャ上限とサイクル上限でブレーキをかける。

バックテストでは、
まず CloseFractionOnTP = 1.0（フルクローズ）から開始し、
回転率とDDのバランスを見ながら Tp*Pct, BaseDcaPctPerDay, MaxSymbolExposurePct をチューニングしていく。

