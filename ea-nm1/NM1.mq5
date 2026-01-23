#property strict
#property version   "1.26"

// v1.24 ナンピン停止ルール追加, ナンピン幅の厳格化
// v1.25 AdxMaxForNanpinのデフォルトを20.0に、DiGapMinのデフォルトを2.0に
// v1.26 no martingaleモードを用意

#include <Trade/Trade.mqh>

namespace NM1
{
enum { kMaxLevels = 13 };
enum { kMaxSymbols = 6 };
const int kAtrBasePeriod = 14;
const int kLotDigits = 2;
const double kMinLot = 0.01;
const double kMaxLot = 100.0;
const int kCoreFlexSplitLevel = 100; // 100 = no split
const string kFlexComment = "NM1_FLEX";
const string kCoreComment = "NM1_CORE";
}

input group "COMMON"
input string SymbolSuffix = "c";
input int MagicNumber = 202507;
input int SlippagePoints = 4;
input int StartDelaySeconds = 5;
input bool UseAsyncClose = true;
input int CloseRetryCount = 3;
input int CloseRetryDelayMs = 200;
input bool SafetyMode = true;
input bool SafeStopMode = false;
input double SafeK = 2.0;
input double SafeSlopeK = 0.3;
input double CoreRatio = 1.0;
input double FlexRatio = 0;
input double FlexAtrProfitMultiplier = 0.8;
input int RestartDelaySeconds = 1;
input int NanpinSleepSeconds = 10;
input int AdxPeriod = 14;
input double AdxMaxForNanpin = 20.0;
input double DiGapMin = 2.0;

input group "XAUUSD"
input bool EnableXAUUSD = true;
input string SymbolXAUUSD = "XAUUSD";
input double BaseLotXAUUSD = 0.03;
input double AtrMultiplierXAUUSD = 1.4;
input double MinAtrXAUUSD = 1.6;
input double ProfitBaseXAUUSD = 1.5;
input int MaxLevelsXAUUSD = 12;
input double StopBuyLimitPriceXAUUSD = 4000.0;
input double StopBuyLimitLotXAUUSD = 0.01;
input bool NoMartingaleXAUUSD = false;

input group "EURUSD"
input bool EnableEURUSD = false;
input string SymbolEURUSD = "EURUSD";
input double BaseLotEURUSD = 0.01;
input double AtrMultiplierEURUSD = 1.3;
input double MinAtrEURUSD = 0.00025;
input double ProfitBaseEURUSD = 0.00005;
input int MaxLevelsEURUSD = 10;
input double StopBuyLimitPriceEURUSD = 4000.0;
input double StopBuyLimitLotEURUSD = 0.01;
input bool NoMartingaleEURUSD = false;

input group "USDJPY"
input bool EnableUSDJPY = false;
input string SymbolUSDJPY = "USDJPY";
input double BaseLotUSDJPY = 0.3;
input double AtrMultiplierUSDJPY = 1.6;
input double MinAtrUSDJPY = 0.05;
input double ProfitBaseUSDJPY = 0.01;
input int MaxLevelsUSDJPY = 12;
input double StopBuyLimitPriceUSDJPY = 4000.0;
input double StopBuyLimitLotUSDJPY = 0.01;
input bool NoMartingaleUSDJPY = false;

input group "AUDUSD"
input bool EnableAUDUSD = false;
input string SymbolAUDUSD = "AUDUSD";
input double BaseLotAUDUSD = 0.01;
input double AtrMultiplierAUDUSD = 1.2;
input double MinAtrAUDUSD = 0.00015;
input double ProfitBaseAUDUSD = 1.0;
input int MaxLevelsAUDUSD = 10;
input double StopBuyLimitPriceAUDUSD = 4000.0;
input double StopBuyLimitLotAUDUSD = 0.01;
input bool NoMartingaleAUDUSD = false;

input group "BTCUSD"
input bool EnableBTCUSD = false;
input string SymbolBTCUSD = "BTCUSD";
input double BaseLotBTCUSD = 0.3;
input double AtrMultiplierBTCUSD = 2.5;
input double MinAtrBTCUSD = 10.0;
input double ProfitBaseBTCUSD = 4.0;
input int MaxLevelsBTCUSD = 8;
input double StopBuyLimitPriceBTCUSD = 4000.0;
input double StopBuyLimitLotBTCUSD = 0.01;
input bool NoMartingaleBTCUSD = true;

input group "ETHUSD"
input bool EnableETHUSD = false;
input string SymbolETHUSD = "ETHUSD";
input double BaseLotETHUSD = 0.1;
input double AtrMultiplierETHUSD = 1.6;
input double MinAtrETHUSD = 1.2;
input double ProfitBaseETHUSD = 1.0;
input int MaxLevelsETHUSD = 12;
input double StopBuyLimitPriceETHUSD = 4000.0;
input double StopBuyLimitLotETHUSD = 0.01;
input bool NoMartingaleETHUSD = false;

struct NM1Params
{
  int magic_number;
  int slippage_points;
  int start_delay_seconds;
  double atr_multiplier;
  double min_atr;
  bool safety_mode;
  bool safe_stop_mode;
  double safe_k;
  double safe_slope_k;
  double base_lot;
  double profit_base;
  double core_ratio;
  double flex_ratio;
  double flex_atr_profit_multiplier;
  int adx_period;
  double adx_max_for_nanpin;
  double di_gap_min;
  int max_levels;
  int restart_delay_seconds;
  int nanpin_sleep_seconds;
  bool use_async_close;
  int close_retry_count;
  int close_retry_delay_ms;
  double stop_buy_limit_price;
  double stop_buy_limit_lot;
  bool no_martingale;
};

struct BasketInfo
{
  int count;
  int level_count;
  double volume;
  double avg_price;
  double min_price;
  double max_price;
  double profit;
};

struct FlexRef
{
  bool active;
  double price;
  double lot;
  int level;
};

CTrade trade;
CTrade close_trade;

