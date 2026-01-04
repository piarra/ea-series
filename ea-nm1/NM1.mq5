#property strict
#property version   "000.130"

#include <Trade/Trade.mqh>

namespace NM1
{
enum { kMaxLevels = 20 };
const int kAtrBasePeriod = 14;
const int kLotDigits = 2;
const double kMinLot = 0.01;
const double kMaxLot = 100.0;
}

input int MagicNumber = 202507;
input int SlippagePoints = 4;
input int StartDelaySeconds = 5;
input int GridStepPoints = 250;
input bool GridStepAuto = true;
input double AtrMultiplier = 1.2;
input bool SafetyMode = true;
input bool SafeStopMode = false;
input double SafeK = 2.0;
input double SafeSlopeK = 0.3;
input double BaseLot = 0.01;
input double ProfitBase = 1.0;
input double ProfitStep = 0.1;
input int MaxLevels = 20;
input int RestartDelaySeconds = 1;
input int NanpinSleepSeconds = 10;
input bool UseAsyncClose = true;
input int CloseRetryCount = 3;
input int CloseRetryDelayMs = 200;
input double StopBuyLimitPrice = 4000.0;
input double StopBuyLimitLot = 0.01;

struct BasketInfo
{
  int count;
  double volume;
  double avg_price;
  double min_price;
  double max_price;
};

CTrade trade;
CTrade close_trade;
datetime start_time = 0;
bool initial_started = false;
double lot_seq[NM1::kMaxLevels];
datetime last_buy_close_time = 0;
datetime last_sell_close_time = 0;
datetime last_buy_nanpin_time = 0;
datetime last_sell_nanpin_time = 0;
int prev_buy_count = 0;
int prev_sell_count = 0;
int atr_handle = INVALID_HANDLE;
bool safety_active = false;

bool IsTradingTime()
{
  return true;
}

double NormalizeLot(double lot)
{
  double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  if (step <= 0.0)
    step = 0.01;
  if (minlot <= 0.0)
    minlot = NM1::kMinLot;
  if (maxlot <= 0.0)
    maxlot = NM1::kMaxLot;
  lot = MathMax(minlot, MathMin(maxlot, lot));
  double steps = MathFloor(lot / step + 0.0000001);
  return NormalizeDouble(steps * step, NM1::kLotDigits);
}

int EffectiveMaxLevels()
{
  int levels = MaxLevels;
  if (levels < 1)
    levels = 1;
  if (levels > NM1::kMaxLevels)
    levels = NM1::kMaxLevels;
  return levels;
}

void BuildLotSequence()
{
  int levels = EffectiveMaxLevels();
  lot_seq[0] = BaseLot;
  if (levels > 1)
    lot_seq[1] = BaseLot;
  for (int i = 2; i < levels; ++i)
  {
    lot_seq[i] = lot_seq[i - 1] + lot_seq[i - 2];
  }
  for (int i = 0; i < levels; ++i)
  {
    lot_seq[i] = NormalizeLot(lot_seq[i]);
  }
}

int OnInit()
{
  start_time = TimeCurrent();
  initial_started = false;
  BuildLotSequence();
  if (GridStepAuto || SafetyMode)
    atr_handle = iATR(_Symbol, _Period, NM1::kAtrBasePeriod);

  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(SlippagePoints);
  int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  close_trade.SetExpertMagicNumber(MagicNumber);
  close_trade.SetDeviationInPoints(SlippagePoints);
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  close_trade.SetAsyncMode(UseAsyncClose);
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  if (atr_handle != INVALID_HANDLE)
    IndicatorRelease(atr_handle);
  atr_handle = INVALID_HANDLE;
}

double GetAtrBase()
{
  if (atr_handle == INVALID_HANDLE)
    return 0.0;
  double buffer[];
  if (CopyBuffer(atr_handle, 0, 5, 50, buffer) < 50)
    return 0.0;
  double sum = 0.0;
  for (int i = 0; i < 50; ++i)
    sum += buffer[i];
  return sum / 50.0;
}

double GetCurrentAtr()
{
  if (atr_handle == INVALID_HANDLE)
    return 0.0;
  double buffer[];
  if (CopyBuffer(atr_handle, 0, 0, 1, buffer) <= 0)
    return 0.0;
  return buffer[0];
}

double GetAtrSlope()
{
  if (atr_handle == INVALID_HANDLE)
    return 0.0;

  double buf[3];
  if (CopyBuffer(atr_handle, 0, 0, 3, buf) < 3)
    return 0.0;

  return buf[0] - buf[2];
}

