//+------------------------------------------------------------------+
//| SMT + PVT + Structure Break EA (MT5 / MQL5)                      |
//| Implements:                                                      |
//| 1) SMT (XAUUSD vs XAGUSD)                                        |
//| 2) PVT divergence confirmation                                   |
//| 3) Entry on M5 structure break                                   |
//| Risk: fixed lot, SL beyond last swing, TP by RR                  |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;
CTrade close_trade;

//-------------------- Inputs --------------------
input string InpSymbolGold        = "XAUUSD-m";
input string InpSymbolSilver      = "XAGUSD-m";

input ENUM_TIMEFRAMES InpSMT_TF   = PERIOD_M1; // SMT + PVT confirmation timeframe
input ENUM_TIMEFRAMES InpEntry_TF = PERIOD_M2;  // Entry timeframe (structure break)

input int    InpPivotLeft         = 3;   // Pivot detection left bars
input int    InpPivotRight        = 2;   // Pivot detection right bars
input int    InpLookbackBars      = 400; // History scan bars per TF

input int    InpSetupExpiryBars   = 12;  // Setup validity in Entry TF bars after SMT+PVT align

input double InpFixedLot          = 0.01;
input double InpMinRR             = 2.1; // RR >= 2
input int    InpSL_BufferPoints   = 40;  // buffer in points beyond swing
input double InpSwingTPMultipleOfScalp = 2.0;   // SWING TP distance = SCALP TP distance * N
input bool   InpSwingMoveSLOnScalpTP   = true;  // when SCALP hits TP, move SWING SL to BE +/- offset
input double InpSwingBEOffsetPips      = 10.0;  // offset in pips from entry for SWING BE lock
input double InpSwingTrailDistanceRatio = 0.55; // legacy trailing ratio (currently unused)

input long   InpMagic             = 26021401;
input bool   InpOnePositionOnly   = false;
input bool   InpEnableNewsFilter  = true; // block entry around calendar news
input int    InpNewsMinutesBefore = 4;    // minutes before news
input int    InpNewsMinutesAfter  = 18;   // minutes after news
input string InpNewsBacktestCalendarFile = "economic_calendar_2025_2030.csv"; // MQL_TESTER uses FILE_COMMON

//-------------------- Internal State --------------------
enum SetupDir { SETUP_NONE=0, SETUP_BUY=1, SETUP_SELL=-1 };

SetupDir setup_dir = SETUP_NONE;
datetime setup_time = 0;   // time when setup was armed (Entry TF bar time)
datetime news_last_checked_server_time = 0;
bool news_last_check_blocked = false;
datetime news_last_event_time = 0;
datetime news_last_logged_event_time = 0;
int news_last_calendar_error = 0;
datetime news_backtest_event_times[];
bool news_backtest_calendar_loaded = false;
bool news_backtest_calendar_ready = false;
long next_pair_seq = 1;
ulong swing_trail_tickets[];
double swing_trail_distances[];
bool swing_trail_active[];

//-------------------- Utilities --------------------
bool IsNewBar(const string sym, ENUM_TIMEFRAMES tf, datetime &last_bar_time)
{
   datetime t = iTime(sym, tf, 0);
   if(t == 0) return false;
   if(t != last_bar_time)
   {
      last_bar_time = t;
      return true;
   }
   return false;
}

int DigitsOf(const string sym)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return d;
}

double PointOf(const string sym)
{
   return SymbolInfoDouble(sym, SYMBOL_POINT);
}

