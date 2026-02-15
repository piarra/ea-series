#property strict
#property description "NM3: XAUUSD mean-reversion EA with staged entries and mandatory filters"

#include <Trade/Trade.mqh>

struct Series
{
   bool   active;
   int    direction;   // 1=BUY, -1=SELL
   double total_lots;
   double avg_price;
   int    level;       // 1..4
};

struct EconEvent
{
   datetime time;
   string   name;
};

input ENUM_TIMEFRAMES InpTimeframe           = PERIOD_H4;
input int             InpEMAPeriod           = 50;
input int             InpATRPeriod           = 14;

input double          InpRiskPercent         = 0.7;
input double          InpSafetyFactor        = 0.8;
input double          InpKappaSL             = 2.5;

input double          InpMaxTotalLots        = 0.30;

input double          InpUnitWeight1         = 1.0;
input double          InpUnitWeight2         = 2.0;
input double          InpUnitWeight3         = 3.0;
input double          InpUnitWeight4         = 4.0;

input double          InpZEntry              = 2.0;
input double          InpZStep               = 0.5;
input double          InpZExit               = 0.3;
input double          InpZStop               = 4.0;

input double          InpSlopeThreshold      = 0.15;

input int             InpATRPercentilePeriod = 200;
input double          InpATRPercentile       = 90.0;

input int             InpEventWindowMinutes  = 120;
input string          InpEventFileName       = "events.csv";
input int             InpTimerSeconds        = 60;

input long            InpMagicNumber         = 3003;
input int             InpDeviationPoints     = 30;

CTrade     trade;
Series     current_series;
EconEvent  event_list[];

double     unit_weights[4];

double     ema_current = 0.0;
double     ema_past = 0.0;
double     atr_current = 0.0;
double     z_score = 0.0;
double     normalized_slope = 0.0;

double     atr_history[];
int        atr_history_count = 0;

datetime   last_tf_bar_time = 0;

int        ema_handle = INVALID_HANDLE;
int        atr_handle = INVALID_HANDLE;

int      PrecisionFromStep(double step);
string   Trim(string text);
void     PushAtrHistory(double value);
void     SeedAtrHistory();
void     ManageSeries();
void     UpdateIndicators();
void     EvaluateEntry();
void     EvaluateAdd();
void     EvaluateExit();
double   CalculateUnitSize();
bool     CheckFilters(double new_lot, string &reason);
bool     ExposureCheck(double new_lot);
double   SumLots();
bool     LoadEvents();
bool     IsEventBlocked(string &detail);
double   CalculatePercentile(double &array[], int size, double percentile);
double   NormalizeLot(double lot);
bool     ExecuteMarketOrder(ENUM_POSITION_TYPE type, double lot, string tag);
bool     CloseSeriesPositions(string reason);

int OnInit()
{
   unit_weights[0] = InpUnitWeight1;
   unit_weights[1] = InpUnitWeight2;
   unit_weights[2] = InpUnitWeight3;
   unit_weights[3] = InpUnitWeight4;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   ema_handle = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(ema_handle == INVALID_HANDLE)
   {
      Print("OnInit: failed to create EMA handle");
      return INIT_FAILED;
   }

   atr_handle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("OnInit: failed to create ATR handle");
      return INIT_FAILED;
   }

   int hist_size = MathMax(1, InpATRPercentilePeriod);
   ArrayResize(atr_history, hist_size);
   ArrayInitialize(atr_history, 0.0);
   atr_history_count = 0;

   SeedAtrHistory();
   LoadEvents();
   ManageSeries();
   UpdateIndicators();

   EventSetTimer(MathMax(1, InpTimerSeconds));

   PrintFormat("OnInit complete: symbol=%s timeframe=%d, atr_history=%d", _Symbol, InpTimeframe, atr_history_count);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(ema_handle != INVALID_HANDLE)
      IndicatorRelease(ema_handle);
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);

   PrintFormat("OnDeinit: reason=%d", reason);
}

void OnTick()
{
   ManageSeries();
   UpdateIndicators();

   if(atr_current <= 0.0)
      return;

   if(!current_series.active)
   {
      EvaluateEntry();
      return;
   }

   EvaluateAdd();
   EvaluateExit();
}

