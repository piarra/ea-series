#property strict
#property version   "0.1"

// NM3 v0.1

#include <Trade/Trade.mqh>

namespace NM3
{
enum { kMaxLevels = 20 };
enum { kMaxSymbols = 1 };
enum { kMaxTrackedBaskets = 64 };
const double kAdxH1HardStopThreshold = 24.0;
const int kLotDigits = 2;
const double kMinLot = 0.01;
const double kMaxLot = 100.0;
const string kCoreComment = "NM3_CORE";
const int kLevelCap = 8;
const int kRecentCloseRequestCap = 256;
const ulong kRecentCloseRequestTtlMs = 3000;
const int kClosedTicketCountCap = 4096;
const int kRunnerTrailStateCap = 512;
const double kDeepLevelTrailLockPoints = 2.0;
const double kDeepRunnerRevisitCloseBandRatio = 0.20;
const int kTimedExitMinutes = 15;
}

enum RegimeState
{
  REGIME_NORMAL = 0,
  REGIME_TREND_UP,
  REGIME_TREND_DOWN,
  REGIME_COOLING
};

enum MartingaleMode
{
  MARTINGALE_FIBONACCI = 0,
  MARTINGALE_PROPORTIONAL = 1
};

input group "COMMON"
input string SymbolSuffix = "c";
input int MagicNumber = 202602;
input int SlippagePoints = 10;
input int StartDelaySeconds = 5;
input int CloseRetryCount = 3;
input int CloseRetryDelayMs = 200;
input int TrailSLModifyMinIntervalMs = 600;
input int TrailSLRateLimitCooldownMs = 2000;
input int RestartDelaySeconds = 20;
input int NanpinSleepSeconds = 10;
input int OrderPendingTimeoutSeconds = 2;
input bool EnableHedgedEntry = true;
input bool CloseAllOnTradingStopStart = false;
input bool EnableTrailingTakeProfit = true;
input bool EnableAdxH1HardStop = true;
input bool EnableAdxH1RisingHardStop = true;
input double AdxMaxForNanpin = 20.0;
input double DiGapMin = 2.0;

input group "NEWS FILTER"
input bool EnableNewsFilter = true;
input int NewsMinutesBefore = 5;
input int NewsMinutesAfter = 30;
input bool NewsOnlyHighImpact = true;
input string NewsBacktestCalendarFile = "economic_calendar_2025_2030.csv"; // MQL_TESTER時はFILE_COMMONから参照

input group "TAKE PROFIT"
input bool UseTakeProfitTrailSL = false;
input bool EnableDeepRunnerRevisitTakeProfit = true;
input bool EnableFixedTrailStart = true;
input double FixedTrailStartPointsXAUUSD = 2500.0;
input bool EnableTakeProfitTrailDistanceCap = true;
input double FixedTrailDistanceCapRatio = 0.24;

input group "RISK CONTROL"
input bool EnableBalanceGuard = false;
input double MinAccountBalance = 0.0;
input bool ClosePositionsOnLowBalance = false;
input bool EnableBasketLossStop = true;
input double BasketLossStopPointsLevel1 = 20000.0;
input double BasketLossStopPointsLevel2 = 28000.0;
input double BasketLossStopPointsLevel3 = 33000.0;
input double BasketLossStopPointsLevel4 = 36000.0;
input double BasketLossStopPointsLevel5 = 40000.0;
input double BasketLossStopNanpinWidthMultiplierLevel1 = 6.0;
input double BasketLossStopNanpinWidthMultiplierLevel2Plus = 6.0;
input int CombinedProfitCloseLevel = 3;
input double CombinedProfitCloseNanpinWidthMultiplier = 3.80;

input group "MANAGEMENT SERVER"
input string ManagementServerHost = "";
input string ManagementServerUser = "demo1";
input string ManagementServerApiKey = "";
input string LogServerHost = "ea-logserver.an-hc.workers.dev";

input group "REGIME FILTER"
input int RegimeOnBars = 2;
input int RegimeOffBars = 3;
input int RegimeCoolingBars = 3;
input double RegimeDiGapOn = 2.0;
input double RegimeDiGapOff = 2.0;
input double TrendLotMultiplier = 2.0;

input group "DEBUG"
input bool DebugMode = false;

input group "XAUUSD"
input bool EnableXAUUSD = true;
input string SymbolXAUUSD = "XAUUSD";
input double BaseLotXAUUSD = 0.01;
input double FixedNanpinWidthPointsXAUUSD = 2500.0;
input double TakeProfitPointsXAUUSD = 1400.0;
input double TrailingTakeProfitDistanceRatioXAUUSD = 0.40;
input int AdxPeriodXAUUSD = 14;
input double RegimeAdxOnXAUUSD = 40.0;
input double RegimeAdxOffXAUUSD = 25.0;
input double MaxSpreadPointsXAUUSD = 320.0;
input int MaxLevelsXAUUSD = 4;
input MartingaleMode MartingaleModeXAUUSD = MARTINGALE_FIBONACCI;
input double ProportionalMartingaleMultiplierXAUUSD = 1.5;
input bool DoubleSecondLotXAUUSD = true;

struct NM3Params
{
  int magic_number;
  int slippage_points;
  int start_delay_seconds;
  double base_lot;
  double fixed_nanpin_width_points;
  double take_profit_points;
  bool trailing_take_profit;
  bool use_take_profit_trail_sl;
  bool enable_deep_runner_revisit_take_profit;
  bool enable_adx_h1_hard_stop;
  bool enable_adx_h1_rising_hard_stop;
  double trailing_take_profit_distance_ratio;
  int adx_period;
  double adx_max_for_nanpin;
  double di_gap_min;
  double max_spread_points;
  int regime_on_bars;
  int regime_off_bars;
  int regime_cooling_bars;
  double regime_adx_on;
  double regime_di_gap_on;
  double regime_adx_off;
  double regime_di_gap_off;
  double trend_lot_multiplier;
  int max_levels;
  int restart_delay_seconds;
  int nanpin_sleep_seconds;
  int order_pending_timeout_seconds;
  bool enable_hedged_entry;
  bool close_all_on_trading_stop_start;
  MartingaleMode martingale_mode;
  double proportional_martingale_multiplier;
  bool double_second_lot;
  int close_retry_count;
  int close_retry_delay_ms;
  int trail_sl_modify_min_interval_ms;
  int trail_sl_rate_limit_cooldown_ms;
  bool enable_balance_guard;
  double min_account_balance;
  bool close_positions_on_low_balance;
  bool enable_basket_loss_stop;
  double basket_loss_stop_points_level1;
  double basket_loss_stop_points_level2;
  double basket_loss_stop_points_level3;
  double basket_loss_stop_points_level4;
  double basket_loss_stop_points_level5;
  double basket_loss_stop_nanpin_width_multiplier_level1;
  double basket_loss_stop_nanpin_width_multiplier_level2_plus;
  int combined_profit_close_level;
  double combined_profit_close_nanpin_width_multiplier;
};

struct BasketInfo
{
  int basket_id;
  int count;
  int level_count;
  int deepest_level;
  ulong deepest_ticket;
  double volume;
  double avg_price;
  double min_price;
  double max_price;
  double profit;
};

CTrade trade;
CTrade close_trade;

double cumulative_trade_lots = 0.0;
datetime cumulative_lot_start_time = 0;
ulong recent_close_request_tickets[];
ulong recent_close_request_times_ms[];
ulong counted_closed_tickets[];
ulong runner_trail_tickets[];
int runner_trail_types[];
double runner_trail_stops[];
ulong runner_revisit_tickets[];
int runner_revisit_types[];
double runner_revisit_rebound_prices[];
double runner_revisit_deep_prices[];
bool runner_revisit_rebound_touched[];
datetime news_last_checked_server_time = 0;
bool news_last_check_blocked = false;
ulong news_last_event_id = 0;
datetime news_last_event_time = 0;
ulong news_last_logged_event_id = 0;
datetime news_last_logged_event_time = 0;
int news_last_calendar_error = 0;
datetime news_backtest_all_event_times[];
datetime news_backtest_high_event_times[];
bool news_backtest_calendar_loaded = false;
bool news_backtest_calendar_ready = false;
bool trading_time_state_initialized = false;
bool trading_time_state_prev = true;

struct SymbolState
{
  string logical_symbol;
  string broker_symbol;
  bool enabled;
  NM3Params params;
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
  int next_basket_id;
  int buy_active_basket_id;
  int sell_active_basket_id;
  bool buy_close_as_completed;
  bool sell_close_as_completed;
  int buy_completed_basket_count;
  int sell_completed_basket_count;
  int buy_completed_basket_ids[NM3::kMaxTrackedBaskets];
  int sell_completed_basket_ids[NM3::kMaxTrackedBaskets];
  double lot_seq[NM3::kMaxLevels];
  double buy_level_price[NM3::kMaxLevels];
  double sell_level_price[NM3::kMaxLevels];
  double buy_grid_step;
  double sell_grid_step;
  datetime last_buy_close_time;
  datetime last_sell_close_time;
  datetime last_buy_nanpin_time;
  datetime last_sell_nanpin_time;
  datetime buy_open_time;
  datetime sell_open_time;
  datetime buy_deepest_entry_time;
  datetime sell_deepest_entry_time;
  bool buy_order_pending;
  bool sell_order_pending;
  datetime buy_order_pending_time;
  datetime sell_order_pending_time;
  datetime buy_basket_add_blocked_log_time;
  datetime sell_basket_add_blocked_log_time;
  int last_debug_regime;
  int prev_buy_count;
  int prev_sell_count;
  int adx_handle;
  int adx_m15_handle;
  int adx_h1_handle;
  int adx_h4_handle;
  bool adx_h1_hard_stop_active;
  bool low_balance_active;
  bool buy_take_profit_trailing_active;
  bool sell_take_profit_trailing_active;
  double buy_take_profit_peak_price;
  double sell_take_profit_bottom_price;
  ulong buy_trail_sl_last_send_ms;
  ulong sell_trail_sl_last_send_ms;
  ulong buy_trail_sl_cooldown_until_ms;
  ulong sell_trail_sl_cooldown_until_ms;
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
  datetime last_regime_bar_time;
};

SymbolState symbols[NM3::kMaxSymbols];
int symbols_count = 0;

int BasketIdFromComment(const string comment);
double TakeProfitTrailDistanceCapped(const SymbolState &state, double take_profit_distance);

bool IsManagedMagic(const int magic)
{
  if (magic == MagicNumber)
    return true;
  return false;
}

void ClearRunnerTrailTracking()
{
  ArrayResize(runner_trail_tickets, 0);
  ArrayResize(runner_trail_types, 0);
  ArrayResize(runner_trail_stops, 0);
  ArrayResize(runner_revisit_tickets, 0);
  ArrayResize(runner_revisit_types, 0);
  ArrayResize(runner_revisit_rebound_prices, 0);
  ArrayResize(runner_revisit_deep_prices, 0);
  ArrayResize(runner_revisit_rebound_touched, 0);
}

void ClearCloseTracking()
{
  ArrayResize(recent_close_request_tickets, 0);
  ArrayResize(recent_close_request_times_ms, 0);
  ArrayResize(counted_closed_tickets, 0);
}

int FindTicketIndex(const ulong &tickets[], const ulong ticket)
{
  int count = ArraySize(tickets);
  for (int i = 0; i < count; ++i)
  {
    if (tickets[i] == ticket)
      return i;
  }
  return -1;
}

void CleanupRecentCloseRequests(const ulong now_ms)
{
  int count = ArraySize(recent_close_request_tickets);
  if (count <= 0)
    return;
  int write_index = 0;
  for (int i = 0; i < count; ++i)
  {
    ulong sent_ms = recent_close_request_times_ms[i];
    ulong elapsed_ms = (now_ms >= sent_ms) ? (now_ms - sent_ms) : 0;
    if (elapsed_ms > NM3::kRecentCloseRequestTtlMs)
      continue;
    if (write_index != i)
    {
      recent_close_request_tickets[write_index] = recent_close_request_tickets[i];
      recent_close_request_times_ms[write_index] = recent_close_request_times_ms[i];
    }
    write_index++;
  }
  if (write_index < count)
  {
    ArrayResize(recent_close_request_tickets, write_index);
    ArrayResize(recent_close_request_times_ms, write_index);
  }
}

bool IsRecentCloseRequestPending(const ulong ticket, const ulong now_ms)
{
  CleanupRecentCloseRequests(now_ms);
  int idx = FindTicketIndex(recent_close_request_tickets, ticket);
  if (idx < 0)
    return false;
  ulong sent_ms = recent_close_request_times_ms[idx];
  ulong elapsed_ms = (now_ms >= sent_ms) ? (now_ms - sent_ms) : 0;
  return elapsed_ms <= NM3::kRecentCloseRequestTtlMs;
}

void MarkRecentCloseRequest(const ulong ticket, const ulong now_ms)
{
  int idx = FindTicketIndex(recent_close_request_tickets, ticket);
  if (idx >= 0)
  {
    recent_close_request_times_ms[idx] = now_ms;
    return;
  }
  int count = ArraySize(recent_close_request_tickets);
  if (count >= NM3::kRecentCloseRequestCap)
  {
    for (int i = 1; i < count; ++i)
    {
      recent_close_request_tickets[i - 1] = recent_close_request_tickets[i];
      recent_close_request_times_ms[i - 1] = recent_close_request_times_ms[i];
    }
    count--;
    ArrayResize(recent_close_request_tickets, count);
    ArrayResize(recent_close_request_times_ms, count);
  }
  ArrayResize(recent_close_request_tickets, count + 1);
  ArrayResize(recent_close_request_times_ms, count + 1);
  recent_close_request_tickets[count] = ticket;
  recent_close_request_times_ms[count] = now_ms;
}

bool IsTicketAlreadyCounted(const ulong ticket)
{
  return (FindTicketIndex(counted_closed_tickets, ticket) >= 0);
}

void MarkTicketCounted(const ulong ticket)
{
  if (IsTicketAlreadyCounted(ticket))
    return;
  int count = ArraySize(counted_closed_tickets);
  if (count >= NM3::kClosedTicketCountCap)
  {
    for (int i = 1; i < count; ++i)
      counted_closed_tickets[i - 1] = counted_closed_tickets[i];
    count--;
    ArrayResize(counted_closed_tickets, count);
  }
  ArrayResize(counted_closed_tickets, count + 1);
  counted_closed_tickets[count] = ticket;
}

void InitCumulativeLotTracking()
{
  cumulative_trade_lots = 0.0;
  cumulative_lot_start_time = TimeCurrent();
  ClearCloseTracking();
  ClearRunnerTrailTracking();
}

bool ClosePositionWithLog(const ulong ticket, const string context)
{
  ulong now_ms = GetTickCount();
  if (IsRecentCloseRequestPending(ticket, now_ms))
    return true;
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
  if (closed)
    MarkRecentCloseRequest(ticket, now_ms);
  if (closed && has_info && IsManagedMagic(magic) && volume > 0.0)
  {
    if (!IsTicketAlreadyCounted(ticket))
    {
      cumulative_trade_lots += volume;
      MarkTicketCounted(ticket);
      if (StringLen(context) > 0)
      {
        PrintFormat("Position closed: ticket=%I64u symbol=%s lots=%.2f total=%.2f (%s)",
                    ticket, symbol, volume, cumulative_trade_lots, context);
      }
      else
      {
        PrintFormat("Position closed: ticket=%I64u symbol=%s lots=%.2f total=%.2f",
                    ticket, symbol, volume, cumulative_trade_lots);
      }
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
    string expected = StringFormat("NM3_DEBUG_%s", regime_name);
    if (comment == expected)
      return true;
  }
  return false;
}

bool HasAnyDebugPendingOrder(const SymbolState &state)
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
    if (StringFind(comment, "NM3_DEBUG_") == 0)
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
    if (StringFind(comment, "NM3_DEBUG_") != 0)
      continue;
    trade.OrderDelete(ticket);
  }
}

void DebugLog(SymbolState &state, const string message)
{
  if (!DebugMode)
    return;
  if (HasAnyDebugPendingOrder(state))
    CancelDebugPendingOrders(state);
  trade.SetExpertMagicNumber(state.params.magic_number);
  trade.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  double price = 2000.0;
  string comment = StringFormat("NM3_DEBUG_%s", message);
  if (StringLen(comment) > 60)
    comment = StringSubstr(comment, 0, 60);
  trade.BuyLimit(0.01, price, state.broker_symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, comment);
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
  if (state.adx_handle != INVALID_HANDLE)
    IndicatorRelease(state.adx_handle);
  state.adx_handle = INVALID_HANDLE;
  if (state.adx_m15_handle != INVALID_HANDLE)
    IndicatorRelease(state.adx_m15_handle);
  state.adx_m15_handle = INVALID_HANDLE;
  if (state.adx_h1_handle != INVALID_HANDLE)
    IndicatorRelease(state.adx_h1_handle);
  state.adx_h1_handle = INVALID_HANDLE;
  if (state.adx_h4_handle != INVALID_HANDLE)
    IndicatorRelease(state.adx_h4_handle);
  state.adx_h4_handle = INVALID_HANDLE;
  if (StringLen(reason) > 0)
    PrintFormat("Symbol disabled: %s (%s)", state.broker_symbol, reason);
}