double PipSizeOf(const string sym)
{
   double point = PointOf(sym);
   if(point <= 0.0) return 0.00001;

   int digits = DigitsOf(sym);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

double CalcSwingTPFromScalp(const SetupDir dir, const double sl, const double scalp_tp)
{
   double rr = InpMinRR;
   if(rr <= 0.0) return 0.0;

   double entry_ref = (scalp_tp + rr * sl) / (1.0 + rr);
   double scalp_distance = MathAbs(scalp_tp - entry_ref);
   if(scalp_distance <= 0.0) return 0.0;

   double tp_mult = InpSwingTPMultipleOfScalp;
   if(tp_mult <= 0.0) tp_mult = 1.0;
   double swing_distance = scalp_distance * tp_mult;

   if(dir == SETUP_SELL) return entry_ref - swing_distance;
   if(dir == SETUP_BUY)  return entry_ref + swing_distance;
   return 0.0;
}

bool EnsureSymbols()
{
   if(!SymbolSelect(InpSymbolGold, true))  return false;
   if(!SymbolSelect(InpSymbolSilver, true))return false;
   return true;
}

void ResetNewsFilterCache()
{
   news_last_checked_server_time = 0;
   news_last_check_blocked = false;
   news_last_event_time = 0;
   news_last_logged_event_time = 0;
   news_last_calendar_error = 0;
   ArrayResize(news_backtest_event_times, 0);
   news_backtest_calendar_loaded = false;
   news_backtest_calendar_ready = false;
}

int LowerBoundEventTime(const datetime &events[], datetime target)
{
   int left = 0;
   int right = ArraySize(events);
   while(left < right)
   {
      int mid = left + (right - left) / 2;
      if(events[mid] < target)
         left = mid + 1;
      else
         right = mid;
   }
   return left;
}

bool HasBacktestNewsEventInWindow(const datetime &events[], datetime from, datetime to, datetime &hit_time)
{
   int count = ArraySize(events);
   if(count <= 0 || to < from)
      return false;
   int idx = LowerBoundEventTime(events, from);
   if(idx >= 0 && idx < count && events[idx] <= to)
   {
      hit_time = events[idx];
      return true;
   }
   return false;
}

bool LoadBacktestNewsCalendarCsv()
{
   news_backtest_calendar_loaded = true;
   news_backtest_calendar_ready = false;
   ArrayResize(news_backtest_event_times, 0);

   if(StringLen(InpNewsBacktestCalendarFile) == 0)
   {
      Print("News filter backtest CSV file name is empty.");
      return false;
   }

   ResetLastError();
   int fh = FileOpen(InpNewsBacktestCalendarFile, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("News filter backtest CSV open failed: file=%s err=%d",
                  InpNewsBacktestCalendarFile,
                  GetLastError());
      return false;
   }

   const int kCsvColumns = 14;
   for(int c=0; c<kCsvColumns && !FileIsEnding(fh); c++)
      FileReadString(fh); // header

   int capacity = 0;
   int count = 0;

   while(!FileIsEnding(fh))
   {
      string server_time = FileReadString(fh);
      if(FileIsEnding(fh) && StringLen(server_time) == 0)
         break;

      FileReadString(fh); // gmt_time
      FileReadString(fh); // currency
      FileReadString(fh); // event_id
      FileReadString(fh); // value_id
      FileReadString(fh); // importance
      FileReadString(fh); // impact
      FileReadString(fh); // event_name
      FileReadString(fh); // period
      FileReadString(fh); // revision
      FileReadString(fh); // actual
      FileReadString(fh); // forecast
      FileReadString(fh); // previous
      FileReadString(fh); // revised_previous

      datetime event_time = StringToTime(server_time);
      if(event_time <= 0)
         continue;

      if(count >= capacity)
      {
         capacity = (capacity <= 0) ? 512 : (capacity * 2);
         ArrayResize(news_backtest_event_times, capacity);
      }
      news_backtest_event_times[count] = event_time;
      count++;
   }

   FileClose(fh);

   ArrayResize(news_backtest_event_times, count);
   if(count > 1)
      ArraySort(news_backtest_event_times);

   news_backtest_calendar_ready = (count > 0);
   if(!news_backtest_calendar_ready)
   {
      PrintFormat("News filter backtest CSV is empty: file=%s", InpNewsBacktestCalendarFile);
      return false;
   }

   PrintFormat("News filter backtest CSV loaded: file=%s rows=%d",
               InpNewsBacktestCalendarFile,
               count);
   return true;
}

bool IsNewsTimeNowBacktest(datetime from, datetime to, datetime &hit_time)
{
   if(!news_backtest_calendar_loaded)
      LoadBacktestNewsCalendarCsv();
   if(!news_backtest_calendar_ready)
      return false;
   return HasBacktestNewsEventInWindow(news_backtest_event_times, from, to, hit_time);
}

bool IsNewsTimeNow()
{
   if(!InpEnableNewsFilter) return false;

   datetime now_server = TimeTradeServer();
   if(now_server <= 0) now_server = TimeCurrent();
   if(now_server <= 0) return false;

   if(news_last_checked_server_time == now_server)
      return news_last_check_blocked;

   news_last_checked_server_time = now_server;
   news_last_check_blocked = false;
   news_last_event_time = 0;

   int before_min = MathMax(0, InpNewsMinutesBefore);
   int after_min  = MathMax(0, InpNewsMinutesAfter);
   datetime from  = now_server - (datetime)(before_min * 60);
   datetime to    = now_server + (datetime)(after_min * 60);

   if(MQLInfoInteger(MQL_TESTER))
   {
      datetime hit_time = 0;
      if(!IsNewsTimeNowBacktest(from, to, hit_time))
         return false;

      news_last_check_blocked = true;
      news_last_event_time = hit_time;
      if(news_last_logged_event_time != news_last_event_time)
      {
         PrintFormat("Entry blocked by news filter(backtest CSV): server=%s",
                     TimeToString(news_last_event_time, TIME_DATE|TIME_MINUTES));
         news_last_logged_event_time = news_last_event_time;
      }
      return true;
   }

   MqlCalendarValue values[];
   ResetLastError();
   int n = CalendarValueHistory(values, from, to); // no currency filter: all calendar news
   if(n < 0)
   {
      int err = GetLastError();
      if(err != 0 && err != news_last_calendar_error)
      {
         PrintFormat("News filter query failed. err=%d", err);
         news_last_calendar_error = err;
      }
      return false; // fail-open
   }

   news_last_calendar_error = 0;
   if(n <= 0) return false;

   news_last_check_blocked = true;
   news_last_event_time = values[0].time;
   if(news_last_logged_event_time != news_last_event_time)
   {
      Print("Entry blocked by news filter. events=", n,
            " window=", before_min, "m/", after_min, "m");
      news_last_logged_event_time = news_last_event_time;
   }
   return true;
}

int CountMyPositions()
{
   int cnt=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionSelectByTicket(ticket))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         long mg = (long)PositionGetInteger(POSITION_MAGIC);
         if(mg == InpMagic && sym == InpSymbolGold) cnt++;
      }
   }
   return cnt;
}

