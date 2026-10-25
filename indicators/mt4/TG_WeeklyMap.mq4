//+------------------------------------------------------------------+
//|  TG_WeeklyMap.mq4  —  TradingGuard level indicator                |
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

//--- What this indicator draws -------------------------------------
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

//--- Inputs --------------------------------------------------------
input int    InpWeeks        = 10;             // number of weeks to map, current week included (1..100)
input string InpLevels       = "H,L,50,25,75,+25,+50,+75,+100,-25,-50,-75,-100"; // levels to show, empty = all
input bool   InpShowGap      = true;           // mark the weekend gap with two lines
input int    InpGapMinPoints = 5;              // minimum gap distance in points, smaller gaps are ignored
input color  InpMainColor    = clrDodgerBlue;  // colour of H, L and 50%
input color  InpSubColor     = clrSlateGray;   // colour of 25% and 75%
input color  InpExtColor     = clrDarkGoldenrod; // colour of the eight extensions
input color  InpGapUpColor   = clrSeaGreen;    // colour of a gap to the upside
input color  InpGapDownColor = clrOrangeRed;   // colour of a gap to the downside
input int    InpLineWidth    = 1;              // line width of every level (1..5)
input bool   InpShowLabels   = true;           // write the level name next to each line

//--- Why InpLevels is one string and not fourteen check boxes ------
// Fourteen booleans would push the property dialog over one screen,
// they cannot be saved as a short preset line, and every new level
// would need a new input plus a new branch. One comma separated key
// list stays readable in a .set file, can be copied between charts
// and keeps the drawing loop a single table walk.

//--- Object namespace ----------------------------------------------
// Everything this indicator creates starts with this prefix, so it
// can never collide with the TradingGuard panel ("MMT_") or with
// objects a user or another tool placed on the chart.
#define TGWM_PREFIX "TGWM_"

#define TGWM_LEVELS 13

//--- Level table ---------------------------------------------------
// price = (fromHigh ? H : L) + factor * range
string g_key[TGWM_LEVELS] =
   {"H","L","50","25","75","+25","+50","+75","+100","-25","-50","-75","-100"};
string g_label[TGWM_LEVELS] =
   {"H","L","50%","25%","75%","+25%","+50%","+75%","+100%","-25%","-50%","-75%","-100%"};
bool   g_fromHigh[TGWM_LEVELS] =
   {true,false,false,false,false,true,true,true,true,false,false,false,false};
double g_factor[TGWM_LEVELS] =
   {0.0,0.0,0.5,0.25,0.75,0.25,0.5,0.75,1.0,-0.25,-0.5,-0.75,-1.0};
int    g_role[TGWM_LEVELS] =          // 0 = main, 1 = sub, 2 = extension
   {0,0,0,1,1,2,2,2,2,2,2,2,2};
bool   g_solidLine[TGWM_LEVELS] =     // false = dotted
   {true,true,true,false,false,false,false,false,true,false,false,false,true};

//--- State ---------------------------------------------------------
string   g_filter   = "";    // normalised key list, framed by commas
bool     g_allOn    = true;  // true when InpLevels is empty
int      g_weeks    = 10;    // validated copy of InpWeeks
int      g_width    = 1;     // validated copy of InpLineWidth
double   g_gapDist  = 0.0;   // minimum gap distance as a price distance
datetime g_anchor   = 0;     // open time of the weekly bar the drawing was built from
int      g_wBars    = 0;     // weekly bars available at that moment
bool     g_drawn    = false; // true while our objects are on the chart

//+------------------------------------------------------------------+
//| Normalise InpLevels once, so the test per line stays cheap       |
//+------------------------------------------------------------------+
void BuildLevelFilter()
  {
   string s = InpLevels;
   StringReplace(s, " ", "");
   StringReplace(s, "\t", "");
   StringToUpper(s);
   g_allOn  = (StringLen(s) == 0);
   g_filter = "," + s + ",";
  }

//+------------------------------------------------------------------+
//| Is this level key part of the selection?                         |
//+------------------------------------------------------------------+
bool LevelOn(const string key)
  {
   if(g_allOn)
      return(true);
   return(StringFind(g_filter, "," + key + ",") >= 0);
  }