void OnTimer()
{
   LoadEvents();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_DELETE ||
      trans.type == TRADE_TRANSACTION_DEAL_UPDATE)
   {
      ManageSeries();
   }
}

int PrecisionFromStep(double step)
{
   if(step <= 0.0)
      return 2;

   int precision = 0;
   double scaled = step;
   while(precision < 8 && MathAbs(MathRound(scaled) - scaled) > 1e-8)
   {
      scaled *= 10.0;
      precision++;
   }
   return precision;
}

string Trim(string text)
{
   StringTrimLeft(text);
   StringTrimRight(text);
   return text;
}

void PushAtrHistory(double value)
{
   if(value <= 0.0)
      return;

   int max_size = MathMax(1, InpATRPercentilePeriod);
   if(ArraySize(atr_history) != max_size)
      ArrayResize(atr_history, max_size);

   if(atr_history_count < max_size)
   {
      atr_history[atr_history_count] = value;
      atr_history_count++;
      return;
   }

   for(int i = 1; i < max_size; i++)
      atr_history[i - 1] = atr_history[i];

   atr_history[max_size - 1] = value;
}

void SeedAtrHistory()
{
   int required = MathMax(1, InpATRPercentilePeriod);
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);

   int copied = CopyBuffer(atr_handle, 0, 1, required, atr_buffer);
   if(copied <= 0)
   {
      Print("SeedAtrHistory: failed to copy ATR history");
      return;
   }

   for(int i = copied - 1; i >= 0; i--)
      PushAtrHistory(atr_buffer[i]);
}

void ManageSeries()
{
   current_series.active = false;
   current_series.direction = 0;
   current_series.total_lots = 0.0;
   current_series.avg_price = 0.0;
   current_series.level = 0;

   int count = 0;
   double weighted_sum = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL)
         continue;

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;
      if(!current_series.active)
      {
         current_series.active = true;
         current_series.direction = dir;
      }
      else if(current_series.direction != dir)
      {
         Print("ManageSeries: opposite-direction positions detected; keeping first direction only.");
         continue;
      }

      double lot = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);

      current_series.total_lots += lot;
      weighted_sum += (price * lot);
      count++;
   }

   if(current_series.active && current_series.total_lots > 0.0)
   {
      current_series.avg_price = weighted_sum / current_series.total_lots;
      current_series.level = MathMin(4, count);
   }
}

void UpdateIndicators()
{
   if(ema_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
      return;

   double ema_buffer[];
   double atr_buffer[];

   ArraySetAsSeries(ema_buffer, true);
   ArraySetAsSeries(atr_buffer, true);

   int ema_copied = CopyBuffer(ema_handle, 0, 0, 2, ema_buffer);
   int atr_copied = CopyBuffer(atr_handle, 0, 0, 1, atr_buffer);

   if(ema_copied < 2 || atr_copied < 1)
      return;

   ema_current = ema_buffer[0];
   ema_past = ema_buffer[1];
   atr_current = atr_buffer[0];

   double price = iClose(_Symbol, InpTimeframe, 0);
   if(price <= 0.0)
   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
         price = (tick.bid + tick.ask) * 0.5;
   }

   if(atr_current > 0.0)
   {
      z_score = (price - ema_current) / atr_current;
      normalized_slope = (ema_current - ema_past) / atr_current;
   }

   datetime bar_time = iTime(_Symbol, InpTimeframe, 0);
   if(bar_time > 0 && bar_time != last_tf_bar_time)
   {
      last_tf_bar_time = bar_time;
      PushAtrHistory(atr_current);

      PrintFormat("UpdateIndicators: z=%.3f atr=%.5f slope=%.3f", z_score, atr_current, normalized_slope);
   }
}

