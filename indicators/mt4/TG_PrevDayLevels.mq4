//+------------------------------------------------------------------+
//|  TG_PrevDayLevels.mq4  —  TradingGuard level indicator            |
//|  Copyright (C) 2026 Mohammadreza Tavakoli — https://itavakoli.com/ |
//|                                                                   |
//|  This program is free software under the GNU Affero General       |
//|  Public License v3 or later. It comes WITHOUT ANY WARRANTY.       |
//|  <https://www.gnu.org/licenses/>                                  |
//|                                                                   |
//|  Drawing only. No orders, no signals, no trading decisions.       |
//+------------------------------------------------------------------+
#property copyright "Mohammadreza Tavakoli"
#property link      "https://itavakoli.com/"
#property version   "1.00"
#property strict
#property indicator_chart_window

//+------------------------------------------------------------------+
//| What this indicator does                                         |
//|                                                                  |
//| For every day inside the chosen history window it reads the      |
//| D1 candle of the PREVIOUS day and draws five levels on the day   |
//| that follows it: high, low, mid, open and close.                  |
//|                                                                  |
//| Every level is a trend segment that starts at the open time of    |
//| its own day and ends one second before the next day opens. Rays   |
//| are switched off on both sides. A horizontal line would be the    |
//| shorter code, but it runs forever: a Friday level would then be   |
//| drawn across the weekend and across every later day, which is     |
//| exactly the kind of wrong level a risk tool must not show.        |
//+------------------------------------------------------------------+

//--- object name space, kept separate from the TradingGuard panel ("MMT_")
#define TG_PREFIX           "TGPD_"
//--- how many stub candles in a row may be skipped before giving up
#define TG_STUB_MAX_STEPS   5
//--- window used for the average daily range of the stub test
#define TG_RANGE_DAYS       20
//--- minimum number of reference days before the stub test is allowed to judge
#define TG_RANGE_MIN_DAYS   5
//--- fallback length of a day in seconds
#define TG_DAY_SECONDS      86400

//--- history --------------------------------------------------------
input int            InpDays           = 10;          // Days to cover, the current day counts as one (1..1000)
input bool           InpDrawToday      = true;        // Draw the levels of the current day
input bool           InpDrawEarlier    = true;        // Draw the levels of the earlier days
//--- which levels ---------------------------------------------------
input bool           InpShowHigh       = true;        // Show previous day high (PDH)
input bool           InpShowLow        = true;        // Show previous day low (PDL)
input bool           InpShowMid        = true;        // Show previous day mid, (high+low)/2 (PDM)
input bool           InpShowOpen       = true;        // Show previous day open (PDO)
input bool           InpShowClose      = true;        // Show previous day close (PDC)
//--- stub candle handling -------------------------------------------
input bool           InpSkipStubCandle = true;        // Skip a stub day candle and use the full day before it
input double         InpStubMaxPercent = 25.0;        // Stub limit in percent of the 20 day average range (0..100)
//--- appearance -----------------------------------------------------
input color          InpHighColor      = clrTomato;   // Colour of the high level
input color          InpLowColor       = clrDodgerBlue; // Colour of the low level
input color          InpMidColor       = clrGray;     // Colour of the mid level
input color          InpOpenColor      = clrGoldenrod; // Colour of the open level
input color          InpCloseColor     = clrMediumSeaGreen; // Colour of the close level
input ENUM_LINE_STYLE InpHighStyle     = STYLE_SOLID; // Line style of the high level
input ENUM_LINE_STYLE InpLowStyle      = STYLE_SOLID; // Line style of the low level
input ENUM_LINE_STYLE InpMidStyle      = STYLE_DOT;   // Line style of the mid level
input ENUM_LINE_STYLE InpOpenStyle     = STYLE_DASHDOT; // Line style of the open level (short dashes)
input ENUM_LINE_STYLE InpCloseStyle    = STYLE_DASH;  // Line style of the close level
input int            InpLineWidth      = 1;           // Line width of the solid levels (1..5)
input bool           InpShowLabels     = true;        // Write a short tag at the left edge of each day

