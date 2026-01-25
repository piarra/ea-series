//+------------------------------------------------------------------+
//| BollingerBand Cross Long/Short EA (MT5)                         |
//| H4ロジック固定 / ショートはEnableShortがtrueなら実施             |
//+------------------------------------------------------------------+

// TP	annualProfit
// 5000	2821
// 6000	3337
// 7000	3586
// 8000	3787
// 9000	3986
// 10000	3792

#property strict

input double Lots          = 0.10;
input int    Slippage      = 3;
input int    MagicNumber   = 12345;
input int    TakeProfitPips = 9000;

// ボリンジャーバンド設定
input int    BandsPeriod   = 20;
input double BandsDev      = 2.0;

// ★ ショート可否フラグ
input bool   EnableShort   = true;

// 内部制御
datetime lastTradeBarTimeLong = 0;
datetime lastTradeBarTimeShort = 0;
int bandsHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   bandsHandle = iBands(_Symbol, PERIOD_H4, BandsPeriod, 0, BandsDev, PRICE_CLOSE);
   if(bandsHandle == INVALID_HANDLE)
      return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(bandsHandle != INVALID_HANDLE)
      IndicatorRelease(bandsHandle);
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

   // ======= ロング決済：上バンドタッチ =======
   if(hasLong && bid >= upper[0])
      CloseAll(sym, MagicNumber, POSITION_TYPE_BUY);

   // ======= ショート決済：下バンドタッチ =======
   if(hasShort && ask <= lower[0])
      CloseAll(sym, MagicNumber, POSITION_TYPE_SELL);

   // ======= エントリー =======

   // ロング：下バンド上抜け
   bool crossLong =
      (close[2] < lower[2]) &&
      (close[1] > lower[1]);

   bool newBarLong = (time1 != lastTradeBarTimeLong);

   if(!hasLong && !hasShort && crossLong && newBarLong)
   {
      Open(sym, Lots, Slippage, MagicNumber, POSITION_TYPE_BUY);
      lastTradeBarTimeLong = time1;
   }

   // ショート：上バンド下抜け（フラグがtrueなら）
   bool crossShort =
      EnableShort &&
      (close[2] > upper[2]) &&
      (close[1] < upper[1]);

   bool newBarShort = (time1 != lastTradeBarTimeShort);

   if(!hasLong && !hasShort && crossShort && newBarShort)
   {
      Open(sym, Lots, Slippage, MagicNumber, POSITION_TYPE_SELL);
      lastTradeBarTimeShort = time1;
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