void EvaluateEntry()
{
   double unit = CalculateUnitSize();
   if(unit <= 0.0)
   {
      Print("EvaluateEntry: unit lot <= 0; skip entry");
      return;
   }

   if(z_score <= -InpZEntry)
   {
      double lot = NormalizeLot(unit * unit_weights[0]);
      if(lot <= 0.0)
      {
         Print("EvaluateEntry BUY: normalized lot <= 0");
         return;
      }

      string filter_reason;
      if(!CheckFilters(lot, filter_reason))
      {
         PrintFormat("EvaluateEntry BUY blocked: %s", filter_reason);
         return;
      }

      ExecuteMarketOrder(POSITION_TYPE_BUY, lot, "entry");
      return;
   }

   if(z_score >= InpZEntry)
   {
      double lot = NormalizeLot(unit * unit_weights[0]);
      if(lot <= 0.0)
      {
         Print("EvaluateEntry SELL: normalized lot <= 0");
         return;
      }

      string filter_reason;
      if(!CheckFilters(lot, filter_reason))
      {
         PrintFormat("EvaluateEntry SELL blocked: %s", filter_reason);
         return;
      }

      ExecuteMarketOrder(POSITION_TYPE_SELL, lot, "entry");
   }
}

void EvaluateAdd()
{
   if(!current_series.active)
      return;

   if(current_series.level >= 4)
      return;

   double unit = CalculateUnitSize();
   if(unit <= 0.0)
      return;

   int next_idx = current_series.level; // level=1 => use weight2
   if(next_idx < 0 || next_idx > 3)
      return;

   double lot = NormalizeLot(unit * unit_weights[next_idx]);
   if(lot <= 0.0)
      return;

   double threshold = InpZEntry + (current_series.level * InpZStep);

   if(current_series.direction > 0)
   {
      if(z_score > -threshold)
         return;

      string filter_reason;
      if(!CheckFilters(lot, filter_reason))
      {
         PrintFormat("EvaluateAdd BUY blocked: %s", filter_reason);
         return;
      }

      ExecuteMarketOrder(POSITION_TYPE_BUY, lot, "add");
      return;
   }

   if(current_series.direction < 0)
   {
      if(z_score < threshold)
         return;

      string filter_reason;
      if(!CheckFilters(lot, filter_reason))
      {
         PrintFormat("EvaluateAdd SELL blocked: %s", filter_reason);
         return;
      }

      ExecuteMarketOrder(POSITION_TYPE_SELL, lot, "add");
   }
}

void EvaluateExit()
{
   if(!current_series.active)
      return;

   if(current_series.direction > 0)
   {
      if(z_score >= -InpZExit)
      {
         CloseSeriesPositions("take-profit");
         return;
      }

      if(z_score <= -InpZStop)
      {
         CloseSeriesPositions("stop-loss");
         return;
      }
   }

   if(current_series.direction < 0)
   {
      if(z_score <= InpZExit)
      {
         CloseSeriesPositions("take-profit");
         return;
      }

      if(z_score >= InpZStop)
      {
         CloseSeriesPositions("stop-loss");
         return;
      }
   }
}

double CalculateUnitSize()
{
   if(atr_current <= 0.0)
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   double risk_money = equity * InpRiskPercent / 100.0;
   double delta_sl = atr_current * InpKappaSL;

   if(contract_size <= 0.0 || delta_sl <= 0.0)
      return 0.0;

   double unit = risk_money / (10.0 * contract_size * delta_sl);
   unit *= InpSafetyFactor;

   return NormalizeLot(unit);
}

bool CheckFilters(double new_lot, string &reason)
{
   if(atr_history_count < InpATRPercentilePeriod)
   {
      reason = StringFormat("ATR history insufficient (%d)", atr_history_count);
      return false;
   }

   double pctl = CalculatePercentile(atr_history, atr_history_count, InpATRPercentile);
   if(pctl > 0.0 && atr_current > pctl)
   {
      reason = StringFormat("ATR filter: atr=%.5f > p%.1f=%.5f", atr_current, InpATRPercentile, pctl);
      return false;
   }

   if(MathAbs(normalized_slope) > InpSlopeThreshold)
   {
      reason = StringFormat("slope filter: |%.3f| > %.3f", normalized_slope, InpSlopeThreshold);
      return false;
   }

   string event_detail;
   if(IsEventBlocked(event_detail))
   {
      reason = StringFormat("event filter: %s", event_detail);
      return false;
   }

   if(!ExposureCheck(new_lot))
   {
      reason = StringFormat("exposure filter: total=%.2f new=%.2f max=%.2f",
                            SumLots(), new_lot, InpMaxTotalLots);
      return false;
   }

   reason = "ok";
   return true;
}

