//+------------------------------------------------------------------+
//| BollingerBand Cross Long/Short EA (MT5)                         |
//| H4ロジック固定 / ショートはEnableShortがtrueなら実施             |
//+------------------------------------------------------------------+

#property strict

input double Lots          = 0.10;
input int    Slippage      = 3;
input int    MagicNumber   = 12345;
input int    TakeProfitPips = 9000;
input double BreakEvenK    = 1; // TP * k 利益で建値SL
input bool   EnableTrailOnTakeProfit = false; // BBタッチ時にトレーリングへ移行
input int    TrailingStopPips = 300; // トレーリングの最小幅(pips)
input int    TrailingATRPeriod  = 14;  // ATR計算期間
input double TrailingATRMultiplier = 2.5; // ATR倍率（ボラ依存の追随距離）
input int    TrailingStepPips = 5; // SLを更新する最小刻み(pips)

// ボリンジャーバンド設定
input int    BandsPeriod   = 20;
input double BandsDev      = 2.0;

// ★ ショート可否フラグ
input bool   EnableShort   = true;

// 内部制御
datetime lastTradeBarTimeLong = 0;
datetime lastTradeBarTimeShort = 0;
int bandsHandle = INVALID_HANDLE;
int atrHandle   = INVALID_HANDLE;
bool trailLongActive = false;
bool trailShortActive = false;

