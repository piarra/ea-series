# plan.md — MT5 EA: XAUUSD ヘッジファンド型 平均回帰＋段階建て

## 0. 目的

MetaTrader 5 用 Expert Advisor (EA) として、XAUUSDの平均回帰戦略を実装する。

特徴：

- z-score ベースの平均回帰エントリー
- 線形ロットスケーリング（1u,2u,3u,4u）
- シリーズ最大損失を固定（リスク一定化）
- 以下4つのフィルタを必須実装：

  1. ATRパーセンタイル（p90）ボラ急拡大フィルタ
  2. EMA傾きトレンドフィルタ
  3. 経済指標イベントフィルタ
  4. ネットエクスポージャ上限

---

## 1. EA基本仕様

### 1.1 対象

- Platform: MetaTrader 5
- Language: MQL5
- Symbol: XAUUSD
- Timeframe: デフォルト PERIOD_H4（externで変更可能）

---

### 1.2 EA構造（必須関数）

実装必須：

- OnInit()
- OnDeinit()
- OnTick()
- OnTimer()（イベントフィルタ用）
- OnTradeTransaction()（ポジション管理）

補助関数：

- UpdateIndicators()
- EvaluateEntry()
- EvaluateAdd()
- EvaluateExit()
- CalculateUnitSize()
- CheckFilters()
- ManageSeries()

---

## 2. インジケータ仕様

### 2.1 EMA

使用関数：

iMA()

パラメータ：

- period = InpEMAPeriod
- method = MODE_EMA
- applied_price = PRICE_CLOSE

保存変数：

double ema_current;
double ema_past;

---

### 2.2 ATR

使用関数：

iATR()

保存：

double atr_current;

ATR履歴配列：

double atr_history[MaxATRHistory];

---

### 2.3 z-score

定義：

z = (price - ema_current) / atr_current

---

### 2.4 EMA slope（正規化）

raw_slope = (ema_current - ema_past)

normalized_slope = raw_slope / atr_current

---

### 2.5 ATR percentile

関数：

double CalculatePercentile(double &array[], int size, double percentile);

---

## 3. リスク・ロット計算

### 3.1 入力パラメータ（extern）

input double InpRiskPercent = 0.7;
input double InpSafetyFactor = 0.8;
input double InpKappaSL = 2.5;

input double InpMaxTotalLots = 0.30;

input double InpUnitWeights[4] = {1,2,3,4};

---

### 3.2 口座情報取得

double equity = AccountInfoDouble(ACCOUNT_EQUITY);

double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

---

### 3.3 シリーズ最大損失

double risk_money = equity * InpRiskPercent / 100.0;

double delta_sl = atr_current * InpKappaSL;

---

### 3.4 unit size 計算

u = risk_money / (10 * contract_size * delta_sl)

u *= InpSafetyFactor

u = NormalizeLot(u)

---

### 3.5 ロット正規化

使用：

SYMBOL_VOLUME_MIN  
SYMBOL_VOLUME_MAX  
SYMBOL_VOLUME_STEP  

関数：

double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor(lot / step) * step;
}

---

## 4. Series管理

Seriesとは同方向ポジション群。

構造体：

struct Series
{
   bool active;
   int direction;
   double total_lots;
   double avg_price;
   int level;
};

グローバル：

Series current_series;

---

## 5. エントリーロジック

入力：

input double InpZEntry = 2.0;
input double InpZStep = 0.5;
input double InpZExit = 0.3;
input double InpZStop = 4.0;

---

### 5.1 新規エントリー条件

if current_series.active == false

BUY:

z <= -InpZEntry

SELL:

z >= InpZEntry

AND

CheckFilters() == true

AND

ExposureCheck() == true

---

## 6. 追加エントリー

current_series.level < 4

BUY:

z <= -(InpZEntry + level * InpZStep)

SELL:

z >= +(InpZEntry + level * InpZStep)

---

ロット：

lot = unit * weight[level]

---

## 7. 利確

BUY:

z >= -InpZExit

SELL:

z <= InpZExit

→ Close all

---

## 8. 損切り

BUY:

z <= -InpZStop

SELL:

z >= InpZStop

→ Close all

---

## 9. フィルタ実装

## 9.1 ボラフィルタ

input int InpATRPercentilePeriod = 200;
input double InpATRPercentile = 90;

double atr_p90 = CalculatePercentile(atr_history)

if atr_current > atr_p90

return false

---

## 9.2 トレンドフィルタ

input double InpSlopeThreshold = 0.15;

if abs(normalized_slope) > threshold

return false

---

## 9.3 イベントフィルタ

実装方法：

CSVファイル：

Files/events.csv

形式：

datetime,event_name

例：

2026.03.20 21:00,FOMC
2026.04.10 21:30,CPI

読み込み：

FileOpen()

判定：

if abs(event_time - TimeCurrent()) < InpEventWindowMinutes * 60

return false

---

input int InpEventWindowMinutes = 120;

---

## 9.4 エクスポージャフィルタ

double total = SumLots()

if total + new_lot > InpMaxTotalLots

return false

---

## 10. 注文実行

使用：

CTrade trade;

BUY:

trade.Buy(lot,_Symbol)

SELL:

trade.Sell(lot,_Symbol)

Close:

trade.PositionClose(_Symbol)

---

## 11. OnTickフロー

OnTick():

1. UpdateIndicators()

2. if current_series.active == false

   EvaluateEntry()

3. else

   EvaluateAdd()

   EvaluateExit()

---

## 12. 状態更新

OnTradeTransaction()

ポジション確認：

PositionsTotal()

PositionGetSymbol()

PositionGetDouble(POSITION_VOLUME)

PositionGetDouble(POSITION_PRICE_OPEN)

---

## 13. ログ

Print():

- z
- atr
- slope
- lot
- filter result
- entry/add/exit reason

---

## 14. externパラメータ一覧

input int InpEMAPeriod = 50;
input int InpATRPeriod = 14;

input double InpRiskPercent = 0.7;

input double InpZEntry = 2.0;
input double InpZStep = 0.5;
input double InpZExit = 0.3;
input double InpZStop = 4.0;

input double InpSlopeThreshold = 0.15;

input int InpATRPercentilePeriod = 200;

input double InpMaxTotalLots = 0.30;

input int InpEventWindowMinutes = 120;

---

## 15. 完了条件（Definition of Done）

- MT5 Strategy Testerで正常動作
- 4段ロットスケーリングが正しく実行
- フィルタが機能
- max lots制限が機能
- イベント時間に新規エントリーされない
- コンパイルエラーゼロ
