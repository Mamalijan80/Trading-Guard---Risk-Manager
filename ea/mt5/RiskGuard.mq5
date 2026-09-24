// TradingGuard — Risiko- und Disziplin-Tool fuer MetaTrader 4
// Copyright (C) 2026 Mohammadreza Tavakoli — https://itavakoli.com/
//
// Dieses Programm ist freie Software: Sie koennen es weitergeben und/oder
// veraendern unter den Bedingungen der GNU Affero General Public License,
// Version 3 oder (nach Ihrer Wahl) jeder spaeteren Version.
//
// Die Veroeffentlichung erfolgt in der Hoffnung, dass es nuetzlich ist, aber
// OHNE JEDE GEWAEHRLEISTUNG — sogar ohne die implizite Gewaehrleistung der
// MARKTGAENGIGKEIT oder EIGNUNG FUER EINEN BESTIMMTEN ZWECK. Einzelheiten in
// der GNU Affero General Public License: <https://www.gnu.org/licenses/>.
//
// KEINE ANLAGEBERATUNG. Handel mit Hebelprodukten kann zum Totalverlust
// fuehren. Dieses Werkzeug erzwingt Regeln, es trifft keine Marktentscheidung
// und uebernimmt keine Verantwortung fuer Handelsergebnisse.
//+------------------------------------------------------------------+
//|  RiskGuard.mq5  —  TradingGuard EA-Boden, v0.4                    |
//|  Erzwingt:  R4  Tagesverlust-Hard-Lock (2%)                       |
//|             R4b Gesamtverlust-Sperre (8%, permanent)             |
//|             R7  SL/TP-Pflicht mit 10s-Frist                       |
//|             R1  Risiko pro Trade (max %, schliesst zu grosse)     |
//|  Crash-hardened, Tamper-Warnung, LIVE-Panel (Floating-P/L,Risiko).|
//|                                                                  |
//|  ⚠ NUR DEMO. Gilt als UNGETESTET bis im MetaEditor kompiliert.   |
//+------------------------------------------------------------------+
#property copyright "Mohammadreza Tavakoli"
#property link      "https://itavakoli.com/"
#property strict
#include <Trade/Trade.mqh>

input double InpInitialBalance   = 20000;  // FTMO-Startbalance (z.B. 20000). 0 = automatisch/persistiert
input double InpDailyLossPct     = 2.0;    // R4:  Tagesverlust-Sperre in % (< FTMO 5%)
input double InpMaxLossPct       = 8.0;    // R4b: Gesamtverlust-Sperre in % (< FTMO 10%)
input double InpRiskPerTradePct  = 0.5;    // R1:  max Risiko pro Trade in % der Equity
input double InpRiskTolFactor    = 1.10;   // R1:  Toleranz gegen Rundung/Spread (1.10 = 10%)
input bool   InpRequireSL        = true;   // R7:  SL Pflicht
input bool   InpRequireTP        = true;   // R7:  TP Pflicht
input int    InpSLTPGraceSeconds = 10;     // R7:  Frist zum Nachtragen von SL/TP
input int    InpTimerSeconds     = 1;      // Poll-Intervall
input int    InpMinActionMs      = 400;    // Drossel gegen Request-Storm (Crash-Schutz)
input bool   InpUseAlert         = false;  // Alert kann unter Wine instabil sein -> default aus

CTrade trade;

#define GV_DAYSTART_EQ   "RG_DAYSTART_EQ"
#define GV_DAYSTART_DAY  "RG_DAYSTART_DAY"
#define GV_LOCK_UNTIL    "RG_LOCK_UNTIL"
#define GV_HARD_LOCK     "RG_HARD_LOCK"
#define GV_INIT_BAL      "RG_INIT_BAL"
#define PFX              "RG_"

double g_initialBalance = 0;
uint   g_lastActionMs   = 0;
bool   g_warnedDisabled = false;

ulong    g_nakedTicket[];
datetime g_nakedSince[];

long ServerDayKey(){ MqlDateTime t; TimeToStruct(TimeTradeServer(),t); return (long)t.year*10000+(long)t.mon*100+(long)t.day; }
datetime NextServerMidnight(){ MqlDateTime t; TimeToStruct(TimeTradeServer(),t); t.hour=0; t.min=0; t.sec=0; return StructToTime(t)+86400; }

int OnInit()
{
   if(InpInitialBalance>0)                                                       g_initialBalance=InpInitialBalance;
   else if(GlobalVariableCheck(GV_INIT_BAL) && GlobalVariableGet(GV_INIT_BAL)>0) g_initialBalance=GlobalVariableGet(GV_INIT_BAL);
   else                                                                          g_initialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   GlobalVariableSet(GV_INIT_BAL,g_initialBalance);

   long today=ServerDayKey();
   if(!GlobalVariableCheck(GV_DAYSTART_DAY) || (long)GlobalVariableGet(GV_DAYSTART_DAY)!=today) RollNewDay();
   EventSetTimer(InpTimerSeconds);
   Enforce();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){ EventKillTimer(); DeletePanel(); Comment(""); }