long NextPairId()
{
   long now_sec = (long)TimeCurrent();
   if(now_sec <= 0) now_sec = (long)TimeLocal();
   long seq = next_pair_seq++;
   if(next_pair_seq > 999) next_pair_seq = 1;
   return now_sec * 1000 + seq;
}

string BuildPairComment(const string role, const long pair_id)
{
   return role + "#" + (string)pair_id;
}

bool ParsePositionRoleAndPairId(const string comment, string &role_out, long &pair_id_out)
{
   role_out = "";
   pair_id_out = 0;

   string tail = "";
   if(StringFind(comment, "SCALP#") == 0)
   {
      role_out = "SCALP";
      tail = StringSubstr(comment, 6);
   }
   else if(StringFind(comment, "SWING#") == 0)
   {
      role_out = "SWING";
      tail = StringSubstr(comment, 6);
   }
   else
   {
      return false;
   }

   if(StringLen(tail) <= 0)
      return false;

   long pair_id = (long)StringToInteger(tail);
   if(pair_id <= 0)
      return false;

   pair_id_out = pair_id;
   return true;
}

bool ClosePositionTicketWithRetry(const ulong ticket)
{
   for(int attempt=0; attempt<3; attempt++)
   {
      if(!PositionSelectByTicket(ticket))
         return true;

      close_trade.SetExpertMagicNumber(InpMagic);
      close_trade.SetDeviationInPoints(20);
      if(close_trade.PositionClose(ticket))
         return true;

      Sleep(50);
   }

   return !PositionSelectByTicket(ticket);
}

bool ClosePairPositionsById(const long pair_id)
{
   ulong tickets[];
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbolGold)
         continue;

      string role = "";
      long pos_pair_id = 0;
      string comment = PositionGetString(POSITION_COMMENT);
      if(!ParsePositionRoleAndPairId(comment, role, pos_pair_id))
         continue;
      if(pos_pair_id != pair_id)
         continue;

      ArrayResize(tickets, count + 1);
      tickets[count] = ticket;
      count++;
   }

   bool all_closed = true;
   for(int i=0; i<count; i++)
   {
      if(!ClosePositionTicketWithRetry(tickets[i]))
         all_closed = false;
   }

   return all_closed;
}

bool HasOpenPairRole(const long pair_id, const string role, const ENUM_POSITION_TYPE type)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbolGold)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
         continue;

      string pos_role = "";
      long pos_pair_id = 0;
      string comment = PositionGetString(POSITION_COMMENT);
      if(!ParsePositionRoleAndPairId(comment, pos_role, pos_pair_id))
         continue;
      if(pos_pair_id == pair_id && pos_role == role)
         return true;
   }
   return false;
}

int FindSwingTrailIndex(const ulong ticket)
{
   int count = ArraySize(swing_trail_tickets);
   for(int i=0; i<count; i++)
   {
      if(swing_trail_tickets[i] == ticket)
         return i;
   }
   return -1;
}

