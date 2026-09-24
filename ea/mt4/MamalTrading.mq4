// TradingGuard — risk and discipline tool for MetaTrader 4
// Copyright (C) 2026 Mohammadreza Tavakoli — https://itavakoli.com/
//
// This program is free software: you may redistribute it and/or
// modify it under the terms of the GNU Affero General Public License,
// version 3 or (at your option) any later version.
//
// It is published in the hope that it will be useful, but
// WITHOUT ANY WARRANTY — not even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Details in
// the GNU Affero General Public License: <https://www.gnu.org/licenses/>.
//
// NOT INVESTMENT ADVICE. Trading leveraged products can lead to total
// loss. This tool enforces rules, it makes no market decision
// and takes no responsibility for trading results.
//+------------------------------------------------------------------+
//|  MamalTrading.mq4  —  Mamal-Trading Risk-Engine, v0.46         |
//|  v0.46: Risk-Free (SL to break-even), draggable TP line,        |
//|   Live-Spread + Kerzen-Countdown, Schrift-/Formskalierung,      |
//|   Auto-fit of the panel to the chart height.                    |
//|  v0.40: 4 Close-Buttons (Full/Chart x Voll/50%) + PanelClose;    |
//|   Close-Erkennung magic-/tab-unabhaengig (RGOPN-Registry +       |
//|   ticket fallback); InpMagic<=0 guard; cockpit-off notice.       |
//|  v0.39: dashboard upgrade — dayBase/weekBase in the JSON,       |
//|   "Tag beenden"-Kommando (Tighten-Only-Selbstsperre).           |
//|  v0.38: Zero-Config — Basis voll-automatisch (Einzahlungs-      |
//|   history or rebuild), no more "BASIS UNSICHER" (base unsure);  |
//|   Konto-Wegweiser pro Login (Multi-Konto-Cockpit).              |
//|  v0.37: InpPanelScale — panel geometry for Windows scaling      |
//|   >100% (1.5 for 150%), against panel overlap.                  |
//|   + Meldungsbox 3-zeilig mit Wort-Umbruch (WrapText), voller    |
//|   Text statt Abschneiden; Box +16px, Buttons nachgerueckt.      |
//|   + cockpit signpost (mamal_files.txt) in the Common folder:    |
//|   server finds the real Files path even with portable/multi-    |
//|   Terminal; Cockpit-Meldung neutral-blau statt rotem Fehler.    |
//|  v0.36: weekly risk selector in panel ([-]/[+], applies to the   |
//|   week; auto-scale cascade scales too, trade counter does not).  |
//|  (rules R1-R19 + R22 + R25; R8/R9/R14/R15/R19/R25 off;           |
//|   auto-scale caps; R22 = panel trades only, magic 0 is closed)   |
//|  v0.34: Audit-Haertung (Konto-Bindung, Lockstate-Reconcile 5s,    |
//|   tighten-only on all lock inputs, no loss laundering,            |
//|   Entry-Regeln nachtraeglich, R2-Monitor, History-Wachhund).      |
//|  v0.35: R22 — manuelle/Handy-Orders (Magic 0) werden geschlossen; |
//|   fremde EA-Magics bleiben unangetastet.                          |
//|  v0.15 P0/P1: FTMO-Basis MathMax + Erststart-Failsafe (P0-5/P1-2)|
//|   Enforce tickunabh. (P0-1) · EA-Close-Ausschluss persistent     |
//|   (P0-3, immediate flush) · history loss resolution (P0-2/4).    |
//|  v0.16: echte Close-Queue (Retry/Backoff/Error-Codes/Journal) +  |
//|   lockstate file (HMAC-light, fail-closed) + protection-off log. |
//|  v0.17: R25 persistent · Audit-Journal · R17 Waehrungsvektor ·    |
//|   R7-Haertung (OpenTime-Anker/News-Grace) · TickValue-Fallback ·  |
//|   Funded-Gate (TOOL_ONLY) · Prop-Firm-Profil · TestMode-Harness.  |
//|  ⚠ DEMO ONLY. UNTESTED — compile proof only after F7=0 errors.   |
//+------------------------------------------------------------------+
#property copyright "Mohammadreza Tavakoli"
#property link      "https://itavakoli.com/"
#property strict

enum WatchScope { TOOL_ONLY, TOOL_PLUS_MANUAL, ALL_POSITIONS };   // reach of the watchdog
enum PropFirm   { PF_FTMO, PF_THE5ERS, PF_FUNDEDNEXT, PF_FUNDINGPIPS, PF_ALPHACAPITAL, PF_CUSTOM };  // Prop-Firm-Profile (FTMO=Default; Limits bleiben Inputs)

extern double InpInitialBalance     = 0;     // B1: 0 = automatic (real account base). Otherwise set the REAL challenge start balance — R4b max loss calculates against it!
extern double InpDayStartBase       = 0;     // P1-2: real FTMO midnight base set manually (0=auto). On a first start in the middle of the day, set it!
extern double InpDailyLossPct       = 2.0;   // R4
extern double InpMaxLossPct         = 6.0;   // R4b Max-Loss-Sperre % (Puffer unter FTMO 10%)
extern bool   InpTightenOnly        = true;  // v0.30 self-lock: loss limits can only be set TIGHTER; LOOSENING takes effect only at the next day change (no tilt loosening)
extern double InpMaxLossWarnPct     = 5.0;   // R4b warn gate: from here on NO new trades (before the lock)
extern double InpRiskPerTradePct    = 0.25;  // R1 (FTMO: konservativ)
extern double InpRiskTolFactor      = 1.10;  // R1/R12
extern bool   InpAutoScale          = true;  // caps derived dynamically from risk/trade (R2->R3/R12 follow)
extern double InpIdeaXrisk          = 2.0;   // R2  Idee-Cap   = X * Risiko/Trade
extern double InpHeatXidea          = 2.0;   // R12 Gesamtrisiko = X * Idee-Cap
extern double InpDayXidea           = 4.0;   // R3  daily budget = X * idea cap (v0.20: 4 -> 2.0% = 400 EUR, so that R4/daily target stays reachable)
extern double InpIdeaCapPct         = 1.0;   // R2  (only if AutoScale=false)
extern double InpDailyRiskBudgetPct = 2.0;   // R3  (only if AutoScale=false; v0.20: 2.0% = 400 EUR)
extern double InpPortfolioHeatPct   = 2.0;   // R12 (only if AutoScale=false)
extern double InpDailyTargetPct     = 3.0;   // R13
extern double InpGivebackArmPct     = 1.0;   // R13
extern double InpGivebackPct        = 1.0;   // R13
extern int    InpCooldownAfter      = 3;     // R5
extern int    InpCooldownMin        = 45;    // R5
extern int    InpLockAfter          = 5;     // R6
extern double InpMinRR              = 0;     // R8 minimum risk-reward ratio OFF (v0.20, on request; 0=off)
extern double InpRR                 = 2.0;   // Auto-TP
extern double InpMinStopPips        = 0;     // R15 min SL OFF (user request: M1 scalping needs tight stops; 0=off). The broker minimum distance (STOPLEVEL) stays hard.
extern double InpMaxLot             = 0;     // R15 (0=off)
extern int    InpMinGapSec          = 0;     // R14 minimum pause OFF (v0.20, on request; 0=off)
extern int    InpRevengeMin         = 0;     // R25 revenge window OFF (v0.20, on request; 0=off)
extern bool   InpUseSession         = false; // R16
extern int    InpSessionStart       = 8;     // R16
extern int    InpSessionEnd         = 22;    // R16
extern int    InpNewsFrom           = 0;     // R16 HHMM (0=off)
extern int    InpNewsTo             = 0;     // R16 HHMM
extern bool   InpUseCorrCap         = true;  // R17
extern double InpCorrCapPct         = 1.5;   // R17
extern double InpWeeklyLossPct      = 5.0;   // R18 (0=off)
extern int    InpDeRiskAfter        = 2;     // R19
extern double InpDeRiskFactor       = 1.0;   // R19 de-risk ladder OFF (v0.20, on request; 1.0=off)
extern bool   InpFomoGate           = false; // R9
extern int    InpFomoSeconds        = 7;     // R9
extern bool   InpJournal            = true;  // R11
extern bool   InpHistoryBackfill    = true;  // v0.66: ONE-TIME backfill of closed trades from the account history into the journal
                                             //   (ticket + net), so the trade file can assign old positions. Runs exactly once per account.
                                             //   DELIBERATELY RENAMED (formerly InpBackfillHistory): MT4 stores EA inputs per chart and takes
                                             //   the STORED value when you attach it, not the default from the source — the old switch
                                             //   therefore stayed "off" although the default here had long been "on". A new name has no
                                             //   stored predecessor, so the default applies. Set "Gesamte Historie" (all history) in the terminal first.
                                             //   (ticket + net). Set "Gesamte Historie" (all history) in the terminal first, otherwise
                                             //   the EA only sees the filtered excerpt. Runs exactly once per account.
extern bool   InpScreenshots        = true;  // R11 / v0.47: screenshot on every action (open/close/SL-TP move) — shown per trade in the cockpit
extern int    InpShotWidth          = 1100;  // v0.47: width of the screenshots (pixels)
extern int    InpShotHeight         = 620;   // v0.47: height of the screenshots (pixels)
extern int    InpShotKeepDays       = 14;    // v0.47: Screenshots aelter als X Tage loeschen (0 = nie aufraeumen)
extern int    InpSlippage           = 30;
extern int    InpMagic              = 990201;
extern WatchScope InpWatchScope     = TOOL_ONLY;  // TOOL_ONLY=foreign magics untouched · TOOL_PLUS_MANUAL=+Magic0 · ALL_POSITIONS=touches EVERYTHING (demo/debug only, NOT funded)
extern int    InpCloseThrottleMs    = 300;   // P0-1: min. distance between close passes
extern int    InpCloseRetries       = 5;     // close queue: max attempts per ticket before FINAL-FAIL
extern int    InpCloseBackoffMs     = 400;   // Close-Queue: Basis-Backoff (verdoppelt je Versuch)
extern int    InpCloseMaxBackoffMs  = 4000;  // Close-Queue: max Backoff je Ticket
extern double InpDefaultSLpips      = 20;
extern int    InpSlClicksToMove     = 3;     // v0.21: set the SL line only after this many clicks into the same zone (1 = immediately)
extern double InpSlZonePips         = 10;    // v0.21: lower tolerance bound for "same zone" in pips (plus ~0.15% of the price)
extern bool   InpRequireSL          = true;  // R7
extern bool   InpRequireTP          = true;  // R7
extern int    InpSLTPGraceSeconds   = 4;     // R7 (v0.33: 5->4; anchor = since SL/TP was REMOVED, not from open)
extern int    InpTimerSeconds       = 1;
extern int    InpMinActionMs        = 500;
extern int    InpPanelMs            = 1500;
extern bool   InpUseAlert           = false;
extern string InpPanelMono          = "Consolas";  // v0.24 panel: monospace font for numbers (if wrong under Wine -> "Courier New" or "Lucida Console")
extern double InpPanelScale         = 0;           // v0.37: 0 = AUTO (from Windows DPI, 150%->1.5). Otherwise a manual factor (1.5 for 150%). Fixes panel overlap without user action.
extern double InpFontScale          = 1.0;         // v0.46: scale the panel font size separately (0.8 = smaller, 1.3 = bigger)
extern double InpShapeScale         = 1.0;         // v0.46: scale tile/button size separately (affects widths/heights)
extern bool   InpPanelAutoFit       = true;        // v0.46: shrink the panel automatically if it would otherwise be taller than the chart window
extern bool   InpShowSpread         = true;        // v0.46: show the live spread in the panel
extern bool   InpShowCandleTime     = true;        // v0.46: show the remaining time of the running candle (green -> amber -> red)
extern bool   InpCandleTimeOnChart  = true;        // v0.52: show the countdown right NEXT TO the running candle (not only in the panel)
extern bool   InpBreakEvenBtn       = true;        // v0.46: "RISK FREE" button (SL of all trades in profit to break-even)
extern double InpBreakEvenBufferPts = 0;           // v0.46: extra buffer in points beyond break-even (0 = exactly entry; covers commission)
extern bool   InpTpLine             = false;       // v0.46: draggable TP line instead of auto TP from InpRR (the line wins when set)
extern bool   InpCockpit            = true;        // v0.26: write live state for the localhost cockpit as JSON (local server required)
extern int    InpCockpitPort        = 8730;        // v0.26: port of the local cockpit server (display/reference only)
//--- v0.17: Prop-Firm-Profil, Funded-Gate, R7-Haertung, Test-Harness ---
extern PropFirm InpPropFirm         = PF_FTMO;  // Prop-Firm-Profil (Label/Audit; Limits bleiben Inputs, pro Firma verifizieren)
extern bool   InpFundedMode         = false; // Real/Funded: erzwingt WatchScope=TOOL_ONLY + sperrt TestMode hart
extern int    InpSLTPGraceNews      = 0;     // R7: Grace-Sekunden waehrend News-Blackout (0 = sofort schliessen)
extern bool   InpTestMode           = false; // rule test harness (DEMO ONLY; hard off in FundedMode)
extern int    InpDayResetHour        = 0;     // Prop-Firm-Tagesreset-Stunde in Server-Zeit (0 = Mitternacht = FTMO); R4/Tag
extern int    InpWeekStartDay        = 0;     // week start (0=Sunday..6=Saturday) for R18
//--- R22 (v0.35): PANEL TRADES ONLY. Orders opened manually/from a phone (magic 0) are closed immediately. ---
// Trades of OTHER EAs (their own magic number) are deliberately left untouched. Applies in FundedMode too, and also to
// positions already open when the EA starts (no grandfathering -> no loophole via an EA restart).
extern bool   InpCloseManualTrades   = true;  // R22: close manual/phone trades (magic 0) immediately — only panel trades allowed
//--- v0.36: weekly risk selector in the panel (set risk/trade yourself, applies for the week) ---
enum PanelLang { LANG_DE, LANG_EN };       // v0.53: Panel-Sprache
extern PanelLang InpLang = LANG_DE;        // v0.53: language of the on-chart panel (the dashboard has its own switch)
extern bool   InpRequireWeeklyRisk = true;  // v0.49: WITHOUT a fixed weekly risk there is no trading (confirm anew every week)
extern bool   InpRiskChooser         = true;  // show the risk selector [-]/[+] in the panel (0 = only via InpRiskPerTradePct)
extern double InpRiskStep            = 0.05;  // step size of the selector in % (e.g. 0.05 -> 0.25 / 0.30 / 0.35 …)
extern double InpRiskMaxPct          = 1.00;  // upper limit the selector allows (the hard cap stays 1.0 % / RULES range)

#define GV_DAYSTART_EQ   "RG_DAYSTART_EQ"
#define GV_DAYSTART_DAY  "RG_DAYSTART_DAY"
#define GV_LOCK_UNTIL    "RG_LOCK_UNTIL"
#define GV_HARD_LOCK     "RG_HARD_LOCK"
#define GV_MASTER        "RG_MASTER"      // v0.28: single-instance lock — which chart is the active master
#define GV_MASTER_HB     "RG_MASTER_HB"   // v0.28: Master-Heartbeat (Server-Zeit); stale -> anderer uebernimmt
#define GV_INIT_BAL      "RG_INIT_BAL"
#define GV_DAY_RISK      "RG_DAY_RISK"
#define GV_CONSEC        "RG_CONSEC"
#define GV_COOLDOWN      "RG_COOLDOWN"
#define GV_PEAK_EQ       "RG_PEAK_EQ"
#define GV_TARGET_HIT    "RG_TARGET_HIT"
#define GV_LAST_ENTRY    "RG_LAST_ENTRY"
#define GV_WEEKSTART_EQ  "RG_WEEKSTART_EQ"
#define GV_WEEK_IDX      "RG_WEEK_IDX"
#define GV_WEEK_LOCK     "RG_WEEK_LOCK"
#define GV_LAST_CLOSE    "RG_LAST_CLOSE"    // P4 Wasserstand letzter verarbeiteter Close
#define GV_BASE_WARN     "RG_BASE_WARN"     // P1-2 Tagesbasis unsicher (Erststart)
#define GV_EFF_DL        "RG_EFF_DL"        // v0.30: effective daily loss limit (loosening only at the day change)
#define GV_EFF_ML        "RG_EFF_ML"        // v0.30: effektives Max-Verlustlimit (dito)
#define GV_PROTOFF       "RG_PROTOFF"       // v0.30: Zaehler "AutoTrading heute ausgeschaltet"
#define GV_EFF_DAY       "RG_EFF_DAY"       // v0.30-fix: for which day EFF was last set (only by the master) -> deterministic
#define GV_PROT_LATCH    "RG_PROT_LATCH"    // v0.30-fix: shared latch (current protection-off episode already counted) -> no double counting on master handoff
#define GV_BLOCKS        "RG_BLOCKS"        // v0.32 Panel-Spiegel: abgelehnte Versuche heute (geteilt, kontoweit)
#define GV_FILLS         "RG_FILLS"         // v0.32: tatsaechliche Trades heute
#define GV_BLK_LAST      "RG_BLK_LAST"      // v0.32: time of the last rejection (for tilt burst)
#define GV_BLK_BURST     "RG_BLK_BURST"     // v0.32: rejections in the current <60s window
#define GV_ACCOUNT       "RG_ACCOUNT"        // §04-fix (high): login of the account the stored state belongs to (account binding)
#define GV_MAGIC         "RG_MAGIC"          // v0.38: InpMagic of the master — passive charts warn on a mismatch (otherwise unguarded trades)
#define GV_SRV_OFFSET    "RG_SRV_OFFSET"     // §04-fix (medium): last GOOD server offset (sec) — otherwise a restart in a tickless phase seeds from a stale TimeCurrent
#define GV_EFF_RH        "RG_EFF_RH"         // §05-fix (high): effective daily reset hour — an input change takes effect only at the real rollover (no artificial roll wipe)
#define GV_EFF_WS        "RG_EFF_WS"         // §05-fix (high): effective week start day — ditto for R18
#define GV_TEST_SET      "RG_TEST_SET"       // §05-fix (high): a lock was set via the TEST button -> only then may 'Reset' delete real locks
#define GV_LOCK_WHY      "RG_LOCK_WHY"       // v0.65: WHY is the day locked? 1=R4 daily loss 2=R6 losing streak
                                             //   3=R13 Giveback 4=Selbstsperre 5=Historie unsichtbar 6=Lockstate manipuliert 7=Test
#define GV_BACKFILL      "RG_BACKFILL2"      // v0.65: Nachtrag ERFOLGREICH gelaufen (Wert = Kontonummer).
                                             //   Only set on hits — a failed attempt must not burn the one-time chance.
#define GV_LS_SEEN       "RG_LS_SEEN"        // v0.63: the lockstate file has existed on this account before -> from then on its ABSENCE is tampering, not a first start
// §06-fix (medium): extend tighten-only to ALL lock-relevant inputs (so far only Daily/MaxLoss).
#define GV_TIGHT_LATCH   "RG_TIGHT_LATCH"    // self-lock was active today -> InpTightenOnly cannot be switched off intraday
#define GV_PROT_SINCE    "RG_PROT_SINCE"     // §07-fix: start of the current protection-off phase (AutoTrading off) -> extend lock periods by the downtime
// v0.36: weekly risk selector in the panel — the user sets risk/trade for the week himself (own account OR prop).
#define GV_WEEK_RISK     "RG_WEEK_RISK"      // actively chosen risk/trade (%) for the running week
#define GV_WEEK_RISK_IDX "RG_WEEK_RISK_IDX"  // week index (WeekIdx) that GV_WEEK_RISK applies to
#define GV_WEEK_RISK_NXT "RG_WEEK_RISK_NXT"  // pending increase -> takes effect only at the next week change (anti-tilt)
#define GV_EFF_WEEK      "RG_EFF_WEEK"       // R18 Wochenlimit
#define GV_EFF_WARN      "RG_EFF_WARN"       // R4b Warn-Gate
#define GV_EFF_LOCKAFT   "RG_EFF_LOCKAFT"    // R6 lock after n losses
#define GV_EFF_CDAFT     "RG_EFF_CDAFT"      // R5 cooldown after n losses
#define GV_EFF_CDMIN     "RG_EFF_CDMIN"      // R5 Cooldown-Dauer (groesser = strenger)
#define GV_EFF_GIVE      "RG_EFF_GIVE"       // R13 Giveback
#define GV_EFF_RISK      "RG_EFF_RISK"       // R1 risk/trade (scales the whole cascade via AutoScale)
#define GV_EFF_REQSL     "RG_EFF_REQSL"      // R7 SL mandatory (once on -> cannot be switched off intraday)
#define GV_EFF_REQTP     "RG_EFF_REQTP"      // R7 TP-Pflicht
#define GV_EFF_CORR      "RG_EFF_CORR"       // R17 correlation cap on/off
#define EA_VER           "0.67"             // ONE version source (log print + cockpit JSON) — increment here
#define PFX              "MMT_"
#define SLLINE           "MMT_slline"
#define TPLINE           "MMT_tpline"      // v0.46: optional, draggable TP line (InpTpLine); otherwise auto TP from InpRR
#define JOURNAL          "MamalTrading_Journal.csv"
#define LOCKFILE         "MamalTrading_Lockstate.dat"   // Lockstate-Spiegel (fail-closed/Tamper)
#define COCKPIT_FILE     "mamal_cockpit.json"           // v0.26: live state for the localhost cockpit (DLL-free file bridge)
#define COCKPIT_TMP      "mamal_cockpit.tmp"            // atomic: write tmp first, then FileMove -> no torn read
#define COCKPIT_OPEN     "mamal_cockpit_open.txt"       // trigger: server sees the file -> opens the browser
#define COCKPIT_PATHS    "mamal_files.txt"              // v0.37: signpost in the Common folder -> real Files path (portable/multi-terminal safe)
#define COCKPIT_CMD      "mamal_cmd.txt"                // v0.39: command from the dashboard — ONLY tightening (endday = self-lock), never loosening
#define LOCKSALT         "MMT-ls-7731"                  // HMAC-light salt for the lockstate checksum

double g_initialBalance = 0;
bool   g_initBalConfirmed = false;   // §04-fix: base comes from input/GV/lockstate (confirmed) — a pure auto-derivation must NEVER be persisted (neither GV nor file)
uint   g_lastActionMs   = 0;
uint   g_lastPanelMs    = 0;
uint   g_lastEnforceMs  = 0;   // P0-1 Close-Drossel
string g_panelSig       = "";
int    g_armed          = 0;
uint   g_armMs          = 0;
int    g_slClicks       = 0;    // v0.21: click counter for 3-click SL setting
double g_slClickPrice   = 0;    // Zonen-Anker-Preis
uint   g_slClickMs      = 0;    // time of the last zone click
string g_flash          = "";   // v0.21: show the last message (e.g. rejection reason) directly in the panel
uint   g_flashMs        = 0;    // time of the last message
uint   g_flashHold      = 6000; // v0.63: Standzeit DIESER Meldung. Manipulationsbefunde bleiben laenger stehen —
                                //   they occur rarely, and whoever misses them misses exactly what matters.
bool   g_flashLoud      = false;// v0.64: the standing message is a tampering finding -> must not be pushed aside by
                                //   harmless follow-up messages (otherwise the 120 s had no effect)
bool   g_lsMissWarned   = false;// v0.64: "file missing" (file missing) already reported? Forced alerts ONLY on a state change,
bool   g_lsCorruptWarned= false;//   otherwise a permanently unreadable folder fires a modal dialog every second
bool   g_flashInfo      = false;// v0.37: true = neutraler Hinweis (z.B. Cockpit), false = rote Ablehnung
string g_rkEditSync     = "";   // v0.49: value last written INTO the input field — keeps DrawPanel from overwriting what is being typed
datetime g_noMasterSince = 0;   // v0.45: since when is NO instance master (0 = all fine)
bool     g_noMasterWarned= false;// v0.45: alarm only once per outage episode
bool   g_gvDirty        = false;// v0.22: GlobalVariables changed -> ONE bundled flush at the end of the cycle (Wine crash protection instead of 4 synchronous flushes per tick)
int    g_fgTries        = 0;    // v0.28: set the foreground flag only a limited number of times (not every cycle -> no ChartSetInteger spam)
int    g_masterStreak   = 0;    // v0.28: how many cycles in a row master (hysteresis: really act only from 2 on -> no startup/slow-cycle burst)
double g_lastScopeSig   = 0.0;  // v0.31: signature of the in-scope SL/TP from the last cycle (detect user modify)
int    g_lastScopeN     = -1;   // v0.31: In-Scope-Order-Anzahl letzter Cycle
uint   g_modifyQuietMs  = 0;    // v0.31: time of the last detected user modify -> briefly NO EA close (no OrderClose during a running modify = Wine crash)
uint   g_lastCockpitMs  = 0;    // v0.26: Cockpit-JSON gedrosselt schreiben

// Close-Queue (echte ticketbasierte Schliessung mit Retry/Backoff/Journal)
int      g_qTicket[];
string   g_qReason[];
int      g_qTries[];
uint     g_qNextMs[];
// §06-fix: R7 grace now lives persistently in GlobalVariables (RG_NK_/RG_NKH_), no longer in per-instance arrays
uint     g_modifyQuietStart = 0;   // §06-fix: start of the running modify series (hard-cap the quiet window)
int      g_seenTicket[];           // §06-fix: zuletzt gesehene offene In-Scope-Tickets (History-Sichtbarkeits-Wachhund)
int      g_suspTicket[];           // vanished tickets that are not (yet) findable in the history
string   g_lockSig         = "";   // letzte geschriebene Lockstate-Signatur (Disk-Schonung)
bool     g_lsGuard         = false; // v0.63: laeuft gerade ein Abgleich? verhindert Rekursion WriteLockstate <-> ReconcileLockstate
uint     g_lastReconcileMs = 0;    // throttle for the R3 reconcile in Cycle()
uint     g_lastLockReconcileMs = 0;// §05-fix (high): throttle for the periodic lockstate reconciliation (catches an F3 deletion of the lock GVs)
datetime g_lastStaleWarnDay= 0;    // throttle for the server-time drift notice (max 1x/day)
datetime g_lastTvWarnDay   = 0;    // throttle for the TickValue fallback warning (max 1x/day)
bool     g_tvEstimate      = false;// §07-fix: risk rests (partly) on an estimate instead of a real TickValue -> make it visible in panel/cockpit
datetime g_lastRdrWarnDay  = 0;    // §07-fix: throttle for the R3 reconstruction warning (previously CSV spam every 15 s)
datetime g_lastRollWarn    = 0;    // §07-fix: throttle for "Roll ohne Broker-Bestaetigung" (roll without broker confirmation) (PC clock manipulation)
int      g_srvOffset       = 0;    // server offset (sec): TimeCurrent - TimeLocal at the last tick
bool     g_srvOffsetSet    = false;
datetime g_lastSrvSeen     = 0;    // §04-fix (medium): last observed TimeCurrent value — "fresh" = it has moved since the last observation

double Pip(){ return ((Digits==5 || Digits==3) ? 10*Point : Point); }
long DayKeyOf(datetime t){ return (long)(TimeYear(t)*10000+TimeMonth(t)*100+TimeDay(t)); }
// Server time, tick-independent: MQL4 has NO TimeTradeServer() (MQL5 only). Solution: server time = PC clock
// (TimeLocal) + a maintained server offset (from TimeCurrent-TimeLocal at the last tick). That way time keeps
// running even without new ticks. The offset is updated in OnTick/OnInit via UpdateSrvOffset().
// §04-fix (medium): derive the offset only from FRESH server time. After a restart in a tickless phase (weekend)
// TimeCurrent() returns the cache from the last tick — an offset built from it makes SrvTime() lag by the whole
// tick gap (up to ~2.5 days): expired locks re-activate themselves, SafeCloseAll closes at the
// Monday open. "Fresh" = TimeCurrent has moved since the last observation (some symbol delivered a
// quote — detectable from OnTimer too), OR the candidate matches the persisted last good offset.
void AdoptSrvOffset(datetime sc)
{
   g_srvOffset=(int)(sc - TimeLocal()); g_srvOffsetSet=true;
   if(!GlobalVariableCheck(GV_SRV_OFFSET) || (int)GlobalVariableGet(GV_SRV_OFFSET)!=g_srvOffset)
      GlobalVariableSet(GV_SRV_OFFSET,(double)g_srvOffset);   // rarely changes (drift/DST) -> hardly any writes, the flush is done by the cycle/terminal
}
void UpdateSrvOffset()
{
   datetime sc = TimeCurrent();
   if(sc<=0) return;
   bool fresh = (g_lastSrvSeen>0 && sc>g_lastSrvSeen);         // server time is moving -> quote is fresh
   if(g_lastSrvSeen<=0)                                        // first call after start: TimeCurrent may be the weekend cache
   {
      if(GlobalVariableCheck(GV_SRV_OFFSET))
      {
         int stored=(int)GlobalVariableGet(GV_SRV_OFFSET);
         int cand  =(int)(sc - TimeLocal());
         if(MathAbs(cand-stored)<=120) fresh=true;             // Kandidat ~= letzter guter Offset -> plausibel frisch
         else { g_srvOffset=stored; g_srvOffsetSet=true;       // stale (tick gap): use the last good offset until a fresh quote arrives
                PrintFormat("Mamal: TimeCurrent %d s neben letztem gutem Offset (Tick-Luecke?) — nutze persistierten Offset, bis frische Quote da ist.", cand-stored); }
      }
      else fresh=true;                                         // no prior knowledge (first start): adopt the candidate — better than no server time
   }
   if(sc>g_lastSrvSeen) g_lastSrvSeen=sc;
   if(fresh) AdoptSrvOffset(sc);
}
datetime SrvTime()
{
   if(g_srvOffsetSet)
   {
      datetime est = TimeLocal() + g_srvOffset;   // PC clock + offset -> moves even without ticks
      datetime sc  = TimeCurrent();
      if(sc>0 && (est-sc) > 6*3600 && DayKeyOf(g_lastStaleWarnDay)!=DayKeyOf(est))
      { g_lastStaleWarnDay=est; PrintFormat("Mamal: HINWEIS letzter Tick %d s alt — Zeit aus PC-Uhr+Server-Offset.", (int)(est-sc)); }
      return est;
   }
   // §07-fix: offset not set yet -> use the PERSISTED offset first. The old fallback returned raw PC local time
   //   (wrong time zone) and thereby corrupted DayKey and the GV_LAST_CLOSE floor before the first server time arrived.
   if(GlobalVariableCheck(GV_SRV_OFFSET)) return TimeLocal() + (int)GlobalVariableGet(GV_SRV_OFFSET);
   datetime sc2 = TimeCurrent();       // otherwise: last tick
   if(sc2>0) return sc2;
   return TimeLocal();                 // letzter Ausweg (reine PC-Zeit, Zeitzone unbekannt)
}
// Prop-Firm-Zeit-Profil (P0/P1-3): Tagesreset um InpDayResetHour (Server), Woche ab InpWeekStartDay. Default 0/0 = FTMO/Sonntag.
// §05-fix (high): do NOT read the day-reset hour/week start straight from the input, but from the persisted EFFECTIVE
//   value. Otherwise an INTRADAY change of InpDayResetHour/InpWeekStartDay shifts the day/week key -> an artificial
//   RollNewDay/week roll wipes base/R3/series/TargetHit/week lock. The new input only takes effect at the REAL rollover
//   (adopted there). Seeded in OnInit; if the GV is missing -> input (first start).
int EffResetHour(){ return GlobalVariableCheck(GV_EFF_RH) ? (int)GlobalVariableGet(GV_EFF_RH) : InpDayResetHour; }
int EffWeekStart(){ return GlobalVariableCheck(GV_EFF_WS) ? (int)GlobalVariableGet(GV_EFF_WS) : InpWeekStartDay; }
long ServerDayKey(){ return DayKeyOf(SrvTime() - EffResetHour()*3600); }
datetime NextServerMidnight(){ datetime sh=SrvTime()-EffResetHour()*3600; datetime nx=(sh-(sh%86400))+86400; return nx + EffResetHour()*3600; }
long WeekIdx(){ datetime t=SrvTime()-EffResetHour()*3600; MqlDateTime st; TimeToStruct(t,st); int dow=(st.day_of_week-EffWeekStart()+7)%7; return (long)(t/86400) - (long)dow; }   // B2: anchor on the week start day (default Sunday)
// §07-fix (high): PC clock manipulation. SrvTime() = TimeLocal + offset — whoever moves the Windows clock forward shifts the
//   day/week key and thereby triggered a RollNewDay that wiped the lock, the day base, the R3 budget and the loss series
//   (the next tick corrected only the offset, not the deleted state). TimeCurrent(), by contrast, comes FROM THE BROKER
//   and cannot be faked locally. A roll is therefore only accepted if the broker time shows the same
//   day/week change. Across a weekend without ticks that means: the roll happens at the first real tick
//   (market open) — before that no trading is possible anyway, so the lock stays in place until then (conservative).
bool ServerDayRollConfirmed(long storedDay)
{
   datetime sc=TimeCurrent();
   if(sc<=0) return false;                                        // no broker time -> no roll
   return (DayKeyOf(sc - EffResetHour()*3600) != storedDay);
}
bool ServerWeekRollConfirmed(long storedWeek)
{
   datetime sc=TimeCurrent();
   if(sc<=0) return false;
   datetime t=sc-EffResetHour()*3600; MqlDateTime st; TimeToStruct(t,st);
   int dow=(st.day_of_week-EffWeekStart()+7)%7;
   return (((long)(t/86400)-(long)dow) != storedWeek);
}
void WarnUnconfirmedRoll(string what)   // throttled: otherwise one message per cycle
{
   if(SrvTime()-g_lastRollWarn < 300) return;
   g_lastRollWarn=SrvTime();
   Notify(TF("time.rolloverNotConfirmed",what));
   Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("%s ohne Broker-Bestaetigung -> Roll unterdrueckt (Uhr-Manipulation?)",what));
}
datetime ServerDayStart(){ datetime sh=SrvTime()-EffResetHour()*3600; return (sh-(sh%86400))+EffResetHour()*3600; }   // §04-fix: start of the CURRENT server day (= the moment at which the roll should have happened)
datetime ServerWeekStart(){ return (datetime)(WeekIdx()*86400) + EffResetHour()*3600; }                              // §04-fix: start of the current week (R18 anchor)
// §04-fix (medium): reconstruct the balance at the anchor moment from the broker history: current balance minus all
// net results realized SINCE then (incl. deposits/withdrawals — everything that moved the balance since the anchor, across ALL
// magics/symbols, because the account balance is account-wide). If the terminal was off across the anchor and night-time
// SL hits ran, the late roll otherwise measures from the already-dropped level — FTMO limits can break before the EA
// locks. With no closes since the anchor the sum is 0 -> result = current balance (identical to the old behavior).
// Limit: sees only the range loaded in the account history tab (documented OrdersHistoryTotal weakness) — it then delivers
// too little correction, never a wrong one; max() below prevents any worsening against the actual state.
double ReconstructedBalanceAt(datetime anchor)
{
   double sum=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderCloseTime()<anchor) continue;
      if(OrderType()==7) continue;   // credit operation: moves equity/credit, NOT the balance (type 6 = deposit, by contrast, does belong in; deleted pendings have profit 0)
      sum += OrderProfit()+OrderSwap()+OrderCommission();
   }
   return AccountBalance()-sum;
}

// v0.38: derive the challenge start balance from the deposit history (first deposit = account size).
// FTMO/prop accounts have exactly ONE initial balance entry (type 6). Limit: sees only the loaded
// history range — if it finds nothing, the caller falls back to the current balance.
double DepositBase()
{
   double first=0; datetime firstT=0;
   for(int i=0;i<OrdersHistoryTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderType()!=6) continue;         // 6 = Balance-Operation (Ein-/Auszahlung)
      if(OrderProfit()<=0) continue;       // deposits only
      if(firstT==0 || OrderOpenTime()<firstT){ firstT=OrderOpenTime(); first=OrderProfit(); }
   }
   return first;
}

