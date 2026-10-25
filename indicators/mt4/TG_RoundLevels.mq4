//+------------------------------------------------------------------+
//|  TG_RoundLevels.mq4  —  TradingGuard level indicator             |
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

//--- inputs ---------------------------------------------------------
input bool            InpAutoSpacing   = true;        // auto spacing from price, otherwise InpManualStep
input double          InpAutoPercent   = 0.5;         // auto step as percent of current price
input double          InpRecalcPercent = 20.0;        // recompute step only after price moved this many percent
input double          InpManualStep    = 250;         // fixed step in price units (used when auto spacing is off)
input bool            InpShowLabels    = true;        // print the price value next to each line
input int             InpMaxLines      = 300;         // hard cap on drawn levels (centre of screen wins)
input color           InpLineColor     = clrDimGray;  // colour of the level lines
input ENUM_LINE_STYLE InpLineStyle     = STYLE_DOT;   // dotted and dashed styles only render as such at width 1
input int             InpLineWidth     = 1;           // line width in pixels
input color           InpLabelColor    = clrSilver;   // colour of the price labels
input int             InpLabelSize     = 8;           // label font size
input string          InpLabelFont     = "Tahoma";    // label font family

//--- private object namespace, must not clash with the panel ("MMT_")
#define TGRL_PREFIX     "TGRL_"
#define TGRL_LINE       "TGRL_L_"
#define TGRL_TEXT       "TGRL_T_"
#define TGRL_LABEL_GAP  3            // label offset to the right, in chart periods
#define TGRL_NICE_COUNT 5

//--- cached state: everything that decides whether a redraw is needed
double   g_step        = 0.0;        // current level distance in price units
double   g_refPrice    = 0.0;        // price the current step was computed from
int      g_slotsUsed   = 0;          // number of object slots written on the last draw
int      g_lowIndex    = 0;          // first drawn level index (level = index * step)
int      g_highIndex   = -1;         // last drawn level index
datetime g_labelTime   = 0;          // time anchor used for the labels
bool     g_capped      = false;      // true while levels are being hidden by InpMaxLines
bool     g_noticeShown = false;      // true while our ShowNotice() text is on the chart
int      g_maxLines    = 300;        // validated copy of InpMaxLines
double   g_manualStep  = 250.0;      // validated copy of InpManualStep
double   g_autoPercent = 0.5;        // validated copy of InpAutoPercent

//+------------------------------------------------------------------+
//| Round a raw distance up or down to the nearest friendly number:  |
//| 1, 2, 2.5 or 5 times a power of ten.                             |
//+------------------------------------------------------------------+
double NiceStep(const double raw)
{
   if(raw <= 0.0)
      return(0.0);

   double nice[TGRL_NICE_COUNT] = {1.0, 2.0, 2.5, 5.0, 10.0};

   double decade   = MathPow(10.0, MathFloor(MathLog10(raw)));
   double mantissa = raw / decade;

   int    pick = 0;
   double gap  = MathAbs(mantissa - nice[0]);
   for(int i = 1; i < TGRL_NICE_COUNT; i++)
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
double ReferencePrice()
{
   if(Bid > 0.0)
      return(Bid);
   if(Bars > 0)
      return(Close[0]);
   return(0.0);
}

//+------------------------------------------------------------------+
//| Keep g_step up to date. In auto mode the step is deliberately    |
//| sticky: it only changes after a move of InpRecalcPercent, so the |
//| grid does not jump around during normal trading.                 |
//+------------------------------------------------------------------+
void UpdateStep()
{
   if(!InpAutoSpacing)
   {
      g_step     = g_manualStep;
      g_refPrice = 0.0;
      return;
   }

   double price = ReferencePrice();
   if(price <= 0.0)
      return;

   if(g_step > 0.0 && g_refPrice > 0.0)
   {
      double moved = MathAbs(price - g_refPrice) / g_refPrice * 100.0;
      if(moved <= InpRecalcPercent)
         return;
   }

   double fresh = NiceStep(price * g_autoPercent / 100.0);
   if(fresh > 0.0)
   {
      g_step     = fresh;
      g_refPrice = price;
   }
}

//+------------------------------------------------------------------+
//| Visible price band of the chart window.                          |
//+------------------------------------------------------------------+
bool VisibleBand(double &low, double &high)
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
datetime LabelTime()
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

   return(Time[shift] + (datetime)(TGRL_LABEL_GAP * PeriodSeconds()));
}

//+------------------------------------------------------------------+
//| Create or refresh one horizontal level line.                     |
//+------------------------------------------------------------------+
void WriteLine(const string name, const double price)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      InpLineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      InpLineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpLineWidth);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Create or refresh one price label at the right chart edge.       |
//+------------------------------------------------------------------+
void WriteLabel(const string name, const datetime when, const double price)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, when, price);

   ObjectSetInteger(0, name, OBJPROP_TIME,  0, when);
   ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0,  name, OBJPROP_TEXT,       DoubleToString(price, _Digits));
   ObjectSetString(0,  name, OBJPROP_FONT,       InpLabelFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpLabelSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      InpLabelColor);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Drop object slots that the current draw no longer needs.         |
//+------------------------------------------------------------------+
void TrimSlots(const int keep)
{
   for(int slot = keep; slot < g_slotsUsed; slot++)
   {
      ObjectDelete(0, TGRL_LINE + IntegerToString(slot));
      ObjectDelete(0, TGRL_TEXT + IntegerToString(slot));
   }
   g_slotsUsed = keep;
}

