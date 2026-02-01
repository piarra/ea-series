#property strict
#property version   "1.29"

// v1.24 ナンピン停止ルール追加, ナンピン幅の厳格化
// v1.25 AdxMaxForNanpinのデフォルトを20.0に、DiGapMinのデフォルトを2.0に
// v1.26 no martingaleモードを用意
// v1.27 strictモード(ナンピン幅厳格モード)を用意
// v1.28 moneyManagementモードを追加

#include <Trade/Trade.mqh>

namespace NM1
{
enum { kMaxLevels = 13 };
enum { kMaxSymbols = 6 };
const int kAtrBasePeriod = 14;
const int kLotDigits = 2;
const double kMinLot = 0.01;
const double kMaxLot = 100.0;
const string kFlexComment = "NM1_FLEX";
const string kCoreComment = "NM1_CORE";
const string kHedgeComment = "NM1_HEDGE";
}

enum RegimeState
{
  REGIME_NORMAL = 0,
  REGIME_TREND_UP,
  REGIME_TREND_DOWN,
  REGIME_COOLING
};

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
input int CoreSplitLevel = 100;
input double CoreRatio = 1.0;
input double FlexRatio = 0;
input double FlexAtrProfitMultiplier = 0.8;
input int RestartDelaySeconds = 1;
input int NanpinSleepSeconds = 10;
input int AdxPeriod = 14;
input double AdxMaxForNanpin = 20.0;
input double DiGapMin = 2.0;

input group "REGIME FILTER"
input int RegimeOnBars = 3;
input int RegimeOffBars = 5;
input int RegimeCoolingBars = 15;
input double RegimeAdxOn = 25.0; // not fixed
input double RegimeDiGapOn = 6.0; // not fixed
input double RegimeAdxOff = 18.0; // not fixed
input double RegimeDiGapOff = 3.0; // not fixed
input bool CloseOppositeOnTrend = false;
input double TrendLotMultiplier = 1.0; // not fixed

input group "TREND HEDGE"
input bool EnableTrendHedge = false;
input double HedgeRatio = 0.5;
input int HedgeMagicOffset = 10000;
input int HedgeCooldownSeconds = 5;
input int HedgeRecoveryMinutes = 360;
input double HedgeRecoveryPercent = 10.0;
input bool EnableLonelyL1Close = true;
input int LonelyL1CloseMinutes = 60;
input int MultiLevelCloseMinutes = 180;

input group "DEBUG"
input bool DebugMode = false;
enum HedgeProfitMode
{
  HEDGE_PROFIT_FIXED = 0,
  HEDGE_PROFIT_TRAIL = 1
};
input HedgeProfitMode HedgeProfitModeInput = HEDGE_PROFIT_FIXED;

input group "MONEY MANAGEMENT"
input bool EnableMoneyManagement = false;
input double SessionMaxDD = 2000.0;
input double SessionTargetMultiplier = 10.0;
input int SessionFailureIntervalSeconds = 120;

input group "XAUUSD"
input bool EnableXAUUSD = true;
input string SymbolXAUUSD = "XAUUSD";
input double BaseLotXAUUSD = 0.05;
input double AtrMultiplierXAUUSD = 1.2;
input double NanpinLevelRatioXAUUSD = 1.1; // not fixed
input bool StrictNanpinSpacingXAUUSD = true;
input double MinAtrXAUUSD = 1.6;
input double ProfitBaseXAUUSD = 2.0;
input int MaxLevelsXAUUSD = 12;
input double StopBuyLimitPriceXAUUSD = 4000.0;
input double StopBuyLimitLotXAUUSD = 0.01;
input bool NoMartingaleXAUUSD = false;

input group "EURUSD"
input bool EnableEURUSD = false;
input string SymbolEURUSD = "EURUSD";
input double BaseLotEURUSD = 0.3;
input double AtrMultiplierEURUSD = 3.0;
input double NanpinLevelRatioEURUSD = 1.1;
input bool StrictNanpinSpacingEURUSD = true;
input double MinAtrEURUSD = 0.00050;
input double ProfitBaseEURUSD = 0.00010;
input int MaxLevelsEURUSD = 10;
input double StopBuyLimitPriceEURUSD = 4000.0;
input double StopBuyLimitLotEURUSD = 0.01;
input bool NoMartingaleEURUSD = false;

input group "USDJPY"
input bool EnableUSDJPY = false;
input string SymbolUSDJPY = "USDJPY";
input double BaseLotUSDJPY = 0.3;
input double AtrMultiplierUSDJPY = 3.0;
input double NanpinLevelRatioUSDJPY = 1.1;
input bool StrictNanpinSpacingUSDJPY = true;
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
input double NanpinLevelRatioAUDUSD = 1.1;
input bool StrictNanpinSpacingAUDUSD = true;
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
input double NanpinLevelRatioBTCUSD = 1.1;
input bool StrictNanpinSpacingBTCUSD = true;
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
input double NanpinLevelRatioETHUSD = 1.1;
input bool StrictNanpinSpacingETHUSD = true;
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
  double nanpin_level_ratio;
  bool strict_nanpin_spacing;
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
  int regime_on_bars;
  int regime_off_bars;
  int regime_cooling_bars;
  double regime_adx_on;
  double regime_di_gap_on;
  double regime_adx_off;
  double regime_di_gap_off;
  bool close_opposite_on_trend;
  double trend_lot_multiplier;
  bool enable_trend_hedge;
  double hedge_ratio;
  int hedge_magic_offset;
  int hedge_cooldown_seconds;
  int hedge_profit_mode;
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

