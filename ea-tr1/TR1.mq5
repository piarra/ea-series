#property copyright "Aki"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// this is for hedge account only

#include <Trade/Trade.mqh>

input int    MagicNumber       = 310001;
input double BaseLot           = 0.10;
input int    FastEmaPeriod     = 20;
input int    SlowEmaPeriod     = 50;
input int    ConfirmBarsStartup = 5;     // 起動時に確認する過去バー数
input bool   EnterOnInit       = true;   // 起動直後に即エントリーするか
input double MaxSpreadPoints   = 40;     // スプレッド上限 (ポイント)
input int    SyntheticBarSec   = 10;     // オンメモリ足の秒数（例:10秒）
input int    SlippagePoints    = 20;
input string TradeComment      = "TR1";
input int    MinTradeIntervalMs = 300;   // 連続OrderSend間の最小インターバル（ミリ秒）
input bool   EnableInfoLog     = false;  // 詳細ログ出力を有効化
input double BreakevenBufferPoints = 30; // 建値SLに上乗せするバッファ（ポイント）

// ボラティリティ連動パラメータ（10秒足ATRベース）
input int            AtrPeriod      = 20;
input double         ScalpAtrTpMult = 0.32; // SCALP 利確 = ATR×0.32
input double         SwingAtrTpMult = 1.05; // SWING 初期TP = ATR×1.05
input double         SwingTrailMult = 1.00; // SWING トレーリング距離 = ATR×1.0
input double         StopAtrMult    = 1.00; // 共通ストップ = ATR×1.0
input int            ScalpRefillIntervalSec = 1; // SCALP消失後に新ペアを建てるまでの待機秒数

enum TrendDirection
{
  TREND_NONE = 0,
  TREND_BUY  = 1,
  TREND_SELL = -1
};

CTrade trade;

datetime g_last_close_time = 0;
double   g_tr_atr = 0.0;        // 10秒合成足ベースのATR（価格単位）
double   g_prev_close = 0.0;    // 直近合成足の終値
ulong    g_last_trade_us = 0;   // 直近の注文リクエスト時刻 (マイクロ秒)
bool     g_action_used_this_tick = false; // 1tick=1action を強制
datetime g_last_refill_time = 0; // SCALP消失後の再エントリー間隔管理

// ペア初動を2tickに分割して送るための簡易ステート
enum OpenPhase
{
  OPEN_IDLE = 0,   // 何も準備していない
  OPEN_SWING,      // SWING 建玉を試行中
  OPEN_SCALP       // SWING 成功後、SCALP を追加予定
};

OpenPhase g_open_phase = OPEN_IDLE;
TrendDirection g_open_dir = TREND_NONE; // 開始時に決めた方向を保持

// 30秒バー生成用
datetime g_curr_slot_start = 0;
double   g_bar_open = 0, g_bar_high = 0, g_bar_low = 0, g_bar_close = 0;
int      g_bar_count = 0;
double   g_fast_ema = 0, g_slow_ema = 0;
int      g_trend_history[];
bool     g_startup_done = false;

// pip換算 (5桁/3桁は10ポイント = 1pip)
int PipSizeInPoints()
{
  if (_Digits == 3 || _Digits == 5)
    return 10;
  return 1;
}

int VolumeDigits()
{
  double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if (step <= 0)
    return 2; // fallback

  // Convert volume step (e.g., 0.01) to number of decimal places
  int digits = (int)MathRound(-MathLog(step) / MathLog(10.0));
  if (digits < 0) digits = 0;
  if (digits > 8) digits = 8;
  return digits;
}

// OrderSendスパム防止: 直近送信から MinTradeIntervalMs 経過したら許可
bool TradeRequestAllowed()
{
  // 1tick=1action の上限
  if (g_action_used_this_tick)
    return false;

  ulong now = GetMicrosecondCount();
  ulong gap_us = (ulong)MinTradeIntervalMs * 1000;

  if (g_last_trade_us == 0)
    return true;

  if (now >= g_last_trade_us)
    return (now - g_last_trade_us) >= gap_us;

  // wrap-around時は保守的に許可
  return true;
}

void MarkTradeRequest()
{
  g_action_used_this_tick = true;
  g_last_trade_us = GetMicrosecondCount();
}