//--- validated copies of the inputs
int      g_days      = 10;
double   g_stubLimit = 25.0;
int      g_width     = 1;
//--- true when the current period cannot carry daily levels
bool     g_blocked   = false;
//--- state of the last drawing pass, used to avoid redrawing on every tick
datetime g_lastDayOpen = 0;
int      g_lastDayBars = 0;
//--- the missing history message is printed once, not on every tick
bool     g_warned      = false;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("TG_PrevDayLevels");

   g_days = InpDays;
   if(g_days < 1)
   {
      Print("TG_PrevDayLevels: InpDays below 1, using 1.");
      g_days = 1;
   }
   if(g_days > 1000)
   {
      Print("TG_PrevDayLevels: InpDays above 1000, using 1000.");
      g_days = 1000;
   }

   g_stubLimit = InpStubMaxPercent;
   if(g_stubLimit < 0.0)
   {
      Print("TG_PrevDayLevels: InpStubMaxPercent below 0, using 0.");
      g_stubLimit = 0.0;
   }
   if(g_stubLimit > 100.0)
   {
      Print("TG_PrevDayLevels: InpStubMaxPercent above 100, using 100.");
      g_stubLimit = 100.0;
   }

   g_width = InpLineWidth;
   if(g_width < 1)
      g_width = 1;
   if(g_width > 5)
      g_width = 5;

   // One W1 or MN1 candle spans several days, so a per day segment has no
   // place to live there. Leave quietly instead of drawing something wrong.
   g_blocked = (Period() == PERIOD_W1 || Period() == PERIOD_MN1);
   if(g_blocked)
   {
      Print("TG_PrevDayLevels: W1 and MN1 are not supported, one candle covers several days. Nothing drawn.");
      return(INIT_SUCCEEDED);
   }

   // A parameter change runs OnDeinit and OnInit again, so the stored
   // drawing state has to start empty here.
   g_lastDayOpen = 0;
   g_lastDayBars = 0;
   g_warned      = false;

   Refresh();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Clean up: nothing of ours may stay on the chart                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, TG_PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Tick handler, the real work is guarded inside Refresh()          |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   Refresh();
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart changes: new period, scrolling, zoom. Refresh() decides    |
//| whether anything really needs to be drawn again, so this stays   |
//| cheap. It mainly catches the case of daily history arriving while |
//| no tick comes in, for example over the weekend.                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
      Refresh();
}

//+------------------------------------------------------------------+
//| Redraw only when the daily data changed                          |
//|                                                                  |
//| The segments have fixed times and prices, so scrolling or zooming |
//| does not change them. Only a new daily candle or newly loaded     |
//| daily history does. Rebuilding a few hundred objects on every     |
//| tick would make the terminal slow for no gain.                    |
//+------------------------------------------------------------------+
void Refresh()
{
   if(g_blocked)
      return;

   int d1bars = iBars(Symbol(), PERIOD_D1);
   datetime dayOpen = (d1bars > 1 ? iTime(Symbol(), PERIOD_D1, 0) : 0);

   // The most common reason such an indicator shows nothing at all:
   // the daily history is simply not loaded yet.
   if(d1bars < 2 || dayOpen <= 0)
   {
      if(!g_warned)
      {
         Print("TG_PrevDayLevels: daily history of ", Symbol(),
               " not available yet (D1 bars: ", d1bars,
               "). Open the D1 chart once, then nothing else is needed.");
         g_warned = true;
      }
      return;
   }
   g_warned = false;

   if(dayOpen == g_lastDayOpen && d1bars == g_lastDayBars)
      return;

   g_lastDayOpen = dayOpen;
   g_lastDayBars = d1bars;
   DrawAll(d1bars);
}