void RemoveSwingTrailAt(const int idx)
{
   int count = ArraySize(swing_trail_tickets);
   if(idx < 0 || idx >= count)
      return;

   for(int i=idx; i<count-1; i++)
   {
      swing_trail_tickets[i] = swing_trail_tickets[i+1];
      swing_trail_distances[i] = swing_trail_distances[i+1];
      swing_trail_active[i] = swing_trail_active[i+1];
   }

   count--;
   ArrayResize(swing_trail_tickets, count);
   ArrayResize(swing_trail_distances, count);
   ArrayResize(swing_trail_active, count);
}

void CleanupSwingTrailState()
{
   int i = 0;
   int count = ArraySize(swing_trail_tickets);
   while(i < count)
   {
      ulong ticket = swing_trail_tickets[i];
      if(!PositionSelectByTicket(ticket))
      {
         RemoveSwingTrailAt(i);
         count = ArraySize(swing_trail_tickets);
         continue;
      }

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic ||
         PositionGetString(POSITION_SYMBOL) != InpSymbolGold)
      {
         RemoveSwingTrailAt(i);
         count = ArraySize(swing_trail_tickets);
         continue;
      }

      string role = "";
      long pair_id = 0;
      string comment = PositionGetString(POSITION_COMMENT);
      if(!ParsePositionRoleAndPairId(comment, role, pair_id) || role != "SWING")
      {
         RemoveSwingTrailAt(i);
         count = ArraySize(swing_trail_tickets);
         continue;
      }

      i++;
   }
}

int EnsureSwingTrailState(const ulong ticket, const double open_price, const double base_sl)
{
   int idx = FindSwingTrailIndex(ticket);
   if(idx >= 0)
      return idx;

   if(open_price <= 0.0 || base_sl <= 0.0)
      return -1;

   double risk = MathAbs(open_price - base_sl);
   if(risk <= 0.0)
      return -1;

   double trail_distance = risk * InpMinRR * InpSwingTrailDistanceRatio;
   double min_distance = PointOf(InpSymbolGold);
   if(min_distance <= 0.0) min_distance = 0.00001;
   if(trail_distance < min_distance)
      trail_distance = min_distance;

   int count = ArraySize(swing_trail_tickets);
   ArrayResize(swing_trail_tickets, count + 1);
   ArrayResize(swing_trail_distances, count + 1);
   ArrayResize(swing_trail_active, count + 1);
   swing_trail_tickets[count] = ticket;
   swing_trail_distances[count] = trail_distance;
   swing_trail_active[count] = false;
   return count;
}

bool UpdatePositionTrailSL(const ulong ticket, const ENUM_POSITION_TYPE type, double requested_sl)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return false;
   if(symbol != InpSymbolGold)
      return false;
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      return false;

   int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stops_level < 0) stops_level = 0;

   double broker_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(broker_point <= 0.0) broker_point = PointOf(symbol);
   if(broker_point <= 0.0) broker_point = 0.00001;

   double price_step = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(price_step <= 0.0) price_step = broker_point;
   if(price_step <= 0.0) price_step = 0.00001;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits < 0) digits = 5;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;

   double stops_dist = stops_level * broker_point;
   double min_dist = stops_dist + (2.0 * broker_point);

   if(type == POSITION_TYPE_BUY)
   {
      double max_sl = tick.bid - min_dist;
      if(requested_sl > max_sl)
         requested_sl = max_sl;
      requested_sl = MathFloor(requested_sl / price_step) * price_step;
   }
   else
   {
      double min_sl = tick.ask + min_dist;
      if(requested_sl < min_sl)
         requested_sl = min_sl;
      requested_sl = MathCeil(requested_sl / price_step) * price_step;
   }
   requested_sl = NormalizeDouble(requested_sl, digits);

   double current_sl = PositionGetDouble(POSITION_SL);
   double tol = price_step * 0.5;
   if(current_sl > 0.0)
   {
      double current_sl_cmp = NormalizeDouble(MathRound(current_sl / price_step) * price_step, digits);
      if(type == POSITION_TYPE_BUY && requested_sl <= current_sl_cmp + tol)
         return true;
      if(type == POSITION_TYPE_SELL && requested_sl >= current_sl_cmp - tol)
         return true;
   }

   double tp = PositionGetDouble(POSITION_TP);
   if(tp > 0.0)
      tp = NormalizeDouble(MathRound(tp / price_step) * price_step, digits);

   CTrade tr;
   tr.SetExpertMagicNumber(InpMagic);
   tr.SetDeviationInPoints(20);
   bool ok = tr.PositionModify(ticket, requested_sl, tp);
   if(!ok)
   {
      PrintFormat("SWING SL update failed: ticket=%I64u type=%d sl=%.5f retcode=%d %s",
                  ticket,
                  (int)type,
                  requested_sl,
                  tr.ResultRetcode(),
                  tr.ResultRetcodeDescription());
   }
   return ok;
}