void InitSymbolState(SymbolState &state, const string logical, const string broker, bool enabled, const NM3Params &params)
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
  state.next_basket_id = 1;
  state.buy_active_basket_id = 0;
  state.sell_active_basket_id = 0;
  state.buy_close_as_completed = false;
  state.sell_close_as_completed = false;
  state.buy_completed_basket_count = 0;
  state.sell_completed_basket_count = 0;
  for (int i = 0; i < NM3::kMaxTrackedBaskets; ++i)
  {
    state.buy_completed_basket_ids[i] = 0;
    state.sell_completed_basket_ids[i] = 0;
  }
  state.last_buy_close_time = 0;
  state.last_sell_close_time = 0;
  state.last_buy_nanpin_time = 0;
  state.last_sell_nanpin_time = 0;
  state.buy_open_time = 0;
  state.sell_open_time = 0;
  state.buy_deepest_entry_time = 0;
  state.sell_deepest_entry_time = 0;
  state.buy_order_pending = false;
  state.sell_order_pending = false;
  state.buy_order_pending_time = 0;
  state.sell_order_pending_time = 0;
  state.buy_basket_add_blocked_log_time = 0;
  state.sell_basket_add_blocked_log_time = 0;
  state.last_debug_regime = -1;
  state.prev_buy_count = 0;
  state.prev_sell_count = 0;
  state.adx_handle = INVALID_HANDLE;
  state.adx_m15_handle = INVALID_HANDLE;
  state.adx_h1_handle = INVALID_HANDLE;
  state.adx_h4_handle = INVALID_HANDLE;
  state.adx_h1_hard_stop_active = false;
  state.low_balance_active = false;
  state.buy_take_profit_trailing_active = false;
  state.sell_take_profit_trailing_active = false;
  state.buy_take_profit_peak_price = 0.0;
  state.sell_take_profit_bottom_price = 0.0;
  state.buy_trail_sl_last_send_ms = 0;
  state.sell_trail_sl_last_send_ms = 0;
  state.buy_trail_sl_cooldown_until_ms = 0;
  state.sell_trail_sl_cooldown_until_ms = 0;
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
  state.last_regime_bar_time = 0;
  ClearLevelPrices(state.buy_level_price);
  ClearLevelPrices(state.sell_level_price);
  state.buy_grid_step = 0.0;
  state.sell_grid_step = 0.0;
}

void RefreshSymbolInfo(SymbolState &state)
{
  const string symbol = state.broker_symbol;
  state.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (AccountInfoString(ACCOUNT_COMPANY) == "Titan FX Limited" && state.logical_symbol == "XAUUSD")
    state.point *= 0.1;
  state.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  state.volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
  state.volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
  state.volume_max = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
  state.tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
  state.tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  state.filling_mode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
  state.symbol_info_ready = true;
}

void ApplyCommonParams(NM3Params &params)
{
  params.magic_number = MagicNumber;
  params.slippage_points = SlippagePoints;
  params.start_delay_seconds = StartDelaySeconds;
  params.adx_max_for_nanpin = AdxMaxForNanpin;
  params.di_gap_min = DiGapMin;
  params.regime_on_bars = RegimeOnBars;
  params.regime_off_bars = RegimeOffBars;
  params.regime_cooling_bars = RegimeCoolingBars;
  params.regime_di_gap_on = RegimeDiGapOn;
  params.regime_di_gap_off = RegimeDiGapOff;
  params.trend_lot_multiplier = TrendLotMultiplier;
  params.restart_delay_seconds = RestartDelaySeconds;
  params.nanpin_sleep_seconds = NanpinSleepSeconds;
  params.order_pending_timeout_seconds = OrderPendingTimeoutSeconds;
  params.enable_hedged_entry = EnableHedgedEntry;
  params.close_all_on_trading_stop_start = CloseAllOnTradingStopStart;
  params.trailing_take_profit = EnableTrailingTakeProfit;
  params.use_take_profit_trail_sl = UseTakeProfitTrailSL;
  params.enable_deep_runner_revisit_take_profit = EnableDeepRunnerRevisitTakeProfit;
  params.enable_adx_h1_hard_stop = EnableAdxH1HardStop;
  params.enable_adx_h1_rising_hard_stop = EnableAdxH1RisingHardStop;
  params.base_lot = 0.01;
  params.fixed_nanpin_width_points = 2500.0;
  params.take_profit_points = 120.0;
  params.trailing_take_profit_distance_ratio = 0.55;
  params.adx_period = 14;
  params.regime_adx_on = 40.0;
  params.regime_adx_off = 25.0;
  params.max_spread_points = 320.0;
  params.max_levels = 4;
  params.martingale_mode = MARTINGALE_FIBONACCI;
  params.proportional_martingale_multiplier = 1.5;
  params.double_second_lot = false;
  params.close_retry_count = CloseRetryCount;
  params.close_retry_delay_ms = CloseRetryDelayMs;
  params.trail_sl_modify_min_interval_ms = TrailSLModifyMinIntervalMs;
  params.trail_sl_rate_limit_cooldown_ms = TrailSLRateLimitCooldownMs;
  params.enable_balance_guard = EnableBalanceGuard;
  params.min_account_balance = MinAccountBalance;
  params.close_positions_on_low_balance = ClosePositionsOnLowBalance;
  params.enable_basket_loss_stop = EnableBasketLossStop;
  params.basket_loss_stop_points_level1 = BasketLossStopPointsLevel1;
  params.basket_loss_stop_points_level2 = BasketLossStopPointsLevel2;
  params.basket_loss_stop_points_level3 = BasketLossStopPointsLevel3;
  params.basket_loss_stop_points_level4 = BasketLossStopPointsLevel4;
  params.basket_loss_stop_points_level5 = BasketLossStopPointsLevel5;
  params.basket_loss_stop_nanpin_width_multiplier_level1 = BasketLossStopNanpinWidthMultiplierLevel1;
  params.basket_loss_stop_nanpin_width_multiplier_level2_plus = BasketLossStopNanpinWidthMultiplierLevel2Plus;
  params.combined_profit_close_level = CombinedProfitCloseLevel;
  params.combined_profit_close_nanpin_width_multiplier = CombinedProfitCloseNanpinWidthMultiplier;
}

void LoadParamsForIndex(int index, NM3Params &params)
{
  ApplyCommonParams(params);
  if (index != 0)
    return;
  params.take_profit_points = TakeProfitPointsXAUUSD;
  params.trailing_take_profit_distance_ratio = TrailingTakeProfitDistanceRatioXAUUSD;
  params.adx_period = AdxPeriodXAUUSD;
  params.regime_adx_on = RegimeAdxOnXAUUSD;
  params.regime_adx_off = RegimeAdxOffXAUUSD;
  params.max_spread_points = MaxSpreadPointsXAUUSD;
  params.base_lot = BaseLotXAUUSD;
  params.max_levels = MaxLevelsXAUUSD;
  params.fixed_nanpin_width_points = FixedNanpinWidthPointsXAUUSD;
  params.martingale_mode = MartingaleModeXAUUSD;
  params.proportional_martingale_multiplier = ProportionalMartingaleMultiplierXAUUSD;
  params.double_second_lot = DoubleSecondLotXAUUSD;
}

void BuildSymbols()
{
  symbols_count = 0;
  NM3Params params;
  LoadParamsForIndex(0, params);
  string logical = "XAUUSD";
  bool enabled = EnableXAUUSD;
  string broker_symbol = SymbolXAUUSD;
  if (StringLen(broker_symbol) == 0)
    broker_symbol = logical;
  if (StringLen(SymbolSuffix) > 0)
    broker_symbol += SymbolSuffix;
  if (enabled && !SymbolSelect(broker_symbol, true))
  {
    PrintFormat("Symbol unavailable: %s", broker_symbol);
    enabled = false;
  }
  InitSymbolState(symbols[0], logical, broker_symbol, enabled, params);
  if (enabled)
  {
    RefreshSymbolInfo(symbols[0]);
    symbols_count = 1;
  }

  if (symbols_count == 0)
    Print("No enabled symbols available. Check XAUUSD inputs.");
}

void ResetNewsFilterCache()
{
  news_last_checked_server_time = 0;
  news_last_check_blocked = false;
  news_last_event_id = 0;
  news_last_event_time = 0;
  news_last_logged_event_id = 0;
  news_last_logged_event_time = 0;
  news_last_calendar_error = 0;
  ArrayResize(news_backtest_all_event_times, 0);
  ArrayResize(news_backtest_high_event_times, 0);
  news_backtest_calendar_loaded = false;
  news_backtest_calendar_ready = false;
}

int LowerBoundEventTime(const datetime &events[], datetime target)
{
  int left = 0;
  int right = ArraySize(events);
  while (left < right)
  {
    int mid = left + (right - left) / 2;
    if (events[mid] < target)
      left = mid + 1;
    else
      right = mid;
  }
  return left;
}

bool HasBacktestNewsEventInWindow(const datetime &events[], datetime from, datetime to, datetime &hit_time)
{
  int count = ArraySize(events);
  if (count <= 0 || to < from)
    return false;
  int idx = LowerBoundEventTime(events, from);
  if (idx >= 0 && idx < count && events[idx] <= to)
  {
    hit_time = events[idx];
    return true;
  }
  return false;
}

bool LoadBacktestNewsCalendarCsv()
{
  news_backtest_calendar_loaded = true;
  news_backtest_calendar_ready = false;
  ArrayResize(news_backtest_all_event_times, 0);
  ArrayResize(news_backtest_high_event_times, 0);

  if (StringLen(NewsBacktestCalendarFile) == 0)
  {
    Print("News filter backtest CSV file name is empty.");
    return false;
  }

  ResetLastError();
  int fh = FileOpen(NewsBacktestCalendarFile, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON);
  if (fh == INVALID_HANDLE)
  {
    PrintFormat("News filter backtest CSV open failed: file=%s err=%d",
                NewsBacktestCalendarFile,
                GetLastError());
    return false;
  }

  const int kCsvColumns = 14;
  for (int c = 0; c < kCsvColumns && !FileIsEnding(fh); ++c)
    FileReadString(fh); // header

  int all_capacity = 0;
  int high_capacity = 0;
  int all_count = 0;
  int high_count = 0;

  while (!FileIsEnding(fh))
  {
    string server_time = FileReadString(fh);
    if (FileIsEnding(fh) && StringLen(server_time) == 0)
      break;

    FileReadString(fh); // gmt_time
    FileReadString(fh); // currency
    FileReadString(fh); // event_id
    FileReadString(fh); // value_id
    string importance = FileReadString(fh);
    FileReadString(fh); // impact
    FileReadString(fh); // event_name
    FileReadString(fh); // period
    FileReadString(fh); // revision
    FileReadString(fh); // actual
    FileReadString(fh); // forecast
    FileReadString(fh); // previous
    FileReadString(fh); // revised_previous

    datetime event_time = StringToTime(server_time);
    if (event_time <= 0)
      continue;

    if (all_count >= all_capacity)
    {
      all_capacity = (all_capacity <= 0) ? 512 : (all_capacity * 2);
      ArrayResize(news_backtest_all_event_times, all_capacity);
    }
    news_backtest_all_event_times[all_count] = event_time;
    all_count++;

    StringToUpper(importance);
    if (importance == "HIGH")
    {
      if (high_count >= high_capacity)
      {
        high_capacity = (high_capacity <= 0) ? 256 : (high_capacity * 2);
        ArrayResize(news_backtest_high_event_times, high_capacity);
      }
      news_backtest_high_event_times[high_count] = event_time;
      high_count++;
    }
  }

  FileClose(fh);

  ArrayResize(news_backtest_all_event_times, all_count);
  ArrayResize(news_backtest_high_event_times, high_count);
  if (all_count > 1)
    ArraySort(news_backtest_all_event_times);
  if (high_count > 1)
    ArraySort(news_backtest_high_event_times);

  news_backtest_calendar_ready = (all_count > 0);
  if (!news_backtest_calendar_ready)
  {
    PrintFormat("News filter backtest CSV is empty: file=%s", NewsBacktestCalendarFile);
    return false;
  }

  PrintFormat("News filter backtest CSV loaded: file=%s rows=%d high=%d",
              NewsBacktestCalendarFile,
              all_count,
              high_count);
  return true;
}

bool IsNewsTimeNowBacktest(datetime from, datetime to)
{
  if (!news_backtest_calendar_loaded)
    LoadBacktestNewsCalendarCsv();
  if (!news_backtest_calendar_ready)
    return false;

  datetime hit_time = 0;
  bool blocked = false;
  if (NewsOnlyHighImpact)
    blocked = HasBacktestNewsEventInWindow(news_backtest_high_event_times, from, to, hit_time);
  else
    blocked = HasBacktestNewsEventInWindow(news_backtest_all_event_times, from, to, hit_time);
  if (!blocked)
    return false;

  news_last_check_blocked = true;
  news_last_event_id = 0;
  news_last_event_time = hit_time;

  if (news_last_logged_event_time != news_last_event_time || news_last_logged_event_id != 0)
  {
    PrintFormat("News filter block(backtest CSV): importance=%s server=%s",
                NewsOnlyHighImpact ? "HIGH" : "ALL",
                TimeToString(news_last_event_time, TIME_DATE | TIME_MINUTES));
    news_last_logged_event_id = 0;
    news_last_logged_event_time = news_last_event_time;
  }
  return true;
}

bool IsNewsTimeNow()
{
  if (!EnableNewsFilter)
    return false;

  datetime now_server = TimeTradeServer();
  if (now_server <= 0)
    now_server = TimeCurrent();
  if (now_server <= 0)
    return false;

  if (news_last_checked_server_time == now_server)
    return news_last_check_blocked;

  news_last_checked_server_time = now_server;
  news_last_check_blocked = false;
  news_last_event_id = 0;
  news_last_event_time = 0;

  int minutes_before = NewsMinutesBefore;
  if (minutes_before < 0)
    minutes_before = 0;
  int minutes_after = NewsMinutesAfter;
  if (minutes_after < 0)
    minutes_after = 0;

  datetime from = now_server - minutes_before * 60;
  datetime to = now_server + minutes_after * 60;

  if (MQLInfoInteger(MQL_TESTER))
    return IsNewsTimeNowBacktest(from, to);

  MqlCalendarValue values[];
  ResetLastError();
  int n = CalendarValueHistory(values, from, to);
  if (n < 0)
  {
    int err = GetLastError();
    if (err != 0 && err != news_last_calendar_error)
    {
      PrintFormat("News filter query failed: err=%d", err);
      news_last_calendar_error = err;
    }
    return false;
  }
  news_last_calendar_error = 0;
  if (n == 0)
    return false;

  for (int i = 0; i < n; ++i)
  {
    ulong event_id = values[i].event_id;
    MqlCalendarEvent event;
    if (!CalendarEventById(event_id, event))
      continue;
    if (NewsOnlyHighImpact && event.importance != CALENDAR_IMPORTANCE_HIGH)
      continue;

    news_last_check_blocked = true;
    news_last_event_id = event_id;
    news_last_event_time = values[i].time;

    if (news_last_logged_event_id != news_last_event_id
        || news_last_logged_event_time != news_last_event_time)
    {
      PrintFormat("News filter block: id=%I64u event=%s importance=%d server=%s",
                  news_last_event_id,
                  event.name,
                  (int)event.importance,
                  TimeToString(news_last_event_time, TIME_DATE | TIME_MINUTES));
      news_last_logged_event_id = news_last_event_id;
      news_last_logged_event_time = news_last_event_time;
    }
    return true;
  }

  return false;
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
  int stop_end = 8 * 60 + 5;
  bool in_stop = (minutes >= stop_start && minutes < stop_end);
  return !in_stop;
}

void HandleTradingStopStartCloseAll()
{
  bool now_trading_time = IsTradingTime();
  if (!trading_time_state_initialized)
  {
    trading_time_state_initialized = true;
    trading_time_state_prev = now_trading_time;
    return;
  }

  bool entered_stop = (trading_time_state_prev && !now_trading_time);
  trading_time_state_prev = now_trading_time;
  if (!entered_stop || !CloseAllOnTradingStopStart)
    return;

  bool has_positions = false;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      continue;
    has_positions = true;
    break;
  }
  if (!has_positions)
    return;

  PrintFormat("Trading stop started: close all positions. magic=%d time=%s",
              MagicNumber,
              TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
  CloseAllPositionsByMagic(MagicNumber);
}

double NormalizeLotCached(const SymbolState &state, double lot)
{
  double step = state.volume_step;
  double minlot = state.volume_min;
  double maxlot = state.volume_max;
  if (step <= 0.0)
    step = 0.01;
  if (minlot <= 0.0)
    minlot = NM3::kMinLot;
  if (maxlot <= 0.0)
    maxlot = NM3::kMaxLot;
  lot = MathMax(minlot, MathMin(maxlot, lot));
  double steps = MathFloor(lot / step + 0.0000001);
  return NormalizeDouble(steps * step, NM3::kLotDigits);
}

void ClearLevelPrices(double &prices[])
{
  for (int i = 0; i < NM3::kMaxLevels; ++i)
    prices[i] = 0.0;
}

void SyncLevelPricesFromPositions(SymbolState &state, int buy_basket_id, int sell_basket_id)
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
    int basket_id = BasketIdFromComment(comment);
    int level = ExtractLevelFromComment(comment);
    if (level <= 0)
      level = 1;
    if (level > NM3::kMaxLevels)
      continue;
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    int type = (int)PositionGetInteger(POSITION_TYPE);
    if (type == POSITION_TYPE_BUY)
    {
      if (buy_basket_id <= 0 || basket_id != buy_basket_id)
        continue;
      if (state.buy_level_price[level - 1] <= 0.0)
        state.buy_level_price[level - 1] = price;
    }
    else if (type == POSITION_TYPE_SELL)
    {
      if (sell_basket_id <= 0 || basket_id != sell_basket_id)
        continue;
      if (state.sell_level_price[level - 1] <= 0.0)
        state.sell_level_price[level - 1] = price;
    }
  }
  if (state.buy_grid_step <= 0.0 && state.buy_level_price[0] > 0.0 && state.buy_level_price[1] > 0.0)
    state.buy_grid_step = MathAbs(state.buy_level_price[0] - state.buy_level_price[1]);
  if (state.sell_grid_step <= 0.0 && state.sell_level_price[0] > 0.0 && state.sell_level_price[1] > 0.0)
    state.sell_grid_step = MathAbs(state.sell_level_price[0] - state.sell_level_price[1]);
}

int EffectiveMaxLevels(const NM3Params &params)
{
  int levels = params.max_levels;
  if (levels < 1)
    levels = 1;
  if (levels > NM3::kLevelCap)
    levels = NM3::kLevelCap;
  return levels;
}

int EffectiveMaxLevelsRuntime(const SymbolState &state)
{
  return EffectiveMaxLevels(state.params);
}

int EffectiveNanpinLevelsRuntime(const SymbolState &state, bool is_trading_time)
{
  int levels = EffectiveMaxLevelsRuntime(state);
  if (!is_trading_time)
  {
    levels -= 1;
    if (levels < 0)
      levels = 0;
  }
  return levels;
}

