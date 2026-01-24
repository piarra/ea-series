#property strict
#property version "0.1"

#include <Trade/Trade.mqh>

input group "COMMON"
input string SymbolName = "BTCUSD";
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;
input int MagicNumber = 223344;
input int Slippage = 50;
input string CommentTag = "DCA_SCALP_BTC";
input int MaxSpreadPoints = 0;

input group "RISK"
input double BaseDcaPctPerDay = 1.0;
input double MaxDailyInvestPct = 3.0;
input double MaxSymbolExposurePct = 25.0;
input double MaxTotalExposurePct = 50.0;
input double MaxMarginUsagePct = 10.0;
input double MaxDrawdownCycleInvestPct = 15.0;
input double MinNotionalPerTrade = 10.0;

input group "INDICATORS"
input int AtrPeriod = 14;
input double VolLowThreshold = 100.0;
input double VolHighThreshold = 300.0;
input int EmaLen = 200;
input double VolLowMult = 0.8;
input double VolMidMult = 1.0;
input double VolHighMult = 1.2;

input group "TP/SL"
input double TpLowVolPct = 0.5;
input double TpMidVolPct = 0.8;
input double TpHighVolPct = 1.2;
input double CloseFractionOnTP = 1.0;
input int MaxHoldBars = 24;
input double MaxAdversePct = 5.0;

input group "OPERATION"
input int ActiveHoursPerDay = 24;
input int RecentHighLookbackBars = 500;
input double DailyProfitTargetPct = 3.0;
input double DailyLossLimitPct = 5.0;
input bool CloseAllOnDailyLoss = true;

CTrade trade;

int atrHandle = INVALID_HANDLE;
int emaHandle = INVALID_HANDLE;
datetime lastProcessedBarTime = 0;
int lastDayKey = 0;
double todayInvestedNotional = 0.0;
double cycleInvestedNotional = 0.0;
double cycleRecentHigh = 0.0;
double dailyStartEquity = 0.0;
double dailyStartBalance = 0.0;
double lastAtrValue = 0.0;
double lastEmaValue = 0.0;
bool dailyEntryBlocked = false;
bool dailyTradingHalted = false;

int DayKey(datetime t)
{
  return (int)(TimeYear(t) * 10000 + TimeMonth(t) * 100 + TimeDay(t));
}

double NormalizeVolume(double volume)
{
  double step = SymbolInfoDouble(SymbolName, SYMBOL_VOLUME_STEP);
  double minLot = SymbolInfoDouble(SymbolName, SYMBOL_VOLUME_MIN);
  double maxLot = SymbolInfoDouble(SymbolName, SYMBOL_VOLUME_MAX);
  if (step <= 0.0)
    return 0.0;
  double lots = MathFloor(volume / step) * step;
  if (lots < minLot)
    return 0.0;
  if (lots > maxLot)
    lots = maxLot;
  int digits = (int)SymbolInfoInteger(SymbolName, SYMBOL_VOLUME_DIGITS);
  return NormalizeDouble(lots, digits);
}

double PositionNotional(double volume, double price)
{
  double contractSize = SymbolInfoDouble(SymbolName, SYMBOL_TRADE_CONTRACT_SIZE);
  return volume * contractSize * price;
}

bool IsOurPosition()
{
  if (!PositionSelectByTicket(PositionGetTicket(0)))
    return false;
  return true;
}

double SumSymbolExposure()
{
  double total = 0.0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    string sym = PositionGetString(POSITION_SYMBOL);
    if (sym != SymbolName)
      continue;
    if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
      continue;
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = SymbolInfoDouble(SymbolName, SYMBOL_BID);
    total += PositionNotional(volume, price);
  }
  return total;
}

double SumTotalExposure()
{
  double total = 0.0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_BID);
    double contractSize = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_CONTRACT_SIZE);
    total += volume * contractSize * price;
  }
  return total;
}

bool UpdateIndicators()
{
  if (atrHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
    return false;
  double atrBuf[1];
  double emaBuf[1];
  if (CopyBuffer(atrHandle, 0, 1, 1, atrBuf) != 1)
    return false;
  if (CopyBuffer(emaHandle, 0, 1, 1, emaBuf) != 1)
    return false;
  lastAtrValue = atrBuf[0];
  lastEmaValue = emaBuf[0];
  return true;
}

void ResetDailyState(datetime nowTime)
{
  todayInvestedNotional = 0.0;
  dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
  dailyEntryBlocked = false;
  dailyTradingHalted = false;
  lastDayKey = DayKey(nowTime);
}

void ClosePositionByTicket(ulong ticket, double volume)
{
  if (!PositionSelectByTicket(ticket))
    return;
  double posVolume = PositionGetDouble(POSITION_VOLUME);
  if (volume <= 0.0 || volume >= posVolume)
  {
    trade.PositionClose(ticket);
    return;
  }
  trade.PositionClosePartial(ticket, volume);
}

void CloseAllPositions()
{
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetString(POSITION_SYMBOL) != SymbolName)
      continue;
    if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    trade.PositionClose(ticket);
  }
}

