//+------------------------------------------------------------------+
//| XAUUSD Mean-Reversion (M15) with DCA + Basket TP + Stopout        |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input string InpSymbol          = "XAUUSD";
input ENUM_TIMEFRAMES InpTF     = PERIOD_M15;

// good setting note
// TIMEFRAME M15 Ma 96, Std 160, Dca 2.4, LotMul 1.0, ZEntry1.8 (Low DD)
// TIMEFRAME M15 Ma 128, Std 32, Dca 2.4, LotMul 1.0, ZEntry1.4 (Moderate)

// TIMEFRAME M4, Ma 192, Std32, maxLevel 6, DcaStep 2.4, LotMul 1.0, ZEntry1.8, FILTER=M30,18,25

// Entry (mean reversion)
input int    MaPeriod           = 64;
input int    StdPeriod          = 64;
input bool   UseEMA             = true;
input double Z_Entry            = 1.8;      // long: z <= -Z_Entry, short: z >= Z_Entry
input bool   ENABLE_LONG        = true;
input bool   ENABLE_SHORT       = true;
input ENUM_TIMEFRAMES AdxFilterTF = PERIOD_M30; // ADX filter timeframe
input int    AdxPeriod          = 18;       // ADX period (width)
input double AdxBlockMin        = 25.0;     // block entry when ADX >= this value

// DCA settings
input int    MaxDcaStages       = 6;        // max stages per side (including initial entry)
input double DcaStep_ATR        = 2.4;      // add next stage when price moves against by ATR*step
input double LotMultiplier      = 1.0;      // lots *= multiplier each added stage
input bool   AllowReEnterAfterStop = true;  // after 4th trigger stopout, allow immediate new cycle if signal still valid
input int    CooldownBarsAfterStop = 1;     // wait N new bars after stopout before re-entering

// Position sizing (base lot)
input bool   UseRiskPercent     = false;    // simple base lots by default (DCA strategy often uses fixed)
input double RiskPercent        = 0.5;      // if true, base lot from SL distance (not used here unless you add SL)
input double BaseLots           = 0.10;

// Take Profit mode
enum TPMode { TP_ATR = 0, TP_POINTS = 1 };
input TPMode TakeProfitMode     = TP_POINTS;
input double TP_ATR_Mult        = 1.8;      // TP distance = ATR * mult (from weighted avg entry)
input double TP_Points          = 3300;      // TP distance in points (from weighted avg entry)
input bool   EnableTrailingTakeProfit = true; // TP到達時に最深ポジションのみ残してトレーリング
input double TrailingDistanceRatio    = 0.55; // trail distance = TP distance * ratio

// News filter ( not required for DCA2 )
input bool   EnableNewsFilter      = false;
input int    NewsMinutesBefore     = 5;
input int    NewsMinutesAfter      = 30;
input bool   NewsOnlyHighImpact    = true;
input string NewsBacktestCalendarFile = "economic_calendar_2025_2030.csv"; // MQL_TESTER時はFILE_COMMONから参照

// Safety
input double MaxSpreadPoints    = 320;
input int    Magic              = 20260228;

datetime last_bar_time = 0;

bool  buy_runner_active = false;
bool  sell_runner_active = false;
ulong buy_runner_ticket = 0;
ulong sell_runner_ticket = 0;
double buy_runner_stop = 0.0;
double sell_runner_stop = 0.0;
double buy_runner_trail_dist = 0.0;
double sell_runner_trail_dist = 0.0;
double buy_dca_step_locked = 0.0;
double sell_dca_step_locked = 0.0;
datetime news_last_checked_server_time = 0;
bool news_last_check_blocked = false;
ulong news_last_event_id = 0;
datetime news_last_event_time = 0;
ulong news_last_logged_event_id = 0;
datetime news_last_logged_event_time = 0;
int news_last_calendar_error = 0;
datetime news_backtest_all_event_times[];
datetime news_backtest_high_event_times[];
bool news_backtest_calendar_loaded = false;
bool news_backtest_calendar_ready = false;

// -------- helpers --------
bool IsNewBar(string sym, ENUM_TIMEFRAMES tf){
   datetime t = iTime(sym, tf, 0);
   if(t != last_bar_time){
      last_bar_time = t;
      return true;
   }
   return false;
}