void OnTick(){ Guarded(); }
void OnTimer(){ Guarded(); }
void OnTradeTransaction(const MqlTradeTransaction &tr,const MqlTradeRequest &rq,const MqlTradeResult &rs){ Guarded(); }

void Guarded()
{
   uint now=GetTickCount();
   if(now - g_lastActionMs < (uint)InpMinActionMs) return;
   g_lastActionMs = now;
   Enforce();
}

void RollNewDay()
{
   GlobalVariableSet(GV_DAYSTART_EQ,  AccountInfoDouble(ACCOUNT_EQUITY));
   GlobalVariableSet(GV_DAYSTART_DAY, (double)ServerDayKey());
   GlobalVariableSet(GV_LOCK_UNTIL,   0);
   GlobalVariablesFlush();
   PrintFormat("RiskGuard: neuer Handelstag. Basis-Equity=%.2f", AccountInfoDouble(ACCOUNT_EQUITY));
}

bool IsHardLocked(){ return GlobalVariableCheck(GV_HARD_LOCK) && GlobalVariableGet(GV_HARD_LOCK)>0.5; }
bool IsDayLocked(){ if(!GlobalVariableCheck(GV_LOCK_UNTIL)) return false; datetime u=(datetime)GlobalVariableGet(GV_LOCK_UNTIL); return (u>0 && TimeTradeServer()<u); }
void Notify(string m){ Print(m); if(InpUseAlert) Alert(m); }

int FindNaked(ulong t){ for(int i=0;i<ArraySize(g_nakedTicket);i++) if(g_nakedTicket[i]==t) return i; return -1; }
void AddNaked(ulong t){ int n=ArraySize(g_nakedTicket); ArrayResize(g_nakedTicket,n+1); ArrayResize(g_nakedSince,n+1); g_nakedTicket[n]=t; g_nakedSince[n]=TimeLocal(); }
void RemoveNakedAt(int idx){ int n=ArraySize(g_nakedTicket); for(int i=idx;i<n-1;i++){ g_nakedTicket[i]=g_nakedTicket[i+1]; g_nakedSince[i]=g_nakedSince[i+1]; } ArrayResize(g_nakedTicket,n-1); ArrayResize(g_nakedSince,n-1); }
void RemoveNaked(ulong t){ int idx=FindNaked(t); if(idx>=0) RemoveNakedAt(idx); }
void PruneNaked(){ for(int i=ArraySize(g_nakedTicket)-1;i>=0;i--) if(!PositionSelectByTicket(g_nakedTicket[i])) RemoveNakedAt(i); }

void Enforce()
{
   long today=ServerDayKey();
   if(!GlobalVariableCheck(GV_DAYSTART_DAY) || (long)GlobalVariableGet(GV_DAYSTART_DAY)!=today) RollNewDay();

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double base=GlobalVariableGet(GV_DAYSTART_EQ);
   if(base<=0){ base=eq; GlobalVariableSet(GV_DAYSTART_EQ,eq); }

   double dailyDDpct=(base-eq)/base*100.0;                         if(dailyDDpct<0) dailyDDpct=0;
   double totalDDpct=(g_initialBalance-eq)/g_initialBalance*100.0; if(totalDDpct<0) totalDDpct=0;

   bool tradingDisabled = !( (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) );
   if(tradingDisabled && !g_warnedDisabled){ Notify("RiskGuard: WARNUNG — AutoTrading ist AUS. Schutz inaktiv!"); g_warnedDisabled=true; }
   if(!tradingDisabled) g_warnedDisabled=false;

   if(!IsHardLocked() && totalDDpct>=InpMaxLossPct)
   { GlobalVariableSet(GV_HARD_LOCK,1); GlobalVariablesFlush(); Notify(StringFormat("RiskGuard: MAX-LOSS-SPERRE (%.2f%%).", totalDDpct)); }
   if(!IsDayLocked() && !IsHardLocked() && dailyDDpct>=InpDailyLossPct)
   { GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariablesFlush(); Notify(StringFormat("RiskGuard: TAGESVERLUST-SPERRE (%.2f%%).", dailyDDpct)); }

   if(!tradingDisabled)
   {
      if(IsDayLocked() || IsHardLocked()) SafeCloseAll();
      else                              { EnforceSLTP(); EnforceRisk(); }
   }
   UpdatePanel(dailyDDpct,totalDDpct,tradingDisabled);
}