// P1-11: WatchScope — TOOL_ONLY/TOOL_PLUS_MANUAL do NOT touch foreign magics; ALL_POSITIONS does (demo/debug only)
bool InScope(int magic)
{
   if(InpWatchScope==ALL_POSITIONS) return true;
   if(magic==InpMagic) return true;
   if(InpWatchScope==TOOL_PLUS_MANUAL && magic==0) return true;
   return false;
}
// P0-3/P4: vom EA geschlossene Tickets PERSISTENT merken (GlobalVariable -> ueberlebt Neustart)
string EaKey(int t){ return "RGEAC_"+IntegerToString(t); }
string OpnKey(int t){ return "RGOPN_"+IntegerToString(t); }   // v0.40: vom Panel eroeffnete Tickets — Close-Erkennung findet sie auch bei Magic-Divergenz/gefiltertem History-Tab
int CountOpn(){ int c=0; for(int i=GlobalVariablesTotal()-1;i>=0;i--) if(StringFind(GlobalVariableName(i),"RGOPN_")==0) c++; return c; }   // v0.42: Diagnose
string EacfKey(int t){ return "RGEACF_"+IntegerToString(t); }   // §05-fix (high): the EA close was the TRADER'S OWN FAULT (R7/R1/R8) -> counts toward the loss series (no laundering)
bool IsFaultCloseReason(string r){ return (StringFind(r,"R7")==0 || StringFind(r,"R8")==0 || StringFind(r,"R1 ")==0); }   // R7 SL/TP removed, R1 over-risk, R8 CRV — NOT R12/lock (that is a genuine protective flat)
void MarkEaClosed(int t,string reason){ GlobalVariableSet(EaKey(t),(double)SrvTime()); if(IsFaultCloseReason(reason)) GlobalVariableSet(EacfKey(t),(double)SrvTime()); GlobalVariablesFlush(); }   // P0-3: sofort persistieren (Crash-fest)
// §07-fix: UnmarkEaClosed()/TakeEaClosed() waren toter Code (nirgends aufgerufen) — entfernt statt mitgeschleppt.
// P0-2/P0-4: verarbeitete POSITIONEN (Key = OpenTime_Type_Symbol_Magic_OpenPrice) persistent -> idempotent, same-second-robust
// §07-fix: FIXED price precision instead of MarketInfo(MODE_DIGITS). The digits value is unavailable after a restart without the symbol
//   in the Market Watch (fallback 5) -> the same loss got a different key and was counted TWICE.
//   Note (deliberate MT4 limit): two positions with an identical open second, the same price, the same symbol/magic and
//   the same direction still share one key — MT4 has no position ID, and the ticket is no good (partial closes).
string ProcKey(datetime ot,int ty,string sym,int magic,double openPrice){ return "RGP_"+IntegerToString((int)ot)+"_"+IntegerToString(ty)+"_"+sym+"_"+IntegerToString(magic)+"_"+DoubleToString(openPrice,8); }
string ProcKeyLegacy(datetime ot,int ty,string sym,int magic,double openPrice){ int dg=(int)MarketInfo(sym,MODE_DIGITS); if(dg<=0) dg=5; return "RGP_"+IntegerToString((int)ot)+"_"+IntegerToString(ty)+"_"+sym+"_"+IntegerToString(magic)+"_"+DoubleToString(openPrice,dg); }
bool   IsProcessed(string key){ return GlobalVariableCheck(key); }
bool   IsProcessedAny(string key,string legacyKey){ return (GlobalVariableCheck(key) || GlobalVariableCheck(legacyKey)); }   // migration: keep honoring old markers -> no double counting on the update
// v0.45 (Verify): ONE marker pair per position. RGM_ = "already shown in the cockpit" — is set by BOTH paths
//   so that a trade never lands in the net as CLOSE *and* as CLOSE_MAN (scope/magic change).
string ManKey(string procKey){ return "RGM_"+StringSubstr(procKey,4); }
void   AddProcessed(string key,datetime ct){ GlobalVariableSet(key,(double)ct); GlobalVariableSet(ManKey(key),(double)ct); }
void   PruneGV(string prefix,datetime below)
{
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   {
      string nm=GlobalVariableName(i);
      if(StringFind(nm,prefix)==0 && (datetime)GlobalVariableGet(nm) < below) GlobalVariableDel(nm);
   }
}
// §04-fix (high): full state reset on an account switch — GVs are terminal-wide and carry NO account number,
// so after a login change the stored state (bases/locks/series/markers) does NOT belong to the new account.
void WipeAllState()
{
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   { string nm=GlobalVariableName(i); if(StringFind(nm,"RG")==0) GlobalVariableDel(nm); }   // gesamter Namespace: RG_*, RGP_*, RGEAC_*
   if(FileIsExist(LOCKFILE)) FileDelete(LOCKFILE);   // do not restore the signed lockstate of the old account
   g_lockSig="";
   GlobalVariablesFlush();
}

string PropFirmName(PropFirm p)
{
   switch(p)
   {
      case PF_FTMO:         return "FTMO";
      case PF_THE5ERS:      return "The5ers";
      case PF_FUNDEDNEXT:   return "FundedNext";
      case PF_FUNDINGPIPS:  return "FundingPips";
      case PF_ALPHACAPITAL: return "AlphaCapital";
   }
   return "Custom";
}
void ApplyFundedAndProfile()
{
   if(InpFundedMode)   // #11 Real/Funded-Hard-Gate
   {
      if(InpWatchScope!=TOOL_ONLY){ InpWatchScope=TOOL_ONLY; Notify(T("cfg.fundedWatchScopeForced")); }
      if(InpTestMode){ InpTestMode=false; Notify(T("cfg.fundedTestModeOff")); }
   }
   if(InpMinRR>0 && InpRR<InpMinRR){ Notify(TF("cfg.rrClampedToMinRR",DoubleToString(InpRR,2),DoubleToString(InpMinRR,2),DoubleToString(InpMinRR,2))); InpRR=InpMinRR; }
   PrintFormat("Mamal: Prop-Firm-Profil=%s | FundedMode=%s | Limits Daily %.1f%% / Max %.1f%% (Warn %.1f%%) / Woche %.1f%% — pro Firma verifizieren!",
               PropFirmName(InpPropFirm), InpFundedMode?"AN":"aus", InpDailyLossPct, InpMaxLossPct, InpMaxLossWarnPct, InpWeeklyLossPct);
   Journal("PROFILE","-","-",0,0,0,0,0,StringFormat("Prop-Firm=%s Funded=%s Daily=%.1f Max=%.1f Week=%.1f",PropFirmName(InpPropFirm),InpFundedMode?"1":"0",InpDailyLossPct,InpMaxLossPct,InpWeeklyLossPct));
}

int OnInit()
{
   UpdateSrvOffset();          // seed the server offset (TimeCurrent is usually valid already)
   // v0.40-fix: InpMagic=0 machte Panel-Trades von manuellen ununterscheidbar (R22-Failsafe, Scope-Chaos,
   //   Close-Erkennung blind). Ungueltige Magic -> Default erzwingen, laut melden.
   if(InpMagic<=0){ InpMagic=990201; Notify(T("cfg.magicInvalid")); }
   ApplyFundedAndProfile();    // #11/#13: Funded-Gate (TOOL_ONLY) + Prop-Firm-Profil-Log
   ObjectsDeleteAll(0,PFX);   // B20: panel objects are named MMT_ (not RG_) — previously a no-op
   // §04-fix (high): account binding. GVs/lockstate are terminal-wide without an account number — after an account switch
   //   (demo->challenge->verification->funded in the same terminal) the EA would otherwise run against the BASES of the OLD
   //   Kontos rechnen (Sperren tot bzw. Phantom-Sperre + Zwangs-Close). Bei Login-Wechsel -> kompletter State-Reset.
   long acct=(long)AccountNumber();
   if(acct>0)   // acct<=0 = not (yet) connected -> do not trigger a reset against a phantom 0
   {
      if(GlobalVariableCheck(GV_ACCOUNT) && (long)GlobalVariableGet(GV_ACCOUNT)!=acct)
      {
         long prev=(long)GlobalVariableGet(GV_ACCOUNT);
         PrintFormat("Mamal: ACCOUNT SWITCH %d -> %d detected — full state reset (bases/locks/streak) so nothing is computed against a foreign base.", prev, acct);
         Journal("ACCOUNT_SWITCH","-","-",0,0,0,0,0,StringFormat("Konto %d -> %d: State-Reset (fail-closed bis Basis bestaetigt)", prev, acct));
         WipeAllState();
      }
      GlobalVariableSet(GV_ACCOUNT,(double)acct);
   }
   // §04-fix (high): remember the origin of the R4b base. Only InpInitialBalance or an already persisted value
   //   count as CONFIRMED; the plain auto-derivation from AccountBalance() is too low on a first attach in the middle of a
   //   challenge (after prior losses) and is treated fail-closed below.
   double prevInit    = (GlobalVariableCheck(GV_INIT_BAL) && GlobalVariableGet(GV_INIT_BAL)>0) ? GlobalVariableGet(GV_INIT_BAL) : 0;
   bool initFromInput = (InpInitialBalance>0);
   // v0.37-fix: plausibility. A base FAR below the account balance is almost certainly a decimal-separator
   //   typo (e.g. "163.659" or "163,659" -> MT4 reads 163.66 instead of 163659). The R4b max-loss floor would then
   //   sit far below the balance -> protection practically OFF. Discard the input.
   // v0.38-fix (Verify): the guard MUST run before the store/lockstate resolution — otherwise the discarded
   //   input bypasses the existing confirmed base and the auto branch overwrites it.
   if(initFromInput && AccountBalance()>0 && InpInitialBalance < AccountBalance()*0.1)
   {
      Notify(TF("base.initialBalanceImplausible",DoubleToString(InpInitialBalance,2),DoubleToString(AccountBalance(),2),DoubleToString(AccountBalance(),2)));
      Journal("BASEWARN","-","-",0,0,0,0,0,StringFormat("InpInitialBalance %.2f unplausibel (<10%% von Balance %.0f) -> verworfen",InpInitialBalance,AccountBalance()));
      initFromInput=false;   // -> Store/Lockstate/Auto uebernehmen (unten), Tighten-Only bleibt intakt
   }
   bool initFromStore = (!initFromInput && GlobalVariableCheck(GV_INIT_BAL) && GlobalVariableGet(GV_INIT_BAL)>0);
   double lsInit      = (!initFromInput && !initFromStore) ? LsStoredInitBal() : 0;   // §04-fix (medium): the lockstate file survives the 4-week GV expiry
   bool initFromFile  = (lsInit>0);
   if(initFromInput)
   {
      g_initialBalance=InpInitialBalance;
      if(prevInit>0 && InpInitialBalance < prevInit-0.01)   // §05-fix (high): LOWERING the base intraday pushes the R4b lock further away -> reject (tighten-only); keep the higher base, a lowering only takes effect at the day change
      {
         g_initialBalance=prevInit;
         Notify(TF("base.initialBalanceLoweringIgnored",DoubleToString(prevInit,2),DoubleToString(InpInitialBalance,2),DoubleToString(prevInit,2)));
         Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("Basis-Absenkung %.2f->%.2f intraday abgelehnt (tighten-only)",prevInit,InpInitialBalance));
      }
   }
   else if(initFromStore) g_initialBalance=GlobalVariableGet(GV_INIT_BAL);
   else if(initFromFile)  g_initialBalance=lsInit;
   else   // v0.38: FULLY AUTOMATIC — challenge base from the deposit history, fallback the current balance.
   {      //   Once derived it is persisted (stable across restarts) -> never again "BASIS UNSICHER" (base uncertain).
      double dep=DepositBase();
      // v0.38-fix (Verify): unplausibel kleine "Einzahlung" (z.B. Fee-Refund bei gefiltertem History-Tab)
      //   do NOT take as the base — R4b would otherwise be ineffective (base << balance -> DD clamps to 0).
      if(dep>0 && AccountBalance()>0 && dep < AccountBalance()*0.1)
      { Journal("INFO","-","-",0,0,0,0,0,StringFormat("Einzahlung %.2f unplausibel klein ggue. Balance %.0f (Historie unvollstaendig?) -> Fallback Balance",dep,AccountBalance())); dep=0; }
      if(dep>0)
      { g_initialBalance=dep;
        Journal("INFO","-","-",0,0,0,0,0,StringFormat("Auto-Basis aus Einzahlung: %.2f (Historie)",dep)); }
      else
      { g_initialBalance=AccountBalance();
        if(g_initialBalance>0) Notify(TF("base.autoFromBalance",DoubleToString(g_initialBalance,2))); }
      // v0.38-fix (Verify): tighten-only in the auto branch too — an already confirmed higher base
      //   (store/lockstate) must NEVER be lowered by a lower auto-derivation.
      if(prevInit>0 && g_initialBalance<prevInit) g_initialBalance=prevInit;
   }
   g_initBalConfirmed = (g_initialBalance>0);   // v0.38: every source counts — the base is fixed immediately (tighten-only still protects against lowering)
   if(g_initBalConfirmed)
      GlobalVariableSet(GV_INIT_BAL,g_initialBalance);         // v0.38: persist the auto base as well — stability across restarts (from now on the value is the binding reference)
   // P0-2: no valid max-loss base -> fail-closed (no new trades) until account data/InpInitialBalance are there
   if(g_initialBalance<=0)
   { GlobalVariableSet(GV_BASE_WARN,1); GlobalVariablesFlush(); Notify(T("base.missingFailClosed")); }
   // B1: warn if the max-loss base deviates strongly from the real account base (R4b computes against it!)
   {
      double ab=AccountBalance();
      if(g_initialBalance>0 && ab>0 && MathAbs(g_initialBalance-ab)/MathMax(g_initialBalance,ab) > 0.25)
         Notify(TF("base.maxLossBaseMismatch",DoubleToString(g_initialBalance,2),DoubleToString(ab,2),DoubleToString(g_initialBalance,2)));
   }

   // §05-fix (hoch): effektive Tagesreset-Stunde/Wochenstart seeden (Erststart) bzw. anstehende Config-Aenderung melden.
   //   Is NOT overwritten by the input — the adoption happens only at the real day/week rollover (RollNewDay/Cycle).
   if(!GlobalVariableCheck(GV_EFF_RH)) GlobalVariableSet(GV_EFF_RH,(double)InpDayResetHour);
   if(!GlobalVariableCheck(GV_EFF_WS)) GlobalVariableSet(GV_EFF_WS,(double)InpWeekStartDay);
   if(EffResetHour()!=InpDayResetHour || EffWeekStart()!=InpWeekStartDay)
      Notify(TF("time.resetInputsPending",IntegerToString(EffResetHour()),IntegerToString(EffWeekStart()),IntegerToString(InpDayResetHour),IntegerToString(InpWeekStartDay)));
   long today=ServerDayKey();
   bool firstAttach = !GlobalVariableCheck(GV_DAYSTART_DAY);              // P1-2
   if(firstAttach)                                          RollNewDay(true);
   else if((long)GlobalVariableGet(GV_DAYSTART_DAY)!=today) RollNewDay(false);
   if(!GlobalVariableCheck(GV_LAST_CLOSE)) GlobalVariableSet(GV_LAST_CLOSE,(double)SrvTime());  // P4: ab jetzt zaehlen
   if(InpDayStartBase>0 && DayStartBaseInput()<=0)   // v0.37-fix: Tippfehler-Hinweis (Punkt/Komma)
      Notify(TF("base.dayStartBaseImplausible",DoubleToString(InpDayStartBase,2),DoubleToString(AccountBalance(),2),DoubleToString(AccountBalance(),2)));
   double dsbIn = DayStartBaseInput();
   if(BaseWarn() && dsbIn>0)   // P1-2: nachtraeglich gesetzte FTMO-Tagesbasis uebernehmen -> Sperre aufheben
   {
      GlobalVariableSet(GV_DAYSTART_EQ, dsbIn);
      GlobalVariableSet(GV_PEAK_EQ,     MathMax(GlobalVariableGet(GV_PEAK_EQ), dsbIn));
      GlobalVariableSet(GV_BASE_WARN,   0);
      GlobalVariablesFlush();
      Notify(TF("base.dayStartBaseManual",DoubleToString(dsbIn,2)));
   }
   // v0.38: the earlier fail-closed block "auto base unconfirmed" is gone — the base is now derived automatically
   //   from the deposit history (or balance), confirmed immediately and persisted. Anyone wanting a different
   //   base sets InpInitialBalance (tighten-only stays active: a lowering only takes effect at the day change).

   ReconcileLockstate();   // Lockstate-Datei (fail-closed) abgleichen, bevor irgendetwas handelt
   // v0.42: Boot-Diagnose — Ground Truth ins Journal (jede Instanz; klaert Registry/Floor/History/Kontext)
   // v0.66: write the backfill state in as well. The backfill ran into the void once, and from the outside it was
   //   impossible to tell whether the switch was even on — diagnosis by guesswork instead of by evidence.
   Journal("INFO",Symbol(),"-",0,0,0,0,0,StringFormat("BootDiag v%s: RGOPN=%d HistTotal=%d Floor=%s Ctx=%s Magic=%d Backfill=%s MasterSlot=%s",EA_VER,CountOpn(),OrdersHistoryTotal(),TimeToString((datetime)GlobalVariableGet(GV_LAST_CLOSE)),IsTradeContextBusy()?"BUSY":"frei",InpMagic,(InpHistoryBackfill?(GlobalVariableCheck(GV_BACKFILL)?"erledigt":"an"):"aus"),GlobalVariableCheck(GV_MASTER)?"da":"FEHLT"));
   ReconcileDayRisk();     // R3: restore the daily budget from broker data after a crash/restart
   ChartSetInteger(0,CHART_FOREGROUND,false);
   g_fgTries=8;                              // v0.28: retry in the foreground for the first few cycles (in case init does not stick), then stay quiet
   CreateControls();
   // §07-fix: check the return value + validate the input. The timer carries the TICK-INDEPENDENT enforcement (P0-1) —
   //   if EventSetTimer failed or InpTimerSeconds<=0, the protection silently ran on ticks only.
   int tsec=InpTimerSeconds; if(tsec<1){ tsec=1; Notify(T("cfg.timerSecondsInvalid")); }
   if(tsec>60){ tsec=60; Notify(T("cfg.timerSecondsCapped")); }
   if(!EventSetTimer(tsec))
   { Notify(T("watchdog.timerFailed"));
     Journal("PROTECT_OFF","-","-",0,0,0,0,0,StringFormat("EventSetTimer fehlgeschlagen (err=%d) — nur noch tick-getriebenes Enforcement",GetLastError())); }
   PrintFormat("Mamal-Trading v%s aktiv (%s). Scope=%d. Profil=%s Funded=%s Test=%s SL-Klicks=%d. R15-min-SL=%s. Cockpit=%s(Port %d). UNGETESTET bis F7=0 Errors.", EA_VER, Symbol(), (int)InpWatchScope, PropFirmName(InpPropFirm), InpFundedMode?"AN":"aus", InpTestMode?"AN":"aus", InpSlClicksToMove, (InpMinStopPips>0?"an":"AUS"), (InpCockpit?"an":"aus"), InpCockpitPort);
   if(InpWatchScope==ALL_POSITIONS) Notify(T("cfg.watchScopeAllPositions"));
   // R22: manual positions present at start are closed as well (no grandfathering) -> announce it loudly beforehand
   if(InpCloseManualTrades)
   {
      if(InpMagic==0)   // FAILSAFE: panel trades then carry magic 0 themselves and would be indistinguishable from manual ones
      { Notify(T("cfg.r22DisabledMagicZero"));
        Journal("INFO","-","-",0,0,0,0,0,"R22 wegen InpMagic=0 deaktiviert (Failsafe)"); }
      else
      {
         int man=0;
         for(int mi=OrdersTotal()-1;mi>=0;mi--)
            if(OrderSelect(mi,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==0) man++;
         // Honestly: OnInit closes nothing. The close runs via the enforcement cycle and needs the confirmed
         // Master-Instanz (>=2 Cycles) -> typischerweise 1-3 Sekunden, bei geschlossenem Markt (err 132) deutlich laenger.
         if(man>0)
         { Notify(TF("cfg.r22ManualOrdersOpen",IntegerToString(man)));
           Journal("INFO","-","-",0,0,0,0,0,StringFormat("R22 Start: %d manuelle Order(s) vorgefunden -> werden geschlossen",man)); }
         else Notify(T("cfg.r22PanelOnly"));
         // R22 deliberately does NOT hang off the WatchScope -> applies account-wide across all symbols and in FundedMode too
         if(InpFundedMode)                   Notify(T("cfg.r22FundedNote"));
         if(InpWatchScope==TOOL_PLUS_MANUAL) Notify(T("cfg.r22ScopeNote"));
      }
   }
   Cycle();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){ EventKillTimer();
   // v0.42-fix (CRITICAL): release the master by SETTING TO 0, NOT by deleting! GlobalVariableSetOnCondition cannot
   //   create a MISSING variable (err 4058) — after a delete a master could NEVER be elected again
   //   (deadlock: no enforcement, no close accounting, no cockpit data, until F3/re-creation).
   if(GlobalVariableCheck(GV_MASTER) && GlobalVariableGet(GV_MASTER)==(double)ChartID()){ GlobalVariableSet(GV_MASTER,0.0); GlobalVariableSet(GV_MASTER_HB,0.0); }   // the slot still exists -> immediate takeover by the next instance
   Journal("PROTECT_OFF","-","-",0,0,0,0,0,StringFormat("EA gestoppt (reason=%d) — Watchdog inaktiv (Tamper/Schutz-aus moeglich)",reason)); ObjectsDeleteAll(0,PFX); Comment(""); }

void OnTick()
{
   UpdateSrvOffset();          // jeder Tick liefert frische Serverzeit -> Offset pflegen
   uint now=GetTickCount();
   if(now - g_lastActionMs < (uint)InpMinActionMs) return;
   g_lastActionMs = now;
   Cycle();
}
void OnTimer(){ Cycle(); }   // P0-1: Enforcement laeuft auch tickunabhaengig

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   // v0.49: Enter in the input field confirms just like the "SETZEN" (set) button
   if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam==PFX+"rkin"){ ApplyWeekRiskFromEdit(); return; }
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam==PFX+"buy"){  ObjectSetInteger(0,sparam,OBJPROP_STATE,false); GateClick(true);  }
      if(sparam==PFX+"sell"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); GateClick(false); }
      if(sparam==PFX+"cockpit"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); OpenCockpit(); }   // v0.26
      // v0.40: close buttons — risk REDUCTION, therefore they ALWAYS run (even under lock/cooldown), immediately without confirmation
      if(sparam==PFX+"fc"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); PanelClose(false,false); }
      if(sparam==PFX+"cc"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); PanelClose(true, false); }
      if(sparam==PFX+"f5"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); PanelClose(false,true ); }
      if(sparam==PFX+"c5"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); PanelClose(true, true ); }
      if(sparam==PFX+"be"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); PanelBreakEven(true); }   // v0.46: Risk-Free (Chart)
      if(sparam==PFX+"rkset"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ApplyWeekRiskFromEdit(); }   // v0.49: Wochen-Risiko bestaetigen
      if(InpTestMode && !InpFundedMode)
      {
         if(sparam==PFX+"t1"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); TestAction("cooldown"); }
         if(sparam==PFX+"t2"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); TestAction("daylock");  }
         if(sparam==PFX+"t3"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); TestAction("maxlock");  }
         if(sparam==PFX+"t4"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); TestAction("revenge");  }
         if(sparam==PFX+"t5"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); TestAction("corrupt");  }
         if(sparam==PFX+"t6"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); TestAction("reset");    }
      }
      return;
   }
   if(id==CHARTEVENT_OBJECT_DRAG && sparam==SLLINE)
   { ObjectSetString(0,PFX+"prev",OBJPROP_TEXT,Clip(PreviewText(),42)); ChartRedraw(0); return; }   // v0.37: one line immediately; the full-text wrapping is done by DrawPanel
   if(id==CHARTEVENT_CLICK)
   {
      int cx=(int)lparam, cy=(int)dparam;
      if(cx>=PS(12) && cx<=PS(312) && cy>=PS(16) && cy<=PS(16)+PS(PanelH())) return;   // v0.25: do not treat a click ON THE PANEL as an SL zone (v0.37: scaled with InpPanelScale, like the card)
      int sub=0; datetime tt=0; double pp=0;
      // §07-fix: treat only clicks in the MAIN WINDOW (sub==0) as an SL zone — in an indicator subwindow
      //   ChartXYToTimePrice returns the indicator value (e.g. RSI 42) and that would be adopted as the SL price.
      if(ChartXYToTimePrice(0,cx,cy,sub,tt,pp) && pp>0 && sub==0)
         SlZoneClick(NormalizeDouble(pp,Digits));   // only set after InpSlClicksToMove clicks in the same zone
   }
}

void GateClick(bool isBuy)
{
   if(!InpFomoGate){ DoEntry(isBuy); return; }
   int want=isBuy?1:2;
   if(g_armed==want && (GetTickCount()-g_armMs) >= (uint)(InpFomoSeconds*1000)){ g_armed=0; DoEntry(isBuy); }
   else { g_armed=want; g_armMs=GetTickCount(); Notify(TF("fomo.arm",IntegerToString(InpFomoSeconds),isBuy?"BUY":"SELL")); g_panelSig=""; }
}

double DayStartBaseInput()   // v0.37-fix: InpDayStartBase only if plausible; decimal-separator typo (e.g. 163.659 instead of 163659) -> treat as not set
{
   double d=InpDayStartBase;
   if(d>0 && AccountBalance()>0 && d < AccountBalance()*0.1) return 0;   // unplausibel klein -> ignorieren (Tagesbasis bleibt unsicher)
   return d;
}
void RollNewDay(bool firstAttach=false)
{
   // P0-5: FTMO base = max(balance,equity) at the midnight roll.
   // v0.38: FULLY AUTOMATIC — a first start in the middle of the day reconstructs the midnight base from the history
   //   (no more warn flag/lock); InpDayStartBase remains as the manual override.
   double dsb = DayStartBaseInput();   // v0.37-fix: tippfehler-geprueft
   double dayBase;
   if(firstAttach && dsb>0) dayBase = dsb;                                                                // §04-fix (high): manual midnight base ONLY on the first start
   else if(firstAttach)     // v0.38: first start in the middle of the day -> reconstruct the real midnight base from the history
   {                        //   (balance minus the results realized since then). Conservative upward against the actual state.
      double rec = ReconstructedBalanceAt(ServerDayStart());
      dayBase = MathMax(rec, MathMax(AccountBalance(), AccountEquity()));
      Journal("INFO","-","-",0,0,0,0,0,StringFormat("Auto-Tagesbasis (Erststart): %.2f (rekonstruiert %.2f)",dayBase,rec));
   }
   else                                                                                                   // Folgetage: echter Mitternachts-Snapshot — bei VERSPAETETEM Roll (EA war
   {                                                                                                      // across the reset boundary) additionally reconstruct the midnight balance from the
      double rec = ReconstructedBalanceAt(ServerDayStart());                                              // history (§04-fix medium): otherwise night-time SL hits lower the
      dayBase = MathMax(MathMax(AccountBalance(), AccountEquity()), rec);                                 // base and the 2% limit measures from the dropped level. On a punctual
   }                                                                                                      // roll rec == balance (no closes since the anchor) -> behavior unchanged.
   if(InpDayResetHour!=EffResetHour()){ GlobalVariableSet(GV_EFF_RH,(double)InpDayResetHour); Notify(TF("time.dayResetHourActive",IntegerToString(InpDayResetHour))); }   // §05-fix: adopt a changed input only at the real rollover
   // §05-fix (high): adopt a base change (a lowering too) only at the real day change.
   // v0.38-fix (Verify): ONLY plausible values — the decimal-separator typo (163.66 instead of 163659) that OnInit
   //   discards must not slip through here either (R4b would otherwise be silently disabled).
   if(!firstAttach && InpInitialBalance>0 && MathAbs(InpInitialBalance-g_initialBalance)>0.01
      && !(AccountBalance()>0 && InpInitialBalance < AccountBalance()*0.1))
   { g_initialBalance=InpInitialBalance; g_initBalConfirmed=true; GlobalVariableSet(GV_INIT_BAL,InpInitialBalance);
     Notify(TF("base.challengeBaseRollover",DoubleToString(InpInitialBalance,2))); }
   GlobalVariableSet(GV_DAYSTART_EQ,  dayBase);
   GlobalVariableSet(GV_DAYSTART_DAY, (double)ServerDayKey());
   GlobalVariableSet(GV_LOCK_UNTIL,   0); ClearLockWhy();   // v0.65b: otherwise yesterday's reason sticks to the next lock
   GlobalVariableSet(GV_DAY_RISK,     0);
   GlobalVariableSet(GV_CONSEC,       0);
   // §07-fix: do not cut off a still RUNNING cooldown at the day change — otherwise R5 was, shortly before midnight,
   //   systematisch verkuerzt bzw. durch Warten bis 00:00 umgehbar. Abgelaufene Cooldowns werden weiterhin genullt.
   { datetime cdNow=GlobalVariableCheck(GV_COOLDOWN)?(datetime)GlobalVariableGet(GV_COOLDOWN):0;
     GlobalVariableSet(GV_COOLDOWN, (cdNow>SrvTime()) ? (double)cdNow : 0); }
   GlobalVariableSet(GV_PEAK_EQ,      dayBase);
   GlobalVariableSet(GV_TARGET_HIT,   0);
   // v0.38-fix (Verify): do not blindly zero BASE_WARN — the fail-closed case "no valid account base"
   //   (g_initialBalance<=0, e.g. EA start before the broker handshake) must survive the roll, otherwise
   //   liefe R4b dauerhaft mit Basis 0 (fail-open).
   GlobalVariableSet(GV_BASE_WARN,    (g_initialBalance<=0) ? 1 : 0);
   // v0.30-fix: EFF limits + protection-off counters are NOT set here (RollNewDay also runs from OnInit on EVERY instance).
   //            The master sets them once per day in Cycle() -> deterministic = master input (no loose limit from the init order).
   GlobalVariablesFlush();
   PrintFormat("Mamal: new trading day. Base=%.2f", dayBase);
}

bool IsHardLocked(){ return GlobalVariableCheck(GV_HARD_LOCK) && GlobalVariableGet(GV_HARD_LOCK)>0.5; }
bool IsDayLocked(){ if(!GlobalVariableCheck(GV_LOCK_UNTIL)) return false; datetime u=(datetime)GlobalVariableGet(GV_LOCK_UNTIL); return (u>0 && SrvTime()<u); }
bool IsWeekLocked(){ return GlobalVariableCheck(GV_WEEK_LOCK) && (long)GlobalVariableGet(GV_WEEK_LOCK)==WeekIdx(); }
bool IsLocked(){ return IsDayLocked() || IsHardLocked() || IsWeekLocked(); }
bool CooldownActive(){ if(!GlobalVariableCheck(GV_COOLDOWN)) return false; return SrvTime() < (datetime)GlobalVariableGet(GV_COOLDOWN); }
bool TargetHit(){ return GlobalVariableCheck(GV_TARGET_HIT) && GlobalVariableGet(GV_TARGET_HIT)>0.5; }
bool BaseWarn(){ return GlobalVariableCheck(GV_BASE_WARN) && GlobalVariableGet(GV_BASE_WARN)>0.5; }
double TotalDDpct(){ double eq=AccountEquity(); if(g_initialBalance<=0) return 0; double d=(g_initialBalance-eq)/g_initialBalance*100.0; return d>0?d:0; }   // R4b
// v0.30 self-lock: effective limit = tightening possible immediately, LOOSENING only at the day change (RG_EFF_* is set from the input at the day roll; intraday only tightened).
// §06-fix (medium): (a) extended to ALL lock-relevant inputs — so far only daily/max loss were protected, while
//   weekly limit, warn gate, R5/R6 parameters, giveback, risk/trade and even the SL/TP requirement were freely loosenable intraday.
//   (b) InpTightenOnly itself latched: the self-lock could be switched off with a single input flip (contradicts
//   R4 "immutability not configurable" and R10 no-override). The latch is re-seeded from the input only at the daily roll.
// §07-fix: rare but critical latches (lock set / daily target reached) are persisted IMMEDIATELY instead of only at the
//   bundled flush at cycle end — a crash in the window in between made the freshly set state disappear.
//   Do not flush while a trade operation is running (Wine protection, same as for the regular flush).
void PersistLatch(){ g_gvDirty=true; if(!IsTradeContextBusy()){ GlobalVariablesFlush(); g_gvDirty=false; } }
bool TightenOn(){ if(InpTightenOnly) return true; return (GlobalVariableCheck(GV_TIGHT_LATCH) && GlobalVariableGet(GV_TIGHT_LATCH)>0.5); }
double EffMinPct(string gv,double inp)   // smaller = stricter; <=0 means OFF (= weakest state)
{
   if(!TightenOn() || !GlobalVariableCheck(gv)) return inp;
   double st=GlobalVariableGet(gv);
   if(st<=0)  return inp;      // stored value was OFF -> any input (even a stricter one) applies immediately
   if(inp<=0) return st;       // input OFF = looser -> keep the stored value
   return MathMin(inp,st);
}
double EffMaxNum(string gv,double inp)   // groesser = strenger (z.B. Cooldown-Dauer)
{
   if(!TightenOn() || !GlobalVariableCheck(gv)) return inp;
   return MathMax(inp,GlobalVariableGet(gv));
}
bool EffFlagOn(string gv,bool inp)       // once ON -> not switchable off intraday
{
   if(inp) return true;
   if(!TightenOn() || !GlobalVariableCheck(gv)) return inp;
   return (GlobalVariableGet(gv)>0.5);
}
double EffDailyLoss(){   return EffMinPct(GV_EFF_DL,  InpDailyLossPct);   }
double EffMaxLoss(){     return EffMinPct(GV_EFF_ML,  InpMaxLossPct);     }
double EffWeekLoss(){    return EffMinPct(GV_EFF_WEEK,InpWeeklyLossPct);  }
double EffMaxLossWarn(){ return EffMinPct(GV_EFF_WARN,InpMaxLossWarnPct); }
double EffGivebackPct(){ return EffMinPct(GV_EFF_GIVE,InpGivebackPct);    }
// v0.36: desired risk/trade = the value chosen in the panel for THIS week; otherwise the input default.
//   Becomes the base of the whole auto-scale cascade (idea/heat/daily budget). The trade COUNT rules (R5/R6 counters)
//   deliberately do NOT hang off this — they stay InpCooldownAfter/InpLockAfter.
//   v0.62: The VALUE no longer hangs off the week index. Previously it fell back at the week change to the
//   input default as long as the new week was not confirmed — then R1 (EnforceRisk,
//   comparison against EffRiskPct()) forced weekend positions closed on Monday that were correctly sized
//   according to the last confirmed weekly value. The index now controls exclusively the
//   CONFIRMATION (WeekRiskSet) — i.e. whether trading is allowed, not with which size it is computed.
double DesiredRiskPct()
{
   if(GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0)
      return GlobalVariableGet(GV_WEEK_RISK);
   return InpRiskPerTradePct;
}
double EffRiskPct(){ double r=EffMinPct(GV_EFF_RISK,DesiredRiskPct()); if(r>1.0) r=1.0; if(r<0) r=0; return r; }   // base = weekly choice/input; daily tighten-only stays on top as intraday safeguard (no raising within the day)
double RiskCap(){ double m=InpRiskMaxPct; if(m<=0 || m>1.0) m=1.0; return m; }   // Waehler-Obergrenze, hart bei 1,0 %
// v0.36: pre-booked increase (for next week) — 0 if none.
double PendingWeekRisk(){ return GlobalVariableCheck(GV_WEEK_RISK_NXT) ? GlobalVariableGet(GV_WEEK_RISK_NXT) : 0; }
// v0.36: the user chooses his weekly risk in the panel. Semantics "once for the whole week": the FIRST choice of a week
//   is free; after that the week is FIXED — ANY change (up OR down) takes effect only at the next week change
//   (deliberately chosen risk = bound for the week; no fiddling around, not even lowering). Prop = own account.
void SetWeekRisk(double v)
{
   v = NormalizeDouble(v,2);
   if(v < InpRiskStep) v = InpRiskStep;   // not below one step size
   if(v > RiskCap())   v = RiskCap();
   long   wk    = WeekIdx();
   bool   fresh = (!GlobalVariableCheck(GV_WEEK_RISK) || GlobalVariableGet(GV_WEEK_RISK)<=0
                   || (long)GlobalVariableGet(GV_WEEK_RISK_IDX)!=wk);   // not yet set this week
   double cur   = DesiredRiskPct();
   if(fresh)   // FIRST choice of the week -> free, effective immediately; after that the week is bound
   {
      GlobalVariableSet(GV_WEEK_RISK,     v);
      GlobalVariableSet(GV_WEEK_RISK_IDX, (double)wk);
      if(GlobalVariableCheck(GV_WEEK_RISK_NXT)) GlobalVariableDel(GV_WEEK_RISK_NXT);
      GlobalVariableSet(GV_EFF_RISK,v);   // effective immediately (otherwise the daily tighten-only layer would push the first choice down)
      PersistLatch();
      Notify(TF("risk.set.confirmed",DoubleToString(v,2)));
      Journal("INFO","-","-",0,0,0,0,v,StringFormat("Wochen-Risiko gesetzt: %.2f%% (fest fuer die Woche)",v));
   }
   else if(MathAbs(v-cur)<=0.0001)   // typed back to the currently fixed value -> cancel any pre-booking
   {
      if(GlobalVariableCheck(GV_WEEK_RISK_NXT)){ GlobalVariableDel(GV_WEEK_RISK_NXT); PersistLatch(); Notify(TF("cfg.weekRiskPendingCancelled",DoubleToString(cur,2))); }
      else Notify(TF("cfg.weekRiskAlreadySet",DoubleToString(cur,2)));
   }
   else   // ANY change (up OR down) within the running week -> pre-book for next week
   {
      GlobalVariableSet(GV_WEEK_RISK_NXT, v); PersistLatch();
      Notify(TF("risk.set.pending",DoubleToString(v,2),DoubleToString(cur,2)));
      Journal("INFO","-","-",0,0,0,0,v,StringFormat("Wochen-Risiko-Aenderung %.2f%% vorgemerkt (ab naechster Woche)",v));
   }
   g_panelSig="";
}
void ChangeWeekRisk(int dir)   // panel [-]/[+]: build on an existing pre-booking, otherwise on the current value
{
   double base = (PendingWeekRisk()>0) ? PendingWeekRisk() : DesiredRiskPct();
   SetWeekRisk(base + dir*InpRiskStep);
}
// v0.49: Has the weekly risk been deliberately set for the CURRENT week?
bool WeekRiskSet()
{
   return (GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0
           && GlobalVariableCheck(GV_WEEK_RISK_IDX) && (long)GlobalVariableGet(GV_WEEK_RISK_IDX)==WeekIdx());
}
// v0.62: Is the weekly commitment still pending (R23)? ONE source for gate, panel status, button greying
//   and sub-line. Deliberately from the LOCAL inputs of this instance — each instance decides for itself whether it
//   lets trading happen. The weekly roll (master) must NOT pre-empt this decision globally: otherwise
//   a chart with InpRequireWeeklyRisk=false that happens to be master would have lifted the gate for all others.
bool WeekRiskPending(){ return (InpRiskChooser && InpRequireWeeklyRisk && !WeekRiskSet()); }
// v0.49: evaluate the input field — the trader types his weekly value and confirms.
//   A decimal comma is accepted (a German keyboard writes "0,25"); without this conversion
//   MQL4 would read 0 from it and silently discard the input.
void ApplyWeekRiskFromEdit()
{
   string t=ObjectGetString(0,PFX+"rkin",OBJPROP_TEXT);
   StringReplace(t,",","."); StringReplace(t,"%",""); StringReplace(t," ","");
   StringTrimLeft(t); StringTrimRight(t);
   double v=StringToDouble(t);
   if(v<=0 || v>1.0)
   {
      Notify(TF("risk.set.invalid",t));
      g_rkEditSync="";   // reset the field to the valid state
      g_panelSig=""; return;
   }
   SetWeekRisk(v);
   g_rkEditSync=""; g_panelSig="";   // relabel the field with the value actually accepted
}
int  EffLockAfter(){     return (int)EffMinPct(GV_EFF_LOCKAFT,(double)InpLockAfter);    }
int  EffCooldownAfter(){ return (int)EffMinPct(GV_EFF_CDAFT,  (double)InpCooldownAfter);}
int  EffCooldownMin(){   return (int)EffMaxNum(GV_EFF_CDMIN,  (double)InpCooldownMin);  }
bool EffRequireSL(){     return EffFlagOn(GV_EFF_REQSL,InpRequireSL);  }
bool EffRequireTP(){     return EffFlagOn(GV_EFF_REQTP,InpRequireTP);  }
bool EffUseCorrCap(){    return EffFlagOn(GV_EFF_CORR, InpUseCorrCap); }
void TightenPersistMin(string gv,double inp,string label)   // persist the stricter value immediately (survives a restart on the same day)
{
   if(inp<=0) return;                                       // OFF = looser -> never persist
   if(!GlobalVariableCheck(gv) || GlobalVariableGet(gv)<=0 || inp < GlobalVariableGet(gv)-0.0001)
   { GlobalVariableSet(gv,inp); g_gvDirty=true; if(StringLen(label)>0) Notify(TF("cfg.tightenedImmediately",label,DoubleToString(inp,2))); }
}
void TightenPersistMax(string gv,double inp){ if(!GlobalVariableCheck(gv) || inp > GlobalVariableGet(gv)+0.0001){ GlobalVariableSet(gv,inp); g_gvDirty=true; } }
void TightenPersistFlag(string gv,bool inp){ if(inp && (!GlobalVariableCheck(gv) || GlobalVariableGet(gv)<0.5)){ GlobalVariableSet(gv,1); g_gvDirty=true; } }
void TightenOnlyLimits()   // pro Cycle (Master): Input ENGER als effektiv -> sofort; LOCKERER -> ignoriert bis Tageswechsel
{
   if(!TightenOn()) return;
   TightenPersistMin(GV_EFF_DL,      InpDailyLossPct,           "daily limit");
   TightenPersistMin(GV_EFF_ML,      InpMaxLossPct,             "Max-Limit");
   TightenPersistMin(GV_EFF_WEEK,    InpWeeklyLossPct,          "weekly limit");
   TightenPersistMin(GV_EFF_WARN,    InpMaxLossWarnPct,         "");
   TightenPersistMin(GV_EFF_GIVE,    InpGivebackPct,            "");
   TightenPersistMin(GV_EFF_RISK,    DesiredRiskPct(),          "");   // v0.36: base is the weekly choice, no longer the raw input
   TightenPersistMin(GV_EFF_LOCKAFT,(double)InpLockAfter,       "");
   TightenPersistMin(GV_EFF_CDAFT,  (double)InpCooldownAfter,   "");
   TightenPersistMax(GV_EFF_CDMIN,  (double)InpCooldownMin);
   TightenPersistFlag(GV_EFF_REQSL,  InpRequireSL);
   TightenPersistFlag(GV_EFF_REQTP,  InpRequireTP);
   TightenPersistFlag(GV_EFF_CORR,   InpUseCorrCap);
}
bool MaxLossWarnActive(){ double w=EffMaxLossWarn(); return (w>0 && EffMaxLoss()>0 && w<EffMaxLoss() && TotalDDpct()>=w); }   // R4b Warn-Gate (mit Input-Schutz)
// v0.63: loud=true for tamper / protection-failure findings. Exactly that showed up in testing: the
//   detection "lockstate file missing" fired correctly, but the message stood in the panel for only 6 s and
//   InpUseAlert is off by default — the trader was left with a silent finding. Such events are
//   rare enough that a forced alert is not spam, and important enough that missing one would be expensive.
void Notify(string m, bool info=false, bool loud=false)   // v0.37: info=true -> neutral note (cockpit), no red "NICHT MOEGLICH" (not possible)
{
   Print(m);
   if(InpUseAlert || loud) Alert(m);
   // v0.64: A standing tamper finding is NOT overwritten by harmless messages. Without that
   //   the long display time was useless: the missing branch itself sets a day lock whose message
   //   ran in right behind the finding and replaced it within fractions of a second.
   if(!loud && g_flashLoud && (GetTickCount()-g_flashMs) < g_flashHold) return;
   g_flashLoud = loud;
   g_flashHold = loud ? 120000 : 6000;
   string fm=m; if(StringSubstr(fm,0,7)=="Mamal: ") fm=StringSubstr(fm,7);      // v0.21: short panel form without prefix
   fm=Clip(fm,132);                                                             // v0.37: vollen Text behalten (bis zu 3 Panel-Zeilen); Umbruch macht DrawPanel
   g_flash=fm; g_flashMs=GetTickCount(); g_flashInfo=info;                      // show reason/message in the panel for 6s
   if(ObjectFind(0,PFX+"prev")>=0){ ObjectSetString(0,PFX+"prev",OBJPROP_TEXT,Clip(fm,42)); ObjectSetInteger(0,PFX+"prev",OBJPROP_COLOR,info?C'150,200,255':C'255,140,60'); ChartRedraw(0); }   // immediate first line; the rest follows at the next DrawPanel
   g_panelSig="";                                                               // forces a redraw at the next DrawPanel
}