double GetMA(string sym, ENUM_TIMEFRAMES tf, int period){
   int h = iMA(sym, tf, period, 0, UseEMA ? MODE_EMA : MODE_SMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return EMPTY_VALUE;
   double b[];
   if(CopyBuffer(h, 0, 0, 1, b) <= 0){ IndicatorRelease(h); return EMPTY_VALUE; }
   IndicatorRelease(h);
   return b[0];
}

double GetStd(string sym, ENUM_TIMEFRAMES tf, int period){
   int h = iStdDev(sym, tf, period, 0, MODE_SMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return EMPTY_VALUE;
   double b[];
   if(CopyBuffer(h, 0, 0, 1, b) <= 0){ IndicatorRelease(h); return EMPTY_VALUE; }
   IndicatorRelease(h);
   return b[0];
}

double GetATR(string sym, ENUM_TIMEFRAMES tf, int period){
   int h = iATR(sym, tf, period);
   if(h == INVALID_HANDLE) return EMPTY_VALUE;
   double b[];
   if(CopyBuffer(h, 0, 0, 1, b) <= 0){ IndicatorRelease(h); return EMPTY_VALUE; }
   IndicatorRelease(h);
   return b[0];
}

double GetADX(string sym, ENUM_TIMEFRAMES tf, int period){
   if(period<=0) return EMPTY_VALUE;
   int h = iADX(sym, tf, period);
   if(h == INVALID_HANDLE) return EMPTY_VALUE;
   double b[];
   if(CopyBuffer(h, 0, 0, 1, b) <= 0){ IndicatorRelease(h); return EMPTY_VALUE; }
   IndicatorRelease(h);
   return b[0];
}

double NormalizeLots(string sym, double lots){
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots/step)*step;
   return lots;
}

// Return count of positions by side for this EA
int CountPositionsByType(string sym, long posType){
   int c=0;
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType) c++;
      }
   }
   return c;
}

// Weighted average entry price + total volume
bool GetBasketByType(string sym, long posType, double &avgPrice, double &totalVol){
   avgPrice=0; totalVol=0;
   double sumPV=0;

   bool any=false;
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType){
            any=true;
            double vol   = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            sumPV += vol*price;
            totalVol += vol;
         }
      }
   }
   if(!any || totalVol<=0) return false;
   avgPrice = sumPV/totalVol;
   return true;
}

// Find last added entry price by side (most recent open time)
bool GetLastEntryByType(string sym, long posType, double &lastPrice){
   datetime bestT=0; lastPrice=0;
   bool any=false;

   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType){
            datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
            if(ot >= bestT){
               bestT = ot;
               lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               any=true;
            }
         }
      }
   }
   return any;
}

// Close all EA positions for side
void CloseAllByType(string sym, long posType){
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType){
            trade.PositionClose(ticket);
         }
      }
   }
}

void ResetRunnerState(long posType){
   if(posType==POSITION_TYPE_BUY){
      buy_runner_active = false;
      buy_runner_ticket = 0;
      buy_runner_stop = 0.0;
      buy_runner_trail_dist = 0.0;
   } else {
      sell_runner_active = false;
      sell_runner_ticket = 0;
      sell_runner_stop = 0.0;
      sell_runner_trail_dist = 0.0;
   }
}

bool IsRunnerActive(long posType){
   return (posType==POSITION_TYPE_BUY) ? buy_runner_active : sell_runner_active;
}

ulong RunnerTicket(long posType){
   return (posType==POSITION_TYPE_BUY) ? buy_runner_ticket : sell_runner_ticket;
}

double CalcTakeProfitDistancePrice(string sym, double atr){
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0) return 0.0;
   if(TakeProfitMode==TP_ATR){
      return atr * TP_ATR_Mult;
   }
   return TP_Points * point;
}

double CalcTrailDistancePrice(string sym, double atr){
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0) return 0.0;
   double tpDist = CalcTakeProfitDistancePrice(sym, atr);
   if(tpDist<=0) return 0.0;
   double dist = tpDist * TrailingDistanceRatio;
   if(dist < point) dist = point;
   return dist;
}

bool FindDeepestTicketByType(string sym, long posType, ulong &ticket){
   ticket = 0;
   datetime bestT = 0;
   bool any = false;
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong t = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType){
            datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
            if(!any || ot >= bestT){
               any = true;
               bestT = ot;
               ticket = t;
            }
         }
      }
   }
   return any && ticket>0;
}

