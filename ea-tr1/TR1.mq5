#property copyright "Aki"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input int    MagicNumber       = 310001;
input double BaseLot           = 0.10;
input double BaseProfitPips    = 10.0;   // 利確幅 (pips)
input int    FastEmaPeriod     = 20;
input int    SlowEmaPeriod     = 50;
input int    ConfirmBarsStartup = 3;     // 起動時に確認する過去バー数
input bool   EnterOnInit       = true;   // 起動直後に即エントリーするか
input double MaxSpreadPoints   = 40;     // スプレッド上限 (ポイント)
input double LossCutPips       = 20.0;   // 強制損切り・反転の閾値 (pips)
input int    SyntheticBarSec   = 10;     // オンメモリ足の秒数（例:10秒）
input int    SlippagePoints    = 20;
input string TradeComment      = "TR1";

enum TrendDirection
{
  TREND_NONE = 0,
  TREND_BUY  = 1,
  TREND_SELL = -1
};

CTrade trade;

datetime g_last_close_time = 0;

// 30秒バー生成用
datetime g_curr_slot_start = 0;
double   g_bar_open = 0, g_bar_high = 0, g_bar_low = 0, g_bar_close = 0;
int      g_bar_count = 0;
double   g_fast_ema = 0, g_slow_ema = 0;
int      g_trend_history[];
bool     g_startup_done = false;

// pip換算 (5桁/3桁は10ポイント = 1pip)
int PipSizeInPoints()
{
  if (_Digits == 3 || _Digits == 5)
    return 10;
  return 1;
}

int VolumeDigits()
{
  double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if (step <= 0)
    return 2; // fallback

  // Convert volume step (e.g., 0.01) to number of decimal places
  int digits = (int)MathRound(-MathLog(step) / MathLog(10.0));
  if (digits < 0) digits = 0;
  if (digits > 8) digits = 8;
  return digits;
}

double ProfitThresholdPoints()
{
  return BaseProfitPips * PipSizeInPoints();
}

double LossCutThresholdPoints()
{
  return LossCutPips * PipSizeInPoints();
}

// オンメモリの短期足（SyntheticBarSec秒）を構築し、EMAを手計算する
void UpdateEmaOnClose(double closePrice)
{
  double kFast = 2.0 / (FastEmaPeriod + 1.0);
  double kSlow = 2.0 / (SlowEmaPeriod + 1.0);

  if (g_bar_count <= 1)
  {
    g_fast_ema = closePrice;
    g_slow_ema = closePrice;
  }
  else
  {
    g_fast_ema = kFast * closePrice + (1.0 - kFast) * g_fast_ema;
    g_slow_ema = kSlow * closePrice + (1.0 - kSlow) * g_slow_ema;
  }

  TrendDirection dir = (g_fast_ema >= g_slow_ema) ? TREND_BUY : TREND_SELL;

  int sz = ArraySize(g_trend_history);
  ArrayResize(g_trend_history, sz + 1);
  g_trend_history[sz] = dir;

  Print(__FUNCTION__, ": bar#", g_bar_count, " close=", DoubleToString(closePrice, _Digits),
        " fastEma=", DoubleToString(g_fast_ema, _Digits),
        " slowEma=", DoubleToString(g_slow_ema, _Digits),
        " dir=", dir);
}

void FinalizeSyntheticBar()
{
  g_bar_count++;
  UpdateEmaOnClose(g_bar_close);
}

void StartNewSyntheticBar(datetime slot, double price)
{
  g_curr_slot_start = slot;
  g_bar_open = g_bar_high = g_bar_low = g_bar_close = price;
}

void UpdateSyntheticBar()
{
  double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  datetime now = TimeCurrent();
  int sec = MathMax(1, SyntheticBarSec);
  datetime slot = now - (now % sec);

  if (g_curr_slot_start == 0)
  {
    StartNewSyntheticBar(slot, price);
    return;
  }

  if (slot == g_curr_slot_start)
  {
    g_bar_high = MathMax(g_bar_high, price);
    g_bar_low  = MathMin(g_bar_low,  price);
    g_bar_close = price;
    return;
  }

  // スロットが進んだら前バーを確定して新バー開始
  FinalizeSyntheticBar();
  StartNewSyntheticBar(slot, price);
}