// §05-fix (high): can also be evaluated for an ARBITRARY point in time (t) -> "was the position opened DURING a lock?"
bool InSessionAt(datetime t)
{
   if(!InpUseSession) return true;
   if(InpSessionStart==InpSessionEnd) return true;
   int h=TimeHour(t);
   if(InpSessionStart < InpSessionEnd) return (h>=InpSessionStart && h<InpSessionEnd);
   return (h>=InpSessionStart || h<InpSessionEnd);
}
bool InNewsBlackoutAt(datetime t)
{
   if(InpNewsFrom==InpNewsTo) return false;
   int hm=TimeHour(t)*100+TimeMinute(t);
   if(InpNewsFrom < InpNewsTo) return (hm>=InpNewsFrom && hm<InpNewsTo);
   return (hm>=InpNewsFrom || hm<InpNewsTo);
}
bool OffSessionAt(datetime t){ return (InpUseSession && !InSessionAt(t)) || InNewsBlackoutAt(t); }
bool InSession(){ return InSessionAt(SrvTime()); }
bool InNewsBlackout(){ return InNewsBlackoutAt(SrvTime()); }
bool OffSession(){ return OffSessionAt(SrvTime()); }

double EffectiveRiskPct()
{
   int c=(int)GlobalVariableGet(GV_CONSEC);
   if(InpDeRiskFactor<1.0 && c>=InpDeRiskAfter) return EffRiskPct()*InpDeRiskFactor;   // R19
   return EffRiskPct();
}
double EffIdeaCap(){ return InpAutoScale ? EffRiskPct()*InpIdeaXrisk : InpIdeaCapPct; }   // §06-fix: risk/trade tighten-only -> the whole auto-scale cascade can no longer be raised intraday
double EffHeat()   { return InpAutoScale ? EffIdeaCap()*InpHeatXidea      : InpPortfolioHeatPct; }
double EffDay()    { return InpAutoScale ? EffIdeaCap()*InpDayXidea       : InpDailyRiskBudgetPct; }
// §07-fix: R17 was a DEAD rule under auto-scale. The largest net currency exposure can never be larger than
//   the sum of all risks (= heat). So with InpCorrCapPct=1.5 % against a heat cap of 1.0 % the gate could NEVER
//   bite. Under auto-scale the cap is therefore tied to the heat cap (75 %) — a stricter manual
//   InpCorrCapPct gewinnt weiterhin.
double EffCorrCap(){ double c=InpCorrCapPct; if(InpAutoScale){ double a=EffHeat()*0.75; if(a>0 && (c<=0 || a<c)) c=a; } return c; }
// R17 (v0.17): currency vector instead of USD-only. Every position loads the base currency (long on BUY) and
// the quote currency (short on BUY) with its risk%. Non-FX (indices) -> own bucket keyed on the symbol name.
bool IsCcy(string c){ return StringFind(" USD EUR GBP JPY CHF AUD CAD NZD SGD HKD NOK SEK DKK PLN ZAR MXN TRY CNH CZK HUF ", " "+c+" ")>=0; }   // B19: gueltige ISO-Codes
bool SplitCcy(string s,string &base,string &quote)
{
   string a=StringSubstr(s,0,6);
   if(StringLen(a)<6) return false;
   for(int i=0;i<6;i++){ ushort c=StringGetCharacter(a,i); if(!((c>='A'&&c<='Z')||(c>='a'&&c<='z'))) return false; }
   base=StringSubstr(a,0,3); quote=StringSubstr(a,3,3);
   StringToUpper(base); StringToUpper(quote);
   if(!IsCcy(base) || !IsCcy(quote)) return false;   // B19: 6-letter non-FX (CFD/crypto) -> no phantom currency bucket
   return true;
}
void AddCcy(string &ccy[],double &net[],int &n,string c,double v)
{
   for(int i=0;i<n;i++) if(ccy[i]==c){ net[i]+=v; return; }
   ArrayResize(ccy,n+1); ArrayResize(net,n+1); ccy[n]=c; net[n]=v; n++;
}
void AddExposure(string &ccy[],double &net[],int &n,string sym,bool isBuy,double rp)
{
   string b,q;
   if(SplitCcy(sym,b,q)){ AddCcy(ccy,net,n,b, isBuy? rp : -rp); AddCcy(ccy,net,n,q, isBuy? -rp : rp); }
   else { string u=sym; StringToUpper(u); AddCcy(ccy,net,n,u, isBuy? rp : -rp); }   // non-FX: single bucket
}
double MaxCurrencyExposurePct(string addSym,bool addBuy,double addRp,bool conservative=false)   // groesste |Netto-Waehrungs-Exposition| inkl. hypothetischem Trade
{
   string ccy[]; double net[]; int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int t=OrderType(); if(t!=OP_BUY && t!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;
      if(OrderStopLoss()==0.0)   // §06-fix: do not count a naked position as 0 % (otherwise the gate can be bypassed)
      { if(conservative) AddExposure(ccy,net,n,OrderSymbol(),(t==OP_BUY),EffRiskPct()); continue; }
      AddExposure(ccy,net,n,OrderSymbol(),(t==OP_BUY),RiskPctOf(OrderSymbol(),OrderLots(),OrderOpenPrice(),OrderStopLoss()));
   }
   if(addRp>0) AddExposure(ccy,net,n,addSym,addBuy,addRp);
   double mx=0; for(int k=0;k<n;k++){ double a=MathAbs(net[k]); if(a>mx) mx=a; }
   return mx;
}
// R25 PERSISTENT (v0.17): Revenge-Fenster in GlobalVariables -> ueberlebt Neustart.
string RevDirKey(string s){ return "RG_REVD_"+s; }    // verlorene Richtung (OP_BUY/OP_SELL)
string RevUntilKey(string s){ return "RG_REVU_"+s; }  // gueltig-bis (Server-Zeit)
void SetRevenge(string s,int lostType)   // R25
{
   if(InpRevengeMin<=0) return;   // disabled -> write no markers
   GlobalVariableSet(RevDirKey(s), (double)lostType);
   GlobalVariableSet(RevUntilKey(s), (double)(SrvTime()+InpRevengeMin*60));
   g_gvDirty=true;   // v0.22: flush bundled at cycle end (SetRevenge runs in the close path via ApplyResult)
}
bool RevengeBlocked(string s,bool isBuy)
{
   if(InpRevengeMin<=0) return false;
   if(!GlobalVariableCheck(RevUntilKey(s))) return false;
   datetime until=(datetime)GlobalVariableGet(RevUntilKey(s));
   if(SrvTime()>=until) return false;                 // Fenster abgelaufen
   int lostType=(int)GlobalVariableGet(RevDirKey(s));
   if(lostType==OP_BUY  && !isBuy) return true;       // Verlust war BUY -> Gegen-SELL gesperrt
   if(lostType==OP_SELL &&  isBuy) return true;       // Verlust war SELL -> Gegen-BUY gesperrt
   return false;
}
void PruneRevenge()   // abgelaufene Revenge-Marker (RG_REVU_/RG_REVD_) aufraeumen
{
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   {
      string nm=GlobalVariableName(i);
      if(StringFind(nm,"RG_REVU_")==0 && (datetime)GlobalVariableGet(nm) < SrvTime())
      {
         string sym=StringSubstr(nm,8);   // after "RG_REVU_"
         GlobalVariableDel(nm);
         if(GlobalVariableCheck("RG_REVD_"+sym)) GlobalVariableDel("RG_REVD_"+sym);
      }
   }
}

string RuleIdFromTag(string tag)   // pull the leading "Rxx" out of the tag (empty otherwise)
{
   if(StringLen(tag)>=2 && StringGetCharacter(tag,0)=='R')
   {
      ushort c1=StringGetCharacter(tag,1);
      if(c1>='0' && c1<='9'){ int sp=StringFind(tag," "); return (sp>0) ? StringSubstr(tag,0,sp) : tag; }
   }
   return "";
}
// v0.17: audit-grade journal — context (time/account/balance/equity/magic/DayKey/RuleId) is filled
// automatically, ticket/net optional. Header on first write. Call sites stay unchanged.
void Journal(string ev,string sym,string dir,double lot,double entry,double sl,double tp,double riskpct,string tag,int ticket=0,double net=0.0)
{
   // v0.32 Panel-Spiegel: Versuche (BLOCKED) + Trades (OPEN) zaehlen — geteilt (kontoweit), unabhaengig vom CSV-Journal
   if(ev=="BLOCKED")
   {
      GlobalVariableSet(GV_BLOCKS, GlobalVariableGet(GV_BLOCKS)+1);
      datetime nb=SrvTime(); datetime bl=(datetime)GlobalVariableGet(GV_BLK_LAST);
      double burst = ((nb-bl) < 60) ? GlobalVariableGet(GV_BLK_BURST)+1 : 1;   // rejections in the last 60s window
      GlobalVariableSet(GV_BLK_BURST, burst); GlobalVariableSet(GV_BLK_LAST,(double)nb); g_gvDirty=true;
      if(burst==3.0) Notify(T("tilt.burst"));   // Tilt-Blitz (nutzt Panel-Flash)
   }
   else if(ev=="OPEN"){ GlobalVariableSet(GV_FILLS, GlobalVariableGet(GV_FILLS)+1); g_gvDirty=true; }
   if(!InpJournal) return;
   // §06-fix (medium): without sharing flags FileOpen failed silently as soon as the cockpit server (or Excel) was just
   //   reading the CSV — the audit entry (TAMPER/CLOSE/FINAL-FAIL included) was then PERMANENTLY lost, without a trace. Now:
   //   FILE_SHARE_READ|FILE_SHARE_WRITE + short retry, and on failure a loud Print instead of a silent return.
   int h=INVALID_HANDLE;
   for(int a=0;a<3 && h==INVALID_HANDLE;a++)
   { h=FileOpen(JOURNAL,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
     if(h==INVALID_HANDLE) Sleep(15); }
   if(h==INVALID_HANDLE)
   { PrintFormat("Mamal: JOURNAL-Schreibfehler %d — Eintrag VERLOREN: %s | %s | %s",GetLastError(),ev,sym,tag); return; }
   if(FileSize(h)==0)
      FileWrite(h,"ServerTime","DayKey","Account","Balance","Equity","Magic","Event","Symbol","Dir","Lot","Entry","SL","TP","Risk%","Ticket","Net","RuleId","Tag");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
      TimeToString(SrvTime(),TIME_DATE|TIME_SECONDS),
      IntegerToString((int)ServerDayKey()),
      IntegerToString(AccountNumber()),
      DoubleToString(AccountBalance(),2),
      DoubleToString(AccountEquity(),2),
      IntegerToString(InpMagic),
      ev,sym,dir,
      DoubleToString(lot,2),DoubleToString(entry,Digits),DoubleToString(sl,Digits),
      DoubleToString(tp,Digits),DoubleToString(riskpct,2),
      IntegerToString(ticket),DoubleToString(net,2),RuleIdFromTag(tag),tag);
   FileClose(h);
}
// v0.47: screenshot tied to a ticket — the file name carries the ticket so cockpit/server can map every image
//   unambiguously to ONE trade: Mamal_<ticket>_<tag>_<epoch>.png (ticket 0 = no trade reference).
void Shot(string tag,int ticket=0)
{
   if(!InpScreenshots) return;
   ChartScreenShot(0,StringFormat("Mamal_%d_%s_%d.png",ticket,tag,(int)SrvTime()),InpShotWidth,InpShotHeight);
}
// v0.47: clean up screenshots — otherwise MQL4/Files grows without bound (one image per action).
//   Runs in the 60s housekeeping, not in the enforcement cycle.
void PruneShots()
{
   if(InpShotKeepDays<=0) return;
   datetime cutoff=SrvTime()-(datetime)InpShotKeepDays*86400;
   string fn; long h=FileFindFirst("Mamal_*.png",fn);
   if(h==INVALID_HANDLE) return;
   int killed=0;
   do
   {
      // the timestamp sits at the end of the file name: Mamal_<ticket>_<tag>_<epoch>.png
      int p2=StringFind(fn,".png");
      if(p2<=0) continue;
      string base=StringSubstr(fn,0,p2);
      int    us=-1;
      for(int k=StringLen(base)-1;k>=0;k--) if(StringGetChar(base,k)=='_'){ us=k; break; }
      if(us<0) continue;
      long ts=StringToInteger(StringSubstr(base,us+1));
      if(ts>0 && (datetime)ts<cutoff && FileDelete(fn)) killed++;
   } while(FileFindNext(h,fn) && killed<200);   // cap per pass (no long I/O block)
   FileFindClose(h);
   if(killed>0) PrintFormat("Mamal: %d old screenshots deleted (older than %d days)",killed,InpShotKeepDays);
}
string SlSeenKey(int t){ return "RGSLS_"+IntegerToString(t); }   // v0.47: zuletzt gesehener SL
string TpSeenKey(int t){ return "RGTPS_"+IntegerToString(t); }   // v0.47: zuletzt gesehener TP

// v0.47: BEHAVIOUR TRACKING — detects per ticket whether SL or TP was moved, and judges the direction.
//   In substance: an SL AWAY from the entry raises the risk (classic mistake of "giving the loss room");
//   an SL TOWARDS the entry lowers it. A TP closer to the entry cuts profits short. The verdict is written as plain text
//   into the journal; the overall evaluation per position is done by the cockpit server from these lines.
void TrackSLTP()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber()) && !GlobalVariableCheck(OpnKey(OrderTicket()))) continue;
      int    tk=OrderTicket();
      double sl=OrderStopLoss(), tp=OrderTakeProfit(), entry=OrderOpenPrice();
      string sk=SlSeenKey(tk), tkk=TpSeenKey(tk);
      bool   firstSight=(!GlobalVariableCheck(sk) && !GlobalVariableCheck(tkk));
      double lastSL=GlobalVariableCheck(sk)?GlobalVariableGet(sk):sl;
      double lastTP=GlobalVariableCheck(tkk)?GlobalVariableGet(tkk):tp;
      if(firstSight){ GlobalVariableSet(sk,sl); GlobalVariableSet(tkk,tp); g_gvDirty=true; continue; }

      int    dg=(int)MarketInfo(OrderSymbol(),MODE_DIGITS); if(dg<=0) dg=5;
      double eps=MarketInfo(OrderSymbol(),MODE_POINT)/2.0; if(eps<=0) eps=Point/2.0;
      bool   isBuy=(ty==OP_BUY);

      if(MathAbs(sl-lastSL)>eps)
      {
         // distance to the entry: larger = more risk
         double dOld=MathAbs(entry-lastSL), dNew=MathAbs(entry-sl);
         string verdict;
         if(lastSL==0)                       verdict="[SL_SET] SL set for the first time";
         else if(sl==0)                      verdict="[SL_GONE] SL REMOVED — risk unlimited (harmful)";
         else if(dNew>dOld+eps)              verdict="[SL_WORSE] SL moved AWAY from entry ("+DoubleToString(lastSL,dg)+" -> "+DoubleToString(sl,dg)+") — risk INCREASED (harmful)";
         else if(dNew<dOld-eps)
         {
            bool be=((isBuy && sl>=entry-eps) || (!isBuy && sl<=entry+eps));
            verdict="[SL_BETTER] SL moved CLOSER to entry ("+DoubleToString(lastSL,dg)+" -> "+DoubleToString(sl,dg)+") — risk reduced"+(be?", break-even reached":"")+" (beneficial)";
         }
         else                                verdict="[SL_FLAT] SL moved sideways (risk unchanged)";
         Journal("SLTP_MOVE",OrderSymbol(),(isBuy?"BUY":"SELL"),OrderLots(),entry,sl,tp,0,verdict,tk);
         Shot("slmove",tk);
         GlobalVariableSet(sk,sl); g_gvDirty=true;
      }
      if(MathAbs(tp-lastTP)>eps)
      {
         double dOld=MathAbs(entry-lastTP), dNew=MathAbs(entry-tp);
         string verdict;
         if(lastTP==0)                       verdict="[TP_SET] TP set for the first time";
         else if(tp==0)                      verdict="[TP_GONE] TP REMOVED — no target defined any more";
         else if(dNew<dOld-eps)              verdict="[TP_SHORTER] TP moved CLOSER to entry ("+DoubleToString(lastTP,dg)+" -> "+DoubleToString(tp,dg)+") — profit cut short";
         else if(dNew>dOld+eps)              verdict="[TP_LONGER] TP moved AWAY ("+DoubleToString(lastTP,dg)+" -> "+DoubleToString(tp,dg)+") — target extended";
         else                                verdict="[TP_FLAT] TP moved sideways";
         Journal("SLTP_MOVE",OrderSymbol(),(isBuy?"BUY":"SELL"),OrderLots(),entry,sl,tp,0,verdict,tk);
         Shot("tpmove",tk);
         GlobalVariableSet(tkk,tp); g_gvDirty=true;
      }
   }
}