bool ClosePositionsExceptTicket(string sym, long posType, ulong keepTicket){
   bool ok = true;
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType && ticket!=keepTicket){
            if(!trade.PositionClose(ticket)){
               ok = false;
               PrintFormat("Split TP close failed ticket=%I64u ret=%u (%s) err=%d",
                           ticket,
                           trade.ResultRetcode(),
                           trade.ResultRetcodeDescription(),
                           GetLastError());
            }
         }
      }
   }
   return ok;
}

bool ClearPositionTP(ulong ticket){
   if(!PositionSelectByTicket(ticket)) return false;
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   if(tp<=0) return true;
   ResetLastError();
   if(!trade.PositionModify(ticket, sl, 0.0)){
      PrintFormat("Clear TP failed ticket=%I64u ret=%u (%s) err=%d",
                  ticket,
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription(),
                  GetLastError());
      return false;
   }
   return true;
}

void ClearBasketTPByType(string sym, long posType){
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType){
            double tp = PositionGetDouble(POSITION_TP);
            if(tp>0.0){
               ClearPositionTP(ticket);
            }
         }
      }
   }
}

bool ManageDeepestRunnerTrailing(string sym, long posType){
   bool active = IsRunnerActive(posType);
   if(!active) return false;

   ulong keepTicket = RunnerTicket(posType);
   if(keepTicket==0 || !PositionSelectByTicket(keepTicket)){
      ResetRunnerState(posType);
      return false;
   }

   string ps = PositionGetString(POSITION_SYMBOL);
   long pm   = PositionGetInteger(POSITION_MAGIC);
   long pt   = PositionGetInteger(POSITION_TYPE);
   if(ps!=sym || pm!=Magic || pt!=posType){
      ResetRunnerState(posType);
      return false;
   }

   // enforce deepest-only state in case any extra positions appeared
   ClosePositionsExceptTicket(sym, posType, keepTicket);

   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0){
      ResetRunnerState(posType);
      return false;
   }
   double tol = point * 0.5;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return true;

   if(posType==POSITION_TYPE_BUY){
      double candidate = bid - buy_runner_trail_dist;
      if(candidate > buy_runner_stop) buy_runner_stop = candidate;
      if(bid <= buy_runner_stop + tol){
         if(trade.PositionClose(keepTicket)){
            ResetRunnerState(posType);
         } else {
            PrintFormat("Runner trail close failed ticket=%I64u ret=%u (%s) err=%d",
                        keepTicket,
                        trade.ResultRetcode(),
                        trade.ResultRetcodeDescription(),
                        GetLastError());
         }
      }
   } else {
      double candidate = ask + sell_runner_trail_dist;
      if(sell_runner_stop<=0.0 || candidate < sell_runner_stop) sell_runner_stop = candidate;
      if(ask >= sell_runner_stop - tol){
         if(trade.PositionClose(keepTicket)){
            ResetRunnerState(posType);
         } else {
            PrintFormat("Runner trail close failed ticket=%I64u ret=%u (%s) err=%d",
                        keepTicket,
                        trade.ResultRetcode(),
                        trade.ResultRetcodeDescription(),
                        GetLastError());
         }
      }
   }
   return true;
}

double CalcBasketTP(string sym, double avgPrice, double atr, long posType){
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(point<=0 || digits<0) return 0.0;

   double tpDistPrice=0;
   if(TakeProfitMode==TP_ATR){
      tpDistPrice = atr * TP_ATR_Mult;
   } else {
      tpDistPrice = TP_Points * point;
   }
   double rawTP = (posType==POSITION_TYPE_BUY) ? (avgPrice + tpDistPrice) : (avgPrice - tpDistPrice);
   return NormalizeDouble(rawTP, digits);
}

// Apply/Update TP for all positions on side to same basket TP
void UpdateBasketTP(string sym, long posType, double basketTP){
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0 || basketTP<=0) return;

   // modify each position TP (keep SL as-is)
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==posType){
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            if(MathAbs(tp - basketTP) <= point*0.5) continue;
            ResetLastError();
            if(!trade.PositionModify(ticket, sl, basketTP)){
               PrintFormat("TP update failed ticket=%I64u ret=%u (%s) err=%d tp=%.5f",
                           ticket,
                           trade.ResultRetcode(),
                           trade.ResultRetcodeDescription(),
                           GetLastError(),
                           basketTP);
            }
         }
      }
   }
}