int EffectiveCombinedProfitCloseLevel(const SymbolState &state)
{
  int level = state.params.combined_profit_close_level;
  if (level < 1)
    level = 1;
  return level;
}

double BasketLossStopPointsThresholdForLevel(const NM3Params &params, int level_count)
{
  if (level_count <= 0)
    return 0.0;
  int level = level_count;
  if (level > 5)
    level = 5;
  double threshold = 0.0;
  if (level == 1)
    threshold = params.basket_loss_stop_points_level1;
  else if (level == 2)
    threshold = params.basket_loss_stop_points_level2;
  else if (level == 3)
    threshold = params.basket_loss_stop_points_level3;
  else if (level == 4)
    threshold = params.basket_loss_stop_points_level4;
  else
    threshold = params.basket_loss_stop_points_level5;
  if (threshold < 0.0)
    threshold = 0.0;
  return threshold;
}

void BuildLotSequence(SymbolState &state)
{
  NM3Params params = state.params;
  int levels = EffectiveMaxLevels(state.params);
  for (int i = 0; i < NM3::kMaxLevels; ++i)
    state.lot_seq[i] = params.base_lot;
  if (levels <= 0)
    return;

  if (levels > 1)
  {
    if (params.double_second_lot)
      state.lot_seq[1] = params.base_lot * 2.0;
    else
      state.lot_seq[1] = params.base_lot;
  }

  if (params.martingale_mode == MARTINGALE_FIBONACCI)
  {
    for (int i = 2; i < levels; ++i)
      state.lot_seq[i] = state.lot_seq[i - 1] + state.lot_seq[i - 2];
  }
  else
  {
    double multiplier = params.proportional_martingale_multiplier;
    if (multiplier <= 0.0)
      multiplier = 1.0;
    for (int i = 2; i < levels; ++i)
    {
      state.lot_seq[i] = state.lot_seq[i - 1] * multiplier;
    }
  }

  for (int i = 0; i < levels; ++i)
  {
    state.lot_seq[i] = NormalizeLotCached(state, state.lot_seq[i]);
  }
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

bool HasOpenPositionByType(const SymbolState &state, ENUM_POSITION_TYPE type)
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
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
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

int ExtractBasketIdFromComment(const string comment)
{
  int pos = StringFind(comment, "_B");
  if (pos < 0)
    return 0;
  int tail_start = pos + 2;
  int level_pos = StringFind(comment, "_L", tail_start);
  string tail = "";
  if (level_pos >= 0)
    tail = StringSubstr(comment, tail_start, level_pos - tail_start);
  else
    tail = StringSubstr(comment, tail_start);
  int basket_id = (int)StringToInteger(tail);
  if (basket_id < 0)
    return 0;
  return basket_id;
}

int BasketIdFromComment(const string comment)
{
  int basket_id = ExtractBasketIdFromComment(comment);
  if (basket_id <= 0)
    basket_id = 1;
  return basket_id;
}

int NextBasketId(const SymbolState &state)
{
  if (state.next_basket_id > 0)
    return state.next_basket_id;
  return 1;
}

int FindCompletedBasketIndex(const int &basket_ids[], int count, int basket_id)
{
  for (int i = 0; i < count; ++i)
  {
    if (basket_ids[i] == basket_id)
      return i;
  }
  return -1;
}

bool IsCompletedBasket(const SymbolState &state, ENUM_POSITION_TYPE type, int basket_id)
{
  if (basket_id <= 0)
    return false;
  if (type == POSITION_TYPE_BUY)
    return FindCompletedBasketIndex(state.buy_completed_basket_ids, state.buy_completed_basket_count, basket_id) >= 0;
  if (type == POSITION_TYPE_SELL)
    return FindCompletedBasketIndex(state.sell_completed_basket_ids, state.sell_completed_basket_count, basket_id) >= 0;
  return false;
}

bool HasBasketPosition(const SymbolState &state, ENUM_POSITION_TYPE type, int basket_id)
{
  if (basket_id <= 0)
    return false;
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
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    string comment = PositionGetString(POSITION_COMMENT);
    if (BasketIdFromComment(comment) != basket_id)
      continue;
    return true;
  }
  return false;
}

void RemoveCompletedBasketAt(int &basket_ids[], int &count, int index)
{
  if (index < 0 || index >= count)
    return;
  for (int i = index; i < (count - 1); ++i)
    basket_ids[i] = basket_ids[i + 1];
  if (count > 0)
  {
    count--;
    basket_ids[count] = 0;
  }
}

void CleanupCompletedBasketSide(SymbolState &state, ENUM_POSITION_TYPE type)
{
  if (type == POSITION_TYPE_BUY)
  {
    int i = 0;
    while (i < state.buy_completed_basket_count)
    {
      int basket_id = state.buy_completed_basket_ids[i];
      if (basket_id <= 0 || !HasBasketPosition(state, type, basket_id))
      {
        RemoveCompletedBasketAt(state.buy_completed_basket_ids, state.buy_completed_basket_count, i);
        continue;
      }
      i++;
    }
  }
  else if (type == POSITION_TYPE_SELL)
  {
    int i = 0;
    while (i < state.sell_completed_basket_count)
    {
      int basket_id = state.sell_completed_basket_ids[i];
      if (basket_id <= 0 || !HasBasketPosition(state, type, basket_id))
      {
        RemoveCompletedBasketAt(state.sell_completed_basket_ids, state.sell_completed_basket_count, i);
        continue;
      }
      i++;
    }
  }
}

void CleanupCompletedBaskets(SymbolState &state)
{
  CleanupCompletedBasketSide(state, POSITION_TYPE_BUY);
  CleanupCompletedBasketSide(state, POSITION_TYPE_SELL);
}

void AddCompletedBasket(SymbolState &state, ENUM_POSITION_TYPE type, int basket_id)
{
  if (basket_id <= 0)
    return;
  if (IsCompletedBasket(state, type, basket_id))
    return;
  if (type == POSITION_TYPE_BUY)
  {
    if (state.buy_completed_basket_count >= NM3::kMaxTrackedBaskets)
      return;
    state.buy_completed_basket_ids[state.buy_completed_basket_count] = basket_id;
    state.buy_completed_basket_count++;
  }
  else if (type == POSITION_TYPE_SELL)
  {
    if (state.sell_completed_basket_count >= NM3::kMaxTrackedBaskets)
      return;
    state.sell_completed_basket_ids[state.sell_completed_basket_count] = basket_id;
    state.sell_completed_basket_count++;
  }
}

void CommitBasketId(SymbolState &state, ENUM_POSITION_TYPE type, int basket_id)
{
  if (basket_id <= 0)
    basket_id = 1;
  if (type == POSITION_TYPE_BUY)
    state.buy_active_basket_id = basket_id;
  else if (type == POSITION_TYPE_SELL)
    state.sell_active_basket_id = basket_id;
  if (state.next_basket_id <= basket_id)
    state.next_basket_id = basket_id + 1;
}

void RefreshBasketSequenceState(SymbolState &state)
{
  CleanupCompletedBaskets(state);
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  int prev_buy_active_basket_id = state.buy_active_basket_id;
  int prev_sell_active_basket_id = state.sell_active_basket_id;
  int max_basket_id = 0;
  int buy_active_basket_id = 0;
  int sell_active_basket_id = 0;
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
    int basket_id = BasketIdFromComment(comment);
    int level = ExtractLevelFromComment(comment);
    if (level <= 0)
      level = 1;
    if (basket_id > max_basket_id)
      max_basket_id = basket_id;
    int type = (int)PositionGetInteger(POSITION_TYPE);
    if (level == 1)
    {
      if (type == POSITION_TYPE_BUY && !IsCompletedBasket(state, POSITION_TYPE_BUY, basket_id) && basket_id > buy_active_basket_id)
        buy_active_basket_id = basket_id;
      else if (type == POSITION_TYPE_SELL && !IsCompletedBasket(state, POSITION_TYPE_SELL, basket_id) && basket_id > sell_active_basket_id)
        sell_active_basket_id = basket_id;
    }
  }
  if (buy_active_basket_id == 0 && prev_buy_active_basket_id > 0)
  {
    if (!IsCompletedBasket(state, POSITION_TYPE_BUY, prev_buy_active_basket_id)
        && HasBasketPosition(state, POSITION_TYPE_BUY, prev_buy_active_basket_id))
      buy_active_basket_id = prev_buy_active_basket_id;
  }
  if (sell_active_basket_id == 0 && prev_sell_active_basket_id > 0)
  {
    if (!IsCompletedBasket(state, POSITION_TYPE_SELL, prev_sell_active_basket_id)
        && HasBasketPosition(state, POSITION_TYPE_SELL, prev_sell_active_basket_id))
      sell_active_basket_id = prev_sell_active_basket_id;
  }
  state.buy_active_basket_id = buy_active_basket_id;
  state.sell_active_basket_id = sell_active_basket_id;
  if (state.next_basket_id <= max_basket_id)
    state.next_basket_id = max_basket_id + 1;
}

string MakeLevelComment(const string base, int basket_id, int level)
{
  if (basket_id <= 0)
    basket_id = 1;
  if (level <= 0)
    return StringFormat("%s_B%d", base, basket_id);
  return StringFormat("%s_B%d_L%d", base, basket_id, level);
}

int OnInit()
{
  if (_Period != PERIOD_M1)
  {
    PrintFormat("NM3 requires M1 chart timeframe. current=%s", EnumToString((ENUM_TIMEFRAMES)_Period));
    return INIT_FAILED;
  }
  Print("Broker=", AccountInfoString(ACCOUNT_COMPANY));
  LogServerUtcOffset();
  BuildSymbols();
  if (symbols_count == 0)
    return INIT_FAILED;
  ResetNewsFilterCache();
  if (EnableNewsFilter && MQLInfoInteger(MQL_TESTER))
    LoadBacktestNewsCalendarCsv();

  int active = 0;
  for (int i = 0; i < symbols_count; ++i)
  {
    if (!symbols[i].enabled)
      continue;
    if (!symbols[i].symbol_info_ready)
      RefreshSymbolInfo(symbols[i]);
    BuildLotSequence(symbols[i]);
    symbols[i].adx_handle = iADX(symbols[i].broker_symbol, _Period, symbols[i].params.adx_period);
    if (symbols[i].adx_handle == INVALID_HANDLE)
      PrintFormat("ADX handle failed: %s", symbols[i].broker_symbol);
    else
      TryInitRegimeFromHistory(symbols[i]);
    symbols[i].adx_m15_handle = iADX(symbols[i].broker_symbol, PERIOD_M15, symbols[i].params.adx_period);
    if (symbols[i].adx_m15_handle == INVALID_HANDLE)
      PrintFormat("ADX M15 handle failed: %s", symbols[i].broker_symbol);
    symbols[i].adx_h1_handle = iADX(symbols[i].broker_symbol, PERIOD_H1, symbols[i].params.adx_period);
    if (symbols[i].adx_h1_handle == INVALID_HANDLE)
      PrintFormat("ADX H1 handle failed: %s", symbols[i].broker_symbol);
    symbols[i].adx_h4_handle = iADX(symbols[i].broker_symbol, PERIOD_H4, symbols[i].params.adx_period);
    if (symbols[i].adx_h4_handle == INVALID_HANDLE)
      PrintFormat("ADX H4 handle failed: %s", symbols[i].broker_symbol);
    active++;
  }
  if (active == 0)
    return INIT_FAILED;
  if (!MQLInfoInteger(MQL_TESTER) && active > 1)
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
  trading_time_state_initialized = false;
  trading_time_state_prev = true;
  SendLog(BuildInitLogMessage(active));
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  EventKillTimer();
  for (int i = 0; i < symbols_count; ++i)
  {
    if (symbols[i].adx_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].adx_handle);
    symbols[i].adx_handle = INVALID_HANDLE;
    if (symbols[i].adx_m15_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].adx_m15_handle);
    symbols[i].adx_m15_handle = INVALID_HANDLE;
    if (symbols[i].adx_h1_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].adx_h1_handle);
    symbols[i].adx_h1_handle = INVALID_HANDLE;
    if (symbols[i].adx_h4_handle != INVALID_HANDLE)
      IndicatorRelease(symbols[i].adx_h4_handle);
    symbols[i].adx_h4_handle = INVALID_HANDLE;
  }
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
  // Use confirmed bars (shift=1) to avoid intra-bar noise and missed new_bar detection
  const int kStartPos = 1;
  const int kCount = 2;
  if (CopyBuffer(state.adx_handle, 0, kStartPos, kCount, adx_buf) < kCount)
    return false;
  if (CopyBuffer(state.adx_handle, 1, kStartPos, kCount, plus_buf) < kCount)
    return false;
  if (CopyBuffer(state.adx_handle, 2, kStartPos, kCount, minus_buf) < kCount)
    return false;
  adx_now = adx_buf[0];
  adx_prev = adx_buf[1];
  di_plus_now = plus_buf[0];
  di_plus_prev = plus_buf[1];
  di_minus_now = minus_buf[0];
  di_minus_prev = minus_buf[1];
  return true;
}

bool GetAdxH1Snapshot(SymbolState &state, double &adx_h1_current, double &adx_h1_previous)
{
  if (state.adx_h1_handle == INVALID_HANDLE)
    return false;
  double adx_buf[2];
  const int kStartPos = 1;
  const int kCount = 2;
  if (CopyBuffer(state.adx_h1_handle, 0, kStartPos, kCount, adx_buf) < kCount)
    return false;
  adx_h1_current = adx_buf[0];
  adx_h1_previous = adx_buf[1];
  return true;
}

int GetDiDirection(const int handle)
{
  if (handle == INVALID_HANDLE)
    return 0;
  double plus_buf[1];
  double minus_buf[1];
  const int kStartPos = 1;
  const int kCount = 1;
  if (CopyBuffer(handle, 1, kStartPos, kCount, plus_buf) < kCount)
    return 0;
  if (CopyBuffer(handle, 2, kStartPos, kCount, minus_buf) < kCount)
    return 0;
  if (plus_buf[0] > minus_buf[0])
    return 1;
  if (plus_buf[0] < minus_buf[0])
    return -1;
  return 0;
}

double TrendLotMultiplierDynamic(const SymbolState &state, ENUM_ORDER_TYPE order_type)
{
  double trend_multiplier = state.params.trend_lot_multiplier;
  if (trend_multiplier <= 0.0)
    trend_multiplier = 1.0;
  double semi_multiplier = trend_multiplier * 0.5;
  int desired = (order_type == ORDER_TYPE_BUY) ? 1 : -1;
  int dir_m15 = GetDiDirection(state.adx_m15_handle);
  int dir_h1 = GetDiDirection(state.adx_h1_handle);
  int dir_h4 = GetDiDirection(state.adx_h4_handle);

  bool match_m15 = (dir_m15 == desired);
  bool match_h1 = (dir_h1 == desired);
  bool match_h4 = (dir_h4 == desired);
  bool opp_h1 = (dir_h1 == -desired);
  bool opp_h4 = (dir_h4 == -desired);

  // Fallback when no data
  if (dir_m15 == 0 && dir_h1 == 0 && dir_h4 == 0)
    return 1.0;

  if (match_m15 && match_h1 && match_h4)
    return trend_multiplier;
  if (match_m15 && match_h1)
    return semi_multiplier;
  if (match_m15)
  {
    if (opp_h1 || opp_h4)
      return 0.5;
    return 1.0;
  }
  // M15 not aligned; if higher timeframes oppose, reduce risk.
  if (opp_h1 || opp_h4)
    return 0.5;
  return 1.0;
}

int SelectSingleEntryDirection(const SymbolState &state,
                               bool allow_entry_buy,
                               bool allow_entry_sell,
                               bool has_adx,
                               double di_plus_now,
                               double di_minus_now)
{
  if (!allow_entry_buy && !allow_entry_sell)
    return 0;
  if (allow_entry_buy && !allow_entry_sell)
    return 1;
  if (!allow_entry_buy && allow_entry_sell)
    return -1;

  if (state.regime == REGIME_TREND_UP)
    return 1;
  if (state.regime == REGIME_TREND_DOWN)
    return -1;

  if (has_adx)
  {
    if (di_plus_now > di_minus_now)
      return 1;
    if (di_minus_now > di_plus_now)
      return -1;
  }

  // Prefer lower timeframe when DI directions are mixed.
  int score = 0;
  int dir_m15 = GetDiDirection(state.adx_m15_handle);
  int dir_h1 = GetDiDirection(state.adx_h1_handle);
  int dir_h4 = GetDiDirection(state.adx_h4_handle);
  if (dir_m15 == 1)
    score += 2;
  else if (dir_m15 == -1)
    score -= 2;
  if (dir_h1 == 1)
    score += 1;
  else if (dir_h1 == -1)
    score -= 1;
  if (dir_h4 == 1)
    score += 1;
  else if (dir_h4 == -1)
    score -= 1;

  if (score > 0)
    return 1;
  if (score < 0)
    return -1;
  return 0;
}

void ResetBasketInfo(BasketInfo &basket, int basket_id)
{
  basket.basket_id = basket_id;
  basket.count = 0;
  basket.level_count = 0;
  basket.deepest_level = 0;
  basket.deepest_ticket = 0;
  basket.volume = 0.0;
  basket.avg_price = 0.0;
  basket.min_price = 0.0;
  basket.max_price = 0.0;
  basket.profit = 0.0;
}

void CollectBasketInfo(const SymbolState &state,
                       int buy_basket_id,
                       int sell_basket_id,
                       BasketInfo &buy,
                       BasketInfo &sell)
{
  const string symbol = state.broker_symbol;
  ResetBasketInfo(buy, buy_basket_id);
  ResetBasketInfo(sell, sell_basket_id);

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
    string comment = PositionGetString(POSITION_COMMENT);
    int basket_id = BasketIdFromComment(comment);
    int level = ExtractLevelFromComment(comment);
    if (level <= 0)
      level = 1;
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    if (type == POSITION_TYPE_BUY && buy_basket_id > 0 && basket_id == buy_basket_id)
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
      if (level > buy.level_count)
        buy.level_count = level;
      if (level > buy.deepest_level)
      {
        buy.deepest_level = level;
        buy.deepest_ticket = ticket;
      }
      buy.volume += volume;
      buy_value += volume * price;
      buy.profit += PositionGetDouble(POSITION_PROFIT);
    }
    else if (type == POSITION_TYPE_SELL && sell_basket_id > 0 && basket_id == sell_basket_id)
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
      if (level > sell.level_count)
        sell.level_count = level;
      if (level > sell.deepest_level)
      {
        sell.deepest_level = level;
        sell.deepest_ticket = ticket;
      }
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