//+------------------------------------------------------------------+
//| Tell the user why levels are missing above and below.            |
//+------------------------------------------------------------------+
void ShowNotice(const bool capped, const int shown, const int wanted)
{
   if(capped)
   {
      ShowNotice("TG_RoundLevels: " + IntegerToString(wanted) + " levels in view, "
              + IntegerToString(shown) + " drawn (InpMaxLines). "
              + "Levels far from the screen centre are left out.");
      g_noticeShown = true;
      Print("TG_RoundLevels: level cap reached - ", wanted, " in view, ", shown,
            " drawn, step ", DoubleToString(g_step, _Digits));
   }
   else if(g_noticeShown)
   {
      ShowNotice("");
      g_noticeShown = false;
   }
}

//+------------------------------------------------------------------+
//| Redraw the grid, but only when something actually changed.       |
//+------------------------------------------------------------------+
void Refresh(const bool force)
{
   UpdateStep();
   if(g_step <= 0.0)
      return;

   double low, high;
   if(!VisibleBand(low, high))
      return;

   // Levels are counted from zero, so every line sits on an exact
   // multiple of the step and the grid never drifts with the price.
   int lowIndex = (int)MathFloor(low / g_step);
   if(lowIndex * g_step < low)
      lowIndex++;
   int highIndex = (int)MathFloor(high / g_step);

   int wanted = highIndex - lowIndex + 1;
   if(wanted <= 0)
   {
      TrimSlots(0);
      ShowNotice(false, 0, 0);
      ChartRedraw();
      return;
   }

   bool capped = false;
   if(wanted > g_maxLines)                      // keep the band around the screen centre
   {
      int centre = (int)MathRound((low + high) / 2.0 / g_step);
      int from   = centre - g_maxLines / 2;
      int to     = from + g_maxLines - 1;

      if(from < lowIndex)
      {
         from = lowIndex;
         to   = from + g_maxLines - 1;
      }
      if(to > highIndex)
      {
         to   = highIndex;
         from = to - g_maxLines + 1;
      }
      lowIndex  = from;
      highIndex = to;
      capped    = true;
   }

   datetime when = LabelTime();

   if(!force
      && lowIndex  == g_lowIndex
      && highIndex == g_highIndex
      && when      == g_labelTime
      && capped    == g_capped)
      return;                                   // nothing moved, leave the objects alone

   int slot = 0;
   for(int index = lowIndex; index <= highIndex; index++, slot++)
   {
      double level = index * g_step;
      WriteLine(TGRL_LINE + IntegerToString(slot), level);

      if(InpShowLabels && when > 0)
         WriteLabel(TGRL_TEXT + IntegerToString(slot), when, level);
      else
         ObjectDelete(0, TGRL_TEXT + IntegerToString(slot));
   }

   TrimSlots(slot);

   g_lowIndex  = lowIndex;
   g_highIndex = highIndex;
   g_labelTime = when;
   g_capped    = capped;

   ShowNotice(capped, slot, wanted);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Cap notice. Deliberately NOT ShowNotice(): the chart comment is a    |
//| single shared slot. Writing it would overwrite whatever another   |
//| indicator or the TradingGuard EA put there, and clearing it on    |
//| deinit would wipe their text too. An own label in our own         |
//| namespace cannot collide.                                         |
//+------------------------------------------------------------------+
void ShowNotice(const string text)
{
   string n = TGRL_PREFIX + "notice";
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
      ObjectSetString (0, n, OBJPROP_FONT, InpLabelFont);
      ObjectSetInteger(0, n, OBJPROP_COLOR, InpLabelColor);
   }
   ObjectSetString(0, n, OBJPROP_TEXT, text);
}

int OnInit()
{
   g_maxLines    = (InpMaxLines    > 0   ? InpMaxLines    : 1);
   g_manualStep  = (InpManualStep  > 0.0 ? InpManualStep  : 1.0);
   g_autoPercent = (InpAutoPercent > 0.0 ? InpAutoPercent : 0.5);

   if(InpManualStep <= 0.0 && !InpAutoSpacing)
      Print("TG_RoundLevels: InpManualStep must be positive, using 1.0 instead.");
   if(InpAutoPercent <= 0.0 && InpAutoSpacing)
      Print("TG_RoundLevels: InpAutoPercent must be positive, using 0.5 instead.");

   // A restart must not inherit stale objects from the previous run.
   ObjectsDeleteAll(0, TGRL_PREFIX);

   g_step        = 0.0;
   g_refPrice    = 0.0;
   g_slotsUsed   = 0;
   g_lowIndex    = 0;
   g_highIndex   = -1;
   g_labelTime   = 0;
   g_capped      = false;
   g_noticeShown = false;

   IndicatorShortName("TG_RoundLevels");
   Refresh(true);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Clean up every object this indicator owns                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, TGRL_PREFIX);
   if(g_noticeShown)
   {
      ShowNotice("");
      g_noticeShown = false;
   }
   g_slotsUsed = 0;
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Tick work: only the cheap change check, no blind redraw          |
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
   Refresh(false);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Zoom, scroll and resize arrive here                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
      Refresh(false);
}
//+------------------------------------------------------------------+