// Maintain server-side TP and close at target even if TP could not be set.
void ManageBasketTakeProfit(string sym, double atr, long posType){
   if(ManageDeepestRunnerTrailing(sym, posType)) return;

   double avgP, totV;
   if(!GetBasketByType(sym, posType, avgP, totV)) return;
   if(atr<=0) return;

   double basketTP = CalcBasketTP(sym, avgP, atr, posType);
   if(basketTP<=0) return;

   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0) return;

   // Virtual TP fallback: if target is reached but some tickets had no TP, force close.
   bool tpReached = false;
   if(posType==POSITION_TYPE_BUY){
      tpReached = (bid >= basketTP - point*0.5);
   } else {
      tpReached = (ask <= basketTP + point*0.5);
   }

   if(tpReached){
      if(!EnableTrailingTakeProfit){
         CloseAllByType(sym, posType);
         ResetRunnerState(posType);
         return;
      }

      ulong keepTicket = 0;
      if(!FindDeepestTicketByType(sym, posType, keepTicket) || keepTicket==0){
         CloseAllByType(sym, posType);
         ResetRunnerState(posType);
         return;
      }

      if(!ClosePositionsExceptTicket(sym, posType, keepTicket)) return;
      if(!PositionSelectByTicket(keepTicket)){
         ResetRunnerState(posType);
         return;
      }

      double trailDist = CalcTrailDistancePrice(sym, atr);
      if(trailDist<=0){
         CloseAllByType(sym, posType);
         ResetRunnerState(posType);
         return;
      }

      ClearPositionTP(keepTicket);

      if(posType==POSITION_TYPE_BUY){
         buy_runner_active = true;
         buy_runner_ticket = keepTicket;
         buy_runner_trail_dist = trailDist;
         buy_runner_stop = bid - trailDist;
      } else {
         sell_runner_active = true;
         sell_runner_ticket = keepTicket;
         sell_runner_trail_dist = trailDist;
         sell_runner_stop = ask + trailDist;
      }
      PrintFormat("Basket TP split close: keep deepest ticket=%I64u side=%s trail=%.5f",
                  keepTicket,
                  (posType==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  trailDist);
      return;
   }

   if(EnableTrailingTakeProfit){
      // In split-trailing mode, keep TP virtual so server-side TP does not close
      // the deepest runner before trailing starts.
      ClearBasketTPByType(sym, posType);
      return;
   }

   // Some brokers reject TP too close to current price; skip modify and keep virtual TP fallback.
   int stopsLevel = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   if(posType==POSITION_TYPE_BUY){
      double minTP = bid + (stopsLevel + 1) * point;
      if(basketTP <= minTP) return;
   } else {
      double maxTP = ask - (stopsLevel + 1) * point;
      if(basketTP >= maxTP) return;
   }

   UpdateBasketTP(sym, posType, basketTP);
}

// cooldown tracking via GlobalVariable
string DirSuffix(long posType){ return (posType==POSITION_TYPE_SELL) ? "S" : "L"; }
string GV_CooldownName(string sym, long posType){ return "MRDCA_COOLDOWN_"+sym+"_"+(string)Magic+"_"+DirSuffix(posType); }
bool InCooldown(string sym, long posType){
   string n = GV_CooldownName(sym, posType);
   if(!GlobalVariableCheck(n)) return false;
   double v = GlobalVariableGet(n);
   // v = bar time until which cooldown applies (as datetime stored in double)
   datetime until = (datetime)v;
   return (TimeCurrent() < until);
}
void SetCooldownBars(string sym, ENUM_TIMEFRAMES tf, int bars, long posType){
   if(bars<=0) return;
   datetime nextBar = iTime(sym, tf, 0) + PeriodSeconds(tf)*bars;
   GlobalVariableSet(GV_CooldownName(sym, posType), (double)nextBar);
}

void ResetNewsFilterCache(){
   news_last_checked_server_time = 0;
   news_last_check_blocked = false;
   news_last_event_id = 0;
   news_last_event_time = 0;
   news_last_logged_event_id = 0;
   news_last_logged_event_time = 0;
   news_last_calendar_error = 0;
   ArrayResize(news_backtest_all_event_times, 0);
   ArrayResize(news_backtest_high_event_times, 0);
   news_backtest_calendar_loaded = false;
   news_backtest_calendar_ready = false;
}

