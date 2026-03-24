//+------------------------------------------------------------------+
//|                                                FactorEnsemble.mq5|
//|   Volatility-Targeted Multi-Factor EA for MT5                    |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//======================== Inputs ====================================
input long   InpMagicNumber            = 20260315;
input ENUM_TIMEFRAMES InpTF            = PERIOD_H1;

input int    InpFastEMA                = 50;
input int    InpSlowEMA                = 200;

input int    InpATRShort               = 20;
input int    InpATRLong                = 200;
input int    InpMomentumPeriod         = 20;
input int    InpLiquidityPeriod        = 20;

input double InpBaseRiskPct            = 0.50;   // target risk as % equity per strong signal
input double InpMaxPositionLots        = 1.00;   // hard cap
input double InpMinPositionLots        = 0.01;
input double InpSignalEntryThreshold   = 0.20;   // minimum abs(signal) to act
input double InpSignalExitThreshold    = 0.05;   // flatten near zero
input double InpHighVolThreshold       = 1.50;   // ATR short / ATR long
input double InpRangeVolThreshold      = 0.70;   // ATR short / ATR long
input double InpTrendStrengthThreshold = 0.50;   // normalized trend threshold
input double InpRebalanceLotsStep      = 0.01;   // rebalance tolerance
input double InpEWMAFactorPerf         = 0.05;   // performance learning speed
input bool   InpUseStopLoss            = true;
input double InpStopATRMult            = 3.0;
input bool   InpUseTakeProfit          = false;
input double InpTPATRMult              = 2.0;

//======================== Globals ===================================
int hFastEMA = INVALID_HANDLE;
int hSlowEMA = INVALID_HANDLE;
int hATRShort = INVALID_HANDLE;
int hATRLong = INVALID_HANDLE;

datetime g_lastBarTime = 0;

// dynamic factor scores (EWMA-updated)
double g_scoreTrend = 1.0;
double g_scoreMR    = 1.0;
double g_scoreMom   = 1.0;
double g_scoreLiq   = 1.0;

// previous factor values to evaluate realized directional usefulness
double g_prevTrend = 0.0;
double g_prevMR    = 0.0;
double g_prevMom   = 0.0;
double g_prevLiq   = 0.0;
double g_prevClose = 0.0;
bool   g_hasPrev   = false;

//======================== Utility ===================================
double Clamp(const double x, const double lo, const double hi)
{
   if(x < lo) return lo;
   if(x > hi) return hi;
   return x;
}

double Sign(const double x)
{
   if(x > 0.0) return 1.0;
   if(x < 0.0) return -1.0;
   return 0.0;
}

double SafeDiv(const double a, const double b, const double fallback=0.0)
{
   if(MathAbs(b) < 1e-10) return fallback;
   return a / b;
}

bool CopyOne(const int handle, const int shift, double &value)
{
   double buf[];
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1)
      return false;
   value = buf[0];
   return true;
}

bool GetClose(const int shift, double &value)
{
   double arr[];
   if(CopyClose(_Symbol, InpTF, shift, 1, arr) < 1)
      return false;
   value = arr[0];
   return true;
}

bool GetTickVolumeAverage(const int period, const int shift, double &avgVol)
{
   long vols[];
   if(CopyTickVolume(_Symbol, InpTF, shift, period, vols) < period)
      return false;

   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += (double)vols[i];

   avgVol = sum / period;
   return true;
}

bool GetTickVolume(const int shift, double &vol)
{
   long v[];
   if(CopyTickVolume(_Symbol, InpTF, shift, 1, v) < 1)
      return false;
   vol = (double)v[0];
   return true;
}

double NormalizeLots(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = Clamp(lots, minLot, MathMin(maxLot, InpMaxPositionLots));
   lots = MathFloor(lots / stepLot) * stepLot;
   lots = NormalizeDouble(lots, 2);

   if(lots < minLot)
      lots = 0.0;

   return lots;
}