struct SymbolState
{
  string logical_symbol;
  string broker_symbol;
  bool enabled;
  NM1Params params;
  datetime start_time;
  bool initial_started;
  double lot_seq[NM1::kMaxLevels];
  FlexRef flex_buy_refs[NM1::kMaxLevels];
  FlexRef flex_sell_refs[NM1::kMaxLevels];
  double buy_level_price[NM1::kMaxLevels];
  double sell_level_price[NM1::kMaxLevels];
  double buy_grid_step;
  double sell_grid_step;
  datetime last_buy_close_time;
  datetime last_sell_close_time;
  datetime last_buy_nanpin_time;
  datetime last_sell_nanpin_time;
  int prev_buy_count;
  int prev_sell_count;
  int atr_handle;
  int adx_handle;
  bool safety_active;
  double realized_buy_profit;
  double realized_sell_profit;
  bool has_partial_buy;
  bool has_partial_sell;
  bool buy_stop_active;
  bool sell_stop_active;
  int buy_skip_levels;
  int sell_skip_levels;
  double buy_skip_distance;
  double sell_skip_distance;
  double buy_skip_price;
  double sell_skip_price;
};

SymbolState symbols[NM1::kMaxSymbols];
int symbols_count = 0;

void DisableSymbol(SymbolState &state, const string reason)
{
  if (!state.enabled)
    return;
  state.enabled = false;
  if (state.atr_handle != INVALID_HANDLE)
    IndicatorRelease(state.atr_handle);
  state.atr_handle = INVALID_HANDLE;
  if (state.adx_handle != INVALID_HANDLE)
    IndicatorRelease(state.adx_handle);
  state.adx_handle = INVALID_HANDLE;
  if (StringLen(reason) > 0)
    PrintFormat("Symbol disabled: %s (%s)", state.broker_symbol, reason);
}

void InitSymbolState(SymbolState &state, const string logical, const string broker, bool enabled, const NM1Params &params)
{
  state.logical_symbol = logical;
  state.broker_symbol = broker;
  state.enabled = enabled;
  state.params = params;
  state.start_time = TimeCurrent();
  state.initial_started = false;
  state.last_buy_close_time = 0;
  state.last_sell_close_time = 0;
  state.last_buy_nanpin_time = 0;
  state.last_sell_nanpin_time = 0;
  state.prev_buy_count = 0;
  state.prev_sell_count = 0;
  state.atr_handle = INVALID_HANDLE;
  state.adx_handle = INVALID_HANDLE;
  state.safety_active = false;
  state.realized_buy_profit = 0.0;
  state.realized_sell_profit = 0.0;
  state.has_partial_buy = false;
  state.has_partial_sell = false;
  state.buy_stop_active = false;
  state.sell_stop_active = false;
  state.buy_skip_levels = 0;
  state.sell_skip_levels = 0;
  state.buy_skip_distance = 0.0;
  state.sell_skip_distance = 0.0;
  state.buy_skip_price = 0.0;
  state.sell_skip_price = 0.0;
  ClearFlexRefs(state.flex_buy_refs);
  ClearFlexRefs(state.flex_sell_refs);
  ClearLevelPrices(state.buy_level_price);
  ClearLevelPrices(state.sell_level_price);
  state.buy_grid_step = 0.0;
  state.sell_grid_step = 0.0;
}

void ApplyCommonParams(NM1Params &params)
{
  params.magic_number = MagicNumber;
  params.slippage_points = SlippagePoints;
  params.start_delay_seconds = StartDelaySeconds;
  params.safety_mode = SafetyMode;
  params.safe_stop_mode = SafeStopMode;
  params.safe_k = SafeK;
  params.safe_slope_k = SafeSlopeK;
  params.core_ratio = CoreRatio;
  params.flex_ratio = FlexRatio;
  params.flex_atr_profit_multiplier = FlexAtrProfitMultiplier;
  params.adx_period = AdxPeriod;
  params.adx_max_for_nanpin = AdxMaxForNanpin;
  params.di_gap_min = DiGapMin;
  params.restart_delay_seconds = RestartDelaySeconds;
  params.nanpin_sleep_seconds = NanpinSleepSeconds;
  params.use_async_close = UseAsyncClose;
  params.close_retry_count = CloseRetryCount;
  params.close_retry_delay_ms = CloseRetryDelayMs;
}

void LoadParamsForIndex(int index, NM1Params &params)
{
  ApplyCommonParams(params);
  if (index == 0)
  {
    params.atr_multiplier = AtrMultiplierXAUUSD;
    params.min_atr = MinAtrXAUUSD;
    params.base_lot = BaseLotXAUUSD;
    params.profit_base = ProfitBaseXAUUSD;
    params.max_levels = MaxLevelsXAUUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceXAUUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotXAUUSD;
    params.no_martingale = NoMartingaleXAUUSD;
  }
  else if (index == 1)
  {
    params.atr_multiplier = AtrMultiplierEURUSD;
    params.min_atr = MinAtrEURUSD;
    params.base_lot = BaseLotEURUSD;
    params.profit_base = ProfitBaseEURUSD;
    params.max_levels = MaxLevelsEURUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceEURUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotEURUSD;
    params.no_martingale = NoMartingaleEURUSD;
  }
  else if (index == 2)
  {
    params.atr_multiplier = AtrMultiplierUSDJPY;
    params.min_atr = MinAtrUSDJPY;
    params.base_lot = BaseLotUSDJPY;
    params.profit_base = ProfitBaseUSDJPY;
    params.max_levels = MaxLevelsUSDJPY;
    params.stop_buy_limit_price = StopBuyLimitPriceUSDJPY;
    params.stop_buy_limit_lot = StopBuyLimitLotUSDJPY;
    params.no_martingale = NoMartingaleUSDJPY;
  }
  else if (index == 3)
  {
    params.atr_multiplier = AtrMultiplierAUDUSD;
    params.min_atr = MinAtrAUDUSD;
    params.base_lot = BaseLotAUDUSD;
    params.profit_base = ProfitBaseAUDUSD;
    params.max_levels = MaxLevelsAUDUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceAUDUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotAUDUSD;
    params.no_martingale = NoMartingaleAUDUSD;
  }
  else if (index == 4)
  {
    params.atr_multiplier = AtrMultiplierBTCUSD;
    params.min_atr = MinAtrBTCUSD;
    params.base_lot = BaseLotBTCUSD;
    params.profit_base = ProfitBaseBTCUSD;
    params.max_levels = MaxLevelsBTCUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceBTCUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotBTCUSD;
    params.no_martingale = NoMartingaleBTCUSD;
  }
  else if (index == 5)
  {
    params.atr_multiplier = AtrMultiplierETHUSD;
    params.min_atr = MinAtrETHUSD;
    params.base_lot = BaseLotETHUSD;
    params.profit_base = ProfitBaseETHUSD;
    params.max_levels = MaxLevelsETHUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceETHUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotETHUSD;
    params.no_martingale = NoMartingaleETHUSD;
  }
}

