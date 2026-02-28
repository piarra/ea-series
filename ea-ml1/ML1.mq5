#property strict
#property version "1.00"
#property description "XAUUSD synthetic 10s bars -> features -> ONNX inference -> trade"

// ---- trade
#include <Trade/Trade.mqh>
CTrade trade;

// ---- Put your ONNX file under MQL5/Files/ and pack it as resource (recommended)
#resource "\\Files\\xgb_xau_10s_tp40_sl30.onnx" as uchar ModelBuf[]

// =====================
// Inputs
// =====================
input int      InpBarSeconds        = 10;     // bundled model is 10-second bars
input int      InpFeatures          = 14;     // must match ONNX training feature count
input double   InpBuyThreshold      = 0.62;   // trade only when p is strong
input double   InpSellThreshold     = 0.38;   // symmetric example (adjust to your model meaning)
input bool     InpLongOnly          = true;   // train.py labels are LONG-only
input double   InpLots              = 0.10;
input int      InpMagic             = 260228;

// Risk settings (XAU pip=0.01 assumed)
input double   InpPipSize           = 0.01;   // XAU: 0.01 = 1 pip
input int      InpTP_Pips           = 40;     // TP = 40 pips = 0.40
input int      InpSL_Pips           = 30;     // SL = 30 pips = 0.30

// Filters
input int      InpMaxSpreadPoints   = 400;     // block when spread too wide (points)
input double   InpMinAtrPips        = 10;     // minimum ATR(14) in pips (synthetic bars)
input double   InpMaxAtrPips        = 200;    // maximum ATR(14) in pips

// Limits
input int      InpMinBarsToStart    = 120;    // need enough bars for z-score etc.
input int      InpTickVolZWindow    = 60;     // window for tick_vol_z
input int      InpMaxBarsStored     = 2000;
input int      InpHorizonBars       = 6;      // should match train.py horizon_bars

// =====================
// ONNX
// =====================
long  g_onnx = INVALID_HANDLE;
ulong g_in_shape[];
ulong g_out0_shape[];
ulong g_out1_shape[];
int   g_onnx_mode = 0; // 1=label+prob, 2=single[1], 3=single[1,1], 4=single[1,2]

// =====================
// Synthetic bar state
// =====================
struct SynthBar
{
   datetime start;
   double open, high, low, close;
   double spread_sum, spread_max;
   long   tick_count;
   bool   valid;
};

SynthBar cur_bar;

// history arrays (newest at end)
datetime g_time[];
double   g_open[], g_high[], g_low[], g_close[];
double   g_spread_mean[], g_spread_max[];
double   g_tick_count[];

// =====================
// Utilities
// =====================
double MaxD(double a,double b){ return a>b?a:b; }
double MinD(double a,double b){ return a<b?a:b; }

bool SpreadOK()
{
   int sp = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (sp > 0 && sp <= InpMaxSpreadPoints);
}

// position direction: 1 buy, -1 sell, 0 none (only our magic)
int CurrentPosDir()
{
   if(!PositionSelect(_Symbol)) return 0;
   if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) return 0;
   long type = PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY)  return 1;
   if(type == POSITION_TYPE_SELL) return -1;
   return 0;
}

void CloseIfOpposite(int desired_dir)
{
   int cur = CurrentPosDir();
   if(cur != 0 && desired_dir != 0 && cur != desired_dir)
      trade.PositionClose(_Symbol);
}

// mean/std over last N values in array (using tail)
bool MeanStdTail(const double &arr[], int n, double &mean, double &sd)
{
   int len = ArraySize(arr);
   if(len < n || n <= 1) return false;

   double s=0.0, s2=0.0;
   for(int i=len-n; i<len; i++)
   {
      double v = arr[i];
      s += v;
      s2 += v*v;
   }
   mean = s / n;
   // Match pandas rolling std default (ddof=1) used in training.
   double var = (s2 - (double)n * mean * mean) / (double)(n - 1);
   if(var < 1e-12) var = 1e-12;
   sd = MathSqrt(var);
   return true;
}

datetime ServerToUTC(datetime t_server)
{
   long offset = (long)TimeCurrent() - (long)TimeGMT();
   return (datetime)((long)t_server - offset);
}

// ATR(14) on synthetic bars using TR rolling mean
bool ATR14(double &atr)
{
   int len = ArraySize(g_close);
   if(len < 15) return false;

   double sum = 0.0;
   for(int i=len-14; i<len; i++)
   {
      double h = g_high[i];
      double l = g_low[i];
      double pc = g_close[i-1];
      double tr = MaxD(h - l, MaxD(MathAbs(h - pc), MathAbs(l - pc)));
      sum += tr;
   }
   atr = sum / 14.0;
   return true;
}