double CurrentPositionLots()
{
   if(!PositionSelect(_Symbol))
      return 0.0;

   long type = PositionGetInteger(POSITION_TYPE);
   double vol = PositionGetDouble(POSITION_VOLUME);

   if(type == POSITION_TYPE_BUY)  return vol;
   if(type == POSITION_TYPE_SELL) return -vol;
   return 0.0;
}

bool CloseCurrentPosition()
{
   if(!PositionSelect(_Symbol))
      return true;

   trade.SetExpertMagicNumber(InpMagicNumber);
   return trade.PositionClose(_Symbol);
}

bool SetOrFlipPosition(double targetLots, double stopATR, double tpATR)
{
   trade.SetExpertMagicNumber(InpMagicNumber);

   double currentLots = CurrentPositionLots();
   double diff = targetLots - currentLots;

   if(MathAbs(diff) < MathMax(InpRebalanceLotsStep, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)))
      return true;

   if(targetLots == 0.0)
      return CloseCurrentPosition();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = 0.0, tp = 0.0;

   // Netting-friendly approach: flatten if opposite sign, then open desired side.
   if(currentLots != 0.0 && Sign(currentLots) != Sign(targetLots))
   {
      if(!CloseCurrentPosition())
         return false;
      currentLots = 0.0;
   }

   double needed = NormalizeLots(MathAbs(targetLots) - MathAbs(currentLots));
   if(needed <= 0.0)
      return true;

   if(targetLots > 0.0)
   {
      if(InpUseStopLoss)  sl = ask - stopATR;
      if(InpUseTakeProfit) tp = ask + tpATR;
      return trade.Buy(needed, _Symbol, 0.0, sl, tp, "FactorEnsembleBuy");
   }
   else
   {
      if(InpUseStopLoss)  sl = bid + stopATR;
      if(InpUseTakeProfit) tp = bid - tpATR;
      return trade.Sell(needed, _Symbol, 0.0, sl, tp, "FactorEnsembleSell");
   }
}

bool IsNewBar()
{
   datetime t[];
   if(CopyTime(_Symbol, InpTF, 0, 1, t) < 1)
      return false;

   if(t[0] != g_lastBarTime)
   {
      g_lastBarTime = t[0];
      return true;
   }
   return false;
}

//======================== Factor Logic ===============================
bool ComputeFactors(
   double &trendF,
   double &mrF,
   double &momF,
   double &liqF,
   double &atrS,
   double &atrL,
   double &close0,
   double &close1
)
{
   double fastEMA, slowEMA;
   if(!CopyOne(hFastEMA, 1, fastEMA)) return false;
   if(!CopyOne(hSlowEMA, 1, slowEMA)) return false;
   if(!CopyOne(hATRShort, 1, atrS))   return false;
   if(!CopyOne(hATRLong, 1, atrL))    return false;
   if(!GetClose(1, close1))           return false;
   if(!GetClose(0, close0))           return false;

   if(atrS <= 0.0 || atrL <= 0.0)
      return false;

   // Trend factor: normalized EMA spread
   trendF = SafeDiv(fastEMA - slowEMA, atrS, 0.0);

   // Mean reversion factor: negative z-distance from slow EMA
   mrF = -SafeDiv(close1 - slowEMA, atrS, 0.0);

   // Momentum factor: rate of change normalized by ATR
   double closeMomPast;
   if(!GetClose(1 + InpMomentumPeriod, closeMomPast)) return false;
   momF = SafeDiv(close1 - closeMomPast, atrS, 0.0);

   // Liquidity proxy: current tick volume relative to recent average
   double volNow, volAvg;
   if(!GetTickVolume(1, volNow)) return false;
   if(!GetTickVolumeAverage(InpLiquidityPeriod, 2, volAvg)) return false;

   double liqRatio = SafeDiv(volNow, volAvg, 1.0);
   // centered around 0
   liqF = liqRatio - 1.0;

   return true;
}