void BuildSymbols()
{
  const string supported[NM1::kMaxSymbols] = {"XAUUSD", "EURUSD", "USDJPY", "AUDUSD", "BTCUSD", "ETHUSD"};
  bool enabled_inputs[NM1::kMaxSymbols];
  string symbol_inputs[NM1::kMaxSymbols];
  enabled_inputs[0] = EnableXAUUSD;
  enabled_inputs[1] = EnableEURUSD;
  enabled_inputs[2] = EnableUSDJPY;
  enabled_inputs[3] = EnableAUDUSD;
  enabled_inputs[4] = EnableBTCUSD;
  enabled_inputs[5] = EnableETHUSD;
  symbol_inputs[0] = SymbolXAUUSD;
  symbol_inputs[1] = SymbolEURUSD;
  symbol_inputs[2] = SymbolUSDJPY;
  symbol_inputs[3] = SymbolAUDUSD;
  symbol_inputs[4] = SymbolBTCUSD;
  symbol_inputs[5] = SymbolETHUSD;
  symbols_count = 0;
  for (int i = 0; i < NM1::kMaxSymbols; ++i)
  {
    NM1Params params;
    LoadParamsForIndex(i, params);
    string logical = supported[i];
    bool enabled = enabled_inputs[i];
    string broker_symbol = symbol_inputs[i];
    if (StringLen(broker_symbol) == 0)
      broker_symbol = logical;
    if (StringLen(SymbolSuffix) > 0)
      broker_symbol = broker_symbol + SymbolSuffix;
    if (enabled)
    {
      if (!SymbolSelect(broker_symbol, true))
      {
        PrintFormat("Symbol unavailable: %s", broker_symbol);
        enabled = false;
      }
    }
    InitSymbolState(symbols[symbols_count], logical, broker_symbol, enabled, params);
    if (enabled)
      symbols_count++;
  }
  if (symbols_count == 0)
    Print("No enabled symbols available. Check Enable*/Symbol* inputs.");
}

bool IsTradingTime()
{
  datetime now_gmt = TimeGMT();
  if (now_gmt == 0)
    now_gmt = TimeCurrent();
  MqlDateTime dt;
  TimeToStruct(now_gmt + 9 * 3600, dt);
  int minutes = dt.hour * 60 + dt.min;
  int stop_start = 6 * 60 + 30;
  int stop_end = 8 * 60 + 15;
  bool in_stop = (minutes >= stop_start && minutes < stop_end);
  return !in_stop;
}

double NormalizeLot(const string symbol, double lot)
{
  double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
  double minlot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
  double maxlot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
  if (step <= 0.0)
    step = 0.01;
  if (minlot <= 0.0)
    minlot = NM1::kMinLot;
  if (maxlot <= 0.0)
    maxlot = NM1::kMaxLot;
  lot = MathMax(minlot, MathMin(maxlot, lot));
  double steps = MathFloor(lot / step + 0.0000001);
  return NormalizeDouble(steps * step, NM1::kLotDigits);
}

double NormalizeRatio(double value, double fallback)
{
  if (value <= 0.0)
    return fallback;
  return value;
}

void NormalizeCoreFlexLot(const NM1Params &params, const string symbol, double lot, double &core, double &flex)
{
  double core_ratio = NormalizeRatio(params.core_ratio, 0.7);
  double flex_ratio = NormalizeRatio(params.flex_ratio, 0.3);
  double ratio_sum = core_ratio + flex_ratio;
  if (ratio_sum <= 0.0)
  {
    core_ratio = 0.7;
    flex_ratio = 0.3;
    ratio_sum = 1.0;
  }
  core_ratio /= ratio_sum;
  flex_ratio /= ratio_sum;
  double raw_flex = lot * flex_ratio;
  flex = NormalizeLot(symbol, raw_flex);
  core = NormalizeLot(symbol, lot - flex);
  if (flex <= 0.0)
  {
    flex = 0.0;
    core = NormalizeLot(symbol, lot);
  }
}

void ClearFlexRefs(FlexRef &refs[])
{
  for (int i = 0; i < NM1::kMaxLevels; ++i)
  {
    refs[i].active = false;
    refs[i].level = 0;
  }
}

void ClearLevelPrices(double &prices[])
{
  for (int i = 0; i < NM1::kMaxLevels; ++i)
    prices[i] = 0.0;
}

void SyncLevelPricesFromPositions(SymbolState &state)
{
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    string comment = PositionGetString(POSITION_COMMENT);
    if (IsFlexComment(comment))
      continue;
    int level = ExtractLevelFromComment(comment);
    if (level <= 0)
      level = 1;
    if (level > NM1::kMaxLevels)
      continue;
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    int type = (int)PositionGetInteger(POSITION_TYPE);
    if (type == POSITION_TYPE_BUY)
    {
      if (state.buy_level_price[level - 1] <= 0.0)
        state.buy_level_price[level - 1] = price;
    }
    else if (type == POSITION_TYPE_SELL)
    {
      if (state.sell_level_price[level - 1] <= 0.0)
        state.sell_level_price[level - 1] = price;
    }
  }
  if (state.buy_grid_step <= 0.0 && state.buy_level_price[0] > 0.0 && state.buy_level_price[1] > 0.0)
    state.buy_grid_step = MathAbs(state.buy_level_price[0] - state.buy_level_price[1]);
  if (state.sell_grid_step <= 0.0 && state.sell_level_price[0] > 0.0 && state.sell_level_price[1] > 0.0)
    state.sell_grid_step = MathAbs(state.sell_level_price[0] - state.sell_level_price[1]);
}