struct HedgeInfo
{
  double buy_volume;
  double buy_avg_price;
  double buy_profit;
  double sell_volume;
  double sell_avg_price;
  double sell_profit;
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

bool mm_session_active = false;
bool mm_session_end_pending = false;
bool mm_session_end_success = false;
bool mm_session_waiting = false;
datetime mm_session_wait_until = 0;
datetime mm_session_start_time = 0;
double mm_session_start_equity = 0.0;
int mm_session_id = 0;
int mm_session_id_current = 0;
datetime hedge_mode_start_time = 0;
double hedge_mode_start_equity = 0.0;
double cumulative_trade_lots = 0.0;
datetime cumulative_lot_start_time = 0;

struct SymbolState
{
  string logical_symbol;
  string broker_symbol;
  bool enabled;
  NM1Params params;
  bool symbol_info_ready;
  double point;
  int digits;
  double volume_step;
  double volume_min;
  double volume_max;
  double tick_value;
  double tick_size;
  int filling_mode;
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
  datetime buy_open_time;
  datetime sell_open_time;
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
  int regime;
  int regime_up_count;
  int regime_down_count;
  int regime_off_count;
  int regime_cooling_left;
  datetime last_bar_time;
  datetime last_hedge_time;
  datetime last_hedge_reduce_time;
  double hedge_buy_peak;
  double hedge_sell_peak;
};

SymbolState symbols[NM1::kMaxSymbols];
int symbols_count = 0;

bool IsManagedMagic(const int magic)
{
  if (magic == MagicNumber)
    return true;
  if (HedgeMagicOffset != 0 && magic == MagicNumber + HedgeMagicOffset)
    return true;
  return false;
}

void InitCumulativeLotTracking()
{
  cumulative_trade_lots = 0.0;
  cumulative_lot_start_time = TimeCurrent();
}

bool ClosePositionWithLog(const ulong ticket, const string context)
{
  double volume = 0.0;
  string symbol = "";
  int magic = 0;
  bool has_info = false;
  if (PositionSelectByTicket(ticket))
  {
    volume = PositionGetDouble(POSITION_VOLUME);
    symbol = PositionGetString(POSITION_SYMBOL);
    magic = (int)PositionGetInteger(POSITION_MAGIC);
    has_info = true;
  }
  bool closed = close_trade.PositionClose(ticket);
  if (closed && has_info && IsManagedMagic(magic) && volume > 0.0)
  {
    cumulative_trade_lots += volume;
    if (StringLen(context) > 0)
    {
      PrintFormat("Position closed: ticket=%I64u symbol=%s lots=%.2f cumulative=%.2f (%s)",
                  ticket, symbol, volume, cumulative_trade_lots, context);
    }
    else
    {
      PrintFormat("Position closed: ticket=%I64u symbol=%s lots=%.2f cumulative=%.2f",
                  ticket, symbol, volume, cumulative_trade_lots);
    }
  }
  return closed;
}

bool HasDebugPendingOrder(const SymbolState &state, const string regime_name)
{
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  for (int i = OrdersTotal() - 1; i >= 0; --i)
  {
    ulong ticket = OrderGetTicket(i);
    if (!OrderSelect(ticket))
      continue;
    if (OrderGetInteger(ORDER_MAGIC) != magic)
      continue;
    if (OrderGetString(ORDER_SYMBOL) != symbol)
      continue;
    if ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT)
      continue;
    string comment = OrderGetString(ORDER_COMMENT);
    string expected = StringFormat("NM1_DEBUG_%s", regime_name);
    if (comment == expected)
      return true;
  }
  return false;
}

void CancelDebugPendingOrders(const SymbolState &state)
{
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  for (int i = OrdersTotal() - 1; i >= 0; --i)
  {
    ulong ticket = OrderGetTicket(i);
    if (!OrderSelect(ticket))
      continue;
    if (OrderGetInteger(ORDER_MAGIC) != magic)
      continue;
    if (OrderGetString(ORDER_SYMBOL) != symbol)
      continue;
    if ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT)
      continue;
    string comment = OrderGetString(ORDER_COMMENT);
    if (StringFind(comment, "NM1_DEBUG_") != 0)
      continue;
    trade.OrderDelete(ticket);
  }
}

int FindSymbolStateIndex(const string broker_symbol)
{
  for (int i = 0; i < symbols_count; ++i)
  {
    if (symbols[i].broker_symbol == broker_symbol)
      return i;
  }
  return -1;
}

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
  state.symbol_info_ready = false;
  state.point = 0.0;
  state.digits = 0;
  state.volume_step = 0.0;
  state.volume_min = 0.0;
  state.volume_max = 0.0;
  state.tick_value = 0.0;
  state.tick_size = 0.0;
  state.filling_mode = 0;
  state.start_time = TimeCurrent();
  state.initial_started = false;
  state.last_buy_close_time = 0;
  state.last_sell_close_time = 0;
  state.last_buy_nanpin_time = 0;
  state.last_sell_nanpin_time = 0;
  state.buy_open_time = 0;
  state.sell_open_time = 0;
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
  state.regime = REGIME_NORMAL;
  state.regime_up_count = 0;
  state.regime_down_count = 0;
  state.regime_off_count = 0;
  state.regime_cooling_left = 0;
  state.last_bar_time = 0;
  state.last_hedge_time = 0;
  state.last_hedge_reduce_time = 0;
  state.hedge_buy_peak = 0.0;
  state.hedge_sell_peak = 0.0;
  ClearFlexRefs(state.flex_buy_refs);
  ClearFlexRefs(state.flex_sell_refs);
  ClearLevelPrices(state.buy_level_price);
  ClearLevelPrices(state.sell_level_price);
  state.buy_grid_step = 0.0;
  state.sell_grid_step = 0.0;
}