bool MoveSwingSLToBreakevenOffset(const long pair_id)
{
   if(pair_id <= 0) return false;

   double pip_size = PipSizeOf(InpSymbolGold);
   double offset = InpSwingBEOffsetPips * pip_size;
   if(offset < 0.0) offset = 0.0;

   bool found = false;
   bool all_ok = true;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbolGold)
         continue;

      string role = "";
      long pos_pair_id = 0;
      string comment = PositionGetString(POSITION_COMMENT);
      if(!ParsePositionRoleAndPairId(comment, role, pos_pair_id))
         continue;
      if(role != "SWING" || pos_pair_id != pair_id)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double requested_sl = (type == POSITION_TYPE_BUY)
                          ? (open_price + offset)
                          : (open_price - offset);
      found = true;
      if(!UpdatePositionTrailSL(ticket, type, requested_sl))
      {
         all_ok = false;
      }
      else
      {
         PrintFormat("SWING BE SL set after SCALP TP: pair=%I64d ticket=%I64u sl=%.5f offset_pips=%.2f",
                     pair_id,
                     ticket,
                     requested_sl,
                     InpSwingBEOffsetPips);
      }
   }

   if(!found)
      return true;
   return all_ok;
}

void ManageSwingTrailing()
{
   CleanupSwingTrailState();

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbolGold, tick))
      return;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbolGold)
         continue;

      string role = "";
      long pair_id = 0;
      string comment = PositionGetString(POSITION_COMMENT);
      if(!ParsePositionRoleAndPairId(comment, role, pair_id))
         continue;
      if(role != "SWING")
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      int idx = EnsureSwingTrailState(ticket, open_price, current_sl);
      if(idx < 0)
         continue;

      if(!swing_trail_active[idx] && !HasOpenPairRole(pair_id, "SCALP", type))
      {
         swing_trail_active[idx] = true;
         PrintFormat("SWING trailing armed: pair=%I64d ticket=%I64u", pair_id, ticket);
      }
      if(!swing_trail_active[idx])
         continue;

      double trail_distance = swing_trail_distances[idx];
      if(trail_distance <= 0.0)
         continue;

      double requested_sl = (type == POSITION_TYPE_BUY)
                          ? (tick.bid - trail_distance)
                          : (tick.ask + trail_distance);
      UpdatePositionTrailSL(ticket, type, requested_sl);
   }
}

//-------------------- Pivot Detection --------------------
// Finds last two confirmed pivot highs/lows (indices) on a symbol+tf.
// A pivot high at bar 'k' is confirmed if high[k] is max in [k-left ... k+right].
// Returns true if found two pivots; outputs indices (shift values).
bool GetLastTwoPivotHighs(const string sym, ENUM_TIMEFRAMES tf, int left, int right, int lookback,
                         int &idx1, int &idx2)
{
   idx1 = -1; idx2 = -1;
   int bars = iBars(sym, tf);
   if(bars < left+right+10) return false;

   int oldest = MathMin(lookback, bars - right - 1);
   int newest = right + left;
   // scan from newer to older so idx1/idx2 are truly the latest two confirmed pivots
   for(int k=newest; k<=oldest; k++)
   {
      double hk = iHigh(sym, tf, k);
      bool ok=true;
      for(int j=1;j<=left;j++)
         if(iHigh(sym, tf, k+j) > hk) { ok=false; break; }
      if(!ok) continue;
      for(int j=1;j<=right;j++)
         if(iHigh(sym, tf, k-j) >= hk) { ok=false; break; }
      if(!ok) continue;

      // first hit is latest pivot, second hit is previous pivot
      if(idx1 == -1) idx1 = k;
      else { idx2 = k; return true; }
   }
   return false;
}

bool GetLastTwoPivotLows(const string sym, ENUM_TIMEFRAMES tf, int left, int right, int lookback,
                        int &idx1, int &idx2)
{
   idx1 = -1; idx2 = -1;
   int bars = iBars(sym, tf);
   if(bars < left+right+10) return false;

   int oldest = MathMin(lookback, bars - right - 1);
   int newest = right + left;
   for(int k=newest; k<=oldest; k++)
   {
      double lk = iLow(sym, tf, k);
      bool ok=true;
      for(int j=1;j<=left;j++)
         if(iLow(sym, tf, k+j) < lk) { ok=false; break; }
      if(!ok) continue;
      for(int j=1;j<=right;j++)
         if(iLow(sym, tf, k-j) <= lk) { ok=false; break; }
      if(!ok) continue;

      if(idx1 == -1) idx1 = k;
      else { idx2 = k; return true; }
   }
   return false;
}