// =====================
// Synthetic bar builder (tick-driven)
// =====================
datetime FloorToBucket(datetime t, int seconds)
{
   // floor server time to bucket of N seconds
   long tt = (long)t;
   long b = (tt / seconds) * seconds;
   return (datetime)b;
}

void StartNewBar(datetime bucket_start, double mid, double spread)
{
   cur_bar.start = bucket_start;
   cur_bar.open = cur_bar.high = cur_bar.low = cur_bar.close = mid;
   cur_bar.spread_sum = spread;
   cur_bar.spread_max = spread;
   cur_bar.tick_count = 1;
   cur_bar.valid = true;
}

void UpdateCurrentBar(double mid, double spread)
{
   if(!cur_bar.valid) return;
   cur_bar.high = MaxD(cur_bar.high, mid);
   cur_bar.low  = MinD(cur_bar.low, mid);
   cur_bar.close = mid;
   cur_bar.spread_sum += spread;
   cur_bar.spread_max = MaxD(cur_bar.spread_max, spread);
   cur_bar.tick_count++;
}

void PushFinishedBar(const SynthBar &b)
{
   if(!b.valid || b.tick_count <= 0) return;

   // append history
   int len = ArraySize(g_close);
   if(len >= InpMaxBarsStored)
   {
      // drop oldest by shifting (simple; ok for moderate sizes)
      ArrayRemove(g_time, 0);
      ArrayRemove(g_open, 0);
      ArrayRemove(g_high, 0);
      ArrayRemove(g_low, 0);
      ArrayRemove(g_close, 0);
      ArrayRemove(g_spread_mean, 0);
      ArrayRemove(g_spread_max, 0);
      ArrayRemove(g_tick_count, 0);
   }

   ArrayResize(g_time, len+1);
   ArrayResize(g_open, len+1);
   ArrayResize(g_high, len+1);
   ArrayResize(g_low, len+1);
   ArrayResize(g_close, len+1);
   ArrayResize(g_spread_mean, len+1);
   ArrayResize(g_spread_max, len+1);
   ArrayResize(g_tick_count, len+1);

   g_time[len] = b.start;
   g_open[len] = b.open;
   g_high[len] = b.high;
   g_low[len]  = b.low;
   g_close[len]= b.close;
   g_spread_mean[len] = b.spread_sum / (double)b.tick_count;
   g_spread_max[len]  = b.spread_max;
   g_tick_count[len]  = (double)b.tick_count;
}

// returns true when a bar is closed and pushed
bool UpdateSyntheticBarsOnTick()
{
   // Get prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return false;

   double mid = (bid + ask) / 2.0;
   double spread = (ask - bid);

   datetime now = TimeCurrent();
   datetime bucket = FloorToBucket(now, InpBarSeconds);

   if(!cur_bar.valid)
   {
      StartNewBar(bucket, mid, spread);
      return false;
   }

   if(bucket == cur_bar.start)
   {
      UpdateCurrentBar(mid, spread);
      return false;
   }

   // bucket changed: close previous bar
   SynthBar finished = cur_bar;

   // start new bucket with current tick
   StartNewBar(bucket, mid, spread);

   // push finished
   PushFinishedBar(finished);
   return true;
}