void RefreshSymbolInfo(SymbolState &state)
{
  const string symbol = state.broker_symbol;
  state.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  state.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  state.volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
  state.volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
  state.volume_max = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
  state.tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
  state.tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  state.filling_mode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
  state.symbol_info_ready = true;
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
  params.regime_on_bars = RegimeOnBars;
  params.regime_off_bars = RegimeOffBars;
  params.regime_cooling_bars = RegimeCoolingBars;
  params.regime_adx_on = RegimeAdxOn;
  params.regime_di_gap_on = RegimeDiGapOn;
  params.regime_adx_off = RegimeAdxOff;
  params.regime_di_gap_off = RegimeDiGapOff;
  params.close_opposite_on_trend = CloseOppositeOnTrend;
  params.trend_lot_multiplier = TrendLotMultiplier;
  params.enable_trend_hedge = EnableTrendHedge;
  params.hedge_ratio = HedgeRatio;
  params.hedge_magic_offset = HedgeMagicOffset;
  params.hedge_cooldown_seconds = HedgeCooldownSeconds;
  params.hedge_profit_mode = (int)HedgeProfitModeInput;
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
    params.nanpin_level_ratio = NanpinLevelRatioXAUUSD;
    params.strict_nanpin_spacing = StrictNanpinSpacingXAUUSD;
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
    params.nanpin_level_ratio = NanpinLevelRatioEURUSD;
    params.strict_nanpin_spacing = StrictNanpinSpacingEURUSD;
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
    params.nanpin_level_ratio = NanpinLevelRatioUSDJPY;
    params.strict_nanpin_spacing = StrictNanpinSpacingUSDJPY;
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
    params.nanpin_level_ratio = NanpinLevelRatioAUDUSD;
    params.strict_nanpin_spacing = StrictNanpinSpacingAUDUSD;
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
    params.nanpin_level_ratio = NanpinLevelRatioBTCUSD;
    params.strict_nanpin_spacing = StrictNanpinSpacingBTCUSD;
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
    params.nanpin_level_ratio = NanpinLevelRatioETHUSD;
    params.strict_nanpin_spacing = StrictNanpinSpacingETHUSD;
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
      RefreshSymbolInfo(symbols[symbols_count]);
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

double NormalizeLotCached(const SymbolState &state, double lot)
{
  double step = state.volume_step;
  double minlot = state.volume_min;
  double maxlot = state.volume_max;
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

void NormalizeCoreFlexLot(const SymbolState &state, double lot, double &core, double &flex)
{
  double core_ratio = NormalizeRatio(state.params.core_ratio, 0.7);
  double flex_ratio = NormalizeRatio(state.params.flex_ratio, 0.3);
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
  flex = NormalizeLotCached(state, raw_flex);
  core = NormalizeLotCached(state, lot - flex);
  if (flex <= 0.0)
  {
    flex = 0.0;
    core = NormalizeLotCached(state, lot);
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

bool AddFlexRef(const SymbolState &state, FlexRef &refs[], double price, double lot, int level)
{
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double tol = point * 0.5;
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

void BuildLotSequence(SymbolState &state)
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
    state.lot_seq[i] = NormalizeLotCached(state, state.lot_seq[i]);
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
    if (!symbols[i].symbol_info_ready)
      RefreshSymbolInfo(symbols[i]);
    BuildLotSequence(symbols[i]);
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
  if (!MQLInfoInteger(MQL_TESTER))
  {
    if (!EventSetMillisecondTimer(500))
      Print("EventSetMillisecondTimer failed");
  }

  for (int i = 0; i < symbols_count; ++i)
  {
    if (!symbols[i].enabled)
      continue;
    if (HasOpenPosition(symbols[i]))
      symbols[i].initial_started = true;
  }
  InitCumulativeLotTracking();
  if (EnableMoneyManagement)
    StartSession();
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

bool GetAtrSnapshot(SymbolState &state, double &atr_base, double &atr_now, double &atr_slope)
{
  atr_base = 0.0;
  atr_now = 0.0;
  atr_slope = 0.0;
  if (state.atr_handle == INVALID_HANDLE)
    return false;

  double buffer[55];
  const int kNeeded = 55;
  int copied = CopyBuffer(state.atr_handle, 0, 0, kNeeded, buffer);
  if (copied <= 0)
    return false;

  atr_now = buffer[0];
  if (copied >= 3)
    atr_slope = buffer[0] - buffer[2];
  if (copied >= kNeeded)
  {
    double sum = 0.0;
    for (int i = 5; i < kNeeded; ++i)
      sum += buffer[i];
    atr_base = sum / 50.0;
  }
  return true;
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

double LevelStepFactor(const NM1Params &params, int level)
{
  if (level <= 1)
    return 1.0;
  double ratio = params.nanpin_level_ratio;
  if (ratio <= 0.0)
    return 1.0;
  return MathPow(ratio, level - 1);
}

double AdjustNanpinStep(const double &level_prices[], int level_index, double step, bool enabled)
{
  if (!enabled || level_index < 3)
    return step;
  double p1 = level_prices[level_index - 1];
  double p2 = level_prices[level_index - 2];
  double p3 = level_prices[level_index - 3];
  if (p1 <= 0.0 || p2 <= 0.0 || p3 <= 0.0)
    return step;
  double w1 = MathAbs(p1 - p2);
  double w2 = MathAbs(p2 - p3);
  double min_w = MathMin(w1, w2);
  if (min_w <= 0.0)
    return step;
  return MathMax(step, min_w);
}

string RegimeName(const int regime)
{
  if (regime == REGIME_TREND_UP)
    return "TREND_UP";
  if (regime == REGIME_TREND_DOWN)
    return "TREND_DOWN";
  if (regime == REGIME_COOLING)
    return "COOLING";
  return "NORMAL";
}

bool IsNewBar(SymbolState &state)
{
  datetime bar_time = iTime(state.broker_symbol, _Period, 0);
  if (bar_time == 0)
    return false;
  if (state.last_bar_time == 0 || bar_time != state.last_bar_time)
  {
    state.last_bar_time = bar_time;
    return true;
  }
  return false;
}

void UpdateRegime(SymbolState &state, double adx_now, double di_plus_now, double di_minus_now, bool new_bar)
{
  if (!new_bar)
    return;
  int prev = state.regime;
  int on_bars = MathMax(state.params.regime_on_bars, 1);
  int off_bars = MathMax(state.params.regime_off_bars, 1);
  int cooling_bars = MathMax(state.params.regime_cooling_bars, 0);
  double di_gap = MathAbs(di_plus_now - di_minus_now);
  bool on_cond = (adx_now >= state.params.regime_adx_on && di_gap >= state.params.regime_di_gap_on);
  bool off_cond = (adx_now <= state.params.regime_adx_off || di_gap <= state.params.regime_di_gap_off);

  if (state.regime == REGIME_COOLING)
  {
    if (state.regime_cooling_left > 0)
      state.regime_cooling_left--;
    if (state.regime_cooling_left <= 0)
    {
      state.regime = REGIME_NORMAL;
      state.regime_up_count = 0;
      state.regime_down_count = 0;
      state.regime_off_count = 0;
    }
  }
  else if (state.regime == REGIME_TREND_UP || state.regime == REGIME_TREND_DOWN)
  {
    if (off_cond)
      state.regime_off_count++;
    else
      state.regime_off_count = 0;
    if (state.regime_off_count >= off_bars)
    {
      state.regime = REGIME_COOLING;
      state.regime_cooling_left = cooling_bars;
      state.regime_off_count = 0;
    }
  }
  else
  {
    if (on_cond)
    {
      if (di_plus_now > di_minus_now)
      {
        state.regime_up_count++;
        state.regime_down_count = 0;
      }
      else if (di_minus_now > di_plus_now)
      {
        state.regime_down_count++;
        state.regime_up_count = 0;
      }
    }
    else
    {
      state.regime_up_count = 0;
      state.regime_down_count = 0;
    }
    if (state.regime_up_count >= on_bars)
    {
      state.regime = REGIME_TREND_UP;
      state.regime_up_count = 0;
      state.regime_down_count = 0;
    }
    else if (state.regime_down_count >= on_bars)
    {
      state.regime = REGIME_TREND_DOWN;
      state.regime_up_count = 0;
      state.regime_down_count = 0;
    }
  }

  if (state.regime != prev)
  {
    if (state.params.close_opposite_on_trend)
    {
      if (state.regime == REGIME_TREND_UP)
        CloseBasket(state, POSITION_TYPE_SELL);
      else if (state.regime == REGIME_TREND_DOWN)
        CloseBasket(state, POSITION_TYPE_BUY);
    }
    PrintFormat("Regime changed: %s -> %s (%s)", RegimeName(prev), RegimeName(state.regime), state.broker_symbol);
  }
}

int HedgeMagic(const SymbolState &state)
{
  return state.params.magic_number + state.params.hedge_magic_offset;
}

double GetHedgeVolume(const SymbolState &state, ENUM_POSITION_TYPE type)
{
  if (state.params.hedge_magic_offset == 0)
    return 0.0;
  const string symbol = state.broker_symbol;
  const int magic = HedgeMagic(state);
  double volume = 0.0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    volume += PositionGetDouble(POSITION_VOLUME);
  }
  return volume;
}

void CloseHedgePositions(const SymbolState &state, ENUM_POSITION_TYPE type)
{
  if (state.params.hedge_magic_offset == 0)
    return;
  const string symbol = state.broker_symbol;
  const int magic = HedgeMagic(state);
  close_trade.SetExpertMagicNumber(magic);
  close_trade.SetDeviationInPoints(state.params.slippage_points);
  close_trade.SetAsyncMode(state.params.use_async_close);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  ulong tickets[];
  int count = 0;
  int total = PositionsTotal();
  if (total > 0)
    ArrayResize(tickets, total);
  for (int i = total - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    tickets[count++] = ticket;
  }
  if (count > 0)
    ArrayResize(tickets, count);

  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    while (attempts <= state.params.close_retry_count)
    {
      if (ClosePositionWithLog(tickets[i], "hedge"))
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
      PrintFormat("Hedge close failed after retries: ticket=%I64u retcode=%d %s",
                  tickets[i], close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
}

bool ReduceHedgePositions(SymbolState &state, ENUM_POSITION_TYPE type, double ratio)
{
  if (state.params.hedge_magic_offset == 0)
    return false;
  if (ratio <= 0.0 || ratio >= 1.0)
    return false;
  double current = GetHedgeVolume(state, type);
  if (current <= 0.0)
    return false;
  double target = current * ratio;
  double minlot = state.volume_min > 0.0 ? state.volume_min : NM1::kMinLot;
  if (current - target < minlot * 0.5)
    return false;

  const string symbol = state.broker_symbol;
  const int magic = HedgeMagic(state);
  close_trade.SetExpertMagicNumber(magic);
  close_trade.SetDeviationInPoints(state.params.slippage_points);
  close_trade.SetAsyncMode(state.params.use_async_close);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);

  ulong tickets[];
  int count = 0;
  int total = PositionsTotal();
  if (total > 0)
    ArrayResize(tickets, total);
  for (int i = total - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    tickets[count++] = ticket;
  }
  if (count > 0)
    ArrayResize(tickets, count);

  double remaining = current;
  bool reduced = false;
  for (int i = 0; i < count; ++i)
  {
    if (remaining <= target + minlot * 0.5)
      break;
    if (!PositionSelectByTicket(tickets[i]))
      continue;
    double vol = PositionGetDouble(POSITION_VOLUME);
    bool closed = false;
    int attempts = 0;
    while (attempts <= state.params.close_retry_count)
    {
      if (ClosePositionWithLog(tickets[i], "hedge_reduce"))
      {
        closed = true;
        break;
      }
      attempts++;
      if (attempts <= state.params.close_retry_count && state.params.close_retry_delay_ms > 0)
        Sleep(state.params.close_retry_delay_ms);
    }
    if (closed)
    {
      remaining -= vol;
      reduced = true;
    }
    else
    {
      PrintFormat("Hedge reduce close failed: ticket=%I64u retcode=%d %s",
                  tickets[i], close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
  if (reduced)
    state.last_hedge_reduce_time = TimeCurrent();
  return reduced;
}

bool TryOpenHedge(const SymbolState &state, ENUM_ORDER_TYPE order_type, double lot)
{
  if (state.params.hedge_magic_offset == 0)
    return false;
  lot = NormalizeLotCached(state, lot);
  if (lot <= 0.0)
    return false;
  trade.SetExpertMagicNumber(HedgeMagic(state));
  trade.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  string comment = AppendSessionSuffix(NM1::kHedgeComment);
  bool ok = false;
  if (order_type == ORDER_TYPE_BUY)
    ok = trade.Buy(lot, state.broker_symbol, 0.0, 0.0, 0.0, comment);
  else if (order_type == ORDER_TYPE_SELL)
    ok = trade.Sell(lot, state.broker_symbol, 0.0, 0.0, 0.0, comment);
  if (!ok)
  {
    PrintFormat("Hedge order failed: type=%d lot=%.2f retcode=%d %s",
                order_type, lot, trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }
  return ok;
}

void ProcessTrendHedge(SymbolState &state, const BasketInfo &buy, const BasketInfo &sell)
{
  if (!state.params.enable_trend_hedge)
    return;
  if (state.params.hedge_ratio <= 0.0)
    return;
  if (state.params.hedge_magic_offset == 0)
    return;

  if (state.regime == REGIME_COOLING)
  {
    datetime now = TimeCurrent();
    if (state.params.hedge_cooldown_seconds > 0 && state.last_hedge_reduce_time > 0 &&
        (now - state.last_hedge_reduce_time) < state.params.hedge_cooldown_seconds)
      return;
    ReduceHedgePositions(state, POSITION_TYPE_BUY, 0.5);
    ReduceHedgePositions(state, POSITION_TYPE_SELL, 0.5);
    return;
  }

  if (state.regime == REGIME_NORMAL)
  {
    if (GetHedgeVolume(state, POSITION_TYPE_BUY) > 0.0)
      CloseHedgePositions(state, POSITION_TYPE_BUY);
    if (GetHedgeVolume(state, POSITION_TYPE_SELL) > 0.0)
      CloseHedgePositions(state, POSITION_TYPE_SELL);
    return;
  }

  if (state.regime != REGIME_TREND_UP && state.regime != REGIME_TREND_DOWN)
    return;

  datetime now = TimeCurrent();
  if (state.params.hedge_cooldown_seconds > 0 && state.last_hedge_time > 0 &&
      (now - state.last_hedge_time) < state.params.hedge_cooldown_seconds)
    return;

  if (state.regime == REGIME_TREND_UP)
  {
    if (sell.level_count < 4)
      return;
    if (GetHedgeVolume(state, POSITION_TYPE_SELL) > 0.0)
      CloseHedgePositions(state, POSITION_TYPE_SELL);
    double losing = (sell.profit + state.realized_sell_profit) < 0.0 ? sell.volume : 0.0;
    if (losing <= 0.0)
      return;
    double target = losing * state.params.hedge_ratio;
    double current = GetHedgeVolume(state, POSITION_TYPE_BUY);
    double need = target - current;
    double minlot = state.volume_min > 0.0 ? state.volume_min : NM1::kMinLot;
    if (need > minlot * 0.5)
    {
      if (TryOpenHedge(state, ORDER_TYPE_BUY, need))
        state.last_hedge_time = now;
    }
  }
  else if (state.regime == REGIME_TREND_DOWN)
  {
    if (buy.level_count < 4)
      return;
    if (GetHedgeVolume(state, POSITION_TYPE_BUY) > 0.0)
      CloseHedgePositions(state, POSITION_TYPE_BUY);
    double losing = (buy.profit + state.realized_buy_profit) < 0.0 ? buy.volume : 0.0;
    if (losing <= 0.0)
      return;
    double target = losing * state.params.hedge_ratio;
    double current = GetHedgeVolume(state, POSITION_TYPE_SELL);
    double need = target - current;
    double minlot = state.volume_min > 0.0 ? state.volume_min : NM1::kMinLot;
    if (need > minlot * 0.5)
    {
      if (TryOpenHedge(state, ORDER_TYPE_SELL, need))
        state.last_hedge_time = now;
    }
  }
}

void CloseBasket(const SymbolState &state, ENUM_POSITION_TYPE type)
{
  const string symbol = state.broker_symbol;
  close_trade.SetExpertMagicNumber(state.params.magic_number);
  close_trade.SetDeviationInPoints(state.params.slippage_points);
  close_trade.SetAsyncMode(state.params.use_async_close);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  ulong tickets[];
  int count = 0;
  int total = PositionsTotal();
  if (total > 0)
    ArrayResize(tickets, total);
  for (int i = total - 1; i >= 0; --i)
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
    tickets[count++] = ticket;
  }
  if (count > 0)
    ArrayResize(tickets, count);

  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    while (attempts <= state.params.close_retry_count)
    {
      if (ClosePositionWithLog(tickets[i], "basket"))
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

double PipSize(const SymbolState &state)
{
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  if (state.digits == 3 || state.digits == 5)
    return point * 10.0;
  return point;
}

void CollectHedgeInfo(const SymbolState &state, HedgeInfo &hedge)
{
  const string symbol = state.broker_symbol;
  hedge.buy_volume = 0.0;
  hedge.buy_avg_price = 0.0;
  hedge.buy_profit = 0.0;
  hedge.sell_volume = 0.0;
  hedge.sell_avg_price = 0.0;
  hedge.sell_profit = 0.0;
  if (state.params.hedge_magic_offset == 0)
    return;

  double buy_value = 0.0;
  double sell_value = 0.0;
  const int magic = HedgeMagic(state);

  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;

    int type = (int)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    if (type == POSITION_TYPE_BUY)
    {
      hedge.buy_volume += volume;
      buy_value += volume * price;
      hedge.buy_profit += PositionGetDouble(POSITION_PROFIT);
    }
    else if (type == POSITION_TYPE_SELL)
    {
      hedge.sell_volume += volume;
      sell_value += volume * price;
      hedge.sell_profit += PositionGetDouble(POSITION_PROFIT);
    }
  }

  if (hedge.buy_volume > 0.0)
    hedge.buy_avg_price = buy_value / hedge.buy_volume;
  if (hedge.sell_volume > 0.0)
    hedge.sell_avg_price = sell_value / hedge.sell_volume;
}

bool CheckHedgeBasketBreakeven(SymbolState &state,
                               const BasketInfo &buy,
                               const BasketInfo &sell,
                               const HedgeInfo &hedge,
                               double value_per_unit)
{
  bool closed = false;
  if (hedge.buy_volume > 0.0)
  {
    double combined = hedge.buy_profit + (sell.profit + state.realized_sell_profit);
    double threshold = 0.0;
    if (value_per_unit > 0.0)
      threshold = (sell.volume + hedge.buy_volume) * state.params.profit_base * value_per_unit;
    if (combined >= threshold && sell.count > 0)
    {
      CloseBasket(state, POSITION_TYPE_SELL);
      closed = true;
    }
  }
  if (hedge.sell_volume > 0.0)
  {
    double combined = hedge.sell_profit + (buy.profit + state.realized_buy_profit);
    double threshold = 0.0;
    if (value_per_unit > 0.0)
      threshold = (buy.volume + hedge.sell_volume) * state.params.profit_base * value_per_unit;
    if (combined >= threshold && buy.count > 0)
    {
      CloseBasket(state, POSITION_TYPE_BUY);
      closed = true;
    }
  }
  return closed;
}

void ProcessHedgeTrailing(SymbolState &state, const HedgeInfo &hedge, double bid, double ask, double atr_now)
{
  double trail_atr = atr_now > 0.0 ? atr_now * 0.25 : 0.0;
  double trail_pips = PipSize(state) * 5.0;

  if (hedge.buy_volume <= 0.0)
  {
    state.hedge_buy_peak = 0.0;
  }
  else
  {
    if (state.hedge_buy_peak <= 0.0)
      state.hedge_buy_peak = bid;
    if (bid > state.hedge_buy_peak)
      state.hedge_buy_peak = bid;
    double move = state.hedge_buy_peak - hedge.buy_avg_price;
    double trail = trail_pips;
    if (trail_atr > 0.0 && move >= trail_atr)
      trail = trail_atr;
    if (bid <= state.hedge_buy_peak - trail)
    {
      CloseHedgePositions(state, POSITION_TYPE_BUY);
      state.hedge_buy_peak = 0.0;
    }
  }

  if (hedge.sell_volume <= 0.0)
  {
    state.hedge_sell_peak = 0.0;
  }
  else
  {
    if (state.hedge_sell_peak <= 0.0)
      state.hedge_sell_peak = ask;
    if (ask < state.hedge_sell_peak)
      state.hedge_sell_peak = ask;
    double move = hedge.sell_avg_price - state.hedge_sell_peak;
    double trail = trail_pips;
    if (trail_atr > 0.0 && move >= trail_atr)
      trail = trail_atr;
    if (ask >= state.hedge_sell_peak + trail)
    {
      CloseHedgePositions(state, POSITION_TYPE_SELL);
      state.hedge_sell_peak = 0.0;
    }
  }
}

bool TryOpen(const SymbolState &state, const string symbol, ENUM_ORDER_TYPE order_type, double lot, const string comment = "")
{
  double multiplier = state.params.trend_lot_multiplier;
  if (multiplier > 1.0)
  {
    if (order_type == ORDER_TYPE_BUY && state.regime == REGIME_TREND_UP)
      lot *= multiplier;
    else if (order_type == ORDER_TYPE_SELL && state.regime == REGIME_TREND_DOWN)
      lot *= multiplier;
  }
  lot = NormalizeLotCached(state, lot);
  if (lot <= 0.0)
    return false;
  trade.SetExpertMagicNumber(state.params.magic_number);
  trade.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  bool ok = false;
  string final_comment = AppendSessionSuffix(comment);
  if (order_type == ORDER_TYPE_BUY)
    ok = trade.Buy(lot, symbol, 0.0, 0.0, 0.0, final_comment);
  else if (order_type == ORDER_TYPE_SELL)
    ok = trade.Sell(lot, symbol, 0.0, 0.0, 0.0, final_comment);

  if (!ok)
  {
    PrintFormat("Order failed: type=%d lot=%.2f retcode=%d %s",
                order_type, lot, trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }
  return ok;
}

bool ShouldStopOnBuyLimit(const SymbolState &state, double limit_price, double limit_lot)
{
  if (limit_price <= 0.0 || limit_lot <= 0.0)
    return false;
  const string symbol = state.broker_symbol;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double price_tol = point * 0.5;
  double norm_lot = NormalizeLotCached(state, limit_lot);
  for (int i = OrdersTotal() - 1; i >= 0; --i)
  {
    ulong ticket = OrderGetTicket(i);
    if (!OrderSelect(ticket))
      continue;
    long magic = OrderGetInteger(ORDER_MAGIC);
    if (magic != state.params.magic_number && magic != 0)
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

double PriceValuePerUnitCached(const SymbolState &state)
{
  if (state.tick_value <= 0.0 || state.tick_size <= 0.0)
    return 0.0;
  return state.tick_value / state.tick_size;
}

bool CanRestart(const NM1Params &params, datetime last_close_time)
{
  if (last_close_time == 0)
    return true;
  return (TimeCurrent() - last_close_time) >= params.restart_delay_seconds;
}

string AppendSessionSuffix(const string comment)
{
  if (!EnableMoneyManagement || mm_session_id_current <= 0)
    return comment;
  string suffix = StringFormat("_S%d", mm_session_id_current);
  if (StringLen(comment) == 0)
    return suffix;
  return comment + suffix;
}

bool HasAnyPositionByMagic(const int magic)
{
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    return true;
  }
  return false;
}

bool HasAnyHedgePosition()
{
  if (HedgeMagicOffset == 0)
    return false;
  return HasAnyPositionByMagic(MagicNumber + HedgeMagicOffset);
}

void UpdateHedgeModeTracking()
{
  bool has_hedge = HasAnyHedgePosition();
  if (has_hedge)
  {
    if (hedge_mode_start_time == 0)
    {
      hedge_mode_start_time = TimeCurrent();
      hedge_mode_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    }
  }
  else
  {
    hedge_mode_start_time = 0;
    hedge_mode_start_equity = 0.0;
  }
}

void CloseAllPositionsByMagic(const int magic)
{
  close_trade.SetExpertMagicNumber(magic);
  close_trade.SetDeviationInPoints(SlippagePoints);
  close_trade.SetAsyncMode(UseAsyncClose);
  ulong tickets[];
  string symbols[];
  int count = 0;
  int total = PositionsTotal();
  if (total > 0)
  {
    ArrayResize(tickets, total);
    ArrayResize(symbols, total);
  }
  for (int i = total - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    tickets[count] = ticket;
    symbols[count] = PositionGetString(POSITION_SYMBOL);
    count++;
  }
  if (count > 0)
  {
    ArrayResize(tickets, count);
    ArrayResize(symbols, count);
  }

  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    int filling = (int)SymbolInfoInteger(symbols[i], SYMBOL_FILLING_MODE);
    if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
      close_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
    while (attempts <= CloseRetryCount)
    {
      if (ClosePositionWithLog(tickets[i], "close_all"))
      {
        closed = true;
        break;
      }
      attempts++;
      if (attempts <= CloseRetryCount && CloseRetryDelayMs > 0)
        Sleep(CloseRetryDelayMs);
    }
    if (!closed)
    {
      PrintFormat("Close failed after retries: ticket=%I64u retcode=%d %s",
                  tickets[i], close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
}

void CloseAllPositionsForEA()
{
  CloseAllPositionsByMagic(MagicNumber);
  if (HedgeMagicOffset != 0)
    CloseAllPositionsByMagic(MagicNumber + HedgeMagicOffset);
}

void StartSession()
{
  mm_session_id++;
  mm_session_id_current = mm_session_id;
  mm_session_active = true;
  mm_session_end_pending = false;
  mm_session_end_success = false;
  mm_session_waiting = false;
  mm_session_wait_until = 0;
  mm_session_start_time = TimeCurrent();
  mm_session_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
  PrintFormat("Session started: id=%d equity=%.2f", mm_session_id_current, mm_session_start_equity);
}

void EndSession(const bool success)
{
  mm_session_active = false;
  mm_session_end_pending = true;
  mm_session_end_success = success;
  CloseAllPositionsForEA();
  if (success)
    Print("Session success: closing all positions.");
  else
    Print("Session failed: closing all positions.");
}

bool CheckHedgeRecoveryClose()
{
  UpdateHedgeModeTracking();
  if (HedgeRecoveryMinutes <= 0 || HedgeRecoveryPercent <= 0.0)
    return false;
  if (hedge_mode_start_time == 0)
    return false;
  int elapsed = (int)(TimeCurrent() - hedge_mode_start_time);
  if (elapsed < HedgeRecoveryMinutes * 60)
    return false;

  double base_equity = hedge_mode_start_equity;
  if (base_equity <= 0.0)
    base_equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double threshold = base_equity * (1.0 - HedgeRecoveryPercent / 100.0);
  if (threshold <= 0.0)
    return false;
  if (equity < threshold)
    return false;

  double equity_ratio = base_equity > 0.0 ? (equity / base_equity) * 100.0 : 0.0;
  PrintFormat("Hedge recovery close triggered: elapsed=%d min equity=%.2f (%.2f%%) base=%.2f equity=%.2f",
              elapsed / 60, threshold, equity_ratio, base_equity, equity);
  bool hedge_buy[NM1::kMaxSymbols];
  bool hedge_sell[NM1::kMaxSymbols];
  for (int i = 0; i < symbols_count; ++i)
  {
    hedge_buy[i] = false;
    hedge_sell[i] = false;
  }
  const int hedge_magic = MagicNumber + HedgeMagicOffset;
  int total = PositionsTotal();
  for (int i = total - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != hedge_magic)
      continue;
    string symbol = PositionGetString(POSITION_SYMBOL);
    int idx = FindSymbolStateIndex(symbol);
    if (idx < 0)
      continue;
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    if (type == POSITION_TYPE_BUY)
      hedge_buy[idx] = true;
    else if (type == POSITION_TYPE_SELL)
      hedge_sell[idx] = true;
  }
  for (int i = 0; i < symbols_count; ++i)
  {
    if (hedge_buy[i])
      CloseBasket(symbols[i], POSITION_TYPE_SELL);
    if (hedge_sell[i])
      CloseBasket(symbols[i], POSITION_TYPE_BUY);
  }
  if (HedgeProfitModeInput == HEDGE_PROFIT_FIXED)
  {
    for (int i = 0; i < symbols_count; ++i)
    {
      if (hedge_buy[i])
        CloseHedgePositions(symbols[i], POSITION_TYPE_BUY);
      if (hedge_sell[i])
        CloseHedgePositions(symbols[i], POSITION_TYPE_SELL);
    }
  }
  hedge_mode_start_time = 0;
  hedge_mode_start_equity = 0.0;
  return true;
}

bool UpdateMoneyManagement()
{
  if (!EnableMoneyManagement)
    return true;

  if (!mm_session_active && !mm_session_end_pending && !mm_session_waiting)
    StartSession();

  if (mm_session_end_pending)
  {
    CloseAllPositionsByMagic(MagicNumber);
    if (!HasAnyPositionByMagic(MagicNumber))
    {
      mm_session_end_pending = false;
      if (mm_session_end_success)
      {
        StartSession();
        return true;
      }
      mm_session_waiting = true;
      mm_session_wait_until = TimeCurrent() + SessionFailureIntervalSeconds;
      PrintFormat("Session cooldown started: %d seconds", SessionFailureIntervalSeconds);
    }
    return false;
  }

  if (mm_session_waiting)
  {
    if (TimeCurrent() >= mm_session_wait_until)
    {
      mm_session_waiting = false;
      StartSession();
      return true;
    }
    return false;
  }

  if (!mm_session_active)
    return false;

  double max_dd = MathMax(SessionMaxDD, 0.0);
  double target_multiplier = MathMax(SessionTargetMultiplier, 0.0);
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double pnl = equity - mm_session_start_equity;

  if (max_dd > 0.0 && equity <= (mm_session_start_equity - max_dd))
  {
    EndSession(false);
    return false;
  }

  if (max_dd > 0.0 && target_multiplier > 0.0)
  {
    double target = max_dd * target_multiplier;
    if (pnl >= target)
    {
      EndSession(true);
      return false;
    }
  }

  return true;
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

    if (ClosePositionWithLog(ticket, "flex"))
    {
      double realized = DealNetProfit(close_trade.ResultDeal());
      int level = ExtractLevelFromComment(comment);
      if (type == POSITION_TYPE_BUY)
      {
        state.realized_buy_profit += realized;
        state.has_partial_buy = true;
        AddFlexRef(state, state.flex_buy_refs, price, volume, level);
      }
      else
      {
        state.realized_sell_profit += realized;
        state.has_partial_sell = true;
        AddFlexRef(state, state.flex_sell_refs, price, volume, level);
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
  double point = state.point;
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
  HedgeInfo hedge;
  CollectHedgeInfo(state, hedge);
  MqlTick t;
  if (!SymbolInfoTick(symbol, t))
    return;
  if ((long)TimeCurrent() - (long)t.time > 2)
    return;
  if (t.bid <= 0.0 || t.ask <= 0.0 || t.ask < t.bid)
    return;
  double bid = t.bid;
  double ask = t.ask;
  if (DebugMode)
  {
    string regime_name = RegimeName(state.regime);
    if (!HasDebugPendingOrder(state, regime_name))
      CancelDebugPendingOrders(state);
    if (HasDebugPendingOrder(state, regime_name))
      return;
    trade.SetExpertMagicNumber(state.params.magic_number);
    trade.SetDeviationInPoints(state.params.slippage_points);
    int filling = state.filling_mode;
    if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
      trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
    double price = 2000.0;
    string comment = StringFormat("NM1_DEBUG_%s", regime_name);
    trade.BuyLimit(0.01, price, state.broker_symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, comment);
  }
  double atr_base = 0.0;
  double atr_now = 0.0;
  double atr_slope = 0.0;
  GetAtrSnapshot(state, atr_base, atr_now, atr_slope);
  bool is_trading_time = IsTradingTime();
  bool new_bar = IsNewBar(state);
  double value_per_unit = PriceValuePerUnitCached(state);
  if (CheckHedgeBasketBreakeven(state, buy, sell, hedge, value_per_unit))
  {
    if (params.hedge_profit_mode == HEDGE_PROFIT_FIXED)
    {
      if (hedge.buy_volume > 0.0)
        CloseHedgePositions(state, POSITION_TYPE_BUY);
      if (hedge.sell_volume > 0.0)
        CloseHedgePositions(state, POSITION_TYPE_SELL);
    }
    else
    {
      ProcessHedgeTrailing(state, hedge, bid, ask, atr_now);
    }
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }
  if (params.hedge_profit_mode == HEDGE_PROFIT_TRAIL)
    ProcessHedgeTrailing(state, hedge, bid, ask, atr_now);
  if (!is_trading_time)
  {
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
  if (ShouldStopOnBuyLimit(state, params.stop_buy_limit_price, params.stop_buy_limit_lot))
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
    state.buy_open_time = 0;
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
    state.sell_open_time = 0;
  }
  if (state.prev_buy_count == 0 && buy.count > 0)
    state.buy_open_time = TimeCurrent();
  if (state.prev_sell_count == 0 && sell.count > 0)
    state.sell_open_time = TimeCurrent();

  if (EnableLonelyL1Close)
  {
    datetime now = TimeCurrent();
    int limit_l1 = LonelyL1CloseMinutes * 60;
    int limit_multi = MultiLevelCloseMinutes * 60;
    if (buy.count > 0 && state.buy_open_time > 0 &&
        buy.level_count <= 1 && limit_l1 > 0 &&
        (now - state.buy_open_time) >= limit_l1)
      CloseBasket(state, POSITION_TYPE_BUY);
    if (sell.count > 0 && state.sell_open_time > 0 &&
        sell.level_count <= 1 && limit_l1 > 0 &&
        (now - state.sell_open_time) >= limit_l1)
      CloseBasket(state, POSITION_TYPE_SELL);
    if (buy.count > 0 && state.buy_open_time > 0 &&
        buy.level_count >= 2 && limit_multi > 0 &&
        (now - state.buy_open_time) >= limit_multi)
      CloseBasket(state, POSITION_TYPE_BUY);
    if (sell.count > 0 && state.sell_open_time > 0 &&
        sell.level_count >= 2 && limit_multi > 0 &&
        (now - state.sell_open_time) >= limit_multi)
      CloseBasket(state, POSITION_TYPE_SELL);
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
  if (params.safety_mode && atr_base > 0.0)
  {
    if (atr_now >= atr_base * params.safe_k)
    {
      safety_triggered = true;
      if (!params.safe_stop_mode)
        allow_nanpin = false;
    }
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
  double adx_now = 0.0;
  double adx_prev = 0.0;
  double di_plus_now = 0.0;
  double di_plus_prev = 0.0;
  double di_minus_now = 0.0;
  double di_minus_prev = 0.0;
  bool has_adx = GetAdxSnapshot(state, adx_now, adx_prev, di_plus_now, di_plus_prev, di_minus_now, di_minus_prev);
  if (has_adx)
    UpdateRegime(state, adx_now, di_plus_now, di_minus_now, new_bar);
  if (allow_nanpin && has_adx)
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
  if (state.regime == REGIME_TREND_UP)
    sell_stop = true;
  else if (state.regime == REGIME_TREND_DOWN)
    buy_stop = true;
  allow_buy_trigger = allow_nanpin && !buy_stop;
  allow_sell_trigger = allow_nanpin && !sell_stop;

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
      double value_per_unit = PriceValuePerUnitCached(state);
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
      double value_per_unit = PriceValuePerUnitCached(state);
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
    ProcessTrendHedge(state, buy, sell);

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
        if (params.strict_nanpin_spacing)
        {
          double base_step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
          int level_index = buy.level_count + state.buy_skip_levels;
          double step = base_step * LevelStepFactor(params, level_index + 1);
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
              level_index = buy.level_count + state.buy_skip_levels;
              step = base_step * LevelStepFactor(params, level_index + 1);
            }
            state.buy_skip_distance = distance;
          }
        }
        else
        {
          if (!state.buy_stop_active)
            state.buy_stop_active = true;
          state.buy_skip_levels = 0;
          state.buy_skip_distance = 0.0;
          state.buy_skip_price = 0.0;
        }
      }
      else
      {
        state.buy_stop_active = false;
        state.buy_skip_price = 0.0;
        if (!params.strict_nanpin_spacing)
          state.buy_skip_levels = 0;
      }
    }
    if (sell.count > 0)
    {
      if (sell_stop)
      {
        if (params.strict_nanpin_spacing)
        {
          double base_step = state.sell_grid_step > 0.0 ? state.sell_grid_step : grid_step;
          int level_index = sell.level_count + state.sell_skip_levels;
          double step = base_step * LevelStepFactor(params, level_index + 1);
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
              level_index = sell.level_count + state.sell_skip_levels;
              step = base_step * LevelStepFactor(params, level_index + 1);
            }
            state.sell_skip_distance = distance;
          }
        }
        else
        {
          if (!state.sell_stop_active)
            state.sell_stop_active = true;
          state.sell_skip_levels = 0;
          state.sell_skip_distance = 0.0;
          state.sell_skip_price = 0.0;
        }
      }
      else
      {
        state.sell_stop_active = false;
        state.sell_skip_price = 0.0;
        if (!params.strict_nanpin_spacing)
          state.sell_skip_levels = 0;
      }
    }

    if (buy.count > 0 && (buy.level_count + state.buy_skip_levels) < levels)
    {
      // Buy orders fill at ask, so compare ask to the grid.
      double step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
      int level_index = buy.level_count + state.buy_skip_levels;
      step *= LevelStepFactor(params, level_index + 1);
      bool apply_min_width = !params.strict_nanpin_spacing || state.buy_skip_levels > 0;
      step = AdjustNanpinStep(state.buy_level_price, level_index, step, apply_min_width);
      double target = 0.0;
      target = EnsureBuyTarget(state, buy, step, level_index);
      double point = state.point;
      if (point <= 0.0)
        point = 0.00001;
      double tol = point * 0.5;
      if (allow_buy_trigger && CanNanpin(params, state.last_buy_nanpin_time) && ask <= target + tol)
      {
        double lot = state.lot_seq[level_index];
        int next_level = level_index + 1;
        if (next_level >= CoreSplitLevel)
        {
          double core_lot = 0.0;
          double flex_lot = 0.0;
          NormalizeCoreFlexLot(state, lot, core_lot, flex_lot);
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
      step *= LevelStepFactor(params, level_index + 1);
      bool apply_min_width = !params.strict_nanpin_spacing || state.sell_skip_levels > 0;
      step = AdjustNanpinStep(state.sell_level_price, level_index, step, apply_min_width);
      double target = 0.0;
      target = EnsureSellTarget(state, sell, step, level_index);
      double point = state.point;
      if (point <= 0.0)
        point = 0.00001;
      double tol = point * 0.5;
      if (allow_sell_trigger && CanNanpin(params, state.last_sell_nanpin_time) && bid >= target - tol)
      {
        double lot = state.lot_seq[level_index];
        int next_level = level_index + 1;
        if (next_level >= CoreSplitLevel)
        {
          double core_lot = 0.0;
          double flex_lot = 0.0;
          NormalizeCoreFlexLot(state, lot, core_lot, flex_lot);
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
  if (CheckHedgeRecoveryClose())
    return;
  if (!UpdateMoneyManagement())
    return;
  for (int i = 0; i < symbols_count; ++i)
    ProcessSymbolTick(symbols[i]);
}

void OnTimer()
{
  OnTick();
}