//-------------------- PVT --------------------
// Builds PVT array for [0..n-1] bars. Using tick_volume.
// PVT[oldest] starts at 0; then cumulative towards newest.
bool BuildPVT(const string sym, ENUM_TIMEFRAMES tf, int n, double &pvt[])
{
   if(n <= 10) return false;
   ArrayResize(pvt, n);
   ArraySetAsSeries(pvt, true);

   // We'll compute from oldest to newest but store series=true.
   // Need closes and volumes.
   double close[];
   long vol[];
   ArrayResize(close, n);
   ArrayResize(vol, n);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(vol, true);

   if(CopyClose(sym, tf, 0, n, close) != n) return false;
   if(CopyTickVolume(sym, tf, 0, n, vol) != n) return false;

   // Convert to non-series indexing for cumulative calc
   double c_ns[];
   long   v_ns[];
   ArrayResize(c_ns, n);
   ArrayResize(v_ns, n);
   for(int i=0;i<n;i++){ c_ns[i]=close[n-1-i]; v_ns[i]=vol[n-1-i]; } // oldest at 0

   double p_ns[];
   ArrayResize(p_ns, n);
   p_ns[0]=0.0;
   for(int i=1;i<n;i++)
   {
      double prev = c_ns[i-1];
      if(prev == 0) { p_ns[i]=p_ns[i-1]; continue; }
      double delta = (c_ns[i]-prev)/prev;
      p_ns[i] = p_ns[i-1] + delta * (double)v_ns[i];
   }

   // back to series
   for(int i=0;i<n;i++) pvt[i]=p_ns[n-1-i];
   return true;
}

// Finds PVT value at a bar shift (series indexing).
double PVTAt(const double &pvt[], int shift)
{
   if(shift < 0 || shift >= ArraySize(pvt)) return 0.0;
   return pvt[shift];
}

//-------------------- Strategy Logic --------------------
// 1) SMT: gold makes HH but silver does not => sell setup (anticipate reversal down)
//         gold makes LL but silver does not => buy setup
bool CheckSMT(SetupDir &dir_out)
{
   dir_out = SETUP_NONE;

   int gh1, gh2, gl1, gl2;
   int sh1, sh2, sl1, sl2;

   bool gH = GetLastTwoPivotHighs(InpSymbolGold, InpSMT_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, gh1, gh2);
   bool gL = GetLastTwoPivotLows (InpSymbolGold, InpSMT_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, gl1, gl2);
   bool sH = GetLastTwoPivotHighs(InpSymbolSilver, InpSMT_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, sh1, sh2);
   bool sL = GetLastTwoPivotLows (InpSymbolSilver, InpSMT_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, sl1, sl2);

   if(!(gH && gL && sH && sL)) return false;

   double g_high_new = iHigh(InpSymbolGold, InpSMT_TF, gh1);
   double g_high_old = iHigh(InpSymbolGold, InpSMT_TF, gh2);
   double s_high_new = iHigh(InpSymbolSilver, InpSMT_TF, sh1);
   double s_high_old = iHigh(InpSymbolSilver, InpSMT_TF, sh2);

   double g_low_new  = iLow(InpSymbolGold, InpSMT_TF, gl1);
   double g_low_old  = iLow(InpSymbolGold, InpSMT_TF, gl2);
   double s_low_new  = iLow(InpSymbolSilver, InpSMT_TF, sl1);
   double s_low_old  = iLow(InpSymbolSilver, InpSMT_TF, sl2);

   // SMT sell: Gold HH, Silver not HH
   bool gold_HH  = (g_high_new > g_high_old);
   bool silver_HH= (s_high_new > s_high_old);

   // SMT buy: Gold LL, Silver not LL
   bool gold_LL  = (g_low_new < g_low_old);
   bool silver_LL= (s_low_new < s_low_old);

   if(gold_HH && !silver_HH) { dir_out = SETUP_SELL; return true; }
   if(gold_LL && !silver_LL) { dir_out = SETUP_BUY;  return true; }

   return false;
}

