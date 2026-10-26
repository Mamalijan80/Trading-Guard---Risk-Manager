//+------------------------------------------------------------------+
//|  TG_Levels.mq4  —  TradingGuard level indicators                  |
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
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Three level tools in one indicator                               |
//|                                                                  |
//|   RL  Round Levels     a price grid on friendly round numbers    |
//|   PD  Previous Day     high, low, mid, open, close of the day    |
//|                        before, drawn day by day                  |
//|   WM  Weekly Map       13 levels derived from the previous week   |
//|                                                                  |
//| Each group keeps its own inputs, its own object namespace, its    |
//| own redraw condition and its own timeframe rules. A group that    |
//| stops drawing never stops the other two.                         |
//+------------------------------------------------------------------+

//--- shared object namespace ----------------------------------------
// Everything this indicator creates starts with TGL_, so it can never
// collide with the TradingGuard panel ("MMT_") or with objects a user
// or another tool placed on the chart. Each group owns one subtree.
#define TGL_ROOT        "TGL_"

//====================================================================
//  INPUTS
//====================================================================
input string          __sep_rl           = "---------- Round Levels ----------"; // separator only
input bool            InpShowRoundLevels = true;        // draw the round level grid
input bool            InpRL_AutoSpacing  = true;        // auto spacing from price, otherwise InpRL_ManualStep
input double          InpRL_AutoPercent  = 0.5;         // auto step as percent of current price
input double          InpRL_RecalcPercent= 20.0;        // recompute step only after price moved this many percent
input double          InpRL_ManualStep   = 250;         // fixed step in price units (used when auto spacing is off)
input bool            InpRL_ShowLabels   = true;        // print the price value next to each line
input int             InpRL_MaxLines     = 300;         // hard cap on drawn levels (centre of screen wins)
input color           InpRL_LineColor    = clrDimGray;  // colour of the level lines
input ENUM_LINE_STYLE InpRL_LineStyle    = STYLE_DOT;   // dotted and dashed styles only render as such at width 1
input int             InpRL_LineWidth    = 1;           // line width in pixels
input color           InpRL_LabelColor   = clrSilver;   // colour of the price labels
input int             InpRL_LabelSize    = 8;           // label font size
input string          InpRL_LabelFont    = "Tahoma";    // label font family

input string          __sep_pd           = "---------- Previous Day ----------"; // separator only
input bool            InpShowPrevDay     = true;        // draw the previous day levels
input int             InpPD_Days         = 10;          // Days to cover, the current day counts as one (1..1000)
input bool            InpPD_DrawToday    = true;        // Draw the levels of the current day
input bool            InpPD_DrawEarlier  = true;        // Draw the levels of the earlier days
input bool            InpPD_ShowHigh     = true;        // Show previous day high (PDH)
input bool            InpPD_ShowLow      = true;        // Show previous day low (PDL)
input bool            InpPD_ShowMid      = true;        // Show previous day mid, (high+low)/2 (PDM)
input bool            InpPD_ShowOpen     = true;        // Show previous day open (PDO)
input bool            InpPD_ShowClose    = true;        // Show previous day close (PDC)
input bool            InpPD_SkipStubCandle = true;      // Skip a stub day candle and use the full day before it
input double          InpPD_StubMaxPercent = 25.0;      // Stub limit in percent of the 20 day average range (0..100)
input color           InpPD_HighColor    = clrTomato;   // Colour of the high level
input color           InpPD_LowColor     = clrDodgerBlue; // Colour of the low level
input color           InpPD_MidColor     = clrGray;     // Colour of the mid level
input color           InpPD_OpenColor    = clrGoldenrod; // Colour of the open level
input color           InpPD_CloseColor   = clrMediumSeaGreen; // Colour of the close level
input ENUM_LINE_STYLE InpPD_HighStyle    = STYLE_SOLID; // Line style of the high level
input ENUM_LINE_STYLE InpPD_LowStyle     = STYLE_SOLID; // Line style of the low level
input ENUM_LINE_STYLE InpPD_MidStyle     = STYLE_DOT;   // Line style of the mid level
input ENUM_LINE_STYLE InpPD_OpenStyle    = STYLE_DASHDOT; // Line style of the open level (short dashes)
input ENUM_LINE_STYLE InpPD_CloseStyle   = STYLE_DASH;  // Line style of the close level
input int             InpPD_LineWidth    = 1;           // Line width of the solid levels (1..5)
input bool            InpPD_ShowLabels   = true;        // Write a short tag at the left edge of each day