//--- v0.26: cockpit bridge (DLL-free) — live state as JSON in MQL4/Files, a local server serves the localhost page from it ---
string JB(bool b){ return b?"true":"false"; }
void WriteCockpit()
{
   double eq=AccountEquity(), bal=AccountBalance();
   double base=GlobalVariableGet(GV_DAYSTART_EQ); if(base<=0) base=MathMax(bal,eq); if(base<=0) base=1;
   double dailyDD=(base-eq)/base*100.0; if(dailyDD<0) dailyDD=0;
   double dayR=GlobalVariableGet(GV_DAY_RISK);
   double heat=TotalOpenRiskPct();
   int    consec=(int)GlobalVariableGet(GV_CONSEC);
   double profitPct=(eq-base)/base*100.0;
   double wbase=GlobalVariableGet(GV_WEEKSTART_EQ); if(wbase<=0) wbase=eq;
   double weekDD=(wbase-eq)/wbase*100.0; if(weekDD<0) weekDD=0;
   int    cdSec=0; if(CooldownActive()){ cdSec=(int)((datetime)GlobalVariableGet(GV_COOLDOWN)-SrvTime()); if(cdSec<0) cdSec=0; }
   bool   disabled=!IsTradeAllowed();
   bool   maxw=(!IsLocked() && !disabled && MaxLossWarnActive());

   string st="AKTIV", sc="green";
   if(disabled)              { st=T("status.guardOff");        sc="amber"; }
   else if(IsLocked())       { st=(IsHardLocked()?T("status.hardLock"):(IsWeekLocked()?T("status.weekLock"):T("status.dayLock"))); sc="red"; }
   else if(BaseWarn())       { st=T("status.baseWarn");    sc="amber"; }   // §07-fix: BaseWarn blocks EVERY entry, but was displayed as "AKTIV" (active)
   // v0.62: R23 was missing from the cockpit ladder — the dashboard showed green "AKTIV" (active) while the panel
   //   blocked. Order deliberately identical to the panel ladder (DrawPanel), otherwise the two displays drift apart.
   else if(WeekRiskPending()){ st=T("status.setWeekRisk");  sc="blue"; }
   else if(maxw)             { st=T("status.maxLossWarn");  sc="amber"; }
   else if(CooldownActive()) { st=T("status.cooldown");          sc="amber"; }
   else if(TargetHit())      { st=T("status.targetHit");     sc="green"; }
   else if(OffSession())     { st=T("status.offSession");    sc="neutral"; }

   string dis="";
   if(!InpFomoGate)         dis=dis+"\"R9\",";
   if(InpMinRR<=0)          dis=dis+"\"R8\",";
   if(InpMinGapSec<=0)      dis=dis+"\"R14\",";
   if(InpDeRiskFactor>=1.0) dis=dis+"\"R19\",";
   if(InpRevengeMin<=0)     dis=dis+"\"R25\",";
   if(InpMinStopPips<=0)    dis=dis+"\"R15min\",";
   if(!InpCloseManualTrades) dis=dis+"\"R22\",";   // R22: panel-only trades switched off
   if(StringLen(dis)>0) dis=StringSubstr(dis,0,StringLen(dis)-1);

   string j="{";
   j=j+StringFormat("\"v\":\"%s\",\"srvtime\":\"%s\",", EA_VER, TimeToString(SrvTime(),TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   j=j+StringFormat("\"account\":\"%s\",\"symbol\":\"%s\",\"tf\":\"%s\",\"port\":%d,\"profile\":\"%s\",\"funded\":%s,", IntegerToString(AccountNumber()), Symbol(), PeriodStr(), InpCockpitPort, PropFirmName(InpPropFirm), JB(InpFundedMode));   // v0.37: Kontonummer (String, ueberlauf-sicher) -> Dashboard zeigt, WELCHES Konto (bei mehreren Terminals)
   j=j+StringFormat("\"equity\":%s,\"balance\":%s,\"ccy\":\"%s\",\"initBal\":%s,", DoubleToString(eq,2), DoubleToString(bal,2), AccountCurrency(), DoubleToString(g_initialBalance,2));
   j=j+StringFormat("\"status\":\"%s\",\"statusColor\":\"%s\",\"protectOff\":%s,", st, sc, JB(disabled));
   j=j+StringFormat("\"dailyDD\":%s,\"dailyLimit\":%s,\"dayBase\":%s,\"weekBase\":%s,", DoubleToString(dailyDD,2), DoubleToString(EffDailyLoss(),2), DoubleToString(GlobalVariableGet(GV_DAYSTART_EQ),2), DoubleToString(GlobalVariableGet(GV_WEEKSTART_EQ),2));   // v0.39: bases for the € conversion in the dashboard (buffer gauge)
   j=j+StringFormat("\"totalDD\":%s,\"maxLoss\":%s,\"maxLossWarn\":%s,", DoubleToString(TotalDDpct(),2), DoubleToString(EffMaxLoss(),2), DoubleToString(EffMaxLossWarn(),2));
   j=j+StringFormat("\"protOff\":%d,\"tightenOnly\":%s,", (int)GlobalVariableGet(GV_PROTOFF), JB(TightenOn()));   // v0.30: protection-off counter + self-lock status (§06: latched actual state, not the raw input)
   j=j+StringFormat("\"dayRisk\":%s,\"dayBudget\":%s,", DoubleToString(dayR,2), DoubleToString(EffDay(),2));
   j=j+StringFormat("\"heat\":%s,\"heatCap\":%s,\"ideaCap\":%s,\"riskPerTrade\":%s,\"riskNextWeek\":%s,", DoubleToString(heat,2), DoubleToString(EffHeat(),2), DoubleToString(EffIdeaCap(),2), DoubleToString(EffRiskPct(),2), DoubleToString(PendingWeekRisk(),2));   // v0.36: wirksames Risiko/Trade (Wochenwahl) + vorgemerkte Erhoehung
   j=j+StringFormat("\"consec\":%d,\"lockAfter\":%d,\"cooldownAfter\":%d,\"cooldownSec\":%d,\"cooldownMin\":%d,", consec, EffLockAfter(), EffCooldownAfter(), cdSec, EffCooldownMin());
   j=j+StringFormat("\"weekDD\":%s,\"weekLimit\":%s,", DoubleToString(weekDD,2), DoubleToString(EffWeekLoss(),2));
   j=j+StringFormat("\"targetPct\":%s,\"profitPct\":%s,\"givebackPct\":%s,", DoubleToString(InpDailyTargetPct,2), DoubleToString(profitPct,2), DoubleToString(EffGivebackPct(),2));
   j=j+StringFormat("\"dayLock\":%s,\"hardLock\":%s,\"weekLock\":%s,\"targetHit\":%s,\"baseWarn\":%s,\"cooldown\":%s,\"offSession\":%s,\"maxWarn\":%s,\"weekRiskPending\":%s,\"lockWhy\":%d,", JB(IsDayLocked()), JB(IsHardLocked()), JB(IsWeekLocked()), JB(TargetHit()), JB(BaseWarn()), JB(CooldownActive()), JB(OffSession()), JB(maxw), JB(WeekRiskPending()), (IsLocked() && GlobalVariableCheck(GV_LOCK_WHY)) ? (int)GlobalVariableGet(GV_LOCK_WHY) : 0);   // §06-fix: maxWarn as its own flag — otherwise the dashboard showed green "Alles frei" (all clear) while the EA blocked every trade; v0.62: weekRiskPending (R23) likewise
   j=j+StringFormat("\"minStopPips\":%s,\"rr\":%s,\"scope\":%d,", DoubleToString(InpMinStopPips,0), DoubleToString(InpRR,1), (int)InpWatchScope);
   j=j+StringFormat("\"fills\":%d,\"blocks\":%d,\"riskEstimate\":%s,", (int)GlobalVariableGet(GV_FILLS), (int)GlobalVariableGet(GV_BLOCKS), JB(g_tvEstimate));   // §07-fix: GV_FILLS was maintained but read nowhere; riskEstimate makes the TickValue estimate visible
   j=j+StringFormat("\"disabled\":[%s]", dis);
   j=j+"}";

   int h=FileOpen(COCKPIT_TMP,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   FileWriteString(h,j);
   FileClose(h);
   FileMove(COCKPIT_TMP,0,COCKPIT_FILE,FILE_REWRITE);   // atomar ersetzen
   // v0.37: signpost into the common folder (fixed path, no matter whether portable/terminal hash).
   // Tells the server the REAL Files folder of this terminal -> the server always finds JSON/journal/trigger.
   // v0.38-fix (verify): write the signpost only ONCE per session/account — not every 2s.
   //   (Saves I/O and removes the read race on a half-written path line.)
   static long beaconAcct=-2;
   if((long)AccountNumber()!=beaconAcct)
   {
      int hp=FileOpen(COCKPIT_PATHS,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(hp!=INVALID_HANDLE){ FileWriteString(hp,TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL4\\Files"); FileClose(hp); }
      // v0.38: PRO KONTO ein Wegweiser (mamal_files_<login>.txt) — mehrere Terminals/Konten
      //   no longer overwrite each other; from these the server offers the account switcher.
      if(AccountNumber()>0)
      {
         int hp2=FileOpen("mamal_files_"+IntegerToString(AccountNumber())+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
         if(hp2!=INVALID_HANDLE){ FileWriteString(hp2,TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL4\\Files"); FileClose(hp2); }
         beaconAcct=(long)AccountNumber();   // erledigt — erst bei Konto-Wechsel erneut
      }
   }
}
void OpenCockpit()
{
   WriteCockpit();   // frischen Stand garantieren
   int h=FileOpen(COCKPIT_OPEN,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE){ FileWriteString(h,StringFormat("open %d",(int)SrvTime())); FileClose(h); }
   if(!InpCockpit){ Notify(T("cfg.cockpitDisabled")); return; }   // v0.40: otherwise one wonders about 'Daten veraltet' (data stale)
   Notify(TF("info.cockpit",IntegerToString(InpCockpitPort)), true);   // v0.37: ehrlicher Hinweis + URL statt rotem Fehler
}

// v0.40: close buttons — close open positions immediately (risk reduction: NO gates, no confirmation).
//   chartOnly=true -> only this chart's symbol; half=true -> shrink every position by 50% (rounded to lot step,
//   floor rounds in favour of the remainder). Reach deliberately ACCOUNT-WIDE incl. foreign magics (user decision) —
//   pending orders stay untouched. NO MarkEaClosed: for EA-/panel-opened trades losses therefore count
//   normally towards streak/cooldown (trader decision, no laundering); FOREIGN magics are only journalled,
//   their P/L stays outside the evaluation (scope design).
void PanelClose(bool chartOnly,bool half)
{
   if(IsTradeContextBusy()){ Notify(T("info.tradeContextBusy"),true); return; }
   // phase 1 (verify v0.40): freeze the target tickets BEFORE the first close — the pool mutates during the
   //   closes (the 50% remainder gets a NEW ticket) and MQL4 does not guarantee the pool ordering; positionally
   //   a fresh remainder could otherwise be halved again.
   int tks[]; int nT=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int oty=OrderType(); if(oty!=OP_BUY && oty!=OP_SELL) continue;
      if(chartOnly && OrderSymbol()!=Symbol()) continue;
      ArrayResize(tks,nT+1); tks[nT]=OrderTicket(); nT++;
   }
   int closed=0, failed=0, skipped=0;
   for(int t=0;t<nT;t++)
   {
      if(!OrderSelect(tks[t],SELECT_BY_TICKET)) continue;
      if(OrderCloseTime()!=0) continue;   // inzwischen anderweitig geschlossen
      int      ty =OrderType();
      int      tk =OrderTicket();
      string   sy =OrderSymbol();
      datetime ot =OrderOpenTime();
      double   op =OrderOpenPrice();
      int      mg =OrderMagicNumber();
      double   all=OrderLots();
      double stp=MarketInfo(sy,MODE_LOTSTEP); if(stp<=0) stp=0.01;
      double mn =MarketInfo(sy,MODE_MINLOT);  if(mn<=0)  mn=stp;
      double lots=all;
      if(half)
      {
         // +epsilon (verify v0.40): binary FP otherwise makes e.g. 0.06*0.5/0.01 = 2.9999... -> 0.02 instead of 0.03
         lots=NormalizeDouble(MathFloor(all*0.5/stp + 0.0000001)*stp,LotDigits(stp));
         if(lots<mn-0.0000001 || all-lots<mn-0.0000001){ skipped++; continue; }   // Haelfte ODER Rest unter Minimum -> unveraendert lassen
      }
      RefreshRates();
      double px=(ty==OP_BUY)?MarketInfo(sy,MODE_BID):MarketInfo(sy,MODE_ASK);
      if(OrderClose(tk,lots,px,InpSlippage,clrOrange))
      {
         closed++;
         Journal("PANEL_CLOSE",sy,(ty==OP_BUY?"BUY":"SELL"),lots,px,0,0,0,StringFormat("%s%s per Panel-Button (#%d)",half?"50%":"Voll",chartOnly?" · Chart":" · account",tk),tk);
         if(half && GlobalVariableCheck(OpnKey(tk)))   // Rest-Ticket unseres Trades registrieren -> Close-Erkennung findet auch ihn
         {
            // verify v0.40: prefer detection via the MT4 standard comment "from #<tk>"; fallback only on an
            //   EXACT match of time/price/magic/remaining lots (two simultaneous positions of the same
            //   second/price must never register the wrong ticket).
            double rem=all-lots; int found=-1;
            for(int r=OrdersTotal()-1;r>=0;r--)
            {
               if(!OrderSelect(r,SELECT_BY_POS,MODE_TRADES)) continue;
               if(OrderTicket()==tk || OrderSymbol()!=sy || OrderType()!=ty) continue;
               if(StringFind(OrderComment(),StringFormat("from #%d",tk))>=0){ found=OrderTicket(); break; }
               if(found<0 && OrderOpenTime()==ot && OrderMagicNumber()==mg
                  && MathAbs(OrderOpenPrice()-op)<=0.0000001 && MathAbs(OrderLots()-rem)<stp*0.5) found=OrderTicket();
            }
            if(found>0){ GlobalVariableSet(OpnKey(found),(double)SrvTime()); g_gvDirty=true; }
         }
      }
      else
      {
         failed++; int err=GetLastError();
         Journal("PANEL_CLOSE",sy,(ty==OP_BUY?"BUY":"SELL"),lots,px,0,0,0,StringFormat("FEHLGESCHLAGEN err=%d (#%d)",err,tk),tk);
      }
   }
   string msg=TF("close.result",IntegerToString(closed))+(half?" ("+T("close.halved")+")":"");
   if(skipped>0) msg=msg+StringFormat(", %d zu klein (Min-Lot)",skipped);
   if(failed>0)  msg=msg+StringFormat(", %d FEHLER (Journal)",failed);
   if(closed==0 && skipped==0 && failed==0) msg=T("close.none");
   Notify(msg, failed==0);
   g_panelSig="";
}

// v0.46: "RISK FREE" — pull the SL of all positions IN PROFIT to break-even (entry + optional buffer).
//   Pure risk REDUCTION: no rule is touched, so it also runs during lock/cooldown.
//   Reach: only positions the tool is responsible for (InScope OR registered panel ticket) — foreign
//   EAs stay untouched, because their logic may rely on their own SL.
//   Break-even is exactly OrderOpenPrice(): MT4 opens a BUY at the ask and closes at the bid (and vice versa),
//   so the spread is already inside the entry price. InpBreakEvenBufferPts additionally covers the commission.
void PanelBreakEven(bool chartOnly)
{
   if(IsTradeContextBusy()){ Notify(T("info.tradeContextBusy"),true); return; }
   int done=0, skipped=0, failed=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      if(chartOnly && OrderSymbol()!=Symbol()) continue;
      if(!InScope(OrderMagicNumber()) && !GlobalVariableCheck(OpnKey(OrderTicket()))) continue;
      string sy=OrderSymbol(); int tk=OrderTicket();
      double entry=OrderOpenPrice(), curSL=OrderStopLoss(), tp=OrderTakeProfit();
      int    dg=(int)MarketInfo(sy,MODE_DIGITS); if(dg<=0) dg=5;
      double pt=MarketInfo(sy,MODE_POINT); if(pt<=0) pt=Point;
      double buf=MathMax(0.0,InpBreakEvenBufferPts)*pt;
      double target=(ty==OP_BUY)? entry+buf : entry-buf;
      target=NormalizeDouble(target,dg);
      // already at/above break-even? -> nothing to do (never loosen the SL!)
      if(curSL>0 && ((ty==OP_BUY && curSL>=target-pt/2) || (ty==OP_SELL && curSL<=target+pt/2))) continue;
      RefreshRates();
      double cur=(ty==OP_BUY)?MarketInfo(sy,MODE_BID):MarketInfo(sy,MODE_ASK);
      if(cur<=0) continue;
      // only if really in profit
      if((ty==OP_BUY && cur<=target) || (ty==OP_SELL && cur>=target)){ skipped++; continue; }
      // respect the broker's minimum distance, otherwise the server rejects the modify (err 130)
      double stopLvl=MarketInfo(sy,MODE_STOPLEVEL)*pt;
      if(MathAbs(cur-target)<stopLvl){ skipped++; continue; }
      if(OrderModify(tk,entry,target,tp,0,clrDodgerBlue))
      {
         done++;
         Journal("BREAKEVEN",sy,(ty==OP_BUY?"BUY":"SELL"),OrderLots(),entry,target,tp,0,
                 StringFormat("SL auf Break-Even gezogen (#%d)",tk),tk);
      }
      else
      {
         failed++; int err=GetLastError();
         Journal("BREAKEVEN",sy,(ty==OP_BUY?"BUY":"SELL"),OrderLots(),entry,target,tp,0,
                 StringFormat("FEHLGESCHLAGEN err=%d (#%d)",err,tk),tk);
      }
   }
   string m=TF("riskfree.result",IntegerToString(done));
   if(skipped>0) m=m+StringFormat(", %d not yet in profit/too close",skipped);
   if(failed>0)  m=m+StringFormat(", %d FEHLER (Journal)",failed);
   if(done==0 && skipped==0 && failed==0) m=T("riskfree.none");
   Notify(m, failed==0);
   g_panelSig="";
}

// v0.44: make manual / foreign trades (not from the panel, outside the WatchScope) visible for the cockpit —
//   own event "CLOSE_MAN". They change NO rule (no loss streak, no cooldown, no daily budget):
//   the enforcement stays exactly as defined, the dashboard only marks them as "manual".
//   Window = today's server day (bounded); dedup via its own namespace RGM_ (RGP_ belongs to the rule path).
void ResolveManualHistory()
{
   datetime dayStart=ServerDayStart();
   if(dayStart<=0 || dayStart>SrvTime()) return;                    // v0.45: unplausible Zeitbasis -> nichts tun
   // v0.45 (verify): aggregation window WIDER than the reporting window. A partial close from yesterday belongs
   //   to the same position net as the remainder closed today — otherwise CLOSE_MAN reports only a partial amount.
   datetime scanFrom=dayStart-7*86400;
   string   gKey[]; string gSym[]; int gType[]; int gMagic[]; double gNet[]; double gLots[];
   datetime gMax[]; datetime gOpen[]; double gPrice[];
   int gN=0, tot=OrdersHistoryTotal();
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      // v0.45 (verify): cheap filters FIRST — GlobalVariableCheck is O(N_GV) and previously ran on every
      //   History-Zeile (bei "Gesamte Historie" alle 2s zehntausende Lookups -> Wine-Freeze-Risiko).
      datetime ct=OrderCloseTime(); if(ct<scanFrom) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      if(InScope(OrderMagicNumber())) continue;                     // Tool-Trades macht ResolveHistory
      if(GlobalVariableCheck(OpnKey(OrderTicket()))) continue;      // registrierte Panel-Tickets: Ticket-Pfad
      string key=ProcKey(OrderOpenTime(),ty,OrderSymbol(),OrderMagicNumber(),OrderOpenPrice());
      int gi=-1; for(int g=0;g<gN;g++) if(gKey[g]==key){ gi=g; break; }
      if(gi<0)
      {
         gi=gN;
         ArrayResize(gKey,gN+1); ArrayResize(gSym,gN+1); ArrayResize(gType,gN+1); ArrayResize(gMagic,gN+1);
         ArrayResize(gNet,gN+1); ArrayResize(gLots,gN+1); ArrayResize(gMax,gN+1); ArrayResize(gOpen,gN+1); ArrayResize(gPrice,gN+1);
         gKey[gi]=key; gSym[gi]=OrderSymbol(); gType[gi]=ty; gMagic[gi]=OrderMagicNumber();
         gNet[gi]=0; gLots[gi]=0; gMax[gi]=ct; gOpen[gi]=OrderOpenTime(); gPrice[gi]=OrderOpenPrice();
         gN++;
      }
      gNet[gi]+=OrderProfit()+OrderSwap()+OrderCommission();
      gLots[gi]+=OrderLots();
      if(ct>gMax[gi]) gMax[gi]=ct;
   }
   static bool s_manMarkerFail=false;
   for(int g2=0;g2<gN;g2++)
   {
      if(gMax[g2]<dayStart) continue;                                                          // older than today -> aggregation context only
      string mk=ManKey(gKey[g2]);
      if(GlobalVariableCheck(mk)) continue;                                                    // already shown/counted
      // v0.45 (verify): cross-check against the RULE path. Without it a trade that ResolveHistory
      //   had counted via the ticket registration (magic divergence/scope change) could additionally appear as
      //   CLOSE_MAN -> double net in the dashboard.
      string kleg=ProcKeyLegacy(gOpen[g2],gType[g2],gSym[g2],gMagic[g2],gPrice[g2]);
      if(IsProcessedAny(gKey[g2],kleg)){ GlobalVariableSet(mk,(double)gMax[g2]); g_gvDirty=true; continue; }
      if(HasOpenRemainder(gOpen[g2],gSym[g2],gType[g2],gMagic[g2],gPrice[g2])) continue;        // partial close: only once fully closed
      // v0.45 (verify): set the marker BEFORE the journal and check success — if creating the GV fails
      //   (name length/GV limit), the same line would otherwise be rewritten every 2s (journal flood).
      if(!GlobalVariableSet(mk,(double)gMax[g2]))
      {
         if(!s_manMarkerFail)
         { s_manMarkerFail=true;
           Journal("INFO","-","-",0,0,0,0,0,StringFormat("CLOSE_MAN-Marker nicht persistierbar (err=%d) — manuelle Trades werden NICHT angezeigt",GetLastError())); }
         continue;
      }
      g_gvDirty=true;
      Journal("CLOSE_MAN",gSym[g2],(gType[g2]==OP_BUY?"BUY":"SELL"),gLots[g2],gPrice[g2],0,0,0,
              StringFormat("Manual/foreign trade (Magic %d) — outside the tool rules, display only",gMagic[g2]),0,gNet[g2]);
   }
}

// v0.40: Sicherheitsnetz — verarbeitet VOLL geschlossene, registrierte Panel-Tickets per SELECT_BY_TICKET
//   (independent of the history tab's period filter and of the GV_LAST_CLOSE floor). Same dedup keys as
//   ResolveHistory -> nie doppelt gezaehlt.
// v0.40-fix (Verify): GRUPPEN-AGGREGATION — alle registrierten Legs derselben Position (gleicher ProcKey,
//   e.g. after a panel 50% close) are counted TOGETHER. Previously the fallback counted only the first
//   iterated leg and AddProcessed swallowed the P/L of the siblings (laundering window: profit leg
//   first -> series reset despite a net loss). The registry is frozen up front (new GVs created by
//   ApplyResult would otherwise shift the iteration); keys of open positions are refreshed (4-week expiry).
void ResolveByTicketRegistry()
{
   // Phase 1: Registry einfrieren
   int regT[]; int nReg=0;
   for(int g=GlobalVariablesTotal()-1; g>=0; g--)
   {
      string n=GlobalVariableName(g);
      if(StringFind(n,"RGOPN_")!=0) continue;
      int t=(int)StringToInteger(StringSubstr(n,6));
      if(t<=0){ GlobalVariableDel(n); continue; }
      ArrayResize(regT,nReg+1); regT[nReg]=t; nReg++;
   }
   // v0.41/v0.45: diagnostics go to the journal only on a REAL anomaly (unresolvable tickets), otherwise a log print.
   //   Before, the 60s cycle wrote INFO lines nonstop and pushed real events out of the cockpit list.
   static uint s_diagMs=0;
   if(nReg==0) return;
   if(GetTickCount()-s_diagMs>=60000)
   {
      s_diagMs=GetTickCount();
      int unres=0; for(int d=0; d<nReg; d++) if(!OrderSelect(regT[d],SELECT_BY_TICKET)) unres++;
      if(unres>0) Journal("INFO","-","-",0,0,0,0,0,StringFormat("Registry-Diag: %d vorgemerkt, %d NICHT aufloesbar (History-Cache pruefen), HistTotal=%d",nReg,unres,OrdersHistoryTotal()));
      else        PrintFormat("Mamal registry diag: %d pending, all resolvable, HistTotal=%d",nReg,OrdersHistoryTotal());
   }
   bool done[]; ArrayResize(done,nReg); ArrayInitialize(done,false);

   for(int i=0;i<nReg;i++)
   {
      if(done[i]) continue;
      int tk=regT[i];
      if(!OrderSelect(tk,SELECT_BY_TICKET))
      {
         // Not resolvable (history purged / tab cache?): surface it once per hour, keep the key.
         double reg=GlobalVariableGet(OpnKey(tk));
         if(reg>0 && SrvTime()-(datetime)reg>3600)
         { GlobalVariableSet(OpnKey(tk),(double)SrvTime()); g_gvDirty=true;
           Journal("INFO","-","-",0,0,0,0,0,StringFormat("Ticket-Registry: #%d seit >1h nicht aufloesbar — bleibt vorgemerkt (History-Cache pruefen)",tk)); }
         continue;
      }
      if(OrderCloseTime()==0)
      { GlobalVariableSet(OpnKey(tk),GlobalVariableGet(OpnKey(tk))); continue; }   // open -> refresh the key (only here: orphans still expire after 4 weeks)
      int ty=OrderType();
      if(ty!=OP_BUY && ty!=OP_SELL){ GlobalVariableDel(OpnKey(tk)); done[i]=true; continue; }
      datetime ot=OrderOpenTime(); string sy=OrderSymbol(); int mg=OrderMagicNumber(); double op=OrderOpenPrice();
      string key   =ProcKey      (ot,ty,sy,mg,op);
      string keyLeg=ProcKeyLegacy(ot,ty,sy,mg,op);
      if(IsProcessedAny(key,keyLeg)){ GlobalVariableDel(OpnKey(tk)); done[i]=true; continue; }   // Gruppen-Pfad war schneller
      if(HasOpenRemainder(ot,sy,ty,mg,op)) continue;   // remainder (even an unregistered one) still open -> later
      // Collect and aggregate all registered sibling legs of the same position
      double manNet=0, eaNet=0; bool hasMan=false, eaFault=false, defer=false;
      datetime maxCt=0; int grp[]; int nG=0;
      for(int j=i;j<nReg;j++)
      {
         if(done[j]) continue;
         if(!OrderSelect(regT[j],SELECT_BY_TICKET)) continue;
         if(OrderOpenTime()!=ot || OrderType()!=ty || OrderSymbol()!=sy) continue;
         if(OrderMagicNumber()!=mg || MathAbs(OrderOpenPrice()-op)>0.0000001) continue;
         if(OrderCloseTime()==0){ defer=true; break; }   // registered sibling still open -> whole group later
         double lnet=OrderProfit()+OrderSwap()+OrderCommission();
         if(GlobalVariableCheck(EaKey(OrderTicket()))){ eaNet+=lnet; if(GlobalVariableCheck(EacfKey(OrderTicket()))) eaFault=true; }
         else                                         { manNet+=lnet; hasMan=true; }
         if(OrderCloseTime()>maxCt) maxCt=OrderCloseTime();
         ArrayResize(grp,nG+1); grp[nG]=j; nG++;
      }
      if(defer || nG==0) continue;
      // v0.65b: pick the same ticket as the group path (smallest = entry). Otherwise the same trade
      //   is journaled with a different ticket per resolution path and the trade record loses it.
      for(int k3=0;k3<nG;k3++) if(regT[grp[k3]]<tk) tk=regT[grp[k3]];
      bool sameDay=(DayKeyOf(maxCt-EffResetHour()*3600)==(long)ServerDayKey());
      double tot=manNet+eaNet;
      if(!sameDay)      Journal("CLOSE",sy,"-",0,0,0,0,0,"Close aus vorherigem Servertag — zaehlt nicht fuer die heutige Serie, net "+DoubleToString(tot,2),tk,tot);
      else if(hasMan)   ApplyResult(manNet,tk,sy,ty);   // like the group path: the trader's share counts for the series
      else if(eaFault)  ApplyResult(eaNet, tk,sy,ty);
      else              Journal("CLOSE",sy,"-",0,0,0,0,0,"EA-Schutz-Close (zaehlt nicht fuer die Serie), net "+DoubleToString(tot,2),tk,tot);
      Shot("close",tk);                                              // v0.47: exit snapshot for the before/after comparison
      GlobalVariableDel(SlSeenKey(tk)); GlobalVariableDel(TpSeenKey(tk));   // v0.47: clean up the tracking marker of the closed ticket
      AddProcessed(key,maxCt);
      for(int k2=0;k2<nG;k2++){ GlobalVariableDel(OpnKey(regT[grp[k2]])); done[grp[k2]]=true; }
      g_gvDirty=true;
   }
}

//--- R5/R6/R19/R25: history-based, idempotent loss resolution (P0-2/P0-4) ---
// v0.65: plain-text reason for the lock. Empty if nothing was stored (lock from an older version
//   or restored from the lockstate file) — then the neutral wording stands.
string LockWhyText()
{
   if(!GlobalVariableCheck(GV_LOCK_WHY)) return "";
   int w=(int)GlobalVariableGet(GV_LOCK_WHY);
   if(w==1) return T("why.r4");
   if(w==2) return T("why.r6");
   if(w==3) return T("why.r13");
   if(w==4) return T("why.self");
   if(w==5) return T("why.history");
   if(w==6) return T("why.tamper");
   if(w==7) return T("why.test");
   if(w==8) return T("why.maxloss");
   if(w==9) return T("why.week");
   return "";
}
// v0.65: one-off backfill from the account history. Writes JOURNAL LINES ONLY —
//   no rule evaluation, no touching of loss series, daily budget, locks or dedup markers.
//   The event is deliberately named CLOSE_HIST and not CLOSE: calendar and statistics only count "CLOSE",
//   otherwise every backfilled trade would count into the net a second time.
//   Limit the user must know: OrdersHistoryTotal() only sees what the history tab shows.
//   If a time filter is set there, only that slice gets backfilled.
void BackfillHistory()
{
   if(!InpHistoryBackfill) return;
   if(GlobalVariableCheck(GV_BACKFILL) && (long)GlobalVariableGet(GV_BACKFILL)==(long)AccountNumber()) return;
   int tot=OrdersHistoryTotal();
   if(tot<=0) return;   // History not loaded yet -> next cycle. Do NOT set the guard.
   int cnt=0, skipType=0, skipScope=0, seenMagic=-1; double sum=0;
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int ty=OrderType();
      if(ty!=OP_BUY && ty!=OP_SELL){ skipType++; continue; }   // Ein-/Auszahlungen
      int mg=OrderMagicNumber(); if(seenMagic<0) seenMagic=mg;
      if(!InScope(mg)){ skipScope++; continue; }               // foreign magics have no trade record
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      Journal("CLOSE_HIST",OrderSymbol(),(ty==OP_BUY?"BUY":"SELL"),OrderLots(),OrderOpenPrice(),
              OrderStopLoss(),OrderTakeProfit(),0,
              "Backfilled from account history (closed "+TimeToString(OrderCloseTime())+"), net "+DoubleToString(net,2),
              OrderTicket(),net);
      cnt++; sum+=net;
   }
   // ALWAYS log, even with 0 hits — otherwise there is no telling afterwards whether the
   //   backfill ran at all and what it failed on (exactly this case occurred).
   Journal("INFO","-","-",0,0,0,0,0,StringFormat(
      "Backfill: %d backfilled (sum %.2f) | history=%d, skipped: %d no trade, %d out of range | InpMagic=%d, first magic in history=%d, Scope=%d",
      cnt,sum,tot,skipType,skipScope,InpMagic,seenMagic,(int)InpWatchScope));
   if(cnt>0)
   { GlobalVariableSet(GV_BACKFILL,(double)AccountNumber()); GlobalVariablesFlush();
     Notify(TF("backfill.done",IntegerToString(cnt),DoubleToString(sum,2)),false,true); }
   else Notify(TF("backfill.empty",IntegerToString(tot),IntegerToString(skipScope)),false,true);
}
void ClearLockWhy(){ if(GlobalVariableCheck(GV_LOCK_WHY)) GlobalVariableSet(GV_LOCK_WHY,0); }   // v0.65
void ApplyResult(double net,int ticket,string sym,int type)
{
   if(net<0)
   {
      SetRevenge(sym,type);
      double c=GlobalVariableGet(GV_CONSEC)+1; GlobalVariableSet(GV_CONSEC,c);
      Journal("CLOSE",sym,(type==OP_BUY?"BUY":"SELL"),0,0,0,0,0,StringFormat("Verlust net %.2f (Serie %d) #%d",net,(int)c,ticket),ticket,net);
      if(c>=EffLockAfter()){ GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,2); g_gvDirty=true; Notify(TF("lock.dayLockStreak",IntegerToString((int)c))); }
      else if(c>=EffCooldownAfter()){ GlobalVariableSet(GV_COOLDOWN,(double)(SrvTime()+EffCooldownMin()*60)); g_gvDirty=true; Notify(TF("lock.cooldownStreak",IntegerToString((int)c),IntegerToString(EffCooldownMin()))); }
   }
   else   // L4: net>=0 (Gewinn ODER Break-even) -> Verlustserie zuruecksetzen
   {
      GlobalVariableSet(GV_CONSEC,0);
      Journal("CLOSE",sym,(type==OP_BUY?"BUY":"SELL"),0,0,0,0,0,StringFormat("%s net %.2f (Serie reset) #%d",(net>0?"Gewinn":"Break-even"),net,ticket),ticket,net);
   }
}
bool HasOpenRemainder(datetime openTime,string sym,int type,int magic,double openPrice)   // P0-4 Teil-Schliessung (identisch zu ProcKey)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()!=type || OrderSymbol()!=sym) continue;
      if(OrderMagicNumber()!=magic) continue;
      if(OrderOpenTime()!=openTime) continue;
      if(MathAbs(OrderOpenPrice()-openPrice) > 0.0000001) continue;
      return true;
   }
   return false;
}
void ResolveHistory()
{
   datetime floor=(datetime)GlobalVariableGet(GV_LAST_CLOSE);
   // v0.41-fix: catch a FUTURE floor. If GV_LAST_CLOSE was ever seeded with a broken server offset
   //   (first attach during a tickless phase), the anchor sat in the future -> ct<floor skipped EVERY
   //   close forever (0 CLOSE lines since day 1). Self-healing: reset to the start of the day.
   if(floor>SrvTime()+60)
   {
      Journal("INFO","-","-",0,0,0,0,0,StringFormat("GV_LAST_CLOSE lag in der ZUKUNFT (%s) -> zurueckgesetzt auf Tagesbeginn (Close-Wertung war dadurch blockiert)",TimeToString(floor)));
      floor=ServerDayStart(); GlobalVariableSet(GV_LAST_CLOSE,(double)floor); g_gvDirty=true;
   }
   // Group history by POSITION (key=OpenTime_Type_Symbol) -> partial closes are aggregated into ONE result
   string   gKey[]; string gKeyLeg[]; datetime gOpen[]; string gSym[]; int gType[]; datetime gMin[]; datetime gMax[]; double gNet[]; double gEaNet[]; double gManNet[]; bool gHasMan[]; bool gEaFault[]; double gPrice[]; int gMagic[]; int gTick[];   // B4/6 (+§05 gEaFault, +§07 gKeyLeg for the key migration, +v0.65 gTick)
   // v0.65: gTick = smallest ticket of the group. Up to v0.64 this path wrote the CLOSE line with ticket 0 —
   //   so the trade record could NEVER match a close to its entry and showed every trade as
   //   "offen" (open), without a result and with a summary claiming "noch nicht verbucht" (not booked yet) forever.
   int gN=0, tot=OrdersHistoryTotal();
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      // v0.40-fix: ALWAYS process registered panel tickets — if the master instance runs with a different
      //   InpMagic (input changed / chart divergence), our own trades would otherwise drop out of the evaluation
      //   (exactly how the CLOSE entries got lost: master had InpMagic=0, trades had magic 990201).
      if(!InScope(OrderMagicNumber()) && !GlobalVariableCheck(OpnKey(OrderTicket()))) continue;
      datetime ct=OrderCloseTime(); if(ct<floor) continue;
      string key=ProcKey(OrderOpenTime(),ty,OrderSymbol(),OrderMagicNumber(),OrderOpenPrice());
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      bool   ea =GlobalVariableCheck(EaKey(OrderTicket()));
      bool   fault=GlobalVariableCheck(EacfKey(OrderTicket()));   // §05-fix: EA-Close war Trader-Verschulden (R7/R1/R8)
      int gi=-1; for(int g=0;g<gN;g++) if(gKey[g]==key){ gi=g; break; }
      if(gi<0)
      {
         gi=gN; ArrayResize(gKey,gN+1);ArrayResize(gKeyLeg,gN+1);ArrayResize(gOpen,gN+1);ArrayResize(gSym,gN+1);ArrayResize(gType,gN+1);
         ArrayResize(gMin,gN+1);ArrayResize(gMax,gN+1);ArrayResize(gNet,gN+1);ArrayResize(gEaNet,gN+1);ArrayResize(gManNet,gN+1);ArrayResize(gHasMan,gN+1);ArrayResize(gEaFault,gN+1);ArrayResize(gPrice,gN+1);ArrayResize(gMagic,gN+1);ArrayResize(gTick,gN+1);
         gKey[gi]=key; gKeyLeg[gi]=ProcKeyLegacy(OrderOpenTime(),ty,OrderSymbol(),OrderMagicNumber(),OrderOpenPrice());
         gOpen[gi]=OrderOpenTime(); gSym[gi]=OrderSymbol(); gType[gi]=ty;
         gPrice[gi]=OrderOpenPrice(); gMagic[gi]=OrderMagicNumber();
         gTick[gi]=OrderTicket();   // v0.65: entry ticket of the group
         gMin[gi]=ct; gMax[gi]=ct; gNet[gi]=0; gEaNet[gi]=0; gManNet[gi]=0; gHasMan[gi]=false; gEaFault[gi]=false; gN++;
      }
      gNet[gi]+=net; if(ct<gMin[gi]) gMin[gi]=ct; if(ct>gMax[gi]) gMax[gi]=ct;
      if(OrderTicket()<gTick[gi]) gTick[gi]=OrderTicket();   // v0.65: smallest = the original entry ticket
      if(ea){ gEaNet[gi]+=net; if(fault) gEaFault[gi]=true; } else { gManNet[gi]+=net; gHasMan[gi]=true; }   // B4/6: EA- vs Trader-Anteil getrennt (+§05-fix: Fault-EA-Close markieren)
   }
   if(gN==0) return;
   // P1: evaluate groups chronologically by close time (gMax) ascending -> loss series/cooldown in real order (broker history is not guaranteed to be sorted)
   int ord[]; ArrayResize(ord,gN); for(int a=0;a<gN;a++) ord[a]=a;
   for(int a=1;a<gN;a++){ int kk=ord[a]; int b=a-1; while(b>=0 && gMax[ord[b]]>gMax[kk]){ ord[b+1]=ord[b]; b--; } ord[b+1]=kk; }
   datetime earliestDeferred=0; bool haveDeferred=false; datetime maxProcessed=floor;
   for(int oi=0;oi<gN;oi++)
   {
      int g=ord[oi];
      // Partial close: as long as a remaining ticket of this position is open -> do NOT evaluate (skip only this group)
      if(HasOpenRemainder(gOpen[g],gSym[g],gType[g],gMagic[g],gPrice[g]))
      {
         // §06-fix (medium): cap the deferral in time. A 0.01-lot remainder could hold up the loss evaluation (R5/R6/R25) INDEFINITELY
         //   although the loss is long since realized ("close 0.99 of 1.0 lot, leave the rest open").
         //   After 10 min an already realized LOSS is evaluated — losses only, so that a realized partial profit
         //   does not reset the series prematurely if the remainder still turns negative.
         double effNet = gHasMan[g] ? gManNet[g] : (gEaFault[g] ? gEaNet[g] : 0);
         bool   stale  = (SrvTime()-gMax[g] >= 600);
         if(!(stale && effNet<0 && !IsProcessedAny(gKey[g],gKeyLeg[g])))
         { if(!haveDeferred || gMin[g]<earliestDeferred){ earliestDeferred=gMin[g]; haveDeferred=true; } continue; }
         Journal("CLOSE",gSym[g],"-",0,0,0,0,0,"Teil-Close: realisierter Verlust nach 10 min gewertet (Rest noch offen), net "+DoubleToString(effNet,2),gTick[g],effNet);
      }
      if(IsProcessedAny(gKey[g],gKeyLeg[g])) continue;          // already evaluated (idempotent, incl. legacy markers)
      // B4/6: if there was a trader-close share -> it counts for series/cooldown/revenge.
      // §05-fix (hoch): auch ein reiner EA-Close mit TRADER-VERSCHULDEN (R7 SL entfernt / R1 Ueberrisiko / R8) zaehlt —
      //   otherwise "remove the SL and let the EA close it" launders the loss series. ONLY genuine protective flats
      //   (Lock-SafeCloseAll / R12) stay excluded (not the trader's fault).
      // §07-fix: losses of a PAST server day no longer count into the new day's series (RollNewDay has
      //   already zeroed CONSEC) — otherwise the new day started with inherited losses and cooldown/lock fired too early.
      bool sameDay = (DayKeyOf(gMax[g]-EffResetHour()*3600) == (long)ServerDayKey());
      if(!sameDay)         Journal("CLOSE",gSym[g],"-",0,0,0,0,0,"Close aus vorherigem Servertag — zaehlt nicht fuer die heutige Serie, net "+DoubleToString(gNet[g],2),gTick[g],gNet[g]);
      else if(gHasMan[g])  ApplyResult(gManNet[g],gTick[g],gSym[g],gType[g]);
      else if(gEaFault[g]) ApplyResult(gEaNet[g], gTick[g],gSym[g],gType[g]);
      else                 Journal("CLOSE",gSym[g],"-",0,0,0,0,0,"EA-Schutz-Close (zaehlt nicht fuer die Serie), net "+DoubleToString(gEaNet[g],2),gTick[g],gEaNet[g]);   // P0-3
      AddProcessed(gKey[g],gMax[g]);
      if(gMax[g]>maxProcessed) maxProcessed=gMax[g];
   }
   // Set the floor safely: never beyond a still-open (deferred) close -> stays scannable later
   datetime newFloor = haveDeferred ? (earliestDeferred>1?earliestDeferred-1:floor) : maxProcessed;
   if(newFloor<floor) newFloor=floor;
   GlobalVariableSet(GV_LAST_CLOSE,(double)newFloor);
   // v0.22: do NOT run the three O(N_GlobalVariables) sweeps on every close (Wine freeze protection) — pure cleanup housekeeping, 60s is enough
   static uint s_lastPruneMs=0;
   if(GetTickCount()-s_lastPruneMs >= 60000)
   {
      s_lastPruneMs=GetTickCount();
      // v0.43-fix (CRITICAL): 6h grace period. Previously the dedup markers were pruned IMMEDIATELY along with the floor
      //   (only the very last one survived). For ResolveHistory that was fine (the floor itself protects), but
      //   the ticket fallback checks exactly those markers -> it found none and evaluated EVERYTHING a second time
      //   (duplicate CLOSE lines, duplicated loss series, duplicated net in the calendar).
      PruneGV("RGP_",   newFloor-21600);           // forget processed positions only after 6h (dedup for both paths)
      PruneGV("RGM_",   SrvTime()-2*86400);        // v0.45: "shown in cockpit" markers only after 2 days (here in the 60s block, not every 2s)
      PruneShots();                                // v0.47: alte Screenshots loeschen (InpShotKeepDays)
      PruneGV("RGEACF_",SrvTime()-2*86400);     // §05-fix: prune fault markers BEFORE RGEAC_ (RGEAC_ is not a prefix of RGEACF_, but the order does not matter)
      PruneGV("RGEAC_", SrvTime()-2*86400);     // alte EA-Close-Marker aufraeumen
      PruneRevenge();                              // R25: abgelaufene Revenge-Fenster (v0.17)
      PruneNaked();                                // §06-fix: R7 grace markers of closed tickets (O(N_GV) -> only here, not per enforcement cycle)
   }
   g_gvDirty=true;                                 // v0.22: flush batched at the end of the cycle (not synchronously here in the close tick)
}

//--- R7: naked = without SL/TP. Deadline from OrderOpenTime (restart-safe, no in-memory state) ----------

//--- Close-Queue: ticketbasiert, Retry-Limit, Backoff, Error-Codes, Journal je Versuch ---
int  QFind(int ticket){ for(int i=0;i<ArraySize(g_qTicket);i++) if(g_qTicket[i]==ticket) return i; return -1; }
void QRemoveAt(int idx)
{
   int n=ArraySize(g_qTicket);
   for(int i=idx;i<n-1;i++){ g_qTicket[i]=g_qTicket[i+1]; g_qReason[i]=g_qReason[i+1]; g_qTries[i]=g_qTries[i+1]; g_qNextMs[i]=g_qNextMs[i+1]; }
   ArrayResize(g_qTicket,n-1); ArrayResize(g_qReason,n-1); ArrayResize(g_qTries,n-1); ArrayResize(g_qNextMs,n-1);
}
void RequestClose(int ticket,string reason)   // Lots are read live from OrderLots() at close time (partial-close safe)
{
   if(QFind(ticket)>=0) return;            // already queued -> no double close
   int n=ArraySize(g_qTicket);
   ArrayResize(g_qTicket,n+1); ArrayResize(g_qReason,n+1); ArrayResize(g_qTries,n+1); ArrayResize(g_qNextMs,n+1);
   g_qTicket[n]=ticket; g_qReason[n]=reason; g_qTries[n]=0; g_qNextMs[n]=GetTickCount();
}
bool IsRetryableClose(int err)
{
   switch(err)
   {  // transiente Fehler -> kurzer Backoff, erneut versuchen
      case 4:   case 6:   case 8:   case 128: case 129:   // 132=ERR_MARKET_CLOSED is handled separately in ProcessCloseQueue (long backoff)
      case 135: case 136: case 137: case 138: case 146: return true;
   }
   return false;   // otherwise: hard backoff, faster towards FINAL-FAIL
}
uint CloseBackoffMs(int tries)
{
   double ms=(double)InpCloseBackoffMs*MathPow(2.0,(double)(tries-1));
   if(ms>(double)InpCloseMaxBackoffMs) ms=(double)InpCloseMaxBackoffMs;
   if(ms<1) ms=1;
   return (uint)ms;
}
// v0.31: signature of the in-scope positions (ticket + SL + TP) -> a change with the SAME count = the user modified SL/TP.
double OrderScopeSig(int &cnt)
{
   cnt=0; double s=0.0; int n=OrdersTotal();
   for(int i=0;i<n;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;
      cnt++; s += (double)OrderTicket()*3.0 + OrderStopLoss()*7.0 + OrderTakeProfit()*11.0;
   }
   return s;
}
// §06-fix (medium): between enqueue and the actual close there can be seconds up to (with err=132, market closed) hours.
//   So far the queue only checked "exists/open", never whether the REASON still holds: a position healed meanwhile
//   (SL/TP added, risk reduced), or a position after an expired lock, was force-closed anyway
//   (slippage cost without a rule reason). Now the reason is re-validated immediately before the close.
bool CloseReasonStillValid(int ticket,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return false;
   if(OrderCloseTime()!=0) return false;
   int ty=OrderType();
   if(StringFind(reason,"R22")==0) return (InpCloseManualTrades && OrderMagicNumber()==0);   // R22 stays valid as long as the order is manual and the rule is active
   if(StringFind(reason,"Lock")==0) return IsLocked();               // lock expired in the meantime (e.g. across midnight)?
   if(ty!=OP_BUY && ty!=OP_SELL) return true;                        // pending: deleting costs nothing -> no further checks
   if(StringFind(reason,"R7")==0)
      return ((EffRequireSL() && OrderStopLoss()==0.0) || (EffRequireTP() && OrderTakeProfit()==0.0));
   if(StringFind(reason,"R1 ")==0)
   { double sl=OrderStopLoss(); if(sl==0.0) return false;
     return (RiskPctOfBase(OrderSymbol(),OrderLots(),OrderOpenPrice(),sl,DayRiskBase()) > EffRiskPct()*InpRiskTolFactor); }
   if(StringFind(reason,"R8")==0)
   { double sl=OrderStopLoss(), tp=OrderTakeProfit(); if(sl==0.0 || tp==0.0) return false;
     double rk=MathAbs(OrderOpenPrice()-sl), rw=MathAbs(tp-OrderOpenPrice()); if(rk<=0) return false;
     return ((rw/rk) < InpMinRR-0.01); }
   if(StringFind(reason,"R12")==0) return (TotalOpenRiskPct() > EffHeat()*InpRiskTolFactor);
   if(StringFind(reason,"R2 idea")==0) return (IdeaOpenRiskPct(OrderSymbol(),(ty==OP_BUY)) > EffIdeaCap()*InpRiskTolFactor);
   if(StringFind(reason,"R5 Cooldown-Entry")==0) return CooldownActive();
   if(StringFind(reason,"R16 Off-Session")==0)   return OffSessionAt(OrderOpenTime());
   if(StringFind(reason,"R25 Revenge")==0)       return RevengeBlocked(OrderSymbol(),(ty==OP_BUY));
   return true;
}
void ProcessCloseQueue()
{
   if(ArraySize(g_qTicket)==0) return;
   if(IsTradeContextBusy())   return;
   uint nowMs=GetTickCount();
   for(int i=ArraySize(g_qTicket)-1;i>=0;i--)
   {
      if((int)(nowMs - g_qNextMs[i]) < 0) continue;                          // Backoff laeuft (B17: wrap-sicher)
      int ticket=g_qTicket[i];
      if(!OrderSelect(ticket,SELECT_BY_TICKET)){ QRemoveAt(i); continue; }   // weg/ungueltig
      if(OrderCloseTime()!=0){ QRemoveAt(i); continue; }                     // already closed (not by us)
      int    tp =OrderType();
      string sym=OrderSymbol();
      // Re-validate the reason — BEFORE both branches. Previously the check sat behind the pending branch, so a queued
      // pending order was still deleted even when the reason had gone away in the meantime (e.g. lock
      // expired or InpCloseManualTrades switched off meanwhile).
      if(!CloseReasonStillValid(ticket,g_qReason[i]))
      { Journal("CLOSE",sym,"-",0,0,0,0,0,"Queue verworfen — Grund entfallen: "+g_qReason[i],ticket); QRemoveAt(i); continue; }
      if(!OrderSelect(ticket,SELECT_BY_TICKET)){ QRemoveAt(i); continue; }   // restore the order selection after the check
      if(tp!=OP_BUY && tp!=OP_SELL)                                          // Pending -> loeschen
      {
         if(IsTradeContextBusy()) return;   // v0.31: re-check the context JUST before OrderDelete -> not into an ongoing user modify (= Wine crash)
         if(OrderDelete(ticket)){ Journal("CLOSE",sym,"-",0,0,0,0,0,"Queue DELETE ok: "+g_qReason[i]); QRemoveAt(i); }
         else
         {
            int derr=GetLastError(); g_qTries[i]++; g_qNextMs[i]=nowMs+CloseBackoffMs(g_qTries[i]);
            if(g_qTries[i]>=InpCloseRetries){ Journal("CLOSE",sym,"-",0,0,0,0,0,StringFormat("Queue DELETE FINAL-FAIL err=%d: %s",derr,g_qReason[i])); QRemoveAt(i); }
            else                              Journal("CLOSE",sym,"-",0,0,0,0,0,StringFormat("Queue DELETE RETRY %d err=%d: %s",g_qTries[i],derr,g_qReason[i]));
         }
         continue;
      }
      RefreshRates();   // (the reason re-validation happened above, before the pending branch)
      double lots =OrderLots();
      double price=(tp==OP_BUY) ? MarketInfo(sym,MODE_BID) : MarketInfo(sym,MODE_ASK);
      if(IsTradeContextBusy()) return;   // v0.31: re-check the context IMMEDIATELY before OrderClose -> no closing into an ongoing user modify (= Wine crash, root cause)
      if(OrderClose(ticket,lots,price,InpSlippage,clrRed))
      {
         MarkEaClosed(ticket,g_qReason[i]);                                  // B5/B8: set the marker ONLY after a confirmed close (+ §05-fix: fault reason for the loss series)
         Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue OK (Versuch %d): %s",g_qTries[i]+1,g_qReason[i]),ticket);
         QRemoveAt(i);
      }
      else
      {
         int  err  =GetLastError();
         if(OrderSelect(ticket,SELECT_BY_TICKET) && OrderCloseTime()!=0)     // B5: returned false, but closed on the server side ANYWAY (requote/timeout)
         {
            MarkEaClosed(ticket,g_qReason[i]);
            Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue OK (nach false-Rueckgabe err=%d): %s",err,g_qReason[i]),ticket);
            QRemoveAt(i);
         }
         else if(err==132)                                                  // P1: ERR_MARKET_CLOSED -> long backoff, do NOT escalate (no request storm over the weekend)
         {
            g_qNextMs[i] = nowMs + 900000;   // wait 15 min, the ticket stays in the queue
            Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue WAIT Markt geschlossen (err=132, 15min Backoff): %s",g_qReason[i]));
         }
         else                                                               // real failed attempt -> backoff/retry, NO marker
         {
            bool retry=IsRetryableClose(err);
            g_qTries[i] += (retry ? 1 : 2);
            g_qNextMs[i] = nowMs + (retry ? CloseBackoffMs(g_qTries[i]) : (uint)InpCloseMaxBackoffMs);
            if(g_qTries[i]>=InpCloseRetries)
            { Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue FINAL-FAIL err=%d nach %d Versuchen (%s): %s",err,g_qTries[i],retry?"transient":"hart",g_qReason[i])); QRemoveAt(i); }
            else
              Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue RETRY %d err=%d (%s): %s",g_qTries[i],err,retry?"transient":"hart",g_qReason[i]));
         }
      }
   }
}

//--- Lockstate-Datei: GV-Spiegel mit HMAC-light, fail-closed bei Beschaedigung ---
uint LsHash(string s)   // salted djb2 variant (HMAC-light, not real crypto)
{
   string d=LOCKSALT+s+LOCKSALT;
   uint h=5381;
   int  n=StringLen(d);
   for(int i=0;i<n;i++) h=((h<<5)+h) + (uint)StringGetCharacter(d,i);
   return h;
}
string LsPayload()
{
   long lu = GlobalVariableCheck(GV_LOCK_UNTIL) ? (long)GlobalVariableGet(GV_LOCK_UNTIL) : 0;
   long wl = GlobalVariableCheck(GV_WEEK_LOCK)  ? (long)GlobalVariableGet(GV_WEEK_LOCK)  : -1;
   long cd = GlobalVariableCheck(GV_COOLDOWN)   ? (long)GlobalVariableGet(GV_COOLDOWN)   : 0;
   return IntegerToString((int)ServerDayKey())+";"+
          IntegerToString(IsHardLocked()?1:0)+";"+
          IntegerToString((int)lu)+";"+
          IntegerToString((int)wl)+";"+
          IntegerToString(TargetHit()?1:0)+";"+
          IntegerToString((int)cd)+";"+
          DoubleToString(GlobalVariableGet(GV_DAY_RISK),4)+";"+
          IntegerToString((int)GlobalVariableGet(GV_CONSEC))+";"+
          DoubleToString(g_initBalConfirmed ? g_initialBalance : 0,2);   // §04-fix (medium): R4b base in the file — survives the 4-week GV expiry (field 9, appended at the end = old 8-field files stay readable). CONFIRMED base ONLY — otherwise the auto base would become the "confirmed" one via the file
}
// §04-fix (medium): stored R4b base from the (signed) lockstate file — for the OnInit cascade,
// when the GlobalVariables have expired after a >4-week pause and InpInitialBalance is not set.
double LsStoredInitBal()
{
   string payload; if(!ReadLockstateRaw(payload) || payload=="CORRUPT") return 0;
   string p[]; int k=StringSplit(payload,(ushort)';',p);
   if(k>=9) return StringToDouble(p[8]);
   return 0;
}
void WriteLockstate()
{
   string payload=LsPayload();
   string line="MMTLS1;"+payload+";"+IntegerToString((long)LsHash(payload));
   if(line==g_lockSig) return;            // unchanged -> no disk write
   // v0.63-FIX (fail-open, found in testing): this mirror ran EVERY cycle (~1s), the reconciliation
   //   ReconcileLockstate only every 5s. Whoever deleted RG_HARD_LOCK via F3 saw the lock vanish within a
   //   second from the signed file TOO — the mirror overtook the watchdog and
   //   deleted exactly the piece of evidence the lock was supposed to be restored from.
   //   Now: before a CHANGED state goes to disk, it is reconciled against the file.
   //   A lock still ACTIVE there moves back into the GVs beforehand (ReconcileLockstate writes on its own).
   //   NO IsTradeContextBusy gate here (verify finding against the first version of this fix): this mirror is
   //   the crash-safe persistence INDEPENDENT of the GV flush. On a busy trade context PersistLatch() skips
   //   the flush and relies on the .dat being written anyway. Had this been gated
   //   hier ebenfalls gegatet, schwiegen bei R4b-Ausloesung waehrend einer Close-Queue-Retry BEIDE Schichten
   //   at the same time — a crash in that window would have lost the hard lock. The extra read access
   //   is to the same tiny file that gets written here anyway.
   if(!g_lsGuard)
   {
      g_lsGuard=true; ReconcileLockstate(true); g_lsGuard=false;
      payload=LsPayload();               // the reconciliation may have restored locks
      line="MMTLS1;"+payload+";"+IntegerToString((long)LsHash(payload));
      if(line==g_lockSig) return;        // ReconcileLockstate has already written
   }
   int h=FileOpen(LOCKFILE,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE){ PrintFormat("Mamal: Lockstate-Schreibfehler %d",GetLastError()); return; }
   FileWriteString(h,line+"\r\n");
   FileClose(h);
   g_lockSig=line;
   if(!GlobalVariableCheck(GV_LS_SEEN) || GlobalVariableGet(GV_LS_SEEN)<=0.5)
   { GlobalVariableSet(GV_LS_SEEN,1); g_gvDirty=true; }   // from now on a missing file is a finding
}
bool ReadLockstateRaw(string &payloadOut)   // true=file present; payloadOut="CORRUPT" if invalid
{
   payloadOut="";
   if(!FileIsExist(LOCKFILE)) return false;
   // §06-fix (medium): the file EXISTS but cannot be opened (sharing lock by antivirus/backup/sync, I/O error).
   //   That used to be treated like a "first start" -> the more restrictive file state got overwritten (fail-OPEN).
   //   Now: short retry, then treat it like CORRUPT (fail-closed) instead of silently losing the lock.
   int h=INVALID_HANDLE;
   for(int a=0;a<3 && h==INVALID_HANDLE;a++)
   { h=FileOpen(LOCKFILE,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE); if(h==INVALID_HANDLE) Sleep(20); }
   if(h==INVALID_HANDLE){ PrintFormat("Mamal: lockstate present but not readable (err=%d) -> fail-closed.",GetLastError()); payloadOut="CORRUPT"; return true; }
   string line=FileReadString(h);
   FileClose(h);
   string parts[]; int k=StringSplit(line,(ushort)';',parts);
   if(k<3 || parts[0]!="MMTLS1"){ payloadOut="CORRUPT"; return true; }
   string payload=""; for(int i=1;i<k-1;i++) payload+=(i>1?";":"")+parts[i];
   if((uint)StringToInteger(parts[k-1]) != LsHash(payload)){ payloadOut="CORRUPT"; return true; }
   payloadOut=payload;
   return true;
}
// §05-fix (high): can also be called PERIODICALLY from the cycle. ReconcileLockstate() used to run only in OnInit — intraday,
//   the cycle read the locks straight from the GlobalVariables, which are deletable via F3 (lock gone, and WriteLockstate then mirrored
//   the unlocked state back with a valid signature = the EA laundered its own tamper detection). Now the
//   periodic call restores still ACTIVE locks from the signed file and journals the GV deletion as TAMPER.
void ReconcileLockstate(bool periodic=false)   // most restrictive state from GV + file; fail-closed on corruption
{
   string payload; bool had=ReadLockstateRaw(payload);
   // v0.63 (verify finding, critical): a MISSING file used to count as a first start and had no consequences —
   //   so the protection could be defeated cleanly with one Explorer click plus one F3 delete:
   //   first the file gone (nobody notices), then the GlobalVariable gone, and the next write
   //   recreated the file from the defused state, correctly signed. No race, fully reproducible.
   //   Therefore, from the first successful write on, the EA remembers that the file EXISTED (GV_LS_SEEN);
   //   if it disappears afterwards, that is a tampering finding and is treated like a corrupt file.
   if(!had)
   {
      if(GlobalVariableCheck(GV_LS_SEEN) && GlobalVariableGet(GV_LS_SEEN)>0.5)
      { GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,6); GlobalVariablesFlush();
        // v0.64: forced alert ONLY on a state change. If the state does not heal (write-protected
        //   folder, file permissions), this branch would otherwise fire a modal dialog in EVERY cycle — that would have
        //   made the terminal unusable and would be worse than the missed message it fixes.
        if(!g_lsMissWarned)
        { g_lsMissWarned=true;
          Notify(T("tamper.lockstateMissing"),false,true);
          Journal("TAMPER","-","-",0,0,0,0,0,"Lockstate-Datei fehlt (geloescht?) -> fail-closed (Tagessperre)"); }
        g_lsGuard=true; WriteLockstate(); g_lsGuard=false;   // write directly: the reconciliation has nothing left to read
        return; }
      if(!periodic) WriteLockstate(); return;   // genuine first start: create it, no alert
   }
   if(payload=="CORRUPT")
   {
      GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,6); GlobalVariablesFlush();
      if(!g_lsCorruptWarned)
      { g_lsCorruptWarned=true;
        Notify(T("tamper.lockstateCorrupt"),false,true);
        Journal("TAMPER","-","-",0,0,0,0,0,"Lockstate korrupt -> fail-closed (Tagessperre)"); }
      g_lsGuard=true; WriteLockstate(); g_lsGuard=false;   // v0.64: without the guard WriteLockstate called the reconciliation
      return;                                              //   again -> two alerts and two TAMPER lines per corruption
   }
   g_lsMissWarned=false; g_lsCorruptWarned=false;   // file is readable and valid again -> latches free for the next real finding
   string p[]; int k=StringSplit(payload,(ushort)';',p);
   if(k>=8)
   {
      long   fDay   =StringToInteger(p[0]);
      int    fHard  =(int)StringToInteger(p[1]);
      long   fLockU =StringToInteger(p[2]);
      long   fWeek  =StringToInteger(p[3]);
      int    fTgt   =(int)StringToInteger(p[4]);
      long   fCool  =StringToInteger(p[5]);
      double fDayR  =StringToDouble(p[6]);
      int    fConsec=(int)StringToInteger(p[7]);
      bool   restored=false;   // a still ACTIVE lock had to be restored from the file -> GV was tampered with
      if(fHard==1 && !IsHardLocked()){ GlobalVariableSet(GV_HARD_LOCK,1); restored=true; if(!periodic) Notify(T("tamper.hardLockRestored"),false,true); }
      datetime gLockU=GlobalVariableCheck(GV_LOCK_UNTIL)?(datetime)GlobalVariableGet(GV_LOCK_UNTIL):0;
      if((datetime)fLockU>gLockU && (datetime)fLockU>SrvTime()){ GlobalVariableSet(GV_LOCK_UNTIL,(double)fLockU); restored=true; }   // only restore a still ACTIVE day lock (not an expired one -> the RollNewDay clear stands)
      if(fWeek==WeekIdx() && (!GlobalVariableCheck(GV_WEEK_LOCK)||(long)GlobalVariableGet(GV_WEEK_LOCK)!=WeekIdx()))
         { GlobalVariableSet(GV_WEEK_LOCK,(double)WeekIdx()); restored=true; }
      if(fTgt==1 && fDay==(long)ServerDayKey() && !TargetHit()) GlobalVariableSet(GV_TARGET_HIT,1);
      datetime gCool=GlobalVariableCheck(GV_COOLDOWN)?(datetime)GlobalVariableGet(GV_COOLDOWN):0;
      if((datetime)fCool>gCool && (datetime)fCool>SrvTime()){ GlobalVariableSet(GV_COOLDOWN,(double)fCool); restored=true; }
      if(fDay==(long)ServerDayKey())
      {
         if(fDayR  >GlobalVariableGet(GV_DAY_RISK))    GlobalVariableSet(GV_DAY_RISK,fDayR);
         if(fConsec>(int)GlobalVariableGet(GV_CONSEC)) GlobalVariableSet(GV_CONSEC,(double)fConsec);
      }
      if(k>=9)   // §04-fix (medium): read the R4b base back from the file if the GVs (4-week expiry) lost it — field 9 holds CONFIRMED bases only
      {
         double fInit=StringToDouble(p[8]);
         if(fInit>0 && (!GlobalVariableCheck(GV_INIT_BAL) || GlobalVariableGet(GV_INIT_BAL)<=0))
         { GlobalVariableSet(GV_INIT_BAL,fInit); if(g_initialBalance<=0){ g_initialBalance=fInit; g_initBalConfirmed=true; } }
      }
      GlobalVariablesFlush();
      if(periodic){ if(restored){ Notify(T("tamper.lockRestoredWarning"),false,true); Journal("TAMPER","-","-",0,0,0,0,0,"Aktive Sperre aus Datei wiederhergestellt (GV-Loeschung erkannt)"); } }
      else Notify(T("tamper.lockstateReconciled"));
   }
   WriteLockstate();
}