//+------------------------------------------------------------------+
int OnInit()
{
   bandsHandle = iBands(_Symbol, PERIOD_H4, BandsPeriod, 0, BandsDev, PRICE_CLOSE);
   if(bandsHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   atrHandle = iATR(_Symbol, PERIOD_H4, TrailingATRPeriod);
   if(atrHandle == INVALID_HANDLE)
      return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(bandsHandle != INVALID_HANDLE)
      IndicatorRelease(bandsHandle);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES TF = PERIOD_H4;

   int bars = Bars(sym, TF);
   if(bars < 3) return;

   // BBと終値取得
   double lower[], upper[], close[];
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(close, true);
   if(CopyBuffer(bandsHandle, 2, 0, 3, lower) < 3) return;
   if(CopyBuffer(bandsHandle, 1, 0, 3, upper) < 3) return;
   if(CopyClose(sym, TF, 0, 3, close) < 3) return;

   datetime time1 = iTime(sym, TF, 1);

   bool hasLong  = HasOpen(sym, MagicNumber, POSITION_TYPE_BUY);
   bool hasShort = HasOpen(sym, MagicNumber, POSITION_TYPE_SELL);

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   // ======= 建値SL：TP*k利益到達時 =======
   ApplyBreakEven(sym, MagicNumber, BreakEvenK);

   if(!hasLong)  trailLongActive = false;
   if(!hasShort) trailShortActive = false;

   // ======= トレーリング（BBタッチ後に発動） =======
   if(EnableTrailOnTakeProfit)
   {
      if(hasLong && trailLongActive)
         ApplyTrailing(sym, MagicNumber, POSITION_TYPE_BUY, TrailingStopPips);
      if(hasShort && trailShortActive)
         ApplyTrailing(sym, MagicNumber, POSITION_TYPE_SELL, TrailingStopPips);
   }

   // ======= ロング決済：上バンドタッチ =======
   if(hasLong && bid >= upper[0])
   {
      if(EnableTrailOnTakeProfit)
         trailLongActive = true;
      else
         CloseAll(sym, MagicNumber, POSITION_TYPE_BUY);
   }

   // ======= ショート決済：下バンドタッチ =======
   if(hasShort && ask <= lower[0])
   {
      if(EnableTrailOnTakeProfit)
         trailShortActive = true;
      else
         CloseAll(sym, MagicNumber, POSITION_TYPE_SELL);
   }

   // ======= エントリー =======

   // ロング：下バンド上抜け
   bool crossLong =
      (close[2] < lower[2]) &&
      (close[1] > lower[1]);

   bool newBarLong = (time1 != lastTradeBarTimeLong);

   if(!hasLong && crossLong && newBarLong)
   {
      Open(sym, Lots, Slippage, MagicNumber, POSITION_TYPE_BUY);
      lastTradeBarTimeLong = time1;
      trailLongActive = false;
   }

   // ショート：上バンド下抜け（フラグがtrueなら）
   bool crossShort =
      EnableShort &&
      (close[2] > upper[2]) &&
      (close[1] < upper[1]);

   bool newBarShort = (time1 != lastTradeBarTimeShort);

   if(!hasShort && crossShort && newBarShort)
   {
      Open(sym, Lots, Slippage, MagicNumber, POSITION_TYPE_SELL);
      lastTradeBarTimeShort = time1;
      trailShortActive = false;
   }
}

//+------------------------------------------------------------------+
bool HasOpen(string sym, int magic, ENUM_POSITION_TYPE type)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==sym &&
            PositionGetInteger(POSITION_MAGIC)==magic &&
            PositionGetInteger(POSITION_TYPE)==type)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void Open(string sym, double lots, int slippage, int magic, ENUM_POSITION_TYPE type)
{
   if(type==POSITION_TYPE_SELL && !EnableShort)
   {
      Print("EnableShort=false; skip SELL order.");
      return;
   }
   double price = (type==POSITION_TYPE_BUY)
      ? SymbolInfoDouble(sym, SYMBOL_ASK)
      : SymbolInfoDouble(sym, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double pip = (digits==3 || digits==5) ? point*10.0 : point;
   double tp = 0.0;
   if(TakeProfitPips > 0)
   {
      double dist = TakeProfitPips * pip;
      tp = (type==POSITION_TYPE_BUY) ? price + dist : price - dist;
      tp = NormalizeDouble(tp, digits);
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = sym;
   req.volume   = lots;
   req.magic    = magic;
   req.deviation = slippage;
   req.comment  = "M4V1";
   req.type     = (type==POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price    = price;
   if(tp > 0.0)
      req.tp    = tp;

   if(!OrderSend(req, res))
   {
      PrintFormat("OrderSend failed in Open: retcode=%d, last_error=%d", res.retcode, GetLastError());
   }
}

//+------------------------------------------------------------------+
void CloseAll(string sym, int magic, ENUM_POSITION_TYPE type)
{
   double price = (type==POSITION_TYPE_BUY)
      ? SymbolInfoDouble(sym, SYMBOL_BID)
      : SymbolInfoDouble(sym, SYMBOL_ASK);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==sym &&
            PositionGetInteger(POSITION_MAGIC)==magic &&
            PositionGetInteger(POSITION_TYPE)==type)
         {
            MqlTradeRequest req;
            MqlTradeResult  res;
            ZeroMemory(req);

            req.action = TRADE_ACTION_DEAL;
            req.symbol = sym;
            req.magic  = magic;
            req.volume = PositionGetDouble(POSITION_VOLUME);
            req.position = ticket; // Close the specific position in hedging mode
            req.comment = "M4V1";
            req.type   = (type==POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price  = price;

            if(!OrderSend(req, res))
            {
               PrintFormat("OrderSend failed in CloseAll: retcode=%d, last_error=%d", res.retcode, GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void ApplyBreakEven(string sym, int magic, double k)
{
   if(k <= 0.0 || TakeProfitPips <= 0)
      return;

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double pip = (digits==3 || digits==5) ? point*10.0 : point;
   double threshold = TakeProfitPips * pip * k;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=sym ||
         PositionGetInteger(POSITION_MAGIC)!=magic)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      if(type==POSITION_TYPE_BUY)
      {
         if(sl >= open) continue;
         if((bid - open) < threshold) continue;
      }
      else if(type==POSITION_TYPE_SELL)
      {
         if(sl > 0.0 && sl <= open) continue;
         if((open - ask) < threshold) continue;
      }
      else
      {
         continue;
      }

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);

      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = sym;
      req.position = ticket;
      req.sl       = NormalizeDouble(open, digits);
      if(tp > 0.0)
         req.tp    = NormalizeDouble(tp, digits);

      if(!OrderSend(req, res))
      {
         PrintFormat("OrderSend failed in ApplyBreakEven: retcode=%d, last_error=%d", res.retcode, GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
void ApplyTrailing(string sym, int magic, ENUM_POSITION_TYPE type, int trailingPips)
{
   if(trailingPips <= 0)
      return;

   // 価格関連
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double pip = (digits==3 || digits==5) ? point*10.0 : point;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   // ボラティリティに応じたトレイル幅（ATRベース）
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) < 1)
      return;
   double volTrail = atrBuf[0] * TrailingATRMultiplier;
   double minTrail = trailingPips * pip;
   double trail = MathMax(minTrail, volTrail);

   // 最小更新刻み
   double step = TrailingStepPips * pip;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=sym ||
         PositionGetInteger(POSITION_MAGIC)!=magic ||
         PositionGetInteger(POSITION_TYPE)!=type)
         continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double new_sl = sl;
      bool update_sl = false;
      double move_th = step > 0 ? step : point; // 更新最小幅

      if(type==POSITION_TYPE_BUY)
      {
         double cand_sl = bid - trail;
         // 少なくとも建値以上を維持（損益を食わない）
         if(cand_sl < open) cand_sl = open;
         // 十分に前進した時のみ更新
         if(sl <= 0.0 || cand_sl > sl + move_th)
         {
            new_sl = cand_sl;
            update_sl = true;
         }

      }
      else if(type==POSITION_TYPE_SELL)
      {
         double cand_sl = ask + trail;
         if(cand_sl > open) cand_sl = open;
         if(sl <= 0.0 || cand_sl < sl - move_th)
         {
            new_sl = cand_sl;
            update_sl = true;
         }
      }
      else
      {
         continue;
      }

      if(!update_sl)
         continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);

      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = sym;
      req.position = ticket;
      if(new_sl > 0.0)
         req.sl    = NormalizeDouble(new_sl, digits);

      if(!OrderSend(req, res))
      {
         PrintFormat("OrderSend failed in ApplyTrailing: retcode=%d, last_error=%d", res.retcode, GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
void CopyBands(string sym, ENUM_TIMEFRAMES tf, int p, int shift, double dev, int price, int mode, double &buff[], int cnt)
{
   ArraySetAsSeries(buff, true);
   CopyBuffer(iBands(sym, tf, p, shift, dev, price), mode, 0, cnt, buff);
}
//+------------------------------------------------------------------+
void CopyClose(string sym, ENUM_TIMEFRAMES tf, double &buff[], int cnt)
{
   ArraySetAsSeries(buff, true);
   CopyClose(sym, tf, 0, cnt, buff);
}
