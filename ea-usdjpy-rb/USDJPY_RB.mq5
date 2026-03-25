//+------------------------------------------------------------------+
//| USDJPY Asia Range Breakout EA (MT5 / MQL5)                      |
//| - JST-fixed Asia range build                                    |
//| - Breakout trigger by touch on live tick                        |
//| - Single position by symbol+magic                               |
//| - ATR-based SL, fixed RR TP, break-even shift                   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

input string InpSymbol                    = "";          // blank = chart symbol
input ulong  InpMagic                     = 20260325;
input double InpRiskPercent               = 0.5;         // risk per trade (% of balance)

input int    InpRangeStartJST_Hour        = 0;
input int    InpRangeStartJST_Minute      = 0;
input int    InpRangeEndJST_Hour          = 8;
input int    InpRangeEndJST_Minute        = 59;
input ENUM_TIMEFRAMES InpBreakoutTF       = PERIOD_M5;

input int    InpATRPeriod                 = 14;
input double InpSL_ATR_Mult               = 1.0;
input double InpRR                        = 1.5;
input double InpBreakEvenAtR              = 1.0;
input int    InpBreakEvenOffsetPoints     = 0;

input int    InpMaxSpreadPoints           = 30;
input bool   InpUseTradeDays              = true;        // Monday-Friday (JST)
input bool   InpUseOneTradePerDay         = true;
input int    InpEntryCutoffJST_Hour       = 11;          // -1 to disable
input int    InpEntryCutoffJST_Minute     = 30;
input double InpMinBreakATRMult           = 0.10;        // min breakout distance from range edge
input double InpMinRangeATRMult           = 0.80;        // skip too narrow Asia range
input bool   InpLogTradeDetails           = true;

CTrade trade;
string SYM = "";
int g_atr_handle = INVALID_HANDLE;

struct DayState
{
   int date_key;
   bool range_initialized;
   double range_high;
   double range_low;
   bool breakout_high_touched;
   bool breakout_low_touched;
   bool entered_today;
};

DayState g_day = {0, false, 0.0, 0.0, false, false, false};
ulong g_be_ticket = 0;
bool g_be_done = false;

int g_entry_count = 0;
int g_closed_count = 0;
int g_win_count = 0;
int g_loss_count = 0;
double g_peak_equity = 0.0;
double g_max_dd_abs = 0.0;
double g_max_dd_pct = 0.0;

// ------------------------------------------------------------------
datetime ToJST(datetime gmt_time)
{
   return gmt_time + 9 * 3600;
}

void JSTStruct(datetime gmt_time, MqlDateTime &out_dt)
{
   TimeToStruct(ToJST(gmt_time), out_dt);
}

