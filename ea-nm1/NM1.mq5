#property strict
#property version   "100.160"

#include <Trade/Trade.mqh>

namespace NM1
{
enum { kMaxLevels = 14 };
enum { kMaxSymbols = 6 };
const int kAtrBasePeriod = 14;
const int kLotDigits = 2;
const double kMinLot = 0.01;
const double kMaxLot = 100.0;
const string kFlexComment = "NM1_FLEX";
const string kCoreComment = "NM1_CORE";
}

input group "XAUUSD"
input bool EnableXAUUSD = true;
input string SymbolXAUUSD = "XAUUSD";
input int MagicNumberXAUUSD = 202507;
input int SlippagePointsXAUUSD = 4;
input int StartDelaySecondsXAUUSD = 5;
input int GridStepPointsXAUUSD = 250;
input bool GridStepAutoXAUUSD = true;
input double AtrMultiplierXAUUSD = 1.2;
input bool SafetyModeXAUUSD = true;
input bool SafeStopModeXAUUSD = true;
input double SafeKXAUUSD = 2.0;
input double SafeSlopeKXAUUSD = 0.3;
input double BaseLotXAUUSD = 0.01;
input double ProfitBaseXAUUSD = 1.0;
input double ProfitStepXAUUSD = 0;
input double CoreRatioXAUUSD = 0.7;
input double FlexRatioXAUUSD = 0.3;
input double FlexAtrProfitMultiplierXAUUSD = 0.5;
input int MaxLevelsXAUUSD = 20;
input int RestartDelaySecondsXAUUSD = 1;
input int NanpinSleepSecondsXAUUSD = 10;
input bool UseAsyncCloseXAUUSD = true;
input int CloseRetryCountXAUUSD = 3;
input int CloseRetryDelayMsXAUUSD = 200;
input double StopBuyLimitPriceXAUUSD = 4000.0;
input double StopBuyLimitLotXAUUSD = 0.01;

input group "EURUSD"
input bool EnableEURUSD = true;
input string SymbolEURUSD = "EURUSD";
input int MagicNumberEURUSD = 202507;
input int SlippagePointsEURUSD = 4;
input int StartDelaySecondsEURUSD = 5;
input int GridStepPointsEURUSD = 250;
input bool GridStepAutoEURUSD = true;
input double AtrMultiplierEURUSD = 1.2;
input bool SafetyModeEURUSD = true;
input bool SafeStopModeEURUSD = true;
input double SafeKEURUSD = 2.0;
input double SafeSlopeKEURUSD = 0.3;
input double BaseLotEURUSD = 0.01;
input double ProfitBaseEURUSD = 1.0;
input double ProfitStepEURUSD = 0;
input double CoreRatioEURUSD = 0.7;
input double FlexRatioEURUSD = 0.3;
input double FlexAtrProfitMultiplierEURUSD = 0.5;
input int MaxLevelsEURUSD = 20;
input int RestartDelaySecondsEURUSD = 1;
input int NanpinSleepSecondsEURUSD = 10;
input bool UseAsyncCloseEURUSD = true;
input int CloseRetryCountEURUSD = 3;
input int CloseRetryDelayMsEURUSD = 200;
input double StopBuyLimitPriceEURUSD = 4000.0;
input double StopBuyLimitLotEURUSD = 0.01;

input group "USDJPY"
input bool EnableUSDJPY = true;
input string SymbolUSDJPY = "USDJPY";
input int MagicNumberUSDJPY = 202507;
input int SlippagePointsUSDJPY = 4;
input int StartDelaySecondsUSDJPY = 5;
input int GridStepPointsUSDJPY = 250;
input bool GridStepAutoUSDJPY = true;
input double AtrMultiplierUSDJPY = 1.2;
input bool SafetyModeUSDJPY = true;
input bool SafeStopModeUSDJPY = true;
input double SafeKUSDJPY = 2.0;
input double SafeSlopeKUSDJPY = 0.3;
input double BaseLotUSDJPY = 0.01;
input double ProfitBaseUSDJPY = 1.0;
input double ProfitStepUSDJPY = 0;
input double CoreRatioUSDJPY = 0.7;
input double FlexRatioUSDJPY = 0.3;
input double FlexAtrProfitMultiplierUSDJPY = 0.5;
input int MaxLevelsUSDJPY = 20;
input int RestartDelaySecondsUSDJPY = 1;
input int NanpinSleepSecondsUSDJPY = 10;
input bool UseAsyncCloseUSDJPY = true;
input int CloseRetryCountUSDJPY = 3;
input int CloseRetryDelayMsUSDJPY = 200;
input double StopBuyLimitPriceUSDJPY = 4000.0;
input double StopBuyLimitLotUSDJPY = 0.01;

