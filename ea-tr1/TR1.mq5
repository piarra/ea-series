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
input double MaxSpreadPoints   = 40;     // スプレッド上限 (ポイント)
input int    SlippagePoints    = 20;
input string TradeComment      = "TR1";

enum TrendDirection
{
  TREND_NONE = 0,
  TREND_BUY  = 1,
  TREND_SELL = -1
};

CTrade trade;

datetime g_entry_time      = 0;
int      g_entry_trend     = TREND_NONE;
bool     g_third_checked   = false;
datetime g_last_close_time = 0;

// pip換算 (5桁/3桁は10ポイント = 1pip)
int PipSizeInPoints()
{
  if (_Digits == 3 || _Digits == 5)
    return 10;
  return 1;
}

double ProfitThresholdPoints()
{
  return BaseProfitPips * PipSizeInPoints();
}

TrendDirection DetectTrend()
{
  // 最新確定足(シフト1)のEMAで判定してノイズを減らす
  double fast = iMA(_Symbol, PERIOD_M1, FastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
  double slow = iMA(_Symbol, PERIOD_M1, SlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
  if (fast > slow)
    return TREND_BUY;
  if (fast < slow)
    return TREND_SELL;
  return TREND_NONE;
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
  if (dir == TREND_NONE)
    return false;

  ENUM_ORDER_TYPE orderType = (dir == TREND_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  double lot = NormalizeDouble(BaseLot, (int)SymbolInfoInteger(_Symbol, SYMBOL_VOLUME_DIGITS));
  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(SlippagePoints);

  bool ok = trade.PositionOpen(_Symbol, orderType, lot, 0, 0, 0, TradeComment);
  if (ok)
  {
    g_entry_time = TimeCurrent();
    g_entry_trend = dir;
    g_third_checked = false;
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
    g_entry_time = 0;
    g_entry_trend = TREND_NONE;
    g_third_checked = false;
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

void TryManagePosition()
{
  int posType;
  double entryPrice;
  if (!HasOurPosition(posType, entryPrice))
    return;

  // 利確判定
  double profit_points = CurrentProfitPoints(posType, entryPrice);
  if (profit_points >= ProfitThresholdPoints())
  {
    ClosePosition();
    return;
  }

  // 3本目チェック (約180秒経過時に1回だけ)
  if (!g_third_checked)
  {
    if (g_entry_time > 0 && (TimeCurrent() - g_entry_time) >= 180)
    {
      g_third_checked = true;
      TrendDirection nowTrend = DetectTrend();
      int entryDir = (posType == POSITION_TYPE_BUY) ? TREND_BUY : TREND_SELL;
      if (nowTrend != TREND_NONE && nowTrend != entryDir)
      {
        ClosePosition();
      }
    }
  }
}

void TryEnterIfFlat()
{
  // クローズ直後の 1 秒待ち
  if (g_last_close_time != 0 && (TimeCurrent() - g_last_close_time) < 1)
    return;

  int dummyType;
  double dummyPrice;
  if (HasOurPosition(dummyType, dummyPrice))
    return;

  if (SpreadTooWide())
    return;

  TrendDirection dir = DetectTrend();
  OpenPosition(dir);
}

int OnInit()
{
  trade.SetExpertMagicNumber(MagicNumber);
  return(INIT_SUCCEEDED);
}

void OnTick()
{
  TryManagePosition();
  TryEnterIfFlat();
}