// 2) PVT divergence on Gold (confirmation):
// Sell confirmation: price makes HH but PVT does NOT make HH (lower high) => bearish divergence
// Buy confirmation : price makes LL but PVT does NOT make LL (higher low) => bullish divergence
bool CheckPVT_Divergence(SetupDir dir)
{
   if(dir == SETUP_NONE) return false;

   int ph1, ph2, pl1, pl2;
   bool hasH = GetLastTwoPivotHighs(InpSymbolGold, InpSMT_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, ph1, ph2);
   bool hasL = GetLastTwoPivotLows (InpSymbolGold, InpSMT_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, pl1, pl2);
   if(!hasH || !hasL) return false;

   int n = MathMin(InpLookbackBars, iBars(InpSymbolGold, InpSMT_TF));
   if(n < 50) return false;

   double pvt[];
   if(!BuildPVT(InpSymbolGold, InpSMT_TF, n, pvt)) return false;

   if(dir == SETUP_SELL)
   {
      // price HH?
      double price_new = iHigh(InpSymbolGold, InpSMT_TF, ph1);
      double price_old = iHigh(InpSymbolGold, InpSMT_TF, ph2);
      if(!(price_new > price_old)) return false;

      double pvt_new = PVTAt(pvt, ph1);
      double pvt_old = PVTAt(pvt, ph2);
      // divergence: PVT fails to HH
      if(pvt_new <= pvt_old) return true;
      return false;
   }
   else // BUY
   {
      double price_new = iLow(InpSymbolGold, InpSMT_TF, pl1);
      double price_old = iLow(InpSymbolGold, InpSMT_TF, pl2);
      if(!(price_new < price_old)) return false;

      double pvt_new = PVTAt(pvt, pl1);
      double pvt_old = PVTAt(pvt, pl2);
      // divergence: PVT fails to LL (i.e., higher low)
      if(pvt_new >= pvt_old) return true;
      return false;
   }
}

// 3) Entry structure break on Entry TF (Gold):
// SELL: close breaks below last pivot low AND last pivot high is lower than previous pivot high
// BUY : close breaks above last pivot high AND last pivot low is higher than previous pivot low
bool CheckStructureBreak(SetupDir dir, double &sl_out, double &tp_out)
{
   sl_out = 0; tp_out = 0;
   if(dir == SETUP_NONE) return false;

   // Get pivots on Entry TF
   int h1,h2,l1,l2;
   bool hasH = GetLastTwoPivotHighs(InpSymbolGold, InpEntry_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, h1,h2);
   bool hasL = GetLastTwoPivotLows (InpSymbolGold, InpEntry_TF, InpPivotLeft, InpPivotRight, InpLookbackBars, l1,l2);
   if(!hasH || !hasL) return false;

   double lastClose = iClose(InpSymbolGold, InpEntry_TF, 1); // closed bar
   double bid = SymbolInfoDouble(InpSymbolGold, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbolGold, SYMBOL_ASK);

   double pt = PointOf(InpSymbolGold);
   double buf = InpSL_BufferPoints * pt;

   if(dir == SETUP_SELL)
   {
      double pivotLow  = iLow(InpSymbolGold, InpEntry_TF, l1);
      double high_new  = iHigh(InpSymbolGold, InpEntry_TF, h1);
      double high_old  = iHigh(InpSymbolGold, InpEntry_TF, h2);

      bool brokeLow = (lastClose < pivotLow);
      bool lowerHigh= (high_new < high_old);

      if(!brokeLow || !lowerHigh) return false;

      // SL beyond last pivot high (most recent swing high)
      double sl = high_new + buf;
      double entry = bid; // market sell
      if(sl <= entry) sl = entry + buf;

      double risk = sl - entry;
      double tp = entry - InpMinRR * risk;

      sl_out = sl;
      tp_out = tp;
      return true;
   }
   else // BUY
   {
      double pivotHigh = iHigh(InpSymbolGold, InpEntry_TF, h1);
      double low_new   = iLow (InpSymbolGold, InpEntry_TF, l1);
      double low_old   = iLow (InpSymbolGold, InpEntry_TF, l2);

      bool brokeHigh = (lastClose > pivotHigh);
      bool higherLow = (low_new > low_old);

      if(!brokeHigh || !higherLow) return false;

      double sl = low_new - buf;
      double entry = ask; // market buy
      if(sl >= entry) sl = entry - buf;

      double risk = entry - sl;
      double tp = entry + InpMinRR * risk;

      sl_out = sl;
      tp_out = tp;
      return true;
   }
}

// Check if setup expired
bool SetupStillValid()
{
   if(setup_dir == SETUP_NONE) return false;
   // expire by bars on entry TF
   datetime bar0 = iTime(InpSymbolGold, InpEntry_TF, 0);
   if(setup_time == 0 || bar0 == 0) return false;

   // count how many closed bars since setup_time
   int shift = iBarShift(InpSymbolGold, InpEntry_TF, setup_time, true);
   if(shift < 0) return false;

   // setup_time is a bar time; as time goes on, shift increases
   // when shift > expiry => expired
   if(shift > InpSetupExpiryBars)
   {
      setup_dir = SETUP_NONE;
      setup_time = 0;
      return false;
   }
   return true;
}