int JSTDateKey(datetime gmt_time)
{
   MqlDateTime dt;
   JSTStruct(gmt_time, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

int JSTMinuteOfDay(datetime gmt_time)
{
   MqlDateTime dt;
   JSTStruct(gmt_time, dt);
   return dt.hour * 60 + dt.min;
}

bool IsTradeDayJST(datetime gmt_time)
{
   if(!InpUseTradeDays)
      return true;

   MqlDateTime dt;
   JSTStruct(gmt_time, dt);
   return (dt.day_of_week >= 1 && dt.day_of_week <= 5);
}

int RangeStartMinute()
{
   return InpRangeStartJST_Hour * 60 + InpRangeStartJST_Minute;
}

int RangeEndMinute()
{
   return InpRangeEndJST_Hour * 60 + InpRangeEndJST_Minute;
}

bool IsMinuteInRangeWindow(int minute_of_day)
{
   int start = RangeStartMinute();
   int endv = RangeEndMinute();

   if(start <= endv)
      return (minute_of_day >= start && minute_of_day <= endv);

   return (minute_of_day >= start || minute_of_day <= endv);
}

bool IsAfterRangeWindow(int minute_of_day)
{
   int endv = RangeEndMinute();
   return (minute_of_day > endv);
}

bool EntryCutoffOK(int minute_of_day)
{
   if(InpEntryCutoffJST_Hour < 0)
      return true;

   int cutoff = InpEntryCutoffJST_Hour * 60 + InpEntryCutoffJST_Minute;
   return (minute_of_day <= cutoff);
}

void UpdateDrawdown()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return;

   if(g_peak_equity <= 0.0 || equity > g_peak_equity)
      g_peak_equity = equity;

   double dd_abs = g_peak_equity - equity;
   if(dd_abs > g_max_dd_abs)
      g_max_dd_abs = dd_abs;

   if(g_peak_equity > 0.0)
   {
      double dd_pct = (dd_abs / g_peak_equity) * 100.0;
      if(dd_pct > g_max_dd_pct)
         g_max_dd_pct = dd_pct;
   }
}

void ResetDayState(int new_date_key)
{
   g_day.date_key = new_date_key;
   g_day.range_initialized = false;
   g_day.range_high = 0.0;
   g_day.range_low = 0.0;
   g_day.breakout_high_touched = false;
   g_day.breakout_low_touched = false;
   g_day.entered_today = false;
}

bool SpreadOK(double bid, double ask)
{
   double point = SymbolInfoDouble(SYM, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   double spread_points = (ask - bid) / point;
   return (spread_points <= InpMaxSpreadPoints);
}

bool GetMyPosition(
   ulong &ticket,
   long &type,
   double &price_open,
   double &sl,
   double &tp,
   double &volume)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!PositionGetTicket(i))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != SYM)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      type = (long)PositionGetInteger(POSITION_TYPE);
      price_open = PositionGetDouble(POSITION_PRICE_OPEN);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      volume = PositionGetDouble(POSITION_VOLUME);
      return true;
   }

   ticket = 0;
   type = -1;
   price_open = 0.0;
   sl = 0.0;
   tp = 0.0;
   volume = 0.0;
   return false;
}