// ATR をポイント換算で返す（前回値をキャッシュしてゼロ回避）
double AtrPoints()
{
  if (g_tr_atr <= 0.0)
    return 0.0;
  return g_tr_atr / _Point;
}

double ScalpTakeProfitPoints()
{
  return AtrPoints() * ScalpAtrTpMult;
}

double SwingTakeProfitPoints()
{
  return AtrPoints() * SwingAtrTpMult;
}

double SwingTrailPoints()
{
  return AtrPoints() * SwingTrailMult;
}

double StopLossPoints()
{
  return AtrPoints() * StopAtrMult;
}

// ポジションをインデックスで選択（PositionSelectByIndex が使えない環境向けフォールバック）
bool SelectPositionByIndex(int index)
{
#ifdef __MQL5__
  ulong ticket = PositionGetTicket(index);
  if (ticket == 0)
    return false;
  return PositionSelectByTicket(ticket);
#else
  return false;
#endif
}

// オンメモリの短期足（SyntheticBarSec秒）を構築し、EMAを手計算する
void UpdateEmaOnClose(double closePrice)
{
  double kFast = 2.0 / (FastEmaPeriod + 1.0);
  double kSlow = 2.0 / (SlowEmaPeriod + 1.0);

  if (g_bar_count <= 1)
  {
    g_fast_ema = closePrice;
    g_slow_ema = closePrice;
  }
  else
  {
    g_fast_ema = kFast * closePrice + (1.0 - kFast) * g_fast_ema;
    g_slow_ema = kSlow * closePrice + (1.0 - kSlow) * g_slow_ema;
  }

  TrendDirection dir = (g_fast_ema >= g_slow_ema) ? TREND_BUY : TREND_SELL;

  int sz = ArraySize(g_trend_history);
  ArrayResize(g_trend_history, sz + 1);
  g_trend_history[sz] = dir;

  if (EnableInfoLog)
  {
    Print(__FUNCTION__, ": bar#", g_bar_count, " close=", DoubleToString(closePrice, _Digits),
          " fastEma=", DoubleToString(g_fast_ema, _Digits),
          " slowEma=", DoubleToString(g_slow_ema, _Digits),
          " dir=", dir);
  }
}

// 10秒合成足を用いたATR（Period=AtrPeriod）を更新
void UpdateSyntheticATR()
{
  double tr;

  if (g_bar_count <= 1)
  {
    g_tr_atr = (g_bar_high - g_bar_low);
  }
  else
  {
    double hl = g_bar_high - g_bar_low;
    double hc = MathAbs(g_bar_high - g_prev_close);
    double lc = MathAbs(g_bar_low  - g_prev_close);

    tr = MathMax(hl, MathMax(hc, lc));

    double k = 2.0 / (AtrPeriod + 1.0);
    g_tr_atr = k * tr + (1.0 - k) * g_tr_atr;
  }

  g_prev_close = g_bar_close;
}

void FinalizeSyntheticBar()
{
  g_bar_count++;
  UpdateEmaOnClose(g_bar_close);
  UpdateSyntheticATR();
}

void StartNewSyntheticBar(datetime slot, double price)
{
  g_curr_slot_start = slot;
  g_bar_open = g_bar_high = g_bar_low = g_bar_close = price;
}

void UpdateSyntheticBar()
{
  double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  datetime now = TimeCurrent();
  int sec = MathMax(1, SyntheticBarSec);
  datetime slot = now - (now % sec);

  if (g_curr_slot_start == 0)
  {
    StartNewSyntheticBar(slot, price);
    return;
  }

  if (slot == g_curr_slot_start)
  {
    g_bar_high = MathMax(g_bar_high, price);
    g_bar_low  = MathMin(g_bar_low,  price);
    g_bar_close = price;
    return;
  }

  // スロットが進んだら前バーを確定して新バー開始
  FinalizeSyntheticBar();
  StartNewSyntheticBar(slot, price);
}

TrendDirection DetectTrend()
{
  int sz = ArraySize(g_trend_history);
  if (sz == 0)
  {
    if (EnableInfoLog)
      Print(__FUNCTION__, ": no history, default BUY");
    return TREND_BUY;
  }

  TrendDirection dir = (TrendDirection)g_trend_history[sz - 1];
  if (EnableInfoLog)
    Print(__FUNCTION__, ": last dir=", dir, " bar#", g_bar_count);
  return dir;
}