TrendDirection DetectTrendConfirmed(int bars)
{
  if (bars <= 1)
    return DetectTrend();

  int sz = ArraySize(g_trend_history);
  if (sz == 0)
    return DetectTrend();

  if (bars > sz)
    bars = sz;

  int buy_count = 0;
  int sell_count = 0;
  for (int i = sz - bars; i < sz; i++)
  {
    if (g_trend_history[i] == TREND_BUY)
      buy_count++;
    else
      sell_count++;
  }

  if (buy_count > sell_count)
  {
    Print(__FUNCTION__, ": confirmed BUY on ", bars, " bars (buy=", buy_count, ", sell=", sell_count, ")");
    return TREND_BUY;
  }
  if (sell_count > buy_count)
  {
    Print(__FUNCTION__, ": confirmed SELL on ", bars, " bars (buy=", buy_count, ", sell=", sell_count, ")");
    return TREND_SELL;
  }

  TrendDirection tie = DetectTrend();
  Print(__FUNCTION__, ": tie -> fallback to last bar trend=", tie, " (buy=", buy_count, ", sell=", sell_count, ")");
  return tie;
}

TrendDirection DetectTrend()
{
  int sz = ArraySize(g_trend_history);
  if (sz == 0)
  {
    Print(__FUNCTION__, ": no history, default BUY");
    return TREND_BUY;
  }

  TrendDirection dir = (TrendDirection)g_trend_history[sz - 1];
  Print(__FUNCTION__, ": last dir=", dir, " bar#", g_bar_count);
  return dir;
}

bool HasOurPosition(int &type, double &price)
{
  type = -1;
  price = 0.0;

  if (!PositionSelect(_Symbol))
    return false;

  long magic = PositionGetInteger(POSITION_MAGIC);
  if (magic != MagicNumber)
    return false;

  type = (int)PositionGetInteger(POSITION_TYPE); // POSITION_TYPE_BUY / POSITION_TYPE_SELL
  price = PositionGetDouble(POSITION_PRICE_OPEN);
  return true;
}