double BasketTotalLossPoints(const SymbolState &state,
                             ENUM_POSITION_TYPE type,
                             int basket_id,
                             double bid,
                             double ask)
{
  if (basket_id <= 0)
    return 0.0;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  const string symbol = state.broker_symbol;
  int target_type = (int)type;
  double net_points = 0.0;
  for (int i = PositionsTotal() - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != state.params.magic_number)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    if ((int)PositionGetInteger(POSITION_TYPE) != target_type)
      continue;
    string comment = PositionGetString(POSITION_COMMENT);
    if (BasketIdFromComment(comment) != basket_id)
      continue;
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double position_points = 0.0;
    if (target_type == POSITION_TYPE_BUY)
      position_points = (open_price - bid) / point;
    else
      position_points = (ask - open_price) / point;
    net_points += position_points;
  }
  if (net_points < 0.0)
    net_points = 0.0;
  return net_points;
}

bool CanAddBasketByConstraint(const SymbolState &state,
                              ENUM_POSITION_TYPE type,
                              double bid,
                              double ask,
                              double take_profit_distance,
                              string &reason)
{
  reason = "";
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;

  int basket_ids[NM3::kMaxTrackedBaskets];
  int basket_counts[NM3::kMaxTrackedBaskets];
  bool basket_missing_sl[NM3::kMaxTrackedBaskets];
  double basket_volumes[NM3::kMaxTrackedBaskets];
  double basket_values[NM3::kMaxTrackedBaskets];
  int basket_count = 0;
  for (int i = 0; i < NM3::kMaxTrackedBaskets; ++i)
  {
    basket_ids[i] = 0;
    basket_counts[i] = 0;
    basket_missing_sl[i] = false;
    basket_volumes[i] = 0.0;
    basket_values[i] = 0.0;
  }

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

    string comment = PositionGetString(POSITION_COMMENT);
    int basket_id = BasketIdFromComment(comment);
    int idx = FindTrackedBasketIndex(basket_ids, basket_count, basket_id);
    if (idx < 0)
    {
      if (basket_count >= NM3::kMaxTrackedBaskets)
      {
        reason = "tracked_basket_limit_exceeded";
        return false;
      }
      idx = basket_count;
      basket_ids[idx] = basket_id;
      basket_count++;
    }

    basket_counts[idx]++;
    double volume = PositionGetDouble(POSITION_VOLUME);
    double price = PositionGetDouble(POSITION_PRICE_OPEN);
    basket_volumes[idx] += volume;
    basket_values[idx] += volume * price;
    if (PositionGetDouble(POSITION_SL) <= 0.0)
      basket_missing_sl[idx] = true;
  }

  if (basket_count <= 0)
    return true;

  bool require_tp_check = (take_profit_distance > 0.0);
  for (int i = 0; i < basket_count; ++i)
  {
    if (basket_counts[i] <= 0 || basket_volumes[i] <= 0.0)
      continue;
    double avg_price = basket_values[i] / basket_volumes[i];
    bool tp_reached = true;
    if (require_tp_check)
    {
      if (type == POSITION_TYPE_BUY)
        tp_reached = bid >= (avg_price + take_profit_distance);
      else
        tp_reached = ask <= (avg_price - take_profit_distance);
    }
    if (basket_missing_sl[i] || !tp_reached)
    {
      reason = StringFormat("basket=%d count=%d missing_sl=%s tp_reached=%s avg=%.5f",
                            basket_ids[i], basket_counts[i],
                            basket_missing_sl[i] ? "true" : "false",
                            tp_reached ? "true" : "false",
                            avg_price);
      return false;
    }
  }
  return true;
}

void LogBasketAddBlocked(SymbolState &state,
                         ENUM_POSITION_TYPE type,
                         datetime now,
                         const string reason)
{
  datetime last_logged = 0;
  if (type == POSITION_TYPE_BUY)
    last_logged = state.buy_basket_add_blocked_log_time;
  else
    last_logged = state.sell_basket_add_blocked_log_time;

  if (last_logged > 0 && (now - last_logged) < 5)
    return;

  PrintFormat("Basket add blocked: %s type=%d reason=%s",
              state.broker_symbol, (int)type, reason);
  if (type == POSITION_TYPE_BUY)
    state.buy_basket_add_blocked_log_time = now;
  else
    state.sell_basket_add_blocked_log_time = now;
}