bool ExposureCheck(double new_lot)
{
   return (SumLots() + new_lot <= InpMaxTotalLots + 1e-9);
}

double SumLots()
{
   double total = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      total += PositionGetDouble(POSITION_VOLUME);
   }

   return total;
}

bool LoadEvents()
{
   ArrayResize(event_list, 0);

   int handle = FileOpen(InpEventFileName, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("LoadEvents: unable to open %s (error=%d)", InpEventFileName, GetLastError());
      return false;
   }

   int count = 0;
   while(!FileIsEnding(handle))
   {
      string time_txt = Trim(FileReadString(handle));
      string event_name = Trim(FileReadString(handle));

      if(time_txt == "")
         continue;

      if(StringFind(StringToLower(time_txt), "datetime") >= 0)
         continue;

      datetime ev_time = StringToTime(time_txt);
      if(ev_time <= 0)
         continue;

      int idx = ArraySize(event_list);
      ArrayResize(event_list, idx + 1);
      event_list[idx].time = ev_time;
      event_list[idx].name = event_name;
      count++;
   }

   FileClose(handle);
   PrintFormat("LoadEvents: loaded %d events from %s", count, InpEventFileName);
   return true;
}

bool IsEventBlocked(string &detail)
{
   if(InpEventWindowMinutes <= 0)
      return false;

   datetime now = TimeCurrent();
   int window_sec = InpEventWindowMinutes * 60;

   for(int i = 0; i < ArraySize(event_list); i++)
   {
      long diff = (long)MathAbs((double)(event_list[i].time - now));
      if(diff <= window_sec)
      {
         detail = StringFormat("%s at %s within %d min",
                               event_list[i].name,
                               TimeToString(event_list[i].time, TIME_DATE | TIME_MINUTES),
                               InpEventWindowMinutes);
         return true;
      }
   }

   return false;
}

double CalculatePercentile(double &array[], int size, double percentile)
{
   if(size <= 0)
      return 0.0;

   double temp[];
   ArrayResize(temp, size);
   for(int i = 0; i < size; i++)
      temp[i] = array[i];

   ArraySort(temp);

   double p = MathMax(0.0, MathMin(100.0, percentile));
   if(size == 1)
      return temp[0];

   double rank = (p / 100.0) * (size - 1);
   int lower = (int)MathFloor(rank);
   int upper = (int)MathCeil(rank);

   if(lower == upper)
      return temp[lower];

   double weight = rank - lower;
   return temp[lower] + (temp[upper] - temp[lower]) * weight;
}

double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0 || max_lot <= 0.0)
      return 0.0;

   double normalized = MathFloor(lot / step) * step;
   if(normalized > max_lot)
      normalized = max_lot;

   if(normalized < min_lot)
      return 0.0;

   return NormalizeDouble(normalized, PrecisionFromStep(step));
}

bool ExecuteMarketOrder(ENUM_POSITION_TYPE type, double lot, string tag)
{
   if(lot <= 0.0)
      return false;

   bool ok = false;
   if(type == POSITION_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol);
   else if(type == POSITION_TYPE_SELL)
      ok = trade.Sell(lot, _Symbol);

   if(!ok)
   {
      PrintFormat("Order failed (%s): type=%d lot=%.2f retcode=%d",
                  tag, type, lot, trade.ResultRetcode());
      return false;
   }

   PrintFormat("Order success (%s): type=%d lot=%.2f z=%.3f atr=%.5f slope=%.3f",
               tag, type, lot, z_score, atr_current, normalized_slope);

   ManageSeries();
   return true;
}

bool CloseSeriesPositions(string reason)
{
   bool any = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(trade.PositionClose(ticket))
      {
         any = true;
      }
      else
      {
         PrintFormat("Close failed (%s): ticket=%I64u retcode=%d", reason, ticket, trade.ResultRetcode());
      }
   }

   if(any)
      PrintFormat("CloseSeriesPositions: reason=%s z=%.3f", reason, z_score);

   ManageSeries();
   return any;
}