//+------------------------------------------------------------------+
//| Remove every object of this indicator                            |
//+------------------------------------------------------------------+
void ClearAll()
  {
   ObjectsDeleteAll(0, TGWM_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| One horizontal segment, limited to a single week                 |
//+------------------------------------------------------------------+
void DrawSegment(const string tag, const datetime t1, const datetime t2,
                 const double price, const color clr, const bool solid)
  {
   string name = TGWM_PREFIX + "L_" + tag;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
     {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      solid ? STYLE_SOLID : STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      g_width);
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
void DrawLabel(const string tag, const datetime t1, const double price,
               const color clr, const string txt)
  {
   if(!InpShowLabels)
      return;
   string name = TGWM_PREFIX + "T_" + tag;
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
color RoleColor(const int role)
  {
   if(role == 0)
      return(InpMainColor);
   if(role == 1)
      return(InpSubColor);
   return(InpExtColor);
  }

//+------------------------------------------------------------------+
//| Map one week: shift is the weekly bar index, 0 = current week     |
//+------------------------------------------------------------------+
void DrawWeek(const int shift)
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

   for(int i = 0; i < TGWM_LEVELS; i++)
     {
      if(!LevelOn(g_key[i]))
         continue;
      double base  = (g_fromHigh[i] ? high : low);
      double price = base + g_factor[i] * range;
      color  clr   = RoleColor(g_role[i]);
      string tag   = stamp + "_" + g_key[i];
      DrawSegment(tag, t1, t2, price, clr, g_solidLine[i]);
      DrawLabel(tag, t1, price, clr, g_label[i]);
     }

   DrawWeekendGap(shift, t1, t2, stamp);
  }

//+------------------------------------------------------------------+
//| Weekend gap: close of the old week against open of the new one   |
//+------------------------------------------------------------------+
void DrawWeekendGap(const int shift, const datetime t1, const datetime t2,
                    const string stamp)
  {
   if(!InpShowGap)
      return;
   double prevClose = iClose(_Symbol, PERIOD_W1, shift + 1);
   double weekOpen  = iOpen(_Symbol,  PERIOD_W1, shift);
   if(prevClose <= 0.0 || weekOpen <= 0.0)
      return;
   double dist = MathAbs(weekOpen - prevClose);
   if(dist < g_gapDist)
      return;                                  // too small to be worth a line
   color clr = (weekOpen > prevClose) ? InpGapUpColor : InpGapDownColor;
   DrawSegment(stamp + "_GAPC", t1, t2, prevClose, clr, true);
   DrawSegment(stamp + "_GAPO", t1, t2, weekOpen,  clr, true);
   DrawLabel(stamp + "_GAPC", t1, prevClose, clr, "W close");
   DrawLabel(stamp + "_GAPO", t1, weekOpen,  clr, "W open");
  }

//+------------------------------------------------------------------+
//| Rebuild the whole map                                            |
//+------------------------------------------------------------------+
void Rebuild(const int wBars)
  {
   ObjectsDeleteAll(0, TGWM_PREFIX);
   int maxWeeks = (int)MathMin(g_weeks, wBars - 1); // every week needs its predecessor
   for(int shift = 0; shift < maxWeeks; shift++)
      DrawWeek(shift);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Redraw only when something really changed                        |
//+------------------------------------------------------------------+
void RefreshIfNeeded()
  {
   // The monthly chart is explicitly out of scope: weekly segments
   // would be thinner than a single bar there.
   if(Period() == PERIOD_MN1)
     {
      if(g_drawn)
        {
         ClearAll();
         g_drawn = false;
         g_anchor = 0;
         g_wBars  = 0;
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
   if(g_drawn && w0 == g_anchor && wBars == g_wBars)
      return;

   Rebuild(wBars);
   g_anchor = w0;
   g_wBars  = wBars;
   g_drawn  = true;
  }

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorShortName("TG Weekly Map");
   g_weeks   = (int)MathMax(1, MathMin(100, InpWeeks));
   g_width   = (int)MathMax(1, MathMin(5,   InpLineWidth));
   g_gapDist = MathMax(0, InpGapMinPoints) * _Point;
   BuildLevelFilter();
   g_anchor = 0;
   g_wBars  = 0;
   g_drawn  = false;
   EventSetTimer(5);     // picks up weekly history that arrives without ticks
   RefreshIfNeeded();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Clean up: no object of ours may survive the indicator            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ClearAll();
  }

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   RefreshIfNeeded();
  }

//+------------------------------------------------------------------+
//| Chart events                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   // Segments are anchored in time and price, so scrolling and
   // zooming need no work. The event is only used to notice that the
   // chart left or re-entered a timeframe we draw on.
   if(id == CHARTEVENT_CHART_CHANGE)
      RefreshIfNeeded();
  }

//+------------------------------------------------------------------+
//| Tick handler                                                     |
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
   RefreshIfNeeded();
   return(rates_total);
  }
//+------------------------------------------------------------------+