bool CanStartNewBasket(SymbolState &state,
                       ENUM_ORDER_TYPE order_type,
                       double bid,
                       double ask,
                       double take_profit_distance,
                       datetime now)
{
  ENUM_POSITION_TYPE type = POSITION_TYPE_BUY;
  if (order_type == ORDER_TYPE_BUY)
    type = POSITION_TYPE_BUY;
  else if (order_type == ORDER_TYPE_SELL)
    type = POSITION_TYPE_SELL;
  else
    return false;

  string reason = "";
  if (CanAddBasketByConstraint(state, type, bid, ask, take_profit_distance, reason))
    return true;
  LogBasketAddBlocked(state, type, now,
                      StringFormat("request_type=%d %s", (int)order_type, reason));
  return false;
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

double LevelStepFactor(const NM3Params &params, int level)
{
  return 1.0;
}

double AdjustNanpinStep(const double &level_prices[], int level_index, double step, bool enabled)
{
  return step;
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

string EscapeJson(const string text)
{
  string out = "";
  int len = StringLen(text);
  for (int i = 0; i < len; ++i)
  {
    ushort ch = StringGetCharacter(text, i);
    if (ch == '\\')
      out += "\\\\";
    else if (ch == '\"')
      out += "\\\"";
    else if (ch == '\n')
      out += "\\n";
    else if (ch == '\r')
      out += "\\r";
    else if (ch == '\t')
      out += "\\t";
    else
      out += StringSubstr(text, i, 1);
  }
  return out;
}

string BuildLogServerUrl()
{
  if (StringLen(LogServerHost) == 0)
    return "";
  string host = LogServerHost;
  string lower = host;
  StringToLower(lower);
  if (StringFind(lower, "http://") == 0)
    host = StringSubstr(host, 7);
  else if (StringFind(lower, "https://") == 0)
    host = StringSubstr(host, 8);

  // strip leading/trailing slashes
  while (StringLen(host) > 0 && StringSubstr(host, 0, 1) == "/")
    host = StringSubstr(host, 1);
  while (StringLen(host) > 0 && StringSubstr(host, StringLen(host) - 1, 1) == "/")
    host = StringSubstr(host, 0, StringLen(host) - 1);

  if (StringLen(host) == 0)
    return "";

  return StringFormat("https://%s/logs", host);
}

void SendLog(const string message, const string level = "info", const string source = "")
{
  string url = BuildLogServerUrl();
  if (StringLen(url) == 0)
    return;

  string src = source;
  if (StringLen(src) == 0)
    src = (StringLen(ManagementServerUser) > 0 ? ManagementServerUser : "NM3");
  string payload = StringFormat("{\"message\":\"%s\",\"level\":\"%s\",\"source\":\"%s\"}",
                                EscapeJson(message), EscapeJson(level), EscapeJson(src));

  char data[];
  int data_size = StringToCharArray(payload, data, 0, WHOLE_ARRAY, CP_UTF8);
  if (data_size > 0)
    data_size--; // exclude null terminator for HTTP body
  string headers = "Content-Type: application/json\r\n";
  char result[];
  string result_headers;

  ResetLastError();
  int status = WebRequest("POST", url, "", "", 200, data, data_size, result, result_headers);
  if (status <= 0)
  {
    int err = GetLastError();
    PrintFormat("Log POST failed (%d): %s", err, url);
  }
  else if (status >= 400)
  {
    PrintFormat("Log POST HTTP %d: %s", status, url);
  }
}

string BuildRegimeLogMessage(const SymbolState &state, const int prev_regime)
{
  return StringFormat("Regime changed: %s -> %s (%s)",
                      RegimeName(prev_regime), RegimeName(state.regime), state.broker_symbol);
}

string BuildInitLogMessage(const int active_symbols)
{
  return StringFormat("OnInit succeeded: active_symbols=%d", active_symbols);
}

void LogServerUtcOffset()
{
  datetime server_current = TimeCurrent();
  datetime server_trade = TimeTradeServer();
  datetime utc_time = TimeGMT();
  if (MQLInfoInteger(MQL_TESTER))
  {
    PrintFormat("ServerTimeOffset skipped in tester: SimServer=%s UTC(now)=%s",
                TimeToString(server_current, TIME_DATE | TIME_SECONDS),
                TimeToString(utc_time, TIME_DATE | TIME_SECONDS));
    return;
  }

  datetime server_time = server_trade;
  string source = "TimeTradeServer";
  if (server_time <= 0)
  {
    server_time = server_current;
    source = "TimeCurrent";
  }
  long offset_sec = (long)server_time - (long)utc_time;
  long abs_sec = offset_sec;
  if (abs_sec < 0)
    abs_sec = -abs_sec;
  int offset_h = (int)(abs_sec / 3600);
  int offset_m = (int)((abs_sec % 3600) / 60);
  string sign = (offset_sec >= 0) ? "+" : "-";
  PrintFormat("ServerTimeOffset Broker=%s Server=%s UTC=%s Offset=%s%02d:%02d Source=%s",
              AccountInfoString(ACCOUNT_COMPANY),
              TimeToString(server_time, TIME_DATE | TIME_SECONDS),
              TimeToString(utc_time, TIME_DATE | TIME_SECONDS),
              sign, offset_h, offset_m, source);
}

void TryInitRegimeFromHistory(SymbolState &state)
{
  if (state.adx_handle == INVALID_HANDLE)
    return;
  int on_bars = MathMax(state.params.regime_on_bars, 1);
  int needed = on_bars;
  if (needed <= 0)
    return;

  double adx_buf[];
  double plus_buf[];
  double minus_buf[];
  ArrayResize(adx_buf, needed);
  ArrayResize(plus_buf, needed);
  ArrayResize(minus_buf, needed);
  if (CopyBuffer(state.adx_handle, 0, 0, needed, adx_buf) < needed)
    return;
  if (CopyBuffer(state.adx_handle, 1, 0, needed, plus_buf) < needed)
    return;
  if (CopyBuffer(state.adx_handle, 2, 0, needed, minus_buf) < needed)
    return;

  int up_count = 0;
  int down_count = 0;
  for (int i = 0; i < needed; ++i)
  {
    double di_gap = MathAbs(plus_buf[i] - minus_buf[i]);
    bool on_cond = (adx_buf[i] >= state.params.regime_adx_on && di_gap >= state.params.regime_di_gap_on);
    if (!on_cond)
      break;
    if (plus_buf[i] > minus_buf[i])
    {
      if (down_count > 0)
        break;
      up_count++;
    }
    else if (minus_buf[i] > plus_buf[i])
    {
      if (up_count > 0)
        break;
      down_count++;
    }
    else
    {
      break;
    }
  }

  state.regime = REGIME_NORMAL;
  if (up_count >= on_bars)
    state.regime = REGIME_TREND_UP;
  else if (down_count >= on_bars)
    state.regime = REGIME_TREND_DOWN;
  state.regime_up_count = 0;
  state.regime_down_count = 0;
  state.regime_off_count = 0;
  state.regime_cooling_left = 0;
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

void UpdateRegime(SymbolState &state, double adx_now, double di_plus_now, double di_minus_now, datetime confirmed_bar_time)
{
  // Process once per confirmed bar (shift=1) to avoid missing regime changes when new_bar detection lags.
  if (confirmed_bar_time <= 0)
    return;
  if (state.last_regime_bar_time != 0 && confirmed_bar_time == state.last_regime_bar_time)
    return;
  state.last_regime_bar_time = confirmed_bar_time;
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
    // If on_cond persists but DI dominance flips for several bars, allow direct trend reversal.
    if (on_cond)
    {
      if (state.regime == REGIME_TREND_UP && di_minus_now > di_plus_now)
      {
        state.regime_down_count++;
        state.regime_up_count = 0;
      }
      else if (state.regime == REGIME_TREND_DOWN && di_plus_now > di_minus_now)
      {
        state.regime_up_count++;
        state.regime_down_count = 0;
      }
      else
      {
        state.regime_up_count = 0;
        state.regime_down_count = 0;
      }
    }
    else
    {
      state.regime_up_count = 0;
      state.regime_down_count = 0;
    }
    if (state.regime_off_count >= off_bars)
    {
      state.regime = REGIME_COOLING;
      state.regime_cooling_left = cooling_bars;
      state.regime_off_count = 0;
    }
    else if (state.regime == REGIME_TREND_UP && state.regime_down_count >= on_bars)
    {
      state.regime = REGIME_TREND_DOWN;
      state.regime_up_count = 0;
      state.regime_down_count = 0;
      state.regime_off_count = 0;
    }
    else if (state.regime == REGIME_TREND_DOWN && state.regime_up_count >= on_bars)
    {
      state.regime = REGIME_TREND_UP;
      state.regime_up_count = 0;
      state.regime_down_count = 0;
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
    SendLog(BuildRegimeLogMessage(state, prev));
    PrintFormat("Regime changed: %s -> %s (%s)", RegimeName(prev), RegimeName(state.regime), state.broker_symbol);
  }
}

void CloseBasket(const SymbolState &state, ENUM_POSITION_TYPE type)
{
  const string symbol = state.broker_symbol;
  close_trade.SetExpertMagicNumber(state.params.magic_number);
  close_trade.SetDeviationInPoints(state.params.slippage_points);
  close_trade.SetAsyncMode(true);
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

bool CloseBasketPositionsExceptTicket(const SymbolState &state,
                                      ENUM_POSITION_TYPE type,
                                      int basket_id,
                                      ulong keep_ticket,
                                      const string context)
{
  if (basket_id <= 0)
    return false;
  const string symbol = state.broker_symbol;
  close_trade.SetExpertMagicNumber(state.params.magic_number);
  close_trade.SetDeviationInPoints(state.params.slippage_points);
  close_trade.SetAsyncMode(true);
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
    if (ticket == keep_ticket)
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != state.params.magic_number)
      continue;
    if (PositionGetString(POSITION_SYMBOL) != symbol)
      continue;
    if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
      continue;
    string comment = PositionGetString(POSITION_COMMENT);
    if (BasketIdFromComment(comment) != basket_id)
      continue;
    tickets[count++] = ticket;
  }
  if (count > 0)
    ArrayResize(tickets, count);

  bool all_closed = true;
  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    while (attempts <= state.params.close_retry_count)
    {
      if (ClosePositionWithLog(tickets[i], context))
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
      all_closed = false;
      PrintFormat("Close failed after retries: ticket=%I64u retcode=%d %s",
                  tickets[i], close_trade.ResultRetcode(), close_trade.ResultRetcodeDescription());
    }
  }
  return all_closed;
}

bool CloseBasketById(const SymbolState &state, ENUM_POSITION_TYPE type, int basket_id)
{
  return CloseBasketPositionsExceptTicket(state, type, basket_id, 0, "basket_by_id");
}

bool UpdatePositionTrailSL(const SymbolState &state,
                           ulong ticket,
                           ENUM_POSITION_TYPE type,
                           double requested_sl)
{
  if (!PositionSelectByTicket(ticket))
    return false;
  const string symbol = PositionGetString(POSITION_SYMBOL);
  if (PositionGetInteger(POSITION_MAGIC) != state.params.magic_number)
    return false;
  if (symbol != state.broker_symbol)
    return false;
  if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
    return false;

  int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
  if (stops_level < 0)
    stops_level = 0;
  double broker_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (broker_point <= 0.0)
    broker_point = state.point;
  if (broker_point <= 0.0)
    broker_point = 0.00001;
  double stops_dist = stops_level * broker_point;
  double min_dist = stops_dist + (2.0 * broker_point);

  double price_step = state.tick_size;
  if (price_step <= 0.0)
    price_step = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  if (price_step <= 0.0)
    price_step = broker_point;
  if (price_step <= 0.0)
    price_step = 0.00001;

  int price_digits = state.digits;
  if (price_digits < 0)
    price_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  if (price_digits < 0)
    price_digits = 5;

  MqlTick tick;
  if (!SymbolInfoTick(symbol, tick))
    return false;

  if (type == POSITION_TYPE_BUY)
  {
    double max_sl = tick.bid - min_dist;
    if (requested_sl > max_sl)
      requested_sl = max_sl;
    requested_sl = MathFloor(requested_sl / price_step) * price_step;
  }
  else
  {
    double min_sl = tick.ask + min_dist;
    if (requested_sl < min_sl)
      requested_sl = min_sl;
    requested_sl = MathCeil(requested_sl / price_step) * price_step;
  }
  requested_sl = NormalizeDouble(requested_sl, price_digits);

  double cur_sl = PositionGetDouble(POSITION_SL);
  double tol = price_step * 0.5;
  if (cur_sl > 0.0)
  {
    double cur_sl_cmp = NormalizeDouble(MathRound(cur_sl / price_step) * price_step, price_digits);
    if (type == POSITION_TYPE_BUY && requested_sl <= cur_sl_cmp + tol)
      return true;
    if (type == POSITION_TYPE_SELL && requested_sl >= cur_sl_cmp - tol)
      return true;
  }

  double tp = PositionGetDouble(POSITION_TP);
  if (tp > 0.0)
    tp = NormalizeDouble(MathRound(tp / price_step) * price_step, price_digits);
  CTrade tr;
  tr.SetExpertMagicNumber(state.params.magic_number);
  tr.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    tr.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  bool ok = tr.PositionModify(ticket, requested_sl, tp);
  if (!ok)
  {
    PrintFormat("Runner SL update failed: %s ticket=%I64u type=%d sl=%.5f retcode=%d %s",
                symbol, ticket, (int)type, requested_sl, tr.ResultRetcode(), tr.ResultRetcodeDescription());
  }
  return ok;
}

bool ClearPositionSL(const SymbolState &state,
                     ulong ticket,
                     ENUM_POSITION_TYPE type)
{
  if (!PositionSelectByTicket(ticket))
    return false;
  const string symbol = PositionGetString(POSITION_SYMBOL);
  if (PositionGetInteger(POSITION_MAGIC) != state.params.magic_number)
    return false;
  if (symbol != state.broker_symbol)
    return false;
  if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
    return false;
  double cur_sl = PositionGetDouble(POSITION_SL);
  if (cur_sl <= 0.0)
    return true;
  double tp = PositionGetDouble(POSITION_TP);
  double price_step = state.tick_size;
  if (price_step <= 0.0)
    price_step = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  if (price_step <= 0.0)
    price_step = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (price_step > 0.0 && tp > 0.0)
  {
    int price_digits = state.digits;
    if (price_digits < 0)
      price_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    if (price_digits < 0)
      price_digits = 5;
    tp = NormalizeDouble(MathRound(tp / price_step) * price_step, price_digits);
  }
  CTrade tr;
  tr.SetExpertMagicNumber(state.params.magic_number);
  tr.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    tr.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
  bool ok = tr.PositionModify(ticket, 0.0, tp);
  if (!ok)
  {
    PrintFormat("Runner SL clear failed: %s ticket=%I64u type=%d retcode=%d %s",
                symbol, ticket, (int)type, tr.ResultRetcode(), tr.ResultRetcodeDescription());
  }
  return ok;
}

int FindTrackedBasketIndex(const int &basket_ids[], int count, int basket_id)
{
  for (int i = 0; i < count; ++i)
  {
    if (basket_ids[i] == basket_id)
      return i;
  }
  return -1;
}

int FindRunnerTrailIndex(const ulong ticket)
{
  int count = ArraySize(runner_trail_tickets);
  for (int i = 0; i < count; ++i)
  {
    if (runner_trail_tickets[i] == ticket)
      return i;
  }
  return -1;
}

int FindRunnerRevisitIndex(const ulong ticket)
{
  int count = ArraySize(runner_revisit_tickets);
  for (int i = 0; i < count; ++i)
  {
    if (runner_revisit_tickets[i] == ticket)
      return i;
  }
  return -1;
}

void RemoveRunnerRevisitAt(const int index)
{
  int count = ArraySize(runner_revisit_tickets);
  if (index < 0 || index >= count)
    return;
  for (int i = index; i < (count - 1); ++i)
  {
    runner_revisit_tickets[i] = runner_revisit_tickets[i + 1];
    runner_revisit_types[i] = runner_revisit_types[i + 1];
    runner_revisit_rebound_prices[i] = runner_revisit_rebound_prices[i + 1];
    runner_revisit_deep_prices[i] = runner_revisit_deep_prices[i + 1];
    runner_revisit_rebound_touched[i] = runner_revisit_rebound_touched[i + 1];
  }
  count--;
  ArrayResize(runner_revisit_tickets, count);
  ArrayResize(runner_revisit_types, count);
  ArrayResize(runner_revisit_rebound_prices, count);
  ArrayResize(runner_revisit_deep_prices, count);
  ArrayResize(runner_revisit_rebound_touched, count);
}

void RemoveRunnerRevisitTicket(const ulong ticket)
{
  int idx = FindRunnerRevisitIndex(ticket);
  if (idx >= 0)
    RemoveRunnerRevisitAt(idx);
}

void RemoveRunnerRevisitForBasket(const SymbolState &state,
                                  ENUM_POSITION_TYPE type,
                                  int basket_id)
{
  if (basket_id <= 0)
    return;
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  int i = 0;
  int count = ArraySize(runner_revisit_tickets);
  while (i < count)
  {
    ulong ticket = runner_revisit_tickets[i];
    if (!PositionSelectByTicket(ticket))
    {
      RemoveRunnerRevisitAt(i);
      count = ArraySize(runner_revisit_tickets);
      continue;
    }
    if (PositionGetInteger(POSITION_MAGIC) != magic
        || PositionGetString(POSITION_SYMBOL) != symbol
        || (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
    {
      i++;
      continue;
    }
    string comment = PositionGetString(POSITION_COMMENT);
    if (BasketIdFromComment(comment) == basket_id)
    {
      RemoveRunnerRevisitAt(i);
      count = ArraySize(runner_revisit_tickets);
      continue;
    }
    i++;
  }
}

void RemoveRunnerTrailAt(const int index)
{
  int count = ArraySize(runner_trail_tickets);
  if (index < 0 || index >= count)
    return;
  for (int i = index; i < (count - 1); ++i)
  {
    runner_trail_tickets[i] = runner_trail_tickets[i + 1];
    runner_trail_types[i] = runner_trail_types[i + 1];
    runner_trail_stops[i] = runner_trail_stops[i + 1];
  }
  count--;
  ArrayResize(runner_trail_tickets, count);
  ArrayResize(runner_trail_types, count);
  ArrayResize(runner_trail_stops, count);
}

void RemoveRunnerTrailTicket(const ulong ticket)
{
  int idx = FindRunnerTrailIndex(ticket);
  if (idx >= 0)
    RemoveRunnerTrailAt(idx);
  RemoveRunnerRevisitTicket(ticket);
}

void CleanupRunnerTrailState()
{
  int i = 0;
  int count = ArraySize(runner_trail_tickets);
  while (i < count)
  {
    ulong ticket = runner_trail_tickets[i];
    if (!PositionSelectByTicket(ticket))
    {
      RemoveRunnerTrailAt(i);
      count = ArraySize(runner_trail_tickets);
      continue;
    }
    i++;
  }
}

void CleanupRunnerRevisitState()
{
  int i = 0;
  int count = ArraySize(runner_revisit_tickets);
  while (i < count)
  {
    ulong ticket = runner_revisit_tickets[i];
    if (!PositionSelectByTicket(ticket))
    {
      RemoveRunnerRevisitAt(i);
      count = ArraySize(runner_revisit_tickets);
      continue;
    }
    i++;
  }
}

double UpsertRunnerTrailStop(const ulong ticket,
                             ENUM_POSITION_TYPE type,
                             double candidate_stop)
{
  int idx = FindRunnerTrailIndex(ticket);
  if (idx < 0)
  {
    int count = ArraySize(runner_trail_tickets);
    if (count >= NM3::kRunnerTrailStateCap)
    {
      RemoveRunnerTrailAt(0);
      count = ArraySize(runner_trail_tickets);
    }
    ArrayResize(runner_trail_tickets, count + 1);
    ArrayResize(runner_trail_types, count + 1);
    ArrayResize(runner_trail_stops, count + 1);
    runner_trail_tickets[count] = ticket;
    runner_trail_types[count] = (int)type;
    runner_trail_stops[count] = candidate_stop;
    return candidate_stop;
  }

  double stop = runner_trail_stops[idx];
  if (type == POSITION_TYPE_BUY)
  {
    if (candidate_stop > stop)
      stop = candidate_stop;
  }
  else
  {
    if (candidate_stop < stop)
      stop = candidate_stop;
  }
  runner_trail_types[idx] = (int)type;
  runner_trail_stops[idx] = stop;
  return stop;
}

void UpsertRunnerRevisitState(const ulong ticket,
                              ENUM_POSITION_TYPE type,
                              double rebound_price,
                              double deep_price)
{
  if (ticket == 0 || rebound_price <= 0.0 || deep_price <= 0.0)
    return;
  if (MathAbs(rebound_price - deep_price) <= 0.0)
    return;

  int idx = FindRunnerRevisitIndex(ticket);
  if (idx < 0)
  {
    int count = ArraySize(runner_revisit_tickets);
    if (count >= NM3::kRunnerTrailStateCap)
    {
      RemoveRunnerRevisitAt(0);
      count = ArraySize(runner_revisit_tickets);
    }
    ArrayResize(runner_revisit_tickets, count + 1);
    ArrayResize(runner_revisit_types, count + 1);
    ArrayResize(runner_revisit_rebound_prices, count + 1);
    ArrayResize(runner_revisit_deep_prices, count + 1);
    ArrayResize(runner_revisit_rebound_touched, count + 1);
    idx = count;
  }

  runner_revisit_tickets[idx] = ticket;
  runner_revisit_types[idx] = (int)type;
  runner_revisit_rebound_prices[idx] = rebound_price;
  runner_revisit_deep_prices[idx] = deep_price;
  runner_revisit_rebound_touched[idx] = false;
}

double RunnerRevisitCloseBand(const SymbolState &state, double rebound_price, double deep_price)
{
  double band = MathAbs(rebound_price - deep_price) * NM3::kDeepRunnerRevisitCloseBandRatio;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double min_band = point * NM3::kDeepLevelTrailLockPoints;
  if (band < min_band)
    band = min_band;
  return band;
}

bool ShouldCloseRunnerByRevisit(SymbolState &state,
                                const ulong ticket,
                                ENUM_POSITION_TYPE type,
                                double market_price)
{
  int idx = FindRunnerRevisitIndex(ticket);
  if (idx < 0)
    return false;

  if (runner_revisit_types[idx] != (int)type)
  {
    RemoveRunnerRevisitAt(idx);
    return false;
  }

  double rebound_price = runner_revisit_rebound_prices[idx];
  double deep_price = runner_revisit_deep_prices[idx];
  if (rebound_price <= 0.0 || deep_price <= 0.0)
    return false;

  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double tol = point * 0.5;

  if (!runner_revisit_rebound_touched[idx])
  {
    bool touched = false;
    if (type == POSITION_TYPE_BUY)
      touched = (market_price >= (rebound_price - tol));
    else
      touched = (market_price <= (rebound_price + tol));
    if (touched)
    {
      runner_revisit_rebound_touched[idx] = true;
      PrintFormat("Deep runner revisit armed: %s ticket=%I64u type=%d rebound=%.5f deep=%.5f",
                  state.broker_symbol, ticket, (int)type, rebound_price, deep_price);
    }
    return false;
  }

  double close_band = RunnerRevisitCloseBand(state, rebound_price, deep_price);
  bool close_signal = false;
  if (type == POSITION_TYPE_BUY)
    close_signal = (market_price <= (deep_price + close_band));
  else
    close_signal = (market_price >= (deep_price - close_band));
  if (!close_signal)
    return false;

  if (!ClosePositionWithLog(ticket, "runner_deep_revisit"))
    return false;

  if (!PositionSelectByTicket(ticket))
  {
    RemoveRunnerTrailTicket(ticket);
    PrintFormat("Deep runner revisit TP: %s ticket=%I64u type=%d price=%.5f rebound=%.5f deep=%.5f band=%.5f",
                state.broker_symbol, ticket, (int)type, market_price, rebound_price, deep_price, close_band);
  }
  return true;
}

void ManageRunnerTrailing(SymbolState &state,
                          ENUM_POSITION_TYPE type,
                          int active_basket_id,
                          double market_price,
                          double take_profit_distance)
{
  if (!state.params.trailing_take_profit)
    return;
  if (take_profit_distance <= 0.0)
    return;
  CleanupRunnerTrailState();
  CleanupRunnerRevisitState();
  double trail_distance = TakeProfitTrailDistanceCapped(state, take_profit_distance);
  if (trail_distance <= 0.0)
    return;
  bool use_trail_sl = state.params.use_take_profit_trail_sl;
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  int basket_ids[NM3::kMaxTrackedBaskets];
  int deepest_levels[NM3::kMaxTrackedBaskets];
  ulong deepest_tickets[NM3::kMaxTrackedBaskets];
  int basket_count = 0;
  for (int i = 0; i < NM3::kMaxTrackedBaskets; ++i)
  {
    basket_ids[i] = 0;
    deepest_levels[i] = 0;
    deepest_tickets[i] = 0;
  }

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
    string comment = PositionGetString(POSITION_COMMENT);
    int basket_id = BasketIdFromComment(comment);
    if (active_basket_id > 0 && basket_id == active_basket_id)
      continue;
    if (!IsCompletedBasket(state, type, basket_id))
      continue;
    int level = ExtractLevelFromComment(comment);
    if (level <= 0)
      level = 1;
    int idx = FindTrackedBasketIndex(basket_ids, basket_count, basket_id);
    if (idx < 0)
    {
      if (basket_count >= NM3::kMaxTrackedBaskets)
        continue;
      idx = basket_count;
      basket_ids[idx] = basket_id;
      deepest_levels[idx] = level;
      deepest_tickets[idx] = ticket;
      basket_count++;
    }
    else if (level > deepest_levels[idx])
    {
      deepest_levels[idx] = level;
      deepest_tickets[idx] = ticket;
    }
  }

  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double tol = point * 0.5;
  for (int i = 0; i < basket_count; ++i)
  {
    int basket_id = basket_ids[i];
    int deepest_level = deepest_levels[i];
    ulong keep_ticket = deepest_tickets[i];
    if (basket_id <= 0 || keep_ticket == 0 || deepest_level <= 0)
      continue;

    // If non-deep orders remain unexpectedly, keep enforcing deepest-only runner state.
    CloseBasketPositionsExceptTicket(state, type, basket_id, keep_ticket, "runner_cleanup");

    if (!PositionSelectByTicket(keep_ticket))
      continue;
    if (state.params.enable_deep_runner_revisit_take_profit)
    {
      if (ShouldCloseRunnerByRevisit(state, keep_ticket, type, market_price))
        continue;
      // L3+ runner waits for revisit condition; skip generic trail close while armed.
      if (FindRunnerRevisitIndex(keep_ticket) >= 0)
        continue;
    }
    else
    {
      if (FindRunnerRevisitIndex(keep_ticket) >= 0)
        RemoveRunnerRevisitTicket(keep_ticket);
    }
    double requested_stop = market_price;
    if (type == POSITION_TYPE_BUY)
      requested_stop = market_price - trail_distance;
    else
      requested_stop = market_price + trail_distance;

    if (use_trail_sl)
    {
      RemoveRunnerTrailTicket(keep_ticket);
      UpdatePositionTrailSL(state, keep_ticket, type, requested_stop);
      continue;
    }

    ClearPositionSL(state, keep_ticket, type);
    double stop_price = UpsertRunnerTrailStop(keep_ticket, type, requested_stop);
    if (type == POSITION_TYPE_BUY)
    {
      if (market_price <= stop_price + tol)
        ClosePositionWithLog(keep_ticket, "runner_trail");
    }
    else
    {
      if (market_price >= stop_price - tol)
        ClosePositionWithLog(keep_ticket, "runner_trail");
    }
  }
}

bool UpdateBasketSL(SymbolState &state,
                    ENUM_POSITION_TYPE type,
                    double requested_sl,
                    double &applied_sl)
{
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;
  bool is_buy = (type == POSITION_TYPE_BUY);
  ulong now_ms = GetTickCount();

  ulong cooldown_until_ms = is_buy ? state.buy_trail_sl_cooldown_until_ms : state.sell_trail_sl_cooldown_until_ms;
  if (cooldown_until_ms > 0 && now_ms < cooldown_until_ms)
    return true;

  int min_interval_ms = state.params.trail_sl_modify_min_interval_ms;
  if (min_interval_ms < 0)
    min_interval_ms = 0;
  ulong last_send_ms = is_buy ? state.buy_trail_sl_last_send_ms : state.sell_trail_sl_last_send_ms;
  if (min_interval_ms > 0 && last_send_ms > 0)
  {
    ulong elapsed_ms = (now_ms >= last_send_ms) ? (now_ms - last_send_ms) : 0;
    if (elapsed_ms < (ulong)min_interval_ms)
      return true;
  }

  applied_sl = requested_sl;

  int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
  int freeze_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
  if (stops_level < 0)
    stops_level = 0;
  if (freeze_level < 0)
    freeze_level = 0;

  double broker_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  if (broker_point <= 0.0)
    broker_point = state.point;
  if (broker_point <= 0.0)
    broker_point = 0.00001;

  double price_step = state.tick_size;
  if (price_step <= 0.0)
    price_step = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  if (price_step <= 0.0)
    price_step = broker_point;
  if (price_step <= 0.0)
    price_step = 0.00001;
  int price_digits = state.digits;
  if (price_digits < 0)
    price_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  if (price_digits < 0)
    price_digits = 5;

  MqlTick tick;
  if (!SymbolInfoTick(symbol, tick))
    return false;

  double stops_dist = stops_level * broker_point;
  double freeze_dist = freeze_level * broker_point;
  double min_dist = stops_dist + (2.0 * broker_point);
  if (type == POSITION_TYPE_BUY)
  {
    double max_sl = tick.bid - min_dist;
    if (applied_sl > max_sl)
      applied_sl = max_sl;
    applied_sl = MathFloor(applied_sl / price_step) * price_step;
  }
  else
  {
    double min_sl = tick.ask + min_dist;
    if (applied_sl < min_sl)
      applied_sl = min_sl;
    applied_sl = MathCeil(applied_sl / price_step) * price_step;
  }
  applied_sl = NormalizeDouble(applied_sl, price_digits);

  CTrade tr;
  tr.SetExpertMagicNumber(magic);
  tr.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if (filling == ORDER_FILLING_FOK || filling == ORDER_FILLING_IOC || filling == ORDER_FILLING_RETURN)
    tr.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);

  bool any_position = false;
  bool all_protected = true;
  double tol = price_step * 0.5;
  bool attempted_modify = false;
  bool rate_limited = false;

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
    any_position = true;

    double cur_sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    double cur_sl_cmp = cur_sl;
    if (cur_sl_cmp > 0.0)
      cur_sl_cmp = NormalizeDouble(MathRound(cur_sl_cmp / price_step) * price_step, price_digits);
    double tp_req = tp;
    if (tp_req > 0.0)
      tp_req = NormalizeDouble(MathRound(tp_req / price_step) * price_step, price_digits);

    if (cur_sl_cmp > 0.0 && MathAbs(applied_sl - cur_sl_cmp) <= tol)
      continue;

    if (type == POSITION_TYPE_BUY)
    {
      if (cur_sl_cmp > 0.0 && applied_sl <= cur_sl_cmp + tol)
        continue;
    }
    else
    {
      if (cur_sl_cmp > 0.0 && applied_sl >= cur_sl_cmp - tol)
        continue;
    }

    if (cur_sl_cmp > 0.0 && freeze_dist > 0.0)
    {
      if (type == POSITION_TYPE_BUY && (tick.bid - cur_sl_cmp) <= (freeze_dist + tol))
        continue;
      if (type == POSITION_TYPE_SELL && (cur_sl_cmp - tick.ask) <= (freeze_dist + tol))
        continue;
    }

    bool modified = false;
    int attempts = 0;
    while (attempts <= state.params.close_retry_count)
    {
      MqlTick t_now;
      if (!SymbolInfoTick(symbol, t_now))
      {
        attempts++;
        continue;
      }
      double step_up = (double)(attempts * 2);
      double min_dist_now = stops_dist + (2.0 + step_up) * broker_point;
      double sl_try = applied_sl;
      if (type == POSITION_TYPE_BUY)
      {
        double max_sl_now = t_now.bid - min_dist_now;
        if (sl_try > max_sl_now)
          sl_try = max_sl_now;
        sl_try = MathFloor(sl_try / price_step) * price_step;
      }
      else
      {
        double min_sl_now = t_now.ask + min_dist_now;
        if (sl_try < min_sl_now)
          sl_try = min_sl_now;
        sl_try = MathCeil(sl_try / price_step) * price_step;
      }
      sl_try = NormalizeDouble(sl_try, price_digits);

      if (cur_sl_cmp > 0.0 && MathAbs(sl_try - cur_sl_cmp) <= tol)
      {
        modified = true;
        break;
      }

      attempted_modify = true;
      if (tr.PositionModify(ticket, sl_try, tp_req))
      {
        applied_sl = sl_try;
        modified = true;
        break;
      }
      uint retcode = tr.ResultRetcode();
      if (retcode == TRADE_RETCODE_TOO_MANY_REQUESTS)
      {
        rate_limited = true;
        break;
      }
      if (retcode == TRADE_RETCODE_INVALID_STOPS)
      {
        attempts++;
        if (attempts <= state.params.close_retry_count && state.params.close_retry_delay_ms > 0)
          Sleep(state.params.close_retry_delay_ms);
        continue;
      }
      attempts++;
      if (attempts <= state.params.close_retry_count && state.params.close_retry_delay_ms > 0)
        Sleep(state.params.close_retry_delay_ms);
    }

    if (rate_limited)
      break;

    if (!modified)
    {
      all_protected = false;
      PrintFormat("Trail SL update failed: %s ticket=%I64u type=%d sl=%.5f retcode=%d %s",
                  symbol, ticket, (int)type, applied_sl, tr.ResultRetcode(), tr.ResultRetcodeDescription());
    }
  }

  if (attempted_modify)
  {
    if (is_buy)
      state.buy_trail_sl_last_send_ms = now_ms;
    else
      state.sell_trail_sl_last_send_ms = now_ms;
  }

  if (rate_limited)
  {
    int cooldown_ms = state.params.trail_sl_rate_limit_cooldown_ms;
    if (cooldown_ms < min_interval_ms)
      cooldown_ms = min_interval_ms;
    if (cooldown_ms < 0)
      cooldown_ms = 0;
    ulong until_ms = now_ms + (ulong)cooldown_ms;
    if (is_buy)
      state.buy_trail_sl_cooldown_until_ms = until_ms;
    else
      state.sell_trail_sl_cooldown_until_ms = until_ms;
    PrintFormat("Trail SL rate limited: %s type=%d cooldown_ms=%d",
                symbol, (int)type, cooldown_ms);
    return true;
  }

  if (is_buy)
    state.buy_trail_sl_cooldown_until_ms = 0;
  else
    state.sell_trail_sl_cooldown_until_ms = 0;

  if (!any_position)
    return true;
  return all_protected;
}