// =====================
// Features (must match training!)
// =====================
bool BuildFeatures(vector &x)
{
   x = vector(InpFeatures);

   int len = ArraySize(g_close);
   if(len < InpMinBarsToStart) return false;

   // Use last closed synthetic bar index i = len-1
   int i = len - 1;

   // ret1, ret2, mom3
   double c0 = g_close[i];
   double c1 = g_close[i-1];
   double c2 = g_close[i-2];
   double c3 = g_close[i-3];

   double ret1 = (c0 - c1) / (c1 == 0 ? 1.0 : c1);
   double ret2 = (c0 - c2) / (c2 == 0 ? 1.0 : c2);
   double mom3 = (c0 - c3) / (c3 == 0 ? 1.0 : c3);

   double rng = (g_high[i] - g_low[i]);
   if(rng <= 0) return false;

   double body_ratio = MathAbs(g_close[i] - g_open[i]) / rng;
   double upper_wick = (g_high[i] - MaxD(g_open[i], g_close[i])) / rng;
   double lower_wick = (MinD(g_open[i], g_close[i]) - g_low[i]) / rng;

   double atr14;
   if(!ATR14(atr14)) return false;

   // tick_vol and z-score over last window
   double tick_vol = g_tick_count[i];
   double m, sd;
   if(!MeanStdTail(g_tick_count, InpTickVolZWindow, m, sd)) return false;
   double tick_vol_z = (tick_vol - m) / sd;

   // time-of-day cyclical (UTC), matching train.py.
   datetime t = ServerToUTC(g_time[i]);
   MqlDateTime st;
   TimeToStruct(t, st);
   double hh = (double)st.hour + (double)st.min/60.0 + (double)st.sec/3600.0;
   double tod_sin = MathSin(2.0 * M_PI * hh / 24.0);
   double tod_cos = MathCos(2.0 * M_PI * hh / 24.0);

   // spread stats for this bar
   double spread_mean = g_spread_mean[i];
   double spread_mx   = g_spread_max[i];

   // Fill in (order MUST match python training)
   // [ ret1, ret2, mom3, range, body_ratio, upper_wick, lower_wick, atr14,
   //   spread_mean, spread_max, tick_vol, tick_vol_z, tod_sin, tod_cos ]
   x[0]  = ret1;
   x[1]  = ret2;
   x[2]  = mom3;
   x[3]  = rng;
   x[4]  = body_ratio;
   x[5]  = upper_wick;
   x[6]  = lower_wick;
   x[7]  = atr14;
   x[8]  = spread_mean;
   x[9]  = spread_mx;
   x[10] = tick_vol;
   x[11] = tick_vol_z;
   x[12] = tod_sin;
   x[13] = tod_cos;

   return true;
}

// =====================
// ONNX inference
// =====================
bool Predict(double &p)
{
   vector x;
   if(!BuildFeatures(x)) return false;

   matrixf X(1, InpFeatures);
   for(int j=0; j<InpFeatures; j++)
      X[0][j] = (float)x[j];

   if(g_onnx_mode == 1)
   {
      vectorf y_label(1);
      matrixf y_prob(1, 2);
      if(!OnnxRun(g_onnx, 0, X, y_label, y_prob))
      {
         Print("OnnxRun(mode=1) failed err=", GetLastError());
         return false;
      }
      p = (double)y_prob[0][1];
      return true;
   }
   if(g_onnx_mode == 2)
   {
      vectorf y(1);
      if(!OnnxRun(g_onnx, 0, X, y))
      {
         Print("OnnxRun(mode=2) failed err=", GetLastError());
         return false;
      }
      p = (double)y[0];
      return true;
   }
   if(g_onnx_mode == 3)
   {
      matrixf y(1, 1);
      if(!OnnxRun(g_onnx, 0, X, y))
      {
         Print("OnnxRun(mode=3) failed err=", GetLastError());
         return false;
      }
      p = (double)y[0][0];
      return true;
   }
   if(g_onnx_mode == 4)
   {
      matrixf y(1, 2);
      if(!OnnxRun(g_onnx, 0, X, y))
      {
         Print("OnnxRun(mode=4) failed err=", GetLastError());
         return false;
      }
      p = (double)y[0][1];
      return true;
   }

   Print("ONNX mode not configured.");
   return false;
}

// =====================
// Trading
// =====================
bool AtrFilterOK()
{
   double atr14;
   if(!ATR14(atr14)) return false;

   // Convert ATR price to pips using pip_size
   double atr_pips = atr14 / InpPipSize;
   return (atr_pips >= InpMinAtrPips && atr_pips <= InpMaxAtrPips);
}

bool OpenTrade(int dir)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return false;

   double tp_price = InpTP_Pips * InpPipSize; // e.g. 40*0.01 = 0.40
   double sl_price = InpSL_Pips * InpPipSize; // e.g. 30*0.01 = 0.30

   double sl=0, tp=0;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   if(dir > 0)
   {
      // BUY at ask
      sl = bid - sl_price;
      tp = bid + tp_price;
      return trade.Buy(InpLots, _Symbol, ask, sl, tp, "ONNX BUY");
   }
   else if(dir < 0)
   {
      // SELL at bid
      sl = ask + sl_price;
      tp = ask - tp_price;
      return trade.Sell(InpLots, _Symbol, bid, sl, tp, "ONNX SELL");
   }
   return false;
}

int BarsHeldForOurPosition()
{
   if(!PositionSelect(_Symbol)) return 0;
   if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) return 0;

   datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
   datetime ob = FloorToBucket(ot, InpBarSeconds);
   datetime nb = FloorToBucket(TimeCurrent(), InpBarSeconds);

   long diff = (long)nb - (long)ob;
   if(diff <= 0) return 0;
   return (int)(diff / InpBarSeconds);
}