void EnforceSLTP()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      bool naked=( (InpRequireSL && PositionGetDouble(POSITION_SL)==0.0) || (InpRequireTP && PositionGetDouble(POSITION_TP)==0.0) );
      int idx=FindNaked(ticket);
      if(naked)
      {
         if(idx<0){ AddNaked(ticket); PrintFormat("RiskGuard: %I64u (%s) ohne SL/TP — %ds Frist laeuft.", ticket, PositionGetString(POSITION_SYMBOL), InpSLTPGraceSeconds); }
         else if(TimeLocal()-g_nakedSince[idx] >= InpSLTPGraceSeconds)
         {
            PrintFormat("RiskGuard: %I64u (%s) nach %ds ohne SL/TP -> schliesse (R7).", ticket, PositionGetString(POSITION_SYMBOL), InpSLTPGraceSeconds);
            if(trade.PositionClose(ticket)) RemoveNaked(ticket);
         }
      }
      else if(idx>=0) RemoveNaked(ticket);
   }
   PruneNaked();
}

void EnforceRisk()   // R1: zu grosse Positionen schliessen
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY); if(eq<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      double sl=PositionGetDouble(POSITION_SL); if(sl==0.0) continue;   // ohne SL -> R7
      string s=PositionGetString(POSITION_SYMBOL);
      double ts=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE), tv=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE);
      if(ts<=0.0 || tv<=0.0) continue;
      double riskPct=(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-sl)/ts)*tv*PositionGetDouble(POSITION_VOLUME)/eq*100.0;
      if(riskPct > InpRiskPerTradePct*InpRiskTolFactor)
      {
         PrintFormat("RiskGuard: %I64u (%s) Risiko %.2f%% > erlaubt %.2f%% -> schliesse (R1).", ticket, s, riskPct, InpRiskPerTradePct);
         trade.PositionClose(ticket);
      }
   }
}

void SafeCloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t>0) trade.PositionClose(t); }
   for(int i=OrdersTotal()-1;i>=0;i--){ ulong t=OrderGetTicket(i); if(t>0) trade.OrderDelete(t); }
}

//--- Live-Kennzahlen fuer das Panel ---------------------------------
double OpenFloatingPL(){ return AccountInfoDouble(ACCOUNT_PROFIT); }
double OpenRiskPct(int &count)
{
   count=0; double eq=AccountInfoDouble(ACCOUNT_EQUITY); if(eq<=0) return 0.0;
   double sum=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !PositionSelectByTicket(t)) continue;
      count++;
      double sl=PositionGetDouble(POSITION_SL); if(sl==0.0) continue;
      string s=PositionGetString(POSITION_SYMBOL);
      double ts=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE), tv=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE);
      if(ts<=0.0 || tv<=0.0) continue;
      sum += (MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-sl)/ts)*tv*PositionGetDouble(POSITION_VOLUME);
   }
   return sum/eq*100.0;
}

//--- On-Chart-Panel -------------------------------------------------
void Lbl(string name,int x,int y,string text,color col,int size)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}
void Bg(string name,int x,int y,int w,int h,color col)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,col);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}
void UpdatePanel(double dd,double tdd,bool disabled)
{
   string state; color bg;
   if(disabled)            { state="SCHUTZ AUS!";        bg=clrDarkOrange; }
   else if(IsHardLocked()) { state="MAX-LOSS GESPERRT";  bg=clrCrimson; }
   else if(IsDayLocked())  { state="TAGES-SPERRE";       bg=clrCrimson; }
   else                    { state="aktiv";              bg=C'20,70,45'; }

   int cnt=0; double riskPct=OpenRiskPct(cnt); double pl=OpenFloatingPL();

   Bg (PFX+"bg",10,18,252,150,bg);
   Lbl(PFX+"t", 22,24, "R I S K G U A R D",clrWhite,10);
   Lbl(PFX+"s", 22,44, state,clrWhite,13);
   Lbl(PFX+"d", 22,72, StringFormat("Tag:     %.2f%%  /  %.2f%%",dd,InpDailyLossPct),clrWhite,9);
   Lbl(PFX+"g", 22,90, StringFormat("Gesamt:  %.2f%%  /  %.2f%%",tdd,InpMaxLossPct),clrWhite,9);
   Lbl(PFX+"o", 22,114,StringFormat("Offen: %d    P/L: %.2f",cnt,pl), (pl<0?clrGold:clrWhite),9);
   Lbl(PFX+"r", 22,132,StringFormat("Offenes Risiko: %.2f%% / max %.2f%%",riskPct,InpRiskPerTradePct),clrWhite,9);
   ChartRedraw(0);
}
void DeletePanel(){ ObjectDelete(0,PFX+"bg"); ObjectDelete(0,PFX+"t"); ObjectDelete(0,PFX+"s"); ObjectDelete(0,PFX+"d"); ObjectDelete(0,PFX+"g"); ObjectDelete(0,PFX+"o"); ObjectDelete(0,PFX+"r"); }
//+------------------------------------------------------------------+