// v0.17: robuster TickValue (Wert je Tick je Lot, i.d.R. Konto-Waehrung). Fallback, falls Broker 0 liefert,
// so that the risk never wrongly appears as 0 in enforcement (otherwise R1/R12/R17 would not take effect).
double TickVal(string s)
{
   double tv=MarketInfo(s,MODE_TICKVALUE);
   if(tv>0){ return tv; }
   double ts=MarketInfo(s,MODE_TICKSIZE), cs=MarketInfo(s,MODE_LOTSIZE);
   if(ts>0 && cs>0)   // rough estimate in quote currency (no FX conversion) -> better than 0
   {
      // §07-fix: the estimate is SELF-CONSISTENT — CalcLot and EnforceRisk compute with the same wrong value,
      //   which kept the error invisible. A reliable FX conversion cannot be derived soundly without broker-specific
      //   symbol names; so the state is at least made VISIBLE now
      //   (panel/cockpit flag + daily warning), so that the symbol/account currency gets checked.
      g_tvEstimate=true;
      if(DayKeyOf(g_lastTvWarnDay)!=DayKeyOf(SrvTime()))
      { g_lastTvWarnDay=SrvTime(); PrintFormat("Mamal: WARN TickValue for %s unavailable -> estimate in QUOTE currency (risk inaccurate, NOT converted!). Check symbol/account currency.", s);
        Journal("INFO",s,"-",0,0,0,0,0,"TickValue fehlt -> Risiko-Schaetzung ohne FX-Konvertierung (ungenau)"); }
      return ts*cs;
   }
   return 0;
}
// R3 base: ONE % base for the additive path AND for reconstruction (stable daily base, no live equity drift)
double DayRiskBase()
{
   double b = GlobalVariableCheck(GV_DAYSTART_EQ) ? GlobalVariableGet(GV_DAYSTART_EQ) : 0;
   if(b<=0) b = g_initialBalance;
   if(b<=0) b = AccountEquity();
   return b;
}
double RiskPctOfBase(string s,double lots,double open,double sl,double base)
{
   if(base<=0 || sl==0.0) return 0;
   double ts=MarketInfo(s,MODE_TICKSIZE), tv=TickVal(s);
   if(ts<=0 || tv<=0) return RiskUnknownPct(s);   // §07-fix: fail-open vermieden (siehe RiskUnknownPct)
   return (MathAbs(open-sl)/ts)*tv*lots/base*100.0;
}

//--- R3 reconciliation: rebuild the daily budget (RG_DAY_RISK) from broker data (crash-proof) ---
// R3 counts risk OPENED TODAY ("shots"), NO refund. After a crash/restart the additive
// RG_DAY_RISK can be missing -> rebuild it from open + today's closed TOOL trades (Magic), each
// position ONCE (ProcKey grouping, partial closes summed back to the entry lot size). Denominator =
// stable daily base (RG_DAYSTART_EQ), NOT live equity -> no intraday drift. Applied via max(persisted, reconstructed).
void RDR_Add(string &k[],double &lots[],double &open[],string &sym[],int &type[],double &sl[],bool &hasSL[],int &n,
             string key,double lt,double op,string sm,int ty,double slv)
{
   for(int i=0;i<n;i++) if(k[i]==key){ lots[i]+=lt; if(!hasSL[i] && slv!=0.0){ sl[i]=slv; hasSL[i]=true; } return; }
   ArrayResize(k,n+1);ArrayResize(lots,n+1);ArrayResize(open,n+1);ArrayResize(sym,n+1);ArrayResize(type,n+1);ArrayResize(sl,n+1);ArrayResize(hasSL,n+1);
   k[n]=key; lots[n]=lt; open[n]=op; sym[n]=sm; type[n]=ty; sl[n]=slv; hasSL[n]=(slv!=0.0); n++;
}
double ReconstructedDayRiskPct()
{
   long   today = ServerDayKey();
   double base  = DayRiskBase(); if(base<=0) return 0;   // same base as the additive R3 path

   string gKey[]; double gLots[]; double gOpen[]; string gSym[]; int gType[]; double gSL[]; bool gHasSL[];
   int gN=0;
   // (1) offene Tool-Positionen, heute eroeffnet
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      if(OrderMagicNumber()!=InpMagic) continue;                       // R3 = tool trades only (like the additive path)
      if(DayKeyOf(OrderOpenTime()-InpDayResetHour*3600)!=today) continue;                   // opened yesterday -> not a shot from today
      RDR_Add(gKey,gLots,gOpen,gSym,gType,gSL,gHasSL,gN,
              ProcKey(OrderOpenTime(),ty,OrderSymbol(),OrderMagicNumber(),OrderOpenPrice()),
              OrderLots(),OrderOpenPrice(),OrderSymbol(),ty,OrderStopLoss());
   }
   // (2) tool positions opened today from history (sum partial closes back to the entry lot size, ONCE per position)
   int tot=OrdersHistoryTotal();
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(DayKeyOf(OrderOpenTime()-InpDayResetHour*3600)!=today) continue;
      RDR_Add(gKey,gLots,gOpen,gSym,gType,gSL,gHasSL,gN,
              ProcKey(OrderOpenTime(),ty,OrderSymbol(),OrderMagicNumber(),OrderOpenPrice()),
              OrderLots(),OrderOpenPrice(),OrderSymbol(),ty,OrderStopLoss());
   }

   double sum=0;
   for(int g=0;g<gN;g++)
   {
      double rp = gHasSL[g] ? RiskPctOfBase(gSym[g],gLots[g],gOpen[g],gSL[g],base) : 0;
      // §07-fix: This line ran again every 15 s and flooded the audit CSV all day long with identical INFO lines
      //   (one position without SL = ~5,760 lines/day). Now only as a Print, max. 1x/day.
      if(rp<=0)
      { rp=EffRiskPct();
        if(DayKeyOf(g_lastRdrWarnDay)!=DayKeyOf(SrvTime()))
        { g_lastRdrWarnDay=SrvTime(); PrintFormat("Mamal: R3-Rekonstruktion — %s ohne SL/Tickdaten, konservativ mit %.2f%% angesetzt.",gSym[g],rp); } }
      sum += rp;
   }
   return sum;
}
void ReconcileDayRisk()
{
   double persisted     = GlobalVariableCheck(GV_DAY_RISK) ? GlobalVariableGet(GV_DAY_RISK) : 0;
   double reconstructed = ReconstructedDayRiskPct();
   if(reconstructed > persisted + 0.0001)   // only RAISE (no refund) -> max(persisted, reconstructed)
   {
      GlobalVariableSet(GV_DAY_RISK, reconstructed); GlobalVariablesFlush();
      Journal("INFO","-","-",0,0,0,0,reconstructed,StringFormat("R3 Reconcile DayRisk %.2f%% -> %.2f%% (rekonstruiert)",persisted,reconstructed));
   }
}

// v0.28: master election via heartbeat (terminal-wide GlobalVariables). Only the master enforces/writes.
// Master dies/is removed -> heartbeat goes stale (>6s) -> the next instance takes over. Fail-safe: as long as
// at least one instance is running, the account is monitored. Enforcement is account-wide (by Magic, not symbol),
// so ONE instance is entirely enough.
//  Fixes after verify: identity in DOUBLE (ChartID>2^53 -> long->double->long lost itself); clock = TimeLocal
//  (identical for all instances in the terminal, no server-offset drift); stale check bidirectional (clock jumping back).
bool ClaimMaster()
{
   double   myKey = (double)ChartID();
   datetime now   = TimeLocal();
   double   mid = GlobalVariableCheck(GV_MASTER)    ? GlobalVariableGet(GV_MASTER)             : 0.0;
   datetime hb  = GlobalVariableCheck(GV_MASTER_HB) ? (datetime)GlobalVariableGet(GV_MASTER_HB) : 0;
   double   dt  = (double)((long)now-(long)hb); if(dt<0.0) dt=-dt;   // Betrag: vergangen ODER zukunft = stale
   if(mid==myKey)   // ich bin bereits Master -> Heartbeat auffrischen (double round-trip exakt -> erkenne mich wieder)
   { GlobalVariableSet(GV_MASTER_HB,(double)now); return true; }
   if(mid==0.0)   // §07-fix: claim a free slot ATOMICALLY — otherwise two instances starting at the same time could both
   {              //   see themselves as master (Set was not atomic). SetOnCondition only sets if the value is still 0.
      // v0.42-fix (CRITICAL): SetOnCondition does NOT create a MISSING variable (Err 4058) -> after a
      //   GlobalVariableDel(GV_MASTER) (old deinit release / F3) a master election was NEVER possible again.
      //   Create the slot first if needed (temp, value 0.0) — the claim atomicity remains: exactly ONE wins.
      if(!GlobalVariableCheck(GV_MASTER)) GlobalVariableTemp(GV_MASTER);
      if(!GlobalVariableSetOnCondition(GV_MASTER,myKey,0.0)) return false;   // ein anderer war schneller
      GlobalVariableSet(GV_MASTER_HB,(double)now); return true;
   }
   if(dt>10.0)   // verwaist (>10s Schwelle: Puffer gegen langsame/eingefrorene Cycles unter Wine; Hysterese verhindert Doppel-Handeln bei Wett-Claim)
   { if(!GlobalVariableSetOnCondition(GV_MASTER,myKey,mid)) return false;    // only take over if the slot still belongs to the stale master
     GlobalVariableSet(GV_MASTER_HB,(double)now); return true; }
   return false;   // another one is the fresher master
}
void Cycle()
{
   UpdateSrvOffset();   // §04-fix (medium): also refresh the offset from OnTimer — TimeCurrent moves with EVERY Market Watch quote, not only with chart ticks
   if(g_armed!=0 && GetTickCount()-g_armMs > 30000) g_armed=0;   // v0.28: FOMO arm timeout on EVERY instance (not just the master)

   // v0.28: single-instance lock + hysteresis. Only the confirmed master (>=2 cycles in a row) enforces + writes files
   // (journal/lockstate/cockpit/flush). Prevents file collisions when the EA runs on several charts (= Wine crash when moving TP/SL)
   // AND startup/race-claim bursts. Passive instances only show their panel; BUY/SELL works on any chart (click path).
   g_masterStreak = ClaimMaster() ? (g_masterStreak+1) : 0;
   if(g_masterStreak < 2)
   {
      // v0.38 (verify): a differing InpMagic on a passive chart = its panel trades would be
      //   invisible to the master (neither InScope nor R22) -> unguarded. Warn clearly, once.
      static bool magicWarned=false;
      if(!magicWarned && GlobalVariableCheck(GV_MAGIC) && (int)GlobalVariableGet(GV_MAGIC)!=InpMagic)
      { magicWarned=true; Notify(TF("cfg.magicMismatchMaster",IntegerToString(InpMagic),IntegerToString((int)GlobalVariableGet(GV_MAGIC)))); }
      // v0.42-fix: NO master means NO enforcement, NO close evaluation, NO cockpit data.
      //   Dieser Zustand war bisher voellig unsichtbar (Panel lief weiter) — jetzt laut melden.
      // v0.43-fix: only alarm if REALLY NOBODY is master (slot free/orphaned). A passive
      //   instance is the normal case (exactly ONE is master) — it must not warn constantly.
      bool someoneIsMaster = (GlobalVariableCheck(GV_MASTER) && GlobalVariableGet(GV_MASTER)!=0.0
                              && GlobalVariableCheck(GV_MASTER_HB)
                              && MathAbs((double)((long)TimeLocal()-(long)GlobalVariableGet(GV_MASTER_HB)))<=10.0);
      // v0.45 (verify): time-based instead of cycle-based (the cycle rate depends on InpTimerSeconds) and the latch
      //   is also cleared when switching into the master state (g_noMasterSince=0 in the master path).
      if(!someoneIsMaster){ if(g_noMasterSince==0) g_noMasterSince=SrvTime(); }
      else { g_noMasterSince=0; g_noMasterWarned=false; }
      if(g_noMasterSince>0 && SrvTime()-g_noMasterSince>=30 && !g_noMasterWarned)
      {
         g_noMasterWarned=true;
         Notify(T("watchdog.noMasterActive"));
         Journal("PROTECT_OFF",Symbol(),"-",0,0,0,0,0,StringFormat("KEIN Master seit %ds — Slot %s (Enforcement/Close-Wertung inaktiv)",(int)(SrvTime()-g_noMasterSince),GlobalVariableCheck(GV_MASTER)?"belegt":"FEHLT"));
      }
      double eqp=AccountEquity(); double bp=GlobalVariableGet(GV_DAYSTART_EQ);
      if(bp<=0) bp=MathMax(AccountBalance(),eqp); if(bp<=0) bp=1;
      double ddp=(bp-eqp)/bp*100.0; if(ddp<0) ddp=0;
      uint nowp=GetTickCount();
      if(nowp-g_lastPanelMs >= (uint)InpPanelMs){ g_lastPanelMs=nowp; DrawPanel(ddp, TotalDDpct(), !IsTradeAllowed()); }
      return;
   }
   GlobalVariableSet(GV_MAGIC,(double)InpMagic);   // v0.38: master publishes its InpMagic (divergence check for the passive charts)
   g_noMasterSince=0; g_noMasterWarned=false;      // v0.45: as master the outage latch is cleared
   // v0.38-fix (verify): self-healing — if the EA started BEFORE the broker handshake (autostart race:
   //   balance/history still empty -> base 0, fail-closed), refresh the base as soon as account data is there.
   if(g_initialBalance<=0 && AccountBalance()>0)
   {
      double dep=DepositBase();
      if(dep>0 && dep < AccountBalance()*0.1) dep=0;   // Plausibilitaet wie in OnInit
      g_initialBalance = (dep>0) ? dep : AccountBalance();
      g_initBalConfirmed=true;
      GlobalVariableSet(GV_INIT_BAL,g_initialBalance);
      GlobalVariableSet(GV_BASE_WARN,0); g_gvDirty=true;
      Notify(TF("base.reloaded",DoubleToString(g_initialBalance,2),(dep>0)?"Einzahlung":"Balance"));
   }
   long today=ServerDayKey();
   // §07-fix (high): daily roll only with confirmation from the (locally unforgeable) broker time -> moving the PC clock forward
   //   no longer wipes lock/base/streak.
   if(!GlobalVariableCheck(GV_DAYSTART_DAY)) RollNewDay(false);
   else if((long)GlobalVariableGet(GV_DAYSTART_DAY)!=today)
   { if(ServerDayRollConfirmed((long)GlobalVariableGet(GV_DAYSTART_DAY))) RollNewDay(false);
     else WarnUnconfirmedRoll("day rollover"); }
   // v0.30-fix: EFF limits + protection-off counter ONCE per day, ONLY from the master (we are in the master path here) -> deterministic = master input, no loose limit from init order/handoff
   if(!GlobalVariableCheck(GV_EFF_DAY) || (long)GlobalVariableGet(GV_EFF_DAY)!=today)
   { GlobalVariableSet(GV_EFF_DAY,(double)today);
     if(InpDailyLossPct>0) GlobalVariableSet(GV_EFF_DL,InpDailyLossPct);   // Tageswechsel: ein evtl. gelockertes Limit greift jetzt
     if(InpMaxLossPct>0)   GlobalVariableSet(GV_EFF_ML,InpMaxLossPct);
     // §06-fix: take all remaining lock-relevant inputs from the input only at the day change as well (loosening only here)
     GlobalVariableSet(GV_EFF_WEEK,   InpWeeklyLossPct);
     GlobalVariableSet(GV_EFF_WARN,   InpMaxLossWarnPct);
     GlobalVariableSet(GV_EFF_GIVE,   InpGivebackPct);
     GlobalVariableSet(GV_EFF_RISK,   DesiredRiskPct());   // v0.36: weekly choice (or input default) — no longer the raw input
     GlobalVariableSet(GV_EFF_LOCKAFT,(double)InpLockAfter);
     GlobalVariableSet(GV_EFF_CDAFT,  (double)InpCooldownAfter);
     GlobalVariableSet(GV_EFF_CDMIN,  (double)InpCooldownMin);
     GlobalVariableSet(GV_EFF_REQSL,  InpRequireSL?1:0);
     GlobalVariableSet(GV_EFF_REQTP,  InpRequireTP?1:0);
     GlobalVariableSet(GV_EFF_CORR,   InpUseCorrCap?1:0);
     GlobalVariableSet(GV_TIGHT_LATCH,InpTightenOnly?1:0);   // re-set the latch only here -> cannot be switched off intraday
     GlobalVariableSet(GV_PROTOFF,0); GlobalVariableSet(GV_PROT_LATCH,0);
     GlobalVariableSet(GV_BLOCKS,0); GlobalVariableSet(GV_FILLS,0); GlobalVariableSet(GV_BLK_BURST,0);   // v0.32: Versuche-Zaehler taeglich zuruecksetzen
     g_gvDirty=true; }

   double eq   = AccountEquity();
   double base = GlobalVariableGet(GV_DAYSTART_EQ);
   if(base<=0){ base=MathMax(AccountBalance(),eq); if(base<=0) base=1; GlobalVariableSet(GV_DAYSTART_EQ,base); }

   double dailyDDpct = (base-eq)/base*100.0;   if(dailyDDpct<0) dailyDDpct=0;
   double totalDDpct = TotalDDpct();           // P0-2: guarded (g_initialBalance<=0 -> 0, no division by 0)

   // R18: Wochenwechsel + Wochenlimit
   long wk=WeekIdx();   // with the stored (effective) week start -> an input change does NOT shift the key (no artificial roll)
   bool wkOk = (!GlobalVariableCheck(GV_WEEK_IDX)) || ServerWeekRollConfirmed((long)GlobalVariableGet(GV_WEEK_IDX));   // §07-fix: the weekly roll needs broker confirmation too
   if(GlobalVariableCheck(GV_WEEK_IDX) && (long)GlobalVariableGet(GV_WEEK_IDX)!=wk && !wkOk) WarnUnconfirmedRoll("week rollover");
   if(wkOk && (!GlobalVariableCheck(GV_WEEK_IDX) || (long)GlobalVariableGet(GV_WEEK_IDX)!=wk))
   { if(InpWeekStartDay!=EffWeekStart()){ GlobalVariableSet(GV_EFF_WS,(double)InpWeekStartDay); wk=WeekIdx(); }   // §05-fix: adopt a changed week start ONLY at a real rollover, then recompute consistently
     GlobalVariableSet(GV_WEEK_IDX,(double)wk);
     GlobalVariableSet(GV_WEEKSTART_EQ,MathMax(MathMax(AccountBalance(),eq),ReconstructedBalanceAt(ServerWeekStart())));   // §04-fix (medium): delayed weekly roll (weekend gap) -> anchor balance from history instead of the dropped current value
     GlobalVariableSet(GV_WEEK_LOCK,0);
     // v0.36: carry the weekly risk into the new week; a pre-booked increase takes effect NOW.
     // v0.62-FIX (R23): The roll no longer writes GV_WEEK_RISK_IDX. Before, it set it to the new
     //   week -> WeekRiskSet() stayed true permanently -> the required weekly commitment in fact happened
     //   only ONE single time (the very first time). The index now means exclusively
     //   "confirmed in THIS week" and is only set by SetWeekRisk() — that is, only by a
     //   real confirmation from the trader.
     //   Important: the VALUE still travels on (GV_WEEK_RISK/GV_EFF_RISK), otherwise EffRiskPct() falls back to the
     //   input default and R1/R2/R12 would force-close weekend positions on Monday.
     //   Important 2: the decision "mandatory yes/no" is NOT made here. The roll runs only on the
     //   Master; haenge dieses Gate an dessen Inputs, koennte ein Chart mit InpRequireWeeklyRisk=false
     //   lift the obligation for all other instances. Gating happens locally via WeekRiskPending().
     //   Important 3 (v0.62): A PRE-BOOKED change is NOT activated by the roll while the obligation is active.
     //   It is a suggestion by the trader, not an instruction — and R23 demands a confirmation for every
     //   week. Otherwise there would be two kinds of damage: (a) a pre-booked REDUCTION would push GV_EFF_RISK
     //   down autonomously, and EnforceRisk (R1) would run in the SAME cycle -> weekend positions would be
     //   force-liquidated on Monday, and the losing close would count as the trader's fault in streak/cooldown;
     //   (b) a pre-booked INCREASE would loosen the whole auto-scale cascade (idea/heat/daily budget) in
     //   a week the trader never confirmed. The pre-booking therefore stays in place and
     //   is only consumed by SetWeekRisk() — until then it merely pre-fills the input field.
     if(GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0)
     { double pend=PendingWeekRisk(); double old=GlobalVariableGet(GV_WEEK_RISK);
       bool   hold = WeekRiskPending();                       // confirmation is pending -> change nothing autonomously
       double nr = (pend>0 && !hold) ? pend : old; if(nr>RiskCap()) nr=RiskCap();
       GlobalVariableSet(GV_WEEK_RISK,nr);
       GlobalVariableSet(GV_EFF_RISK,nr);   // the value travels along; without it EffRiskPct() falls back to the input default (R1 force-close)
       if(!hold)
       { if(GlobalVariableCheck(GV_WEEK_RISK_NXT)) GlobalVariableDel(GV_WEEK_RISK_NXT);
         if(pend>0 && MathAbs(nr-old)>0.0001) Notify(TF("cfg.weekRiskNowActive",DoubleToString(nr,2))); }
       else
       { Notify(TF("risk.week.renew",DoubleToString(nr,2)));
         Journal("INFO","-","-",0,0,0,0,nr,StringFormat("Neue Woche: Wochen-Risiko muss erneut festgelegt werden (zuletzt %.2f%%)",nr)); } }
     g_gvDirty=true; }
   if(EffWeekLoss()>0)
   {
      double wbase=GlobalVariableGet(GV_WEEKSTART_EQ); if(wbase<=0){ wbase=eq; GlobalVariableSet(GV_WEEKSTART_EQ,eq); }
      double wdd=(wbase-eq)/wbase*100.0;
      if(wdd>=EffWeekLoss() && (long)GlobalVariableGet(GV_WEEK_LOCK)!=wk)
      { GlobalVariableSet(GV_WEEK_LOCK,(double)wk); GlobalVariableSet(GV_LOCK_WHY,9); g_gvDirty=true; Notify(TF("lock.weekLimit",DoubleToString(wdd,2))); }
   }

   // R13: Tages-Hoch, Tagesziel, Giveback
   double peak=GlobalVariableGet(GV_PEAK_EQ); if(peak<=0){ peak=eq; GlobalVariableSet(GV_PEAK_EQ,eq); g_gvDirty=true; }
   if(eq>peak){ peak=eq; GlobalVariableSet(GV_PEAK_EQ,eq); g_gvDirty=true; }   // §07-fix: peak was never marked dirty -> lost on a crash (R13 giveback anchor)
   double profitPct     = (eq-base)/base*100.0;
   double peakProfitPct = (peak-base)/base*100.0;
   double dropFromPeak  = (peak-eq)/base*100.0;
   if(!TargetHit() && profitPct>=InpDailyTargetPct)
   { GlobalVariableSet(GV_TARGET_HIT,1); PersistLatch(); Notify(TF("lock.targetReached",DoubleToString(profitPct,2))); }
   if(EffGivebackPct()>0 && !IsLocked() && peakProfitPct>=InpGivebackArmPct && dropFromPeak>=EffGivebackPct())
   { GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,3); g_gvDirty=true; Notify(TF("lock.giveback",DoubleToString(peakProfitPct,2),DoubleToString(profitPct,2))); }

   TightenOnlyLimits();   // v0.30: loss limits can only be set tighter; loosening only at the day change

   bool tradingDisabled = !IsTradeAllowed();
   bool protLatch = (GlobalVariableGet(GV_PROT_LATCH)>0.5);   // v0.30-fix: SHARED latch -> a master handoff does not count the same protection-off episode twice
   if(tradingDisabled && !protLatch)
   { double poc=GlobalVariableGet(GV_PROTOFF)+1; GlobalVariableSet(GV_PROTOFF,poc); GlobalVariableSet(GV_PROT_LATCH,1);
     GlobalVariableSet(GV_PROT_SINCE,(double)SrvTime()); PersistLatch();   // §07-fix: remember the start of the protection-off phase
     Notify(TF("watchdog.autoTradingOff",IntegerToString((int)poc))); Journal("PROTECT_OFF","-","-",0,0,0,0,0,StringFormat("AutoTrading AUS — Watchdog kann NICHT schliessen (heute #%d)",(int)poc)); }
   if(!tradingDisabled && protLatch)
   {
      // §07-fix: The AutoTrading switch is the cheapest one-click bypass — enforcement stands still while the
      //   time-based deadlines (cooldown, daily/weekly lock, revenge) kept running unchecked. So sitting it out paid
      //   off. Now: the downtime is added onto all deadlines that are still ACTIVE.
      datetime ps=(datetime)GlobalVariableGet(GV_PROT_SINCE);
      int off=(ps>0)?(int)(SrvTime()-ps):0; if(off<0) off=0; if(off>86400) off=86400;   // Deckel: max 1 Tag
      if(off>5)
      {
         datetime cd=(datetime)GlobalVariableGet(GV_COOLDOWN);
         if(cd>SrvTime()) GlobalVariableSet(GV_COOLDOWN,(double)(cd+off));
         datetime lu=(datetime)GlobalVariableGet(GV_LOCK_UNTIL);
         if(lu>SrvTime()) GlobalVariableSet(GV_LOCK_UNTIL,(double)(lu+off));
         for(int r=GlobalVariablesTotal()-1;r>=0;r--)   // R25-Fenster mitziehen
         { string rn=GlobalVariableName(r);
           if(StringFind(rn,"RG_REVU_")==0 && (datetime)GlobalVariableGet(rn)>SrvTime()) GlobalVariableSet(rn,GlobalVariableGet(rn)+off); }
         Notify(TF("watchdog.autoTradingOn",IntegerToString(off)));
         Journal("PROTECT_ON","-","-",0,0,0,0,0,StringFormat("AutoTrading wieder AN nach %d s — Cooldown/Sperre/Revenge um diese Zeit verlaengert",off));
      }
      else Journal("PROTECT_ON","-","-",0,0,0,0,0,"AutoTrading wieder AN — Watchdog aktiv");
      GlobalVariableSet(GV_PROT_LATCH,0); GlobalVariableSet(GV_PROT_SINCE,0); PersistLatch();
   }

   if(!IsHardLocked() && totalDDpct>=EffMaxLoss())
   { GlobalVariableSet(GV_HARD_LOCK,1); GlobalVariableSet(GV_LOCK_WHY,8); PersistLatch(); WriteLockstate(); Notify(TF("lock.maxLoss",DoubleToString(totalDDpct,2))); }   // §07-fix: sofort persistieren (GV + signierte Datei)
   if(!IsDayLocked() && !IsHardLocked() && dailyDDpct>=EffDailyLoss())
   { GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,1); PersistLatch(); WriteLockstate(); Notify(TF("lock.dailyLoss",DoubleToString(dailyDDpct,2))); }

   // §05-fix (high): reconcile locks periodically (5s) against the signed lockstate file. Catches intraday deletion
   //   of the RG_* GlobalVariables via F3 -> an active lock is restored from the file (not overwritten by the EA).
   if(!IsTradeContextBusy() && GetTickCount()-g_lastLockReconcileMs >= 5000){ g_lastLockReconcileMs=GetTickCount(); ReconcileLockstate(true); }   // not during a trade op (Wine protection, like GV flush/history scan)

   // v0.22: full history scan NOT 2-3x/sec (Wine freeze protection). Trigger: history count changed (real close -> captured immediately, NO enforcement gap for R5/R6) OR 2s heartbeat (deferred partial close / count-masked cases).
   // v0.23: while a trade operation is running (user drags SL/TP OR the EA closes) NO heavy history scan/flush -> do not collide with MT4's own trade I/O (Wine crash when moving SL/TP). Caught up immediately once free (idempotent, heartbeat/OnTimer).
   static int  s_lastHistTot   = -1;
   static uint s_lastResolveMs = 0;
   int histTot = OrdersHistoryTotal();
   // v0.42/v0.45: cycle pulse now only as a log Print (no longer into the audit journal — 1,440 INFO lines/day
   //   crowded real events out of the cockpit view). Diagnostics stay available in the expert log.
   static uint s_pulseMs=0;
   if(GetTickCount()-s_pulseMs>=60000)
   { s_pulseMs=GetTickCount();
     PrintFormat("Mamal CycleDiag: Ctx=%s HistTotal=%d RGOPN=%d Floor=%s",IsTradeContextBusy()?"BUSY":"frei",histTot,CountOpn(),TimeToString((datetime)GlobalVariableGet(GV_LAST_CLOSE))); }
   if(!IsTradeContextBusy() && (histTot != s_lastHistTot || GetTickCount()-s_lastResolveMs >= 2000))
   { s_lastHistTot = histTot; s_lastResolveMs = GetTickCount(); BackfillHistory(); ResolveHistory(); ResolveByTicketRegistry(); ResolveManualHistory(); HistoryVisibilityWatch(); }   // P0-2/P0-4: loss streak from history (+§06 visibility watchdog, +v0.40 ticket fallback, +v0.44 manual trades for the cockpit)
   if(GetTickCount()-g_lastReconcileMs >= 15000){ g_lastReconcileMs=GetTickCount(); ReconcileDayRisk(); }   // R3: reconcile the daily budget, throttled (15s), against broker data

   // v0.31: detect user modify (same number of in-scope orders, but SL/TP changed) -> ~2s NO new enforcement enqueue, so the EA does not close a trade the user is currently editing (= root cause of the Wine crash).
   int scN; double scSig=OrderScopeSig(scN);
   if(scN==g_lastScopeN && MathAbs(scSig-g_lastScopeSig)>0.0000001)
   { if(GetTickCount()-g_modifyQuietMs >= 2000) g_modifyQuietStart=GetTickCount();   // vorherige Serie war abgelaufen -> neue Serie beginnt
     g_modifyQuietMs=GetTickCount(); }
   g_lastScopeN=scN; g_lastScopeSig=scSig;
   // §06-fix (medium): the quiet window is sliding and could therefore be extended INDEFINITELY — continuous SL/TP wiggling
   //   could suppress R1/R7/R8/R12 permanently (R7 became de facto voluntary). Now hard-capped: after 10 s
   //   of an uninterrupted modify series enforcement runs again, no matter how much the wiggling continues.
   bool modifyQuiet = (GetTickCount()-g_modifyQuietMs < 2000) && (GetTickCount()-g_modifyQuietStart < 10000);

   // v0.47: log SL/TP moves per ticket (behaviour analysis in the cockpit). Deliberately NOT
   //   during an ongoing user modify series — otherwise every intermediate step of the drag would
   //   be counted separately as its own move. Only once the user has let go does the result count.
   { static uint s_trackMs=0;
     if(!modifyQuiet && !IsTradeContextBusy() && GetTickCount()-s_trackMs>=2000){ s_trackMs=GetTickCount(); TrackSLTP(); } }

   // P0-1: Close-Operationen gedrosselt (Wine-Schutz; volle Close-Queue mit Retry-Limit folgt)
   bool canEnforce = (GetTickCount()-g_lastEnforceMs >= (uint)InpCloseThrottleMs);
   if(!tradingDisabled && canEnforce)
   {
      g_lastEnforceMs = GetTickCount();
      if(!modifyQuiet)        EnforceManualTrades();                            // R22: independent of the lock — only panel trades are allowed
      if(IsLocked())          SafeCloseAll();                                   // Sperre = flat, dringend (Close-Site prueft Kontext erneut)
      else if(!modifyQuiet)   { EnforceSLTP(); EnforceRisk(); EnforceRR(); EnforceHeat(); EnforceIdea(); EnforceEntryState(); }   // during user modify: do NOT re-enqueue (+§05: R5/R13/R16/R25, +§06: R2 monitor)
      ProcessCloseQueue();   // detection has enqueued -> now actually close (retry/backoff/journal; context recheck at the close site)
   }

   uint now=GetTickCount();
   if(now - g_lastPanelMs >= (uint)InpPanelMs){ g_lastPanelMs=now; DrawPanel(dailyDDpct,totalDDpct,tradingDisabled); }
   WriteLockstate();   // keep the lockstate mirror current (only on change -> disk; fail-closed .dat, independent of the GV flush)
   if(g_gvDirty && !IsTradeContextBusy()){ GlobalVariablesFlush(); g_gvDirty=false; }   // v0.22: ONE bundled flush per cycle instead of up to 4 synchronous ones; v0.23: do not flush during a trade op (the .dat mirror above stays the crash-safe fail-closed lock persistence, the flush comes next cycle)
   if(InpCockpit && GetTickCount()-g_lastCockpitMs>=2000){ g_lastCockpitMs=GetTickCount(); WriteCockpit(); }   // v0.26/v0.37: live state for the cockpit every 2s. NO IsTradeContextBusy gate — WriteCockpit only does file I/O, never touches the trade thread (otherwise the JSON went stale while the context was busy, e.g. close-queue retries)
   // v0.39: Dashboard-Kommando (Tighten-Only). Einzig erlaubtes Kommando: "endday" = freiwillige Selbstsperre
   //   until server midnight. Loosening is IN PRINCIPLE impossible over this channel (only setting a lock).
   if(FileIsExist(COCKPIT_CMD))
   {
      string cmd="";
      int hc=FileOpen(COCKPIT_CMD,FILE_READ|FILE_TXT|FILE_ANSI);
      if(hc!=INVALID_HANDLE){ cmd=FileReadString(hc); FileClose(hc); }
      // v0.39-fix (verify): check the FileDelete result — a file that cannot be deleted (read-only/AV lock)
      //   would otherwise be processed again EVERY cycle (journal/alert spam every second).
      static bool cmdStuck=false;
      if(!FileDelete(COCKPIT_CMD))
      { if(!cmdStuck){ cmdStuck=true; PrintFormat("Mamal: mamal_cmd.txt cannot be deleted (err=%d) — command is ignored until the file is removed.",GetLastError()); } }
      else
      {
         cmdStuck=false;
         if(StringFind(cmd,"endday")==0)
         {
            // MathMax: a possibly already LONGER lock must never be shortened by endday (strict tighten-only).
            // Guard: only act if the lock actually EXTENDS (no double journal on a repeated click).
            double cur=GlobalVariableCheck(GV_LOCK_UNTIL)?GlobalVariableGet(GV_LOCK_UNTIL):0;
            double nxt=(double)NextServerMidnight();
            if(nxt>cur)
            {
               GlobalVariableSet(GV_LOCK_UNTIL,nxt); GlobalVariableSet(GV_LOCK_WHY,4);
               GlobalVariablesFlush(); WriteLockstate();   // v0.39-fix (verify): persist IMMEDIATELY — the cmd file is already deleted, a crash in the 1s window must not lose the voluntary lock
               Journal("SELF_LOCK","-","-",0,0,0,0,0,"Tag beendet per Dashboard — Selbstsperre bis Server-Mitternacht");
               Notify(T("lock.selfLock"));
            }
         }
      }
   }
   GlobalVariableSet(GV_MASTER_HB,(double)TimeLocal());   // v0.28: heartbeat also at the END of the cycle (slow cycle -> passives do not wrongly see it as stale -> no race claim in the middle of writing)
}