double NormalizeVolume(double volume)
{
   double min_lot = SymbolInfoDouble(SYM, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(SYM, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(SYM, SYMBOL_VOLUME_STEP);

   if(min_lot <= 0.0 || max_lot <= 0.0 || step <= 0.0)
      return 0.0;

   volume = MathMax(min_lot, MathMin(max_lot, volume));
   volume = MathFloor(volume / step) * step;

   int lot_digits = 0;
   double v = step;
   while(v < 1.0 && lot_digits < 8)
   {
      v *= 10.0;
      lot_digits++;
   }

   return NormalizeDouble(volume, lot_digits);
}

double CalcLotsByRisk(double sl_distance_price)
{
   if(sl_distance_price <= 0.0)
      return 0.0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return 0.0;

   double risk_money = balance * (InpRiskPercent / 100.0);
   if(risk_money <= 0.0)
      return 0.0;

   double tick_size = SymbolInfoDouble(SYM, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(SYM, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   double loss_per_lot = (sl_distance_price / tick_size) * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;

   double raw_lots = risk_money / loss_per_lot;
   return NormalizeVolume(raw_lots);
}

double GetATR()
{
   if(g_atr_handle == INVALID_HANDLE)
      return 0.0;

   double buf[];
   if(CopyBuffer(g_atr_handle, 0, 0, 1, buf) != 1)
      return 0.0;

   return buf[0];
}

void UpdateAsiaRange(double bid, double ask, datetime now_gmt)
{
   int minute_of_day = JSTMinuteOfDay(now_gmt);
   if(!IsMinuteInRangeWindow(minute_of_day))
      return;

   if(!g_day.range_initialized)
   {
      g_day.range_initialized = true;
      g_day.range_high = ask;
      g_day.range_low = bid;
      return;
   }

   if(ask > g_day.range_high)
      g_day.range_high = ask;
   if(bid < g_day.range_low)
      g_day.range_low = bid;
}

void ManageBreakEven(double bid, double ask)
{
   ulong ticket;
   long pos_type;
   double price_open, sl, tp, volume;
   bool has_pos = GetMyPosition(ticket, pos_type, price_open, sl, tp, volume);

   if(!has_pos)
   {
      g_be_ticket = 0;
      g_be_done = false;
      return;
   }

   if(ticket != g_be_ticket)
   {
      g_be_ticket = ticket;
      g_be_done = false;
   }

   if(g_be_done)
      return;

   double point = SymbolInfoDouble(SYM, SYMBOL_POINT);
   if(point <= 0.0)
      return;

   double stop_level_points = (double)SymbolInfoInteger(SYM, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_dist = stop_level_points * point;

   if(pos_type == POSITION_TYPE_BUY)
   {
      if(sl <= 0.0)
         return;

      double one_r = price_open - sl;
      if(one_r <= 0.0)
         return;

      double trigger_profit = one_r * InpBreakEvenAtR;
      double current_profit = bid - price_open;
      if(current_profit < trigger_profit)
         return;

      double new_sl = price_open + InpBreakEvenOffsetPoints * point;
      if((bid - new_sl) < min_stop_dist)
         new_sl = bid - min_stop_dist;
      new_sl = NormalizeDouble(new_sl, (int)SymbolInfoInteger(SYM, SYMBOL_DIGITS));

      if(new_sl <= sl)
      {
         g_be_done = true;
         return;
      }

      if(trade.PositionModify(ticket, new_sl, tp))
         g_be_done = true;
   }
   else if(pos_type == POSITION_TYPE_SELL)
   {
      if(sl <= 0.0)
         return;

      double one_r = sl - price_open;
      if(one_r <= 0.0)
         return;

      double trigger_profit = one_r * InpBreakEvenAtR;
      double current_profit = price_open - ask;
      if(current_profit < trigger_profit)
         return;

      double new_sl = price_open - InpBreakEvenOffsetPoints * point;
      if((new_sl - ask) < min_stop_dist)
         new_sl = ask + min_stop_dist;
      new_sl = NormalizeDouble(new_sl, (int)SymbolInfoInteger(SYM, SYMBOL_DIGITS));

      if(new_sl >= sl)
      {
         g_be_done = true;
         return;
      }

      if(trade.PositionModify(ticket, new_sl, tp))
         g_be_done = true;
   }
}

bool PlaceBreakoutOrder(bool is_buy, double bid, double ask, double atr)
{
   if(atr <= 0.0)
      return false;

   double point = SymbolInfoDouble(SYM, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   double stop_level_points = (double)SymbolInfoInteger(SYM, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_dist = stop_level_points * point;

   double sl_dist = atr * InpSL_ATR_Mult;
   if(sl_dist < min_stop_dist)
      sl_dist = min_stop_dist;
   if(sl_dist <= 0.0)
      return false;

   int digits = (int)SymbolInfoInteger(SYM, SYMBOL_DIGITS);

   double entry = is_buy ? ask : bid;
   double sl = is_buy ? (entry - sl_dist) : (entry + sl_dist);
   double tp = is_buy ? (entry + sl_dist * InpRR) : (entry - sl_dist * InpRR);

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lots = CalcLotsByRisk(MathAbs(entry - sl));
   if(lots <= 0.0)
      return false;

   bool ok = false;
   if(is_buy)
      ok = trade.Buy(lots, SYM, 0.0, sl, tp, "USDJPY_RB_BUY");
   else
      ok = trade.Sell(lots, SYM, 0.0, sl, tp, "USDJPY_RB_SELL");

   if(ok)
   {
      if(InpLogTradeDetails)
      {
         PrintFormat(
            "[RB_ENTRY] side=%s lots=%.2f entry=%.5f sl=%.5f tp=%.5f atr=%.5f range_high=%.5f range_low=%.5f",
            (is_buy ? "BUY" : "SELL"),
            lots,
            entry,
            sl,
            tp,
            atr,
            g_day.range_high,
            g_day.range_low
         );
      }
      if(InpUseOneTradePerDay)
         g_day.entered_today = true;
      return true;
   }

   PrintFormat("Order failed. retcode=%d", trade.ResultRetcode());
   return false;
}

void CheckBreakoutAndEnter(double bid, double ask, datetime now_gmt)
{
   if(!g_day.range_initialized)
      return;

   int minute_of_day = JSTMinuteOfDay(now_gmt);
   if(!IsAfterRangeWindow(minute_of_day))
      return;
   if(!EntryCutoffOK(minute_of_day))
      return;

   if(!IsTradeDayJST(now_gmt))
      return;

   if(InpUseOneTradePerDay && g_day.entered_today)
      return;

   ulong ticket;
   long pos_type;
   double po, sl, tp, vol;
   if(GetMyPosition(ticket, pos_type, po, sl, tp, vol))
      return;

   if(!SpreadOK(bid, ask))
      return;

   if(g_day.range_high <= g_day.range_low)
      return;

   double atr = GetATR();
   if(atr <= 0.0)
      return;

   double range_width = g_day.range_high - g_day.range_low;
   if(range_width < atr * InpMinRangeATRMult)
      return;

   double min_break_dist = atr * InpMinBreakATRMult;

   // Breakout is defined by touch on live tick.
   if(!g_day.breakout_high_touched && ask >= (g_day.range_high + min_break_dist))
   {
      g_day.breakout_high_touched = true;
      PlaceBreakoutOrder(true, bid, ask, atr);
      return;
   }

   if(!g_day.breakout_low_touched && bid <= (g_day.range_low - min_break_dist))
   {
      g_day.breakout_low_touched = true;
      PlaceBreakoutOrder(false, bid, ask, atr);
      return;
   }
}

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal_ticket = trans.deal;
   if(deal_ticket == 0 || !HistoryDealSelect(deal_ticket))
      return;

   string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(deal_symbol != SYM || (ulong)deal_magic != InpMagic)
      return;

   ENUM_DEAL_ENTRY entry_type = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   long reason = HistoryDealGetInteger(deal_ticket, DEAL_REASON);
   double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
   double volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   long position_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
   datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);

   if(entry_type == DEAL_ENTRY_IN)
   {
      g_entry_count++;
      if(InpLogTradeDetails)
      {
         PrintFormat(
            "[RB_ENTRY_FILL] time=%s position_id=%I64d deal=%I64u price=%.5f volume=%.2f reason=%d entries=%d",
            TimeToString(deal_time, TIME_DATE | TIME_SECONDS),
            position_id,
            deal_ticket,
            price,
            volume,
            (int)reason,
            g_entry_count
         );
      }
      return;
   }

   if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_OUT_BY)
   {
      double net_profit =
         HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
         HistoryDealGetDouble(deal_ticket, DEAL_SWAP) +
         HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

      g_closed_count++;
      if(net_profit > 0.0)
         g_win_count++;
      else
         g_loss_count++;

      if(InpLogTradeDetails)
      {
         PrintFormat(
            "[RB_EXIT] time=%s position_id=%I64d deal=%I64u net=%.2f reason=%d closed=%d wins=%d losses=%d",
            TimeToString(deal_time, TIME_DATE | TIME_SECONDS),
            position_id,
            deal_ticket,
            net_profit,
            (int)reason,
            g_closed_count,
            g_win_count,
            g_loss_count
         );
      }
   }
}

int OnInit()
{
   SYM = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;

   if(!SymbolSelect(SYM, true))
   {
      Print("Failed to select symbol: ", SYM);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((long)InpMagic);

   g_atr_handle = iATR(SYM, InpBreakoutTF, InpATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle.");
      return INIT_FAILED;
   }

   ResetDayState(JSTDateKey(TimeGMT()));
   g_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_max_dd_abs = 0.0;
   g_max_dd_pct = 0.0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   double win_rate = (g_closed_count > 0) ? (100.0 * g_win_count / g_closed_count) : 0.0;
   PrintFormat(
      "[RB_STATS] entries=%d,wins=%d,losses=%d,win_rate=%.2f,max_dd=%.2f,max_dd_pct=%.2f",
      g_entry_count,
      g_win_count,
      g_loss_count,
      win_rate,
      g_max_dd_abs,
      g_max_dd_pct
   );

   if(g_atr_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atr_handle);
      g_atr_handle = INVALID_HANDLE;
   }
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(SYM, tick))
      return;

   datetime now_gmt = TimeGMT();
   int date_key = JSTDateKey(now_gmt);
   if(date_key != g_day.date_key)
      ResetDayState(date_key);

   UpdateDrawdown();
   UpdateAsiaRange(tick.bid, tick.ask, now_gmt);
   ManageBreakEven(tick.bid, tick.ask);
   CheckBreakoutAndEnter(tick.bid, tick.ask, now_gmt);
}