input string          __sep_wm           = "---------- Weekly Map ----------"; // separator only
input bool            InpShowWeeklyMap   = true;        // draw the weekly map
input int             InpWM_Weeks        = 10;             // number of weeks to map, current week included (1..100)
input string          InpWM_Levels       = "H,L,50,25,75,+25,+50,+75,+100,-25,-50,-75,-100"; // levels to show, empty = all
input bool            InpWM_ShowGap      = true;           // mark the weekend gap with two lines
input int             InpWM_GapMinPoints = 5;              // minimum gap distance in points, smaller gaps are ignored
input color           InpWM_MainColor    = clrDodgerBlue;  // colour of H, L and 50%
input color           InpWM_SubColor     = clrSlateGray;   // colour of 25% and 75%
input color           InpWM_ExtColor     = clrDarkGoldenrod; // colour of the eight extensions
input color           InpWM_GapUpColor   = clrSeaGreen;    // colour of a gap to the upside
input color           InpWM_GapDownColor = clrOrangeRed;   // colour of a gap to the downside
input int             InpWM_LineWidth    = 1;              // line width of every level (1..5)
input bool            InpWM_ShowLabels   = true;           // write the level name next to each line

//====================================================================
//  GROUP RL — ROUND LEVELS
//====================================================================

//--- private object namespace
#define RL_PREFIX     "TGL_RL_"
#define RL_LINE       "TGL_RL_L_"
#define RL_TEXT       "TGL_RL_T_"
#define RL_LABEL_GAP  3            // label offset to the right, in chart periods
#define RL_NICE_COUNT 5

//--- cached state: everything that decides whether a redraw is needed
double   RL_g_step        = 0.0;        // current level distance in price units
double   RL_g_refPrice    = 0.0;        // price the current step was computed from
int      RL_g_slotsUsed   = 0;          // number of object slots written on the last draw
int      RL_g_lowIndex    = 0;          // first drawn level index (level = index * step)
int      RL_g_highIndex   = -1;         // last drawn level index
datetime RL_g_labelTime   = 0;          // time anchor used for the labels
bool     RL_g_capped      = false;      // true while levels are being hidden by InpRL_MaxLines
bool     RL_g_noticeShown = false;      // true while our RL_ShowNotice() text is on the chart
int      RL_g_maxLines    = 300;        // validated copy of InpRL_MaxLines
double   RL_g_manualStep  = 250.0;      // validated copy of InpRL_ManualStep
double   RL_g_autoPercent = 0.5;        // validated copy of InpRL_AutoPercent
bool     RL_g_active      = false;      // true while this group has objects on the chart

//+------------------------------------------------------------------+
//| Round a raw distance up or down to the nearest friendly number:  |
//| 1, 2, 2.5 or 5 times a power of ten.                             |
//+------------------------------------------------------------------+
double RL_NiceStep(const double raw)
{
   if(raw <= 0.0)
      return(0.0);

   double nice[RL_NICE_COUNT] = {1.0, 2.0, 2.5, 5.0, 10.0};

   double decade   = MathPow(10.0, MathFloor(MathLog10(raw)));
   double mantissa = raw / decade;

   int    pick = 0;
   double gap  = MathAbs(mantissa - nice[0]);
   for(int i = 1; i < RL_NICE_COUNT; i++)
   {
      double candidate = MathAbs(mantissa - nice[i]);
      if(candidate < gap)
      {
         gap  = candidate;
         pick = i;
      }
   }
   return(nice[pick] * decade);
}

//+------------------------------------------------------------------+
//| Current reference price. Bid may be zero before the first tick.  |
//+------------------------------------------------------------------+
double RL_ReferencePrice()
{
   if(Bid > 0.0)
      return(Bid);
   if(Bars > 0)
      return(Close[0]);
   return(0.0);
}

//+------------------------------------------------------------------+
//| Keep RL_g_step up to date. In auto mode the step is deliberately |
//| sticky: it only changes after a move of InpRL_RecalcPercent, so  |
//| the grid does not jump around during normal trading.             |
//+------------------------------------------------------------------+
void RL_UpdateStep()
{
   if(!InpRL_AutoSpacing)
   {
      RL_g_step     = RL_g_manualStep;
      RL_g_refPrice = 0.0;
      return;
   }

   double price = RL_ReferencePrice();
   if(price <= 0.0)
      return;

   if(RL_g_step > 0.0 && RL_g_refPrice > 0.0)
   {
      double moved = MathAbs(price - RL_g_refPrice) / RL_g_refPrice * 100.0;
      if(moved <= InpRL_RecalcPercent)
         return;
   }

   double fresh = RL_NiceStep(price * RL_g_autoPercent / 100.0);
   if(fresh > 0.0)
   {
      RL_g_step     = fresh;
      RL_g_refPrice = price;
   }
}

//+------------------------------------------------------------------+
//| Visible price band of the chart window.                          |
//+------------------------------------------------------------------+
bool RL_VisibleBand(double &low, double &high)
{
   low  = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   high = ChartGetDouble(0, CHART_PRICE_MAX, 0);

   if(high - low <= 0.0)                       // fallback for a chart that reports nothing yet
   {
      low  = WindowPriceMin();
      high = WindowPriceMax();
   }
   return(high - low > 0.0);
}