// v0.33: R7 grace clock per ticket from the moment SL/TP was REMOVED (not from OrderOpenTime).
//        Otherwise an old trade would have 0s grace after the SL was removed (elapsed-since-open long > 4s).
// §06-fix (medium): grace clock PERSISTENT per ticket (GlobalVariable instead of an instance array). Before it lived only in RAM:
//   terminal restart, recompile, timeframe change or a master handoff granted a fresh deadline every time, and
//   briefly re-setting the SL reset the clock immediately -> a naked position could be held for as long as you liked.
//   Now: the clock survives restarts, and after SL/TP is re-set it is only deleted after a HEALING PERIOD (60 s).
string NkKey(int t){  return "RG_NK_" +IntegerToString(t); }   // seit wann nackt
string NkhKey(int t){ return "RG_NKH_"+IntegerToString(t); }   // seit wann wieder geheilt (SL/TP gesetzt)
datetime NakedSince(int ticket, datetime now)
{
   if(GlobalVariableCheck(NkhKey(ticket))){ GlobalVariableDel(NkhKey(ticket)); g_gvDirty=true; }   // wieder nackt -> Heilfrist verfaellt
   if(GlobalVariableCheck(NkKey(ticket)))  return (datetime)GlobalVariableGet(NkKey(ticket));
   GlobalVariableSet(NkKey(ticket),(double)now); g_gvDirty=true;
   return now;
}
void NakedClear(int ticket, datetime now)   // SL/TP back -> delete the clock only after the healing period (no reset via a short toggle)
{
   if(!GlobalVariableCheck(NkKey(ticket))) return;
   if(!GlobalVariableCheck(NkhKey(ticket))){ GlobalVariableSet(NkhKey(ticket),(double)now); g_gvDirty=true; return; }
   if(now-(datetime)GlobalVariableGet(NkhKey(ticket)) >= 60)
   { GlobalVariableDel(NkKey(ticket)); GlobalVariableDel(NkhKey(ticket)); g_gvDirty=true; }
}
void PruneNaked()   // remove markers for tickets that are no longer open (O(N_GV) -> only call in the 60s housekeeping)
{
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   {
      string nm=GlobalVariableName(i);
      bool isNk =(StringFind(nm,"RG_NK_") ==0);
      bool isNkh=(StringFind(nm,"RG_NKH_")==0);
      if(!isNk && !isNkh) continue;
      int t=(int)StringToInteger(StringSubstr(nm, isNk?6:7));
      if(t<=0 || !OrderSelect(t,SELECT_BY_TICKET) || OrderCloseTime()!=0 || (OrderType()!=OP_BUY && OrderType()!=OP_SELL))
         GlobalVariableDel(nm);
   }
}

void EnforceSLTP()   // R7 (v0.33: 4s grace from SL/TP REMOVAL, also applies to panel trades; news blackout -> immediately)
{
   if(IsTradeContextBusy()) return;
   int grace = InNewsBlackout() ? InpSLTPGraceNews : InpSLTPGraceSeconds;
   if(grace<0) grace=0;
   datetime now = SrvTime();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11
      int  ticket = OrderTicket();
      bool naked  =( (EffRequireSL() && OrderStopLoss()==0.0) || (EffRequireTP() && OrderTakeProfit()==0.0) );   // §06-fix: SL/TP obligation is tighten-only (cannot be switched off intraday)
      if(!naked){ NakedClear(ticket, now); continue; }       // SL/TP (back) there -> delete the clock only after the healing period
      datetime since   = NakedSince(ticket, now);            // seit wann nackt (persistent, ueberlebt Neustart)
      int      elapsed = (int)(now - since);
      if(elapsed >= grace)                                    // 4s elapsed (news: immediately) -> close the TRADE (not MT4)
         RequestClose(ticket,StringFormat("R7 SL/TP missing (%ds after removal, grace %ds)",elapsed,grace));
      // otherwise: still within the deadline -> time to add SL/TP
   }
}

void EnforceRisk()   // R1
{
   if(IsTradeContextBusy()) return;
   double eq=AccountEquity(); if(eq<=0) return;
   RefreshRates();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11
      double sl=OrderStopLoss(); if(sl==0.0) continue;
      double rp=RiskPctOfBase(OrderSymbol(),OrderLots(),OrderOpenPrice(),sl,DayRiskBase());   // B11: stable daily base instead of live equity (falling equity must not close a correct position)
      if(rp > EffRiskPct()*InpRiskTolFactor)   // §06-fix: Risiko/Trade tighten-only
         RequestClose(OrderTicket(),StringFormat("R1 risk too large (%.2f%%)",rp));
   }
}

void EnforceRR()   // R8
{
   if(InpMinRR<=0) return;
   if(IsTradeContextBusy()) return;
   RefreshRates();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11
      // §07-fix: tool trades were CATEGORICALLY exempt (B3) — a TP worsened after the fact therefore stayed
      //   unenforced while R8 was active. The actual purpose was only to tolerate fill slippage right after the entry:
      //   hence now only a grace period of 60 s instead of a permanent exemption.
      if(OrderMagicNumber()==InpMagic && (SrvTime()-OrderOpenTime())<60) continue;
      double sl=OrderStopLoss(), tp=OrderTakeProfit();
      if(sl==0.0 || tp==0.0) continue;
      double risk=MathAbs(OrderOpenPrice()-sl), rew=MathAbs(tp-OrderOpenPrice());
      if(risk<=0) continue;
      double rr=rew/risk;
      if(rr < InpMinRR-0.01)
         RequestClose(OrderTicket(),StringFormat("R8 CRV %.2f < %.2f",rr,InpMinRR));
   }
}

void EnforceHeat()   // R12
{
   if(IsTradeContextBusy()) return;
   if(TotalOpenRiskPct() <= EffHeat()*InpRiskTolFactor) return;
   RefreshRates();
   int newest=-1; datetime nt=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11
      if(OrderStopLoss()==0.0) continue;
      if(OrderOpenTime()>=nt){ nt=OrderOpenTime(); newest=OrderTicket(); }
   }
   if(newest<0) return;
   if(!OrderSelect(newest,SELECT_BY_TICKET)) return;
   RequestClose(newest,"R12 Gesamtrisiko-Deckel");
}

// §06-fix (medium): R2 monitor. For the idea cap there was ONLY an entry gate — an idea that had once exceeded it
//   (e.g. smuggled through the gate by removing the SL) stayed above the cap permanently, without anything correcting it.
//   Analogous to EnforceHeat: close the YOUNGEST position of the affected idea, one correction per cycle.
void EnforceIdea()
{
   if(IsTradeContextBusy()) return;
   double cap=EffIdeaCap()*InpRiskTolFactor;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int t=OrderType(); if(t!=OP_BUY && t!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;
      string sym=OrderSymbol(); bool isBuy=(t==OP_BUY);
      if(IdeaOpenRiskPct(sym,isBuy) <= cap) continue;        // SL-basiert (Monitor) — nackte Positionen fangen R7
      int newest=-1; datetime nt=0;
      for(int k=OrdersTotal()-1;k>=0;k--)
      {
         if(!OrderSelect(k,SELECT_BY_POS,MODE_TRADES)) continue;
         int t2=OrderType(); if(t2!=OP_BUY && t2!=OP_SELL) continue;
         if(!InScope(OrderMagicNumber())) continue;
         if(OrderSymbol()!=sym || ((t2==OP_BUY)!=isBuy)) continue;
         if(OrderStopLoss()==0.0) continue;
         if(OrderOpenTime()>=nt){ nt=OrderOpenTime(); newest=OrderTicket(); }
      }
      if(newest>0) RequestClose(newest,"R2 idea cap exceeded");
      return;                                                // one correction per cycle (like EnforceHeat)
   }
}

// §06-fix (medium): history visibility watchdog. R5/R6/R25 and the R3 reconstruction read via OrdersHistoryTotal(),
//   which in MT4 only returns the period selected in the account history tab. If the user sets the tab to an old
//   period, today's closes are invisible -> loss streak/cooldown/lock never fire, without any detection.
//   Watchdog: in-scope tickets that disappeared must be findable in the history. Two-pass procedure (suspect list),
//   so that a short timing offset right after the close does not trigger a false alarm.
void HistoryVisibilityWatch()
{
   int cur[]; int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int t=OrderType(); if(t!=OP_BUY && t!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;
      ArrayResize(cur,n+1); cur[n]=OrderTicket(); n++;
   }
   // Pass 2: re-check old suspects -> still invisible = history is filtered
   for(int s=ArraySize(g_suspTicket)-1;s>=0;s--)
   {
      int t=g_suspTicket[s];
      if(OrderSelect(t,SELECT_BY_TICKET) && OrderCloseTime()!=0) continue;   // jetzt sichtbar -> Entwarnung
      Notify(T("watchdog.historyTradeMissing"));
      Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("Ticket %d nach dem Schliessen nicht in der History sichtbar — History-Filter? -> Tagessperre",t));
      GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,5); g_gvDirty=true;
   }
   ArrayResize(g_suspTicket,0);
   // Pass 1: tickets that disappeared since the last run and are (not yet) in the history -> suspect
   for(int a=0;a<ArraySize(g_seenTicket);a++)
   {
      int t=g_seenTicket[a]; bool still=false;
      for(int b=0;b<n;b++) if(cur[b]==t){ still=true; break; }
      if(still) continue;
      if(OrderSelect(t,SELECT_BY_TICKET) && OrderCloseTime()!=0) continue;   // cleanly in the history
      int m=ArraySize(g_suspTicket); ArrayResize(g_suspTicket,m+1); g_suspTicket[m]=t;
   }
   ArrayResize(g_seenTicket,n);
   for(int c=0;c<n;c++) g_seenTicket[c]=cur[c];
}

// §05-fix (hoch): Entry-Regeln (R5 Cooldown / R13 Tagesziel / R16 Session / R25 Revenge) NACHTRAEGLICH durchsetzen.
//   So far they lived ONLY in the DoEntry click path -> an in-scope position created via terminal/mobile/pending fill
//   stayed open (only R1/R7/R12/lock were reverted). Now: delete in-scope pendings inside the lock window and close in-scope
//   positions that were opened WHILE a lock window was active (locks are covered separately by SafeCloseAll).
void EnforceEntryState()
{
   if(IsTradeContextBusy()) return;
   bool cd = CooldownActive();
   bool th = TargetHit();
   bool blockNew = cd || th || OffSession();   // Zustaende, in denen ein NEUER Entry blockiert wuerde
   datetime cend   = (datetime)GlobalVariableGet(GV_COOLDOWN);
   datetime cstart = (EffCooldownMin()>0) ? cend-(datetime)(EffCooldownMin()*60) : cend;   // cooldown start (= time of the triggering loss), effective duration
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11: foreign magics only under TOOL_PLUS_MANUAL/ALL_POSITIONS
      int      ty=OrderType();
      datetime ot=OrderOpenTime();
      if(ty!=OP_BUY && ty!=OP_SELL)                          // Pending -> do not even let it fill during the lock window
      {
         bool pBuy=(ty==OP_BUYLIMIT || ty==OP_BUYSTOP);
         if(blockNew || RevengeBlocked(OrderSymbol(),pBuy)) RequestClose(OrderTicket(),"R5/R13/R16/R25 Pending im Sperrfenster");
         continue;
      }
      bool isBuy=(ty==OP_BUY);
      if(cd && EffCooldownMin()>0 && ot>=cstart)             // waehrend Cooldown eroeffnet (haette R5-Gate blockiert)
      { RequestClose(OrderTicket(),"R5 Cooldown-Entry (nachtraeglich revertiert)"); continue; }
      if(OffSessionAt(ot))                                   // opened outside the session / inside the news window (R16)
      { RequestClose(OrderTicket(),"R16 Off-Session-Entry (nachtraeglich revertiert)"); continue; }
      if(InpRevengeMin>0 && RevengeBlocked(OrderSymbol(),isBuy))   // counter-trade inside the active revenge window (R25)
      {
         datetime ru=(datetime)GlobalVariableGet(RevUntilKey(OrderSymbol()));
         datetime rs=ru-(datetime)(InpRevengeMin*60);
         if(ot>=rs){ RequestClose(OrderTicket(),"R25 Revenge-Entry (nachtraeglich revertiert)"); continue; }
      }
      // R13 TargetHit: no reliable open-time reference for running positions -> only pendings (above) are deleted;
      //   an already open position keeps running (contract: the target blocks NEW trades, it does not flatten).
   }
}

// R22 (v0.35): PANEL TRADES ONLY. Anything that did NOT come from the tool's BUY/SELL button is closed
//   immediately — because only the panel path passes the entry gates (R1 lot calculation, R2/R3/R12/R17 budgets,
//   cooldown, session, revenge). A phone trade used to bypass every rule and, with a lock active, was not even
//   closed (only warned 1x/min) — that was the last big hole in detect-and-revert.
//   DELIBERATE BOUNDARY: magic 0 only (= manual/phone/order window). Trades of other EAs carry their own
//   magic number and stay untouched, so a second EA on the account does not get wiped out.
void EnforceManualTrades()
{
   if(!InpCloseManualTrades) return;
   if(InpMagic==0) return;   // FAILSAFE: with magic 0 our own panel trades would be indistinguishable from manual ones -> R22 would wipe them (warning in OnInit)
   if(IsTradeContextBusy()) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=0) continue;                    // 0 = manuell; fremde EA-Magics bleiben unberuehrt
      int ty=OrderType();
      if(ty==OP_BUY || ty==OP_SELL) RequestClose(OrderTicket(),"R22 Manueller Trade — nur Panel-Trades erlaubt");
      else                          RequestClose(OrderTicket(),"R22 Manuelle Pending-Order — nur Panel-Trades erlaubt");
   }
}

void SafeCloseAll()   // on lock: all in-scope positions/pendings into the close queue (retry/backoff/journal)
{
   int foreign=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int tp=OrderType();
      if(!InScope(OrderMagicNumber()))                       // P1-11: TOOL_ONLY = fremde/manuelle Magics unangetastet
      { if(tp==OP_BUY || tp==OP_SELL) foreign++; continue; }
      if(tp==OP_BUY || tp==OP_SELL) RequestClose(OrderTicket(),"Lock SafeCloseAll");
      else                          RequestClose(OrderTicket(),"Lock SafeCloseAll (pending)");
   }
   // P0-1: LOCKED, but positions open outside the scope -> the watchdog does NOT close them -> warn loudly (max 1x/min)
   if(foreign>0)
   {
      static datetime lastForeignWarn=0;
      if(SrvTime()-lastForeignWarn >= 60)
      {
         lastForeignWarn=SrvTime();
         Notify(TF("watchdog.foreignPositionsWhileLocked",IntegerToString(foreign),IntegerToString((int)InpWatchScope)));
         Journal("PROTECT_OFF","-","-",0,0,0,0,0,StringFormat("Lock aktiv, %d ungeschuetzte Position(en) ausserhalb Scope offen",foreign));
      }
   }
}

//--- Risiko / Auto-Lot ---------------------------------------------
// §07-fix: with tick data missing (TICKSIZE/TickValue = 0) the risk functions returned 0 % — a possibly huge
//   position was thus INVISIBLE to R1/R12/R17 (fail-open), without any warning. Now: valued conservatively with risk/trade
//   (counts into the sums, but on its own triggers no forced close, since EnforceRisk compares against limit*tolerance
//   prueft) + taeglich einmal warnen.
double RiskUnknownPct(string s)
{
   g_tvEstimate=true;
   if(DayKeyOf(g_lastTvWarnDay)!=DayKeyOf(SrvTime()))
   { g_lastTvWarnDay=SrvTime(); PrintFormat("Mamal: WARN no tick data for %s — risk assumed conservatively at %.2f%% (symbol in Market Watch?).", s, EffRiskPct()); }
   return EffRiskPct();
}
double RiskPctOf(string s,double lots,double open,double sl)
{
   double eq=AccountEquity(); if(eq<=0 || sl==0.0) return 0;
   double ts=MarketInfo(s,MODE_TICKSIZE), tv=TickVal(s);
   if(ts<=0 || tv<=0) return RiskUnknownPct(s);
   return (MathAbs(open-sl)/ts)*tv*lots/eq*100.0;
}
// §06-fix (medium): positions WITHOUT SL contributed 0 % to heat/idea/R17. That made every portfolio gate bypassable:
//   briefly remove the SL -> the new trade passes R12/R2 -> SL back within the R7 grace. For the ENTRY gates, naked
//   positions are now valued conservatively with risk/trade (conservative=true). The MONITOR paths (EnforceHeat/EnforceIdea)
//   deliberately keep computing SL-based, so a naked position does not wrongly cause ANOTHER position to be closed
//   (R7 is responsible for that, and closes the naked position itself).
double TotalOpenRiskPct(bool conservative=false)
{
   double sum=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int t=OrderType(); if(t!=OP_BUY && t!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11
      if(OrderStopLoss()==0.0){ if(conservative) sum+=EffRiskPct(); continue; }
      sum += RiskPctOf(OrderSymbol(),OrderLots(),OrderOpenPrice(),OrderStopLoss());
   }
   return sum;
}
double IdeaOpenRiskPct(string s,bool isBuy,bool conservative=false)
{
   double sum=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int t=OrderType(); if(t!=OP_BUY && t!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11
      if(OrderSymbol()!=s) continue;
      if((t==OP_BUY)!=isBuy) continue;
      if(OrderStopLoss()==0.0){ if(conservative) sum+=EffRiskPct(); continue; }
      sum += RiskPctOf(OrderSymbol(),OrderLots(),OrderOpenPrice(),OrderStopLoss());
   }
   return sum;
}
double SLLinePrice(){ if(ObjectFind(0,SLLINE)<0) return 0.0; return ObjectGetDouble(0,SLLINE,OBJPROP_PRICE,0); }

int LotDigits(double step){ if(step>=1.0) return 0; if(step>=0.1) return 1; if(step>=0.01) return 2; if(step>=0.001) return 3; return 4; }   // §07-fix: decimal places from the broker lot step instead of a fixed 2
double CalcLot(double dist,double &riskPctOut)
{
   riskPctOut=0;
   if(dist<=0) return 0;
   double eq=AccountEquity();
   double ts=MarketInfo(Symbol(),MODE_TICKSIZE), tv=TickVal(Symbol());
   if(ts<=0 || tv<=0 || eq<=0) return 0;
   double riskMoney=eq*EffectiveRiskPct()/100.0;
   double lot=riskMoney/((dist/ts)*tv);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP); if(step<=0) step=0.01;
   double mx=MarketInfo(Symbol(),MODE_MAXLOT);
   // §07-fix: NormalizeDouble(lot,2) rounded UP again when LOTSTEP<0.01 (e.g. 0.001) — 0.014 became 0.01->0.01,
   //   but 0.015 became 0.02 = up to +100 % risk above the limit (and an immediate self-close by R1). Now it normalizes
   //   to the decimal places of the BROKER lot step, never beyond the rounded-down value.
   lot=MathFloor(lot/step + 0.0000001)*step; lot=NormalizeDouble(lot,LotDigits(step));   // +eps (v0.40): binary FP otherwise lost a lot step now and then
   if(mx>0 && lot>mx) lot=mx;   // B16: only clamp if the broker supplies a valid MaxLot (otherwise mx=0 would set the lot to 0)
   if(lot>0) riskPctOut=((dist/ts)*tv*lot)/eq*100.0;
   return lot;
}