void UpdateFactorScores(double lastClose)
{
   if(!g_hasPrev || g_prevClose <= 0.0)
      return;

   double ret = lastClose - g_prevClose; // realized last bar change
   double alpha = Clamp(InpEWMAFactorPerf, 0.001, 0.50);

   // Reward factor if its sign matched realized return direction
   double rewardTrend = g_prevTrend * ret;
   double rewardMR    = g_prevMR    * ret;
   double rewardMom   = g_prevMom   * ret;
   double rewardLiq   = g_prevLiq   * ret;

   // softplus-like clamp to avoid instability
   rewardTrend = Clamp(rewardTrend, -5.0, 5.0);
   rewardMR    = Clamp(rewardMR,    -5.0, 5.0);
   rewardMom   = Clamp(rewardMom,   -5.0, 5.0);
   rewardLiq   = Clamp(rewardLiq,   -5.0, 5.0);

   g_scoreTrend = MathMax(0.05, (1.0 - alpha) * g_scoreTrend + alpha * MathMax(0.0, rewardTrend + 1.0));
   g_scoreMR    = MathMax(0.05, (1.0 - alpha) * g_scoreMR    + alpha * MathMax(0.0, rewardMR    + 1.0));
   g_scoreMom   = MathMax(0.05, (1.0 - alpha) * g_scoreMom   + alpha * MathMax(0.0, rewardMom   + 1.0));
   g_scoreLiq   = MathMax(0.05, (1.0 - alpha) * g_scoreLiq   + alpha * MathMax(0.0, rewardLiq   + 1.0));
}

double ComputeEnsembleSignal(double trendF, double mrF, double momF, double liqF, double atrS, double atrL)
{
   // Regime detection
   double volRatio = SafeDiv(atrS, atrL, 1.0);
   bool highVol    = (volRatio > InpHighVolThreshold);
   bool rangeReg   = (volRatio < InpRangeVolThreshold);

   double trendStrength = MathAbs(trendF);

   // Dynamic weights from factor scores
   double sumScore = g_scoreTrend + g_scoreMR + g_scoreMom + g_scoreLiq;
   double wTrend = g_scoreTrend / sumScore;
   double wMR    = g_scoreMR    / sumScore;
   double wMom   = g_scoreMom   / sumScore;
   double wLiq   = g_scoreLiq   / sumScore;

   // Regime tilt
   if(rangeReg)
   {
      wMR    *= 1.35;
      wTrend *= 0.80;
      wMom   *= 0.90;
   }
   else if(trendStrength > InpTrendStrengthThreshold)
   {
      wTrend *= 1.35;
      wMom   *= 1.15;
      wMR    *= 0.60;
   }

   if(highVol)
   {
      wMR    *= 0.70;
      wMom   *= 0.85;
      wLiq   *= 1.10;
   }

   double norm = wTrend + wMR + wMom + wLiq;
   wTrend /= norm;
   wMR    /= norm;
   wMom   /= norm;
   wLiq   /= norm;

   // Composite signal
   double signal = wTrend * trendF + wMR * mrF + wMom * momF + wLiq * liqF;

   // Extra protection:
   // In strong trend, suppress opposing mean-reversion trades
   if(trendStrength > InpTrendStrengthThreshold)
   {
      if(Sign(signal) != Sign(trendF))
         signal *= 0.50;
   }

   // In very high vol, shrink signal
   if(highVol)
      signal *= 0.60;

   return signal;
}