input group "AUDUSD"
input bool EnableAUDUSD = true;
input string SymbolAUDUSD = "AUDUSD";
input int MagicNumberAUDUSD = 202507;
input int SlippagePointsAUDUSD = 4;
input int StartDelaySecondsAUDUSD = 5;
input int GridStepPointsAUDUSD = 250;
input bool GridStepAutoAUDUSD = true;
input double AtrMultiplierAUDUSD = 1.2;
input bool SafetyModeAUDUSD = true;
input bool SafeStopModeAUDUSD = true;
input double SafeKAUDUSD = 2.0;
input double SafeSlopeKAUDUSD = 0.3;
input double BaseLotAUDUSD = 0.01;
input double ProfitBaseAUDUSD = 1.0;
input double ProfitStepAUDUSD = 0;
input double CoreRatioAUDUSD = 0.7;
input double FlexRatioAUDUSD = 0.3;
input double FlexAtrProfitMultiplierAUDUSD = 0.5;
input int MaxLevelsAUDUSD = 20;
input int RestartDelaySecondsAUDUSD = 1;
input int NanpinSleepSecondsAUDUSD = 10;
input bool UseAsyncCloseAUDUSD = true;
input int CloseRetryCountAUDUSD = 3;
input int CloseRetryDelayMsAUDUSD = 200;
input double StopBuyLimitPriceAUDUSD = 4000.0;
input double StopBuyLimitLotAUDUSD = 0.01;

input group "BTCUSD"
input bool EnableBTCUSD = true;
input string SymbolBTCUSD = "BTCUSD";
input int MagicNumberBTCUSD = 202507;
input int SlippagePointsBTCUSD = 4;
input int StartDelaySecondsBTCUSD = 5;
input int GridStepPointsBTCUSD = 250;
input bool GridStepAutoBTCUSD = true;
input double AtrMultiplierBTCUSD = 1.2;
input bool SafetyModeBTCUSD = true;
input bool SafeStopModeBTCUSD = true;
input double SafeKBTCUSD = 2.0;
input double SafeSlopeKBTCUSD = 0.3;
input double BaseLotBTCUSD = 0.3;
input double ProfitBaseBTCUSD = 4.0;
input double ProfitStepBTCUSD = 0;
input double CoreRatioBTCUSD = 0.7;
input double FlexRatioBTCUSD = 0.3;
input double FlexAtrProfitMultiplierBTCUSD = 0.5;
input int MaxLevelsBTCUSD = 20;
input int RestartDelaySecondsBTCUSD = 1;
input int NanpinSleepSecondsBTCUSD = 10;
input bool UseAsyncCloseBTCUSD = true;
input int CloseRetryCountBTCUSD = 3;
input int CloseRetryDelayMsBTCUSD = 200;
input double StopBuyLimitPriceBTCUSD = 4000.0;
input double StopBuyLimitLotBTCUSD = 0.01;

input group "ETHUSD"
input bool EnableETHUSD = true;
input string SymbolETHUSD = "ETHUSD";
input int MagicNumberETHUSD = 202507;
input int SlippagePointsETHUSD = 4;
input int StartDelaySecondsETHUSD = 5;
input int GridStepPointsETHUSD = 250;
input bool GridStepAutoETHUSD = true;
input double AtrMultiplierETHUSD = 1.2;
input bool SafetyModeETHUSD = true;
input bool SafeStopModeETHUSD = true;
input double SafeKETHUSD = 2.0;
input double SafeSlopeKETHUSD = 0.3;
input double BaseLotETHUSD = 0.1;
input double ProfitBaseETHUSD = 1.0;
input double ProfitStepETHUSD = 0;
input double CoreRatioETHUSD = 0.7;
input double FlexRatioETHUSD = 0.3;
input double FlexAtrProfitMultiplierETHUSD = 0.5;
input int MaxLevelsETHUSD = 20;
input int RestartDelaySecondsETHUSD = 1;
input int NanpinSleepSecondsETHUSD = 10;
input bool UseAsyncCloseETHUSD = true;
input int CloseRetryCountETHUSD = 3;
input int CloseRetryDelayMsETHUSD = 200;
input double StopBuyLimitPriceETHUSD = 4000.0;
input double StopBuyLimitLotETHUSD = 0.01;