void DoEntry(bool isBuy)
{
   string dir=isBuy?"BUY":"SELL";
   if(!IsTradeAllowed()){ Notify(T("block.autoTradingOff")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"AutoTrading aus"); return; }
   if(IsLocked()){ Notify(T("block.locked")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"locked"); return; }
   if(BaseWarn()){ Notify(T("block.baseUnsure")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"P1-2 base uncertain"); return; }
   // v0.49: the weekly risk must be set DELIBERATELY before trading. Every new week
   //   forces the decision again — that is the core of the weekly discipline, not a technical constraint.
   if(WeekRiskPending())
   { Notify(T("block.weekRiskMissing"));
     Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"weekly risk not set"); return; }
   if(MaxLossWarnActive()){ Notify(TF("block.maxLossWarn",DoubleToString(TotalDDpct(),2),DoubleToString(EffMaxLoss(),1))); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R4b Warn-Gate"); return; }
   if(TargetHit()){ Notify(T("block.targetHit")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R13 daily target"); return; }
   if(CooldownActive()){ int remm=(int)(((datetime)GlobalVariableGet(GV_COOLDOWN)-SrvTime())/60)+1; Notify(TF("block.cooldown",IntegerToString(remm))); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"cooldown"); return; }
   if(OffSession()){ Notify(T("block.offSession")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R16 Session/News"); return; }
   if(RevengeBlocked(Symbol(),isBuy)){ Notify(T("block.revenge")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R25 Revenge"); return; }
   if(InpMinGapSec>0)
   {
      double lastE=GlobalVariableGet(GV_LAST_ENTRY);
      if(lastE>0 && (SrvTime()-(datetime)lastE) < InpMinGapSec)
      { int rem=(int)(InpMinGapSec-(SrvTime()-(datetime)lastE)); Notify(TF("block.minGap",IntegerToString(rem))); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R14 Mindestpause"); return; }
   }

   double slp=SLLinePrice();
   // §07-fix (R11 gaps): these rejection paths used to write NO journal entry — so the "audit-grade" journal was missing
   //   exactly those failed attempts that matter for the discipline statistics.
   if(slp<=0){ Notify(T("block.noSlLine")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R7 no SL line set"); return; }
   RefreshRates();
   double entry=isBuy ? MarketInfo(Symbol(),MODE_ASK) : MarketInfo(Symbol(),MODE_BID);
   if(isBuy  && slp>=entry){ Notify(T("block.slSideBuy")); Journal("BLOCKED",Symbol(),dir,0,entry,slp,0,0,"R7 SL auf falscher Seite"); return; }
   if(!isBuy && slp<=entry){ Notify(T("block.slSideSell")); Journal("BLOCKED",Symbol(),dir,0,entry,slp,0,0,"R7 SL auf falscher Seite"); return; }
   double dist=MathAbs(entry-slp);
   double stoplevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(dist<=stoplevel){ Notify(T("block.slBrokerStop")); Journal("BLOCKED",Symbol(),dir,0,entry,slp,0,0,"R15 unter Broker-STOPLEVEL"); return; }
   if(InpMinStopPips>0 && dist < InpMinStopPips*Pip())
   { Notify(TF("block.slMinPips",DoubleToString(InpMinStopPips,0))); Journal("BLOCKED",Symbol(),dir,0,entry,slp,0,0,"R15 min SL"); return; }

   double rp; double lot=CalcLot(dist,rp);
   double mn=MarketInfo(Symbol(),MODE_MINLOT);
   if(InpMaxLot>0 && lot>InpMaxLot)
   { double stp=MarketInfo(Symbol(),MODE_LOTSTEP); if(stp<=0) stp=0.01;
     lot=NormalizeDouble(MathFloor(InpMaxLot/stp + 0.0000001)*stp,LotDigits(stp));   // §07-fix: realign to the lot step after clamping (otherwise OrderSend err 131 "invalid volume"); +eps v0.40 (FP)
     rp=RiskPctOf(Symbol(),lot,entry,slp); }
   if(lot<mn || lot<=0){ Notify(TF("block.lotBelowMin",DoubleToString(mn,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R15 Lot unter Broker-Minimum"); return; }
   double r3rp = RiskPctOfBase(Symbol(), lot, entry, slp, DayRiskBase());   // R3 uses the same day baseline as the reconstruction (not live equity)

   double ideaR=IdeaOpenRiskPct(Symbol(),isBuy,true); double ic=EffIdeaCap();   // §06-fix: nackte Positionen konservativ mitzaehlen
   if(ideaR + rp > ic + 0.01)
   { Notify(TF("block.ideaCap",Symbol(),DoubleToString(ideaR,2),DoubleToString(ic,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R2 idea cap"); return; }

   ReconcileDayRisk();   // R3: reconcile the day budget before the gate (max persisted/reconstructed)
   double dayR=GlobalVariableGet(GV_DAY_RISK); double db=EffDay();
   if(dayR + r3rp > db + 0.01)
   { Notify(TF("block.dayBudget",DoubleToString(dayR,2),DoubleToString(r3rp,2),DoubleToString(db,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,r3rp,"R3 daily budget"); return; }

   double heat=TotalOpenRiskPct(true); double hc=EffHeat();   // §06-fix: count naked positions conservatively (gate not bypassable by removing the SL)
   if(heat + rp > hc + 0.01)
   { Notify(TF("block.heat",DoubleToString(heat,2),DoubleToString(rp,2),DoubleToString(hc,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R12 Heat"); return; }

   if(EffUseCorrCap())   // §06-fix: R17 tighten-only (once on -> cannot be switched off intraday)
   {
      double cc = EffCorrCap();
      double mx = MaxCurrencyExposurePct(Symbol(), isBuy, rp, true);
      if(mx > cc + 0.01)
      { Notify(TF("block.correlation",DoubleToString(mx,2),DoubleToString(cc,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R17 Korrelation"); return; }
   }

   int    dig=(int)MarketInfo(Symbol(),MODE_DIGITS);
   // v0.46: a dragged TP line takes precedence — but only if it sits on the correct side.
   //   Otherwise (and if InpTpLine=false) the auto TP from InpRR stays. The R8 minimum R:R is checked further below.
   double tp =isBuy ? entry+dist*InpRR : entry-dist*InpRR;
   double tpl=TPLinePrice();
   if(tpl>0 && ((isBuy && tpl>entry) || (!isBuy && tpl<entry))) tp=tpl;
   double slN=NormalizeDouble(slp,dig), tpN=NormalizeDouble(tp,dig), pxN=NormalizeDouble(entry,dig);

   // §07-fix: check the context and refresh the price before sending — between the lot/gate computation (several
   //   order scans) and the OrderSend the price could be stale, and a busy trade context led to
   //   failure under Wine. Also, a failed OrderSend used to NOT be in the journal (R11 gap).
   if(IsTradeContextBusy()){ Notify(T("misc.tradeContextBusy")); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"Handelskontext belegt"); return; }
   RefreshRates();
   pxN = NormalizeDouble(isBuy ? MarketInfo(Symbol(),MODE_ASK) : MarketInfo(Symbol(),MODE_BID), dig);
   int ticket=OrderSend(Symbol(), isBuy?OP_BUY:OP_SELL, lot, pxN, InpSlippage, slN, tpN, "Mamal", InpMagic, 0, isBuy?clrDodgerBlue:clrTomato);
   if(ticket<0){ int oerr=GetLastError(); Notify(TF("misc.orderSendFailed",IntegerToString(oerr),DoubleToString(lot,2))); Journal("BLOCKED",Symbol(),dir,lot,pxN,slN,tpN,rp,StringFormat("OrderSend fehlgeschlagen err=%d",oerr)); return; }
   GlobalVariableSet(GV_DAY_RISK, dayR+r3rp);   // R3 budget on the day baseline (same unit as the reconstruction)
   GlobalVariableSet(GV_LAST_ENTRY,(double)SrvTime());
   GlobalVariableSet(OpnKey(ticket),(double)SrvTime());   // v0.40: Panel-Ticket registrieren (Close-Erkennung magic-/tab-unabhaengig)
   GlobalVariablesFlush();
   Journal("OPEN",Symbol(),dir,lot,pxN,slN,tpN,rp,"in-plan "+CandleThirdTag(TimeCurrent()),ticket);   // v0.52: in welchem Kerzendrittel ausgefuehrt
   Shot("open",ticket);   // v0.47: Einstiegs-Bild mit Ticket-Bezug
   PrintFormat("Mamal: %s %.2f lot SL %s TP %s (risk %.2f%%, heat %.2f%%, day %.2f%%)", dir, lot, DoubleToString(slN,dig), DoubleToString(tpN,dig), rp, heat+rp, dayR+r3rp);
   g_panelSig="";
}

// v0.21: only set the SL line after InpSlClicksToMove clicks into the same zone (prevents accidental setting on the first click).
void SlZoneClick(double price)
{
   int  need = (InpSlClicksToMove<1 ? 1 : InpSlClicksToMove);
   uint now  = GetTickCount();
   double tol = price*0.0015; double tpip=InpSlZonePips*Pip(); if(tpip>tol) tol=tpip; if(tol<=0) tol=Pip();   // ~0.15% of the price or the pip floor
   bool sameZone = (g_slClicks>0 && MathAbs(price-g_slClickPrice)<=tol && (now-g_slClickMs) < 10000);
   if(sameZone) g_slClicks++;
   else       { g_slClicks=1; g_slClickPrice=price; }   // neue Zone -> Zaehler neu
   g_slClickMs = now;
   if(g_slClicks>=need)   // genug Klicks -> Linie tatsaechlich setzen
   {
      ObjectSetDouble (0,SLLINE,OBJPROP_PRICE,0,price);
      ObjectSetInteger(0,SLLINE,OBJPROP_SELECTED,true);
      g_slClicks=0;
   }
   ObjectSetString(0,PFX+"prev",OBJPROP_TEXT,PreviewText());
   ChartRedraw(0);
}
string PreviewText()
{
   if(g_flash!="" && (GetTickCount()-g_flashMs) < g_flashHold) return g_flash;   // v0.21: letzte Meldung/Ablehnungsgrund 6s zeigen
   if(g_armed!=0) return TF("preview.confirm",g_armed==1?"BUY":"SELL");
   if(g_slClicks>0 && InpSlClicksToMove>1 && (GetTickCount()-g_slClickMs) < 10000)   // v0.21: 3-Klick-Fortschritt anzeigen
      return TF("preview.slClicks",DoubleToString(g_slClickPrice,Digits),IntegerToString(InpSlClicksToMove-g_slClicks));
   double slp=SLLinePrice(); if(slp<=0) return T("preview.noSlLine");
   double bid=MarketInfo(Symbol(),MODE_BID), ask=MarketInfo(Symbol(),MODE_ASK);
   bool isBuy=(slp<bid);
   double entry=isBuy?ask:bid;
   if((isBuy && slp>=entry)||(!isBuy && slp<=entry)) return T("preview.slWrongSide");
   double dist=MathAbs(entry-slp);
   double rp; double lot=CalcLot(dist,rp);
   if(InpMaxLot>0 && lot>InpMaxLot){ lot=InpMaxLot; rp=RiskPctOf(Symbol(),lot,entry,slp); }
   double mn=MarketInfo(Symbol(),MODE_MINLOT);
   if(lot<mn || lot<=0) return TF("preview.lotBelowMin",isBuy?"BUY":"SELL",DoubleToString(dist/Pip(),0),UnitStr());
   double riskEur = rp/100.0*AccountEquity();   // rp = %% of equity -> € risk by definition
   // Format: "<DIR> <detail>" — DrawPanel splits at the first space to color the direction
   return StringFormat("%s %.2f Lot  %.0f %s  %s%%  %s%.0f", isBuy?"BUY":"SELL", lot, dist/Pip(), UnitStr(), Dec2(rp), CurSym(), riskEur);
}

//--- Panel (v0.24 Redesign: Fintech-Terminal-Look) ------------------
double Frac(double v,double lim){ if(lim<=0) return 0.0; double f=v/lim; if(f<0)f=0; if(f>1)f=1; return f; }
color  BarCol(double f){ if(f<0.5) return C'38,194,129'; if(f<0.8) return C'244,183,64'; return C'240,73,90'; }   // gruen / amber / rot

// thousands grouping (German: dot) for the equity display
string GroupInt(double v)
{
   string s=StringFormat("%.0f",MathAbs(v)); int n=StringLen(s); string o="";
   for(int i=0;i<n;i++){ if(i>0 && (n-i)%3==0) o=o+"."; o=o+StringSubstr(s,i,1); }
   return (v<0?"-":"")+o;
}
string CurSym(){ string c=AccountCurrency(); if(c=="EUR")return "€"; if(c=="USD")return "$"; if(c=="GBP")return "£"; return c+" "; }
string PeriodStr()
{
   int p=Period();
   if(p==1)return "M1"; if(p==5)return "M5"; if(p==15)return "M15"; if(p==30)return "M30";
   if(p==60)return "H1"; if(p==240)return "H4"; if(p==1440)return "D1"; if(p==10080)return "W1"; if(p==43200)return "MN";
   return "M"+IntegerToString(p);
}
// v0.25: Distanz-Einheit je Instrument (FX=Pips, Index/CFD/Metall=Pkt)
string UnitStr(){ return (((int)MarketInfo(Symbol(),MODE_PROFITCALCMODE))==0) ? "Pips" : "Pkt"; }
// v0.25: German decimal comma (display) — consistent with the dot thousands separator of the equity
// v0.53: panel texts DE/EN — generated automatically from the translation table.
//   T(key) returns the text in the configured language. An unknown key returns
//   the key itself: stands out in the panel at once instead of staying blank.
// v0.54: fill translated text with values. The table uses {0}/{1}/{2} instead of %s/%d,
//   so the order of the values stays free per language (in English it often differs).
string TF(string k,string a0="",string a1="",string a2="",string a3="")
{
   string s=T(k);
   StringReplace(s,"{0}",a0); StringReplace(s,"{1}",a1);
   StringReplace(s,"{2}",a2); StringReplace(s,"{3}",a3);   // v0.57: 4. Platzhalter (z.B. Reset-Stunde/Wochenstart alt->neu)
   return s;
}
string T(string k)
{
   bool en=(InpLang==LANG_EN);
   if(k=="block.autoTradingOff") return en?"Mamal: AutoTrading is OFF — no protection, no trade. (Enable 'AutoTrading' at the top)":"Mamal: AutoTrading ist AUS — Schutz inaktiv, kein Trade. (Button 'AutoTrading' oben aktivieren)";
   if(k=="block.baseUnsure") return en?"Mamal: Account base uncertain — no trade. Set InpInitialBalance to the real challenge start balance (R4b) or InpDayStartBase to the FTMO midnight base (R4), or wait for the day rollover.":"Mamal: Kontobasis unsicher/unbestaetigt — kein Trade. InpInitialBalance = echte Challenge-Startbalance setzen (R4b) bzw. InpDayStartBase = FTMO-Mitternachtsbasis (R4), oder Tageswechsel abwarten.";
   if(k=="block.cooldown") return en?"Mamal: Cooldown after losses — {0} min left, then free again (R5).":"Mamal: Cooldown nach Verlusten — noch {0} Min, dann wieder frei (R5).";
   if(k=="block.correlation") return en?"Mamal: Too much same-currency exposure — net {0}% over max {1}% (R17).":"Mamal: Zu viel gleiche Waehrung offen — Netto {0}% ueber max {1}% (R17).";
   if(k=="block.dayBudget") return en?"Mamal: Daily risk budget full — {0}% used today, no room for +{1}% (max {2}%). Done for today (R3).":"Mamal: Tages-Risiko-Budget voll — heute {0}% genutzt, kein Platz fuer +{1}% (max {2}%). Fuer heute Schluss (R3).";
   if(k=="block.heat") return en?"Mamal: Total risk limit — open {0}%, +{1}% would exceed max {2}%. Close open trades first (R12).":"Mamal: Gesamtrisiko-Limit — offen {0}%, +{1}% waere ueber max {2}%. Erst offene Trades schliessen (R12).";
   if(k=="block.ideaCap") return en?"Mamal: Idea limit full — {0} already carries {1}% risk (max {2}%). Close it first (R2).":"Mamal: Idee-Limit voll — {0} hat schon {1}% Risiko (max {2}%). Erst diese Position schliessen (R2).";
   if(k=="block.locked") return en?"Mamal: Locked (daily/weekly limit hit) — no new trades today.":"Mamal: Gesperrt (Tages-/Wochen-Limit erreicht) — heute keine neuen Trades.";
   if(k=="block.lotBelowMin") return en?"Mamal: Risk too small for the min lot size ({0}) — move the SL closer to price.":"Mamal: Risiko zu klein fuer die kleinste Lot-Groesse ({0}) — SL naeher an den Preis setzen.";
   if(k=="block.maxLossWarn") return en?"Mamal: Close to the max-loss limit ({0}% of {1}%) — safety buffer, no new trades (R4b).":"Mamal: Nahe der Max-Verlust-Grenze ({0}% von {1}%) — Sicherheitspuffer, keine neuen Trades (R4b).";
   if(k=="block.minGap") return en?"Mamal: Minimum gap between trades — {0} s left (R14).":"Mamal: Mindestpause zwischen Trades — noch {0} s (R14).";
   if(k=="block.noSlLine") return en?"Mamal: No SL line — set the red SL line first (drag or click 3x in the zone).":"Mamal: Keine SL-Linie — erst die rote SL-Linie setzen (ziehen oder 3x in die Zone klicken).";
   if(k=="block.offSession") return en?"Mamal: Outside session / news block — no trade (R16).":"Mamal: Ausserhalb Handelszeit / News-Sperre — kein Trade (R16).";
   if(k=="block.revenge") return en?"Mamal: Revenge block — no counter-trade right after a loss (R25).":"Mamal: Revenge-Sperre — kein Gegen-Trade direkt nach einem Verlust (R25).";
   if(k=="block.slBrokerStop") return en?"Mamal: SL too close to price (broker minimum) — move the SL further away.":"Mamal: SL zu nah am Preis (Broker-Mindestabstand) — SL etwas weiter weg setzen.";
   if(k=="block.slMinPips") return en?"Mamal: SL too close — at least {0} pips distance needed (R15).":"Mamal: SL zu nah — mindestens {0} Pips Abstand noetig (R15).";
   if(k=="block.slSideBuy") return en?"Mamal: For a BUY the SL line must sit BELOW the current price.":"Mamal: Fuer einen BUY muss die SL-Linie UNTER dem aktuellen Preis liegen.";
   if(k=="block.slSideSell") return en?"Mamal: For a SELL the SL line must sit ABOVE the current price.":"Mamal: Fuer einen SELL muss die SL-Linie UEBER dem aktuellen Preis liegen.";
   if(k=="block.targetHit") return en?"Mamal: Daily target hit — lock in the gain, no new trades today (R13).":"Mamal: Tagesziel erreicht — Gewinn sichern, heute keine neuen Trades mehr (R13).";
   if(k=="block.weekRiskMissing") return en?"Mamal: Type this week's risk in the panel and confirm with SET — then trading is open.":"Mamal: Bitte zuerst das Wochen-Risiko im Panel eintippen und mit SETZEN bestaetigen — danach ist Handeln frei.";
   if(k=="box.header.blocked") return en?"NOT POSSIBLE — REASON:":"NICHT MOEGLICH — GRUND:";
   if(k=="box.header.info") return en?"NOTE:":"HINWEIS:";
   if(k=="box.header.plan") return en?"NEXT TRADE · SL LINE":"NAECHSTER TRADE · SL-LINIE";
   if(k=="btn.buy") return en?"BUY":"BUY";
   if(k=="btn.chart50") return en?"CHART 50%":"CHART 50%";
   if(k=="btn.chartClose") return en?"CHART CLOSE":"CHART CLOSE";
   if(k=="btn.cockpit") return en?"COCKPIT: RULES & PROGRESS":"COCKPIT: REGELN & FORTSCHRITT";
   if(k=="btn.full50") return en?"FULL 50%":"FULL 50%";
   if(k=="btn.fullClose") return en?"FULL CLOSE":"FULL CLOSE";
   if(k=="btn.riskFree") return en?"RISK FREE — SL TO BREAK-EVEN":"RISK FREE — SL AUF BREAK-EVEN";
   if(k=="btn.sell") return en?"SELL":"SELL";
   if(k=="btn.setRisk") return en?"SET":"SETZEN";
   if(k=="close.halved") return en?"halved":"halbiert";
   if(k=="close.none") return en?"Panel close: no open position.":"Panel-Close: keine offene Position.";
   if(k=="close.result") return en?"Panel close: {0} closed":"Panel-Close: {0} geschlossen";
   if(k=="fomo.arm") return en?"Mamal: in {0} s click {1} again.":"Mamal: in {0} s nochmal {1} klicken.";
   if(k=="header.candleTime") return en?"Bar {0}":"Kerze {0}";
   if(k=="header.equity") return en?"EQUITY":"KAPITAL";
   if(k=="header.spread") return en?"Spread {0}":"Spread {0}";
   if(k=="info.cockpit") return en?"Cockpit opens in the browser. If not: go to http://localhost:{0} (start.bat must run).":"Cockpit oeffnet im Browser. Falls nicht: http://localhost:{0} aufrufen (start.bat muss laufen).";
   if(k=="info.tradeContextBusy") return en?"Mamal: Trade context busy — please click again shortly.":"Mamal: Trade-Kontext belegt — bitte gleich nochmal klicken.";
   if(k=="lock.cooldownStreak") return en?"Mamal: {0} losses in a row -> COOLDOWN {1} min (R5).":"Mamal: {0} Verluste in Folge -> COOLDOWN {1} min (R5).";
   if(k=="lock.dailyLoss") return en?"Mamal: DAILY-LOSS LOCK ({0}%).":"Mamal: TAGESVERLUST-SPERRE ({0}%).";
   if(k=="lock.dayLockStreak") return en?"Mamal: {0} losses in a row -> DAY LOCK (R6).":"Mamal: {0} Verluste in Folge -> TAGESSPERRE (R6).";
   if(k=="lock.giveback") return en?"Mamal: GIVEBACK GUARD — from peak +{0}% to +{1}% -> day locked (R13).":"Mamal: GIVEBACK-SCHUTZ — vom Hoch +{0}% auf +{1}% -> Tag gesperrt (R13).";
   if(k=="lock.maxLoss") return en?"Mamal: MAX-LOSS LOCK ({0}%).":"Mamal: MAX-LOSS-SPERRE ({0}%).";
   if(k=="lock.selfLock") return en?"Mamal: Day closed — self-lock until server midnight. Good call.":"Mamal: Tag beendet — Selbstsperre bis Server-Mitternacht. Gute Entscheidung.";
   if(k=="lock.targetReached") return en?"Mamal: DAILY TARGET +{0}% hit — no new trades today (R13).":"Mamal: TAGESZIEL +{0}% erreicht — keine neuen Trades heute (R13).";
   if(k=="lock.weekLimit") return en?"Mamal: WEEKLY LOSS LIMIT {0}% -> week locked (R18).":"Mamal: WOCHEN-VERLUSTLIMIT {0}% -> Woche gesperrt (R18).";
   if(k=="meter.dailyLoss") return en?"DAILY LOSS":"TAGESVERLUST";
   if(k=="meter.totalLoss") return en?"TOTAL LOSS":"GESAMTVERLUST";
   if(k=="preview.confirm") return en?"CONFIRM: press {0} again":"BESTAETIGEN: nochmal {0}";
   if(k=="preview.lotBelowMin") return en?"{0} Lot<min ({1} {2})":"{0} Lot<min ({1} {2})";
   if(k=="preview.noSlLine") return en?"Drag the SL line or click 3x in the zone…":"SL-Linie ziehen oder 3x in die Zone klicken…";
   if(k=="preview.slClicks") return en?"SL zone {0} — click {1}x more to set":"SL-Zone {0} — noch {1}x klicken zum Setzen";
   if(k=="preview.slWrongSide") return en?"SL on the wrong side":"SL auf falscher Seite";
   if(k=="risk.label") return en?"RISK PER TRADE":"RISIKO JE TRADE";
   if(k=="risk.set.confirmed") return en?"Weekly risk: {0}% per trade — FIXED for this week.":"Wochen-Risiko: {0}% pro Trade — FEST fuer diese Woche.";
   if(k=="risk.set.invalid") return en?"Mamal: Type a value between 0.01 and 1.00 % (received: \"{0}\").":"Mamal: Bitte einen Wert zwischen 0,01 und 1,00 % eintippen (erhalten: \"{0}\").";
   if(k=="risk.set.pending") return en?"Change to {0}% queued — takes effect next week.":"Aenderung auf {0}% vorgemerkt — greift ab naechster Woche.";
   if(k=="risk.sub.fixed") return en?"{0} per trade · fixed for this week":"{0} je Trade · fest fuer diese Woche";
   if(k=="risk.sub.pending") return en?"{0} per trade · from Mon {1} %":"{0} je Trade · ab Montag {1} %";
   if(k=="risk.sub.unset") return en?"Type the weekly value and press SET — then trading is open":"Wochenwert eintippen und SETZEN druecken — dann ist Handeln frei";
   if(k=="risk.week.renew") return en?"Mamal: New week — set your weekly risk again before trading (last week: {0}%).":"Mamal: Neue Woche — Wochen-Risiko vor dem ersten Trade erneut festlegen (zuletzt {0}%).";
   if(k=="riskfree.none") return en?"Risk-Free: no matching position.":"Risk-Free: keine passende Position.";
   if(k=="riskfree.result") return en?"Risk-Free: {0} to break-even":"Risk-Free: {0} auf Break-Even";
   if(k=="status.active") return en?"LIVE":"AKTIV";
   if(k=="status.baseWarn") return en?"BASE UNCERTAIN":"BASIS UNSICHER";
   if(k=="status.cooldown") return en?"COOLDOWN":"COOLDOWN";
   if(k=="status.dayLock") return en?"DAY LOCKED":"TAG GESPERRT";
   if(k=="status.guardOff") return en?"GUARD OFF":"SCHUTZ AUS";
   if(k=="status.setWeekRisk") return en?"SET RISK":"RISIKO FESTLEGEN";
   if(k=="btn.set") return en?"SET":"SETZEN";
   if(k=="status.hardLock") return en?"MAX-LOSS LOCKED":"MAX-LOSS GESPERRT";
   if(k=="status.maxLossWarn") return en?"MAX-LOSS WARNING":"MAX-LOSS WARNUNG";
   if(k=="status.offSession") return en?"OFF SESSION":"AUSSER SESSION";
   if(k=="status.setRisk") return en?"SET RISK":"RISIKO FESTLEGEN";
   if(k=="status.targetHit") return en?"TARGET HIT":"ZIEL ERREICHT";
   if(k=="status.weekLock") return en?"WEEK LOCKED":"WOCHE GESPERRT";
   if(k=="test.label") return en?"TEST HARNESS (DEMO)":"TEST-HARNESS (NUR DEMO)";
   if(k=="tile.blocked") return en?"BLOCKED":"ABGELEHNT";
   if(k=="tile.limit") return en?"LIMIT":"LIMIT";
   if(k=="tile.limit.value") return en?"{0}% left":"{0}% frei";
   if(k=="tile.risk") return en?"RISK":"RISIKO";
   if(k=="tile.streak") return en?"RUN":"SERIE";
   if(k=="tilt.burst") return en?"STOP — 3 rejections in 1 min. Step away briefly.":"STOPP — 3 Ablehnungen in 1 Min. Kurz weg vom Chart.";
   if(k=="misc.fragmentFomoArm") return en?",IntegerToString(InpFomoSeconds),isBuy?":",IntegerToString(InpFomoSeconds),isBuy?";
   if(k=="misc.fragmentPanelSig") return en?")); g_panelSig=":")); g_panelSig=";
   if(k=="time.dayResetHourActive") return en?"Mamal: Daily reset hour now active: {0}:00 (server time).":"Mamal: Tagesreset-Stunde jetzt aktiv: {0} Uhr (Server).";
   if(k=="base.challengeBaseRollover") return en?"Mamal: Challenge base updated at day rollover: {0}.":"Mamal: Challenge-Basis zum Tageswechsel aktualisiert: {0}.";
   if(k=="cfg.weekRiskPendingCancelled") return en?"Pending change cancelled — stays fixed at {0}% for this week.":"Vormerkung aufgehoben — bleibt fest bei {0}% fuer diese Woche.";
   if(k=="cfg.weekRiskAlreadySet") return en?"Weekly risk is already {0}% — fixed for this week.":"Wochen-Risiko ist bereits {0}% — fest fuer diese Woche.";
   if(k=="cfg.tightenedImmediately") return en?"Mamal: {0} tightened immediately to {1} (loosening only from tomorrow).":"Mamal: {0} sofort verschaerft auf {1} (Lockern erst morgen).";
   if(k=="cfg.cockpitDisabled") return en?"Mamal: InpCockpit=false — NO live data is being written! Enable it in the EA inputs.":"Mamal: InpCockpit=false — es werden KEINE Live-Daten geschrieben! In den EA-Eingaben aktivieren.";
   if(k=="tamper.lockstateCorrupt") return en?"Mamal: LOCKSTATE file corrupted/tampered -> FAIL-CLOSED (locked for today).":"Mamal: LOCKSTATE-Datei beschaedigt/manipuliert -> FAIL-CLOSED (heute gesperrt).";
   if(k=="why.r4") return en?"daily loss limit reached (R4)":"Tagesverlust-Limit erreicht (R4)";
   if(k=="why.r6") return en?"too many losses in a row (R6)":"zu viele Verluste in Folge (R6)";
   if(k=="why.r13") return en?"gave back too much of the day's high (R13)":"zu viel vom Tageshoch abgegeben (R13)";
   if(k=="why.self") return en?"you ended the day yourself":"du hast den Tag selbst beendet";
   if(k=="why.history") return en?"a closed trade was not visible in the history":"ein geschlossener Trade war in der Historie nicht sichtbar";
   if(k=="why.tamper") return en?"lockstate file missing or tampered with":"Lockstate-Datei fehlt oder wurde manipuliert";
   if(k=="why.test") return en?"set by the test button":"per Test-Knopf gesetzt";
   if(k=="backfill.done") return en?"Mamal: {0} closed trades added from the account history (net {1}). You can switch InpHistoryBackfill off again.":"Mamal: {0} geschlossene Trades aus der Kontohistorie nachgetragen (Netto {1}). InpHistoryBackfill kann wieder aus.";
   if(k=="backfill.empty") return en?"Mamal: nothing added. History holds {0} entries, {1} of them outside this tool's magic. Set the History tab to \"All History\" and check InpMagic.":"Mamal: nichts nachgetragen. Die Historie hat {0} Eintraege, davon {1} ausserhalb der Magic dieses Tools. History-Tab auf \"Gesamte Historie\" stellen und InpMagic pruefen.";
   if(k=="why.maxloss") return en?"total loss limit reached (R4b)":"Gesamtverlust-Grenze erreicht (R4b)";
   if(k=="why.week") return en?"weekly loss limit reached (R18)":"Wochen-Verlustlimit erreicht (R18)";
   if(k=="tamper.lockstateMissing") return en?"Mamal: LOCKSTATE file is GONE (deleted?) -> FAIL-CLOSED (locked for today).":"Mamal: LOCKSTATE-Datei ist WEG (geloescht?) -> FAIL-CLOSED (heute gesperrt).";
   if(k=="tamper.hardLockRestored") return en?"Mamal: Hard-Lock restored from the Lockstate file.":"Mamal: Hard-Lock aus Lockstate-Datei wiederhergestellt.";
   if(k=="tamper.lockRestoredWarning") return en?"Mamal: WARNING — active lock restored from the Lockstate file (RG_* GlobalVariables deleted?). Fail-closed.":"Mamal: WARNUNG — aktive Sperre aus der Lockstate-Datei wiederhergestellt (RG_*-GlobalVariables geloescht?). Fail-closed.";
   if(k=="tamper.journalLockRestored") return en?"Active lock restored from file (GV deletion detected)":"Aktive Sperre aus Datei wiederhergestellt (GV-Loeschung erkannt)";
   if(k=="tamper.lockstateReconciled") return en?"Mamal: Lockstate file reconciled (most restrictive state applied).":"Mamal: Lockstate-Datei abgeglichen (restriktivster Zustand uebernommen).";
   if(k=="cfg.magicMismatchMaster") return en?"Mamal: WARNING — InpMagic {0} differs from the master ({1})! Trades on this chart would be UNGUARDED. Apply the same preset to all charts.":"Mamal: ACHTUNG — InpMagic {0} weicht vom Master ({1}) ab! Trades dieses Charts waeren UNBEWACHT. Gleiches Preset auf alle Charts.";
   if(k=="watchdog.noMasterActive") return en?"Mamal: NO master active — enforcement + close evaluation are HALTED. Re-attach the EA (F7/recompile).":"Mamal: KEIN Master aktiv — Enforcement + Close-Wertung stehen STILL. EA neu auflegen (F7/Recompile).";
   if(k=="base.reloaded") return en?"Mamal: Account base reloaded: {0} ({1}).":"Mamal: Kontobasis nachgeladen: {0} ({1}).";
   if(k=="cfg.weekRiskNowActive") return en?"Mamal: Weekly risk now active: {0}% per trade (pending change applied).":"Mamal: Wochen-Risiko jetzt aktiv: {0}% pro Trade (vorgemerkte Aenderung).";
   if(k=="watchdog.autoTradingOff") return en?"Mamal: WARNING — AutoTrading OFF! Protection inactive ({0}. time today). Lock periods are EXTENDED by this downtime.":"Mamal: WARNUNG — AutoTrading AUS! Schutz inaktiv (heute {0}.-mal). Sperrfristen werden um diese Zeit VERLAENGERT.";
   if(k=="misc.fragmentJournalArgs") return en?",0,0,0,0,0,StringFormat(":",0,0,0,0,0,StringFormat(";
   if(k=="watchdog.autoTradingOn") return en?"Mamal: AutoTrading back ON — lock periods extended by {0} s (protection downtime).":"Mamal: AutoTrading wieder AN — Sperrfristen um {0} s verlaengert (Ausfallzeit des Schutzes).";
   if(k=="watchdog.historyTradeMissing") return en?"Mamal: WARNING — a closed trade is NOT visible in the account history (History tab filtered?). Loss streak/daily budget cannot be counted -> FAIL-CLOSED. Set the account history to 'All History'.":"Mamal: WARNUNG — ein geschlossener Trade ist in der Kontohistorie NICHT sichtbar (History-Tab gefiltert?). Verlustserie/Tagesbudget koennen nicht zaehlen -> FAIL-CLOSED. Kontohistorie auf 'Gesamte Historie' stellen.";
   if(k=="watchdog.foreignPositionsWhileLocked") return en?"Mamal: WARNING locked, but {0} foreign/manual position(s) open — the Watchdog does NOT close them (Scope={1})! Close them manually, otherwise they keep breaching the limit.":"Mamal: WARNUNG gesperrt, aber {0} fremde/manuelle Position(en) offen — Watchdog schliesst sie NICHT (Scope={1})! Manuell schliessen, sonst reissen sie das Limit weiter.";
   if(k=="time.rolloverNotConfirmed") return en?"Mamal: {0} per PC clock, but BROKER time does NOT confirm it — no reset. (PC clock changed or no fresh ticks.) State is preserved.":"Mamal: {0} laut PC-Uhr, aber die BROKER-Zeit bestaetigt ihn NICHT — kein Reset. (PC-Uhr verstellt oder keine frischen Ticks.) Zustand bleibt erhalten.";
   if(k=="cfg.fundedWatchScopeForced") return en?"Mamal: FUNDED-MODE -> WatchScope forced to TOOL_ONLY (no foreign positions).":"Mamal: FUNDED-MODE -> WatchScope hart auf TOOL_ONLY (keine fremden Positionen).";
   if(k=="cfg.fundedTestModeOff") return en?"Mamal: FUNDED-MODE -> TestMode force-disabled.":"Mamal: FUNDED-MODE -> TestMode hart deaktiviert.";
   if(k=="cfg.rrClampedToMinRR") return en?"Mamal: InpRR ({0}) < InpMinRR ({1}) -> clamped up to {2} (otherwise the auto TP would violate R8) (P1).":"Mamal: InpRR ({0}) < InpMinRR ({1}) -> hochgeklemmt auf {2} (sonst verletzt der Auto-TP R8) (P1).";
   if(k=="cfg.magicInvalid") return en?"Mamal: InpMagic<=0 is invalid — set to 990201 (panel trades need a unique Magic).":"Mamal: InpMagic<=0 ungueltig — auf 990201 gesetzt (Panel-Trades brauchen eine eindeutige Kennung).";
   if(k=="base.initialBalanceImplausible") return en?"Mamal: InpInitialBalance={0} is implausibly small versus Balance {1} — likely a typo (dot/comma). Enter it WITHOUT thousands separators (e.g. {2}). Input is ignored.":"Mamal: InpInitialBalance={0} ist unplausibel klein ggü. Balance {1} — vermutlich Tippfehler (Punkt/Komma). Bitte OHNE Tausender-Trennzeichen eingeben (z.B. {2}). Eingabe wird ignoriert.";
   if(k=="base.initialBalanceLoweringIgnored") return en?"Mamal: Lowering InpInitialBalance ({0} -> {1}) IGNORED intraday — base stays {2} (increases apply at once; lowering only at the daily rollover).":"Mamal: InpInitialBalance-Absenkung ({0} -> {1}) intraday IGNORIERT — Basis bleibt {2} (nur Erhoehung sofort; Absenken erst zum Tageswechsel).";
   if(k=="base.autoFromBalance") return en?"Mamal: Auto base = current Balance ({0}). For the exact challenge base: set the account history tab to 'All History' or set InpInitialBalance.":"Mamal: Auto-Basis = aktuelle Balance ({0}). Fuer die exakte Challenge-Basis: Kontohistorie-Tab auf 'Gesamte Historie' stellen oder InpInitialBalance setzen.";
   if(k=="base.missingFailClosed") return en?"Mamal: NO valid account base (g_initialBalance<=0) — FAIL-CLOSED, no new trades. Set InpInitialBalance or check the connection.":"Mamal: KEINE gueltige Kontobasis (g_initialBalance<=0) — FAIL-CLOSED, keine neuen Trades. InpInitialBalance setzen oder Verbindung pruefen.";
   if(k=="base.maxLossBaseMismatch") return en?"Mamal: WARNING max-loss base {0} deviates strongly from the account base {1} — R4b calculates against {2}! Check/set InpInitialBalance.":"Mamal: ACHTUNG Max-Loss-Basis {0} weicht stark von Kontobasis {1} ab — R4b rechnet gegen {2}! InpInitialBalance pruefen/setzen.";
   if(k=="time.resetInputsPending") return en?"Mamal: InpDayResetHour/InpWeekStartDay changed ({0}/{1} -> {2}/{3}) — takes effect at the next real rollover only (no intraday wipe of base/streak/lock).":"Mamal: InpDayResetHour/InpWeekStartDay geaendert ({0}/{1} -> {2}/{3}) — wirkt erst zum naechsten echten Rollover (kein Intraday-Wipe von Basis/Serie/Sperre).";
   if(k=="base.dayStartBaseImplausible") return en?"Mamal: InpDayStartBase={0} is implausibly small versus Balance {1} — typo (dot/comma)? Enter it WITHOUT separators (e.g. {2}). Ignored -> daily base stays UNCERTAIN.":"Mamal: InpDayStartBase={0} ist unplausibel klein ggü. Balance {1} — Tippfehler (Punkt/Komma)? OHNE Trennzeichen eingeben (z.B. {2}). Wird ignoriert -> Tagesbasis bleibt UNSICHER.";
   if(k=="base.dayStartBaseManual") return en?"Mamal: Manual FTMO daily base applied ({0}).":"Mamal: Manuelle FTMO-Tagesbasis uebernommen ({0}).";
   if(k=="cfg.timerSecondsInvalid") return en?"Mamal: InpTimerSeconds invalid -> set to 1 s.":"Mamal: InpTimerSeconds ungueltig -> auf 1 s gesetzt.";
   if(k=="cfg.timerSecondsCapped") return en?"Mamal: InpTimerSeconds > 60 -> capped to 60 s (enforcement needs a tight cycle).":"Mamal: InpTimerSeconds > 60 -> auf 60 s begrenzt (Enforcement braucht einen engen Takt).";
   if(k=="watchdog.timerFailed") return en?"Mamal: WARNING EventSetTimer FAILED — tick-independent enforcement is inactive! Re-attach the EA.":"Mamal: ACHTUNG EventSetTimer FEHLGESCHLAGEN — tickunabhaengiges Enforcement inaktiv! EA neu anhaengen.";
   if(k=="cfg.watchScopeAllPositions") return en?"Mamal: WARNING WatchScope=ALL_POSITIONS touches FOREIGN positions — Demo/Debug ONLY, NOT real/funded!":"Mamal: ACHTUNG WatchScope=ALL_POSITIONS fasst FREMDE Positionen an — NUR Demo/Debug, NICHT Real/Funded!";
   if(k=="cfg.r22DisabledMagicZero") return en?"Mamal: R22 DISABLED — InpMagic=0 makes own panel trades indistinguishable from manual ones. Set Magic!=0 (default 990201), otherwise R22 would close its own trades.":"Mamal: R22 DEAKTIVIERT — InpMagic=0 macht eigene Panel-Trades von manuellen ununterscheidbar. Magic!=0 setzen (Default 990201), sonst wuerde R22 die eigenen Trades schliessen.";
   if(k=="cfg.r22ManualOrdersOpen") return en?"Mamal: R22 active — {0} manual order(s) open; they will be closed within the next seconds (no grandfathering).":"Mamal: R22 aktiv — {0} manuelle Order(s) offen; sie werden in den naechsten Sekunden geschlossen (kein Bestandsschutz).";
   if(k=="cfg.r22PanelOnly") return en?"Mamal: R22 active — panel trades only; manual/mobile orders are reverted immediately.":"Mamal: R22 aktiv — nur Panel-Trades erlaubt; manuelle/Handy-Orders werden umgehend zurueckgenommen.";
   if(k=="cfg.r22FundedNote") return en?"Mamal: Note — R22 also applies in FUNDED-MODE: there the EA also closes positions it did not open itself. Confirm this with your prop firm.":"Mamal: Hinweis — R22 greift auch im FUNDED-MODE: der EA schliesst dort auch Positionen, die er nicht selbst geoeffnet hat. Mit der Prop-Firm abgleichen.";
   if(k=="cfg.r22ScopeNote") return en?"Mamal: Note — WatchScope=TOOL_PLUS_MANUAL has no effect with R22 (manual trades are closed anyway).":"Mamal: Hinweis — WatchScope=TOOL_PLUS_MANUAL ist mit R22 wirkungslos (manuelle Trades werden ohnehin geschlossen).";
   if(k=="misc.artifactJournalBlockedArgs") return en?"\",Symbol(),dir,0,0,0,0,0,\"":"\",Symbol(),dir,0,0,0,0,0,\"";
   if(k=="misc.artifactBlockCooldownArgs") return en?"\",IntegerToString(remm))); Journal(\"":"\",IntegerToString(remm))); Journal(\"";
   if(k=="misc.artifactBlockMinGapArgs") return en?"\",IntegerToString(rem))); Journal(\"":"\",IntegerToString(rem))); Journal(\"";
   if(k=="misc.artifactJournalSlSideArgs") return en?"\",Symbol(),dir,0,entry,slp,0,0,\"":"\",Symbol(),dir,0,entry,slp,0,0,\"";
   if(k=="misc.artifactJournalLotRiskArgs") return en?"\",Symbol(),dir,lot,entry,slp,0,rp,\"":"\",Symbol(),dir,lot,entry,slp,0,rp,\"";
   if(k=="misc.artifactBlockIdeaCapArgs") return en?"\",Symbol(),DoubleToString(ideaR,2),DoubleToString(ic,2))); Journal(\"":"\",Symbol(),DoubleToString(ideaR,2),DoubleToString(ic,2))); Journal(\"";
   if(k=="misc.artifactJournalDayBudgetArgs") return en?"\",Symbol(),dir,lot,entry,slp,0,r3rp,\"":"\",Symbol(),dir,lot,entry,slp,0,r3rp,\"";
   if(k=="misc.artifactBlockHeatArgs") return en?"\",DoubleToString(heat,2),DoubleToString(rp,2),DoubleToString(hc,2))); Journal(\"":"\",DoubleToString(heat,2),DoubleToString(rp,2),DoubleToString(hc,2))); Journal(\"";
   if(k=="misc.tradeContextBusy") return en?"Mamal: trade context is busy right now — please click again.":"Mamal: Handelskontext gerade belegt — bitte erneut klicken.";
   if(k=="misc.orderSendFailed") return en?"Mamal: OrderSend error {0} (lot {1})":"Mamal: OrderSend-Fehler {0} (Lot {1})";
   if(k=="misc.artifactJournalOrderSendArgs") return en?"\",Symbol(),dir,lot,pxN,slN,tpN,rp,StringFormat(\"":"\",Symbol(),dir,lot,pxN,slN,tpN,rp,StringFormat(\"";
   if(k=="misc.artifactTestCooldownSetup") return en?"\"){ GlobalVariableSet(GV_COOLDOWN,(double)(SrvTime()+EffCooldownMin()*60)); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"":"\"){ GlobalVariableSet(GV_COOLDOWN,(double)(SrvTime()+EffCooldownMin()*60)); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"";
   if(k=="misc.artifactTestDaylockSetup") return en?"\"){ GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"":"\"){ GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"";
   if(k=="misc.artifactTestMaxlockSetup") return en?"\"){ GlobalVariableSet(GV_HARD_LOCK,1); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"":"\"){ GlobalVariableSet(GV_HARD_LOCK,1); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"";
   if(k=="misc.artifactTestRevengeSetup") return en?"\"){ SetRevenge(Symbol(),OP_BUY); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"":"\"){ SetRevenge(Symbol(),OP_BUY); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(\"";
   if(k=="test.lockstateCorrupted") return en?"TEST: Lockstate corrupted + reconcile -> fail-closed (day lock) expected.":"TEST: Lockstate beschaedigt + Reconcile -> fail-closed (Tagessperre) erwartet.";
   if(k=="test.resetRejected") return en?"TEST: reset REJECTED — {0}. Real locks stay in place; reset only clears locks set by the test buttons themselves, and only on a demo account.":"TEST: Reset ABGELEHNT — {0}. Echte Sperren bleiben; Reset entsperrt nur selbst per Test-Button gesetzte Sperren auf einem Demo-Konto.";
   if(k=="test.resetReasonNoDemo") return en?"not a demo account":"not a demo account";
   if(k=="test.resetReasonNoTestLock") return en?"no test lock active":"no test lock active";
   if(k=="test.locksReset") return en?"TEST: test locks reset (demo). Hard-Lock stays.":"TEST: Test-Sperren zurueckgesetzt (Demo). Hard-Lock bleibt.";
   if(k=="test.cooldown") return en?"TEST: cooldown set (R5).":"TEST: Cooldown gesetzt (R5).";
   if(k=="test.dayLock") return en?"TEST: daily lock set (R4) -> SafeCloseAll expected.":"TEST: Tagessperre gesetzt (R4) -> SafeCloseAll erwartet.";
   if(k=="test.maxLock") return en?"TEST: MAX-LOSS lock set (R4b) -> SafeCloseAll expected. (Reset does NOT clear the hard lock — delete it via F3 on demo.)":"TEST: MAX-LOSS-Sperre gesetzt (R4b) -> SafeCloseAll erwartet. (Reset entsperrt den Hard-Lock NICHT — auf Demo per F3 loeschen.)";
   if(k=="test.revenge") return en?"TEST: revenge (BUY loss) set (R25) -> counter-SELL blocked, survives restart.":"TEST: Revenge (BUY-Verlust) gesetzt (R25) -> Gegen-SELL gesperrt, ueberlebt Restart.";
   return k;
}
string Dec2(double v){ string s=StringFormat("%.2f",v); StringReplace(s,".",","); return s; }
// v0.25: hard-limit the panel text (no overflow onto the chart); the full text stays in the log
string Clip(string s,int mx){ return (StringLen(s)<=mx) ? s : (StringSubstr(s,0,mx-1)+"…"); }
// v0.37: simple word wrap for the message box — MT4 OBJ_LABEL does not wrap by itself, so split the text into maxLines lines
//   of perLine characters each. If it does not all fit, the last line gets a "…". Result in out[0..maxLines-1].
void WrapText(string s,int perLine,int maxLines,string &out[])
{
   ArrayResize(out,maxLines); for(int i=0;i<maxLines;i++) out[i]="";
   string words[]; int wc=StringSplit(s,(ushort)' ',words);
   int line=0; string cur="";
   for(int w=0; w<wc; w++)
   {
      if(StringLen(words[w])==0) continue;                                       // Doppel-Spaces ueberspringen
      string cand=(StringLen(cur)==0) ? words[w] : (cur+" "+words[w]);
      if(StringLen(cand)<=perLine){ cur=cand; continue; }
      if(line>=maxLines-1)                                                       // last line: append the remainder + Clip sets the "…"
      {
         string rest=cur;
         for(int r=w;r<wc;r++) rest=(StringLen(rest)==0)?words[r]:(rest+" "+words[r]);
         out[line]=Clip(rest,perLine);
         return;
      }
      out[line]=Clip(cur,perLine); line++; cur=words[w];
   }
   if(StringLen(cur)>0 && line<maxLines) out[line]=Clip(cur,perLine);
}

// v0.37: scale the panel geometry. With Windows scaling >100% MT4 renders the FONT bigger but leaves the pixel
//   coordinates unscaled -> overlap. Solution: multiply all positions/sizes (NOT the font size, which MT4 scales
//   itself) by the same factor. Applied centrally in the 5 drawing helpers.
double PScale()
{
   double s=InpPanelScale;
   if(s<=0)   // v0.37: AUTO — derive it from the screen DPI (96 dpi = 100%, 144 = 150%)
   {
      int dpi=(int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
      s = (dpi>0) ? (dpi/96.0) : 1.0;   // DPI not available -> neutral
      if(s<1.0) s=1.0;                  // AUTO nie unter 100% (kleine DPI-Werte sollen nichts schrumpfen)
   }
   // v0.48-fix: a MANUALLY set value is explicitly allowed to shrink as well (0.7 = 70%).
   //   Before, the 1.0 lower bound clamped away every wish for a smaller panel.
   if(s<0.5) s=0.5; if(s>3.0) s=3.0;
   // v0.46: auto-fit — scales the panel down if it would otherwise be taller than the chart window.
   //   Prevents cut-off buttons on small charts / a split screen.
   if(InpPanelAutoFit)
   {
      int ph=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      if(ph>120)
      {
         double need=(PanelH()+28)*s;                     // Panel + Rand oben/unten (PanelH rechnet unskaliert)
         if(need>ph) s=s*((double)ph/need);
         if(s<0.6) s=0.6;                                  // must not get unreadably small
      }
   }
   return s;
}
double SScale(){ double v=InpShapeScale; if(v<0.5)v=0.5; if(v>2.0)v=2.0; return v; }   // v0.46: Formgroesse
double FScale(){ double v=InpFontScale;  if(v<0.5)v=0.5; if(v>2.0)v=2.0; return v; }   // v0.46: Schriftgroesse
int    PS(int v){ return (int)MathRound(v*PScale()*SScale()); }
int    PF(int v){ int r=(int)MathRound(v*PScale()*FScale()); return (r<6?6:r); }        // Schriftgrad (nie unter 6 pt)
void Lbl(string name,int x,int y,string text,color col,int size,string font="Tahoma")
{
   if(ObjectFind(0,name)<0){ ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false); }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PS(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PS(y));
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,PF(size));   // v0.46: Schrift getrennt skalierbar
   ObjectSetString (0,name,OBJPROP_FONT,font);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
}
// rectangle with a separate border color (for card edge / chips)
void RectB(string name,int x,int y,int w,int h,color bg,color border)
{
   if(ObjectFind(0,name)<0){ ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false); }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PS(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PS(y));
   ObjectSetInteger(0,name,OBJPROP_XSIZE,PS(w));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,PS(h));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
}
// right-aligned label (anchored right) for numbers/values
void LblR(string name,int xRight,int y,string text,color col,int size,string font="Tahoma")
{
   if(ObjectFind(0,name)<0){ ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false); }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PS(xRight));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PS(y));
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,PF(size));   // v0.46: Schrift getrennt skalierbar
   ObjectSetString (0,name,OBJPROP_FONT,font);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
}
void Rect(string name,int x,int y,int w,int h,color col)
{
   if(ObjectFind(0,name)<0){ ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false); }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PS(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PS(y));
   ObjectSetInteger(0,name,OBJPROP_XSIZE,PS(w));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,PS(h));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,col);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
}
// v0.49: input field for the weekly risk. The text is rewritten ONLY when the
//   valid value has changed — otherwise DrawPanel (2x/second) would constantly erase the user's
//   input from under their fingers while typing.
// v0.52: determine the candle third — in which section of the running candle was the fill?
//   0 = erstes Drittel (frueh, gruen), 1 = zweites (orange), 2 = letztes (spaet/hinterherlaufend, rot).
//   Meaning: entries in the last third are often reactions to a move that has already run.
int CandleThird(datetime t)
{
   int per=PeriodSeconds(); if(per<=0) return 0;
   int el=(int)(t%per); if(el<0) el=0;
   int th=(el*3)/per; if(th>2) th=2;
   return th;
}
string CandleThirdTag(datetime t){ return StringFormat("K%d/3",CandleThird(t)+1); }   // "K1/3".."K3/3" (maschinenlesbar fuers Cockpit)

// v0.52: countdown right next to the running candle (like a chart indicator), in addition to the panel.
//   Anchor: next candle slot at the height of the current price -> it rides along right beside the candle.
void DrawCandleClock()
{
   string n=PFX+"cclock";
   if(!InpCandleTimeOnChart || !InpShowCandleTime)
   { if(ObjectFind(0,n)>=0) ObjectDelete(0,n); return; }
   int rest=(int)(Time[0]+PeriodSeconds()-TimeCurrent()); if(rest<0) rest=0;
   int per=PeriodSeconds(); if(per<=0) per=60;
   // color by ELAPSED third — same logic as the trade logging
   int th=CandleThird(TimeCurrent());
   color c=(th==0)?C'61,220,146':((th==1)?C'244,183,64':C'240,73,90');
   string txt=StringFormat("%02d:%02d",rest/60,rest%60);
   double price=(MarketInfo(Symbol(),MODE_BID)>0)?MarketInfo(Symbol(),MODE_BID):Close[0];
   datetime anchor=Time[0]+per;                       // one slot right of the running candle
   if(ObjectFind(0,n)<0)
   {
      ObjectCreate(0,n,OBJ_TEXT,0,anchor,price);
      ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_LEFT);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,n,OBJPROP_BACK,false);
   }
   ObjectMove(0,n,0,anchor,price);
   ObjectSetString (0,n,OBJPROP_TEXT,txt);
   ObjectSetString (0,n,OBJPROP_FONT,InpPanelMono);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,PF(9));
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
}
void EnsureRiskEdit(int y)
{
   // v0.50-fix: remove leftovers of the [-]/[+] variant. Without this they stayed on the chart as "ghost"
   //   objects (the number then sat doubled over the input field).
   if(ObjectFind(0,PFX+"rkv") >=0) ObjectDelete(0,PFX+"rkv");
   if(ObjectFind(0,PFX+"rmin")>=0) ObjectDelete(0,PFX+"rmin");
   if(ObjectFind(0,PFX+"rpls")>=0) ObjectDelete(0,PFX+"rpls");
   string n=PFX+"rkin";
   bool created=false;
   if(ObjectFind(0,n)<0)
   {
      ObjectCreate(0,n,OBJ_EDIT,0,0,0); created=true;
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,n,OBJPROP_BACK,false);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   }
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,PS(170));
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,PS(y));
   ObjectSetInteger(0,n,OBJPROP_XSIZE,PS(58));
   ObjectSetInteger(0,n,OBJPROP_YSIZE,PS(22));
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,PF(10));
   ObjectSetString (0,n,OBJPROP_FONT,InpPanelMono);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'20,27,38');
   ObjectSetInteger(0,n,OBJPROP_COLOR,C'234,240,249');
   ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR, WeekRiskPending()?C'61,123,255':C'40,52,70');   // ungesetzt -> blau hervorgehoben
   // v0.62: if the weekly confirmation is pending and the trader already staged a change in the
   //   previous week, THAT is his most recently formed intention — it belongs in the field, not the old value.
   //   Confirming still happens deliberately via "SETZEN" (set); without confirmation the staged value has no effect.
   string want=Dec2((WeekRiskPending() && PendingWeekRisk()>0) ? PendingWeekRisk() : DesiredRiskPct());
   if(created || g_rkEditSync!=want){ g_rkEditSync=want; ObjectSetString(0,n,OBJPROP_TEXT,want); }
}
void Btn(string name,int x,int y,int w,int h,string text,color bg,int fsize=11)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PS(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PS(y));
   ObjectSetInteger(0,name,OBJPROP_XSIZE,PS(w));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,PS(h));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,PF(fsize));   // v0.46
   ObjectSetString (0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
}
void EnsureSLLine()
{
   if(ObjectFind(0,SLLINE)>=0)
   { if(ObjectGetInteger(0,SLLINE,OBJPROP_COLOR)!=clrWhite) ObjectSetInteger(0,SLLINE,OBJPROP_COLOR,clrWhite); return; }   // v0.29: recolor an existing (red) SL line to white automatically
   double bid=MarketInfo(Symbol(),MODE_BID); if(bid<=0) bid=Close[0];
   double p=bid - InpDefaultSLpips*Pip();
   ObjectCreate(0,SLLINE,OBJ_HLINE,0,0,p);
   ObjectSetDouble (0,SLLINE,OBJPROP_PRICE,0,p);
   ObjectSetInteger(0,SLLINE,OBJPROP_COLOR,clrWhite);   // v0.29: SL line WHITE (a stop-loss is a good thing, not danger red)
   ObjectSetInteger(0,SLLINE,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,SLLINE,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,SLLINE,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,SLLINE,OBJPROP_SELECTED,true);
   ObjectSetInteger(0,SLLINE,OBJPROP_HIDDEN,false);
   ObjectSetString (0,SLLINE,OBJPROP_TEXT,"Mamal SL");
}
// v0.46: TP line only when switched on. Green = target; once dragged, it takes precedence over InpRR.
double TPLinePrice(){ if(!InpTpLine || ObjectFind(0,TPLINE)<0) return 0.0; return ObjectGetDouble(0,TPLINE,OBJPROP_PRICE,0); }
void EnsureTPLine()
{
   if(!InpTpLine){ if(ObjectFind(0,TPLINE)>=0) ObjectDelete(0,TPLINE); return; }
   if(ObjectFind(0,TPLINE)>=0) return;
   double bid=MarketInfo(Symbol(),MODE_BID); if(bid<=0) bid=Close[0];
   double p=bid + InpDefaultSLpips*Pip()*((InpRR>0)?InpRR:2.0);
   ObjectCreate(0,TPLINE,OBJ_HLINE,0,0,p);
   ObjectSetDouble (0,TPLINE,OBJPROP_PRICE,0,p);
   ObjectSetInteger(0,TPLINE,OBJPROP_COLOR,C'61,220,146');
   ObjectSetInteger(0,TPLINE,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,TPLINE,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,TPLINE,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,TPLINE,OBJPROP_HIDDEN,false);
   ObjectSetString (0,TPLINE,OBJPROP_TEXT,"Mamal TP");
}
// #14 rule test harness: manipulates ONLY state/file (opens NO trades) -> to test rule behavior.
// Hard-gated: only if InpTestMode && !InpFundedMode. Trade-based scenarios (NoSL/BigLot/BadCRV)
// are reproduced by the user manually on demo (click BUY/SELL).
void TestAction(string which)
{
   if(!InpTestMode || InpFundedMode) return;   // hart gegated
   if(which=="cooldown"){ GlobalVariableSet(GV_COOLDOWN,(double)(SrvTime()+EffCooldownMin()*60)); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(T("test.cooldown")); Journal("TEST","-","-",0,0,0,0,0,"TEST Cooldown"); }
   else if(which=="daylock"){ GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,7); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(T("test.dayLock")); Journal("TEST","-","-",0,0,0,0,0,"TEST DayLock"); }
   else if(which=="maxlock"){ GlobalVariableSet(GV_HARD_LOCK,1); GlobalVariableSet(GV_LOCK_WHY,7); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(T("test.maxLock")); Journal("TEST","-","-",0,0,0,0,0,"TEST MaxLock"); }
   else if(which=="revenge"){ SetRevenge(Symbol(),OP_BUY); GlobalVariableSet(GV_TEST_SET,1); GlobalVariablesFlush(); Notify(T("test.revenge")); Journal("TEST",Symbol(),"-",0,0,0,0,0,"TEST Revenge"); }
   else if(which=="corrupt")
   {
      int h=FileOpen(LOCKFILE,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE){ FileWriteString(h,"MMTLS1;GARBAGE;0\r\n"); FileClose(h); }
      g_lockSig="";          // erzwingt spaeter Neu-Schreiben
      ReconcileLockstate();  // simuliert Start-Read -> fail-closed (Tagessperre + TAMPER)
      Notify(T("test.lockstateCorrupted"));
      Journal("TEST","-","-",0,0,0,0,0,"TEST CorruptLock+Reconcile");
   }
   else if(which=="reset")   // §05-fix (high): NO universal unlock any more. Only self-set TEST locks on a demo account; hard lock (R4b permanent) ALWAYS stays.
   {
      bool demo        = IsDemo();
      bool testInduced = (GlobalVariableGet(GV_TEST_SET)>0.5);
      if(!demo || !testInduced)   // live account OR the lock came from a real rule event -> reject
      {
         Notify(TF("test.resetRejected",!demo?"not a demo account":"no test lock active"));
         Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("Reset ABGELEHNT (demo=%d testInduced=%d) — echte Sperren bleiben",demo?1:0,testInduced?1:0));
         g_panelSig=""; return;
      }
      GlobalVariableSet(GV_LOCK_UNTIL,0); ClearLockWhy();
      // Hard lock (GV_HARD_LOCK) is deliberately NOT cleared - R4b is permanent.
      // v0.64 (discarded): a "test locks only" exception could not be built safely. The test button
      //   could relabel an already REALLY triggered lock as a test after the fact, and a
      //   real breach DURING a test lock was not registered at all. Above all, though,
      //   the demo condition does not hold: prop firm challenge accounts run in MT4 AS demo accounts -
      //   exactly where lifting it would be most expensive. Stays permanent; on demo delete it via F3.
      GlobalVariableSet(GV_COOLDOWN,0);   GlobalVariableSet(GV_TARGET_HIT,0);
      if(GlobalVariableCheck(RevUntilKey(Symbol()))) GlobalVariableDel(RevUntilKey(Symbol()));
      if(GlobalVariableCheck(RevDirKey(Symbol())))   GlobalVariableDel(RevDirKey(Symbol()));
      GlobalVariableSet(GV_TEST_SET,0);
      GlobalVariablesFlush(); g_lockSig="";
      // v0.63: this here is the ONLY legitimate unlock. It has to write the mirror directly —
      //   if it went through the new reconciliation, that would pull the just-deleted test lock right back.
      //   The hard lock stays nonetheless, it was deliberately left untouched above.
      g_lsGuard=true; WriteLockstate(); g_lsGuard=false;
      Notify(T("test.locksReset"));
      Journal("TAMPER","-","-",0,0,0,0,0,"TEST Reset (nur Test-Sperren, Hard-Lock unberuehrt)");
   }
   g_panelSig="";
}
// v0.25: Panel-Kartengeometrie an EINER Stelle (CreateControls + Klick-Guard nutzen dieselbe)
int RiskRowOff(){ return InpRiskChooser ? 46 : 0; }   // v0.36: the risk row pushes everything below it down (v0.48: 32->46 for the explanatory subline)
int PanelH(){ int h=372; h+=RiskRowOff(); if(InpBreakEvenBtn) h+=26; if(InpTestMode && !InpFundedMode) h+=72; return h; }   // v0.26: +Cockpit, v0.36: +Risiko-Waehler, v0.37: +16 Meldungsbox, v0.40: +52 Close-Buttons, v0.46: +26 Risk-Free
void CreateControls()
{
   int  cardH = PanelH();
   int  ro    = RiskRowOff();
   RectB(PFX+"card",12,16,300,cardH,C'14,18,25',C'33,42,56');   // Karte mit feinem Rand
   if(InpRiskChooser)   // v0.36: Risiko-Waehler [-] / Wert / [+]
   {
      // v0.49: input field instead of [-]/[+] — the weekly value is deliberately typed and confirmed.
      // v0.50-fix: field 170..228, button 234..298 -> 6px gap between, button wide enough for "SETZEN" (set).
      EnsureRiskEdit(196);
      Btn(PFX+"rkset",234,196,64,22,T("btn.set"),C'28,74,92',8);
   }
   Btn (PFX+"buy",  26,266+ro,131,32,"BUY", C'21,156,100',12);   // v0.37: +16 wegen hoeherer Meldungsbox
   Btn (PFX+"sell",159,266+ro,131,32,"SELL",C'216,63,80',12);
   // v0.40: Close-Buttons (Risiko-Reduktion — immer aktiv, nie ausgegraut)
   Btn (PFX+"fc", 26,302+ro,131,22,T("btn.fullClose"), C'150,45,58',9);
   Btn (PFX+"cc",159,302+ro,131,22,T("btn.chartClose"),C'112,48,60',9);
   Btn (PFX+"f5", 26,328+ro,131,22,T("btn.full50"),   C'70,48,58',9);
   Btn (PFX+"c5",159,328+ro,131,22,T("btn.chart50"),  C'62,46,56',9);
   int bo=0;
   if(InpBreakEvenBtn){ Btn(PFX+"be",26,354+ro,264,22,T("btn.riskFree"),C'28,74,92',9); bo=26; }   // v0.46
   if(InpCockpit) Btn(PFX+"cockpit",26,356+bo+ro,264,24,T("btn.cockpit"),C'30,46,74',9);   // v0.26: oeffnet localhost-Dashboard (v0.40: +52 wegen Close-Reihen)
   if(InpTestMode && !InpFundedMode)
   {
      Lbl(PFX+"tlbl",26,388+bo+ro,T("test.label"),C'244,183,64',8,"Tahoma");
      Btn(PFX+"t1", 26,402+bo+ro, 86,22,"Cooldown",C'44,52,68',8);
      Btn(PFX+"t2",118,402+bo+ro, 86,22,"DayLock", C'44,52,68',8);
      Btn(PFX+"t3",210,402+bo+ro, 86,22,"MaxLock", C'44,52,68',8);
      Btn(PFX+"t4", 26,428+bo+ro, 86,22,"Revenge", C'44,52,68',8);
      Btn(PFX+"t5",118,428+bo+ro, 86,22,"Corrupt", C'110,54,58',8);
      Btn(PFX+"t6",210,428+bo+ro, 86,22,"Reset",   C'34,78,54',8);
   }
   EnsureSLLine();
   EnsureTPLine();
   DrawCandleClock();   // v0.52: countdown next to the candle   // v0.46: keep the TP line updated (only if InpTpLine=true)
}
void Meter(string id,int y,string label,double val,double lim)
{
   double f=Frac(val,lim); int bw=(int)(272*f); if(bw<3 && f>0) bw=3;
   Lbl (PFX+id+"l",26,y,label,C'146,158,178',8,"Tahoma");                              // v0.25: einheitliche Caption
   LblR(PFX+id+"v",298,y,StringFormat("%s / %s%%",Dec2(val),Dec2(lim)),C'205,214,228',8,InpPanelMono);   // dt. Komma
   Rect(PFX+id+"t",26,y+15,272,6,C'26,34,48');       // Track (6px)
   Rect(PFX+id+"f",26,y+15,bw,6,BarCol(f));          // Fill
}
void DrawPanel(double dd,double tdd,bool disabled)
{
   EnsureSLLine();
   EnsureTPLine();
   DrawCandleClock();   // v0.52: countdown next to the candle   // v0.46: keep the TP line updated (only if InpTpLine=true)
   if(g_fgTries>0){ g_fgTries--; if(ChartGetInteger(0,CHART_FOREGROUND)!=0) ChartSetInteger(0,CHART_FOREGROUND,false); }   // v0.28: only a limited number of times (no ChartSetInteger spam per cycle); if it does not hold -> user: turn off F8 „Chart im Vordergrund" (chart on foreground)
   int    consec=(int)GlobalVariableGet(GV_CONSEC);
   double dayR=GlobalVariableGet(GV_DAY_RISK);
   double heat=TotalOpenRiskPct();
   double eq  =AccountEquity();
   bool   cool=CooldownActive();
   bool   tgt=TargetHit();
   bool   off=OffSession();
   bool   maxw=(!IsLocked() && !disabled && MaxLossWarnActive());   // R4b Warn-Gate

   string st; color stcol; color pillBg, pillBd;
   if(disabled)        { st=T("status.guardOff");        stcol=C'244,183,64'; }
   else if(IsLocked()) { st=(IsHardLocked()?T("status.hardLock"):(IsWeekLocked()?T("status.weekLock"):T("status.dayLock"))); stcol=C'240,73,90'; }
   else if(BaseWarn()) { st=T("status.baseWarn");    stcol=C'244,183,64'; }   // §07-fix: blocks every entry -> must not appear as "AKTIV" (active)
   else if(WeekRiskPending())
                       { st=T("status.setWeekRisk");  stcol=C'61,123,255'; }   // v0.49: the weekly decision is pending -> blocks entries
   else if(maxw)       { st=T("status.maxLossWarn");  stcol=C'244,183,64'; }
   else if(cool)       { st=T("status.cooldown");          stcol=C'244,183,64'; }
   else if(tgt)        { st=T("status.targetHit");     stcol=C'61,220,146'; }
   else if(off)        { st=T("status.offSession");    stcol=C'160,170,186'; }
   else                { st=T("status.active");             stcol=C'61,220,146'; }
   // derive the pill tint from the state (green / red / amber / neutral)
   if(stcol==C'61,220,146')      { pillBg=C'15,36,25'; pillBd=C'28,77,52'; }
   else if(stcol==C'240,73,90')  { pillBg=C'40,18,22'; pillBd=C'90,34,40'; }
   else if(stcol==C'244,183,64') { pillBg=C'40,31,15'; pillBd=C'88,64,26'; }
   else                          { pillBg=C'22,28,38'; pillBd=C'40,50,64'; }

   bool noTrade=(IsLocked()||disabled||cool||tgt||off||maxw||BaseWarn()
                 ||(WeekRiskPending()));   // §07-fix: BaseWarn greys the buttons out; v0.49: a pending weekly choice does too
   color bbuy = noTrade?C'46,53,66':C'21,156,100';
   color bsell= noTrade?C'46,53,66':C'216,63,80';
   color bacc = noTrade?C'70,80,96':C'61,220,146';
   color sacc = noTrade?C'70,80,96':C'255,107,120';
   color HAIR = C'30,38,52';   // v0.25: ONE hairline token for all internal separators
   color CAP  = C'146,158,178';// v0.25: EIN Caption-Token (Groesse 8)

   string prev=PreviewText();
   bool   flashOn=(g_flash!="" && (GetTickCount()-g_flashMs)<g_flashHold);
   string dv=StringFormat("%.2f",dd), gv=StringFormat("%.2f",tdd);
   string eqs=CurSym()+GroupInt(eq);
   string cHeat=Dec2(heat)+"/"+Dec2(EffHeat());
   bool   budFull=(EffDay()>0 && dayR >= EffDay()-0.01);
   string cBud =TF("tile.limit.value",Dec2(MathMax(0,EffDay()-dayR)));                          // v0.25: verbleibendes Budget statt verbrauchtem
   string cStp =StringFormat("%d/%d",consec,EffLockAfter());   // §06-fix: show the effective threshold (not the possibly loosened raw input)
   color  stpCol = (consec>=EffLockAfter())?C'240,73,90':((consec>=EffLockAfter()-1 && consec>0)?C'244,183,64':C'205,214,228');   // amber 1 before the lock, red at the lock

   // two-tone: color the direction (BUY/SELL), rest mono — only in the normal trading state
   string pdir="", pdet=prev;
   if(!flashOn && g_armed==0 && !noTrade)
   {
      if(StringSubstr(prev,0,4)=="BUY ")      { pdir="BUY";  pdet=StringSubstr(prev,4); }
      else if(StringSubstr(prev,0,5)=="SELL "){ pdir="SELL"; pdet=StringSubstr(prev,5); }
   }

   // v0.36: Risiko-Waehler-Anzeige (wirksamer Wert; bei vorgemerkter Erhoehung "→ X")
   // v0.48: make the risk row readable — the value stays short (fits between the buttons),
   //   the explanation (euro amount + weekly commitment) sits in a subline of its own.
   string rkv="", rkSub="";
   if(InpRiskChooser)
   {
      rkv=StringFormat("%s %%",Dec2(EffRiskPct()));
      double rEur=AccountEquity()*EffRiskPct()/100.0;
      string eurTxt=CurSym()+GroupInt(rEur);   // v0.55: "je Trade"/"per trade" steckt in risk.sub.* (uebersetzt)
      // v0.62: show "unset" only when a confirmation is really PENDING. Without the obligation
      //   (InpRequireWeeklyRisk=false) the last chosen value stays valid — then
      //   "Wochenwert eintippen ..." (type the weekly value) would be a prompt into the void.
      bool chosen=(GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0
                   && !WeekRiskPending());
      if(WeekRiskPending())     rkSub=T("risk.sub.unset");
      else if(PendingWeekRisk()>0) rkSub=TF("risk.sub.pending",eurTxt,Dec2(PendingWeekRisk()));
      else if(chosen)           rkSub=TF("risk.sub.fixed",eurTxt);
      else                      rkSub=T("risk.sub.unset");
   }
   // v0.65b: resolve by lock type. A stored day reason must never show under a hard or
   //   weekly lock — otherwise something false would stand there with full certainty.
   string lockWhy = IsHardLocked() ? T("why.maxloss")
                  : (IsWeekLocked() ? T("why.week")
                  : (IsDayLocked()  ? LockWhyText() : ""));
   int ro=RiskRowOff();

   // v0.46: spread + the candle's remaining second into the signature — otherwise the cache would freeze the panel
   //   and the countdown would stand still (DrawPanel only draws on a changed signature).
   string tick="";
   if(InpShowCandleTime) tick=tick+IntegerToString((int)(Time[0]+PeriodSeconds()-TimeCurrent()));
   if(InpShowSpread)     tick=tick+"/"+DoubleToString((Point>0)?((MarketInfo(Symbol(),MODE_ASK)-MarketInfo(Symbol(),MODE_BID))/Point):0,0);
   string sig=st+"|"+lockWhy+"|"+dv+"|"+gv+"|"+prev+"|"+eqs+"|"+cHeat+"|"+cBud+"|"+cStp+"|"+rkv+"|"+rkSub+"|"+(flashOn?(g_flashInfo?"I":"F"):"-")+"|"+(noTrade?"N":"T")+"|"+IntegerToString((int)GlobalVariableGet(GV_BLOCKS))+"|"+tick;
   if(sig==g_panelSig) return;
   g_panelSig=sig;

   // Header: Brand-Top-Leiste + Logo-Mark + Wortmarke + Symbol-Chip + Trennlinie
   Rect (PFX+"cardtop",12,16,300,2,C'40,86,178');   // v0.25: dezente Fintech-Top-Kante (gedaempftes Blau)
   Rect (PFX+"lg1",26,33,3, 6,C'61,123,255');
   Rect (PFX+"lg2",31,29,3,10,C'61,123,255');
   Rect (PFX+"lg3",36,25,3,14,C'61,123,255');
   Lbl  (PFX+"br1",46,25,"MAMAL",C'234,240,249',11,"Arial Bold");
   Lbl  (PFX+"br2",90,25,"·TRADING",C'107,118,136',11,"Arial");     // v0.25: gap closed (99->90; adjust to 88-92 after F7 if needed)
   string cxs=Symbol()+" · "+PeriodStr(); int cw=14+StringLen(cxs)*5; if(cw>150) cw=150;   // v0.25: Chip dynamisch, rechtsbuendig
   RectB(PFX+"chip",298-cw,25,cw,18,C'20,27,38',C'33,42,56');
   LblR (PFX+"chiptx",293,28,cxs,CAP,8,"Tahoma");
   // v0.46: live spread + remaining time of the running candle (green -> amber -> red, the closer the close)
   string infoL=""; color infoC=CAP;
   if(InpShowSpread)
   {
      double sprPts=(Point>0)?((MarketInfo(Symbol(),MODE_ASK)-MarketInfo(Symbol(),MODE_BID))/Point):0;
      infoL=TF("header.spread",DoubleToString(sprPts,0));
      double sprAvg=MarketInfo(Symbol(),MODE_SPREAD);   // Broker-Normalspread als Referenz
      if(sprAvg>0 && sprPts>sprAvg*2.0) infoC=C'240,73,90';        // ungewoehnlich weit -> Warnung
      else if(sprAvg>0 && sprPts>sprAvg*1.4) infoC=C'244,183,64';
   }
   if(InpShowCandleTime)
   {
      int rest=(int)(Time[0]+PeriodSeconds()-TimeCurrent());
      if(rest<0) rest=0;
      int rm=rest/60, rs=rest%60;
      string ct=StringFormat("%02d:%02d",rm,rs);
      color cc=(rest<=10)?C'240,73,90':((rest<=30)?C'244,183,64':C'61,220,146');
      if(infoL!="") { Lbl(PFX+"spr",26,44,infoL,infoC,8,InpPanelMono); LblR(PFX+"ctm",298,44,TF("header.candleTime",ct),cc,8,InpPanelMono); }
      else            LblR(PFX+"ctm",298,44,TF("header.candleTime",ct),cc,8,InpPanelMono);
   }
   else if(infoL!="") Lbl(PFX+"spr",26,44,infoL,infoC,8,InpPanelMono);
   Rect (PFX+"hhair",12,54,300,1,HAIR);

   // Status-Pill + Kapital
   int pw=24+StringLen(st)*8+12; if(pw>184) pw=184;   // v0.25: bold capitals (8px/char) + clamp, no overflow
   RectB(PFX+"pill",26,62,pw,22,pillBg,pillBd);
   Rect (PFX+"pdot",36,70,7,7,stcol);
   Lbl  (PFX+"ptx",50,66,st,stcol,10,"Arial Bold");
   // v0.65: WHY locked. Without it, only "TAG GESPERRT" (day locked) stands there and the trader guesses — in doubt he
   //   recomputes his daily loss, finds 0.28 % of 2.00 % and takes the tool for broken, while in
   //   truth the losing streak did the locking.
   if(lockWhy!="") Lbl(PFX+"why",26,86,Clip(lockWhy,46),C'150,162,180',8,"Tahoma");
   else if(ObjectFind(0,PFX+"why")>=0) ObjectDelete(0,PFX+"why");
   LblR (PFX+"eql",298,61,T("header.equity"),CAP,8,"Tahoma");
   LblR (PFX+"eqv",298,71,eqs,C'234,240,249',11,InpPanelMono);

   // Verlust-Meter
   Meter("d",98, T("meter.dailyLoss"),  dd,  EffDailyLoss());
   Meter("g",126,T("meter.totalLoss"), tdd, EffMaxLoss());

   // Metrik-Kacheln: Risiko / Limit / Serie / Abgelehnt (v0.32: 4. Kachel = Impuls-Spiegel)
   int    blkToday=(int)GlobalVariableGet(GV_BLOCKS);
   color  blkCol = (blkToday>=7)?C'240,73,90':((blkToday>=3)?C'244,183,64':C'205,214,228');
   Rect(PFX+"mdiv",26,158,272,1,HAIR);
   Lbl (PFX+"c1l",26, 164,T("tile.risk"),  CAP,8,"Tahoma");  Lbl(PFX+"c1v",26, 174,cHeat,C'205,214,228',10,InpPanelMono);
   Lbl (PFX+"c2l",94, 164,T("tile.limit"),   CAP,8,"Tahoma");  Lbl(PFX+"c2v",94, 174,cBud, budFull?C'240,73,90':C'205,214,228',9,InpPanelMono);
   Lbl (PFX+"c3l",162,164,T("tile.streak"),   CAP,8,"Tahoma");  Lbl(PFX+"c3v",162,174,cStp, stpCol,10,InpPanelMono);
   Lbl (PFX+"c4l",230,164,T("tile.blocked"),CAP,8,"Tahoma"); Lbl(PFX+"c4v",230,174,IntegerToString(blkToday), blkCol,10,InpPanelMono);
   Rect(PFX+"mv1",88, 162,1,26,HAIR);
   Rect(PFX+"mv2",156,162,1,26,HAIR);
   Rect(PFX+"mv3",224,162,1,26,HAIR);
   Rect(PFX+"mdiv2",26,194,272,1,HAIR);

   // v0.36: risk selector row (buttons come from CreateControls; here only label + value)
   if(InpRiskChooser)
   {
      // v0.50-fix: NO separate value label any more — the input field shows the value itself.
      //   Before, the old caption lay exactly over the field (doubled number on screen).
      Lbl (PFX+"rkl", 26,200,T("risk.label"),CAP,8,"Tahoma");
      Lbl (PFX+"rksub",26,216,rkSub,(PendingWeekRisk()>0?C'244,183,64':C'126,138,158'),8,"Tahoma");
      Rect(PFX+"rkdiv",26,194+ro,272,1,HAIR);
   }

   // "Nächster Trade" (next trade)/hint box (v0.37: tall enough for up to 3 lines of full text instead of truncating)
   bool   infoFlash = flashOn && g_flashInfo;   // v0.37: neutral hint (e.g. cockpit) instead of a red "NICHT MOEGLICH" (not possible)
   color  boxBg  = flashOn ? (infoFlash?C'20,30,45':C'34,20,24') : C'20,27,38';
   color  boxBrd = flashOn ? (infoFlash?C'40,70,110':C'90,34,40') : C'33,42,56';
   color  boxAcc = flashOn ? (infoFlash?C'80,150,240':C'240,73,90') : C'61,123,255';
   RectB(PFX+"ntbg",26,202+ro,272,58, boxBg, boxBrd);
   Rect (PFX+"ntacc",26,202+ro,3,58, boxAcc);   // 3px Akzent
   string planHdr = flashOn ? (infoFlash?T("box.header.info"):T("box.header.blocked")) : T("box.header.plan");
   color  planCol = flashOn ? (infoFlash?C'150,200,255':C'255,120,120') : CAP;
   Lbl  (PFX+"plan",37,206+ro, planHdr, planCol,8,"Tahoma");
   color  txtCol  = flashOn ? (infoFlash?C'205,225,255':C'255,150,70') : (noTrade?C'244,183,64':C'234,240,249');
   string txtFont = flashOn?"Arial":InpPanelMono;
   string WL[];
   if(pdir!="")   // farbige Richtung (BUY/SELL) + Detail umgebrochen
   {
      Lbl(PFX+"prevdir",37,219+ro,pdir,(pdir=="BUY"?C'61,220,146':C'255,107,120'),11,"Arial Bold");
      WrapText(pdet,32,3,WL);
      Lbl(PFX+"prev",80,220+ro,WL[0],C'234,240,249',10,InpPanelMono);
      Lbl(PFX+"pl1", 37,232+ro,WL[1],C'234,240,249',10,InpPanelMono);
      Lbl(PFX+"pl2", 37,244+ro,WL[2],C'234,240,249',10,InpPanelMono);
   }
   else           // message / preview wrapped across up to 3 lines
   {
      Lbl(PFX+"prevdir",37,219+ro," ",C'20,27,38',8,"Arial");   // versteckt
      WrapText(prev,42,3,WL);
      Lbl(PFX+"prev",37,220+ro,WL[0],txtCol,10,txtFont);
      Lbl(PFX+"pl1", 37,232+ro,WL[1],txtCol,10,txtFont);
      Lbl(PFX+"pl2", 37,244+ro,WL[2],txtCol,10,txtFont);
   }

   // BUY / SELL + Akzent-Oberkanten (v0.37: +16 wegen hoeherer Meldungsbox)
   Rect(PFX+"buyacc", 26,264+ro,131,2,bacc);
   Rect(PFX+"sellacc",159,264+ro,131,2,sacc);
   ObjectSetInteger(0,PFX+"buy", OBJPROP_BGCOLOR,bbuy);
   ObjectSetInteger(0,PFX+"sell",OBJPROP_BGCOLOR,bsell);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