bool AddFlexRef(const string symbol, FlexRef &refs[], double price, double lot, int level)
{
  double tol = SymbolInfoDouble(symbol, SYMBOL_POINT) * 0.5;
  for (int i = 0; i < NM1::kMaxLevels; ++i)
  {
    if (!refs[i].active)
      continue;
    if (MathAbs(refs[i].price - price) <= tol && MathAbs(refs[i].lot - lot) <= 0.0000001 && refs[i].level == level)
      return false;
  }
  for (int i = 0; i < NM1::kMaxLevels; ++i)
  {
    if (!refs[i].active)
    {
      refs[i].active = true;
      refs[i].price = price;
      refs[i].lot = lot;
      refs[i].level = level;
      return true;
    }
  }
  return false;
}

int EffectiveMaxLevels(const NM1Params &params)
{
  int levels = params.max_levels;
  if (levels < 1)
    levels = 1;
  if (levels > NM1::kMaxLevels)
    levels = NM1::kMaxLevels;
  return levels;
}

void BuildLotSequence(SymbolState &state, const string symbol)
{
  NM1Params params = state.params;
  int levels = EffectiveMaxLevels(state.params);
  state.lot_seq[0] = params.base_lot;
  if (params.no_martingale)
  {
    for (int i = 1; i < levels; ++i)
      state.lot_seq[i] = params.base_lot;
  }
  else
  {
    if (levels > 1)
      state.lot_seq[1] = params.base_lot;
    for (int i = 2; i < levels; ++i)
      state.lot_seq[i] = state.lot_seq[i - 1] + state.lot_seq[i - 2];
  }
  for (int i = 0; i < levels; ++i)
  {
    state.lot_seq[i] = NormalizeLot(symbol, state.lot_seq[i]);
  }
}

bool IsFlexComment(const string comment)
{
  return StringFind(comment, NM1::kFlexComment) == 0;
}

bool HasOpenPosition(const SymbolState &state)
{
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    return true;
  }
  return false;
}

int ExtractLevelFromComment(const string comment)
{
  int pos = StringFind(comment, "_L");
  if (pos < 0)
    return 0;
  string tail = StringSubstr(comment, pos + 2);
  int level = (int)StringToInteger(tail);
  if (level < 0)
    return 0;
  return level;
}

string MakeLevelComment(const string base, int level)
{
  if (level <= 0)
    return base;
  return StringFormat("%s_L%d", base, level);
}

int OnInit()
{
  BuildSymbols();
  if (symbols_count == 0)
    return INIT_FAILED;

  int active = 0;
  for (int i = 0; i < symbols_count; ++i)
  {
    if (!symbols[i].enabled)
      continue;
    BuildLotSequence(symbols[i], symbols[i].broker_symbol);
    symbols[i].atr_handle = iATR(symbols[i].broker_symbol, _Period, NM1::kAtrBasePeriod);
    if (symbols[i].atr_handle == INVALID_HANDLE)
    {
      PrintFormat("ATR handle failed: %s", symbols[i].broker_symbol);
      symbols[i].enabled = false;
      continue;
    }
    symbols[i].adx_handle = iADX(symbols[i].broker_symbol, _Period, symbols[i].params.adx_period);
    if (symbols[i].adx_handle == INVALID_HANDLE)
      PrintFormat("ADX handle failed: %s", symbols[i].broker_symbol);
    active++;
  }
  if (active == 0)
    return INIT_FAILED;
  if (!EventSetMillisecondTimer(500))
    Print("EventSetMillisecondTimer failed");

  for (int i = 0; i < symbols_count; ++i)
  {
    if (!symbols[i].enabled)
      continue;
    if (HasOpenPosition(symbols[i]))
      symbols[i].initial_started = true;
  }
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  EventKillTimer();
  for (int i = 0; i < symbols_count; ++i)
  {
    if (symbols[i].atr_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].atr_handle);
    symbols[i].atr_handle = INVALID_HANDLE;
    if (symbols[i].adx_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].adx_handle);
    symbols[i].adx_handle = INVALID_HANDLE;
  }
}

double GetAtrBase(SymbolState &state)
{
  if (state.atr_handle == INVALID_HANDLE)
    return 0.0;
  double buffer[];
  if (CopyBuffer(state.atr_handle, 0, 5, 50, buffer) < 50)
    return 0.0;
  double sum = 0.0;
  for (int i = 0; i < 50; ++i)
    sum += buffer[i];
  return sum / 50.0;
}

double GetCurrentAtr(SymbolState &state)
{
  if (state.atr_handle == INVALID_HANDLE)
    return 0.0;
  double buffer[];
  if (CopyBuffer(state.atr_handle, 0, 0, 1, buffer) <= 0)
    return 0.0;
  return buffer[0];
}

double GetAtrSlope(SymbolState &state)
{
  if (state.atr_handle == INVALID_HANDLE)
    return 0.0;

  double buf[3];
  if (CopyBuffer(state.atr_handle, 0, 0, 3, buf) < 3)
    return 0.0;

  return buf[0] - buf[2];
}

bool GetAdxSnapshot(SymbolState &state,
                    double &adx_now,
                    double &adx_prev,
                    double &di_plus_now,
                    double &di_plus_prev,
                    double &di_minus_now,
                    double &di_minus_prev)
{
  if (state.adx_handle == INVALID_HANDLE)
    return false;
  double adx_buf[2];
  double plus_buf[2];
  double minus_buf[2];
  if (CopyBuffer(state.adx_handle, 0, 0, 2, adx_buf) < 2)
    return false;
  if (CopyBuffer(state.adx_handle, 1, 0, 2, plus_buf) < 2)
    return false;
  if (CopyBuffer(state.adx_handle, 2, 0, 2, minus_buf) < 2)
    return false;
  adx_now = adx_buf[0];
  adx_prev = adx_buf[1];
  di_plus_now = plus_buf[0];
  di_plus_prev = plus_buf[1];
  di_minus_now = minus_buf[0];
  di_minus_prev = minus_buf[1];
  return true;
}