struct NM1Params
{
  int magic_number;
  int slippage_points;
  int start_delay_seconds;
  int grid_step_points;
  bool grid_step_auto;
  double atr_multiplier;
  bool safety_mode;
  bool safe_stop_mode;
  double safe_k;
  double safe_slope_k;
  double base_lot;
  double profit_base;
  double profit_step;
  double core_ratio;
  double flex_ratio;
  double flex_atr_profit_multiplier;
  int max_levels;
  int restart_delay_seconds;
  int nanpin_sleep_seconds;
  bool use_async_close;
  int close_retry_count;
  int close_retry_delay_ms;
  double stop_buy_limit_price;
  double stop_buy_limit_lot;
};

struct BasketInfo
{
  int count;
  int level_count;
  double volume;
  double avg_price;
  double min_price;
  double max_price;
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
  datetime last_buy_close_time;
  datetime last_sell_close_time;
  datetime last_buy_nanpin_time;
  datetime last_sell_nanpin_time;
  int prev_buy_count;
  int prev_sell_count;
  int atr_handle;
  bool safety_active;
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
  state.safety_active = false;
  ClearFlexRefs(state.flex_buy_refs);
  ClearFlexRefs(state.flex_sell_refs);
}

void LoadParamsForIndex(int index, NM1Params &params)
{
  if (index == 0)
  {
    params.magic_number = MagicNumberXAUUSD;
    params.slippage_points = SlippagePointsXAUUSD;
    params.start_delay_seconds = StartDelaySecondsXAUUSD;
    params.grid_step_points = GridStepPointsXAUUSD;
    params.grid_step_auto = GridStepAutoXAUUSD;
    params.atr_multiplier = AtrMultiplierXAUUSD;
    params.safety_mode = SafetyModeXAUUSD;
    params.safe_stop_mode = SafeStopModeXAUUSD;
    params.safe_k = SafeKXAUUSD;
    params.safe_slope_k = SafeSlopeKXAUUSD;
    params.base_lot = BaseLotXAUUSD;
    params.profit_base = ProfitBaseXAUUSD;
    params.profit_step = ProfitStepXAUUSD;
    params.core_ratio = CoreRatioXAUUSD;
    params.flex_ratio = FlexRatioXAUUSD;
    params.flex_atr_profit_multiplier = FlexAtrProfitMultiplierXAUUSD;
    params.max_levels = MaxLevelsXAUUSD;
    params.restart_delay_seconds = RestartDelaySecondsXAUUSD;
    params.nanpin_sleep_seconds = NanpinSleepSecondsXAUUSD;
    params.use_async_close = UseAsyncCloseXAUUSD;
    params.close_retry_count = CloseRetryCountXAUUSD;
    params.close_retry_delay_ms = CloseRetryDelayMsXAUUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceXAUUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotXAUUSD;
  }
  else if (index == 1)
  {
    params.magic_number = MagicNumberEURUSD;
    params.slippage_points = SlippagePointsEURUSD;
    params.start_delay_seconds = StartDelaySecondsEURUSD;
    params.grid_step_points = GridStepPointsEURUSD;
    params.grid_step_auto = GridStepAutoEURUSD;
    params.atr_multiplier = AtrMultiplierEURUSD;
    params.safety_mode = SafetyModeEURUSD;
    params.safe_stop_mode = SafeStopModeEURUSD;
    params.safe_k = SafeKEURUSD;
    params.safe_slope_k = SafeSlopeKEURUSD;
    params.base_lot = BaseLotEURUSD;
    params.profit_base = ProfitBaseEURUSD;
    params.profit_step = ProfitStepEURUSD;
    params.core_ratio = CoreRatioEURUSD;
    params.flex_ratio = FlexRatioEURUSD;
    params.flex_atr_profit_multiplier = FlexAtrProfitMultiplierEURUSD;
    params.max_levels = MaxLevelsEURUSD;
    params.restart_delay_seconds = RestartDelaySecondsEURUSD;
    params.nanpin_sleep_seconds = NanpinSleepSecondsEURUSD;
    params.use_async_close = UseAsyncCloseEURUSD;
    params.close_retry_count = CloseRetryCountEURUSD;
    params.close_retry_delay_ms = CloseRetryDelayMsEURUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceEURUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotEURUSD;
  }
  else if (index == 2)
  {
    params.magic_number = MagicNumberUSDJPY;
    params.slippage_points = SlippagePointsUSDJPY;
    params.start_delay_seconds = StartDelaySecondsUSDJPY;
    params.grid_step_points = GridStepPointsUSDJPY;
    params.grid_step_auto = GridStepAutoUSDJPY;
    params.atr_multiplier = AtrMultiplierUSDJPY;
    params.safety_mode = SafetyModeUSDJPY;
    params.safe_stop_mode = SafeStopModeUSDJPY;
    params.safe_k = SafeKUSDJPY;
    params.safe_slope_k = SafeSlopeKUSDJPY;
    params.base_lot = BaseLotUSDJPY;
    params.profit_base = ProfitBaseUSDJPY;
    params.profit_step = ProfitStepUSDJPY;
    params.core_ratio = CoreRatioUSDJPY;
    params.flex_ratio = FlexRatioUSDJPY;
    params.flex_atr_profit_multiplier = FlexAtrProfitMultiplierUSDJPY;
    params.max_levels = MaxLevelsUSDJPY;
    params.restart_delay_seconds = RestartDelaySecondsUSDJPY;
    params.nanpin_sleep_seconds = NanpinSleepSecondsUSDJPY;
    params.use_async_close = UseAsyncCloseUSDJPY;
    params.close_retry_count = CloseRetryCountUSDJPY;
    params.close_retry_delay_ms = CloseRetryDelayMsUSDJPY;
    params.stop_buy_limit_price = StopBuyLimitPriceUSDJPY;
    params.stop_buy_limit_lot = StopBuyLimitLotUSDJPY;
  }
  else if (index == 3)
  {
    params.magic_number = MagicNumberAUDUSD;
    params.slippage_points = SlippagePointsAUDUSD;
    params.start_delay_seconds = StartDelaySecondsAUDUSD;
    params.grid_step_points = GridStepPointsAUDUSD;
    params.grid_step_auto = GridStepAutoAUDUSD;
    params.atr_multiplier = AtrMultiplierAUDUSD;
    params.safety_mode = SafetyModeAUDUSD;
    params.safe_stop_mode = SafeStopModeAUDUSD;
    params.safe_k = SafeKAUDUSD;
    params.safe_slope_k = SafeSlopeKAUDUSD;
    params.base_lot = BaseLotAUDUSD;
    params.profit_base = ProfitBaseAUDUSD;
    params.profit_step = ProfitStepAUDUSD;
    params.core_ratio = CoreRatioAUDUSD;
    params.flex_ratio = FlexRatioAUDUSD;
    params.flex_atr_profit_multiplier = FlexAtrProfitMultiplierAUDUSD;
    params.max_levels = MaxLevelsAUDUSD;
    params.restart_delay_seconds = RestartDelaySecondsAUDUSD;
    params.nanpin_sleep_seconds = NanpinSleepSecondsAUDUSD;
    params.use_async_close = UseAsyncCloseAUDUSD;
    params.close_retry_count = CloseRetryCountAUDUSD;
    params.close_retry_delay_ms = CloseRetryDelayMsAUDUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceAUDUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotAUDUSD;
  }
  else if (index == 4)
  {
    params.magic_number = MagicNumberBTCUSD;
    params.slippage_points = SlippagePointsBTCUSD;
    params.start_delay_seconds = StartDelaySecondsBTCUSD;
    params.grid_step_points = GridStepPointsBTCUSD;
    params.grid_step_auto = GridStepAutoBTCUSD;
    params.atr_multiplier = AtrMultiplierBTCUSD;
    params.safety_mode = SafetyModeBTCUSD;
    params.safe_stop_mode = SafeStopModeBTCUSD;
    params.safe_k = SafeKBTCUSD;
    params.safe_slope_k = SafeSlopeKBTCUSD;
    params.base_lot = BaseLotBTCUSD;
    params.profit_base = ProfitBaseBTCUSD;
    params.profit_step = ProfitStepBTCUSD;
    params.core_ratio = CoreRatioBTCUSD;
    params.flex_ratio = FlexRatioBTCUSD;
    params.flex_atr_profit_multiplier = FlexAtrProfitMultiplierBTCUSD;
    params.max_levels = MaxLevelsBTCUSD;
    params.restart_delay_seconds = RestartDelaySecondsBTCUSD;
    params.nanpin_sleep_seconds = NanpinSleepSecondsBTCUSD;
    params.use_async_close = UseAsyncCloseBTCUSD;
    params.close_retry_count = CloseRetryCountBTCUSD;
    params.close_retry_delay_ms = CloseRetryDelayMsBTCUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceBTCUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotBTCUSD;
  }
  else if (index == 5)
  {
    params.magic_number = MagicNumberETHUSD;
    params.slippage_points = SlippagePointsETHUSD;
    params.start_delay_seconds = StartDelaySecondsETHUSD;
    params.grid_step_points = GridStepPointsETHUSD;
    params.grid_step_auto = GridStepAutoETHUSD;
    params.atr_multiplier = AtrMultiplierETHUSD;
    params.safety_mode = SafetyModeETHUSD;
    params.safe_stop_mode = SafeStopModeETHUSD;
    params.safe_k = SafeKETHUSD;
    params.safe_slope_k = SafeSlopeKETHUSD;
    params.base_lot = BaseLotETHUSD;
    params.profit_base = ProfitBaseETHUSD;
    params.profit_step = ProfitStepETHUSD;
    params.core_ratio = CoreRatioETHUSD;
    params.flex_ratio = FlexRatioETHUSD;
    params.flex_atr_profit_multiplier = FlexAtrProfitMultiplierETHUSD;
    params.max_levels = MaxLevelsETHUSD;
    params.restart_delay_seconds = RestartDelaySecondsETHUSD;
    params.nanpin_sleep_seconds = NanpinSleepSecondsETHUSD;
    params.use_async_close = UseAsyncCloseETHUSD;
    params.close_retry_count = CloseRetryCountETHUSD;
    params.close_retry_delay_ms = CloseRetryDelayMsETHUSD;
    params.stop_buy_limit_price = StopBuyLimitPriceETHUSD;
    params.stop_buy_limit_lot = StopBuyLimitLotETHUSD;
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
  return true;
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
  if (levels > 1)
    state.lot_seq[1] = params.base_lot;
  for (int i = 2; i < levels; ++i)
  {
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
    active++;
  }
  if (active == 0)
    return INIT_FAILED;
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  for (int i = 0; i < symbols_count; ++i)
  {
    if (symbols[i].atr_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].atr_handle);
    symbols[i].atr_handle = INVALID_HANDLE;
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

void CollectBasketInfo(const SymbolState &state, BasketInfo &buy, BasketInfo &sell)
{
  const string symbol = state.broker_symbol;
  buy.count = 0;
  buy.level_count = 0;
  buy.volume = 0.0;
  buy.avg_price = 0.0;
  buy.min_price = 0.0;
  buy.max_price = 0.0;
  sell.count = 0;
  sell.level_count = 0;
  sell.volume = 0.0;
  sell.avg_price = 0.0;
  sell.min_price = 0.0;
  sell.max_price = 0.0;

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
    }
  }

  if (buy.volume > 0.0)
    buy.avg_price = buy_value / buy.volume;
  if (sell.volume > 0.0)
    sell.avg_price = sell_value / sell.volume;
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

double ProfitOffsetByCount(const NM1Params &params, int count)
{
  if (count <= 2)
    return params.profit_base;
  return params.profit_base + (count - 2) * params.profit_step;
}

double PipPointSize(const string symbol)
{
  int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (digits == 3 || digits == 5)
    return point * 10.0;
  return point;
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
      int level = ExtractLevelFromComment(comment);
      if (type == POSITION_TYPE_BUY)
        AddFlexRef(symbol, state.flex_buy_refs, price, volume, level);
      else
        AddFlexRef(symbol, state.flex_sell_refs, price, volume, level);
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
    ClearFlexRefs(state.flex_buy_refs);
  }
  if (state.prev_sell_count > 0 && sell.count == 0)
  {
    state.last_sell_close_time = TimeCurrent();
    state.last_sell_nanpin_time = 0;
    ClearFlexRefs(state.flex_sell_refs);
  }

  bool attempted_initial = false;
  if (!state.initial_started && (TimeCurrent() - state.start_time) >= params.start_delay_seconds)
  {
    if (buy.count == 0 && sell.count == 0 && IsTradingTime())
    {
      bool opened = false;
      opened |= TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
      opened |= TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
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

  double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
  double grid_step = params.grid_step_points * PipPointSize(symbol);
  double atr_base = 0.0;
  if (params.grid_step_auto)
  {
    atr_base = GetAtrBase(state);
    if (atr_base > 0.0)
      grid_step = atr_base * params.atr_multiplier;
  }
  else if (params.safety_mode)
  {
    atr_base = GetAtrBase(state);
  }

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

  if (atr_now <= 0.0)
    atr_now = GetCurrentAtr(state);
  ProcessFlexPartial(state, symbol, bid, ask, atr_now);

  if (buy.count > 0)
  {
    double target = buy.avg_price + ProfitOffsetByCount(params, buy.level_count);
    if (bid >= target)
      CloseBasket(state, POSITION_TYPE_BUY);
  }

  if (sell.count > 0)
  {
    double target = sell.avg_price - ProfitOffsetByCount(params, sell.level_count);
    if (ask <= target)
      CloseBasket(state, POSITION_TYPE_SELL);
  }

  if (IsTradingTime())
  {
    if (state.initial_started)
    {
      if (buy.count == 0 && CanRestart(params, state.last_buy_close_time))
        TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
      if (sell.count == 0 && CanRestart(params, state.last_sell_close_time))
        TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM1::kCoreComment, 1));
    }

    int levels = EffectiveMaxLevels(params);
    if (buy.count > 0 && buy.level_count < levels)
    {
      // Buy orders fill at ask, so compare ask to the grid.
      if (allow_nanpin && CanNanpin(params, state.last_buy_nanpin_time) && ask <= buy.min_price - grid_step)
      {
        double lot = state.lot_seq[buy.level_count];
        if (buy.level_count >= 3)
        {
          double core_lot = 0.0;
          double flex_lot = 0.0;
          NormalizeCoreFlexLot(params, symbol, lot, core_lot, flex_lot);
          bool opened = false;
          int level = buy.level_count + 1;
          if (core_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_BUY, core_lot, MakeLevelComment(NM1::kCoreComment, level));
          if (flex_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_BUY, flex_lot, MakeLevelComment(NM1::kFlexComment, level));
          if (opened)
            state.last_buy_nanpin_time = TimeCurrent();
        }
        else
        {
          int level = buy.level_count + 1;
          if (TryOpen(state, symbol, ORDER_TYPE_BUY, lot, MakeLevelComment(NM1::kCoreComment, level)))
            state.last_buy_nanpin_time = TimeCurrent();
        }
      }
    }

    if (sell.count > 0 && sell.level_count < levels)
    {
      // Sell orders fill at bid, so compare bid to the grid.
      if (allow_nanpin && CanNanpin(params, state.last_sell_nanpin_time) && bid >= sell.max_price + grid_step)
      {
        double lot = state.lot_seq[sell.level_count];
        if (sell.level_count >= 3)
        {
          double core_lot = 0.0;
          double flex_lot = 0.0;
          NormalizeCoreFlexLot(params, symbol, lot, core_lot, flex_lot);
          bool opened = false;
          int level = sell.level_count + 1;
          if (core_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_SELL, core_lot, MakeLevelComment(NM1::kCoreComment, level));
          if (flex_lot > 0.0)
            opened |= TryOpen(state, symbol, ORDER_TYPE_SELL, flex_lot, MakeLevelComment(NM1::kFlexComment, level));
          if (opened)
            state.last_sell_nanpin_time = TimeCurrent();
        }
        else
        {
          int level = sell.level_count + 1;
          if (TryOpen(state, symbol, ORDER_TYPE_SELL, lot, MakeLevelComment(NM1::kCoreComment, level)))
            state.last_sell_nanpin_time = TimeCurrent();
        }
      }
    }

    if (allow_nanpin)
    {
      if (buy.count > 0)
        ProcessFlexRefill(state, symbol, ORDER_TYPE_BUY, state.flex_buy_refs, ask);
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