void CloseIfHorizonReached()
{
   if(InpHorizonBars <= 0) return;
   if(!PositionSelect(_Symbol)) return;
   if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) return;

   int held = BarsHeldForOurPosition();
   if(held >= InpHorizonBars)
      trade.PositionClose(_Symbol);
}

// =====================
// MT5 lifecycle
// =====================
int OnInit()
{
   if(InpBarSeconds != 10)
   {
      Print("This bundled model is 10s only. Set InpBarSeconds=10.");
      return INIT_FAILED;
   }
   if(InpFeatures != 14)
   {
      Print("This EA currently expects 14 features (change code if your ONNX differs).");
      // you can still proceed, but feature order must match training
   }
   if(InpHorizonBars <= 0)
   {
      Print("InpHorizonBars must be >= 1");
      return INIT_FAILED;
   }
   if(InpTP_Pips != 40 || InpSL_Pips != 30 || MathAbs(InpPipSize - 0.01) > 1e-12)
      Print("WARN: model labels were trained with pip_size=0.01, TP=40, SL=30.");
   if(InpHorizonBars != 6)
      Print("WARN: model labels were trained with horizon_bars=6.");

   // ONNX load from resource buffer
   g_onnx = OnnxCreateFromBuffer(ModelBuf, 0);
   if(g_onnx == INVALID_HANDLE)
   {
      Print("OnnxCreateFromBuffer failed err=", GetLastError());
      return INIT_FAILED;
   }

   // Input shape [1, F]
   ArrayResize(g_in_shape, 2);
   g_in_shape[0] = 1;
   g_in_shape[1] = (ulong)InpFeatures;

   if(!OnnxSetInputShape(g_onnx, 0, g_in_shape))
   {
      Print("OnnxSetInputShape failed err=", GetLastError());
      OnnxRelease(g_onnx);
      return INIT_FAILED;
   }

   // Try to match common XGB classifier exports first: output0=label[1], output1=prob[1,2]
   ArrayResize(g_out0_shape, 1);
   g_out0_shape[0] = 1;
   ArrayResize(g_out1_shape, 2);
   g_out1_shape[0] = 1;
   g_out1_shape[1] = 2;
   if(OnnxSetOutputShape(g_onnx, 0, g_out0_shape) &&
      OnnxSetOutputShape(g_onnx, 1, g_out1_shape))
   {
      g_onnx_mode = 1;
   }
   else
   {
      // Fallback A: single output [1]
      if(OnnxSetOutputShape(g_onnx, 0, g_out0_shape))
      {
         g_onnx_mode = 2;
      }
      else
      {
         // Fallback B: single output [1,1]
         ArrayResize(g_out0_shape, 2);
         g_out0_shape[0] = 1;
         g_out0_shape[1] = 1;
         if(OnnxSetOutputShape(g_onnx, 0, g_out0_shape))
         {
            g_onnx_mode = 3;
         }
         else
         {
            // Fallback C: single output [1,2]
            ArrayResize(g_out0_shape, 2);
            g_out0_shape[0] = 1;
            g_out0_shape[1] = 2;
            if(OnnxSetOutputShape(g_onnx, 0, g_out0_shape))
               g_onnx_mode = 4;
         }
      }
   }

   if(g_onnx_mode == 0)
   {
      Print("Could not configure ONNX output shape(s). err=", GetLastError());
      OnnxRelease(g_onnx);
      return INIT_FAILED;
   }

   // init current bar
   cur_bar.valid = false;

   PrintFormat("EA initialized. onnx_mode=%d Waiting for synthetic bars...", g_onnx_mode);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_onnx != INVALID_HANDLE) OnnxRelease(g_onnx);
}

void OnTick()
{
   // Build synthetic bars from ticks
   bool bar_closed = UpdateSyntheticBarsOnTick();
   if(!bar_closed) return;

   // Label horizon in training is finite; enforce time exit on live position.
   CloseIfHorizonReached();

   // Filters that matter a lot for scalping
   if(!SpreadOK()) return;
   if(!AtrFilterOK()) return;

   // Predict
   double p;
   if(!Predict(p)) return;

   // Decide signal (you can customize this logic based on what your model outputs)
   int sig = 0;
   if(p >= InpBuyThreshold) sig = 1;
   else if(!InpLongOnly && p <= InpSellThreshold) sig = -1;

   if(sig == 0) return;

   // Close opposite, then open if flat
   CloseIfOpposite(sig);

   if(CurrentPosDir() == 0)
      OpenTrade(sig);

   PrintFormat("SynthBar=%ds p=%.4f sig=%d spreadPts=%d",
               InpBarSeconds, p, sig, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
}