bool ClosePositionByTicket(long ticket)
{
  if (!TradeRequestAllowed())
    return false;

  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(SlippagePoints);

  bool ok = trade.PositionClose((ulong)ticket);
  if (!ok)
  {
    PrintFormat("Close failed ticket %I64d: %d", ticket, GetLastError());
  }
  else
  {
    MarkTradeRequest();
    g_last_close_time = TimeCurrent();
  }
  return ok;
}

// 指定チケットのSL/TPを変更する（ヘッジ口座でも確実に対象を特定する）
bool ModifyPositionByTicket(long ticket, double sl, double tp)
{
  if (!TradeRequestAllowed())
    return false;

  if (!PositionSelectByTicket((ulong)ticket))
  {
    PrintFormat("%s: select ticket %I64d failed", __FUNCTION__, ticket);
    return false;
  }

  // 現在値・ストップレベル・フリーズレベルに基づいて事前チェック
  int    posType     = (int)PositionGetInteger(POSITION_TYPE);
  double curSL       = PositionGetDouble(POSITION_SL);
  double curTP       = PositionGetDouble(POSITION_TP);
  double ask         = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid         = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double stopLevel   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
  double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
  double safetyGap   = 2.0 * _Point; // cushion for price ticks while request is in flight
  double minGap      = MathMax(stopLevel, freezeLevel) + safetyGap;
  double eps         = _Point / 4.0;

  // sl/tp semantics:
  //  <0 : not provided (keep current)
  //   0 : clear
  //  >0 : set to price
  bool slProvided = (sl >= 0.0);
  bool tpProvided = (tp >= 0.0);

  double reqSL = curSL;
  double reqTP = curTP;

  if (slProvided)
    reqSL = (sl > 0.0) ? NormalizeDouble(sl, _Digits) : 0.0;
  if (tpProvided)
    reqTP = (tp > 0.0) ? NormalizeDouble(tp, _Digits) : 0.0;

  bool slNoChange = true;
  if (slProvided)
  {
    if (reqSL == 0.0)
      slNoChange = (curSL <= eps);
    else
      slNoChange = (MathAbs(reqSL - curSL) < eps);
  }

  bool tpNoChange = true;
  if (tpProvided)
  {
    if (reqTP == 0.0)
      tpNoChange = (curTP <= eps);
    else
      tpNoChange = (MathAbs(reqTP - curTP) < eps);
  }

  if (slNoChange && tpNoChange)
    return true;

  // 最小距離を満たさない場合はスキップ（ブローカー制約回避）
  if (minGap > 0.0)
  {
    if (posType == POSITION_TYPE_BUY)
    {
      if (slProvided && reqSL > 0.0 && (bid - reqSL) <= minGap)
      {
        if (EnableInfoLog)
          PrintFormat("%s: skip buy SL close gap=%.1f min=%.1f", __FUNCTION__, (bid - reqSL) / _Point, minGap / _Point);
        return false;
      }
      if (tpProvided && reqTP > 0.0 && (reqTP - ask) <= minGap)
      {
        if (EnableInfoLog)
          PrintFormat("%s: skip buy TP close gap=%.1f min=%.1f", __FUNCTION__, (reqTP - ask) / _Point, minGap / _Point);
        return false;
      }
    }
    else // SELL
    {
      if (slProvided && reqSL > 0.0 && (reqSL - ask) <= minGap)
      {
        if (EnableInfoLog)
          PrintFormat("%s: skip sell SL close gap=%.1f min=%.1f", __FUNCTION__, (reqSL - ask) / _Point, minGap / _Point);
        return false;
      }
      if (tpProvided && reqTP > 0.0 && (bid - reqTP) <= minGap)
      {
        if (EnableInfoLog)
          PrintFormat("%s: skip sell TP close gap=%.1f min=%.1f", __FUNCTION__, (bid - reqTP) / _Point, minGap / _Point);
        return false;
      }
    }
  }

  MqlTradeRequest  req;
  MqlTradeResult   res;
  ZeroMemory(req);
  ZeroMemory(res);

  req.action    = TRADE_ACTION_SLTP;
  req.position  = (ulong)ticket;
  req.symbol    = PositionGetString(POSITION_SYMBOL);
  req.sl        = reqSL;
  req.tp        = reqTP;
  req.deviation = SlippagePoints;
  req.magic     = MagicNumber;

  bool ok = OrderSend(req, res);
  if (!ok || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL))
  {
    PrintFormat("%s: ticket %I64d sltp failed ret=%d err=%d comment=%s", __FUNCTION__, ticket, res.retcode, GetLastError(), res.comment);
    return false;
  }

  MarkTradeRequest();
  return true;
}