double ComputeTargetLots(double signal, double atrS)
{
   if(atrS <= 0.0) return 0.0;

   // Translate ATR to money risk per 1 lot using stop distance
   double stopDistancePrice = atrS * InpStopATRMult;
   if(stopDistancePrice <= 0.0) return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double moneyRiskPerLot = (stopDistancePrice / tickSize) * tickValue;
   if(moneyRiskPerLot <= 0.0) return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double desiredRiskMoney = equity * (InpBaseRiskPct / 100.0) * MathMin(1.0, MathAbs(signal));

   double rawLots = desiredRiskMoney / moneyRiskPerLot;

   // Vol-target style shrink by current symbol volatility regime
   // higher ATR short/long means lower size
   double atrL;
   if(!CopyOne(hATRLong, 1, atrL)) atrL = atrS;
   double volRatio = SafeDiv(atrS, atrL, 1.0);
   rawLots /= MathMax(0.75, volRatio);

   rawLots = Clamp(rawLots, InpMinPositionLots, InpMaxPositionLots);
   rawLots = NormalizeLots(rawLots);

   return Sign(signal) * rawLots;
}

//======================== MT5 Lifecycle ==============================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);

   hFastEMA  = iMA(_Symbol, InpTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA  = iMA(_Symbol, InpTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATRShort = iATR(_Symbol, InpTF, InpATRShort);
   hATRLong  = iATR(_Symbol, InpTF, InpATRLong);

   if(hFastEMA == INVALID_HANDLE ||
      hSlowEMA == INVALID_HANDLE ||
      hATRShort == INVALID_HANDLE ||
      hATRLong == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed.");
      return(INIT_FAILED);
   }

   Print("FactorEnsemble EA initialized on ", _Symbol, " TF=", EnumToString(InpTF));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(hFastEMA  != INVALID_HANDLE) IndicatorRelease(hFastEMA);
   if(hSlowEMA  != INVALID_HANDLE) IndicatorRelease(hSlowEMA);
   if(hATRShort != INVALID_HANDLE) IndicatorRelease(hATRShort);
   if(hATRLong  != INVALID_HANDLE) IndicatorRelease(hATRLong);
}

void OnTick()
{
   if(!IsNewBar())
      return;

   double trendF, mrF, momF, liqF, atrS, atrL, close0, close1;
   if(!ComputeFactors(trendF, mrF, momF, liqF, atrS, atrL, close0, close1))
   {
      Print("ComputeFactors failed.");
      return;
   }

   // Update dynamic factor scores from the just-closed bar
   UpdateFactorScores(close1);

   double signal = ComputeEnsembleSignal(trendF, mrF, momF, liqF, atrS, atrL);

   double targetLots = 0.0;
   if(MathAbs(signal) >= InpSignalEntryThreshold)
      targetLots = ComputeTargetLots(signal, atrS);

   // flatten if signal weak
   if(MathAbs(signal) <= InpSignalExitThreshold)
      targetLots = 0.0;

   // stop/tp distances
   double stopATR = atrS * InpStopATRMult;
   double tpATR   = atrS * InpTPATRMult;

   bool ok = SetOrFlipPosition(targetLots, stopATR, tpATR);
   if(!ok)
      Print("Trade action failed. Error=", GetLastError());

   // store current factors for next performance update
   g_prevTrend = trendF;
   g_prevMR    = mrF;
   g_prevMom   = momF;
   g_prevLiq   = liqF;
   g_prevClose = close1;
   g_hasPrev   = true;

   Comment(
      "Signal=", DoubleToString(signal, 4), "\n",
      "Trend=", DoubleToString(trendF, 3), " MR=", DoubleToString(mrF, 3),
      " Mom=", DoubleToString(momF, 3), " Liq=", DoubleToString(liqF, 3), "\n",
      "Scores T/MR/Mo/L=", DoubleToString(g_scoreTrend,2), "/",
      DoubleToString(g_scoreMR,2), "/", DoubleToString(g_scoreMom,2), "/",
      DoubleToString(g_scoreLiq,2), "\n",
      "ATRs=", DoubleToString(atrS, _Digits), " / ", DoubleToString(atrL, _Digits), "\n",
      "TargetLots=", DoubleToString(targetLots, 2)
   );
}
