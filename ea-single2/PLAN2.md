//+------------------------------------------------------------------+
//| Auto News Filter using MT5 Economic Calendar (2025-2030+)
//| - No hard-coded dates: fully automatic as long as broker provides calendar
//| - Uses Trade Server Time internally (per MT5 calendar API spec)
//+------------------------------------------------------------------+
#property strict

input int  MinutesBefore = 5;
input int  MinutesAfter  = 30;

input bool FilterUSD = true;
input bool FilterEUR = true;
input bool FilterGBP = true;

input bool OnlyHighImpact = true;

// --- internal "whitelist" of event_id (selected by currency + keywords + importance)
int g_allowed_event_ids[];
bool g_inited=false;

// ----------------- helpers -----------------
bool ArrayContainsInt(const int &arr[], int x)
{
   for(int i=0;i<ArraySize(arr);i++)
      if(arr[i]==x) return true;
   return false;
}

void ArrayAddUniqueInt(int &arr[], int x)
{
   if(!ArrayContainsInt(arr,x))
   {
      int n=ArraySize(arr);
      ArrayResize(arr,n+1);
      arr[n]=x;
   }
}

string ToUpper(string s)
{
   StringToUpper(s);
   return s;
}

bool NameMatches(const string name_upper, const string &keys[])
{
   for(int i=0;i<ArraySize(keys);i++)
      if(StringFind(name_upper, keys[i])>=0)
         return true;
   return false;
}

// TradeServer -> GMT (for logging only)
datetime ServerToGMT(datetime t_server)
{
   long offset = (long)(TimeTradeServer() - TimeGMT()); // seconds
   return (datetime)(t_server - offset);
}

// Build whitelist: currency -> all events -> (importance + keyword) -> store event.id
bool BuildAllowedEventsForCurrency(const string ccy)
{
   MqlCalendarEvent events[];
   int n = CalendarEventByCurrency(ccy, events);
   if(n<=0)
   {
      PrintFormat("CalendarEventByCurrency(%s) returned %d, err=%d", ccy, n, GetLastError());
      return false;
   }

   // keywords (UPPERCASE)
   // Note: Calendar event names vary by provider; keep keywords broad.
   string keys_usd[] = {"CPI", "CONSUMER PRICE", "NONFARM", "NON-FARM", "PAYROLL", "NFP",
                        "PPI", "PRODUCER PRICE", "GDP", "GROSS DOMESTIC",
                        "PCE", "PERSONAL CONSUMPTION", "FOMC", "FED", "INTEREST RATE", "RATE DECISION"};
   string keys_eur[] = {"ECB", "INTEREST RATE", "RATE DECISION", "MONETARY POLICY",
                        "HICP", "CPI", "INFLATION", "GDP", "UNEMPLOYMENT", "PMI"};
   string keys_gbp[] = {"BOE", "BANK OF ENGLAND", "INTEREST RATE", "RATE DECISION",
                        "CPI", "INFLATION", "GDP", "EMPLOYMENT", "UNEMPLOYMENT", "AVERAGE EARNINGS"};

   for(int i=0;i<n;i++)
   {
      // importance filter
      if(OnlyHighImpact && events[i].importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      string nm = ToUpper(events[i].name);

      bool ok=false;
      if(ccy=="USD") ok = NameMatches(nm, keys_usd);
      if(ccy=="EUR") ok = NameMatches(nm, keys_eur);
      if(ccy=="GBP") ok = NameMatches(nm, keys_gbp);

      if(ok)
         ArrayAddUniqueInt(g_allowed_event_ids, (int)events[i].id);
   }
   return true;
}

bool InitNewsFilter()
{
   ArrayResize(g_allowed_event_ids,0);

   bool ok=true;
   if(FilterUSD) ok = BuildAllowedEventsForCurrency("USD") && ok;
   if(FilterEUR) ok = BuildAllowedEventsForCurrency("EUR") && ok;
   if(FilterGBP) ok = BuildAllowedEventsForCurrency("GBP") && ok;

   PrintFormat("NewsFilter init: allowed_event_ids=%d", ArraySize(g_allowed_event_ids));
   g_inited=true;
   return ok;
}

// core: are we inside any event window?
bool IsNewsTimeNow()
{
   if(!g_inited)
      InitNewsFilter();

   datetime now_server = TimeTradeServer(); // calendar API uses trade server time  [oai_citation:2‡MQL5](https://www.mql5.com/en/docs/calendar)
   datetime from = now_server - MinutesBefore*60;
   datetime to   = now_server + MinutesAfter*60;

   // Query values near "now" for each currency (narrow window => fast)
   // CalendarValueHistory supports country_code + currency filters  [oai_citation:3‡MQL5](https://www.mql5.com/en/docs/calendar/calendarvaluehistory)
   string ccys[3] = {"USD","EUR","GBP"};

   for(int c=0;c<3;c++)
   {
      if(ccys[c]=="USD" && !FilterUSD) continue;
      if(ccys[c]=="EUR" && !FilterEUR) continue;
      if(ccys[c]=="GBP" && !FilterGBP) continue;

      MqlCalendarValue values[];
      int n = CalendarValueHistory(values, from, to, NULL, ccys[c]);
      if(n<=0) continue;

      for(int i=0;i<n;i++)
      {
         int ev_id = (int)values[i].event_id;
         if(!ArrayContainsInt(g_allowed_event_ids, ev_id))
            continue;

         // We're within [from,to] by construction.
         // Optional: log the event in GMT
         MqlCalendarEvent ev;
         if(CalendarEventById(ev_id, ev))
         {
            datetime gmt_time = ServerToGMT(values[i].time);
            PrintFormat("[NEWS BLOCK] %s (%s) server=%s GMT=%s",
                        ev.name, ccys[c],
                        TimeToString(values[i].time, TIME_DATE|TIME_MINUTES),
                        TimeToString(gmt_time, TIME_DATE|TIME_MINUTES));
         }
         return true;
      }
   }
   return false;
}

// Example usage
void OnTick()
{
   if(IsNewsTimeNow())
      return;

   // ---- your trading logic here ----
}