// 指定コメントのポジションを探す（シンボル・マジック一致）。見つかればticketに設定しtrue。
bool FindTicketByComment(const string tag, ulong &ticket)
{
  ticket = 0;
  int total = PositionsTotal();
  for (int i = 0; i < total; i++)
  {
    if (!SelectPositionByIndex(i))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;
    if (PositionGetString(POSITION_COMMENT) != tag)
      continue;

    ticket = PositionGetInteger(POSITION_TICKET);
    return true;
  }
  return false;
}

// 当該シンボル＆マジックのポジションを1つでも持っているか
bool HasOurPosition()
{
  int total = PositionsTotal();
  for (int i = 0; i < total; i++)
  {
    if (!SelectPositionByIndex(i))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;
    return true;
  }
  return false;
}

// 指定コメントタグの本数をカウント（シンボル・マジック一致）
int CountPositionsByTag(const string tag)
{
  int total = PositionsTotal();
  int count = 0;
  for (int i = 0; i < total; i++)
  {
    if (!SelectPositionByIndex(i))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;
    if (PositionGetString(POSITION_COMMENT) != tag)
      continue;
    count++;
  }
  return count;
}

bool OpenSingle(const string tag, TrendDirection dir)
{
  if (!TradeRequestAllowed())
    return false;

  ENUM_ORDER_TYPE type = (dir == TREND_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  double lot = NormalizeDouble(BaseLot, VolumeDigits());

  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(SlippagePoints);

  bool ok = trade.PositionOpen(_Symbol, type, lot, 0, 0, 0, tag);

  MarkTradeRequest();
  return ok;
}

void ProcessEntryEngine()
{
  // 1tick=1action: 既にリクエストを使っていればスキップ
  if (g_action_used_this_tick)
    return;

  // 初期化中など、トレンド判定ができないときは待つ
  if (g_bar_count == 0)
    return;

  // ブローカー制約・環境条件チェック
  if (SpreadTooWide())
    return;

  if (AtrPoints() <= 0.0)
    return;

  // クローズ直後はクールダウン（1秒）
  if (g_last_close_time != 0 && (TimeCurrent() - g_last_close_time) < 1)
    return;

  // 新規エントリー開始時のみ 2秒ロックを適用
  if (g_open_phase == OPEN_IDLE && RecentlyTriedOpen())
    return;

  // オープンフェーズに従って1tick=1actionで順送り
  if (g_open_phase == OPEN_IDLE)
  {
    // ポジション保有中なら新規エントリーは行わない
    if (HasOurPosition())
      return;

    g_open_dir = DetectTrend();
    g_last_open_attempt = TimeCurrent();
    // 先にSCALPを建て、次tickでSWINGを建てる（1tick=1OrderSendを維持）
    if (OpenSingle("SCALP", g_open_dir))
      g_open_phase = OPEN_SWING;
    else
    {
      g_open_phase = OPEN_IDLE;
      g_open_dir = TREND_NONE;
    }
    return;
  }

  // SCALP建玉ができた次tickでSWINGを建てる
  if (g_open_phase == OPEN_SWING)
  {
    // SCALPが存在しない場合は中止
    if (CountPositionsByTag("SCALP") == 0)
    {
      g_open_phase = OPEN_IDLE;
      g_open_dir = TREND_NONE;
      return;
    }

    if (OpenSingle("SWING", g_open_dir))
    {
      g_open_phase = OPEN_IDLE;
      g_open_dir = TREND_NONE;
    }
    return;
  }
}

// SCALPがなくなったら新しいSWING+SCALPを同時に建てる
void StartPairIfScalpMissing()
{
  if (g_action_used_this_tick)
    return;

  // 初動の2段階オープン中はここでは建てない（重複防止）
  if (g_open_phase != OPEN_IDLE)
    return;

  int swing = CountPositionsByTag("SWING");
  int scalp = CountPositionsByTag("SCALP");

  if (swing == 0)
    return; // SWINGがなければ初動ロジックに任せる

  if (scalp > 0)
    return; // まだSCALPが残っている

  // インターバル待ち
  if (ScalpRefillIntervalSec > 0 && g_last_refill_time != 0 &&
      (TimeCurrent() - g_last_refill_time) < ScalpRefillIntervalSec)
    return;

  if (SpreadTooWide())
    return;

  if (AtrPoints() <= 0.0)
    return;

  if (g_bar_count == 0)
    return; // トレンド判定不可

  TrendDirection dir = DetectTrend();
  g_last_refill_time = TimeCurrent();
  // 1tick=1action を守るため、まずSCALPのみ建て、次tickでSWINGを建てる
  if (OpenSingle("SCALP", dir))
  {
    g_open_phase = OPEN_SWING;
    g_open_dir = dir;
  }
}

bool SpreadTooWide()
{
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double spread_points = (ask - bid) / _Point;
  return (spread_points > MaxSpreadPoints);
}

double CurrentSpreadPoints()
{
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  return (ask - bid) / _Point;
}

double CurrentProfitPoints(int posType, double entryPrice)
{
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  if (posType == POSITION_TYPE_BUY)
    return (bid - entryPrice) / _Point;
  else
    return (entryPrice - ask) / _Point;
}

// 2本構成（SWING/SCALP）のポジション管理
void ManageOpenPositions()
{
  int total = PositionsTotal();
  if (total == 0)
    return;

  double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
  double stopLossPts = StopLossPoints();
  double scalpTpPts  = ScalpTakeProfitPoints();
  double swingTpPts  = SwingTakeProfitPoints();
  double swingTrailPts = SwingTrailPoints();
  double trailUpdateGap = 20.0 * PipSizeInPoints() * _Point; // 20 pips
  static double lastTrailRefBuy = 0.0;
  static double lastTrailRefSell = 0.0;

  for (int i = total - 1; i >= 0; --i)
  {
    if (!SelectPositionByIndex(i))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;

    long   ticket   = PositionGetInteger(POSITION_TICKET);
    string tag      = PositionGetString(POSITION_COMMENT);
    int    posType  = (int)PositionGetInteger(POSITION_TYPE);
    double entry    = PositionGetDouble(POSITION_PRICE_OPEN);
    double profitPt = CurrentProfitPoints(posType, entry);

    // ロスカット（共通）
    if (stopLossPts > 0 && profitPt <= -stopLossPts)
    {
      ClosePositionByTicket(ticket);
      continue;
    }

    if (tag == "SCALP")
    {
      if (scalpTpPts > 0 && profitPt >= scalpTpPts)
      {
        ClosePositionByTicket(ticket);
      }
      continue;
    }

    if (tag == "SWING")
    {
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      // 建値＋トレーリングSL（最小ストップレベルを満たしたときのみ設定）
      double desiredSL = curSL;
      double refPrice  = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool   profitable = (posType == POSITION_TYPE_BUY)
                            ? (refPrice - entry >= stopLevel)
                            : (entry - refPrice >= stopLevel);
      bool   trailUpdated = false;

      double lastRef = (posType == POSITION_TYPE_BUY) ? lastTrailRefBuy : lastTrailRefSell;
      bool allowTrailUpdate = (lastRef == 0.0) || (MathAbs(refPrice - lastRef) >= trailUpdateGap);

      if (allowTrailUpdate)
      {
        double bufferPts = MathMax(BreakevenBufferPoints, CurrentSpreadPoints());

        if (posType == POSITION_TYPE_BUY)
        {
          // 1) 建値まで引き上げ
          if (profitable)
          {
            double be = entry + bufferPts * _Point;
            desiredSL = MathMax(desiredSL, be);
          }

          // 2) ATR×0.8 トレーリング
          if (swingTrailPts > 0)
          {
            double trail = refPrice - swingTrailPts * _Point;
            if (refPrice - trail >= stopLevel)
              desiredSL = MathMax(desiredSL, trail);
          }
        }
        else // SELL
        {
          // 1) 建値まで引き下げ
          if (profitable)
          {
            double be = entry - bufferPts * _Point;
            if (desiredSL == 0.0)
              desiredSL = be;
            else
              desiredSL = MathMin(desiredSL, be);
          }

          // 2) ATR×0.8 トレーリング
          if (swingTrailPts > 0)
          {
            double trail = refPrice + swingTrailPts * _Point;
            if (trail - refPrice >= stopLevel)
              desiredSL = MathMin(desiredSL, trail);
          }
        }
      }

      // TP: 初期は ATR×1.2、建値到達後かつトレーリング有効なら TP を外す
      double desiredTP = curTP;
      if (allowTrailUpdate)
      {
        if (profitable && swingTrailPts > 0)
        {
          desiredTP = 0.0; // トレーリングに任せる
        }
        else if (swingTpPts > 0)
        {
          if (posType == POSITION_TYPE_BUY)
            desiredTP = entry + swingTpPts * _Point;
          else
            desiredTP = entry - swingTpPts * _Point;
        }

        bool needModify = (MathAbs(desiredSL - curSL) > _Point / 2.0) || (MathAbs(desiredTP - curTP) > _Point / 2.0);
        if (needModify)
        {
          if (ModifyPositionByTicket(ticket, desiredSL, desiredTP))
          {
            curSL = desiredSL;
            curTP = desiredTP;
            trailUpdated = true;
          }
        }
      }

      if (trailUpdated)
      {
        if (posType == POSITION_TYPE_BUY)
          lastTrailRefBuy = refPrice;
        else
          lastTrailRefSell = refPrice;
      }

      continue;
    }
  }
}

void TryStartupEntry()
{
  if (!EnterOnInit)
  {
    // 起動時エントリーを行わない設定なら即完了扱い
    g_startup_done = true;
    return;
  }

  if (HasOurPosition())
  {
    g_startup_done = true;
    return;
  }

  if (SpreadTooWide())
  {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread_points = (ask - bid) / _Point;
    if (EnableInfoLog)
      Print(__FUNCTION__, ": skip - spread too wide (points)=", DoubleToString(spread_points, 1), " limit=", MaxSpreadPoints);
    return;
  }

  if (AtrPoints() <= 0.0)
  {
    if (EnableInfoLog)
      Print(__FUNCTION__, ": skip - ATR not ready");
    return;
  }

  int needed = MathMax(MathMax(FastEmaPeriod, SlowEmaPeriod), ConfirmBarsStartup);
  if (g_bar_count < needed)
  {
    if (EnableInfoLog)
      Print(__FUNCTION__, ": skip - bars not ready count=", g_bar_count, " needed=", needed);
    return; // 30秒バーが不足
  }

  // エントリー自体はペアエンジンに任せる。条件が整ったタイミングで一度だけフラグを立てる。
  g_startup_done = true;
}

datetime g_last_open_attempt = 0;

bool RecentlyTriedOpen()
{
  return (g_last_open_attempt != 0 && (TimeCurrent() - g_last_open_attempt) < 2); // 2秒ロック
}

int OnInit()
{
  g_curr_slot_start = 0;
  g_bar_count = 0;
  g_fast_ema = g_slow_ema = 0;
  ArrayResize(g_trend_history, 0);
  g_startup_done = false;
  g_last_close_time = 0;
  g_tr_atr = 0.0;
  g_prev_close = 0.0;
  g_action_used_this_tick = false;
  g_open_phase = OPEN_IDLE;
  g_open_dir = TREND_NONE;
  g_last_refill_time = 0;

  trade.SetExpertMagicNumber(MagicNumber);
  return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
  g_action_used_this_tick = false; // 1tick=1action リセット

  UpdateSyntheticBar();

  int needed_start = MathMax(MathMax(FastEmaPeriod, SlowEmaPeriod), ConfirmBarsStartup);
  if (!g_startup_done && EnterOnInit && g_bar_count >= needed_start)
  {
    TryStartupEntry();
  }

  // オープン系は順番に試し、どれかがリクエストを使ったら残りはスキップされる
  ManageOpenPositions();
  StartPairIfScalpMissing();
  ProcessEntryEngine();
}
