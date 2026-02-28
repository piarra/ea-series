//+------------------------------------------------------------------+
//| XAUUSD Mean-Reversion LONG ONLY (M15) with DCA(3) + Stop(4th)    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input string InpSymbol          = "XAUUSD";
input ENUM_TIMEFRAMES InpTF     = PERIOD_M15;

// Entry (mean reversion)
input int    MaPeriod           = 64;
input int    StdPeriod          = 64;
input bool   UseEMA             = true;
input double Z_Entry            = 2.2;      // enter when z <= -Z_Entry

// DCA settings
input int    MaxDcaStages       = 3;        // allow up to 3 stages (1st + adds until stage==3)
input double DcaStep_ATR        = 1.2;      // add next stage when price moves against by ATR*step
input double LotMultiplier      = 1.6;      // lots *= multiplier each added stage
input bool   AllowReEnterAfterStop = true;  // after 4th trigger stopout, allow immediate new cycle if signal still valid
input int    CooldownBarsAfterStop = 1;     // wait N new bars after stopout before re-entering

// Position sizing (base lot)
input bool   UseRiskPercent     = false;    // simple base lots by default (DCA strategy often uses fixed)
input double RiskPercent        = 0.5;      // if true, base lot from SL distance (not used here unless you add SL)
input double BaseLots           = 0.10;

// Take Profit mode
enum TPMode { TP_ATR = 0, TP_POINTS = 1 };
input TPMode TakeProfitMode     = TP_ATR;
input double TP_ATR_Mult        = 1.8;      // TP distance = ATR * mult (from weighted avg entry)
input double TP_Points          = 350;      // TP distance in points (from weighted avg entry)

// Safety
input double MaxSpreadPoints    = 80;
input int    Magic              = 20260228;

datetime last_bar_time = 0;

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

double NormalizeLots(string sym, double lots){
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots/step)*step;
   return lots;
}

// Return count of BUY positions for this EA
int CountBuys(string sym){
   int c=0;
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==POSITION_TYPE_BUY) c++;
      }
   }
   return c;
}

// Weighted average entry price + total volume
bool GetBuyBasket(string sym, double &avgPrice, double &totalVol, double &worstEntry){
   avgPrice=0; totalVol=0; worstEntry=DBL_MAX;
   double sumPV=0;

   bool any=false;
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==POSITION_TYPE_BUY){
            any=true;
            double vol   = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            sumPV += vol*price;
            totalVol += vol;
            if(price < worstEntry) worstEntry = price; // for BUY, worst entry is the lowest? (actually worst for buy is highest; but DCA trigger uses last add anchor; we'll store separately)
         }
      }
   }
   if(!any || totalVol<=0) return false;
   avgPrice = sumPV/totalVol;
   return true;
}

// Find last added BUY entry price (most recent open time)
bool GetLastBuyEntry(string sym, double &lastPrice){
   datetime bestT=0; lastPrice=0;
   bool any=false;

   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==POSITION_TYPE_BUY){
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

// Close all EA BUY positions
void CloseAllBuys(string sym){
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==POSITION_TYPE_BUY){
            trade.PositionClose(ticket);
         }
      }
   }
}

double CalcBasketTP(string sym, double avgPrice, double atr){
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(point<=0 || digits<0) return 0.0;

   double tpDistPrice=0;
   if(TakeProfitMode==TP_ATR){
      tpDistPrice = atr * TP_ATR_Mult;
   } else {
      tpDistPrice = TP_Points * point;
   }
   return NormalizeDouble(avgPrice + tpDistPrice, digits);
}

// Apply/Update TP for all BUY positions to same basket TP
void UpdateBasketTP(string sym, double basketTP){
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0 || basketTP<=0) return;

   // modify each position TP (keep SL as-is)
   for(int i=PositionsTotal()-1; i>=0; --i){
      if(PositionGetTicket(i)){
         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         string ps = PositionGetString(POSITION_SYMBOL);
         long pm   = PositionGetInteger(POSITION_MAGIC);
         long pt   = PositionGetInteger(POSITION_TYPE);
         if(ps==sym && pm==Magic && pt==POSITION_TYPE_BUY){
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
void ManageBasketTakeProfit(string sym, double atr){
   double avgP, totV, dummy;
   if(!GetBuyBasket(sym, avgP, totV, dummy)) return;
   if(atr<=0) return;

   double basketTP = CalcBasketTP(sym, avgP, atr);
   if(basketTP<=0) return;

   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point<=0) return;

   // Virtual TP fallback: if target is reached but some tickets had no TP, force close.
   if(bid >= basketTP - point*0.5){
      CloseAllBuys(sym);
      return;
   }

   // Some brokers reject TP too close to current price; skip modify and keep virtual TP fallback.
   int stopsLevel = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   double minTP = bid + (stopsLevel + 1) * point;
   if(basketTP <= minTP) return;

   UpdateBasketTP(sym, basketTP);
}

// cooldown tracking via GlobalVariable
string GV_CooldownName(string sym){ return "MRDCA_COOLDOWN_"+sym+"_"+(string)Magic; }
bool InCooldown(string sym){
   string n = GV_CooldownName(sym);
   if(!GlobalVariableCheck(n)) return false;
   double v = GlobalVariableGet(n);
   // v = bar time until which cooldown applies (as datetime stored in double)
   datetime until = (datetime)v;
   return (TimeCurrent() < until);
}
void SetCooldownBars(string sym, ENUM_TIMEFRAMES tf, int bars){
   if(bars<=0) return;
   datetime nextBar = iTime(sym, tf, 0) + PeriodSeconds(tf)*bars;
   GlobalVariableSet(GV_CooldownName(sym), (double)nextBar);
}

// ---------------- main ----------------
int OnInit(){
   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}

void OnTick(){
   string sym = InpSymbol;
   if(!SymbolSelect(sym, true)) return;

   // TP maintenance and recovery run every tick, not only on new bar.
   int liveStage = CountBuys(sym);
   if(liveStage > 0){
      double atrNow = GetATR(sym, InpTF, 14);
      if(atrNow!=EMPTY_VALUE && atrNow>0){
         ManageBasketTakeProfit(sym, atrNow);
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

   int stage = CountBuys(sym); // stage = number of current buys in basket (Hedging)

   // --- DCA / Stopout logic (only if already in position)
   if(stage > 0){
      double lastEntry;
      if(!GetLastBuyEntry(sym, lastEntry)) return;

      // next add trigger distance
      double stepDist = atr * DcaStep_ATR;
      double nextLevel = lastEntry - stepDist;

      // If price went against enough for "next stage"
      if(bid <= nextLevel){
         if(stage < MaxDcaStages){
            // Add next stage
            double lots = NormalizeLots(sym, BaseLots * MathPow(LotMultiplier, stage)); // stage=1 -> 2nd entry multiplier^1
            trade.Buy(lots, sym, ask, 0, 0, "DCA add");
            // After adding, TP is maintained by ManageBasketTakeProfit() on every tick.
         } else {
            // This would be the "4th stage" trigger -> stop out and reset
            CloseAllBuys(sym);
            SetCooldownBars(sym, InpTF, CooldownBarsAfterStop);
         }
      }
      return; // if we already have basket, we don't open new initial here (keep clean)
   }

   // --- No position: entry condition (mean reversion)
   if(InCooldown(sym)) return;

   bool entryOK = (z <= -Z_Entry);
   if(!entryOK) return;

   double lots0 = NormalizeLots(sym, BaseLots);
   trade.Buy(lots0, sym, ask, 0, 0, "MR entry");
}