int LowerBoundEventTime(const datetime &events[], datetime target){
   int left = 0;
   int right = ArraySize(events);
   while(left < right){
      int mid = left + (right - left) / 2;
      if(events[mid] < target)
         left = mid + 1;
      else
         right = mid;
   }
   return left;
}

bool HasBacktestNewsEventInWindow(const datetime &events[], datetime from, datetime to, datetime &hit_time){
   int count = ArraySize(events);
   if(count<=0 || to<from) return false;
   int idx = LowerBoundEventTime(events, from);
   if(idx>=0 && idx<count && events[idx]<=to){
      hit_time = events[idx];
      return true;
   }
   return false;
}

bool LoadBacktestNewsCalendarCsv(){
   news_backtest_calendar_loaded = true;
   news_backtest_calendar_ready = false;
   ArrayResize(news_backtest_all_event_times, 0);
   ArrayResize(news_backtest_high_event_times, 0);

   if(StringLen(NewsBacktestCalendarFile)==0){
      Print("News filter backtest CSV file name is empty.");
      return false;
   }

   ResetLastError();
   int fh = FileOpen(NewsBacktestCalendarFile, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE){
      PrintFormat("News filter backtest CSV open failed: file=%s err=%d",
                  NewsBacktestCalendarFile,
                  GetLastError());
      return false;
   }

   const int kCsvColumns = 14;
   for(int c=0; c<kCsvColumns && !FileIsEnding(fh); ++c)
      FileReadString(fh); // header

   int all_capacity = 0;
   int high_capacity = 0;
   int all_count = 0;
   int high_count = 0;

   while(!FileIsEnding(fh)){
      string server_time = FileReadString(fh);
      if(FileIsEnding(fh) && StringLen(server_time)==0)
         break;

      FileReadString(fh); // gmt_time
      FileReadString(fh); // currency
      FileReadString(fh); // event_id
      FileReadString(fh); // value_id
      string importance = FileReadString(fh);
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

      if(all_count >= all_capacity){
         all_capacity = (all_capacity <= 0) ? 512 : (all_capacity * 2);
         ArrayResize(news_backtest_all_event_times, all_capacity);
      }
      news_backtest_all_event_times[all_count] = event_time;
      all_count++;

      StringToUpper(importance);
      if(importance == "HIGH"){
         if(high_count >= high_capacity){
            high_capacity = (high_capacity <= 0) ? 256 : (high_capacity * 2);
            ArrayResize(news_backtest_high_event_times, high_capacity);
         }
         news_backtest_high_event_times[high_count] = event_time;
         high_count++;
      }
   }
   FileClose(fh);

   ArrayResize(news_backtest_all_event_times, all_count);
   ArrayResize(news_backtest_high_event_times, high_count);
   if(all_count > 1) ArraySort(news_backtest_all_event_times);
   if(high_count > 1) ArraySort(news_backtest_high_event_times);

   news_backtest_calendar_ready = (all_count > 0);
   if(!news_backtest_calendar_ready){
      PrintFormat("News filter backtest CSV is empty: file=%s", NewsBacktestCalendarFile);
      return false;
   }

   PrintFormat("News filter backtest CSV loaded: file=%s rows=%d high=%d",
               NewsBacktestCalendarFile, all_count, high_count);
   return true;
}

bool IsNewsTimeNowBacktest(datetime from, datetime to){
   if(!news_backtest_calendar_loaded)
      LoadBacktestNewsCalendarCsv();
   if(!news_backtest_calendar_ready)
      return false;

   datetime hit_time = 0;
   bool blocked = false;
   if(NewsOnlyHighImpact)
      blocked = HasBacktestNewsEventInWindow(news_backtest_high_event_times, from, to, hit_time);
   else
      blocked = HasBacktestNewsEventInWindow(news_backtest_all_event_times, from, to, hit_time);
   if(!blocked)
      return false;

   news_last_check_blocked = true;
   news_last_event_id = 0;
   news_last_event_time = hit_time;

   if(news_last_logged_event_time != news_last_event_time || news_last_logged_event_id != 0){
      PrintFormat("News filter block(backtest CSV): importance=%s server=%s",
                  NewsOnlyHighImpact ? "HIGH" : "ALL",
                  TimeToString(news_last_event_time, TIME_DATE | TIME_MINUTES));
      news_last_logged_event_id = 0;
      news_last_logged_event_time = news_last_event_time;
   }
   return true;
}