void CloseByFraction(double fraction)
{
  if (fraction <= 0.0)
    return;
  double totalVolume = 0.0;
  int count = 0;
  ulong tickets[];
  datetime times[];
  double volumes[];
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetString(POSITION_SYMBOL) != SymbolName)
      continue;
    if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
      continue;
    ArrayResize(tickets, count + 1);
    ArrayResize(times, count + 1);
    ArrayResize(volumes, count + 1);
    tickets[count] = ticket;
    times[count] = (datetime)PositionGetInteger(POSITION_TIME);
    volumes[count] = PositionGetDouble(POSITION_VOLUME);
    totalVolume += volumes[count];
    count++;
  }
  if (totalVolume <= 0.0)
    return;
  double target = totalVolume * fraction;
  int sorted = 0;
  while (sorted < count - 1)
  {
    int minIndex = sorted;
    for (int j = sorted + 1; j < count; ++j)
    {
      if (times[j] < times[minIndex])
        minIndex = j;
    }
    if (minIndex != sorted)
    {
      datetime t = times[sorted];
      times[sorted] = times[minIndex];
      times[minIndex] = t;
      ulong tk = tickets[sorted];
      tickets[sorted] = tickets[minIndex];
      tickets[minIndex] = tk;
      double v = volumes[sorted];
      volumes[sorted] = volumes[minIndex];
      volumes[minIndex] = v;
    }
    sorted++;
  }
  double remaining = target;
  for (int i = 0; i < count && remaining > 0.0; ++i)
  {
    double closeVol = MathMin(remaining, volumes[i]);
    ClosePositionByTicket(tickets[i], closeVol);
    remaining -= closeVol;
  }
}

void CloseExpiredPositions(datetime nowTime)
{
  if (MaxHoldBars <= 0)
    return;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetString(POSITION_SYMBOL) != SymbolName)
      continue;
    if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
      continue;
    datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
    int entryShift = iBarShift(SymbolName, Timeframe, entryTime, true);
    if (entryShift < 0)
      continue;
    if (entryShift >= MaxHoldBars)
      trade.PositionClose(ticket);
  }
}

void UpdateCycleHigh(double price)
{
  if (cycleRecentHigh <= 0.0)
  {
    cycleRecentHigh = price;
    return;
  }
  double prevHigh = cycleRecentHigh;
  if (price > cycleRecentHigh)
    cycleRecentHigh = price;
  if (price > prevHigh * 1.05)
  {
    cycleRecentHigh = price;
    cycleInvestedNotional = 0.0;
  }
}

double CalcAvgEntry(double &totalVolume)
{
  totalVolume = 0.0;
  double weighted = 0.0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetString(POSITION_SYMBOL) != SymbolName)
      continue;
    if ((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
      continue;
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    totalVolume += volume;
    weighted += volume * price;
  }
  if (totalVolume <= 0.0)
    return 0.0;
  return weighted / totalVolume;
}

bool SpreadTooWide()
{
  if (MaxSpreadPoints <= 0)
    return false;
  long spread = SymbolInfoInteger(SymbolName, SYMBOL_SPREAD);
  return spread > MaxSpreadPoints;
}

void EvaluateExits()
{
  double totalVolume = 0.0;
  double avgEntry = CalcAvgEntry(totalVolume);
  if (totalVolume <= 0.0 || avgEntry <= 0.0)
    return;
  double bid = SymbolInfoDouble(SymbolName, SYMBOL_BID);
  double tpPct = TpMidVolPct;
  if (lastAtrValue > 0.0)
  {
    if (lastAtrValue < VolLowThreshold)
      tpPct = TpLowVolPct;
    else if (lastAtrValue > VolHighThreshold)
      tpPct = TpHighVolPct;
  }
  double tpPrice = avgEntry * (1.0 + tpPct / 100.0);
  if (bid >= tpPrice)
    CloseByFraction(CloseFractionOnTP);
  double adversePct = (avgEntry - bid) / avgEntry * 100.0;
  if (adversePct >= MaxAdversePct)
    CloseAllPositions();
  CloseExpiredPositions(TimeCurrent());
}

bool CheckDailyStops()
{
  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  if (dailyStartBalance <= 0.0)
    dailyStartBalance = balance;
  double dailyNetPct = (balance - dailyStartBalance) / dailyStartBalance * 100.0;
  if (dailyNetPct >= DailyProfitTargetPct)
    dailyEntryBlocked = true;
  if (dailyNetPct <= -DailyLossLimitPct)
  {
    dailyTradingHalted = true;
    if (CloseAllOnDailyLoss)
      CloseAllPositions();
  }
  return !dailyTradingHalted;
}