void CollectBasketInfo(BasketInfo &buy, BasketInfo &sell)
{
  buy.count = 0;
  buy.volume = 0.0;
  buy.avg_price = 0.0;
  buy.min_price = 0.0;
  buy.max_price = 0.0;
  sell.count = 0;
  sell.volume = 0.0;
  sell.avg_price = 0.0;
  sell.min_price = 0.0;
  sell.max_price = 0.0;

  double buy_value = 0.0;
  double sell_value = 0.0;

  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;

    int type = (int)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);

    if (type == POSITION_TYPE_BUY)
    {
      if (buy.count == 0)
      {
        buy.min_price = price;
        buy.max_price = price;
      }
      else
      {
        buy.min_price = MathMin(buy.min_price, price);
        buy.max_price = MathMax(buy.max_price, price);
      }
      buy.count++;
      buy.volume += volume;
      buy_value += volume * price;
    }
    else if (type == POSITION_TYPE_SELL)
    {
      if (sell.count == 0)
      {
        sell.min_price = price;
        sell.max_price = price;
      }
      else
      {
        sell.min_price = MathMin(sell.min_price, price);
        sell.max_price = MathMax(sell.max_price, price);
      }
      sell.count++;
      sell.volume += volume;
      sell_value += volume * price;
    }
  }

  if (buy.volume > 0.0)
    buy.avg_price = buy_value / buy.volume;
  if (sell.volume > 0.0)
    sell.avg_price = sell_value / sell.volume;
}

