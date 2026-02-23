//+------------------------------------------------------------------+
//| CalendarRetriever.mq5
//| Export MT5 Economic Calendar values to CSV (2025-2030 etc.)
//| Saved to: FILE_COMMON
//+------------------------------------------------------------------+
#property strict

input datetime StartDate      = D'2025.01.01 00:00';
input datetime EndDate        = D'2030.12.31 23:59';
input int      ChunkDays      = 30;          // split requests to reduce load
input string   OutputFileName = "economic_calendar_2025_2030.csv";

input bool ExportUSD = true;
input bool ExportEUR = true;
input bool ExportGBP = true;

input bool OnlyHighImportance = false;       // true = importance==HIGH only
input bool IncludeFuture      = true;        // true = allow EndDate=0 (all known including future)

//------------------------------------------------------------
// Helpers
//------------------------------------------------------------
string ImportanceToString(ENUM_CALENDAR_EVENT_IMPORTANCE imp)
{
   switch(imp)
   {
      case CALENDAR_IMPORTANCE_LOW:    return "LOW";
      case CALENDAR_IMPORTANCE_MODERATE: return "MEDIUM";
      case CALENDAR_IMPORTANCE_HIGH:   return "HIGH";
   }
   return "UNKNOWN";
}

string ImpactToString(ENUM_CALENDAR_EVENT_IMPACT impact)
{
   switch(impact)
   {
      case CALENDAR_IMPACT_NA:       return "NA";
      case CALENDAR_IMPACT_POSITIVE: return "POSITIVE";
      case CALENDAR_IMPACT_NEGATIVE: return "NEGATIVE";
   }
   return "UNKNOWN";
}

// Convert TradeServer time -> GMT (for export/logging)
// Uses current offset between server and GMT (good enough for consistent labeling)
datetime ServerToGMT(datetime t_server)
{
   long offset = (long)(TimeTradeServer() - TimeGMT()); // seconds
   return (datetime)(t_server - offset);
}

string Dts(datetime t)
{
   return TimeToString(t, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
}

string DoubleOrEmpty(bool has, double v, int digits=6)
{
   if(!has) return "";
   // Keep a reasonable precision; you can increase if needed
   return DoubleToString(v, digits);
}

//------------------------------------------------------------
// Export one currency
//------------------------------------------------------------
bool ExportCurrency(const string ccy, int fh, datetime from_in, datetime to_in)
{
   datetime from = from_in;
   datetime to   = to_in;

   // If user wants include all known future events, MQL5 allows date_to = 0
   if(IncludeFuture && to==to_in && to_in>0 && to_in>TimeTradeServer())
   {
      // Keep as requested EndDate; do not force 0 automatically.
      // (Setting to 0 can be huge and slow; use only if you really want all future.)
   }

   int total_written = 0;

   // chunk loop
   int step = MathMax(1, ChunkDays);
   while(from < to)
   {
      datetime chunk_to = from + (datetime)step * 86400;
      if(chunk_to > to) chunk_to = to;

      MqlCalendarValue values[];
      ResetLastError();

      // CalendarValueHistory(values, date_from, date_to, country_code=NULL, currency=ccy)
      // Fills values[] and returns true/false  [oai_citation:3‡MQL5](https://www.mql5.com/en/docs/constants/structures/mqlcalendar)
      bool ok = CalendarValueHistory(values, from, chunk_to, NULL, ccy);
      if(!ok)
      {
         int err = GetLastError();
         PrintFormat("CalendarValueHistory failed ccy=%s from=%s to=%s err=%d",
                     ccy, Dts(from), Dts(chunk_to), err);
         // continue with next chunk
         from = chunk_to;
         continue;
      }

      // Write rows
      int n = ArraySize(values);
      for(int i=0; i<n; i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById((ulong)values[i].event_id, ev))
            continue;

         if(OnlyHighImportance && ev.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;

         // times
         datetime t_server = values[i].time;
         datetime t_gmt    = ServerToGMT(t_server);

         // values (use structure methods to get doubles)  [oai_citation:4‡MQL5](https://www.mql5.com/en/docs/constants/structures/mqlcalendar)
         bool hasA = values[i].HasActualValue();
         bool hasF = values[i].HasForecastValue();
         bool hasP = values[i].HasPreviousValue();
         bool hasR = values[i].HasRevisedValue();

         double a = values[i].GetActualValue();
         double f = values[i].GetForecastValue();
         double p = values[i].GetPreviousValue();
         double r = values[i].GetRevisedValue();

         // period
         string period_str = (values[i].period>0 ? Dts(values[i].period) : "");

         // CSV columns:
         // server_time, gmt_time, currency, event_id, value_id, importance, impact, name, period, revision, actual, forecast, previous, revised_previous
         FileWrite(
            fh,
            Dts(t_server),
            Dts(t_gmt),
            ccy,
            (string)values[i].event_id,
            (string)values[i].id,
            ImportanceToString(ev.importance),
            ImpactToString(values[i].impact_type),
            ev.name,
            period_str,
            (string)values[i].revision,
            DoubleOrEmpty(hasA, a),
            DoubleOrEmpty(hasF, f),
            DoubleOrEmpty(hasP, p),
            DoubleOrEmpty(hasR, r)
         ); // FileWrite writes CSV with delimiter automatically  [oai_citation:5‡MQL5](https://www.mql5.com/en/docs/files/filewrite?utm_source=chatgpt.com)

         total_written++;
      }

      from = chunk_to;
   }

   PrintFormat("Exported %d rows for %s", total_written, ccy);
   return true;
}

//------------------------------------------------------------
// Script entry
//------------------------------------------------------------
void OnStart()
{
   datetime from = StartDate;
   datetime to   = EndDate;

   if(IncludeFuture && EndDate==0)
      to = 0; // user explicitly set 0

   if(from<=0)
   {
      Print("StartDate must be set.");
      return;
   }
   if(to!=0 && to <= from)
   {
      Print("EndDate must be > StartDate (or set EndDate=0 to export all known future).");
      return;
   }

   // Open CSV in COMMON folder
   int fh = FileOpen(OutputFileName, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("FileOpen failed: %s err=%d", OutputFileName, GetLastError());
      return;
   }

   // Header
   FileWrite(fh,
      "server_time",
      "gmt_time",
      "currency",
      "event_id",
      "value_id",
      "importance",
      "impact",
      "event_name",
      "period",
      "revision",
      "actual",
      "forecast",
      "previous",
      "revised_previous"
   );

   // If EndDate==0 (all known), we still chunk by date; to==0 breaks loop.
   // For safety/performance, if to==0, cap to a reasonable future horizon:
   // (You can change this if you really want everything.)
   if(to==0)
   {
      to = TimeTradeServer() + 365*86400; // next 1 year
      Print("EndDate=0 detected; capped to +1 year for safety. Change in code if needed.");
   }

   bool any=false;

   if(ExportUSD){ any=true; ExportCurrency("USD", fh, from, to); }
   if(ExportEUR){ any=true; ExportCurrency("EUR", fh, from, to); }
   if(ExportGBP){ any=true; ExportCurrency("GBP", fh, from, to); }

   if(!any)
      Print("No currency selected (USD/EUR/GBP). Nothing to export.");

   FileClose(fh);

   PrintFormat("DONE. CSV saved to COMMON: %s", OutputFileName);
}