bool OpenPosition(TrendDirection dir)
{
  ENUM_ORDER_TYPE orderType = (dir == TREND_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  double lot = NormalizeDouble(BaseLot, VolumeDigits());
  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(SlippagePoints);

  bool ok = trade.PositionOpen(_Symbol, orderType, lot, 0, 0, 0, TradeComment);
  if (ok)
  {
  }
  else
  {
    PrintFormat("Open failed: %d", GetLastError());
  }
  return ok;
}

bool ClosePosition()
{
  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(SlippagePoints);

  bool ok = trade.PositionClose(_Symbol);
  if (!ok)
  {
    PrintFormat("Close failed: %d", GetLastError());
  }
  else
  {
    g_last_close_time = TimeCurrent();
  }
  return ok;
}

bool SpreadTooWide()
{
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double spread_points = (ask - bid) / _Point;
  return (spread_points > MaxSpreadPoints);
}

double CurrentProfitPoints(int posType, double entryPrice)
{
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  if (posType == POSITION_TYPE_BUY)
    return (bid - entryPrice) / _Point;
  else
    return (entryPrice - ask) / _Point;
}

bool TryManagePosition()
{
  if (g_bar_count == 0)
  {
    Print(__FUNCTION__, ": skip - no synthetic bars yet");
    return false;
  }

  int posType;
  double entryPrice;
  if (!HasOurPosition(posType, entryPrice))
  {
    Print(__FUNCTION__, ": skip - no position");
    return false;
  }

  // 利確判定
  double profit_points = CurrentProfitPoints(posType, entryPrice);
  if (profit_points >= ProfitThresholdPoints())
  {
    ClosePosition();
    Print(__FUNCTION__, ": take profit points=", profit_points);
    return true;
  }

  // 強制損切り＆即反転
  if (profit_points <= -LossCutThresholdPoints())
  {
    ClosePosition();
    TrendDirection newDir = DetectTrend();
    Print(__FUNCTION__, ": losscut and reverse profit=", profit_points, " newDir=", newDir);
    OpenPosition(newDir);
    return true;
  }

  // トレンド反転で即損切り
  TrendDirection nowTrend = DetectTrend();
  int entryDir = (posType == POSITION_TYPE_BUY) ? TREND_BUY : TREND_SELL;
  if (nowTrend != entryDir)
  {
    ClosePosition();
    Print(__FUNCTION__, ": trend reversed, entryDir=", entryDir, " nowTrend=", nowTrend, " -> reverse");
    OpenPosition(nowTrend);
    return true;
  }

  Print(__FUNCTION__, ": hold - profit_points=", profit_points, " dir=", entryDir, " trend=", nowTrend);
  return false;
}

void TryStartupEntry()
{
  if (!EnterOnInit)
  {
    Print(__FUNCTION__, ": skip - EnterOnInit=false");
    return;
  }

  int dummyType;
  double dummyPrice;
  if (HasOurPosition(dummyType, dummyPrice))
  {
    Print(__FUNCTION__, ": skip - already have position type=", dummyType, " price=", dummyPrice);
    return;
  }

  if (SpreadTooWide())
  {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread_points = (ask - bid) / _Point;
    Print(__FUNCTION__, ": skip - spread too wide (points)=", DoubleToString(spread_points, 1), " limit=", MaxSpreadPoints);
    return;
  }

  int needed = MathMax(MathMax(FastEmaPeriod, SlowEmaPeriod), ConfirmBarsStartup);
  if (g_bar_count < needed)
  {
    Print(__FUNCTION__, ": skip - bars not ready count=", g_bar_count, " needed=", needed);
    return; // 30秒バーが不足
  }

  TrendDirection dir = DetectTrendConfirmed(ConfirmBarsStartup);
  Print(__FUNCTION__, ": startup enter dir=", dir);
  if (OpenPosition(dir))
    g_startup_done = true;
}

void TryEnterIfFlat()
{
  // クローズ直後の 1 秒待ち
  if (g_last_close_time != 0 && (TimeCurrent() - g_last_close_time) < 1)
  {
    Print(__FUNCTION__, ": skip - cool down after close");
    return;
  }

  if (g_bar_count == 0)
  {
    Print(__FUNCTION__, ": skip - no synthetic bars yet");
    return;
  }

  int dummyType;
  double dummyPrice;
  if (HasOurPosition(dummyType, dummyPrice))
  {
    Print(__FUNCTION__, ": skip - already have position type=", dummyType, " price=", dummyPrice);
    return;
  }

  if (SpreadTooWide())
  {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread_points = (ask - bid) / _Point;
    Print(__FUNCTION__, ": skip - spread too wide (points)=", DoubleToString(spread_points, 1), " limit=", MaxSpreadPoints);
    return;
  }

  TrendDirection dir = DetectTrend();
  Print(__FUNCTION__, ": enter dir=", dir);
  OpenPosition(dir);
}

int OnInit()
{
  g_curr_slot_start = 0;
  g_bar_count = 0;
  g_fast_ema = g_slow_ema = 0;
  ArrayResize(g_trend_history, 0);
  g_startup_done = false;

  trade.SetExpertMagicNumber(MagicNumber);
  return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
  UpdateSyntheticBar();

  int needed_start = MathMax(MathMax(FastEmaPeriod, SlowEmaPeriod), ConfirmBarsStartup);
  if (!g_startup_done && EnterOnInit && g_bar_count >= needed_start)
  {
    TryStartupEntry();
  }

  TryManagePosition();
  TryEnterIfFlat();
}