void CollectBasketInfo(const SymbolState &state, BasketInfo &buy, BasketInfo &sell)
{
  const string symbol = state.broker_symbol;
  buy.count = 0;
  buy.level_count = 0;
  buy.volume = 0.0;
  buy.avg_price = 0.0;
  buy.min_price = 0.0;
  buy.max_price = 0.0;
  buy.profit = 0.0;
  sell.count = 0;
  sell.level_count = 0;
  sell.volume = 0.0;
  sell.avg_price = 0.0;
  sell.min_price = 0.0;
  sell.max_price = 0.0;
  sell.profit = 0.0;

  double buy_value = 0.0;
  double sell_value = 0.0;

  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != state.params.magic_number)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;

    int type = (int)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    string comment = PositionGetString(POSITION_COMMENT);

    if (type == POSITION_TYPE_BUY)
    {
      if (buy.count == 0)
      {
        buy.min_price = price;
        buy.max_price = price;
      }
      else
      {
        buy.min_price = MathMin(buy.min_price, price);
        buy.max_price = MathMax(buy.max_price, price);
      }
      buy.count++;
      if (!IsFlexComment(comment))
        buy.level_count++;
      buy.volume += volume;
      buy_value += volume * price;
      buy.profit += PositionGetDouble(POSITION_PROFIT);
    }
    else if (type == POSITION_TYPE_SELL)
    {
      if (sell.count == 0)
      {
        sell.min_price = price;
        sell.max_price = price;
      }
      else
      {
        sell.min_price = MathMin(sell.min_price, price);
        sell.max_price = MathMax(sell.max_price, price);
      }
      sell.count++;
      if (!IsFlexComment(comment))
        sell.level_count++;
      sell.volume += volume;
      sell_value += volume * price;
      sell.profit += PositionGetDouble(POSITION_PROFIT);
    }
  }

  if (buy.volume > 0.0)
    buy.avg_price = buy_value / buy.volume;
  if (sell.volume > 0.0)
    sell.avg_price = sell_value / sell.volume;
}

double EnsureBuyTarget(SymbolState &state, const BasketInfo &buy, double step, int level_index)
{
  double target = state.buy_level_price[level_index];
  if (target <= 0.0)
  {
    double base = 0.0;
    if (level_index > 0)
      base = state.buy_level_price[level_index - 1];
    if (base <= 0.0)
      base = buy.min_price;
    target = base - step;
    state.buy_level_price[level_index] = target;
  }
  return target;
}

double EnsureSellTarget(SymbolState &state, const BasketInfo &sell, double step, int level_index)
{
  double target = state.sell_level_price[level_index];
  if (target <= 0.0)
  {
    double base = 0.0;
    if (level_index > 0)
      base = state.sell_level_price[level_index - 1];
    if (base <= 0.0)
      base = sell.max_price;
    target = base + step;
    state.sell_level_price[level_index] = target;
  }
  return target;
}