void TryEntry(double atrValue, double emaValue)
{
  if (dailyTradingHalted || dailyEntryBlocked)
    return;
  if (SpreadTooWide())
    return;
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  if (equity <= 0.0)
    return;
  double dailyBudget = equity * BaseDcaPctPerDay / 100.0;
  double hourlyBase = dailyBudget / (double)ActiveHoursPerDay;
  double volMult = VolMidMult;
  if (atrValue > 0.0)
  {
    if (atrValue < VolLowThreshold)
      volMult = VolLowMult;
    else if (atrValue > VolHighThreshold)
      volMult = VolHighMult;
  }
  double trendMult = 0.8;
  double price = SymbolInfoDouble(SymbolName, SYMBOL_BID);
  if (price > emaValue)
    trendMult = 1.2;
  double recentHigh = 0.0;
  int idx = iHighest(SymbolName, Timeframe, MODE_HIGH, RecentHighLookbackBars, 1);
  if (idx >= 0)
    recentHigh = iHigh(SymbolName, Timeframe, idx);
  double ddMult = 1.0;
  if (recentHigh > 0.0)
  {
    double drawdownPct = (recentHigh - price) / recentHigh * 100.0;
    if (drawdownPct < 3.0)
      ddMult = 0.7;
    else if (drawdownPct < 7.0)
      ddMult = 1.0;
    else if (drawdownPct < 15.0)
      ddMult = 1.3;
    else
      ddMult = 1.5;
  }
  double rawNotional = hourlyBase * volMult * trendMult * ddMult;
  if (rawNotional < MinNotionalPerTrade)
    return;
  double dailyMax = equity * MaxDailyInvestPct / 100.0;
  double allowableToday = dailyMax - todayInvestedNotional;
  if (allowableToday <= 0.0)
    return;
  rawNotional = MathMin(rawNotional, allowableToday);
  double symbolBudget = equity * MaxSymbolExposurePct / 100.0;
  double symbolExposure = SumSymbolExposure();
  double allowableSym = symbolBudget - symbolExposure;
  if (allowableSym <= 0.0)
    return;
  rawNotional = MathMin(rawNotional, allowableSym);
  double totalBudget = equity * MaxTotalExposurePct / 100.0;
  double totalExposure = SumTotalExposure();
  double allowableTotal = totalBudget - totalExposure;
  if (allowableTotal <= 0.0)
    return;
  rawNotional = MathMin(rawNotional, allowableTotal);
  double cycleBudget = equity * MaxDrawdownCycleInvestPct / 100.0;
  double allowableCycle = cycleBudget - cycleInvestedNotional;
  if (allowableCycle <= 0.0)
    return;
  rawNotional = MathMin(rawNotional, allowableCycle);
  double ask = SymbolInfoDouble(SymbolName, SYMBOL_ASK);
  double contractSize = SymbolInfoDouble(SymbolName, SYMBOL_TRADE_CONTRACT_SIZE);
  double volume = rawNotional / (contractSize * ask);
  volume = NormalizeVolume(volume);
  if (volume <= 0.0)
    return;
  double margin = 0.0;
  if (!OrderCalcMargin(ORDER_TYPE_BUY, SymbolName, volume, ask, margin))
    return;
  double marginUsage = (AccountInfoDouble(ACCOUNT_MARGIN) + margin) / equity * 100.0;
  if (marginUsage > MaxMarginUsagePct)
    return;
  trade.SetDeviationInPoints(Slippage);
  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetComment(CommentTag);
  if (trade.Buy(volume, SymbolName, ask, 0.0, 0.0, CommentTag))
  {
    todayInvestedNotional += rawNotional;
    cycleInvestedNotional += rawNotional;
  }
}

int OnInit()
{
  if (!SymbolSelect(SymbolName, true))
    return INIT_FAILED;
  atrHandle = iATR(SymbolName, Timeframe, AtrPeriod);
  emaHandle = iMA(SymbolName, Timeframe, EmaLen, 0, MODE_EMA, PRICE_CLOSE);
  if (atrHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
    return INIT_FAILED;
  trade.SetExpertMagicNumber(MagicNumber);
  ResetDailyState(TimeCurrent());
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  if (atrHandle != INVALID_HANDLE)
    IndicatorRelease(atrHandle);
  if (emaHandle != INVALID_HANDLE)
    IndicatorRelease(emaHandle);
}

void OnTick()
{
  datetime nowTime = TimeCurrent();
  int key = DayKey(nowTime);
  if (key != lastDayKey)
    ResetDailyState(nowTime);
  CheckDailyStops();
  EvaluateExits();
  datetime barTime = iTime(SymbolName, Timeframe, 0);
  if (barTime == 0)
    return;
  if (barTime != lastProcessedBarTime)
  {
    lastProcessedBarTime = barTime;
    if (UpdateIndicators())
    {
      double price = SymbolInfoDouble(SymbolName, SYMBOL_BID);
      UpdateCycleHigh(price);
      TryEntry(lastAtrValue, lastEmaValue);
    }
  }
}