// Place order
bool ExecuteTrade(SetupDir dir, double sl, double tp)
{
   if(InpOnePositionOnly && CountMyPositions() > 0) return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);

   long pair_id = NextPairId();
   string scalp_comment = BuildPairComment("SCALP", pair_id);
   string swing_comment = BuildPairComment("SWING", pair_id);
   double swing_tp = CalcSwingTPFromScalp(dir, sl, tp);
   int digits = DigitsOf(InpSymbolGold);
   if(swing_tp > 0.0)
      swing_tp = NormalizeDouble(swing_tp, digits);

   bool scalp_ok = false;
   bool swing_ok = false;

   if(dir == SETUP_SELL)
   {
      scalp_ok = trade.Sell(InpFixedLot, InpSymbolGold, 0.0, sl, tp, scalp_comment);
      if(scalp_ok)
         swing_ok = trade.Sell(InpFixedLot, InpSymbolGold, 0.0, sl, swing_tp, swing_comment);
   }
   else if(dir == SETUP_BUY)
   {
      scalp_ok = trade.Buy(InpFixedLot, InpSymbolGold, 0.0, sl, tp, scalp_comment);
      if(scalp_ok)
         swing_ok = trade.Buy(InpFixedLot, InpSymbolGold, 0.0, sl, swing_tp, swing_comment);
   }

   if(!scalp_ok || !swing_ok)
   {
      ClosePairPositionsById(pair_id);
      PrintFormat("Dual entry failed: pair=%I64d scalp_ok=%d swing_ok=%d retcode=%d %s",
                  pair_id,
                  (int)scalp_ok,
                  (int)swing_ok,
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
      return false;
   }

   setup_dir = SETUP_NONE;
   setup_time = 0;
   return true;
}

//-------------------- EA Lifecycle --------------------
int OnInit()
{
   if(!EnsureSymbols())
   {
      Print("Symbol select failed. Check symbol names: ", InpSymbolGold, " / ", InpSymbolSilver);
      return INIT_FAILED;
   }

   ResetNewsFilterCache();
   if(InpEnableNewsFilter && MQLInfoInteger(MQL_TESTER))
      LoadBacktestNewsCalendarCsv();

   Print("EA init OK: Gold=", InpSymbolGold, ", Silver=", InpSymbolSilver);
   return INIT_SUCCEEDED;
}

datetime last_smt_bar = 0;
datetime last_entry_bar = 0;

void OnTick()
{
   if(!EnsureSymbols()) return;

   // 1) On new SMT TF bar: evaluate SMT + PVT and arm setup
   if(IsNewBar(InpSymbolGold, InpSMT_TF, last_smt_bar))
   {
      SetupDir d;
      if(CheckSMT(d))
      {
         if(CheckPVT_Divergence(d))
         {
            // Arm setup
            setup_dir = d;
            setup_time = iTime(InpSymbolGold, InpEntry_TF, 0); // anchor to current entry TF bar time
            Print("Setup armed: ", (setup_dir==SETUP_BUY?"BUY":"SELL"), " at ", TimeToString(setup_time));
         }
      }
   }

   // 2) On new Entry TF bar: if setup armed and valid, wait structure break and enter
   if(IsNewBar(InpSymbolGold, InpEntry_TF, last_entry_bar))
   {
      if(!SetupStillValid()) return;

      double sl,tp;
      if(CheckStructureBreak(setup_dir, sl, tp))
      {
         if(IsNewsTimeNow()) return;

         // Normalize prices
         int dg = DigitsOf(InpSymbolGold);
         sl = NormalizeDouble(sl, dg);
         tp = NormalizeDouble(tp, dg);

         ExecuteTrade(setup_dir, sl, tp);
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   if((long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   if((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != InpSymbolGold)
      return;

   long reason = (long)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string role = "";
   long pair_id = 0;
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   if(!ParsePositionRoleAndPairId(comment, role, pair_id))
      return;

   if(reason == DEAL_REASON_TP && role == "SCALP")
   {
      if(InpSwingMoveSLOnScalpTP)
      {
         if(!MoveSwingSLToBreakevenOffset(pair_id))
         {
            PrintFormat("SCALP TP sync BE move failed or no SWING found: pair=%I64d deal=%I64u", pair_id, trans.deal);
         }
      }
      return;
   }

   if(reason != DEAL_REASON_SL)
      return;

   if(!ClosePairPositionsById(pair_id))
   {
      PrintFormat("SL sync close failed: pair=%I64d deal=%I64u", pair_id, trans.deal);
   }
}