void CloseBasket(const SymbolState &state, ENUM_POSITION_TYPE type)
{
  const string symbol = state.broker_symbol;
  close_trade.SetExpertMagicNumber(state.params.magic_number);
  close_trade.SetDeviationInPoints(state.params.slippage_points);
  close_trade.SetAsyncMode(state.params.use_async_close);
  int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  ulong tickets[];
  int count = 0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != state.params.magic_number)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    ArrayResize(tickets, ++count);
    tickets[count - 1] = ticket;
  }

  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    while (attempts <= state.params.close_retry_count)
    {
      if (close_trade.PositionClose(tickets[i]))
      {
        closed = true;
        break;
      }
      attempts++;
      if (attempts <= state.params.close_retry_count && state.params.close_retry_delay_ms > 0)
        Sleep(state.params.close_retry_delay_ms);
    }
    if (!closed)
    {
      PrintFormat("Close failed after retries: ticket=%I64u retcode=%d %s",
                  tickets[i], close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
}

bool TryOpen(const SymbolState &state, const string symbol, ENUM_ORDER_TYPE order_type, double lot, const string comment = "")
{
  lot = NormalizeLot(symbol, lot);
  if (lot <= 0.0)
    return false;
  trade.SetExpertMagicNumber(state.params.magic_number);
  trade.SetDeviationInPoints(state.params.slippage_points);
  int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  bool ok = false;
  if (order_type == ORDER_TYPE_BUY)
    ok = trade.Buy(lot, symbol, 0.0, 0.0, 0.0, comment);
  else if (order_type == ORDER_TYPE_SELL)
    ok = trade.Sell(lot, symbol, 0.0, 0.0, 0.0, comment);

  if (!ok)
  {
    PrintFormat("Order failed: type=%d lot=%.2f retcode=%d %s",
                order_type, lot, trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }
  return ok;
}

bool ShouldStopOnBuyLimit(const NM1Params &params, const string symbol, double limit_price, double limit_lot)
{
  if (limit_price <= 0.0 || limit_lot <= 0.0)
    return false;
  double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (point <= 0.0)
    point = 0.00001;
  double price_tol = point * 0.5;
  double norm_lot = NormalizeLot(symbol, limit_lot);
  for (int i = OrdersTotal() - 1; i >= 0; --i)
  {
    ulong ticket = OrderGetTicket(i);
    if (!OrderSelect(ticket))
      continue;
    long magic = OrderGetInteger(ORDER_MAGIC);
    if (magic != params.magic_number && magic != 0)
      continue;
    if (OrderGetString(ORDER_SYMBOL) != symbol)
      continue;
    if ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT)
      continue;
    double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
    double price = OrderGetDouble(ORDER_PRICE_OPEN);
    if (MathAbs(volume - norm_lot) <= 0.0000001 && MathAbs(price - limit_price) <= price_tol)
      return true;
  }
  return false;
}

double PipPointSize(const string symbol)
{
  int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (digits == 3 || digits == 5)
    return point * 10.0;
  return point;
}

double DealNetProfit(ulong deal_ticket)
{
  if (deal_ticket == 0)
    return 0.0;
  if (!HistoryDealSelect(deal_ticket))
  {
    datetime now = TimeCurrent();
    if (!HistorySelect(now - 86400, now + 60))
      return 0.0;
    if (!HistoryDealSelect(deal_ticket))
      return 0.0;
  }
  return HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
         + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
         + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
}

double PriceValuePerUnit(const string symbol)
{
  double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
  double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  if (tick_value <= 0.0 || tick_size <= 0.0)
    return 0.0;
  return tick_value / tick_size;
}

bool CanRestart(const NM1Params &params, datetime last_close_time)
{
  if (last_close_time == 0)
    return true;
  return (TimeCurrent() - last_close_time) >= params.restart_delay_seconds;
}

bool CanNanpin(const NM1Params &params, datetime last_nanpin_time)
{
  if (last_nanpin_time == 0)
    return true;
  return (TimeCurrent() - last_nanpin_time) >= params.nanpin_sleep_seconds;
}

void ProcessFlexPartial(SymbolState &state, const string symbol, double bid, double ask, double atr_now)
{
  NM1Params params = state.params;
  if (atr_now <= 0.0 || params.flex_atr_profit_multiplier <= 0.0)
    return;
  double target = atr_now * params.flex_atr_profit_multiplier;
  close_trade.SetExpertMagicNumber(params.magic_number);
  close_trade.SetDeviationInPoints(params.slippage_points);
  close_trade.SetAsyncMode(params.use_async_close);
  int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != params.magic_number)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    string comment = PositionGetString(POSITION_COMMENT);
    if (!IsFlexComment(comment))
      continue;

    int type = (int)PositionGetInteger(POSITION_TYPE);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double profit = 0.0;
    if (type == POSITION_TYPE_BUY)
      profit = bid - price;
    else if (type == POSITION_TYPE_SELL)
      profit = price - ask;
    else
      continue;

    if (profit < target)
      continue;

    if (close_trade.PositionClose(ticket))
    {
      double realized = DealNetProfit(close_trade.ResultDeal());
      int level = ExtractLevelFromComment(comment);
      if (type == POSITION_TYPE_BUY)
      {
        state.realized_buy_profit += realized;
        state.has_partial_buy = true;
        AddFlexRef(symbol, state.flex_buy_refs, price, volume, level);
      }
      else
      {
        state.realized_sell_profit += realized;
        state.has_partial_sell = true;
        AddFlexRef(symbol, state.flex_sell_refs, price, volume, level);
      }
    }
    else
    {
      PrintFormat("Flex close failed: ticket=%I64u retcode=%d %s",
                  ticket, close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
}

void ProcessFlexRefill(SymbolState &state, const string symbol, ENUM_ORDER_TYPE order_type, FlexRef &refs[], double trigger_price)
{
  double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (point <= 0.0)
    point = 0.00001;
  double tol = point * 0.5;
  for (int i = 0; i < NM1::kMaxLevels; ++i)
  {
    if (!refs[i].active)
      continue;
    bool should_open = false;
    if (order_type == ORDER_TYPE_BUY)
      should_open = trigger_price <= refs[i].price + tol;
    else if (order_type == ORDER_TYPE_SELL)
      should_open = trigger_price >= refs[i].price - tol;
    if (!should_open)
      continue;
    string comment = MakeLevelComment(NM1::kFlexComment, refs[i].level);
    if (TryOpen(state, symbol, order_type, refs[i].lot, comment))
      refs[i].active = false;
  }
}

void ProcessSymbolTick(SymbolState &state)
{
  if (!state.enabled)
    return;
  string symbol = state.broker_symbol;
  NM1Params params = state.params;
  BasketInfo buy, sell;
  CollectBasketInfo(state, buy, sell);
  MqlTick t;
  if (!SymbolInfoTick(symbol, t))
    return;
  if ((long)TimeCurrent() - (long)t.time > 2)
    return;
  if (t.bid <= 0.0 || t.ask <= 0.0 || t.ask < t.bid)
    return;
  double bid = t.bid;
  double ask = t.ask;
  bool is_trading_time = IsTradingTime();
  if (!is_trading_time)
  {
    double value_per_unit = PriceValuePerUnit(symbol);
    double threshold = -0.5 * params.profit_base;
    if (buy.count > 0)
    {
      bool should_close = false;
      if (value_per_unit > 0.0)
      {
        double threshold_profit = buy.volume * threshold * value_per_unit;
        should_close = (buy.profit + state.realized_buy_profit) >= threshold_profit;
      }
      else
      {
        should_close = (bid - buy.avg_price) >= threshold;
      }
      if (should_close)
        CloseBasket(state, POSITION_TYPE_BUY);
    }
    if (sell.count > 0)
    {
      bool should_close = false;
      if (value_per_unit > 0.0)
      {
        double threshold_profit = sell.volume * threshold * value_per_unit;
        should_close = (sell.profit + state.realized_sell_profit) >= threshold_profit;
      }
      else
      {
        should_close = (sell.avg_price - ask) >= threshold;
      }
      if (should_close)
        CloseBasket(state, POSITION_TYPE_SELL);
    }
  }
  if (ShouldStopOnBuyLimit(params, symbol, params.stop_buy_limit_price, params.stop_buy_limit_lot))
  {
    PrintFormat("StopBuyLimit triggered: %s buy limit %.2f lots at price %.2f detected.",
                symbol, params.stop_buy_limit_lot, params.stop_buy_limit_price);
    DisableSymbol(state, "StopBuyLimit");
    return;
  }

  if (state.prev_buy_count > 0 && buy.count == 0)
  {
    state.last_buy_close_time = TimeCurrent();
    state.last_buy_nanpin_time = 0;
    state.realized_buy_profit = 0.0;
    state.has_partial_buy = false;
    state.buy_stop_active = false;
    state.buy_skip_levels = 0;
    state.buy_skip_distance = 0.0;
    state.buy_skip_price = 0.0;
    ClearFlexRefs(state.flex_buy_refs);
    ClearLevelPrices(state.buy_level_price);
    state.buy_grid_step = 0.0;
  }
  if (state.prev_sell_count > 0 && sell.count == 0)
  {
    state.last_sell_close_time = TimeCurrent();
    state.last_sell_nanpin_time = 0;
    state.realized_sell_profit = 0.0;
    state.has_partial_sell = false;
    state.sell_stop_active = false;
    state.sell_skip_levels = 0;
    state.sell_skip_distance = 0.0;
    state.sell_skip_price = 0.0;
    ClearFlexRefs(state.flex_sell_refs);
    ClearLevelPrices(state.sell_level_price);
    state.sell_grid_step = 0.0;
  }

  if (buy.count > 0 || sell.count > 0)
    SyncLevelPricesFromPositions(state);

  bool attempted_initial = false;
  if (!state.initial_started && (TimeCurrent() - state.start_time) >= params.start_delay_seconds)
  {
    if (buy.count == 0 && sell.count == 0 && is_trading_time)
    {
      bool opened_buy = TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
      if (opened_buy && state.buy_level_price[0] <= 0.0)
        state.buy_level_price[0] = ask;
      bool opened_sell = TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
      if (opened_sell && state.sell_level_price[0] <= 0.0)
        state.sell_level_price[0] = bid;
      bool opened = opened_buy || opened_sell;
      if (opened)
        state.initial_started = true;
      attempted_initial = true;
    }
  }

  if (attempted_initial)
  {
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }

  double grid_step = 0.0;
  double atr_base = GetAtrBase(state);
  double atr_ref = atr_base;
  if (params.min_atr > atr_ref)
    atr_ref = params.min_atr;
  if (atr_ref > 0.0)
    grid_step = atr_ref * params.atr_multiplier;

  if (buy.count > 0)
    state.buy_grid_step = MathMax(state.buy_grid_step, grid_step);
  if (sell.count > 0)
    state.sell_grid_step = MathMax(state.sell_grid_step, grid_step);

  bool allow_nanpin = true;
  bool safety_triggered = false;
  double atr_now = 0.0;
  if (params.safety_mode && atr_base > 0.0)
  {
    atr_now = GetCurrentAtr(state);
    if (atr_now >= atr_base * params.safe_k)
    {
      safety_triggered = true;
      if (!params.safe_stop_mode)
        allow_nanpin = false;
    }
    double atr_slope = GetAtrSlope(state);
    if (atr_slope > atr_base * params.safe_slope_k)
    {
      safety_triggered = true;
      if (!params.safe_stop_mode)
        allow_nanpin = false;
    }
  }
  if (params.safety_mode)
  {
    bool prev = state.safety_active;
    state.safety_active = safety_triggered || !allow_nanpin;
    if (state.safety_active != prev)
    {
      string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      if (state.safety_active)
        PrintFormat("Safety mode ON: %s (%s)", ts, symbol);
      else
        PrintFormat("Safety mode OFF: %s (%s)", ts, symbol);
    }
  }

  if (params.safe_stop_mode && safety_triggered)
  {
    if (buy.count > 0)
      CloseBasket(state, POSITION_TYPE_BUY);
    if (sell.count > 0)
      CloseBasket(state, POSITION_TYPE_SELL);
    return;
  }

  bool allow_buy_trigger = allow_nanpin;
  bool allow_sell_trigger = allow_nanpin;
  bool buy_stop = false;
  bool sell_stop = false;
  if (allow_nanpin)
  {
    double adx_now = 0.0;
    double adx_prev = 0.0;
    double di_plus_now = 0.0;
    double di_plus_prev = 0.0;
    double di_minus_now = 0.0;
    double di_minus_prev = 0.0;
    if (GetAdxSnapshot(state, adx_now, adx_prev, di_plus_now, di_plus_prev, di_minus_now, di_minus_prev))
    {
      double buy_gap = di_minus_now - di_plus_now;
      double buy_gap_prev = di_minus_prev - di_plus_prev;
      double sell_gap = di_plus_now - di_minus_now;
      double sell_gap_prev = di_plus_prev - di_minus_prev;
      buy_stop = (adx_now >= params.adx_max_for_nanpin && buy_gap >= params.di_gap_min);
      sell_stop = (adx_now >= params.adx_max_for_nanpin && sell_gap >= params.di_gap_min);
      bool adx_falling = adx_now < adx_prev;
      if (buy_stop && adx_falling && buy_gap < buy_gap_prev)
        buy_stop = false;
      if (sell_stop && adx_falling && sell_gap < sell_gap_prev)
        sell_stop = false;
    }
  }
  allow_buy_trigger = allow_nanpin && !buy_stop;
  allow_sell_trigger = allow_nanpin && !sell_stop;

  if (atr_now <= 0.0)
    atr_now = GetCurrentAtr(state);
  ProcessFlexPartial(state, symbol, bid, ask, atr_now);

  if (params.no_martingale && buy.count > 0 && sell.count > 0)
  {
    int max_level = MathMax(buy.level_count, sell.level_count);
    double total_profit = (buy.profit + state.realized_buy_profit) + (sell.profit + state.realized_sell_profit);
    if (max_level >= 5 && total_profit > 0.0)
    {
      CloseBasket(state, POSITION_TYPE_BUY);
      CloseBasket(state, POSITION_TYPE_SELL);
      state.prev_buy_count = buy.count;
      state.prev_sell_count = sell.count;
      return;
    }
  }

  if (buy.count > 0)
  {
    if (state.has_partial_buy)
    {
      double value_per_unit = PriceValuePerUnit(symbol);
      double target_profit = buy.volume * params.profit_base * 0.5 * value_per_unit;
      if (value_per_unit > 0.0)
      {
        if ((buy.profit + state.realized_buy_profit) >= target_profit)
          CloseBasket(state, POSITION_TYPE_BUY);
      }
      else
      {
        double target = buy.avg_price + params.profit_base;
        if (bid >= target)
          CloseBasket(state, POSITION_TYPE_BUY);
      }
    }
    else
    {
      double target = buy.avg_price + params.profit_base;
      if (bid >= target)
        CloseBasket(state, POSITION_TYPE_BUY);
    }
  }

  if (sell.count > 0)
  {
    if (state.has_partial_sell)
    {
      double value_per_unit = PriceValuePerUnit(symbol);
      double target_profit = sell.volume * params.profit_base * 0.5 * value_per_unit;
      if (value_per_unit > 0.0)
      {
        if ((sell.profit + state.realized_sell_profit) >= target_profit)
          CloseBasket(state, POSITION_TYPE_SELL);
      }
      else
      {
        double target = sell.avg_price - params.profit_base;
        if (ask <= target)
          CloseBasket(state, POSITION_TYPE_SELL);
      }
    }
    else
    {
      double target = sell.avg_price - params.profit_base;
      if (ask <= target)
        CloseBasket(state, POSITION_TYPE_SELL);
    }
  }

  if (is_trading_time)
  {
    if (state.initial_started)
    {
      if (buy.count == 0 && CanRestart(params, state.last_buy_close_time))
      {
        bool opened_buy = TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
        if (opened_buy && state.buy_level_price[0] <= 0.0)
          state.buy_level_price[0] = ask;
      }
      if (sell.count == 0 && CanRestart(params, state.last_sell_close_time))
      {
        bool opened_sell = TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
        if (opened_sell && state.sell_level_price[0] <= 0.0)
          state.sell_level_price[0] = bid;
      }
    }

    int levels = EffectiveMaxLevels(params);
    if (buy.count > 0)
    {
      if (buy_stop)
      {
        double step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
        if (!state.buy_stop_active)
        {
          state.buy_stop_active = true;
          state.buy_skip_distance = 0.0;
          state.buy_skip_price = ask;
        }
        if (step > 0.0 && state.buy_skip_price > 0.0)
        {
          double distance = state.buy_skip_price - ask;
          if (distance < 0.0)
            distance = 0.0;
          while (distance >= step && (buy.level_count + state.buy_skip_levels) < levels)
          {
            distance -= step;
            state.buy_skip_levels++;
            state.buy_skip_price -= step;
            int skipped_index = buy.level_count + state.buy_skip_levels - 1;
            if (skipped_index >= 0 && skipped_index < NM1::kMaxLevels)
              EnsureBuyTarget(state, buy, step, skipped_index);
          }
          state.buy_skip_distance = distance;
        }
      }
      else
      {
        state.buy_stop_active = false;
        state.buy_skip_price = 0.0;
      }
    }
    if (sell.count > 0)
    {
      if (sell_stop)
      {
        double step = state.sell_grid_step > 0.0 ? state.sell_grid_step : grid_step;
        if (!state.sell_stop_active)
        {
          state.sell_stop_active = true;
          state.sell_skip_distance = 0.0;
          state.sell_skip_price = bid;
        }
        if (step > 0.0 && state.sell_skip_price > 0.0)
        {
          double distance = bid - state.sell_skip_price;
          if (distance < 0.0)
            distance = 0.0;
          while (distance >= step && (sell.level_count + state.sell_skip_levels) < levels)
          {
            distance -= step;
            state.sell_skip_levels++;
            state.sell_skip_price += step;
            int skipped_index = sell.level_count + state.sell_skip_levels - 1;
            if (skipped_index >= 0 && skipped_index < NM1::kMaxLevels)
              EnsureSellTarget(state, sell, step, skipped_index);
          }
          state.sell_skip_distance = distance;
        }
      }
      else
      {
        state.sell_stop_active = false;
        state.sell_skip_price = 0.0;
      }
    }

    if (buy.count > 0 && (buy.level_count + state.buy_skip_levels) < levels)
    {
      // Buy orders fill at ask, so compare ask to the grid.
      double step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
      int level_index = buy.level_count + state.buy_skip_levels;
      double target = 0.0;
      target = EnsureBuyTarget(state, buy, step, level_index);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if (point <= 0.0)
        point = 0.00001;
      double tol = point * 0.5;
      if (allow_buy_trigger && CanNanpin(params, state.last_buy_nanpin_time) && ask <= target + tol)
      {
        double lot = state.lot_seq[level_index];
        int next_level = level_index + 1;
        if (next_level >= NM1::kCoreFlexSplitLevel)
        {
          double core_lot = 0.0;
          double flex_lot = 0.0;
          NormalizeCoreFlexLot(params, symbol, lot, core_lot, flex_lot);
          bool opened = false;
          if (core_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_BUY, core_lot, MakeLevelComment(NM1::kCoreComment, next_level));
          if (flex_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_BUY, flex_lot, MakeLevelComment(NM1::kFlexComment, next_level));
          if (opened)
            state.last_buy_nanpin_time = TimeCurrent();
        }
        else
        {
          if (TryOpen(state, symbol, ORDER_TYPE_BUY, lot, MakeLevelComment(NM1::kCoreComment, next_level)))
            state.last_buy_nanpin_time = TimeCurrent();
        }
      }
    }

    if (sell.count > 0 && (sell.level_count + state.sell_skip_levels) < levels)
    {
      // Sell orders fill at bid, so compare bid to the grid.
      double step = state.sell_grid_step > 0.0 ? state.sell_grid_step : grid_step;
      int level_index = sell.level_count + state.sell_skip_levels;
      double target = 0.0;
      target = EnsureSellTarget(state, sell, step, level_index);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if (point <= 0.0)
        point = 0.00001;
      double tol = point * 0.5;
      if (allow_sell_trigger && CanNanpin(params, state.last_sell_nanpin_time) && bid >= target - tol)
      {
        double lot = state.lot_seq[level_index];
        int next_level = level_index + 1;
        if (next_level >= NM1::kCoreFlexSplitLevel)
        {
          double core_lot = 0.0;
          double flex_lot = 0.0;
          NormalizeCoreFlexLot(params, symbol, lot, core_lot, flex_lot);
          bool opened = false;
          if (core_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_SELL, core_lot, MakeLevelComment(NM1::kCoreComment, next_level));
          if (flex_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_SELL, flex_lot, MakeLevelComment(NM1::kFlexComment, next_level));
          if (opened)
            state.last_sell_nanpin_time = TimeCurrent();
        }
        else
        {
          if (TryOpen(state, symbol, ORDER_TYPE_SELL, lot, MakeLevelComment(NM1::kCoreComment, next_level)))
            state.last_sell_nanpin_time = TimeCurrent();
        }
      }
    }

    if (allow_buy_trigger)
    {
      if (buy.count > 0)
        ProcessFlexRefill(state, symbol, ORDER_TYPE_BUY, state.flex_buy_refs, ask);
    }
    if (allow_sell_trigger)
    {
      if (sell.count > 0)
        ProcessFlexRefill(state, symbol, ORDER_TYPE_SELL, state.flex_sell_refs, bid);
    }
  }

  state.prev_buy_count = buy.count;
  state.prev_sell_count = sell.count;
}

void OnTick()
{
  for (int i = 0; i < symbols_count; ++i)
    ProcessSymbolTick(symbols[i]);
}

void OnTimer()
{
  OnTick();
}