bool TryOpen(const SymbolState &state,
             const string symbol,
             ENUM_ORDER_TYPE order_type,
             double lot,
             const string comment = "",
             int level = 0)
{
  double multiplier = 1.0;
  if (level == 1)
  {
    bool trend_side = (order_type == ORDER_TYPE_BUY && state.regime == REGIME_TREND_UP) ||
                      (order_type == ORDER_TYPE_SELL && state.regime == REGIME_TREND_DOWN);
    if (trend_side)
      multiplier = TrendLotMultiplierDynamic(state, order_type);
  }
  lot *= multiplier;
  lot = NormalizeLotCached(state, lot);
  if (lot <= 0.0)
    return false;
  trade.SetExpertMagicNumber(state.params.magic_number);
  trade.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
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

int RestartDelaySecondsDynamic(const NM3Params &params)
{
  int seconds = params.restart_delay_seconds;
  if (seconds < 0)
    seconds = 0;
  return seconds;
}

bool CanRestart(datetime last_close_time, int restart_delay_seconds)
{
  if (last_close_time == 0)
    return true;
  if (restart_delay_seconds < 0)
    restart_delay_seconds = 0;
  return (TimeCurrent() - last_close_time) >= restart_delay_seconds;
}

void CloseAllPositionsByMagic(const int magic)
{
  close_trade.SetExpertMagicNumber(magic);
  close_trade.SetDeviationInPoints(SlippagePoints);
  close_trade.SetAsyncMode(true);
  ulong tickets[];
  string position_symbols[];
  int count = 0;
  int total = PositionsTotal();
  if (total > 0)
  {
    ArrayResize(tickets, total);
    ArrayResize(position_symbols, total);
  }
  for (int i = total - 1; i >= 0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket))
      continue;
    if (PositionGetInteger(POSITION_MAGIC) != magic)
      continue;
    tickets[count] = ticket;
    position_symbols[count] = PositionGetString(POSITION_SYMBOL);
    count++;
  }
  if (count > 0)
  {
    ArrayResize(tickets, count);
    ArrayResize(position_symbols, count);
  }

  for (int i = 0; i < count; ++i)
  {
    bool closed = false;
    int attempts = 0;
    int filling = (int)SymbolInfoInteger(position_symbols[i], SYMBOL_FILLING_MODE);
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

bool CanNanpin(const NM3Params &params, datetime last_nanpin_time)
{
  if (last_nanpin_time == 0)
    return true;
  return (TimeCurrent() - last_nanpin_time) >= params.nanpin_sleep_seconds;
}

double SpreadPoints(const SymbolState &state, double bid, double ask)
{
  double spread = ask - bid;
  if (spread < 0.0)
    spread = 0.0;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  return spread / point;
}

bool IsSpreadAllowed(const NM3Params &params, double spread_points)
{
  if (params.max_spread_points <= 0.0)
    return true;
  return spread_points <= params.max_spread_points;
}

double FixedNanpinDistancePrice(const SymbolState &state)
{
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double distance = state.params.fixed_nanpin_width_points * point;
  if (distance < point)
    distance = point;
  return distance;
}

double ConfirmedAverageNanpinWidth(const BasketInfo &basket)
{
  if (basket.level_count < 2)
    return 0.0;
  double width = MathAbs(basket.max_price - basket.min_price);
  if (width <= 0.0)
    return 0.0;
  return width / (double)(basket.level_count - 1);
}

double BasketAbsoluteStopDistance(const SymbolState &state,
                                  const BasketInfo &basket,
                                  double fallback_step)
{
  if (basket.level_count <= 0)
    return 0.0;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double base_width = FixedNanpinDistancePrice(state);
  if (base_width <= 0.0)
    base_width = fallback_step;
  if (base_width <= 0.0)
    return 0.0;
  if (basket.level_count <= 1)
  {
    double multiplier = state.params.basket_loss_stop_nanpin_width_multiplier_level1;
    if (multiplier <= 0.0)
      return 0.0;
    double distance = base_width * multiplier;
    if (distance < point)
      distance = point;
    return distance;
  }
  double avg_width = ConfirmedAverageNanpinWidth(basket);
  if (avg_width <= 0.0)
    avg_width = fallback_step;
  if (avg_width <= 0.0)
    return 0.0;
  double multiplier = state.params.basket_loss_stop_nanpin_width_multiplier_level2_plus;
  if (multiplier <= 0.0)
    return 0.0;
  double distance = avg_width * multiplier;
  if (distance < point)
    distance = point;
  return distance;
}

void ResetBuyTakeProfitTrail(SymbolState &state)
{
  state.buy_take_profit_trailing_active = false;
  state.buy_take_profit_peak_price = 0.0;
}

void ResetSellTakeProfitTrail(SymbolState &state)
{
  state.sell_take_profit_trailing_active = false;
  state.sell_take_profit_bottom_price = 0.0;
}

double TakeProfitDistanceFromPoints(const SymbolState &state)
{
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double distance_points = state.params.take_profit_points;
  if (distance_points < 0.0)
    distance_points = 0.0;
  double distance = distance_points * point;
  if (distance < point)
    distance = point;
  return distance;
}

double TakeProfitTrailDistance(const SymbolState &state, double take_profit_distance)
{
  double distance = take_profit_distance * state.params.trailing_take_profit_distance_ratio;
  if (distance < 0.0)
    distance = 0.0;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  if (distance < point)
    distance = point;
  return distance;
}

double FixedTrailStartDistancePoints(const SymbolState &state)
{
  return FixedTrailStartPointsXAUUSD;
}

double FixedTrailStartDistancePrice(const SymbolState &state)
{
  if (!EnableFixedTrailStart)
    return 0.0;
  double distance_points = FixedTrailStartDistancePoints(state);
  if (distance_points <= 0.0)
    return 0.0;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  return distance_points * point;
}

bool FixedTrailStartReachedBuy(const SymbolState &state, const BasketInfo &buy, double bid)
{
  double distance = FixedTrailStartDistancePrice(state);
  if (distance <= 0.0)
    return false;
  return bid >= (buy.avg_price + distance);
}

bool FixedTrailStartReachedSell(const SymbolState &state, const BasketInfo &sell, double ask)
{
  double distance = FixedTrailStartDistancePrice(state);
  if (distance <= 0.0)
    return false;
  return ask <= (sell.avg_price - distance);
}

bool DeepLevelProfitTrailStartReached(const BasketInfo &basket, int combined_profit_close_level)
{
  return (basket.level_count >= combined_profit_close_level && basket.profit > 0.0);
}

double DeepLevelTrailLockDistancePrice(const SymbolState &state)
{
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  double lock_distance = point * NM3::kDeepLevelTrailLockPoints;
  if (lock_distance < 0.0)
    lock_distance = 0.0;
  return lock_distance;
}

double TakeProfitTrailDistanceCapped(const SymbolState &state, double take_profit_distance)
{
  double trail_distance = TakeProfitTrailDistance(state, take_profit_distance);
  if (!EnableTakeProfitTrailDistanceCap)
    return trail_distance;
  double cap_ratio = FixedTrailDistanceCapRatio;
  if (cap_ratio <= 0.0)
    return trail_distance;
  double fixed_start_distance = FixedTrailStartDistancePrice(state);
  if (fixed_start_distance <= 0.0)
    return trail_distance;
  double cap_distance = fixed_start_distance * cap_ratio;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  if (cap_distance < point)
    cap_distance = point;
  return MathMin(trail_distance, cap_distance);
}

bool ShouldCloseBuyTakeProfit(const SymbolState &state, const BasketInfo &buy, double bid, double take_profit_distance)
{
  double target = buy.avg_price + take_profit_distance;
  return bid >= target;
}

bool ShouldCloseSellTakeProfit(const SymbolState &state, const BasketInfo &sell, double ask, double take_profit_distance)
{
  double target = sell.avg_price - take_profit_distance;
  return ask <= target;
}

bool ResolveDeepRunnerRevisitPrices(const SymbolState &state,
                                    ENUM_POSITION_TYPE type,
                                    int deepest_level,
                                    ulong deepest_ticket,
                                    double &rebound_price,
                                    double &deep_price)
{
  rebound_price = 0.0;
  deep_price = 0.0;
  if (deepest_level < 3 || deepest_level > NM3::kMaxLevels)
    return false;

  int deep_index = deepest_level - 1;
  int rebound_index = deep_index - 1;
  if (type == POSITION_TYPE_BUY)
  {
    rebound_price = state.buy_level_price[rebound_index];
    deep_price = state.buy_level_price[deep_index];
  }
  else if (type == POSITION_TYPE_SELL)
  {
    rebound_price = state.sell_level_price[rebound_index];
    deep_price = state.sell_level_price[deep_index];
  }
  else
  {
    return false;
  }

  if (deep_price <= 0.0 && deepest_ticket > 0 && PositionSelectByTicket(deepest_ticket))
    deep_price = PositionGetDouble(POSITION_PRICE_OPEN);

  if (rebound_price <= 0.0 && deep_price > 0.0)
  {
    double fallback_step = 0.0;
    if (type == POSITION_TYPE_BUY)
      fallback_step = state.buy_grid_step;
    else
      fallback_step = state.sell_grid_step;
    if (fallback_step > 0.0)
    {
      if (type == POSITION_TYPE_BUY)
        rebound_price = deep_price + fallback_step;
      else
        rebound_price = deep_price - fallback_step;
    }
  }

  if (rebound_price <= 0.0 || deep_price <= 0.0)
    return false;
  double point = state.point;
  if (point <= 0.0)
    point = 0.00001;
  if (MathAbs(rebound_price - deep_price) <= (point * 0.5))
    return false;
  return true;
}

bool ManageBuyTakeProfit(SymbolState &state, const BasketInfo &buy, double bid, double take_profit_distance)
{
  if (buy.count <= 0 || buy.basket_id <= 0 || buy.avg_price <= 0.0)
    return false;
  bool tp_reached = ShouldCloseBuyTakeProfit(state, buy, bid, take_profit_distance);
  if (!tp_reached)
    return false;

  if (!state.params.trailing_take_profit || buy.deepest_ticket == 0)
  {
    PrintFormat("Basket TP close: %s BUY basket=%d deepest_level=%d",
                state.broker_symbol, buy.basket_id, buy.deepest_level);
    bool closed_all = CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
    if (!closed_all)
      return false;
    state.buy_active_basket_id = 0;
    state.buy_close_as_completed = true;
    ResetBuyTakeProfitTrail(state);
    return true;
  }

  bool closed_non_deep = CloseBasketPositionsExceptTicket(state, POSITION_TYPE_BUY, buy.basket_id, buy.deepest_ticket, "basket_target");
  if (!closed_non_deep)
    return false;
  double revisit_rebound_price = 0.0;
  double revisit_deep_price = 0.0;
  bool has_deep_revisit_rule = false;
  if (state.params.enable_deep_runner_revisit_take_profit)
  {
    has_deep_revisit_rule = ResolveDeepRunnerRevisitPrices(state, POSITION_TYPE_BUY, buy.deepest_level,
                                                           buy.deepest_ticket, revisit_rebound_price, revisit_deep_price);
  }
  double trail_distance = TakeProfitTrailDistanceCapped(state, take_profit_distance);
  if (state.params.use_take_profit_trail_sl)
  {
    if (trail_distance <= 0.0)
    {
      PrintFormat("Basket TP split close deferred: %s BUY basket=%d keep_ticket=%I64u reason=invalid_trail_distance",
                  state.broker_symbol, buy.basket_id, buy.deepest_ticket);
      return false;
    }
    if (!PositionSelectByTicket(buy.deepest_ticket))
    {
      PrintFormat("Basket TP split close deferred: %s BUY basket=%d keep_ticket=%I64u reason=keep_ticket_not_found",
                  state.broker_symbol, buy.basket_id, buy.deepest_ticket);
      return false;
    }
    double requested_stop = bid - trail_distance;
    RemoveRunnerTrailTicket(buy.deepest_ticket);
    if (!UpdatePositionTrailSL(state, buy.deepest_ticket, POSITION_TYPE_BUY, requested_stop))
    {
      PrintFormat("Basket TP split close fallback close: %s BUY basket=%d keep_ticket=%I64u reason=trail_sl_update_failed",
                  state.broker_symbol, buy.basket_id, buy.deepest_ticket);
      bool is_l1_l2_only = (buy.count <= 2 && buy.level_count <= 2);
      if (is_l1_l2_only)
      {
        PrintFormat("Basket TP split keep alive: %s BUY basket=%d keep_ticket=%I64u reason=trail_sl_update_failed_l2_or_less",
                    state.broker_symbol, buy.basket_id, buy.deepest_ticket);
        return false;
      }
      bool fallback_closed = CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
      if (!fallback_closed)
      {
        PrintFormat("Basket TP split fallback close failed: %s BUY basket=%d keep_ticket=%I64u",
                    state.broker_symbol, buy.basket_id, buy.deepest_ticket);
        return false;
      }
      state.buy_close_as_completed = false;
      state.buy_active_basket_id = 0;
      ResetBuyTakeProfitTrail(state);
      return true;
    }
  }
  else
  {
    if (trail_distance > 0.0 && PositionSelectByTicket(buy.deepest_ticket))
    {
      double requested_stop = bid - trail_distance;
      ClearPositionSL(state, buy.deepest_ticket, POSITION_TYPE_BUY);
      UpsertRunnerTrailStop(buy.deepest_ticket, POSITION_TYPE_BUY, requested_stop);
    }
  }
  PrintFormat("Basket TP split close: %s BUY basket=%d keep_ticket=%I64u deepest_level=%d",
              state.broker_symbol, buy.basket_id, buy.deepest_ticket, buy.deepest_level);
  if (has_deep_revisit_rule)
  {
    UpsertRunnerRevisitState(buy.deepest_ticket, POSITION_TYPE_BUY, revisit_rebound_price, revisit_deep_price);
    // Keep this basket active so additional nanpin can continue from the remaining deep runner.
    state.buy_active_basket_id = buy.basket_id;
    state.buy_close_as_completed = false;
  }
  else
  {
    RemoveRunnerRevisitTicket(buy.deepest_ticket);
    AddCompletedBasket(state, POSITION_TYPE_BUY, buy.basket_id);
    state.buy_active_basket_id = 0;
    state.buy_close_as_completed = true;
  }
  ResetBuyTakeProfitTrail(state);
  return true;
}

bool ManageSellTakeProfit(SymbolState &state, const BasketInfo &sell, double ask, double take_profit_distance)
{
  if (sell.count <= 0 || sell.basket_id <= 0 || sell.avg_price <= 0.0)
    return false;
  bool tp_reached = ShouldCloseSellTakeProfit(state, sell, ask, take_profit_distance);
  if (!tp_reached)
    return false;

  if (!state.params.trailing_take_profit || sell.deepest_ticket == 0)
  {
    PrintFormat("Basket TP close: %s SELL basket=%d deepest_level=%d",
                state.broker_symbol, sell.basket_id, sell.deepest_level);
    bool closed_all = CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
    if (!closed_all)
      return false;
    state.sell_active_basket_id = 0;
    state.sell_close_as_completed = true;
    ResetSellTakeProfitTrail(state);
    return true;
  }

  bool closed_non_deep = CloseBasketPositionsExceptTicket(state, POSITION_TYPE_SELL, sell.basket_id, sell.deepest_ticket, "basket_target");
  if (!closed_non_deep)
    return false;
  double revisit_rebound_price = 0.0;
  double revisit_deep_price = 0.0;
  bool has_deep_revisit_rule = false;
  if (state.params.enable_deep_runner_revisit_take_profit)
  {
    has_deep_revisit_rule = ResolveDeepRunnerRevisitPrices(state, POSITION_TYPE_SELL, sell.deepest_level,
                                                           sell.deepest_ticket, revisit_rebound_price, revisit_deep_price);
  }
  double trail_distance = TakeProfitTrailDistanceCapped(state, take_profit_distance);
  if (state.params.use_take_profit_trail_sl)
  {
    if (trail_distance <= 0.0)
    {
      PrintFormat("Basket TP split close deferred: %s SELL basket=%d keep_ticket=%I64u reason=invalid_trail_distance",
                  state.broker_symbol, sell.basket_id, sell.deepest_ticket);
      return false;
    }
    if (!PositionSelectByTicket(sell.deepest_ticket))
    {
      PrintFormat("Basket TP split close deferred: %s SELL basket=%d keep_ticket=%I64u reason=keep_ticket_not_found",
                  state.broker_symbol, sell.basket_id, sell.deepest_ticket);
      return false;
    }
    double requested_stop = ask + trail_distance;
    RemoveRunnerTrailTicket(sell.deepest_ticket);
    if (!UpdatePositionTrailSL(state, sell.deepest_ticket, POSITION_TYPE_SELL, requested_stop))
    {
      PrintFormat("Basket TP split close fallback close: %s SELL basket=%d keep_ticket=%I64u reason=trail_sl_update_failed",
                  state.broker_symbol, sell.basket_id, sell.deepest_ticket);
      bool is_l1_l2_only = (sell.count <= 2 && sell.level_count <= 2);
      if (is_l1_l2_only)
      {
        PrintFormat("Basket TP split keep alive: %s SELL basket=%d keep_ticket=%I64u reason=trail_sl_update_failed_l2_or_less",
                    state.broker_symbol, sell.basket_id, sell.deepest_ticket);
        return false;
      }
      bool fallback_closed = CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
      if (!fallback_closed)
      {
        PrintFormat("Basket TP split fallback close failed: %s SELL basket=%d keep_ticket=%I64u",
                    state.broker_symbol, sell.basket_id, sell.deepest_ticket);
        return false;
      }
      state.sell_close_as_completed = false;
      state.sell_active_basket_id = 0;
      ResetSellTakeProfitTrail(state);
      return true;
    }
  }
  else
  {
    if (trail_distance > 0.0 && PositionSelectByTicket(sell.deepest_ticket))
    {
      double requested_stop = ask + trail_distance;
      ClearPositionSL(state, sell.deepest_ticket, POSITION_TYPE_SELL);
      UpsertRunnerTrailStop(sell.deepest_ticket, POSITION_TYPE_SELL, requested_stop);
    }
  }
  PrintFormat("Basket TP split close: %s SELL basket=%d keep_ticket=%I64u deepest_level=%d",
              state.broker_symbol, sell.basket_id, sell.deepest_ticket, sell.deepest_level);
  if (has_deep_revisit_rule)
  {
    UpsertRunnerRevisitState(sell.deepest_ticket, POSITION_TYPE_SELL, revisit_rebound_price, revisit_deep_price);
    // Keep this basket active so additional nanpin can continue from the remaining deep runner.
    state.sell_active_basket_id = sell.basket_id;
    state.sell_close_as_completed = false;
  }
  else
  {
    RemoveRunnerRevisitTicket(sell.deepest_ticket);
    AddCompletedBasket(state, POSITION_TYPE_SELL, sell.basket_id);
    state.sell_active_basket_id = 0;
    state.sell_close_as_completed = true;
  }
  ResetSellTakeProfitTrail(state);
  return true;
}

void ProcessSymbolTick(SymbolState &state)
{
  if (!state.enabled)
    return;
  string symbol = state.broker_symbol;
  NM3Params params = state.params;
  BasketInfo buy, sell;
  RefreshBasketSequenceState(state);
  CollectBasketInfo(state, state.buy_active_basket_id, state.sell_active_basket_id, buy, sell);
  int levels = EffectiveMaxLevelsRuntime(state);
  MqlTick t;
  if (!SymbolInfoTick(symbol, t))
    return;
  if ((long)TimeCurrent() - (long)t.time > 2)
    return;
  if (t.bid <= 0.0 || t.ask <= 0.0 || t.ask < t.bid)
    return;
  double bid = t.bid;
  double ask = t.ask;
  double spread_points = SpreadPoints(state, bid, ask);
  bool spread_ok = IsSpreadAllowed(params, spread_points);
  datetime now = TimeCurrent();
  if (state.buy_order_pending)
  {
    if (buy.count > state.prev_buy_count)
      state.buy_order_pending = false;
    else if (state.buy_order_pending_time > 0
             && (now - state.buy_order_pending_time) >= params.order_pending_timeout_seconds)
      state.buy_order_pending = false;
  }
  if (state.sell_order_pending)
  {
    if (sell.count > state.prev_sell_count)
      state.sell_order_pending = false;
    else if (state.sell_order_pending_time > 0
             && (now - state.sell_order_pending_time) >= params.order_pending_timeout_seconds)
      state.sell_order_pending = false;
  }
  if (buy.count != state.prev_buy_count)
    ResetBuyTakeProfitTrail(state);
  if (sell.count != state.prev_sell_count)
    ResetSellTakeProfitTrail(state);
  bool adx_h1_stop_enabled = (params.enable_adx_h1_hard_stop || params.enable_adx_h1_rising_hard_stop);
  if (adx_h1_stop_enabled)
  {
    double adx_h1_current = 0.0;
    double adx_h1_previous = 0.0;
    bool has_adx_h1 = GetAdxH1Snapshot(state, adx_h1_current, adx_h1_previous);
    bool threshold_stop = (params.enable_adx_h1_hard_stop
                           && has_adx_h1
                           && adx_h1_current >= NM3::kAdxH1HardStopThreshold);
    bool rising_stop = (params.enable_adx_h1_rising_hard_stop
                        && has_adx_h1
                        && adx_h1_current > adx_h1_previous);
    bool hard_stop = (threshold_stop || rising_stop);
    if (hard_stop)
    {
      if (!state.adx_h1_hard_stop_active)
      {
        state.adx_h1_hard_stop_active = true;
        PrintFormat("ADX H1 hard stop ON: %s current=%.2f previous=%.2f threshold_stop=%s rising_stop=%s threshold=%.2f",
                    symbol, adx_h1_current, adx_h1_previous,
                    threshold_stop ? "true" : "false",
                    rising_stop ? "true" : "false",
                    NM3::kAdxH1HardStopThreshold);
      }
      state.prev_buy_count = buy.count;
      state.prev_sell_count = sell.count;
      return;
    }
    if (state.adx_h1_hard_stop_active)
    {
      state.adx_h1_hard_stop_active = false;
      if (has_adx_h1)
      {
        PrintFormat("ADX H1 hard stop OFF: %s current=%.2f previous=%.2f threshold=%.2f",
                    symbol, adx_h1_current, adx_h1_previous, NM3::kAdxH1HardStopThreshold);
      }
      else
      {
        PrintFormat("ADX H1 hard stop OFF: %s adx_h1=n/a threshold=%.2f",
                    symbol, NM3::kAdxH1HardStopThreshold);
      }
    }
  }
  else if (state.adx_h1_hard_stop_active)
  {
    state.adx_h1_hard_stop_active = false;
    PrintFormat("ADX H1 hard stop OFF: %s disabled by parameters threshold=%.2f",
                symbol, NM3::kAdxH1HardStopThreshold);
  }
  if (DebugMode)
  {
    string regime_name = RegimeName(state.regime);
    bool regime_changed = (state.last_debug_regime != (int)state.regime);
    if (regime_changed)
    {
      DebugLog(state, StringFormat("REGIME=%s", regime_name));
      state.last_debug_regime = (int)state.regime;
    }
  }
  double take_profit_distance = TakeProfitDistanceFromPoints(state);
  bool news_blocked = IsNewsTimeNow();
  bool is_trading_time = IsTradingTime() && !news_blocked;
  int nanpin_levels = EffectiveNanpinLevelsRuntime(state, is_trading_time);
  double grid_step = FixedNanpinDistancePrice(state);
  double value_per_unit = PriceValuePerUnitCached(state);
  datetime confirmed_bar_time = iTime(state.broker_symbol, _Period, 1);
  int restart_delay_dynamic_seconds = RestartDelaySecondsDynamic(params);
  double adx_now = 0.0;
  double adx_prev = 0.0;
  double di_plus_now = 0.0;
  double di_plus_prev = 0.0;
  double di_minus_now = 0.0;
  double di_minus_prev = 0.0;
  bool has_adx = GetAdxSnapshot(state, adx_now, adx_prev, di_plus_now, di_plus_prev, di_minus_now, di_minus_prev);
  bool balance_guard_enabled = params.enable_balance_guard && params.min_account_balance > 0.0;
  double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
  bool low_balance = balance_guard_enabled && account_balance <= params.min_account_balance;
  if (state.low_balance_active != low_balance)
  {
    state.low_balance_active = low_balance;
    string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
    if (low_balance)
    {
      PrintFormat("Balance guard ON: %s (%s) balance=%.2f threshold=%.2f",
                  ts, symbol, account_balance, params.min_account_balance);
    }
    else
    {
      PrintFormat("Balance guard OFF: %s (%s) balance=%.2f threshold=%.2f",
                  ts, symbol, account_balance, params.min_account_balance);
    }
  }
  if (low_balance && params.close_positions_on_low_balance)
  {
    if (HasOpenPositionByType(state, POSITION_TYPE_BUY))
      CloseBasket(state, POSITION_TYPE_BUY);
    if (HasOpenPositionByType(state, POSITION_TYPE_SELL))
      CloseBasket(state, POSITION_TYPE_SELL);
  }
  int combined_profit_close_level = EffectiveCombinedProfitCloseLevel(state);
  bool combined_profit_close_enabled = params.combined_profit_close_nanpin_width_multiplier > 0.0;
  bool has_deep_level = (buy.level_count >= combined_profit_close_level
                         || sell.level_count >= combined_profit_close_level);
  if (combined_profit_close_enabled && has_deep_level)
  {
    double total_profit = buy.profit + sell.profit;
    double total_volume = buy.volume + sell.volume;
    double threshold_distance = grid_step * params.combined_profit_close_nanpin_width_multiplier;
    if (threshold_distance > 0.0 && total_volume > 0.0 && value_per_unit > 0.0)
    {
      double threshold_profit = total_volume * threshold_distance * value_per_unit;
      if (total_profit >= threshold_profit)
      {
        PrintFormat("Combined profit close triggered: %s level_trigger=%d total_profit=%.2f threshold=%.2f width=%.5f width_mult=%.3f",
                    symbol, combined_profit_close_level, total_profit, threshold_profit,
                    grid_step, params.combined_profit_close_nanpin_width_multiplier);
        CloseAllPositionsByMagic(params.magic_number);
        state.prev_buy_count = buy.count;
        state.prev_sell_count = sell.count;
        return;
      }
    }
  }
  bool basket_loss_closed = false;
  bool basket_loss_stop_enabled = params.enable_basket_loss_stop;
  if (basket_loss_stop_enabled && !(low_balance && params.close_positions_on_low_balance))
  {
    double point = state.point;
    if (point <= 0.0)
      point = 0.00001;
    double tol = point * 0.5;
    double loss_points_tol = 0.5;
    if (buy.count > 0)
    {
      double loss_points_threshold = BasketLossStopPointsThresholdForLevel(params, buy.level_count);
      if (loss_points_threshold > 0.0 && buy.basket_id > 0)
      {
        double current_loss_points = BasketTotalLossPoints(state, POSITION_TYPE_BUY, buy.basket_id, bid, ask);
        if (current_loss_points + loss_points_tol >= loss_points_threshold)
        {
          PrintFormat("Absolute basket stop triggered (loss_points): %s BUY level=%d basket=%d loss_points=%.1f threshold=%.1f",
                      symbol, buy.level_count, buy.basket_id, current_loss_points, loss_points_threshold);
          if (buy.basket_id > 0)
            CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
          basket_loss_closed = true;
        }
      }
      else if (buy.avg_price > 0.0)
      {
        double stop_distance = BasketAbsoluteStopDistance(state, buy, state.buy_grid_step);
        if (stop_distance > 0.0)
        {
          double stop_price = buy.avg_price - stop_distance;
          if (bid <= stop_price + tol)
          {
            if (buy.level_count <= 1)
            {
              PrintFormat("Absolute basket stop triggered: %s BUY level=%d bid=%.5f avg=%.5f stop=%.5f dist=%.5f rule=WIDTHx%.2f",
                          symbol, buy.level_count, bid, buy.avg_price, stop_price, stop_distance,
                          params.basket_loss_stop_nanpin_width_multiplier_level1);
            }
            else
            {
              double avg_width = ConfirmedAverageNanpinWidth(buy);
              if (avg_width <= 0.0)
                avg_width = state.buy_grid_step;
              PrintFormat("Absolute basket stop triggered: %s BUY level=%d bid=%.5f avg=%.5f stop=%.5f dist=%.5f avg_width=%.5f rule=WIDTHx%.2f",
                          symbol, buy.level_count, bid, buy.avg_price, stop_price, stop_distance, avg_width,
                          params.basket_loss_stop_nanpin_width_multiplier_level2_plus);
            }
            if (buy.basket_id > 0)
              CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
            basket_loss_closed = true;
          }
        }
      }
    }
    if (sell.count > 0)
    {
      double loss_points_threshold = BasketLossStopPointsThresholdForLevel(params, sell.level_count);
      if (loss_points_threshold > 0.0 && sell.basket_id > 0)
      {
        double current_loss_points = BasketTotalLossPoints(state, POSITION_TYPE_SELL, sell.basket_id, bid, ask);
        if (current_loss_points + loss_points_tol >= loss_points_threshold)
        {
          PrintFormat("Absolute basket stop triggered (loss_points): %s SELL level=%d basket=%d loss_points=%.1f threshold=%.1f",
                      symbol, sell.level_count, sell.basket_id, current_loss_points, loss_points_threshold);
          if (sell.basket_id > 0)
            CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
          basket_loss_closed = true;
        }
      }
      else if (sell.avg_price > 0.0)
      {
        double stop_distance = BasketAbsoluteStopDistance(state, sell, state.sell_grid_step);
        if (stop_distance > 0.0)
        {
          double stop_price = sell.avg_price + stop_distance;
          if (ask >= stop_price - tol)
          {
            if (sell.level_count <= 1)
            {
              PrintFormat("Absolute basket stop triggered: %s SELL level=%d ask=%.5f avg=%.5f stop=%.5f dist=%.5f rule=WIDTHx%.2f",
                          symbol, sell.level_count, ask, sell.avg_price, stop_price, stop_distance,
                          params.basket_loss_stop_nanpin_width_multiplier_level1);
            }
            else
            {
              double avg_width = ConfirmedAverageNanpinWidth(sell);
              if (avg_width <= 0.0)
                avg_width = state.sell_grid_step;
              PrintFormat("Absolute basket stop triggered: %s SELL level=%d ask=%.5f avg=%.5f stop=%.5f dist=%.5f avg_width=%.5f rule=WIDTHx%.2f",
                          symbol, sell.level_count, ask, sell.avg_price, stop_price, stop_distance, avg_width,
                          params.basket_loss_stop_nanpin_width_multiplier_level2_plus);
            }
            if (sell.basket_id > 0)
              CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
            basket_loss_closed = true;
          }
        }
      }
    }
  }
  if (basket_loss_closed)
  {
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }
  if (!is_trading_time)
  {
    double threshold_distance = -0.5 * take_profit_distance;
    if (buy.count > 0)
    {
      bool should_close = false;
      if (value_per_unit > 0.0)
      {
        double threshold_profit = buy.volume * threshold_distance * value_per_unit;
        should_close = buy.profit >= threshold_profit;
      }
      else
      {
        should_close = (bid - buy.avg_price) >= threshold_distance;
      }
      if (should_close)
      {
        if (buy.basket_id > 0)
          CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
      }
    }
    if (sell.count > 0)
    {
      bool should_close = false;
      if (value_per_unit > 0.0)
      {
        double threshold_profit = sell.volume * threshold_distance * value_per_unit;
        should_close = sell.profit >= threshold_profit;
      }
      else
      {
        should_close = (sell.avg_price - ask) >= threshold_distance;
      }
      if (should_close)
      {
        if (sell.basket_id > 0)
          CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
      }
    }
  }

  if (state.prev_buy_count > 0 && buy.count == 0)
  {
    if (state.buy_close_as_completed)
      state.last_buy_close_time = 0;
    else
      state.last_buy_close_time = TimeCurrent();
    state.buy_close_as_completed = false;
    state.last_buy_nanpin_time = 0;
    ResetBuyTakeProfitTrail(state);
    state.buy_stop_active = false;
    state.buy_skip_levels = 0;
    state.buy_skip_distance = 0.0;
    state.buy_skip_price = 0.0;
    ClearLevelPrices(state.buy_level_price);
    state.buy_grid_step = 0.0;
    state.buy_open_time = 0;
    state.buy_deepest_entry_time = 0;
  }
  if (state.prev_sell_count > 0 && sell.count == 0)
  {
    if (state.sell_close_as_completed)
      state.last_sell_close_time = 0;
    else
      state.last_sell_close_time = TimeCurrent();
    state.sell_close_as_completed = false;
    state.last_sell_nanpin_time = 0;
    ResetSellTakeProfitTrail(state);
    state.sell_stop_active = false;
    state.sell_skip_levels = 0;
    state.sell_skip_distance = 0.0;
    state.sell_skip_price = 0.0;
    ClearLevelPrices(state.sell_level_price);
    state.sell_grid_step = 0.0;
    state.sell_open_time = 0;
    state.sell_deepest_entry_time = 0;
  }
  if (state.prev_buy_count == 0 && buy.count > 0)
  {
    state.buy_open_time = TimeCurrent();
    state.buy_close_as_completed = false;
  }
  if (state.prev_sell_count == 0 && sell.count > 0)
  {
    state.sell_open_time = TimeCurrent();
    state.sell_close_as_completed = false;
  }

  if (buy.count > 0 || sell.count > 0)
    SyncLevelPricesFromPositions(state, buy.basket_id, sell.basket_id);

  int timed_exit_level = levels;
  if (buy.level_count >= timed_exit_level)
  {
    if (state.buy_deepest_entry_time == 0)
      state.buy_deepest_entry_time = now;
  }
  else
  {
    state.buy_deepest_entry_time = 0;
  }
  if (sell.level_count >= timed_exit_level)
  {
    if (state.sell_deepest_entry_time == 0)
      state.sell_deepest_entry_time = now;
  }
  else
  {
    state.sell_deepest_entry_time = 0;
  }

  int timed_exit_minutes = NM3::kTimedExitMinutes;
  int timed_exit_seconds = timed_exit_minutes * 60;
  bool timed_exit_closed = false;
  if (buy.count > 0 && state.buy_deepest_entry_time > 0
      && (now - state.buy_deepest_entry_time) >= timed_exit_seconds)
  {
    PrintFormat("Timed exit triggered: %s BUY reached level %d for %d minutes",
                symbol, timed_exit_level, timed_exit_minutes);
    if (buy.basket_id > 0)
      CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
    timed_exit_closed = true;
  }
  if (sell.count > 0 && state.sell_deepest_entry_time > 0
      && (now - state.sell_deepest_entry_time) >= timed_exit_seconds)
  {
    PrintFormat("Timed exit triggered: %s SELL reached level %d for %d minutes",
                symbol, timed_exit_level, timed_exit_minutes);
    if (sell.basket_id > 0)
      CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
    timed_exit_closed = true;
  }
  if (timed_exit_closed)
  {
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }

  bool attempted_initial = false;
  const bool allow_entry_buy = (state.regime != REGIME_TREND_DOWN);
  const bool allow_entry_sell = (state.regime != REGIME_TREND_UP);
  if (!state.initial_started && (TimeCurrent() - state.start_time) >= params.start_delay_seconds)
  {
    if (buy.count == 0 && sell.count == 0 && is_trading_time && !low_balance && spread_ok)
    {
      bool opened_buy = false;
      bool opened_sell = false;
      if (params.enable_hedged_entry)
      {
        if (!state.buy_order_pending && allow_entry_buy)
        {
          if (CanStartNewBasket(state, ORDER_TYPE_BUY, bid, ask, take_profit_distance, now))
          {
            int basket_id = (state.buy_active_basket_id > 0) ? state.buy_active_basket_id : NextBasketId(state);
            opened_buy = TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
            if (opened_buy)
            {
              CommitBasketId(state, POSITION_TYPE_BUY, basket_id);
              state.buy_order_pending = true;
              state.buy_order_pending_time = now;
              if (state.buy_level_price[0] <= 0.0)
                state.buy_level_price[0] = ask;
            }
          }
        }
        if (!state.sell_order_pending && allow_entry_sell)
        {
          if (CanStartNewBasket(state, ORDER_TYPE_SELL, bid, ask, take_profit_distance, now))
          {
            int basket_id = (state.sell_active_basket_id > 0) ? state.sell_active_basket_id : NextBasketId(state);
            opened_sell = TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
            if (opened_sell)
            {
              CommitBasketId(state, POSITION_TYPE_SELL, basket_id);
              state.sell_order_pending = true;
              state.sell_order_pending_time = now;
              if (state.sell_level_price[0] <= 0.0)
                state.sell_level_price[0] = bid;
            }
          }
        }
      }
      else
      {
        int dir = SelectSingleEntryDirection(state, allow_entry_buy, allow_entry_sell, has_adx, di_plus_now, di_minus_now);
        if (dir > 0 && !state.buy_order_pending)
        {
          if (CanStartNewBasket(state, ORDER_TYPE_BUY, bid, ask, take_profit_distance, now))
          {
            int basket_id = (state.buy_active_basket_id > 0) ? state.buy_active_basket_id : NextBasketId(state);
            opened_buy = TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
            if (opened_buy)
            {
              CommitBasketId(state, POSITION_TYPE_BUY, basket_id);
              state.buy_order_pending = true;
              state.buy_order_pending_time = now;
              if (state.buy_level_price[0] <= 0.0)
                state.buy_level_price[0] = ask;
            }
          }
        }
        else if (dir < 0 && !state.sell_order_pending)
        {
          if (CanStartNewBasket(state, ORDER_TYPE_SELL, bid, ask, take_profit_distance, now))
          {
            int basket_id = (state.sell_active_basket_id > 0) ? state.sell_active_basket_id : NextBasketId(state);
            opened_sell = TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
            if (opened_sell)
            {
              CommitBasketId(state, POSITION_TYPE_SELL, basket_id);
              state.sell_order_pending = true;
              state.sell_order_pending_time = now;
              if (state.sell_level_price[0] <= 0.0)
                state.sell_level_price[0] = bid;
            }
          }
        }
      }
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

  grid_step = FixedNanpinDistancePrice(state);
  if (buy.count > 0)
    state.buy_grid_step = grid_step;
  if (sell.count > 0)
    state.sell_grid_step = grid_step;

  bool allow_nanpin = !low_balance && !news_blocked;


  bool allow_buy_trigger = allow_nanpin;
  bool allow_sell_trigger = allow_nanpin;
  bool buy_stop = false;
  bool sell_stop = false;
  if (has_adx)
    UpdateRegime(state, adx_now, di_plus_now, di_minus_now, confirmed_bar_time);
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

  bool final_level_sl_closed = false;
  if (nanpin_levels >= 2 && buy.count > 0 && buy.level_count >= nanpin_levels)
  {
    double base_step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
    int next_level_index = nanpin_levels;
    double stop_step = base_step * LevelStepFactor(params, next_level_index + 1);
    stop_step = AdjustNanpinStep(state.buy_level_price, next_level_index, stop_step, false);
    double base_price = state.buy_level_price[nanpin_levels - 1];
    if (base_price <= 0.0)
      base_price = buy.min_price;
    double point = state.point;
    if (point <= 0.0)
      point = 0.00001;
    double tol = point * 0.5;
    if (stop_step > 0.0 && base_price > 0.0)
    {
      double stop_price = base_price - stop_step;
      if (ask <= stop_price + tol)
      {
        PrintFormat("Final level stop-loss triggered: %s BUY level=%d max_levels=%d nanpin_levels=%d is_trading_time=%s ask=%.5f stop=%.5f",
                    symbol, buy.level_count, levels, nanpin_levels, is_trading_time ? "true" : "false", ask, stop_price);
        if (buy.basket_id > 0)
          CloseBasketById(state, POSITION_TYPE_BUY, buy.basket_id);
        final_level_sl_closed = true;
      }
    }
  }
  if (nanpin_levels >= 2 && sell.count > 0 && sell.level_count >= nanpin_levels)
  {
    double base_step = state.sell_grid_step > 0.0 ? state.sell_grid_step : grid_step;
    int next_level_index = nanpin_levels;
    double stop_step = base_step * LevelStepFactor(params, next_level_index + 1);
    stop_step = AdjustNanpinStep(state.sell_level_price, next_level_index, stop_step, false);
    double base_price = state.sell_level_price[nanpin_levels - 1];
    if (base_price <= 0.0)
      base_price = sell.max_price;
    double point = state.point;
    if (point <= 0.0)
      point = 0.00001;
    double tol = point * 0.5;
    if (stop_step > 0.0 && base_price > 0.0)
    {
      double stop_price = base_price + stop_step;
      if (bid >= stop_price - tol)
      {
        PrintFormat("Final level stop-loss triggered: %s SELL level=%d max_levels=%d nanpin_levels=%d is_trading_time=%s bid=%.5f stop=%.5f",
                    symbol, sell.level_count, levels, nanpin_levels, is_trading_time ? "true" : "false", bid, stop_price);
        if (sell.basket_id > 0)
          CloseBasketById(state, POSITION_TYPE_SELL, sell.basket_id);
        final_level_sl_closed = true;
      }
    }
  }
  if (final_level_sl_closed)
  {
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }

  bool tp_closed = false;
  if (buy.count > 0)
  {
    if (ManageBuyTakeProfit(state, buy, bid, take_profit_distance))
      tp_closed = true;
  }
  else
  {
    ResetBuyTakeProfitTrail(state);
  }

  if (sell.count > 0)
  {
    if (ManageSellTakeProfit(state, sell, ask, take_profit_distance))
      tp_closed = true;
  }
  else
  {
    ResetSellTakeProfitTrail(state);
  }

  if (tp_closed)
  {
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }

  bool deep_revisit_closed = false;
  if (params.enable_deep_runner_revisit_take_profit)
  {
    if (buy.count == 1 && buy.basket_id > 0 && buy.deepest_ticket > 0
        && state.buy_active_basket_id == buy.basket_id)
    {
      if (ShouldCloseRunnerByRevisit(state, buy.deepest_ticket, POSITION_TYPE_BUY, bid))
        deep_revisit_closed = true;
    }
    else if (buy.count > 1 && buy.basket_id > 0)
    {
      RemoveRunnerRevisitForBasket(state, POSITION_TYPE_BUY, buy.basket_id);
    }

    if (sell.count == 1 && sell.basket_id > 0 && sell.deepest_ticket > 0
        && state.sell_active_basket_id == sell.basket_id)
    {
      if (ShouldCloseRunnerByRevisit(state, sell.deepest_ticket, POSITION_TYPE_SELL, ask))
        deep_revisit_closed = true;
    }
    else if (sell.count > 1 && sell.basket_id > 0)
    {
      RemoveRunnerRevisitForBasket(state, POSITION_TYPE_SELL, sell.basket_id);
    }
  }
  if (deep_revisit_closed)
  {
    state.prev_buy_count = buy.count;
    state.prev_sell_count = sell.count;
    return;
  }

  ManageRunnerTrailing(state, POSITION_TYPE_BUY, state.buy_active_basket_id, bid, take_profit_distance);
  ManageRunnerTrailing(state, POSITION_TYPE_SELL, state.sell_active_basket_id, ask, take_profit_distance);

  if (is_trading_time && state.initial_started && !low_balance)
  {
    if (params.enable_hedged_entry)
    {
      if (buy.count == 0 && !state.buy_order_pending && allow_entry_buy && spread_ok
          && CanRestart(state.last_buy_close_time, restart_delay_dynamic_seconds))
      {
        if (CanStartNewBasket(state, ORDER_TYPE_BUY, bid, ask, take_profit_distance, now))
        {
          int basket_id = (state.buy_active_basket_id > 0) ? state.buy_active_basket_id : NextBasketId(state);
          bool opened_buy = TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
          if (opened_buy)
          {
            CommitBasketId(state, POSITION_TYPE_BUY, basket_id);
            state.buy_order_pending = true;
            state.buy_order_pending_time = now;
            if (state.buy_level_price[0] <= 0.0)
              state.buy_level_price[0] = ask;
          }
        }
      }
      if (sell.count == 0 && !state.sell_order_pending && allow_entry_sell && spread_ok
          && CanRestart(state.last_sell_close_time, restart_delay_dynamic_seconds))
      {
        if (CanStartNewBasket(state, ORDER_TYPE_SELL, bid, ask, take_profit_distance, now))
        {
          int basket_id = (state.sell_active_basket_id > 0) ? state.sell_active_basket_id : NextBasketId(state);
          bool opened_sell = TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
          if (opened_sell)
          {
            CommitBasketId(state, POSITION_TYPE_SELL, basket_id);
            state.sell_order_pending = true;
            state.sell_order_pending_time = now;
            if (state.sell_level_price[0] <= 0.0)
              state.sell_level_price[0] = bid;
          }
        }
      }
    }
    else if (buy.count == 0 && sell.count == 0 && !state.buy_order_pending && !state.sell_order_pending)
    {
      bool can_restart_buy = allow_entry_buy && CanRestart(state.last_buy_close_time, restart_delay_dynamic_seconds);
      bool can_restart_sell = allow_entry_sell && CanRestart(state.last_sell_close_time, restart_delay_dynamic_seconds);
      int dir = SelectSingleEntryDirection(state, can_restart_buy, can_restart_sell, has_adx, di_plus_now, di_minus_now);
      if (dir > 0 && spread_ok)
      {
        if (CanStartNewBasket(state, ORDER_TYPE_BUY, bid, ask, take_profit_distance, now))
        {
          int basket_id = (state.buy_active_basket_id > 0) ? state.buy_active_basket_id : NextBasketId(state);
          bool opened_buy = TryOpen(state, symbol, ORDER_TYPE_BUY, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
          if (opened_buy)
          {
            CommitBasketId(state, POSITION_TYPE_BUY, basket_id);
            state.buy_order_pending = true;
            state.buy_order_pending_time = now;
            if (state.buy_level_price[0] <= 0.0)
              state.buy_level_price[0] = ask;
          }
        }
      }
      else if (dir < 0 && spread_ok)
      {
        if (CanStartNewBasket(state, ORDER_TYPE_SELL, bid, ask, take_profit_distance, now))
        {
          int basket_id = (state.sell_active_basket_id > 0) ? state.sell_active_basket_id : NextBasketId(state);
          bool opened_sell = TryOpen(state, symbol, ORDER_TYPE_SELL, state.lot_seq[0], MakeLevelComment(NM3::kCoreComment, basket_id, 1), 1);
          if (opened_sell)
          {
            CommitBasketId(state, POSITION_TYPE_SELL, basket_id);
            state.sell_order_pending = true;
            state.sell_order_pending_time = now;
            if (state.sell_level_price[0] <= 0.0)
              state.sell_level_price[0] = bid;
          }
        }
      }
    }
  }

  if (buy.count > 0)
  {
    if (buy_stop)
    {
      double base_step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
      double step = base_step * LevelStepFactor(params, buy.level_count + 1);
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
        state.buy_skip_distance = distance;
      }
      state.buy_skip_levels = 0;
    }
    else
    {
      state.buy_stop_active = false;
      state.buy_skip_price = 0.0;
      state.buy_skip_levels = 0;
    }
  }
  if (sell.count > 0)
  {
    if (sell_stop)
    {
      double base_step = state.sell_grid_step > 0.0 ? state.sell_grid_step : grid_step;
      double step = base_step * LevelStepFactor(params, sell.level_count + 1);
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
        state.sell_skip_distance = distance;
      }
      state.sell_skip_levels = 0;
    }
    else
    {
      state.sell_stop_active = false;
      state.sell_skip_price = 0.0;
      state.sell_skip_levels = 0;
    }
  }

  if (buy.count > 0 && buy.level_count < nanpin_levels)
  {
    // Buy orders fill at ask, so compare ask to the grid.
    double step = state.buy_grid_step > 0.0 ? state.buy_grid_step : grid_step;
    int level_index = buy.level_count;
    step *= LevelStepFactor(params, level_index + 1);
    step = AdjustNanpinStep(state.buy_level_price, level_index, step, false);
    double target = 0.0;
    target = EnsureBuyTarget(state, buy, step, level_index);
    double point = state.point;
    if (point <= 0.0)
      point = 0.00001;
    double tol = point * 0.5;
    if (allow_buy_trigger && spread_ok && CanNanpin(params, state.last_buy_nanpin_time) && ask <= target + tol)
    {
      if (!state.buy_order_pending)
      {
        double lot = state.lot_seq[level_index];
        int next_level = level_index + 1;
        int basket_id = (buy.basket_id > 0) ? buy.basket_id : state.buy_active_basket_id;
        if (basket_id <= 0)
          basket_id = 1;
        if (TryOpen(state, symbol, ORDER_TYPE_BUY, lot, MakeLevelComment(NM3::kCoreComment, basket_id, next_level), next_level))
        {
          state.buy_order_pending = true;
          state.buy_order_pending_time = now;
          state.last_buy_nanpin_time = now;
        }
      }
    }
  }

  if (sell.count > 0 && sell.level_count < nanpin_levels)
  {
    // Sell orders fill at bid, so compare bid to the grid.
    double step = state.sell_grid_step > 0.0 ? state.sell_grid_step : grid_step;
    int level_index = sell.level_count;
    step *= LevelStepFactor(params, level_index + 1);
    step = AdjustNanpinStep(state.sell_level_price, level_index, step, false);
    double target = 0.0;
    target = EnsureSellTarget(state, sell, step, level_index);
    double point = state.point;
    if (point <= 0.0)
      point = 0.00001;
    double tol = point * 0.5;
    if (allow_sell_trigger && spread_ok && CanNanpin(params, state.last_sell_nanpin_time) && bid >= target - tol)
    {
      if (!state.sell_order_pending)
      {
        double lot = state.lot_seq[level_index];
        int next_level = level_index + 1;
        int basket_id = (sell.basket_id > 0) ? sell.basket_id : state.sell_active_basket_id;
        if (basket_id <= 0)
          basket_id = 1;
        if (TryOpen(state, symbol, ORDER_TYPE_SELL, lot, MakeLevelComment(NM3::kCoreComment, basket_id, next_level), next_level))
        {
          state.sell_order_pending = true;
          state.sell_order_pending_time = now;
          state.last_sell_nanpin_time = now;
        }
      }
    }
  }

  state.prev_buy_count = buy.count;
  state.prev_sell_count = sell.count;
}

void OnTick()
{
  HandleTradingStopStartCloseAll();
  for (int i = 0; i < symbols_count; ++i)
    ProcessSymbolTick(symbols[i]);
}

void OnTimer()
{
  OnTick();
}
