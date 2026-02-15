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

//-------------------- Inputs --------------------
input string InpSymbolGold        = "XAUUSD-m";
input string InpSymbolSilver      = "XAGUSD-m";

input ENUM_TIMEFRAMES InpSMT_TF   = PERIOD_M15; // SMT + PVT confirmation timeframe
input ENUM_TIMEFRAMES InpEntry_TF = PERIOD_M5;  // Entry timeframe (structure break)

input int    InpPivotLeft         = 2;   // Pivot detection left bars
input int    InpPivotRight        = 2;   // Pivot detection right bars
input int    InpLookbackBars      = 400; // History scan bars per TF

input int    InpSetupExpiryBars   = 12;  // Setup validity in Entry TF bars after SMT+PVT align

input double InpFixedLot          = 0.10;
input double InpMinRR             = 2.0; // RR >= 2
input int    InpSL_BufferPoints   = 50;  // buffer in points beyond swing

input long   InpMagic             = 26021401;
input bool   InpOnePositionOnly   = true;
input bool   InpEnableNewsFilter  = true; // block entry around calendar news
input int    InpNewsMinutesBefore = 5;    // minutes before news
input int    InpNewsMinutesAfter  = 30;   // minutes after news

//-------------------- Internal State --------------------
enum SetupDir { SETUP_NONE=0, SETUP_BUY=1, SETUP_SELL=-1 };

SetupDir setup_dir = SETUP_NONE;
datetime setup_time = 0;   // time when setup was armed (Entry TF bar time)

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

bool EnsureSymbols()
{
   if(!SymbolSelect(InpSymbolGold, true))  return false;
   if(!SymbolSelect(InpSymbolSilver, true))return false;
   return true;
}

bool IsNewsTimeNow()
{
   if(!InpEnableNewsFilter) return false;

   datetime now_server = TimeTradeServer();
   if(now_server <= 0) now_server = TimeCurrent();

   int before_min = MathMax(0, InpNewsMinutesBefore);
   int after_min  = MathMax(0, InpNewsMinutesAfter);
   datetime from  = now_server - (datetime)(before_min * 60);
   datetime to    = now_server + (datetime)(after_min * 60);

   MqlCalendarValue values[];
   ResetLastError();
   int n = CalendarValueHistory(values, from, to); // no currency filter: all calendar news
   if(n < 0)
   {
      static datetime last_err_log = 0;
      datetime cur_min = now_server - (now_server % 60);
      if(cur_min != last_err_log)
      {
         Print("News filter query failed. err=", GetLastError());
         last_err_log = cur_min;
      }
      return false; // fail-open
   }

   if(n > 0)
   {
      static datetime last_block_log = 0;
      datetime cur_min = now_server - (now_server % 60);
      if(cur_min != last_block_log)
      {
         Print("Entry blocked by news filter. events=", n,
               " window=", before_min, "m/", after_min, "m");
         last_block_log = cur_min;
      }
      return true;
   }

   return false;
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

   int start = MathMin(lookback, bars - right - 1);
   // scan from older to newer, keep last two
   for(int k=start; k>=right+left; k--)
   {
      double hk = iHigh(sym, tf, k);
      bool ok=true;
      for(int j=1;j<=left;j++)
         if(iHigh(sym, tf, k+j) > hk) { ok=false; break; }
      if(!ok) continue;
      for(int j=1;j<=right;j++)
         if(iHigh(sym, tf, k-j) >= hk) { ok=false; break; }
      if(!ok) continue;

      // confirmed pivot high at k
      if(idx1 == -1) idx1 = k;
      else { idx2 = idx1; idx1 = k; }
      if(idx2 != -1) return true;
   }
   return false;
}

bool GetLastTwoPivotLows(const string sym, ENUM_TIMEFRAMES tf, int left, int right, int lookback,
                        int &idx1, int &idx2)
{
   idx1 = -1; idx2 = -1;
   int bars = iBars(sym, tf);
   if(bars < left+right+10) return false;

   int start = MathMin(lookback, bars - right - 1);
   for(int k=start; k>=right+left; k--)
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
      else { idx2 = idx1; idx1 = k; }
      if(idx2 != -1) return true;
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

   bool ok=false;
   if(dir == SETUP_SELL)
      ok = trade.Sell(InpFixedLot, InpSymbolGold, 0.0, sl, tp, "SMT+PVT+MSB SELL");
   else if(dir == SETUP_BUY)
      ok = trade.Buy(InpFixedLot, InpSymbolGold, 0.0, sl, tp, "SMT+PVT+MSB BUY");

   if(ok)
   {
      setup_dir = SETUP_NONE;
      setup_time = 0;
      return true;
   }
   return false;
}

//-------------------- EA Lifecycle --------------------
int OnInit()
{
   if(!EnsureSymbols())
   {
      Print("Symbol select failed. Check symbol names: ", InpSymbolGold, " / ", InpSymbolSilver);
      return INIT_FAILED;
   }
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