//+------------------------------------------------------------------+
//| Time anchor for the labels: rightmost visible bar plus a gap.    |
//+------------------------------------------------------------------+
datetime RL_LabelTime()
{
   if(Bars <= 0)
      return(0);

   int first   = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);
   int visible = (int)ChartGetInteger(0, CHART_VISIBLE_BARS, 0);

   int shift = first - visible + 1;             // rightmost bar inside the window
   if(shift < 0)
      shift = 0;
   if(shift > Bars - 1)
      shift = Bars - 1;

   return(Time[shift] + (datetime)(RL_LABEL_GAP * PeriodSeconds()));
}

//+------------------------------------------------------------------+
//| Create or refresh one horizontal level line.                     |
//+------------------------------------------------------------------+
void RL_WriteLine(const string name, const double price)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      InpRL_LineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      InpRL_LineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpRL_LineWidth);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Create or refresh one price label at the right chart edge.       |
//+------------------------------------------------------------------+
void RL_WriteLabel(const string name, const datetime when, const double price)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, when, price);

   ObjectSetInteger(0, name, OBJPROP_TIME,  0, when);
   ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0,  name, OBJPROP_TEXT,       DoubleToString(price, _Digits));
   ObjectSetString(0,  name, OBJPROP_FONT,       InpRL_LabelFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpRL_LabelSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      InpRL_LabelColor);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Drop object slots that the current draw no longer needs.         |
//+------------------------------------------------------------------+
void RL_TrimSlots(const int keep)
{
   for(int slot = keep; slot < RL_g_slotsUsed; slot++)
   {
      ObjectDelete(0, RL_LINE + IntegerToString(slot));
      ObjectDelete(0, RL_TEXT + IntegerToString(slot));
   }
   RL_g_slotsUsed = keep;
}

//+------------------------------------------------------------------+
//| Tell the user why levels are missing above and below.            |
//+------------------------------------------------------------------+
void RL_ShowNotice(const bool capped, const int shown, const int wanted)
{
   if(capped)
   {
      RL_ShowNotice("TG_Levels round levels: " + IntegerToString(wanted) + " levels in view, "
              + IntegerToString(shown) + " drawn (InpRL_MaxLines). "
              + "Levels far from the screen centre are left out.");
      RL_g_noticeShown = true;
      Print("TG_Levels round levels: level cap reached - ", wanted, " in view, ", shown,
            " drawn, step ", DoubleToString(RL_g_step, _Digits));
   }
   else if(RL_g_noticeShown)
   {
      RL_ShowNotice("");
      RL_g_noticeShown = false;
   }
}