void CloseBasket(ENUM_POSITION_TYPE type)
{
  ulong tickets[];
  int count = 0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    ArrayResize(tickets, ++count);
    tickets[count - 1] = ticket;
  }

  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    while (attempts <= CloseRetryCount)
    {
      if (close_trade.PositionClose(tickets[i]))
      {
        closed = true;
        break;
      }
      attempts++;
      if (attempts <= CloseRetryCount && CloseRetryDelayMs > 0)
        Sleep(CloseRetryDelayMs);
    }
    if (!closed)
    {
      PrintFormat("Close failed after retries: ticket=%I64u retcode=%d %s",
                  tickets[i], close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
}

bool TryOpen(ENUM_ORDER_TYPE order_type, double lot)
{
  lot = NormalizeLot(lot);
  if (lot <= 0.0)
    return false;
  bool ok = false;
  if (order_type == ORDER_TYPE_BUY)
    ok = trade.Buy(lot, _Symbol);
  else if (order_type == ORDER_TYPE_SELL)
    ok = trade.Sell(lot, _Symbol);

  if (!ok)
  {
    PrintFormat("Order failed: type=%d lot=%.2f retcode=%d %s",
                order_type, lot, trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }
  return ok;
}

bool ShouldStopOnBuyLimit(double limit_price, double limit_lot)
{
  if (limit_price <= 0.0 || limit_lot <= 0.0)
    return false;
  double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  if (point <= 0.0)
    point = 0.00001;
  double price_tol = point * 0.5;
  double norm_lot = NormalizeLot(limit_lot);
  for (int i = OrdersTotal() - 1; i >= 0; --i)
  {
    ulong ticket = OrderGetTicket(i);
    if (!OrderSelect(ticket))
      continue;
    long magic = OrderGetInteger(ORDER_MAGIC);
    if (magic != MagicNumber && magic != 0)
      continue;
    if (OrderGetString(ORDER_SYMBOL) != _Symbol)
      continue;
    if ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT)
      continue;
    double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
    double price = OrderGetDouble(ORDER_PRICE_OPEN);
    if (MathAbs(volume - norm_lot) <= 0.0000001 && MathAbs(price - limit_price) <= price_tol)
      return true;
  }
  return false;
}

double ProfitOffsetByCount(int count)
{
  if (count <= 2)
    return ProfitBase;
  return ProfitBase + (count - 2) * ProfitStep;
}

double PipPointSize()
{
  int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  if (digits == 3 || digits == 5)
    return point * 10.0;
  return point;
}

bool CanRestart(datetime last_close_time)
{
  if (last_close_time == 0)
    return true;
  return (TimeCurrent() - last_close_time) >= RestartDelaySeconds;
}

bool CanNanpin(datetime last_nanpin_time)
{
  if (last_nanpin_time == 0)
    return true;
  return (TimeCurrent() - last_nanpin_time) >= NanpinSleepSeconds;
}

void OnTick()
{
  BasketInfo buy, sell;
  CollectBasketInfo(buy, sell);
  if (ShouldStopOnBuyLimit(StopBuyLimitPrice, StopBuyLimitLot))
  {
    PrintFormat("EA stopped: buy limit %.2f lots at price %.2f detected.", StopBuyLimitLot, StopBuyLimitPrice);
    ExpertRemove();
    return;
  }

  if (prev_buy_count > 0 && buy.count == 0)
  {
    last_buy_close_time = TimeCurrent();
    last_buy_nanpin_time = 0;
  }
  if (prev_sell_count > 0 && sell.count == 0)
  {
    last_sell_close_time = TimeCurrent();
    last_sell_nanpin_time = 0;
  }

  bool attempted_initial = false;
  if (!initial_started && (TimeCurrent() - start_time) >= StartDelaySeconds)
  {
    if (buy.count == 0 && sell.count == 0 && IsTradingTime())
    {
      bool opened = false;
      opened |= TryOpen(ORDER_TYPE_BUY, lot_seq[0]);
      opened |= TryOpen(ORDER_TYPE_SELL, lot_seq[0]);
      if (opened)
        initial_started = true;
      attempted_initial = true;
    }
  }

  if (attempted_initial)
  {
    prev_buy_count = buy.count;
    prev_sell_count = sell.count;
    return;
  }

  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double grid_step = GridStepPoints * PipPointSize();
  double atr_base = 0.0;
  if (GridStepAuto)
  {
    atr_base = GetAtrBase();
    if (atr_base > 0.0)
      grid_step = atr_base * AtrMultiplier;
  }
  else if (SafetyMode)
  {
    atr_base = GetAtrBase();
  }

  bool allow_nanpin = true;
  bool safety_triggered = false;
  if (SafetyMode && atr_base > 0.0)
  {
    double atr_now = GetCurrentAtr();
    if (atr_now >= atr_base * SafeK)
    {
      safety_triggered = true;
      if (!SafeStopMode)
        allow_nanpin = false;
    }
    double atr_slope = GetAtrSlope();
    if (atr_slope > atr_base * SafeSlopeK)
    {
      safety_triggered = true;
      if (!SafeStopMode)
        allow_nanpin = false;
    }
  }
  if (SafetyMode)
  {
    bool prev = safety_active;
    safety_active = safety_triggered || !allow_nanpin;
    if (safety_active != prev)
    {
      string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      if (safety_active)
        PrintFormat("Safety mode ON: %s", ts);
      else
        PrintFormat("Safety mode OFF: %s", ts);
    }
  }

  if (SafeStopMode && safety_triggered)
  {
    if (buy.count > 0)
      CloseBasket(POSITION_TYPE_BUY);
    if (sell.count > 0)
      CloseBasket(POSITION_TYPE_SELL);
    return;
  }

  if (buy.count > 0)
  {
    double target = buy.avg_price + ProfitOffsetByCount(buy.count);
    if (bid >= target)
      CloseBasket(POSITION_TYPE_BUY);
  }

  if (sell.count > 0)
  {
    double target = sell.avg_price - ProfitOffsetByCount(sell.count);
    if (ask <= target)
      CloseBasket(POSITION_TYPE_SELL);
  }

  if (IsTradingTime())
  {
    if (initial_started)
    {
      if (buy.count == 0 && CanRestart(last_buy_close_time))
        TryOpen(ORDER_TYPE_BUY, lot_seq[0]);
      if (sell.count == 0 && CanRestart(last_sell_close_time))
        TryOpen(ORDER_TYPE_SELL, lot_seq[0]);
    }

    int levels = EffectiveMaxLevels();
    if (buy.count > 0 && buy.count < levels)
    {
      // Buy orders fill at ask, so compare ask to the grid.
      if (allow_nanpin && CanNanpin(last_buy_nanpin_time) && ask <= buy.min_price - grid_step)
      {
        if (TryOpen(ORDER_TYPE_BUY, lot_seq[buy.count]))
          last_buy_nanpin_time = TimeCurrent();
      }
    }

    if (sell.count > 0 && sell.count < levels)
    {
      // Sell orders fill at bid, so compare bid to the grid.
      if (allow_nanpin && CanNanpin(last_sell_nanpin_time) && bid >= sell.max_price + grid_step)
      {
        if (TryOpen(ORDER_TYPE_SELL, lot_seq[sell.count]))
          last_sell_nanpin_time = TimeCurrent();
      }
    }
  }

  prev_buy_count = buy.count;
  prev_sell_count = sell.count;
}