//+------------------------------------------------------------------+
//| Rebuild every level of the chosen window                         |
//+------------------------------------------------------------------+
void DrawAll(const int d1bars)
{
   ObjectsDeleteAll(0, TG_PREFIX);

   // Day index 0 is the current day. Its source candle is index 1, so the
   // oldest day we can serve is d1bars-2.
   int maxDays = g_days;
   if(maxDays > d1bars - 1)
      maxDays = d1bars - 1;

   for(int d = 0; d < maxDays; d++)
   {
      if(d == 0 && !InpDrawToday)
         continue;
      if(d > 0 && !InpDrawEarlier)
         continue;

      datetime dayStart = iTime(Symbol(), PERIOD_D1, d);
      if(dayStart <= 0)
         break;

      // End of the day: one second before the next day opens. For the
      // current day there is no next candle yet, so a full day is used and
      // the segment reaches to the end of the session.
      datetime dayEnd = dayStart + TG_DAY_SECONDS - 1;
      if(d > 0)
      {
         datetime nextStart = iTime(Symbol(), PERIOD_D1, d - 1);
         if(nextStart > dayStart)
            dayEnd = nextStart - 1;
      }

      int src = SourceCandle(d + 1, d1bars);
      if(src < 0)
         continue;

      double srcHigh  = iHigh(Symbol(),  PERIOD_D1, src);
      double srcLow   = iLow(Symbol(),   PERIOD_D1, src);
      double srcOpen  = iOpen(Symbol(),  PERIOD_D1, src);
      double srcClose = iClose(Symbol(), PERIOD_D1, src);
      if(srcHigh <= 0.0 || srcLow <= 0.0)
         continue;

      if(InpShowHigh)
         DrawLevel("PDH", dayStart, dayEnd, srcHigh, InpHighColor, InpHighStyle);
      if(InpShowLow)
         DrawLevel("PDL", dayStart, dayEnd, srcLow, InpLowColor, InpLowStyle);
      if(InpShowMid)
         DrawLevel("PDM", dayStart, dayEnd, (srcHigh + srcLow) / 2.0, InpMidColor, InpMidStyle);
      if(InpShowOpen)
         DrawLevel("PDO", dayStart, dayEnd, srcOpen, InpOpenColor, InpOpenStyle);
      if(InpShowClose)
         DrawLevel("PDC", dayStart, dayEnd, srcClose, InpCloseColor, InpCloseStyle);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Pick the candle the levels are read from                         |
//|                                                                  |
//| DELIBERATE DEVIATION FROM THE ORIGINAL PRODUCT:                  |
//| Some brokers write a very short Sunday candle. The original only  |
//| warns about it and still reads that candle, so the Monday levels  |
//| come from a few hours of thin trade instead of from the full      |
//| Friday. For a risk tool those are plainly wrong levels, so this   |
//| implementation skips such a stub and steps back one more candle.  |
//| InpSkipStubCandle switches the behaviour back to the original.    |
//+------------------------------------------------------------------+
int SourceCandle(const int start, const int d1bars)
{
   int idx = start;
   if(idx > d1bars - 1)
      return(-1);
   if(!InpSkipStubCandle)
      return(idx);

   for(int step = 0; step < TG_STUB_MAX_STEPS; step++)
   {
      if(!IsStubCandle(idx, d1bars))
         break;
      if(idx + 1 > d1bars - 1)
         break;
      idx++;
   }
   return(idx);
}

//+------------------------------------------------------------------+
//| A candle counts as a stub when its range stays below the given   |
//| share of the average range of the days before it. The candidate   |
//| itself is left out of that average, otherwise a stub would pull   |
//| the reference down and hide itself.                              |
//+------------------------------------------------------------------+
bool IsStubCandle(const int idx, const int d1bars)
{
   double range = iHigh(Symbol(), PERIOD_D1, idx) - iLow(Symbol(), PERIOD_D1, idx);
   if(range <= 0.0)
      return(true);

   double sum = 0.0;
   int    used = 0;
   for(int i = idx + 1; i <= idx + TG_RANGE_DAYS && i <= d1bars - 1; i++)
   {
      double r = iHigh(Symbol(), PERIOD_D1, i) - iLow(Symbol(), PERIOD_D1, i);
      if(r > 0.0)
      {
         sum += r;
         used++;
      }
   }
   // Too little reference data: do not judge, keep the candle.
   if(used < TG_RANGE_MIN_DAYS)
      return(false);

   double average = sum / used;
   return(range < average * g_stubLimit / 100.0);
}

//+------------------------------------------------------------------+
//| One level: a day long segment plus its optional tag              |
//+------------------------------------------------------------------+
void DrawLevel(const string tag,
               const datetime dayStart,
               const datetime dayEnd,
               const double price,
               const color clr,
               const ENUM_LINE_STYLE style)
{
   string stamp = IntegerToString((long)dayStart);
   string name  = TG_PREFIX + tag + "_" + stamp;

   if(!ObjectCreate(0, name, OBJ_TREND, 0, dayStart, price, dayEnd, price))
      return;

   // MT4 renders a non solid style only at width 1, a wider line would be
   // drawn solid and the styles could no longer be told apart.
   int width = (style == STYLE_SOLID ? g_width : 1);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   if(!InpShowLabels)
      return;

   string label = TG_PREFIX + tag + "T_" + stamp;
   if(!ObjectCreate(0, label, OBJ_TEXT, 0, dayStart, price))
      return;

   ObjectSetString(0, label, OBJPROP_TEXT, tag);
   ObjectSetString(0, label, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, label, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, label, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, label, OBJPROP_BACK, true);
   ObjectSetInteger(0, label, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, label, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, label, OBJPROP_HIDDEN, true);
}
//+------------------------------------------------------------------+