//+------------------------------------------------------------------+
//| Redraw the grid, but only when something actually changed.       |
//+------------------------------------------------------------------+
void RL_Refresh(const bool force)
{
   // The master switch is checked on every pass, not only in OnInit,
   // so turning the group off takes its objects with it.
   if(!InpShowRoundLevels)
   {
      if(RL_g_active)
      {
         ObjectsDeleteAll(0, RL_PREFIX);
         RL_g_slotsUsed   = 0;
         RL_g_lowIndex    = 0;
         RL_g_highIndex   = -1;
         RL_g_labelTime   = 0;
         RL_g_capped      = false;
         RL_g_noticeShown = false;
         RL_g_active      = false;
         ChartRedraw();
      }
      return;
   }
   RL_g_active = true;

   RL_UpdateStep();
   if(RL_g_step <= 0.0)
      return;

   double low, high;
   if(!RL_VisibleBand(low, high))
      return;

   // Levels are counted from zero, so every line sits on an exact
   // multiple of the step and the grid never drifts with the price.
   int lowIndex = (int)MathFloor(low / RL_g_step);
   if(lowIndex * RL_g_step < low)
      lowIndex++;
   int highIndex = (int)MathFloor(high / RL_g_step);

   int wanted = highIndex - lowIndex + 1;
   if(wanted <= 0)
   {
      RL_TrimSlots(0);
      RL_ShowNotice(false, 0, 0);
      ChartRedraw();
      return;
   }

   bool capped = false;
   if(wanted > RL_g_maxLines)                   // keep the band around the screen centre
   {
      int centre = (int)MathRound((low + high) / 2.0 / RL_g_step);
      int from   = centre - RL_g_maxLines / 2;
      int to     = from + RL_g_maxLines - 1;

      if(from < lowIndex)
      {
         from = lowIndex;
         to   = from + RL_g_maxLines - 1;
      }
      if(to > highIndex)
      {
         to   = highIndex;
         from = to - RL_g_maxLines + 1;
      }
      lowIndex  = from;
      highIndex = to;
      capped    = true;
   }

   datetime when = RL_LabelTime();

   if(!force
      && lowIndex  == RL_g_lowIndex
      && highIndex == RL_g_highIndex
      && when      == RL_g_labelTime
      && capped    == RL_g_capped)
      return;                                   // nothing moved, leave the objects alone

   int slot = 0;
   for(int index = lowIndex; index <= highIndex; index++, slot++)
   {
      double level = index * RL_g_step;
      RL_WriteLine(RL_LINE + IntegerToString(slot), level);

      if(InpRL_ShowLabels && when > 0)
         RL_WriteLabel(RL_TEXT + IntegerToString(slot), when, level);
      else
         ObjectDelete(0, RL_TEXT + IntegerToString(slot));
   }

   RL_TrimSlots(slot);

   RL_g_lowIndex  = lowIndex;
   RL_g_highIndex = highIndex;
   RL_g_labelTime = when;
   RL_g_capped    = capped;

   RL_ShowNotice(capped, slot, wanted);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Cap notice. Deliberately NOT Comment(): the chart comment is a   |
//| single shared slot. Writing it would overwrite whatever another   |
//| indicator or the TradingGuard EA put there, and clearing it on    |
//| deinit would wipe their text too. An own label in our own         |
//| namespace cannot collide.                                         |
//+------------------------------------------------------------------+
void RL_ShowNotice(const string text)
{
   string n = RL_PREFIX + "notice";
   if(text == "")
   {
      if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
      return;
   }
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
      ObjectSetString (0, n, OBJPROP_FONT, InpRL_LabelFont);
      ObjectSetInteger(0, n, OBJPROP_COLOR, InpRL_LabelColor);
   }
   ObjectSetString(0, n, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Group initialisation                                             |
//+------------------------------------------------------------------+
void RL_Init()
{
   RL_g_maxLines    = (InpRL_MaxLines    > 0   ? InpRL_MaxLines    : 1);
   RL_g_manualStep  = (InpRL_ManualStep  > 0.0 ? InpRL_ManualStep  : 1.0);
   RL_g_autoPercent = (InpRL_AutoPercent > 0.0 ? InpRL_AutoPercent : 0.5);

   if(InpRL_ManualStep <= 0.0 && !InpRL_AutoSpacing)
      Print("TG_Levels round levels: InpRL_ManualStep must be positive, using 1.0 instead.");
   if(InpRL_AutoPercent <= 0.0 && InpRL_AutoSpacing)
      Print("TG_Levels round levels: InpRL_AutoPercent must be positive, using 0.5 instead.");

   // A restart must not inherit stale objects from the previous run.
   ObjectsDeleteAll(0, RL_PREFIX);

   RL_g_step        = 0.0;
   RL_g_refPrice    = 0.0;
   RL_g_slotsUsed   = 0;
   RL_g_lowIndex    = 0;
   RL_g_highIndex   = -1;
   RL_g_labelTime   = 0;
   RL_g_capped      = false;
   RL_g_noticeShown = false;
   RL_g_active      = false;

   RL_Refresh(true);
}

//+------------------------------------------------------------------+
//| Group clean up                                                   |
//+------------------------------------------------------------------+
void RL_Deinit()
{
   ObjectsDeleteAll(0, RL_PREFIX);
   if(RL_g_noticeShown)
   {
      RL_ShowNotice("");
      RL_g_noticeShown = false;
   }
   RL_g_slotsUsed = 0;
   RL_g_active    = false;
}

//====================================================================
//  GROUP PD — PREVIOUS DAY LEVELS
//====================================================================

//+------------------------------------------------------------------+
//| What this group does                                             |
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

//--- object name space of this group
#define PD_PREFIX           "TGL_PD_"
//--- how many stub candles in a row may be skipped before giving up
#define PD_STUB_MAX_STEPS   5
//--- window used for the average daily range of the stub test
#define PD_RANGE_DAYS       20
//--- minimum number of reference days before the stub test is allowed to judge
#define PD_RANGE_MIN_DAYS   5
//--- fallback length of a day in seconds
#define PD_DAY_SECONDS      86400

//--- validated copies of the inputs
int      PD_g_days      = 10;
double   PD_g_stubLimit = 25.0;
int      PD_g_width     = 1;
//--- true when the current period cannot carry daily levels
bool     PD_g_blocked   = false;
//--- state of the last drawing pass, used to avoid redrawing on every tick
datetime PD_g_lastDayOpen = 0;
int      PD_g_lastDayBars = 0;
//--- the missing history message is printed once, not on every tick
bool     PD_g_warned      = false;
//--- true while this group has objects on the chart
bool     PD_g_active      = false;

//+------------------------------------------------------------------+
//| A candle counts as a stub when its range stays below the given   |
//| share of the average range of the days before it. The candidate   |
//| itself is left out of that average, otherwise a stub would pull   |
//| the reference down and hide itself.                              |
//+------------------------------------------------------------------+
bool PD_IsStubCandle(const int idx, const int d1bars)
{
   double range = iHigh(Symbol(), PERIOD_D1, idx) - iLow(Symbol(), PERIOD_D1, idx);
   if(range <= 0.0)
      return(true);

   double sum = 0.0;
   int    used = 0;
   for(int i = idx + 1; i <= idx + PD_RANGE_DAYS && i <= d1bars - 1; i++)
   {
      double r = iHigh(Symbol(), PERIOD_D1, i) - iLow(Symbol(), PERIOD_D1, i);
      if(r > 0.0)
      {
         sum += r;
         used++;
      }
   }
   // Too little reference data: do not judge, keep the candle.
   if(used < PD_RANGE_MIN_DAYS)
      return(false);

   double average = sum / used;
   return(range < average * PD_g_stubLimit / 100.0);
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
//| InpPD_SkipStubCandle switches the behaviour back to the original. |
//+------------------------------------------------------------------+
int PD_SourceCandle(const int start, const int d1bars)
{
   int idx = start;
   if(idx > d1bars - 1)
      return(-1);
   if(!InpPD_SkipStubCandle)
      return(idx);

   for(int step = 0; step < PD_STUB_MAX_STEPS; step++)
   {
      if(!PD_IsStubCandle(idx, d1bars))
         break;
      if(idx + 1 > d1bars - 1)
         break;
      idx++;
   }
   return(idx);
}

//+------------------------------------------------------------------+
//| One level: a day long segment plus its optional tag              |
//+------------------------------------------------------------------+
void PD_DrawLevel(const string tag,
                  const datetime dayStart,
                  const datetime dayEnd,
                  const double price,
                  const color clr,
                  const ENUM_LINE_STYLE style)
{
   string stamp = IntegerToString((long)dayStart);
   string name  = PD_PREFIX + tag + "_" + stamp;

   if(!ObjectCreate(0, name, OBJ_TREND, 0, dayStart, price, dayEnd, price))
      return;

   // MT4 renders a non solid style only at width 1, a wider line would be
   // drawn solid and the styles could no longer be told apart.
   int width = (style == STYLE_SOLID ? PD_g_width : 1);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   if(!InpPD_ShowLabels)
      return;

   string label = PD_PREFIX + tag + "T_" + stamp;
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
//| Rebuild every level of the chosen window                         |
//+------------------------------------------------------------------+
void PD_DrawAll(const int d1bars)
{
   ObjectsDeleteAll(0, PD_PREFIX);

   // Day index 0 is the current day. Its source candle is index 1, so the
   // oldest day we can serve is d1bars-2.
   int maxDays = PD_g_days;
   if(maxDays > d1bars - 1)
      maxDays = d1bars - 1;

   for(int d = 0; d < maxDays; d++)
   {
      if(d == 0 && !InpPD_DrawToday)
         continue;
      if(d > 0 && !InpPD_DrawEarlier)
         continue;

      datetime dayStart = iTime(Symbol(), PERIOD_D1, d);
      if(dayStart <= 0)
         break;

      // End of the day: one second before the next day opens. For the
      // current day there is no next candle yet, so a full day is used and
      // the segment reaches to the end of the session.
      datetime dayEnd = dayStart + PD_DAY_SECONDS - 1;
      if(d > 0)
      {
         datetime nextStart = iTime(Symbol(), PERIOD_D1, d - 1);
         if(nextStart > dayStart)
            dayEnd = nextStart - 1;
      }

      int src = PD_SourceCandle(d + 1, d1bars);
      if(src < 0)
         continue;

      double srcHigh  = iHigh(Symbol(),  PERIOD_D1, src);
      double srcLow   = iLow(Symbol(),   PERIOD_D1, src);
      double srcOpen  = iOpen(Symbol(),  PERIOD_D1, src);
      double srcClose = iClose(Symbol(), PERIOD_D1, src);
      if(srcHigh <= 0.0 || srcLow <= 0.0)
         continue;

      if(InpPD_ShowHigh)
         PD_DrawLevel("PDH", dayStart, dayEnd, srcHigh, InpPD_HighColor, InpPD_HighStyle);
      if(InpPD_ShowLow)
         PD_DrawLevel("PDL", dayStart, dayEnd, srcLow, InpPD_LowColor, InpPD_LowStyle);
      if(InpPD_ShowMid)
         PD_DrawLevel("PDM", dayStart, dayEnd, (srcHigh + srcLow) / 2.0, InpPD_MidColor, InpPD_MidStyle);
      if(InpPD_ShowOpen)
         PD_DrawLevel("PDO", dayStart, dayEnd, srcOpen, InpPD_OpenColor, InpPD_OpenStyle);
      if(InpPD_ShowClose)
         PD_DrawLevel("PDC", dayStart, dayEnd, srcClose, InpPD_CloseColor, InpPD_CloseStyle);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Redraw only when the daily data changed                          |
//|                                                                  |
//| The segments have fixed times and prices, so scrolling or zooming |
//| does not change them. Only a new daily candle or newly loaded     |
//| daily history does. Rebuilding a few hundred objects on every     |
//| tick would make the terminal slow for no gain.                    |
//+------------------------------------------------------------------+
void PD_Refresh()
{
   // The master switch is checked on every pass, not only in OnInit,
   // so turning the group off takes its objects with it.
   if(!InpShowPrevDay)
   {
      if(PD_g_active)
      {
         ObjectsDeleteAll(0, PD_PREFIX);
         PD_g_lastDayOpen = 0;
         PD_g_lastDayBars = 0;
         PD_g_active      = false;
         ChartRedraw();
      }
      return;
   }

   if(PD_g_blocked)
      return;

   int d1bars = iBars(Symbol(), PERIOD_D1);
   datetime dayOpen = (d1bars > 1 ? iTime(Symbol(), PERIOD_D1, 0) : 0);

   // The most common reason such an indicator shows nothing at all:
   // the daily history is simply not loaded yet.
   if(d1bars < 2 || dayOpen <= 0)
   {
      if(!PD_g_warned)
      {
         Print("TG_Levels previous day: daily history of ", Symbol(),
               " not available yet (D1 bars: ", d1bars,
               "). Open the D1 chart once, then nothing else is needed.");
         PD_g_warned = true;
      }
      return;
   }
   PD_g_warned = false;

   if(dayOpen == PD_g_lastDayOpen && d1bars == PD_g_lastDayBars)
      return;

   PD_g_lastDayOpen = dayOpen;
   PD_g_lastDayBars = d1bars;
   PD_g_active      = true;
   PD_DrawAll(d1bars);
}

//+------------------------------------------------------------------+
//| Group initialisation                                             |
//+------------------------------------------------------------------+
void PD_Init()
{
   PD_g_days = InpPD_Days;
   if(PD_g_days < 1)
   {
      Print("TG_Levels previous day: InpPD_Days below 1, using 1.");
      PD_g_days = 1;
   }
   if(PD_g_days > 1000)
   {
      Print("TG_Levels previous day: InpPD_Days above 1000, using 1000.");
      PD_g_days = 1000;
   }

   PD_g_stubLimit = InpPD_StubMaxPercent;
   if(PD_g_stubLimit < 0.0)
   {
      Print("TG_Levels previous day: InpPD_StubMaxPercent below 0, using 0.");
      PD_g_stubLimit = 0.0;
   }
   if(PD_g_stubLimit > 100.0)
   {
      Print("TG_Levels previous day: InpPD_StubMaxPercent above 100, using 100.");
      PD_g_stubLimit = 100.0;
   }

   PD_g_width = InpPD_LineWidth;
   if(PD_g_width < 1)
      PD_g_width = 1;
   if(PD_g_width > 5)
      PD_g_width = 5;

   // One W1 or MN1 candle spans several days, so a per day segment has no
   // place to live there. Leave quietly instead of drawing something wrong.
   // Only this group stops here, the other two keep drawing.
   PD_g_blocked = (Period() == PERIOD_W1 || Period() == PERIOD_MN1);
   if(PD_g_blocked)
   {
      Print("TG_Levels previous day: W1 and MN1 are not supported, one candle covers several days. Nothing drawn.");
      return;
   }

   // A parameter change runs OnDeinit and OnInit again, so the stored
   // drawing state has to start empty here.
   PD_g_lastDayOpen = 0;
   PD_g_lastDayBars = 0;
   PD_g_warned      = false;
   PD_g_active      = false;

   PD_Refresh();
}

//+------------------------------------------------------------------+
//| Group clean up                                                   |
//+------------------------------------------------------------------+
void PD_Deinit()
{
   ObjectsDeleteAll(0, PD_PREFIX);
   PD_g_active = false;
}

//====================================================================
//  GROUP WM — WEEKLY MAP
//====================================================================

//--- What this group draws -----------------------------------------
// Source of every number is the PREVIOUS weekly candle (PERIOD_W1):
//   H = high, L = low, range = H - L.
// The resulting 13 levels are drawn across the FOLLOWING week only,
// so each week carries the map of the week before it.
//   H, L, 50%            solid
//   25%, 75%             dotted
//   H + range*0.25 .. H + range*1.00   upper extensions
//   L - range*0.25 .. L - range*1.00   lower extensions
// Extensions are dotted, the two outer ones (+100% / -100%) solid.
// With a 40 point range, "+25%" therefore sits 10 points above the
// high — the same arithmetic the public description spells out as
// 1.25x, 1.5x, 1.75x, 2x (and the mirrored values below the low).

//--- Why InpWM_Levels is one string and not fourteen check boxes ---
// Fourteen booleans would push the property dialog over one screen,
// they cannot be saved as a short preset line, and every new level
// would need a new input plus a new branch. One comma separated key
// list stays readable in a .set file, can be copied between charts
// and keeps the drawing loop a single table walk.

//--- object name space of this group
#define WM_PREFIX "TGL_WM_"

#define WM_LEVELS 13

//--- Level table ---------------------------------------------------
// price = (fromHigh ? H : L) + factor * range
string WM_g_key[WM_LEVELS] =
   {"H","L","50","25","75","+25","+50","+75","+100","-25","-50","-75","-100"};
string WM_g_label[WM_LEVELS] =
   {"H","L","50%","25%","75%","+25%","+50%","+75%","+100%","-25%","-50%","-75%","-100%"};
bool   WM_g_fromHigh[WM_LEVELS] =
   {true,false,false,false,false,true,true,true,true,false,false,false,false};
double WM_g_factor[WM_LEVELS] =
   {0.0,0.0,0.5,0.25,0.75,0.25,0.5,0.75,1.0,-0.25,-0.5,-0.75,-1.0};
int    WM_g_role[WM_LEVELS] =          // 0 = main, 1 = sub, 2 = extension
   {0,0,0,1,1,2,2,2,2,2,2,2,2};
bool   WM_g_solidLine[WM_LEVELS] =     // false = dotted
   {true,true,true,false,false,false,false,false,true,false,false,false,true};

//--- State ---------------------------------------------------------
string   WM_g_filter   = "";    // normalised key list, framed by commas
bool     WM_g_allOn    = true;  // true when InpWM_Levels is empty
int      WM_g_weeks    = 10;    // validated copy of InpWM_Weeks
int      WM_g_width    = 1;     // validated copy of InpWM_LineWidth
double   WM_g_gapDist  = 0.0;   // minimum gap distance as a price distance
datetime WM_g_anchor   = 0;     // open time of the weekly bar the drawing was built from
int      WM_g_wBars    = 0;     // weekly bars available at that moment
bool     WM_g_drawn    = false; // true while our objects are on the chart

//+------------------------------------------------------------------+
//| Normalise InpWM_Levels once, so the test per line stays cheap    |
//+------------------------------------------------------------------+
void WM_BuildLevelFilter()
  {
   string s = InpWM_Levels;
   StringReplace(s, " ", "");
   StringReplace(s, "\t", "");
   StringToUpper(s);
   WM_g_allOn  = (StringLen(s) == 0);
   WM_g_filter = "," + s + ",";
  }

//+------------------------------------------------------------------+
//| Is this level key part of the selection?                         |
//+------------------------------------------------------------------+
bool WM_LevelOn(const string key)
  {
   if(WM_g_allOn)
      return(true);
   return(StringFind(WM_g_filter, "," + key + ",") >= 0);
  }

//+------------------------------------------------------------------+
//| Remove every object of this group                                |
//+------------------------------------------------------------------+
void WM_ClearAll()
  {
   ObjectsDeleteAll(0, WM_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| One horizontal segment, limited to a single week                 |
//+------------------------------------------------------------------+
void WM_DrawSegment(const string tag, const datetime t1, const datetime t2,
                    const double price, const color clr, const bool solid)
  {
   string name = WM_PREFIX + "L_" + tag;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
     {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      solid ? STYLE_SOLID : STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      WM_g_width);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);   // behind the candles
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);   // keep the object list clean
  }

//+------------------------------------------------------------------+
//| Level name at the left edge of its segment                       |
//+------------------------------------------------------------------+
void WM_DrawLabel(const string tag, const datetime t1, const double price,
                  const color clr, const string txt)
  {
   if(!InpWM_ShowLabels)
      return;
   string name = WM_PREFIX + "T_" + tag;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t1, price);
   else
      ObjectMove(0, name, 0, t1, price);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Tahoma");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   8);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
   // Labels stay in front on purpose: text behind the candles is
   // unreadable. Only the price lines are pushed to the background.
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

//+------------------------------------------------------------------+
//| Colour for a level role                                          |
//+------------------------------------------------------------------+
color WM_RoleColor(const int role)
  {
   if(role == 0)
      return(InpWM_MainColor);
   if(role == 1)
      return(InpWM_SubColor);
   return(InpWM_ExtColor);
  }

//+------------------------------------------------------------------+
//| Weekend gap: close of the old week against open of the new one   |
//+------------------------------------------------------------------+
void WM_DrawWeekendGap(const int shift, const datetime t1, const datetime t2,
                       const string stamp)
  {
   if(!InpWM_ShowGap)
      return;
   double prevClose = iClose(_Symbol, PERIOD_W1, shift + 1);
   double weekOpen  = iOpen(_Symbol,  PERIOD_W1, shift);
   if(prevClose <= 0.0 || weekOpen <= 0.0)
      return;
   double dist = MathAbs(weekOpen - prevClose);
   if(dist < WM_g_gapDist)
      return;                                  // too small to be worth a line
   color clr = (weekOpen > prevClose) ? InpWM_GapUpColor : InpWM_GapDownColor;
   WM_DrawSegment(stamp + "_GAPC", t1, t2, prevClose, clr, true);
   WM_DrawSegment(stamp + "_GAPO", t1, t2, weekOpen,  clr, true);
   WM_DrawLabel(stamp + "_GAPC", t1, prevClose, clr, "W close");
   WM_DrawLabel(stamp + "_GAPO", t1, weekOpen,  clr, "W open");
  }

//+------------------------------------------------------------------+
//| Map one week: shift is the weekly bar index, 0 = current week     |
//+------------------------------------------------------------------+
void WM_DrawWeek(const int shift)
  {
   double high  = iHigh(_Symbol,  PERIOD_W1, shift + 1);
   double low   = iLow(_Symbol,   PERIOD_W1, shift + 1);
   double range = high - low;
   if(range <= 0.0)
      return;                                  // degenerate week, nothing to scale

   datetime t1 = iTime(_Symbol, PERIOD_W1, shift);
   if(t1 <= 0)
      return;
   // End of the week: the start of the next weekly bar, or one week
   // ahead while the current week is still running.
   datetime t2 = (shift > 0) ? iTime(_Symbol, PERIOD_W1, shift - 1)
                             : (datetime)(t1 + 7 * 24 * 60 * 60);

   string stamp = IntegerToString((int)t1);

   for(int i = 0; i < WM_LEVELS; i++)
     {
      if(!WM_LevelOn(WM_g_key[i]))
         continue;
      double base  = (WM_g_fromHigh[i] ? high : low);
      double price = base + WM_g_factor[i] * range;
      color  clr   = WM_RoleColor(WM_g_role[i]);
      string tag   = stamp + "_" + WM_g_key[i];
      WM_DrawSegment(tag, t1, t2, price, clr, WM_g_solidLine[i]);
      WM_DrawLabel(tag, t1, price, clr, WM_g_label[i]);
     }

   WM_DrawWeekendGap(shift, t1, t2, stamp);
  }

//+------------------------------------------------------------------+
//| Rebuild the whole map                                            |
//+------------------------------------------------------------------+
void WM_Rebuild(const int wBars)
  {
   ObjectsDeleteAll(0, WM_PREFIX);
   int maxWeeks = (int)MathMin(WM_g_weeks, wBars - 1); // every week needs its predecessor
   for(int shift = 0; shift < maxWeeks; shift++)
      WM_DrawWeek(shift);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Redraw only when something really changed                        |
//+------------------------------------------------------------------+
void WM_RefreshIfNeeded()
  {
   // The master switch is checked on every pass, not only in OnInit,
   // so turning the group off takes its objects with it.
   if(!InpShowWeeklyMap)
     {
      if(WM_g_drawn)
        {
         WM_ClearAll();
         WM_g_drawn = false;
         WM_g_anchor = 0;
         WM_g_wBars  = 0;
        }
      return;
     }

   // The monthly chart is explicitly out of scope for this group:
   // weekly segments would be thinner than a single bar there. The
   // other groups are not affected by this exit.
   if(Period() == PERIOD_MN1)
     {
      if(WM_g_drawn)
        {
         WM_ClearAll();
         WM_g_drawn = false;
         WM_g_anchor = 0;
         WM_g_wBars  = 0;
        }
      return;
     }

   int wBars = iBars(_Symbol, PERIOD_W1);
   if(wBars < 2)
      return;                                  // weekly history not there yet
   datetime w0 = iTime(_Symbol, PERIOD_W1, 0);
   if(w0 <= 0)
      return;

   // A new weekly bar, or more weekly history arriving from the
   // server, are the only two reasons to touch the objects again.
   if(WM_g_drawn && w0 == WM_g_anchor && wBars == WM_g_wBars)
      return;

   WM_Rebuild(wBars);
   WM_g_anchor = w0;
   WM_g_wBars  = wBars;
   WM_g_drawn  = true;
  }

//+------------------------------------------------------------------+
//| Group initialisation                                             |
//+------------------------------------------------------------------+
void WM_Init()
  {
   WM_g_weeks   = (int)MathMax(1, MathMin(100, InpWM_Weeks));
   WM_g_width   = (int)MathMax(1, MathMin(5,   InpWM_LineWidth));
   WM_g_gapDist = MathMax(0, InpWM_GapMinPoints) * _Point;
   WM_BuildLevelFilter();
   WM_g_anchor = 0;
   WM_g_wBars  = 0;
   WM_g_drawn  = false;
   WM_RefreshIfNeeded();
  }

//+------------------------------------------------------------------+
//| Group clean up                                                   |
//+------------------------------------------------------------------+
void WM_Deinit()
  {
   ObjectsDeleteAll(0, WM_PREFIX);
   WM_g_drawn = false;
  }

//====================================================================
//  ENTRY POINTS — one each, every group is called in turn
//====================================================================

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("TG_Levels");

   // A restart must not inherit stale objects from the previous run.
   ObjectsDeleteAll(0, TGL_ROOT);

   RL_Init();
   PD_Init();
   WM_Init();

   // One timer for all groups. The weekly map needs it to pick up
   // weekly history that arrives without ticks, the others are happy
   // to be asked as well.
   EventSetTimer(5);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Clean up: no object of ours may survive the indicator            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   RL_Deinit();
   PD_Deinit();
   WM_Deinit();

   ObjectsDeleteAll(0, TGL_ROOT);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Tick handler: every group decides for itself whether it has      |
//| work to do, the checks are cheap by design.                      |
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
   RL_Refresh(false);
   PD_Refresh();
   WM_RefreshIfNeeded();
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Zoom, scroll, resize and timeframe changes arrive here           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      RL_Refresh(false);
      PD_Refresh();
      WM_RefreshIfNeeded();
   }
}

//+------------------------------------------------------------------+
//| Timer: catches history that arrives while no tick comes in,      |
//| for example over the weekend.                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   PD_Refresh();
   WM_RefreshIfNeeded();
}
//+------------------------------------------------------------------+