bool IsNewsTimeNow(){
   if(!EnableNewsFilter) return false;

   datetime now_server = TimeTradeServer();
   if(now_server <= 0) now_server = TimeCurrent();
   if(now_server <= 0) return false;

   if(news_last_checked_server_time == now_server)
      return news_last_check_blocked;

   news_last_checked_server_time = now_server;
   news_last_check_blocked = false;
   news_last_event_id = 0;
   news_last_event_time = 0;

   int minutes_before = NewsMinutesBefore;
   if(minutes_before < 0) minutes_before = 0;
   int minutes_after = NewsMinutesAfter;
   if(minutes_after < 0) minutes_after = 0;

   datetime from = now_server - minutes_before * 60;
   datetime to = now_server + minutes_after * 60;

   if(MQLInfoInteger(MQL_TESTER))
      return IsNewsTimeNowBacktest(from, to);

   MqlCalendarValue values[];
   ResetLastError();
   int n = CalendarValueHistory(values, from, to);
   if(n < 0){
      int err = GetLastError();
      if(err != 0 && err != news_last_calendar_error){
         PrintFormat("News filter query failed: err=%d", err);
         news_last_calendar_error = err;
      }
      return false;
   }
   news_last_calendar_error = 0;
   if(n == 0) return false;

   for(int i=0; i<n; ++i){
      ulong event_id = values[i].event_id;
      MqlCalendarEvent event;
      if(!CalendarEventById(event_id, event))
         continue;
      if(NewsOnlyHighImpact && event.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      news_last_check_blocked = true;
      news_last_event_id = event_id;
      news_last_event_time = values[i].time;

      if(news_last_logged_event_id != news_last_event_id
         || news_last_logged_event_time != news_last_event_time){
         PrintFormat("News filter block: id=%I64u event=%s importance=%d server=%s",
                     news_last_event_id,
                     event.name,
                     (int)event.importance,
                     TimeToString(news_last_event_time, TIME_DATE | TIME_MINUTES));
         news_last_logged_event_id = news_last_event_id;
         news_last_logged_event_time = news_last_event_time;
      }
      return true;
   }

   return false;
}

// ---------------- main ----------------
int OnInit(){
   trade.SetExpertMagicNumber(Magic);
   ResetNewsFilterCache();
   if(EnableNewsFilter && MQLInfoInteger(MQL_TESTER))
      LoadBacktestNewsCalendarCsv();
   return(INIT_SUCCEEDED);
}

void OnTick(){
   string sym = InpSymbol;
   if(!SymbolSelect(sym, true)) return;
   bool news_blocked = IsNewsTimeNow();

   // TP maintenance and recovery run every tick, not only on new bar.
   int liveLong  = CountPositionsByType(sym, POSITION_TYPE_BUY);
   int liveShort = CountPositionsByType(sym, POSITION_TYPE_SELL);
   if(liveLong<=0) ResetRunnerState(POSITION_TYPE_BUY);
   if(liveShort<=0) ResetRunnerState(POSITION_TYPE_SELL);
   if(liveLong<=0) buy_dca_step_locked = 0.0;
   if(liveShort<=0) sell_dca_step_locked = 0.0;
   if(liveLong > 0 || liveShort > 0){
      double atrNow = GetATR(sym, InpTF, 14);
      if(atrNow!=EMPTY_VALUE && atrNow>0){
         if(liveLong > 0)  ManageBasketTakeProfit(sym, atrNow, POSITION_TYPE_BUY);
         if(liveShort > 0) ManageBasketTakeProfit(sym, atrNow, POSITION_TYPE_SELL);
      }
   }

   // Entry / DCA logic runs on new bars.
   if(!IsNewBar(sym, InpTF)) return;

   // spread filter
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0) return;
   double spread_points = (ask-bid)/point;
   if(spread_points > MaxSpreadPoints) return;

   double ma  = GetMA(sym, InpTF, MaPeriod);
   double sd  = GetStd(sym, InpTF, StdPeriod);
   double atr = GetATR(sym, InpTF, 14);
   if(ma==EMPTY_VALUE || sd==EMPTY_VALUE || atr==EMPTY_VALUE) return;
   if(sd<=0 || atr<=0) return;

   double close0 = iClose(sym, InpTF, 0);
   double z = (close0 - ma)/sd;

   int longStage  = CountPositionsByType(sym, POSITION_TYPE_BUY);
   int shortStage = CountPositionsByType(sym, POSITION_TYPE_SELL);
   bool hasBasket = false;

   // --- LONG side: DCA / Stopout
   if(longStage > 0){
      hasBasket = true;
      if(!IsRunnerActive(POSITION_TYPE_BUY)){
         double lastEntry;
         if(GetLastEntryByType(sym, POSITION_TYPE_BUY, lastEntry)){
            // next add trigger distance
            double stepDistNow = atr * DcaStep_ATR;
            double stepDist = stepDistNow;
            if(longStage >= 2){
               if(stepDistNow > buy_dca_step_locked) buy_dca_step_locked = stepDistNow;
               if(buy_dca_step_locked > 0.0) stepDist = buy_dca_step_locked;
            }
            double nextLevel = lastEntry - stepDist;

            // If price went against enough for "next stage"
            if(bid <= nextLevel){
               if(longStage < MaxDcaStages){
                  if(ENABLE_LONG && !news_blocked){
                     // Add next stage
                     double lots = NormalizeLots(sym, BaseLots * MathPow(LotMultiplier, longStage)); // stage=1 -> 2nd entry multiplier^1
                     if(trade.Buy(lots, sym, ask, 0, 0, "DCA add long")){
                        // Lock from first nanpin; then only widen, never narrow.
                        if(stepDist > buy_dca_step_locked) buy_dca_step_locked = stepDist;
                     }
                     // After adding, TP is maintained by ManageBasketTakeProfit() on every tick.
                  }
               } else {
                  // Next stage would exceed cap -> stop out this side and set cooldown
                  CloseAllByType(sym, POSITION_TYPE_BUY);
                  SetCooldownBars(sym, InpTF, CooldownBarsAfterStop, POSITION_TYPE_BUY);
                  buy_dca_step_locked = 0.0;
               }
            }
         }
      }
   }

   // --- SHORT side: DCA / Stopout
   if(shortStage > 0){
      hasBasket = true;
      if(!IsRunnerActive(POSITION_TYPE_SELL)){
         double lastEntry;
         if(GetLastEntryByType(sym, POSITION_TYPE_SELL, lastEntry)){
            // For SELL, adverse move is upward.
            double stepDistNow = atr * DcaStep_ATR;
            double stepDist = stepDistNow;
            if(shortStage >= 2){
               if(stepDistNow > sell_dca_step_locked) sell_dca_step_locked = stepDistNow;
               if(sell_dca_step_locked > 0.0) stepDist = sell_dca_step_locked;
            }
            double nextLevel = lastEntry + stepDist;

            if(ask >= nextLevel){
               if(shortStage < MaxDcaStages){
                  if(ENABLE_SHORT && !news_blocked){
                     double lots = NormalizeLots(sym, BaseLots * MathPow(LotMultiplier, shortStage)); // stage=1 -> 2nd entry multiplier^1
                     if(trade.Sell(lots, sym, bid, 0, 0, "DCA add short")){
                        // Lock from first nanpin; then only widen, never narrow.
                        if(stepDist > sell_dca_step_locked) sell_dca_step_locked = stepDist;
                     }
                  }
               } else {
                  CloseAllByType(sym, POSITION_TYPE_SELL);
                  SetCooldownBars(sym, InpTF, CooldownBarsAfterStop, POSITION_TYPE_SELL);
                  sell_dca_step_locked = 0.0;
               }
            }
         }
      }
   }

   // While basket exists on either side, don't open new initial positions.
   if(hasBasket) return;

   // ADX filter: do not start a new basket while trend strength is high.
   double adx = GetADX(sym, AdxFilterTF, AdxPeriod);
   if(adx==EMPTY_VALUE) return;
   if(adx >= AdxBlockMin) return;

   // --- No position: entry condition (mean reversion), side-gated
   bool longEntryOK  = ENABLE_LONG  && !news_blocked && !InCooldown(sym, POSITION_TYPE_BUY)  && (z <= -Z_Entry);
   bool shortEntryOK = ENABLE_SHORT && !news_blocked && !InCooldown(sym, POSITION_TYPE_SELL) && (z >=  Z_Entry);

   double lots0 = NormalizeLots(sym, BaseLots);
   if(longEntryOK){
      trade.Buy(lots0, sym, ask, 0, 0, "MR entry long");
      return;
   }
   if(shortEntryOK){
      trade.Sell(lots0, sym, bid, 0, 0, "MR entry short");
      return;
   }
}
