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
//|  MamalTrading.mq4  —  Mamal-Trading Risk-Engine, v0.46         |
//|  v0.46: Risk-Free (SL auf Break-Even), ziehbare TP-Linie,       |
//|   Live-Spread + Kerzen-Countdown, Schrift-/Formskalierung,      |
//|   Auto-Fit des Panels an die Chart-Hoehe.                       |
//|  v0.40: 4 Close-Buttons (Full/Chart x Voll/50%) + PanelClose;    |
//|   Close-Erkennung magic-/tab-unabhaengig (RGOPN-Registry +       |
//|   Ticket-Fallback); InpMagic<=0-Guard; Cockpit-aus-Hinweis.      |
//|  v0.39: Dashboard-Upgrade — dayBase/weekBase in der JSON,       |
//|   "Tag beenden"-Kommando (Tighten-Only-Selbstsperre).           |
//|  v0.38: Zero-Config — Basis voll-automatisch (Einzahlungs-      |
//|   Historie bzw. Rekonstruktion), nie mehr BASIS UNSICHER;       |
//|   Konto-Wegweiser pro Login (Multi-Konto-Cockpit).              |
//|  v0.37: InpPanelScale — Panel-Geometrie fuer Windows-Skalierung |
//|   >100% skalieren (1.5 fuer 150%), gegen Panel-Ueberlappung.    |
//|   + Meldungsbox 3-zeilig mit Wort-Umbruch (WrapText), voller    |
//|   Text statt Abschneiden; Box +16px, Buttons nachgerueckt.      |
//|   + Cockpit-Wegweiser (mamal_files.txt) im Common-Ordner:       |
//|   Server findet den echten Files-Pfad auch bei Portable/Multi-  |
//|   Terminal; Cockpit-Meldung neutral-blau statt rotem Fehler.    |
//|  v0.36: Wochen-Risiko-Waehler im Panel ([-]/[+], gilt fuer die   |
//|   Woche; Auto-Scale-Kaskade skaliert mit, Trade-Zaehler nicht).  |
//|  (Regeln R1-R19 + R22 + R25; R8/R9/R14/R15/R19/R25 aus;          |
//|   Auto-Scale Caps; R22 = nur Panel-Trades, Magic 0 wird zu)      |
//|  v0.34: Audit-Haertung (Konto-Bindung, Lockstate-Reconcile 5s,    |
//|   Tighten-Only auf alle Sperr-Inputs, kein Verlust-Laundering,    |
//|   Entry-Regeln nachtraeglich, R2-Monitor, History-Wachhund).      |
//|  v0.35: R22 — manuelle/Handy-Orders (Magic 0) werden geschlossen; |
//|   fremde EA-Magics bleiben unangetastet.                          |
//|  v0.15 P0/P1: FTMO-Basis MathMax + Erststart-Failsafe (P0-5/P1-2)|
//|   Enforce tickunabh. (P0-1) · EA-Close-Ausschluss persistent     |
//|   (P0-3, sofort-Flush) · History-Verlustauflösung (P0-2/4).      |
//|  v0.16: echte Close-Queue (Retry/Backoff/Error-Codes/Journal) +  |
//|   Lockstate-Datei (HMAC-light, fail-closed) + Schutz-aus-Logging.|
//|  v0.17: R25 persistent · Audit-Journal · R17 Waehrungsvektor ·    |
//|   R7-Haertung (OpenTime-Anker/News-Grace) · TickValue-Fallback ·  |
//|   Funded-Gate (TOOL_ONLY) · Prop-Firm-Profil · TestMode-Harness.  |
//|  ⚠ NUR DEMO. UNGETESTET — Compile-Nachweis erst nach F7=0 Errors.|
//+------------------------------------------------------------------+
#property copyright "Mohammadreza Tavakoli"
#property link      "https://itavakoli.com/"
#property strict

enum WatchScope { TOOL_ONLY, TOOL_PLUS_MANUAL, ALL_POSITIONS };   // Reichweite des Watchdogs
enum PropFirm   { PF_FTMO, PF_THE5ERS, PF_FUNDEDNEXT, PF_FUNDINGPIPS, PF_ALPHACAPITAL, PF_CUSTOM };  // Prop-Firm-Profile (FTMO=Default; Limits bleiben Inputs)

extern double InpInitialBalance     = 0;     // B1: 0 = automatisch (echte Kontobasis). Sonst die ECHTE Challenge-Startbalance setzen — R4b Max-Loss rechnet dagegen!
extern double InpDayStartBase       = 0;     // P1-2: echte FTMO-Mitternachtsbasis manuell (0=auto). Bei Erststart mitten am Tag setzen!
extern double InpDailyLossPct       = 2.0;   // R4
extern double InpMaxLossPct         = 6.0;   // R4b Max-Loss-Sperre % (Puffer unter FTMO 10%)
extern bool   InpTightenOnly        = true;  // v0.30 Selbst-Sperre: Verlust-Limits nur ENGER stellbar; LOCKERN greift erst zum naechsten Tageswechsel (kein Tilt-Lockern)
extern double InpMaxLossWarnPct     = 5.0;   // R4b Warn-Gate: ab hier KEINE neuen Trades (vor der Sperre)
extern double InpRiskPerTradePct    = 0.25;  // R1 (FTMO: konservativ)
extern double InpRiskTolFactor      = 1.10;  // R1/R12
extern bool   InpAutoScale          = true;  // Caps dynamisch aus Risiko/Trade (R2->R3/R12 folgen)
extern double InpIdeaXrisk          = 2.0;   // R2  Idee-Cap   = X * Risiko/Trade
extern double InpHeatXidea          = 2.0;   // R12 Gesamtrisiko = X * Idee-Cap
extern double InpDayXidea           = 4.0;   // R3  Tagesbudget = X * Idee-Cap (v0.20: 4 -> 2,0% = 400 EUR, damit R4/Tagesziel erreichbar)
extern double InpIdeaCapPct         = 1.0;   // R2  (nur AutoScale=false)
extern double InpDailyRiskBudgetPct = 2.0;   // R3  (nur AutoScale=false; v0.20: 2,0% = 400 EUR)
extern double InpPortfolioHeatPct   = 2.0;   // R12 (nur AutoScale=false)
extern double InpDailyTargetPct     = 3.0;   // R13
extern double InpGivebackArmPct     = 1.0;   // R13
extern double InpGivebackPct        = 1.0;   // R13
extern int    InpCooldownAfter      = 3;     // R5
extern int    InpCooldownMin        = 45;    // R5
extern int    InpLockAfter          = 5;     // R6
extern double InpMinRR              = 0;     // R8 Mindest-CRV AUS (v0.20, auf Wunsch; 0=aus)
extern double InpRR                 = 2.0;   // Auto-TP
extern double InpMinStopPips        = 0;     // R15 min-SL AUS (User-Wunsch: M1-Scalping braucht enge Stops; 0=aus). Broker-Mindestabstand (STOPLEVEL) bleibt hart.
extern double InpMaxLot             = 0;     // R15 (0=aus)
extern int    InpMinGapSec          = 0;     // R14 Mindestpause AUS (v0.20, auf Wunsch; 0=aus)
extern int    InpRevengeMin         = 0;     // R25 Revenge-Fenster AUS (v0.20, auf Wunsch; 0=aus)
extern bool   InpUseSession         = false; // R16
extern int    InpSessionStart       = 8;     // R16
extern int    InpSessionEnd         = 22;    // R16
extern int    InpNewsFrom           = 0;     // R16 HHMM (0=aus)
extern int    InpNewsTo             = 0;     // R16 HHMM
extern bool   InpUseCorrCap         = true;  // R17
extern double InpCorrCapPct         = 1.5;   // R17
extern double InpWeeklyLossPct      = 5.0;   // R18 (0=aus)
extern int    InpDeRiskAfter        = 2;     // R19
extern double InpDeRiskFactor       = 1.0;   // R19 De-Risk-Leiter AUS (v0.20, auf Wunsch; 1.0=aus)
extern bool   InpFomoGate           = false; // R9
extern int    InpFomoSeconds        = 7;     // R9
extern bool   InpJournal            = true;  // R11
extern bool   InpHistoryBackfill    = true;  // v0.66: EINMALIG geschlossene Trades aus der Kontohistorie ins Journal nachtragen
                                             //   (Ticket + Netto), damit die Trade-Akte Altbestand zuordnen kann. Laeuft je Konto genau einmal.
                                             //   BEWUSST NEU BENANNT (vorher InpBackfillHistory): MT4 speichert EA-Eingaben pro Chart und nimmt
                                             //   beim Aufziehen den GESPEICHERTEN Wert, nicht den Default aus dem Quelltext — der alte Schalter
                                             //   blieb dadurch auf "aus", obwohl der Default hier laengst "an" war. Ein neuer Name hat keinen
                                             //   gespeicherten Vorgaenger, also greift der Default. Vorher im Terminal "Gesamte Historie" einstellen.
                                             //   (Ticket + Netto). Vorher im Terminal "Gesamte Historie" einstellen, sonst
                                             //   sieht der EA nur den gefilterten Ausschnitt. Laeuft je Konto genau einmal.
extern bool   InpScreenshots        = true;  // R11 / v0.47: Screenshot bei jeder Aktion (Open/Close/SL-TP-Verschiebung) — wird je Trade im Cockpit angezeigt
extern int    InpShotWidth          = 1100;  // v0.47: Breite der Screenshots (Pixel)
extern int    InpShotHeight         = 620;   // v0.47: Hoehe der Screenshots (Pixel)
extern int    InpShotKeepDays       = 14;    // v0.47: Screenshots aelter als X Tage loeschen (0 = nie aufraeumen)
extern int    InpSlippage           = 30;
extern int    InpMagic              = 990201;
extern WatchScope InpWatchScope     = TOOL_ONLY;  // TOOL_ONLY=fremde Magics unangetastet · TOOL_PLUS_MANUAL=+Magic0 · ALL_POSITIONS=fasst ALLES an (nur Demo/Debug, NICHT Funded)
extern int    InpCloseThrottleMs    = 300;   // P0-1: min. Abstand zwischen Close-Durchläufen
extern int    InpCloseRetries       = 5;     // Close-Queue: max Versuche je Ticket vor FINAL-FAIL
extern int    InpCloseBackoffMs     = 400;   // Close-Queue: Basis-Backoff (verdoppelt je Versuch)
extern int    InpCloseMaxBackoffMs  = 4000;  // Close-Queue: max Backoff je Ticket
extern double InpDefaultSLpips      = 20;
extern int    InpSlClicksToMove     = 3;     // v0.21: SL-Linie erst nach so vielen Klicks in dieselbe Zone setzen (1 = sofort)
extern double InpSlZonePips         = 10;    // v0.21: Toleranz-Untergrenze "gleiche Zone" in Pips (zusaetzlich ~0,15% des Preises)
extern bool   InpRequireSL          = true;  // R7
extern bool   InpRequireTP          = true;  // R7
extern int    InpSLTPGraceSeconds   = 4;     // R7 (v0.33: 5->4; Anker = seit SL/TP ENTFERNT wurde, nicht ab Open)
extern int    InpTimerSeconds       = 1;
extern int    InpMinActionMs        = 500;
extern int    InpPanelMs            = 1500;
extern bool   InpUseAlert           = false;
extern string InpPanelMono          = "Consolas";  // v0.24 Panel: Monospace-Font fuer Zahlen (falls unter Wine falsch -> "Courier New" oder "Lucida Console")
extern double InpPanelScale         = 0;           // v0.37: 0 = AUTO (aus Windows-DPI, 150%->1.5). Sonst manueller Faktor (1.5 fuer 150%). Behebt Panel-Ueberlappung ohne Zutun.
extern double InpFontScale          = 1.0;         // v0.46: Schriftgroesse im Panel getrennt skalieren (0.8 = kleiner, 1.3 = groesser)
extern double InpShapeScale         = 1.0;         // v0.46: Kachel-/Button-Groesse getrennt skalieren (wirkt auf Breiten/Hoehen)
extern bool   InpPanelAutoFit       = true;        // v0.46: Panel automatisch verkleinern, wenn es sonst hoeher als das Chart-Fenster waere
extern bool   InpShowSpread         = true;        // v0.46: Live-Spread im Panel anzeigen
extern bool   InpShowCandleTime     = true;        // v0.46: Restzeit der laufenden Kerze anzeigen (gruen -> amber -> rot)
extern bool   InpCandleTimeOnChart  = true;        // v0.52: Countdown direkt NEBEN der laufenden Kerze einblenden (nicht nur im Panel)
extern bool   InpBreakEvenBtn       = true;        // v0.46: Knopf "RISK FREE" (SL aller Trades im Gewinn auf Break-Even)
extern double InpBreakEvenBufferPts = 0;           // v0.46: Zusatzpuffer in Punkten ueber Break-Even (0 = exakt Einstieg; deckt Kommission)
extern bool   InpTpLine             = false;       // v0.46: ziehbare TP-Linie statt Auto-TP aus InpRR (Linie hat Vorrang, wenn gesetzt)
extern bool   InpCockpit            = true;        // v0.26: Live-Zustand fuer localhost-Cockpit als JSON schreiben (lokaler Server noetig)
extern int    InpCockpitPort        = 8730;        // v0.26: Port des lokalen Cockpit-Servers (nur Anzeige/Referenz)
//--- v0.17: Prop-Firm-Profil, Funded-Gate, R7-Haertung, Test-Harness ---
extern PropFirm InpPropFirm         = PF_FTMO;  // Prop-Firm-Profil (Label/Audit; Limits bleiben Inputs, pro Firma verifizieren)
extern bool   InpFundedMode         = false; // Real/Funded: erzwingt WatchScope=TOOL_ONLY + sperrt TestMode hart
extern int    InpSLTPGraceNews      = 0;     // R7: Grace-Sekunden waehrend News-Blackout (0 = sofort schliessen)
extern bool   InpTestMode           = false; // Rule-Test-Harness (NUR Demo; in FundedMode hart aus)
extern int    InpDayResetHour        = 0;     // Prop-Firm-Tagesreset-Stunde in Server-Zeit (0 = Mitternacht = FTMO); R4/Tag
extern int    InpWeekStartDay        = 0;     // Wochenstart (0=Sonntag..6=Samstag) fuer R18
//--- R22 (v0.35): NUR PANEL-TRADES. Manuell/per Handy geoeffnete Orders (Magic 0) werden sofort geschlossen. ---
// Trades ANDERER EAs (eigene Magic-Nummer) bleiben bewusst unangetastet. Gilt auch im FundedMode und auch fuer
// Positionen, die beim EA-Start bereits offen sind (kein Bestandsschutz -> kein Schlupfloch ueber EA-Neustart).
extern bool   InpCloseManualTrades   = true;  // R22: manuelle/Handy-Trades (Magic 0) sofort schliessen — nur Panel-Trades erlaubt
//--- v0.36: Wochen-Risiko-Wähler im Panel (Risiko/Trade selbst einstellen, gilt fuer die Woche) ---
enum PanelLang { LANG_DE, LANG_EN };       // v0.53: Panel-Sprache
extern PanelLang InpLang = LANG_DE;        // v0.53: Sprache des On-Chart-Panels (das Dashboard hat einen eigenen Umschalter)
extern bool   InpRequireWeeklyRisk = true;  // v0.49: OHNE festgelegtes Wochen-Risiko wird nicht gehandelt (jede Woche neu bestaetigen)
extern bool   InpRiskChooser         = true;  // Risiko-Waehler [-]/[+] im Panel anzeigen (0 = nur ueber InpRiskPerTradePct)
extern double InpRiskStep            = 0.05;  // Schrittweite des Waehlers in % (z.B. 0.05 -> 0,25 / 0,30 / 0,35 …)
extern double InpRiskMaxPct          = 1.00;  // Obergrenze, die der Waehler zulaesst (harte Kappe bleibt 1,0 % / RULES-Bereich)

#define GV_DAYSTART_EQ   "RG_DAYSTART_EQ"
#define GV_DAYSTART_DAY  "RG_DAYSTART_DAY"
#define GV_LOCK_UNTIL    "RG_LOCK_UNTIL"
#define GV_HARD_LOCK     "RG_HARD_LOCK"
#define GV_MASTER        "RG_MASTER"      // v0.28: Einzel-Instanz-Sperre — welcher Chart ist der aktive Master
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
#define GV_EFF_DL        "RG_EFF_DL"        // v0.30: effektives Tages-Verlustlimit (Lockern erst zum Tageswechsel)
#define GV_EFF_ML        "RG_EFF_ML"        // v0.30: effektives Max-Verlustlimit (dito)
#define GV_PROTOFF       "RG_PROTOFF"       // v0.30: Zaehler "AutoTrading heute ausgeschaltet"
#define GV_EFF_DAY       "RG_EFF_DAY"       // v0.30-fix: fuer welchen Tag EFF zuletzt (nur vom Master) gesetzt wurde -> deterministisch
#define GV_PROT_LATCH    "RG_PROT_LATCH"    // v0.30-fix: geteilter Latch (aktuelle Schutz-aus-Episode schon gezaehlt) -> kein Doppelzaehlen bei Master-Handoff
#define GV_BLOCKS        "RG_BLOCKS"        // v0.32 Panel-Spiegel: abgelehnte Versuche heute (geteilt, kontoweit)
#define GV_FILLS         "RG_FILLS"         // v0.32: tatsaechliche Trades heute
#define GV_BLK_LAST      "RG_BLK_LAST"      // v0.32: Zeit der letzten Ablehnung (fuer Tilt-Burst)
#define GV_BLK_BURST     "RG_BLK_BURST"     // v0.32: Ablehnungen im aktuellen <60s-Fenster
#define GV_ACCOUNT       "RG_ACCOUNT"        // §04-fix (hoch): Login des Kontos, zu dem der gespeicherte Zustand gehoert (Konto-Bindung)
#define GV_MAGIC         "RG_MAGIC"          // v0.38: InpMagic des Masters — passive Charts warnen bei Abweichung (sonst unbewachte Trades)
#define GV_SRV_OFFSET    "RG_SRV_OFFSET"     // §04-fix (mittel): letzter GUTER Server-Offset (Sek) — Neustart in tickloser Phase seedet sonst aus stalem TimeCurrent
#define GV_EFF_RH        "RG_EFF_RH"         // §05-fix (hoch): effektive Tagesreset-Stunde — Input-Aenderung greift erst zum echten Rollover (kein kuenstlicher Roll-Wipe)
#define GV_EFF_WS        "RG_EFF_WS"         // §05-fix (hoch): effektiver Wochenstart-Tag — dito fuer R18
#define GV_TEST_SET      "RG_TEST_SET"       // §05-fix (hoch): eine Sperre wurde per TEST-Button gesetzt -> nur dann darf 'Reset' echte Sperren loeschen
#define GV_LOCK_WHY      "RG_LOCK_WHY"       // v0.65: WARUM ist der Tag gesperrt? 1=R4 Tagesverlust 2=R6 Verlustserie
                                             //   3=R13 Giveback 4=Selbstsperre 5=Historie unsichtbar 6=Lockstate manipuliert 7=Test
#define GV_BACKFILL      "RG_BACKFILL2"      // v0.65: Nachtrag ERFOLGREICH gelaufen (Wert = Kontonummer).
                                             //   Nur bei Treffern gesetzt — ein Fehlversuch darf die einmalige Chance nicht verbrennen.
#define GV_LS_SEEN       "RG_LS_SEEN"        // v0.63: die Lockstate-Datei hat auf diesem Konto schon einmal existiert -> ihr FEHLEN ist ab dann Manipulation, nicht Erststart
// §06-fix (mittel): Tighten-Only auf ALLE sperr-relevanten Inputs ausweiten (bisher nur Daily/MaxLoss).
#define GV_TIGHT_LATCH   "RG_TIGHT_LATCH"    // Selbst-Sperre war heute aktiv -> InpTightenOnly intraday nicht abschaltbar
#define GV_PROT_SINCE    "RG_PROT_SINCE"     // §07-fix: Beginn der aktuellen Schutz-aus-Phase (AutoTrading aus) -> Sperrfristen um die Ausfallzeit verlaengern
// v0.36: Wochen-Risiko-Wähler im Panel — der User stellt Risiko/Trade fuer die Woche selbst ein (Eigenkonto ODER Prop).
#define GV_WEEK_RISK     "RG_WEEK_RISK"      // aktiv gewaehltes Risiko/Trade (%) fuer die laufende Woche
#define GV_WEEK_RISK_IDX "RG_WEEK_RISK_IDX"  // Wochen-Index (WeekIdx), fuer den GV_WEEK_RISK gilt
#define GV_WEEK_RISK_NXT "RG_WEEK_RISK_NXT"  // vorgemerkte Erhoehung -> greift erst zum naechsten Wochenwechsel (Anti-Tilt)
#define GV_EFF_WEEK      "RG_EFF_WEEK"       // R18 Wochenlimit
#define GV_EFF_WARN      "RG_EFF_WARN"       // R4b Warn-Gate
#define GV_EFF_LOCKAFT   "RG_EFF_LOCKAFT"    // R6 Sperre nach n Verlusten
#define GV_EFF_CDAFT     "RG_EFF_CDAFT"      // R5 Cooldown nach n Verlusten
#define GV_EFF_CDMIN     "RG_EFF_CDMIN"      // R5 Cooldown-Dauer (groesser = strenger)
#define GV_EFF_GIVE      "RG_EFF_GIVE"       // R13 Giveback
#define GV_EFF_RISK      "RG_EFF_RISK"       // R1 Risiko/Trade (skaliert via AutoScale die ganze Kaskade)
#define GV_EFF_REQSL     "RG_EFF_REQSL"      // R7 SL-Pflicht (einmal an -> intraday nicht abschaltbar)
#define GV_EFF_REQTP     "RG_EFF_REQTP"      // R7 TP-Pflicht
#define GV_EFF_CORR      "RG_EFF_CORR"       // R17 Korrelations-Deckel an/aus
#define EA_VER           "0.66"             // EINE Versions-Quelle (Log-Print + Cockpit-JSON) — hier hochzaehlen
#define PFX              "MMT_"
#define SLLINE           "MMT_slline"
#define TPLINE           "MMT_tpline"      // v0.46: optionale, ziehbare TP-Linie (InpTpLine); sonst Auto-TP aus InpRR
#define JOURNAL          "MamalTrading_Journal.csv"
#define LOCKFILE         "MamalTrading_Lockstate.dat"   // Lockstate-Spiegel (fail-closed/Tamper)
#define COCKPIT_FILE     "mamal_cockpit.json"           // v0.26: Live-Zustand fuer das localhost-Cockpit (DLL-freie Datei-Bruecke)
#define COCKPIT_TMP      "mamal_cockpit.tmp"            // atomar: erst tmp schreiben, dann FileMove -> kein Torn-Read
#define COCKPIT_OPEN     "mamal_cockpit_open.txt"       // Trigger: Server sieht die Datei -> oeffnet Browser
#define COCKPIT_PATHS    "mamal_files.txt"              // v0.37: Wegweiser im Common-Ordner -> echter Files-Pfad (Portable/Multi-Terminal-sicher)
#define COCKPIT_CMD      "mamal_cmd.txt"                // v0.39: Kommando vom Dashboard — NUR verschaerfend (endday = Selbstsperre), nie lockernd
#define LOCKSALT         "MMT-ls-7731"                  // HMAC-light Salt fuer Lockstate-Checksumme

double g_initialBalance = 0;
bool   g_initBalConfirmed = false;   // §04-fix: Basis stammt aus Input/GV/Lockstate (bestaetigt) — reine Auto-Ableitung darf NIE persistiert werden (weder GV noch Datei)
uint   g_lastActionMs   = 0;
uint   g_lastPanelMs    = 0;
uint   g_lastEnforceMs  = 0;   // P0-1 Close-Drossel
string g_panelSig       = "";
int    g_armed          = 0;
uint   g_armMs          = 0;
int    g_slClicks       = 0;    // v0.21: Klick-Zaehler fuer 3-Klick-SL-Setzen
double g_slClickPrice   = 0;    // Zonen-Anker-Preis
uint   g_slClickMs      = 0;    // Zeit des letzten Zonen-Klicks
string g_flash          = "";   // v0.21: letzte Meldung (z.B. Ablehnungsgrund) direkt im Panel zeigen
uint   g_flashMs        = 0;    // Zeit der letzten Meldung
uint   g_flashHold      = 6000; // v0.63: Standzeit DIESER Meldung. Manipulationsbefunde bleiben laenger stehen —
                                //   sie treten selten auf, und wer sie verpasst, verpasst genau das Wichtige.
bool   g_flashLoud      = false;// v0.64: die stehende Meldung ist ein Manipulationsbefund -> darf von harmlosen
                                //   Folgemeldungen nicht verdraengt werden (sonst waren die 120 s wirkungslos)
bool   g_lsMissWarned   = false;// v0.64: "Datei fehlt" schon gemeldet? Erzwungene Alerts NUR beim Zustandswechsel,
bool   g_lsCorruptWarned= false;//   sonst feuert bei dauerhaft unlesbarem Ordner jede Sekunde ein modaler Dialog
bool   g_flashInfo      = false;// v0.37: true = neutraler Hinweis (z.B. Cockpit), false = rote Ablehnung
string g_rkEditSync     = "";   // v0.49: zuletzt INS Eingabefeld geschriebener Wert — verhindert, dass DrawPanel die Tipp-Eingabe ueberschreibt
datetime g_noMasterSince = 0;   // v0.45: seit wann ist KEINE Instanz Master (0 = alles ok)
bool     g_noMasterWarned= false;// v0.45: Alarm nur einmal je Ausfall-Episode
bool   g_gvDirty        = false;// v0.22: GlobalVariables geaendert -> EIN gebuendelter Flush am Cycle-Ende (Wine-Crash-Schutz statt 4 synchroner Flushes je Tick)
int    g_fgTries        = 0;    // v0.28: Vordergrund-Flag nur begrenzt oft setzen (nicht jeden Cycle -> kein ChartSetInteger-Spam)
int    g_masterStreak   = 0;    // v0.28: wie viele Cycles in Folge Master (Hysterese: erst ab 2 wirklich handeln -> kein Startup-/Slow-Cycle-Burst)
double g_lastScopeSig   = 0.0;  // v0.31: Signatur der In-Scope-SL/TP letzter Cycle (User-Modify erkennen)
int    g_lastScopeN     = -1;   // v0.31: In-Scope-Order-Anzahl letzter Cycle
uint   g_modifyQuietMs  = 0;    // v0.31: Zeitpunkt des letzten erkannten User-Modify -> kurz KEINE EA-Close (kein OrderClose in laufenden Modify = Wine-Crash)
uint   g_lastCockpitMs  = 0;    // v0.26: Cockpit-JSON gedrosselt schreiben

// Close-Queue (echte ticketbasierte Schliessung mit Retry/Backoff/Journal)
int      g_qTicket[];
string   g_qReason[];
int      g_qTries[];
uint     g_qNextMs[];
// §06-fix: R7-Grace liegt jetzt persistent in GlobalVariables (RG_NK_/RG_NKH_), nicht mehr in Instanz-Arrays
uint     g_modifyQuietStart = 0;   // §06-fix: Beginn der laufenden Modify-Serie (Quiet-Fenster hart deckeln)
int      g_seenTicket[];           // §06-fix: zuletzt gesehene offene In-Scope-Tickets (History-Sichtbarkeits-Wachhund)
int      g_suspTicket[];           // verschwundene Tickets, die (noch) nicht in der History auffindbar sind
string   g_lockSig         = "";   // letzte geschriebene Lockstate-Signatur (Disk-Schonung)
bool     g_lsGuard         = false; // v0.63: laeuft gerade ein Abgleich? verhindert Rekursion WriteLockstate <-> ReconcileLockstate
uint     g_lastReconcileMs = 0;    // Drossel fuer R3-Reconcile in Cycle()
uint     g_lastLockReconcileMs = 0;// §05-fix (hoch): Drossel fuer periodische Lockstate-Rekonsiliation (faengt F3-Loeschen der Sperr-GVs)
datetime g_lastStaleWarnDay= 0;    // Drossel fuer Serverzeit-Drift-Hinweis (max 1x/Tag)
datetime g_lastTvWarnDay   = 0;    // Drossel fuer TickValue-Fallback-Warnung (max 1x/Tag)
bool     g_tvEstimate      = false;// §07-fix: Risiko beruht (teilweise) auf einer Schaetzung statt echtem TickValue -> im Panel/Cockpit sichtbar machen
datetime g_lastRdrWarnDay  = 0;    // §07-fix: Drossel fuer die R3-Rekonstruktions-Warnung (vorher CSV-Spam alle 15 s)
datetime g_lastRollWarn    = 0;    // §07-fix: Drossel fuer "Roll ohne Broker-Bestaetigung" (PC-Uhr-Manipulation)
int      g_srvOffset       = 0;    // Server-Offset (Sek): TimeCurrent - TimeLocal am letzten Tick
bool     g_srvOffsetSet    = false;
datetime g_lastSrvSeen     = 0;    // §04-fix (mittel): letzter beobachteter TimeCurrent-Stand — "frisch" = er hat sich seit der letzten Beobachtung bewegt

double Pip(){ return ((Digits==5 || Digits==3) ? 10*Point : Point); }
long DayKeyOf(datetime t){ return (long)(TimeYear(t)*10000+TimeMonth(t)*100+TimeDay(t)); }
// Server-Zeit, tickunabhaengig: MQL4 hat KEIN TimeTradeServer() (nur MQL5). Loesung: Serverzeit = PC-Uhr
// (TimeLocal) + gepflegtem Server-Offset (am letzten Tick aus TimeCurrent-TimeLocal). So laeuft die Zeit
// auch ohne neue Ticks weiter. Offset wird in OnTick/OnInit via UpdateSrvOffset() aktualisiert.
// §04-fix (mittel): Offset nur aus FRISCHER Serverzeit ableiten. Nach einem Neustart in tickloser Phase (Wochenende)
// liefert TimeCurrent() den Cache vom letzten Tick — ein daraus gebildeter Offset laesst SrvTime() um die gesamte
// Tick-Luecke (bis ~2,5 Tage) hinterherlaufen: abgelaufene Sperren re-aktivieren sich, SafeCloseAll schliesst zum
// Montags-Open. "Frisch" = TimeCurrent hat sich seit der letzten Beobachtung bewegt (irgendein Symbol lieferte eine
// Quote — auch aus OnTimer erkennbar), ODER der Kandidat passt zum persistierten letzten guten Offset.
void AdoptSrvOffset(datetime sc)
{
   g_srvOffset=(int)(sc - TimeLocal()); g_srvOffsetSet=true;
   if(!GlobalVariableCheck(GV_SRV_OFFSET) || (int)GlobalVariableGet(GV_SRV_OFFSET)!=g_srvOffset)
      GlobalVariableSet(GV_SRV_OFFSET,(double)g_srvOffset);   // aendert sich selten (Drift/DST) -> kaum Writes, Flush macht der Cycle/Terminal
}
void UpdateSrvOffset()
{
   datetime sc = TimeCurrent();
   if(sc<=0) return;
   bool fresh = (g_lastSrvSeen>0 && sc>g_lastSrvSeen);         // Serverzeit bewegt sich -> Quote ist frisch
   if(g_lastSrvSeen<=0)                                        // erster Aufruf nach Start: TimeCurrent kann der Wochenend-Cache sein
   {
      if(GlobalVariableCheck(GV_SRV_OFFSET))
      {
         int stored=(int)GlobalVariableGet(GV_SRV_OFFSET);
         int cand  =(int)(sc - TimeLocal());
         if(MathAbs(cand-stored)<=120) fresh=true;             // Kandidat ~= letzter guter Offset -> plausibel frisch
         else { g_srvOffset=stored; g_srvOffsetSet=true;       // stale (Tick-Luecke): letzten guten Offset nutzen, bis eine frische Quote kommt
                PrintFormat("Mamal: TimeCurrent %d s neben letztem gutem Offset (Tick-Luecke?) — nutze persistierten Offset, bis frische Quote da ist.", cand-stored); }
      }
      else fresh=true;                                         // kein Vorwissen (Erststart): Kandidat uebernehmen — besser als keine Serverzeit
   }
   if(sc>g_lastSrvSeen) g_lastSrvSeen=sc;
   if(fresh) AdoptSrvOffset(sc);
}
datetime SrvTime()
{
   if(g_srvOffsetSet)
   {
      datetime est = TimeLocal() + g_srvOffset;   // PC-Uhr + Offset -> bewegt sich auch ohne Ticks
      datetime sc  = TimeCurrent();
      if(sc>0 && (est-sc) > 6*3600 && DayKeyOf(g_lastStaleWarnDay)!=DayKeyOf(est))
      { g_lastStaleWarnDay=est; PrintFormat("Mamal: HINWEIS letzter Tick %d s alt — Zeit aus PC-Uhr+Server-Offset.", (int)(est-sc)); }
      return est;
   }
   // §07-fix: Offset noch ungesetzt -> zuerst den PERSISTIERTEN Offset nutzen. Der alte Fallback lieferte rohe PC-Lokalzeit
   //   (falsche Zeitzone) und verfaelschte damit DayKey und den GV_LAST_CLOSE-Floor, bevor die erste Serverzeit ankam.
   if(GlobalVariableCheck(GV_SRV_OFFSET)) return TimeLocal() + (int)GlobalVariableGet(GV_SRV_OFFSET);
   datetime sc2 = TimeCurrent();       // sonst: letzter Tick
   if(sc2>0) return sc2;
   return TimeLocal();                 // letzter Ausweg (reine PC-Zeit, Zeitzone unbekannt)
}
// Prop-Firm-Zeit-Profil (P0/P1-3): Tagesreset um InpDayResetHour (Server), Woche ab InpWeekStartDay. Default 0/0 = FTMO/Sonntag.
// §05-fix (hoch): Tagesreset-Stunde/Wochenstart NICHT direkt aus dem Input lesen, sondern aus dem persistierten EFFEKTIVEN
//   Wert. Sonst verschiebt eine INTRADAY-Aenderung von InpDayResetHour/InpWeekStartDay den Tages-/Wochen-Key -> kuenstlicher
//   RollNewDay/Wochen-Roll wiped Basis/R3/Serie/TargetHit/Wochensperre. Der neue Input greift erst zum ECHTEN Rollover
//   (dort adoptiert). Seed in OnInit; fehlt der GV -> Input (Erststart).
int EffResetHour(){ return GlobalVariableCheck(GV_EFF_RH) ? (int)GlobalVariableGet(GV_EFF_RH) : InpDayResetHour; }
int EffWeekStart(){ return GlobalVariableCheck(GV_EFF_WS) ? (int)GlobalVariableGet(GV_EFF_WS) : InpWeekStartDay; }
long ServerDayKey(){ return DayKeyOf(SrvTime() - EffResetHour()*3600); }
datetime NextServerMidnight(){ datetime sh=SrvTime()-EffResetHour()*3600; datetime nx=(sh-(sh%86400))+86400; return nx + EffResetHour()*3600; }
long WeekIdx(){ datetime t=SrvTime()-EffResetHour()*3600; MqlDateTime st; TimeToStruct(t,st); int dow=(st.day_of_week-EffWeekStart()+7)%7; return (long)(t/86400) - (long)dow; }   // B2: am Wochenstart-Tag ankern (Default Sonntag)
// §07-fix (hoch): PC-Uhr-Manipulation. SrvTime() = TimeLocal + Offset — wer die Windows-Uhr vorstellt, verschiebt den
//   Tages-/Wochen-Key und loeste damit einen RollNewDay aus, der Sperre, Tagesbasis, R3-Budget und Verlustserie wegwischte
//   (der naechste Tick korrigierte nur den Offset, nicht den geloeschten Zustand). TimeCurrent() kommt dagegen VOM BROKER
//   und laesst sich lokal nicht faelschen. Ein Roll wird deshalb nur noch akzeptiert, wenn die Broker-Zeit denselben
//   Tages-/Wochenwechsel zeigt. Ueber ein Wochenende ohne Ticks bedeutet das: der Roll passiert beim ersten echten Tick
//   (Marktoeffnung) — vorher kann ohnehin nicht gehandelt werden, die Sperre bleibt so lange bestehen (konservativ).
bool ServerDayRollConfirmed(long storedDay)
{
   datetime sc=TimeCurrent();
   if(sc<=0) return false;                                        // keine Broker-Zeit -> kein Roll
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
void WarnUnconfirmedRoll(string what)   // gedrosselt: sonst je Cycle eine Meldung
{
   if(SrvTime()-g_lastRollWarn < 300) return;
   g_lastRollWarn=SrvTime();
   Notify(TF("time.rolloverNotConfirmed",what));
   Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("%s ohne Broker-Bestaetigung -> Roll unterdrueckt (Uhr-Manipulation?)",what));
}
datetime ServerDayStart(){ datetime sh=SrvTime()-EffResetHour()*3600; return (sh-(sh%86400))+EffResetHour()*3600; }   // §04-fix: Beginn des AKTUELLEN Servertags (= Moment, an dem der Roll haette stattfinden sollen)
datetime ServerWeekStart(){ return (datetime)(WeekIdx()*86400) + EffResetHour()*3600; }                              // §04-fix: Beginn der aktuellen Woche (R18-Anker)
// §04-fix (mittel): Balance zum Anker-Zeitpunkt aus der Broker-History rekonstruieren: aktuelle Balance minus aller
// SEITHER realisierten Nettos (inkl. Ein-/Auszahlungen — alles, was die Balance seit dem Anker bewegt hat, ueber ALLE
// Magics/Symbole, denn die Kontobalance ist kontoweit). War das Terminal ueber den Anker hinweg aus und liefen Nacht-
// SL-Hits, misst der verspaetete Roll sonst vom bereits gefallenen Niveau — FTMO-Limits koennen reissen, bevor der EA
// sperrt. Ohne Closes seit dem Anker ist die Summe 0 -> Ergebnis = aktuelle Balance (identisch zum alten Verhalten).
// Grenze: sieht nur den im Kontohistorie-Tab geladenen Bereich (dokumentierte OrdersHistoryTotal-Schwaeche) — liefert
// dann zu wenig Korrektur, nie eine falsche; max() unten verhindert jede Verschlechterung gegen den Ist-Zustand.
double ReconstructedBalanceAt(datetime anchor)
{
   double sum=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderCloseTime()<anchor) continue;
      if(OrderType()==7) continue;   // Credit-Operation: bewegt Equity/Credit, NICHT die Balance (Typ 6 = Einzahlung gehoert dagegen hinein; geloeschte Pendings haben Profit 0)
      sum += OrderProfit()+OrderSwap()+OrderCommission();
   }
   return AccountBalance()-sum;
}

// v0.38: Challenge-Startbalance aus der Einzahlungs-Historie ableiten (erste Einzahlung = Kontogroesse).
// FTMO/Prop-Konten haben genau EINE initiale Balance-Buchung (Typ 6). Grenze: sieht nur den geladenen
// History-Bereich — findet er nichts, faellt der Aufrufer auf die aktuelle Balance zurueck.
double DepositBase()
{
   double first=0; datetime firstT=0;
   for(int i=0;i<OrdersHistoryTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderType()!=6) continue;         // 6 = Balance-Operation (Ein-/Auszahlung)
      if(OrderProfit()<=0) continue;       // nur Einzahlungen
      if(firstT==0 || OrderOpenTime()<firstT){ firstT=OrderOpenTime(); first=OrderProfit(); }
   }
   return first;
}

// P1-11: WatchScope — TOOL_ONLY/TOOL_PLUS_MANUAL fassen fremde Magics NICHT an; ALL_POSITIONS schon (nur Demo/Debug)
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
string EacfKey(int t){ return "RGEACF_"+IntegerToString(t); }   // §05-fix (hoch): EA-Close war TRADER-VERSCHULDEN (R7/R1/R8) -> zaehlt fuer Verlustserie (kein Laundering)
bool IsFaultCloseReason(string r){ return (StringFind(r,"R7")==0 || StringFind(r,"R8")==0 || StringFind(r,"R1 ")==0); }   // R7 SL/TP entfernt, R1 Ueberrisiko, R8 CRV — NICHT R12/Lock (das ist echter Schutz-Flat)
void MarkEaClosed(int t,string reason){ GlobalVariableSet(EaKey(t),(double)SrvTime()); if(IsFaultCloseReason(reason)) GlobalVariableSet(EacfKey(t),(double)SrvTime()); GlobalVariablesFlush(); }   // P0-3: sofort persistieren (Crash-fest)
// §07-fix: UnmarkEaClosed()/TakeEaClosed() waren toter Code (nirgends aufgerufen) — entfernt statt mitgeschleppt.
// P0-2/P0-4: verarbeitete POSITIONEN (Key = OpenTime_Type_Symbol_Magic_OpenPrice) persistent -> idempotent, same-second-robust
// §07-fix: FESTE Preis-Praezision statt MarketInfo(MODE_DIGITS). Der Digits-Wert ist nach einem Restart ohne das Symbol
//   im Market Watch nicht verfuegbar (Fallback 5) -> derselbe Verlust bekam einen anderen Key und wurde DOPPELT gezaehlt.
//   Hinweis (bewusste MT4-Grenze): zwei Positionen mit identischer Open-Sekunde, gleichem Preis, gleichem Symbol/Magic und
//   gleicher Richtung teilen sich weiterhin einen Key — MT4 hat keine Positions-ID, und Ticket taugt nicht (Teil-Closes).
string ProcKey(datetime ot,int ty,string sym,int magic,double openPrice){ return "RGP_"+IntegerToString((int)ot)+"_"+IntegerToString(ty)+"_"+sym+"_"+IntegerToString(magic)+"_"+DoubleToString(openPrice,8); }
string ProcKeyLegacy(datetime ot,int ty,string sym,int magic,double openPrice){ int dg=(int)MarketInfo(sym,MODE_DIGITS); if(dg<=0) dg=5; return "RGP_"+IntegerToString((int)ot)+"_"+IntegerToString(ty)+"_"+sym+"_"+IntegerToString(magic)+"_"+DoubleToString(openPrice,dg); }
bool   IsProcessed(string key){ return GlobalVariableCheck(key); }
bool   IsProcessedAny(string key,string legacyKey){ return (GlobalVariableCheck(key) || GlobalVariableCheck(legacyKey)); }   // Migration: alte Marker weiter respektieren -> keine Doppelwertung beim Update
// v0.45 (Verify): EIN Marker-Paar pro Position. RGM_ = "im Cockpit schon gezeigt" — wird von BEIDEN Pfaden
//   gesetzt, damit ein Trade nie als CLOSE *und* als CLOSE_MAN im Netto landet (Scope-/Magic-Wechsel).
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
// §04-fix (hoch): kompletter Zustands-Reset bei Kontowechsel — GVs sind terminalweit und tragen KEINE Konto-Nr.,
// darum gehoert der gespeicherte Zustand (Basen/Sperren/Serie/Marker) nach einem Login-Wechsel NICHT zum neuen Konto.
void WipeAllState()
{
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   { string nm=GlobalVariableName(i); if(StringFind(nm,"RG")==0) GlobalVariableDel(nm); }   // gesamter Namespace: RG_*, RGP_*, RGEAC_*
   if(FileIsExist(LOCKFILE)) FileDelete(LOCKFILE);   // signierten Lockstate des alten Kontos nicht wiederherstellen
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
   UpdateSrvOffset();          // Server-Offset seeden (TimeCurrent meist schon gueltig)
   // v0.40-fix: InpMagic=0 machte Panel-Trades von manuellen ununterscheidbar (R22-Failsafe, Scope-Chaos,
   //   Close-Erkennung blind). Ungueltige Magic -> Default erzwingen, laut melden.
   if(InpMagic<=0){ InpMagic=990201; Notify(T("cfg.magicInvalid")); }
   ApplyFundedAndProfile();    // #11/#13: Funded-Gate (TOOL_ONLY) + Prop-Firm-Profil-Log
   ObjectsDeleteAll(0,PFX);   // B20: Panel-Objekte heissen MMT_ (nicht RG_) — vorher No-Op
   // §04-fix (hoch): Konto-Bindung. GVs/Lockstate sind terminalweit ohne Konto-Nr. — nach einem Kontowechsel
   //   (Demo->Challenge->Verification->Funded im selben Terminal) wuerde der EA sonst gegen die BASEN des ALTEN
   //   Kontos rechnen (Sperren tot bzw. Phantom-Sperre + Zwangs-Close). Bei Login-Wechsel -> kompletter State-Reset.
   long acct=(long)AccountNumber();
   if(acct>0)   // acct<=0 = (noch) nicht verbunden -> keinen Reset gegen eine Phantom-0 ausloesen
   {
      if(GlobalVariableCheck(GV_ACCOUNT) && (long)GlobalVariableGet(GV_ACCOUNT)!=acct)
      {
         long prev=(long)GlobalVariableGet(GV_ACCOUNT);
         PrintFormat("Mamal: KONTOWECHSEL %d -> %d erkannt — kompletter Zustands-Reset (Basen/Sperren/Serie), damit nicht gegen fremde Basis gerechnet wird.", prev, acct);
         Journal("ACCOUNT_SWITCH","-","-",0,0,0,0,0,StringFormat("Konto %d -> %d: State-Reset (fail-closed bis Basis bestaetigt)", prev, acct));
         WipeAllState();
      }
      GlobalVariableSet(GV_ACCOUNT,(double)acct);
   }
   // §04-fix (hoch): Herkunft der R4b-Basis merken. Nur InpInitialBalance oder ein bereits persistierter Wert
   //   gelten als BESTAETIGT; die reine Auto-Ableitung aus AccountBalance() ist beim Erst-Attach mitten in einer
   //   Challenge (nach Vorverlust) zu niedrig und wird unten fail-closed behandelt.
   double prevInit    = (GlobalVariableCheck(GV_INIT_BAL) && GlobalVariableGet(GV_INIT_BAL)>0) ? GlobalVariableGet(GV_INIT_BAL) : 0;
   bool initFromInput = (InpInitialBalance>0);
   // v0.37-fix: Plausibilitaet. Eine Basis WEIT unter der Kontobalance ist fast sicher ein Dezimaltrennzeichen-
   //   Tippfehler (z.B. "163.659" oder "163,659" -> MT4 liest 163,66 statt 163659). Der R4b-Max-Loss-Floor laege
   //   sonst weit unter der Balance -> Schutz praktisch AUS. Input verwerfen.
   // v0.38-fix (Verify): Guard MUSS vor der Store/Lockstate-Ermittlung laufen — sonst umgeht der verworfene
   //   Input die bestehende bestaetigte Basis und der Auto-Zweig ueberschreibt sie.
   if(initFromInput && AccountBalance()>0 && InpInitialBalance < AccountBalance()*0.1)
   {
      Notify(TF("base.initialBalanceImplausible",DoubleToString(InpInitialBalance,2),DoubleToString(AccountBalance(),2),DoubleToString(AccountBalance(),2)));
      Journal("BASEWARN","-","-",0,0,0,0,0,StringFormat("InpInitialBalance %.2f unplausibel (<10%% von Balance %.0f) -> verworfen",InpInitialBalance,AccountBalance()));
      initFromInput=false;   // -> Store/Lockstate/Auto uebernehmen (unten), Tighten-Only bleibt intakt
   }
   bool initFromStore = (!initFromInput && GlobalVariableCheck(GV_INIT_BAL) && GlobalVariableGet(GV_INIT_BAL)>0);
   double lsInit      = (!initFromInput && !initFromStore) ? LsStoredInitBal() : 0;   // §04-fix (mittel): Lockstate-Datei ueberlebt den 4-Wochen-GV-Ablauf
   bool initFromFile  = (lsInit>0);
   if(initFromInput)
   {
      g_initialBalance=InpInitialBalance;
      if(prevInit>0 && InpInitialBalance < prevInit-0.01)   // §05-fix (hoch): Basis-ABSENKUNG intraday schiebt die R4b-Sperre weiter weg -> ablehnen (tighten-only); hoehere Basis behalten, Absenken wirkt erst zum Tageswechsel
      {
         g_initialBalance=prevInit;
         Notify(TF("base.initialBalanceLoweringIgnored",DoubleToString(prevInit,2),DoubleToString(InpInitialBalance,2),DoubleToString(prevInit,2)));
         Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("Basis-Absenkung %.2f->%.2f intraday abgelehnt (tighten-only)",prevInit,InpInitialBalance));
      }
   }
   else if(initFromStore) g_initialBalance=GlobalVariableGet(GV_INIT_BAL);
   else if(initFromFile)  g_initialBalance=lsInit;
   else   // v0.38: VOLL-AUTO — Challenge-Basis aus der Einzahlungs-Historie, Fallback aktuelle Balance.
   {      //   Einmal abgeleitet wird sie persistiert (stabil ueber Neustarts) -> nie wieder "BASIS UNSICHER".
      double dep=DepositBase();
      // v0.38-fix (Verify): unplausibel kleine "Einzahlung" (z.B. Fee-Refund bei gefiltertem History-Tab)
      //   NICHT als Basis nehmen — R4b waere sonst wirkungslos (Basis << Balance -> DD clampt auf 0).
      if(dep>0 && AccountBalance()>0 && dep < AccountBalance()*0.1)
      { Journal("INFO","-","-",0,0,0,0,0,StringFormat("Einzahlung %.2f unplausibel klein ggue. Balance %.0f (Historie unvollstaendig?) -> Fallback Balance",dep,AccountBalance())); dep=0; }
      if(dep>0)
      { g_initialBalance=dep;
        Journal("INFO","-","-",0,0,0,0,0,StringFormat("Auto-Basis aus Einzahlung: %.2f (Historie)",dep)); }
      else
      { g_initialBalance=AccountBalance();
        if(g_initialBalance>0) Notify(TF("base.autoFromBalance",DoubleToString(g_initialBalance,2))); }
      // v0.38-fix (Verify): Tighten-Only auch im Auto-Zweig — eine bereits bestaetigte hoehere Basis
      //   (Store/Lockstate) darf durch eine niedrigere Auto-Ableitung NIE abgesenkt werden.
      if(prevInit>0 && g_initialBalance<prevInit) g_initialBalance=prevInit;
   }
   g_initBalConfirmed = (g_initialBalance>0);   // v0.38: jede Quelle gilt — Basis wird sofort festgeschrieben (tighten-only schuetzt weiterhin gegen Absenkung)
   if(g_initBalConfirmed)
      GlobalVariableSet(GV_INIT_BAL,g_initialBalance);         // v0.38: auch die Auto-Basis persistieren — Stabilitaet ueber Neustarts (Wert ist ab jetzt die verbindliche Referenz)
   // P0-2: keine gueltige Max-Loss-Basis -> fail-closed (keine neuen Trades), bis Kontodaten/InpInitialBalance da sind
   if(g_initialBalance<=0)
   { GlobalVariableSet(GV_BASE_WARN,1); GlobalVariablesFlush(); Notify(T("base.missingFailClosed")); }
   // B1: warnen, wenn die Max-Loss-Basis stark von der echten Kontobasis abweicht (R4b rechnet dagegen!)
   {
      double ab=AccountBalance();
      if(g_initialBalance>0 && ab>0 && MathAbs(g_initialBalance-ab)/MathMax(g_initialBalance,ab) > 0.25)
         Notify(TF("base.maxLossBaseMismatch",DoubleToString(g_initialBalance,2),DoubleToString(ab,2),DoubleToString(g_initialBalance,2)));
   }

   // §05-fix (hoch): effektive Tagesreset-Stunde/Wochenstart seeden (Erststart) bzw. anstehende Config-Aenderung melden.
   //   Wird NICHT vom Input ueberschrieben — die Uebernahme passiert erst am echten Tages-/Wochen-Rollover (RollNewDay/Cycle).
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
   // v0.38: Der fruehere Fail-Closed-Block "Auto-Basis unbestaetigt" entfaellt — die Basis wird jetzt automatisch
   //   aus der Einzahlungs-Historie (bzw. Balance) abgeleitet, sofort bestaetigt und persistiert. Wer eine abweichende
   //   Basis will, setzt InpInitialBalance (tighten-only bleibt aktiv: Absenken wirkt erst zum Tageswechsel).

   ReconcileLockstate();   // Lockstate-Datei (fail-closed) abgleichen, bevor irgendetwas handelt
   // v0.42: Boot-Diagnose — Ground Truth ins Journal (jede Instanz; klaert Registry/Floor/History/Kontext)
   // v0.66: Backfill-Zustand mit hineinschreiben. Der Nachtrag lief einmal ins Leere, und von aussen war
   //   nicht feststellbar, ob der Schalter ueberhaupt an war — Diagnose per Ferndeutung statt per Beleg.
   Journal("INFO",Symbol(),"-",0,0,0,0,0,StringFormat("BootDiag v%s: RGOPN=%d HistTotal=%d Floor=%s Ctx=%s Magic=%d Backfill=%s MasterSlot=%s",EA_VER,CountOpn(),OrdersHistoryTotal(),TimeToString((datetime)GlobalVariableGet(GV_LAST_CLOSE)),IsTradeContextBusy()?"BUSY":"frei",InpMagic,(InpHistoryBackfill?(GlobalVariableCheck(GV_BACKFILL)?"erledigt":"an"):"aus"),GlobalVariableCheck(GV_MASTER)?"da":"FEHLT"));
   ReconcileDayRisk();     // R3: Tagesbudget nach Crash/Restart aus Broker-Daten wiederherstellen
   ChartSetInteger(0,CHART_FOREGROUND,false);
   g_fgTries=8;                              // v0.28: Vordergrund die ersten paar Zyklen erneut versuchen (falls Init nicht haelt), dann Ruhe
   CreateControls();
   // §07-fix: Rueckgabe pruefen + Input validieren. Der Timer traegt das TICKUNABHAENGIGE Enforcement (P0-1) —
   //   scheiterte EventSetTimer oder war InpTimerSeconds<=0, lief der Schutz still nur noch auf Ticks.
   int tsec=InpTimerSeconds; if(tsec<1){ tsec=1; Notify(T("cfg.timerSecondsInvalid")); }
   if(tsec>60){ tsec=60; Notify(T("cfg.timerSecondsCapped")); }
   if(!EventSetTimer(tsec))
   { Notify(T("watchdog.timerFailed"));
     Journal("PROTECT_OFF","-","-",0,0,0,0,0,StringFormat("EventSetTimer fehlgeschlagen (err=%d) — nur noch tick-getriebenes Enforcement",GetLastError())); }
   PrintFormat("Mamal-Trading v%s aktiv (%s). Scope=%d. Profil=%s Funded=%s Test=%s SL-Klicks=%d. R15-min-SL=%s. Cockpit=%s(Port %d). UNGETESTET bis F7=0 Errors.", EA_VER, Symbol(), (int)InpWatchScope, PropFirmName(InpPropFirm), InpFundedMode?"AN":"aus", InpTestMode?"AN":"aus", InpSlClicksToMove, (InpMinStopPips>0?"an":"AUS"), (InpCockpit?"an":"aus"), InpCockpitPort);
   if(InpWatchScope==ALL_POSITIONS) Notify(T("cfg.watchScopeAllPositions"));
   // R22: beim Start vorhandene manuelle Positionen werden ebenfalls geschlossen (kein Bestandsschutz) -> vorher laut ansagen
   if(InpCloseManualTrades)
   {
      if(InpMagic==0)   // FAILSAFE: Panel-Trades traegen dann selbst Magic 0 und waeren von manuellen nicht unterscheidbar
      { Notify(T("cfg.r22DisabledMagicZero"));
        Journal("INFO","-","-",0,0,0,0,0,"R22 wegen InpMagic=0 deaktiviert (Failsafe)"); }
      else
      {
         int man=0;
         for(int mi=OrdersTotal()-1;mi>=0;mi--)
            if(OrderSelect(mi,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==0) man++;
         // Ehrlich: OnInit schliesst nichts. Der Close laeuft ueber den Enforcement-Cycle und braucht die bestaetigte
         // Master-Instanz (>=2 Cycles) -> typischerweise 1-3 Sekunden, bei geschlossenem Markt (err 132) deutlich laenger.
         if(man>0)
         { Notify(TF("cfg.r22ManualOrdersOpen",IntegerToString(man)));
           Journal("INFO","-","-",0,0,0,0,0,StringFormat("R22 Start: %d manuelle Order(s) vorgefunden -> werden geschlossen",man)); }
         else Notify(T("cfg.r22PanelOnly"));
         // R22 haengt bewusst NICHT am WatchScope -> gilt kontoweit ueber alle Symbole und auch im FundedMode
         if(InpFundedMode)                   Notify(T("cfg.r22FundedNote"));
         if(InpWatchScope==TOOL_PLUS_MANUAL) Notify(T("cfg.r22ScopeNote"));
      }
   }
   Cycle();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){ EventKillTimer();
   // v0.42-fix (KRITISCH): Master freigeben durch SET AUF 0, NICHT loeschen! GlobalVariableSetOnCondition kann
   //   eine FEHLENDE Variable nicht anlegen (Err 4058) — nach einem Del konnte NIE wieder ein Master gewaehlt
   //   werden (Deadlock: kein Enforcement, keine Close-Wertung, keine Cockpit-Daten, bis F3/Neuanlage).
   if(GlobalVariableCheck(GV_MASTER) && GlobalVariableGet(GV_MASTER)==(double)ChartID()){ GlobalVariableSet(GV_MASTER,0.0); GlobalVariableSet(GV_MASTER_HB,0.0); }   // Slot existiert weiter -> sofortige Uebernahme durch die naechste Instanz
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
   // v0.49: Enter im Eingabefeld bestaetigt genauso wie der SETZEN-Knopf
   if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam==PFX+"rkin"){ ApplyWeekRiskFromEdit(); return; }
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam==PFX+"buy"){  ObjectSetInteger(0,sparam,OBJPROP_STATE,false); GateClick(true);  }
      if(sparam==PFX+"sell"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); GateClick(false); }
      if(sparam==PFX+"cockpit"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); OpenCockpit(); }   // v0.26
      // v0.40: Close-Buttons — Risiko-REDUKTION, laufen deshalb IMMER (auch bei Sperre/Cooldown), sofort ohne Bestaetigung
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
   { ObjectSetString(0,PFX+"prev",OBJPROP_TEXT,Clip(PreviewText(),42)); ChartRedraw(0); return; }   // v0.37: eine Zeile sofort; Volltext-Umbruch macht DrawPanel
   if(id==CHARTEVENT_CLICK)
   {
      int cx=(int)lparam, cy=(int)dparam;
      if(cx>=PS(12) && cx<=PS(312) && cy>=PS(16) && cy<=PS(16)+PS(PanelH())) return;   // v0.25: Klick AUFS PANEL nicht als SL-Zone werten (v0.37: mit InpPanelScale skaliert, wie die Karte)
      int sub=0; datetime tt=0; double pp=0;
      // §07-fix: nur Klicks im HAUPTFENSTER (sub==0) als SL-Zone werten — in einem Indikator-Unterfenster liefert
      //   ChartXYToTimePrice den Indikatorwert (z.B. RSI 42) und der wuerde als SL-Preis uebernommen.
      if(ChartXYToTimePrice(0,cx,cy,sub,tt,pp) && pp>0 && sub==0)
         SlZoneClick(NormalizeDouble(pp,Digits));   // erst nach InpSlClicksToMove Klicks in dieselbe Zone setzen
   }
}

void GateClick(bool isBuy)
{
   if(!InpFomoGate){ DoEntry(isBuy); return; }
   int want=isBuy?1:2;
   if(g_armed==want && (GetTickCount()-g_armMs) >= (uint)(InpFomoSeconds*1000)){ g_armed=0; DoEntry(isBuy); }
   else { g_armed=want; g_armMs=GetTickCount(); Notify(TF("fomo.arm",IntegerToString(InpFomoSeconds),isBuy?"BUY":"SELL")); g_panelSig=""; }
}

double DayStartBaseInput()   // v0.37-fix: InpDayStartBase nur wenn plausibel; Dezimaltrenner-Tippfehler (z.B. 163.659 statt 163659) -> als nicht gesetzt behandeln
{
   double d=InpDayStartBase;
   if(d>0 && AccountBalance()>0 && d < AccountBalance()*0.1) return 0;   // unplausibel klein -> ignorieren (Tagesbasis bleibt unsicher)
   return d;
}
void RollNewDay(bool firstAttach=false)
{
   // P0-5: FTMO-Basis = max(Balance,Equity) am Mitternachts-Roll.
   // v0.38: VOLL-AUTO — Erststart mitten am Tag rekonstruiert die Mitternachtsbasis aus der History
   //   (kein Warn-Flag/keine Sperre mehr); InpDayStartBase bleibt als manueller Override.
   double dsb = DayStartBaseInput();   // v0.37-fix: tippfehler-geprueft
   double dayBase;
   if(firstAttach && dsb>0) dayBase = dsb;                                                                // §04-fix (hoch): manuelle Mitternachtsbasis NUR beim Erststart
   else if(firstAttach)     // v0.38: Erststart mitten am Tag -> echte Mitternachtsbasis aus der History rekonstruieren
   {                        //   (Balance minus seitdem realisierte Ergebnisse). Konservativ nach oben gegen Ist-Zustand.
      double rec = ReconstructedBalanceAt(ServerDayStart());
      dayBase = MathMax(rec, MathMax(AccountBalance(), AccountEquity()));
      Journal("INFO","-","-",0,0,0,0,0,StringFormat("Auto-Tagesbasis (Erststart): %.2f (rekonstruiert %.2f)",dayBase,rec));
   }
   else                                                                                                   // Folgetage: echter Mitternachts-Snapshot — bei VERSPAETETEM Roll (EA war
   {                                                                                                      // ueber die Reset-Grenze aus) zusaetzlich die Mitternachts-Balance aus der
      double rec = ReconstructedBalanceAt(ServerDayStart());                                              // History rekonstruieren (§04-fix mittel): Nacht-SL-Hits senken sonst die
      dayBase = MathMax(MathMax(AccountBalance(), AccountEquity()), rec);                                 // Basis und das 2%-Limit misst vom gefallenen Niveau. Beim puenktlichen
   }                                                                                                      // Roll ist rec == Balance (keine Closes seit Anker) -> Verhalten unveraendert.
   if(InpDayResetHour!=EffResetHour()){ GlobalVariableSet(GV_EFF_RH,(double)InpDayResetHour); Notify(TF("time.dayResetHourActive",IntegerToString(InpDayResetHour))); }   // §05-fix: geaenderten Input erst am echten Rollover uebernehmen
   // §05-fix (hoch): Basis-Aenderung (auch Absenkung) erst am echten Tageswechsel uebernehmen.
   // v0.38-fix (Verify): NUR plausible Werte — der Dezimaltrenner-Tippfehler (163.66 statt 163659), den OnInit
   //   verwirft, darf auch hier nicht durchrutschen (R4b waere sonst still deaktiviert).
   if(!firstAttach && InpInitialBalance>0 && MathAbs(InpInitialBalance-g_initialBalance)>0.01
      && !(AccountBalance()>0 && InpInitialBalance < AccountBalance()*0.1))
   { g_initialBalance=InpInitialBalance; g_initBalConfirmed=true; GlobalVariableSet(GV_INIT_BAL,InpInitialBalance);
     Notify(TF("base.challengeBaseRollover",DoubleToString(InpInitialBalance,2))); }
   GlobalVariableSet(GV_DAYSTART_EQ,  dayBase);
   GlobalVariableSet(GV_DAYSTART_DAY, (double)ServerDayKey());
   GlobalVariableSet(GV_LOCK_UNTIL,   0); ClearLockWhy();   // v0.65b: sonst klebt der Grund von gestern an der naechsten Sperre
   GlobalVariableSet(GV_DAY_RISK,     0);
   GlobalVariableSet(GV_CONSEC,       0);
   // §07-fix: einen noch LAUFENDEN Cooldown nicht am Tageswechsel kappen — sonst war R5 kurz vor Mitternacht
   //   systematisch verkuerzt bzw. durch Warten bis 00:00 umgehbar. Abgelaufene Cooldowns werden weiterhin genullt.
   { datetime cdNow=GlobalVariableCheck(GV_COOLDOWN)?(datetime)GlobalVariableGet(GV_COOLDOWN):0;
     GlobalVariableSet(GV_COOLDOWN, (cdNow>SrvTime()) ? (double)cdNow : 0); }
   GlobalVariableSet(GV_PEAK_EQ,      dayBase);
   GlobalVariableSet(GV_TARGET_HIT,   0);
   // v0.38-fix (Verify): BASE_WARN nicht blind nullen — der Fail-Closed-Fall "keine gueltige Kontobasis"
   //   (g_initialBalance<=0, z.B. EA-Start vor dem Broker-Handshake) muss den Roll ueberleben, sonst
   //   liefe R4b dauerhaft mit Basis 0 (fail-open).
   GlobalVariableSet(GV_BASE_WARN,    (g_initialBalance<=0) ? 1 : 0);
   // v0.30-fix: EFF-Limits + Schutz-aus-Zaehler werden NICHT hier gesetzt (RollNewDay laeuft auch aus OnInit auf JEDER Instanz).
   //            Der Master setzt sie einmal pro Tag in Cycle() -> deterministisch = Master-Input (kein loses Limit durch Init-Reihenfolge).
   GlobalVariablesFlush();
   PrintFormat("Mamal: neuer Handelstag. Basis=%.2f", dayBase);
}

bool IsHardLocked(){ return GlobalVariableCheck(GV_HARD_LOCK) && GlobalVariableGet(GV_HARD_LOCK)>0.5; }
bool IsDayLocked(){ if(!GlobalVariableCheck(GV_LOCK_UNTIL)) return false; datetime u=(datetime)GlobalVariableGet(GV_LOCK_UNTIL); return (u>0 && SrvTime()<u); }
bool IsWeekLocked(){ return GlobalVariableCheck(GV_WEEK_LOCK) && (long)GlobalVariableGet(GV_WEEK_LOCK)==WeekIdx(); }
bool IsLocked(){ return IsDayLocked() || IsHardLocked() || IsWeekLocked(); }
bool CooldownActive(){ if(!GlobalVariableCheck(GV_COOLDOWN)) return false; return SrvTime() < (datetime)GlobalVariableGet(GV_COOLDOWN); }
bool TargetHit(){ return GlobalVariableCheck(GV_TARGET_HIT) && GlobalVariableGet(GV_TARGET_HIT)>0.5; }
bool BaseWarn(){ return GlobalVariableCheck(GV_BASE_WARN) && GlobalVariableGet(GV_BASE_WARN)>0.5; }
double TotalDDpct(){ double eq=AccountEquity(); if(g_initialBalance<=0) return 0; double d=(g_initialBalance-eq)/g_initialBalance*100.0; return d>0?d:0; }   // R4b
// v0.30 Selbst-Sperre: effektives Limit = enger stellbar sofort, LOCKERN erst zum Tageswechsel (RG_EFF_* wird am Tages-Roll aus dem Input gesetzt; intraday nur verschaerft).
// §06-fix (mittel): (a) auf ALLE sperr-relevanten Inputs ausgeweitet — bisher waren nur Daily/MaxLoss geschuetzt, waehrend
//   Wochenlimit, Warn-Gate, R5/R6-Parameter, Giveback, Risiko/Trade und sogar die SL/TP-Pflicht intraday frei lockerbar waren.
//   (b) InpTightenOnly selbst gelatcht: die Selbst-Sperre war mit einem einzigen Input-Flip abschaltbar (Widerspruch zu
//   R4 "Immutabilitaet nicht konfigurierbar" und R10 No-Override). Der Latch wird nur am Tages-Roll aus dem Input neu gesetzt.
// §07-fix: seltene, aber kritische Latches (Sperre gesetzt / Tagesziel erreicht) SOFORT persistieren statt erst beim
//   gebuendelten Flush am Cycle-Ende — ein Crash im Fenster dazwischen liess den frisch gesetzten Zustand verschwinden.
//   Nicht waehrend einer laufenden Handelsoperation flushen (Wine-Schutz, wie beim regulaeren Flush).
void PersistLatch(){ g_gvDirty=true; if(!IsTradeContextBusy()){ GlobalVariablesFlush(); g_gvDirty=false; } }
bool TightenOn(){ if(InpTightenOnly) return true; return (GlobalVariableCheck(GV_TIGHT_LATCH) && GlobalVariableGet(GV_TIGHT_LATCH)>0.5); }
double EffMinPct(string gv,double inp)   // kleiner = strenger; <=0 bedeutet AUS (= schwaechster Zustand)
{
   if(!TightenOn() || !GlobalVariableCheck(gv)) return inp;
   double st=GlobalVariableGet(gv);
   if(st<=0)  return inp;      // gespeichert war AUS -> jeder Input (auch ein strengerer) gilt sofort
   if(inp<=0) return st;       // Input AUS = lockerer -> gespeicherten Wert behalten
   return MathMin(inp,st);
}
double EffMaxNum(string gv,double inp)   // groesser = strenger (z.B. Cooldown-Dauer)
{
   if(!TightenOn() || !GlobalVariableCheck(gv)) return inp;
   return MathMax(inp,GlobalVariableGet(gv));
}
bool EffFlagOn(string gv,bool inp)       // einmal AN -> intraday nicht abschaltbar
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
// v0.36: gewuenschtes Risiko/Trade = der im Panel fuer DIESE Woche gewaehlte Wert; sonst der Input-Default.
//   Wird zur Basis der ganzen Auto-Scale-Kaskade (Idee/Heat/Tagesbudget). Die Trade-ANZAHL-Regeln (R5/R6-Zaehler)
//   haengen bewusst NICHT hieran — sie bleiben InpCooldownAfter/InpLockAfter.
//   v0.62: Der WERT haengt NICHT mehr am Wochen-Index. Frueher fiel er beim Wochenwechsel auf den
//   Input-Default zurueck, solange die neue Woche nicht bestaetigt war — dann schloss R1 (EnforceRisk,
//   Vergleich gegen EffRiskPct()) am Montag Wochenend-Positionen zwang, die nach dem zuletzt
//   bestaetigten Wochenwert korrekt dimensioniert waren. Der Index steuert jetzt ausschliesslich die
//   BESTAETIGUNG (WeekRiskSet) — also ob gehandelt werden darf, nicht mit welcher Groesse gerechnet wird.
double DesiredRiskPct()
{
   if(GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0)
      return GlobalVariableGet(GV_WEEK_RISK);
   return InpRiskPerTradePct;
}
double EffRiskPct(){ double r=EffMinPct(GV_EFF_RISK,DesiredRiskPct()); if(r>1.0) r=1.0; if(r<0) r=0; return r; }   // Basis = Wochenwahl/Input; Tages-Tighten-Only bleibt als Intraday-Absicherung darueber (kein Hochsetzen innerhalb des Tages)
double RiskCap(){ double m=InpRiskMaxPct; if(m<=0 || m>1.0) m=1.0; return m; }   // Waehler-Obergrenze, hart bei 1,0 %
// v0.36: vorgemerkte Erhoehung (fuer die naechste Woche) — 0, wenn keine.
double PendingWeekRisk(){ return GlobalVariableCheck(GV_WEEK_RISK_NXT) ? GlobalVariableGet(GV_WEEK_RISK_NXT) : 0; }
// v0.36: der User waehlt sein Wochen-Risiko im Panel. Semantik "einmal fuer die ganze Woche": die ERSTE Wahl einer Woche
//   ist frei; danach ist die Woche FEST — JEDE Aenderung (hoch ODER runter) greift erst zum naechsten Wochenwechsel
//   (bewusst gewaehltes Risiko = fuer die Woche gebunden; kein Herum-Justieren, auch kein Senken). Prop = Eigenkonto.
void SetWeekRisk(double v)
{
   v = NormalizeDouble(v,2);
   if(v < InpRiskStep) v = InpRiskStep;   // nicht unter eine Schrittweite
   if(v > RiskCap())   v = RiskCap();
   long   wk    = WeekIdx();
   bool   fresh = (!GlobalVariableCheck(GV_WEEK_RISK) || GlobalVariableGet(GV_WEEK_RISK)<=0
                   || (long)GlobalVariableGet(GV_WEEK_RISK_IDX)!=wk);   // diese Woche noch nicht gesetzt
   double cur   = DesiredRiskPct();
   if(fresh)   // ERSTE Wahl der Woche -> frei, sofort wirksam; danach ist die Woche gebunden
   {
      GlobalVariableSet(GV_WEEK_RISK,     v);
      GlobalVariableSet(GV_WEEK_RISK_IDX, (double)wk);
      if(GlobalVariableCheck(GV_WEEK_RISK_NXT)) GlobalVariableDel(GV_WEEK_RISK_NXT);
      GlobalVariableSet(GV_EFF_RISK,v);   // sofort wirksam (sonst wuerde der Tages-Tighten-Only-Layer die erste Wahl runterdruecken)
      PersistLatch();
      Notify(TF("risk.set.confirmed",DoubleToString(v,2)));
      Journal("INFO","-","-",0,0,0,0,v,StringFormat("Wochen-Risiko gesetzt: %.2f%% (fest fuer die Woche)",v));
   }
   else if(MathAbs(v-cur)<=0.0001)   // zurueck auf den aktuell fixen Wert getippt -> evtl. Vormerkung aufheben
   {
      if(GlobalVariableCheck(GV_WEEK_RISK_NXT)){ GlobalVariableDel(GV_WEEK_RISK_NXT); PersistLatch(); Notify(TF("cfg.weekRiskPendingCancelled",DoubleToString(cur,2))); }
      else Notify(TF("cfg.weekRiskAlreadySet",DoubleToString(cur,2)));
   }
   else   // JEDE Aenderung (hoch ODER runter) innerhalb der laufenden Woche -> fuer naechste Woche vormerken
   {
      GlobalVariableSet(GV_WEEK_RISK_NXT, v); PersistLatch();
      Notify(TF("risk.set.pending",DoubleToString(v,2),DoubleToString(cur,2)));
      Journal("INFO","-","-",0,0,0,0,v,StringFormat("Wochen-Risiko-Aenderung %.2f%% vorgemerkt (ab naechster Woche)",v));
   }
   g_panelSig="";
}
void ChangeWeekRisk(int dir)   // Panel [-]/[+]: auf einer bestehenden Vormerkung aufbauen, sonst auf dem aktuellen Wert
{
   double base = (PendingWeekRisk()>0) ? PendingWeekRisk() : DesiredRiskPct();
   SetWeekRisk(base + dir*InpRiskStep);
}
// v0.49: Ist das Wochen-Risiko fuer die LAUFENDE Woche bewusst gesetzt worden?
bool WeekRiskSet()
{
   return (GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0
           && GlobalVariableCheck(GV_WEEK_RISK_IDX) && (long)GlobalVariableGet(GV_WEEK_RISK_IDX)==WeekIdx());
}
// v0.62: Steht die woechentliche Festlegung aus (R23)? EINE Quelle fuer Gate, Panel-Status, Button-Graufaerbung
//   und Unterzeile. Bewusst aus den LOKALEN Inputs dieser Instanz — jede Instanz entscheidet fuer sich, ob sie
//   handeln laesst. Der Wochen-Roll (Master) darf diese Entscheidung NICHT global vorwegnehmen: sonst haette
//   ein Chart mit InpRequireWeeklyRisk=false, der zufaellig Master ist, das Gate fuer alle anderen aufgehoben.
bool WeekRiskPending(){ return (InpRiskChooser && InpRequireWeeklyRisk && !WeekRiskSet()); }
// v0.49: Eingabefeld auswerten — der Trader tippt seinen Wochenwert und bestaetigt.
//   Dezimalkomma wird akzeptiert (deutsche Tastatur schreibt "0,25"); ohne diese Umwandlung
//   laese MQL4 daraus 0 und wuerde die Eingabe stillschweigend verwerfen.
void ApplyWeekRiskFromEdit()
{
   string t=ObjectGetString(0,PFX+"rkin",OBJPROP_TEXT);
   StringReplace(t,",","."); StringReplace(t,"%",""); StringReplace(t," ","");
   StringTrimLeft(t); StringTrimRight(t);
   double v=StringToDouble(t);
   if(v<=0 || v>1.0)
   {
      Notify(TF("risk.set.invalid",t));
      g_rkEditSync="";   // Feld auf den gueltigen Stand zuruecksetzen
      g_panelSig=""; return;
   }
   SetWeekRisk(v);
   g_rkEditSync=""; g_panelSig="";   // Feld mit dem tatsaechlich uebernommenen Wert neu beschriften
}
int  EffLockAfter(){     return (int)EffMinPct(GV_EFF_LOCKAFT,(double)InpLockAfter);    }
int  EffCooldownAfter(){ return (int)EffMinPct(GV_EFF_CDAFT,  (double)InpCooldownAfter);}
int  EffCooldownMin(){   return (int)EffMaxNum(GV_EFF_CDMIN,  (double)InpCooldownMin);  }
bool EffRequireSL(){     return EffFlagOn(GV_EFF_REQSL,InpRequireSL);  }
bool EffRequireTP(){     return EffFlagOn(GV_EFF_REQTP,InpRequireTP);  }
bool EffUseCorrCap(){    return EffFlagOn(GV_EFF_CORR, InpUseCorrCap); }
void TightenPersistMin(string gv,double inp,string label)   // strengeren Wert sofort persistieren (ueberlebt Restart am selben Tag)
{
   if(inp<=0) return;                                       // AUS = lockerer -> nie persistieren
   if(!GlobalVariableCheck(gv) || GlobalVariableGet(gv)<=0 || inp < GlobalVariableGet(gv)-0.0001)
   { GlobalVariableSet(gv,inp); g_gvDirty=true; if(StringLen(label)>0) Notify(TF("cfg.tightenedImmediately",label,DoubleToString(inp,2))); }
}
void TightenPersistMax(string gv,double inp){ if(!GlobalVariableCheck(gv) || inp > GlobalVariableGet(gv)+0.0001){ GlobalVariableSet(gv,inp); g_gvDirty=true; } }
void TightenPersistFlag(string gv,bool inp){ if(inp && (!GlobalVariableCheck(gv) || GlobalVariableGet(gv)<0.5)){ GlobalVariableSet(gv,1); g_gvDirty=true; } }
void TightenOnlyLimits()   // pro Cycle (Master): Input ENGER als effektiv -> sofort; LOCKERER -> ignoriert bis Tageswechsel
{
   if(!TightenOn()) return;
   TightenPersistMin(GV_EFF_DL,      InpDailyLossPct,           "Tages-Limit");
   TightenPersistMin(GV_EFF_ML,      InpMaxLossPct,             "Max-Limit");
   TightenPersistMin(GV_EFF_WEEK,    InpWeeklyLossPct,          "Wochen-Limit");
   TightenPersistMin(GV_EFF_WARN,    InpMaxLossWarnPct,         "");
   TightenPersistMin(GV_EFF_GIVE,    InpGivebackPct,            "");
   TightenPersistMin(GV_EFF_RISK,    DesiredRiskPct(),          "");   // v0.36: Basis ist die Wochenwahl, nicht mehr der Roh-Input
   TightenPersistMin(GV_EFF_LOCKAFT,(double)InpLockAfter,       "");
   TightenPersistMin(GV_EFF_CDAFT,  (double)InpCooldownAfter,   "");
   TightenPersistMax(GV_EFF_CDMIN,  (double)InpCooldownMin);
   TightenPersistFlag(GV_EFF_REQSL,  InpRequireSL);
   TightenPersistFlag(GV_EFF_REQTP,  InpRequireTP);
   TightenPersistFlag(GV_EFF_CORR,   InpUseCorrCap);
}
bool MaxLossWarnActive(){ double w=EffMaxLossWarn(); return (w>0 && EffMaxLoss()>0 && w<EffMaxLoss() && TotalDDpct()>=w); }   // R4b Warn-Gate (mit Input-Schutz)
// v0.63: loud=true fuer Manipulations-/Schutzausfall-Befunde. Im Test ist genau das aufgefallen: die
//   Erkennung "Lockstate-Datei fehlt" hat korrekt gefeuert, aber die Meldung stand nur 6 s im Panel und
//   InpUseAlert ist per Default aus — der Trader stand vor einem stillen Befund. Solche Ereignisse sind
//   selten genug, dass ein erzwungener Alert kein Spam ist, und wichtig genug, dass Verpassen teuer waere.
void Notify(string m, bool info=false, bool loud=false)   // v0.37: info=true -> neutraler Hinweis (Cockpit), kein rotes "NICHT MOEGLICH"
{
   Print(m);
   if(InpUseAlert || loud) Alert(m);
   // v0.64: Ein stehender Manipulationsbefund wird von harmlosen Meldungen NICHT ueberschrieben. Ohne das
   //   war die lange Standzeit wirkungslos: der Missing-Zweig setzt selbst eine Tagessperre, deren Meldung
   //   dem Befund unmittelbar hinterherlief und ihn nach Sekundenbruchteilen ersetzte.
   if(!loud && g_flashLoud && (GetTickCount()-g_flashMs) < g_flashHold) return;
   g_flashLoud = loud;
   g_flashHold = loud ? 120000 : 6000;
   string fm=m; if(StringSubstr(fm,0,7)=="Mamal: ") fm=StringSubstr(fm,7);      // v0.21: Panel-Kurzform ohne Prefix
   fm=Clip(fm,132);                                                             // v0.37: vollen Text behalten (bis zu 3 Panel-Zeilen); Umbruch macht DrawPanel
   g_flash=fm; g_flashMs=GetTickCount(); g_flashInfo=info;                      // Grund/Meldung 6s im Panel zeigen
   if(ObjectFind(0,PFX+"prev")>=0){ ObjectSetString(0,PFX+"prev",OBJPROP_TEXT,Clip(fm,42)); ObjectSetInteger(0,PFX+"prev",OBJPROP_COLOR,info?C'150,200,255':C'255,140,60'); ChartRedraw(0); }   // sofortige erste Zeile; Rest folgt beim naechsten DrawPanel
   g_panelSig="";                                                               // erzwingt Neuzeichnen beim naechsten DrawPanel
}

// §05-fix (hoch): auch fuer einen BELIEBIGEN Zeitpunkt auswertbar (t) -> "wurde die Position WAEHREND einer Sperre eroeffnet?"
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
double EffIdeaCap(){ return InpAutoScale ? EffRiskPct()*InpIdeaXrisk : InpIdeaCapPct; }   // §06-fix: Risiko/Trade tighten-only -> die ganze Auto-Scale-Kaskade ist nicht mehr intraday hochsetzbar
double EffHeat()   { return InpAutoScale ? EffIdeaCap()*InpHeatXidea      : InpPortfolioHeatPct; }
double EffDay()    { return InpAutoScale ? EffIdeaCap()*InpDayXidea       : InpDailyRiskBudgetPct; }
// §07-fix: R17 war unter Auto-Scale eine TOTE Regel. Die groesste Netto-Waehrungs-Exposition kann nie groesser sein als
//   die Summe aller Risiken (= Heat). Mit InpCorrCapPct=1,5 % bei einem Heat-Cap von 1,0 % konnte das Gate also NIE
//   greifen. Unter Auto-Scale wird der Deckel deshalb an den Heat-Cap gekoppelt (75 %) — ein strengerer manueller
//   InpCorrCapPct gewinnt weiterhin.
double EffCorrCap(){ double c=InpCorrCapPct; if(InpAutoScale){ double a=EffHeat()*0.75; if(a>0 && (c<=0 || a<c)) c=a; } return c; }
// R17 (v0.17): Waehrungsvektor statt USD-only. Jede Position belastet Basis-Waehrung (long bei BUY) und
// Quote-Waehrung (short bei BUY) mit ihrem Risiko%. Nicht-FX (Indizes) -> eigener Bucket auf Symbolname.
bool IsCcy(string c){ return StringFind(" USD EUR GBP JPY CHF AUD CAD NZD SGD HKD NOK SEK DKK PLN ZAR MXN TRY CNH CZK HUF ", " "+c+" ")>=0; }   // B19: gueltige ISO-Codes
bool SplitCcy(string s,string &base,string &quote)
{
   string a=StringSubstr(s,0,6);
   if(StringLen(a)<6) return false;
   for(int i=0;i<6;i++){ ushort c=StringGetCharacter(a,i); if(!((c>='A'&&c<='Z')||(c>='a'&&c<='z'))) return false; }
   base=StringSubstr(a,0,3); quote=StringSubstr(a,3,3);
   StringToUpper(base); StringToUpper(quote);
   if(!IsCcy(base) || !IsCcy(quote)) return false;   // B19: 6-Buchstaben-Nicht-FX (CFD/Krypto) -> kein Phantom-Waehrungs-Bucket
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
   else { string u=sym; StringToUpper(u); AddCcy(ccy,net,n,u, isBuy? rp : -rp); }   // Nicht-FX: Einzel-Bucket
}
double MaxCurrencyExposurePct(string addSym,bool addBuy,double addRp,bool conservative=false)   // groesste |Netto-Waehrungs-Exposition| inkl. hypothetischem Trade
{
   string ccy[]; double net[]; int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int t=OrderType(); if(t!=OP_BUY && t!=OP_SELL) continue;
      if(!InScope(OrderMagicNumber())) continue;
      if(OrderStopLoss()==0.0)   // §06-fix: nackte Position nicht als 0 % zaehlen (sonst Gate umgehbar)
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
   if(InpRevengeMin<=0) return;   // deaktiviert -> keine Marker schreiben
   GlobalVariableSet(RevDirKey(s), (double)lostType);
   GlobalVariableSet(RevUntilKey(s), (double)(SrvTime()+InpRevengeMin*60));
   g_gvDirty=true;   // v0.22: Flush gebuendelt am Cycle-Ende (SetRevenge laeuft im Close-Pfad ueber ApplyResult)
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
         string sym=StringSubstr(nm,8);   // nach "RG_REVU_"
         GlobalVariableDel(nm);
         if(GlobalVariableCheck("RG_REVD_"+sym)) GlobalVariableDel("RG_REVD_"+sym);
      }
   }
}

string RuleIdFromTag(string tag)   // fuehrendes "Rxx" aus dem Tag ziehen (sonst leer)
{
   if(StringLen(tag)>=2 && StringGetCharacter(tag,0)=='R')
   {
      ushort c1=StringGetCharacter(tag,1);
      if(c1>='0' && c1<='9'){ int sp=StringFind(tag," "); return (sp>0) ? StringSubstr(tag,0,sp) : tag; }
   }
   return "";
}
// v0.17: audit-taugliches Journal — Kontext (Zeit/Konto/Balance/Equity/Magic/DayKey/RuleId) wird automatisch
// gefuellt, Ticket/Netto optional. Header beim ersten Schreiben. Aufruf-Stellen bleiben unveraendert.
void Journal(string ev,string sym,string dir,double lot,double entry,double sl,double tp,double riskpct,string tag,int ticket=0,double net=0.0)
{
   // v0.32 Panel-Spiegel: Versuche (BLOCKED) + Trades (OPEN) zaehlen — geteilt (kontoweit), unabhaengig vom CSV-Journal
   if(ev=="BLOCKED")
   {
      GlobalVariableSet(GV_BLOCKS, GlobalVariableGet(GV_BLOCKS)+1);
      datetime nb=SrvTime(); datetime bl=(datetime)GlobalVariableGet(GV_BLK_LAST);
      double burst = ((nb-bl) < 60) ? GlobalVariableGet(GV_BLK_BURST)+1 : 1;   // Ablehnungen im letzten 60s-Fenster
      GlobalVariableSet(GV_BLK_BURST, burst); GlobalVariableSet(GV_BLK_LAST,(double)nb); g_gvDirty=true;
      if(burst==3.0) Notify(T("tilt.burst"));   // Tilt-Blitz (nutzt Panel-Flash)
   }
   else if(ev=="OPEN"){ GlobalVariableSet(GV_FILLS, GlobalVariableGet(GV_FILLS)+1); g_gvDirty=true; }
   if(!InpJournal) return;
   // §06-fix (mittel): ohne Sharing-Flags scheiterte FileOpen still, sobald der Cockpit-Server (oder Excel) die CSV gerade
   //   liest — der Audit-Eintrag (auch TAMPER/CLOSE/FINAL-FAIL) war dann DAUERHAFT verloren, ohne jede Spur. Jetzt:
   //   FILE_SHARE_READ|FILE_SHARE_WRITE + kurzer Retry, und im Fehlerfall ein lauter Print statt eines stummen return.
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
// v0.47: Screenshot mit Ticket-Bezug — Dateiname traegt das Ticket, damit Cockpit/Server jedes Bild
//   eindeutig EINEM Trade zuordnen kann: Mamal_<ticket>_<tag>_<epoch>.png (ticket 0 = kein Trade-Bezug).
void Shot(string tag,int ticket=0)
{
   if(!InpScreenshots) return;
   ChartScreenShot(0,StringFormat("Mamal_%d_%s_%d.png",ticket,tag,(int)SrvTime()),InpShotWidth,InpShotHeight);
}
// v0.47: Screenshots aufraeumen — sonst waechst MQL4/Files unbegrenzt (ein Bild je Aktion).
//   Laeuft im 60s-Housekeeping, nicht im Enforcement-Takt.
void PruneShots()
{
   if(InpShotKeepDays<=0) return;
   datetime cutoff=SrvTime()-(datetime)InpShotKeepDays*86400;
   string fn; long h=FileFindFirst("Mamal_*.png",fn);
   if(h==INVALID_HANDLE) return;
   int killed=0;
   do
   {
      // Zeitstempel steckt am Dateiende: Mamal_<ticket>_<tag>_<epoch>.png
      int p2=StringFind(fn,".png");
      if(p2<=0) continue;
      string base=StringSubstr(fn,0,p2);
      int    us=-1;
      for(int k=StringLen(base)-1;k>=0;k--) if(StringGetChar(base,k)=='_'){ us=k; break; }
      if(us<0) continue;
      long ts=StringToInteger(StringSubstr(base,us+1));
      if(ts>0 && (datetime)ts<cutoff && FileDelete(fn)) killed++;
   } while(FileFindNext(h,fn) && killed<200);   // pro Durchlauf deckeln (kein langer I/O-Block)
   FileFindClose(h);
   if(killed>0) PrintFormat("Mamal: %d alte Screenshots geloescht (aelter als %d Tage)",killed,InpShotKeepDays);
}
string SlSeenKey(int t){ return "RGSLS_"+IntegerToString(t); }   // v0.47: zuletzt gesehener SL
string TpSeenKey(int t){ return "RGTPS_"+IntegerToString(t); }   // v0.47: zuletzt gesehener TP

// v0.47: VERHALTENS-TRACKING — erkennt je Ticket, ob SL oder TP verschoben wurde, und bewertet die Richtung.
//   Fachlich: ein SL WEG vom Einstieg erhoeht das Risiko (klassischer Fehler „dem Verlust Luft geben");
//   ein SL ZUM Einstieg senkt es. Ein TP naeher am Einstieg kuerzt Gewinne ab. Das Urteil wird als Klartext
//   ins Journal geschrieben; die Gesamtauswertung je Position macht der Cockpit-Server aus diesen Zeilen.
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
         // Abstand zum Einstieg: groesser = mehr Risiko
         double dOld=MathAbs(entry-lastSL), dNew=MathAbs(entry-sl);
         string verdict;
         if(lastSL==0)                       verdict="SL erstmals gesetzt";
         else if(sl==0)                      verdict="SL ENTFERNT — Risiko unbegrenzt (nachteilhaft)";
         else if(dNew>dOld+eps)              verdict="SL WEITER weg vom Einstieg ("+DoubleToString(lastSL,dg)+" -> "+DoubleToString(sl,dg)+") — Risiko ERHOEHT (nachteilhaft)";
         else if(dNew<dOld-eps)
         {
            bool be=((isBuy && sl>=entry-eps) || (!isBuy && sl<=entry+eps));
            verdict="SL naeher an den Einstieg ("+DoubleToString(lastSL,dg)+" -> "+DoubleToString(sl,dg)+") — Risiko gesenkt"+(be?", Break-Even erreicht":"")+" (vorteilhaft)";
         }
         else                                verdict="SL seitlich verschoben (Risiko unveraendert)";
         Journal("SLTP_MOVE",OrderSymbol(),(isBuy?"BUY":"SELL"),OrderLots(),entry,sl,tp,0,verdict,tk);
         Shot("slmove",tk);
         GlobalVariableSet(sk,sl); g_gvDirty=true;
      }
      if(MathAbs(tp-lastTP)>eps)
      {
         double dOld=MathAbs(entry-lastTP), dNew=MathAbs(entry-tp);
         string verdict;
         if(lastTP==0)                       verdict="TP erstmals gesetzt";
         else if(tp==0)                      verdict="TP ENTFERNT — kein Ziel mehr definiert";
         else if(dNew<dOld-eps)              verdict="TP NAEHER an den Einstieg ("+DoubleToString(lastTP,dg)+" -> "+DoubleToString(tp,dg)+") — Gewinn abgekuerzt";
         else if(dNew>dOld+eps)              verdict="TP WEITER weg ("+DoubleToString(lastTP,dg)+" -> "+DoubleToString(tp,dg)+") — Ziel vergroessert";
         else                                verdict="TP seitlich verschoben";
         Journal("SLTP_MOVE",OrderSymbol(),(isBuy?"BUY":"SELL"),OrderLots(),entry,sl,tp,0,verdict,tk);
         Shot("tpmove",tk);
         GlobalVariableSet(tkk,tp); g_gvDirty=true;
      }
   }
}

//--- v0.26: Cockpit-Bruecke (DLL-frei) — Live-Zustand als JSON in MQL4/Files, ein lokaler Server serviert daraus die localhost-Seite ---
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
   else if(BaseWarn())       { st=T("status.baseWarn");    sc="amber"; }   // §07-fix: BaseWarn blockt JEDEN Entry, wurde aber als "AKTIV" angezeigt
   // v0.62: R23 fehlte in der Cockpit-Leiter — das Dashboard zeigte gruen "AKTIV", waehrend das Panel
   //   sperrte. Reihenfolge bewusst identisch zur Panel-Leiter (DrawPanel), sonst driften beide Anzeigen.
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
   if(!InpCloseManualTrades) dis=dis+"\"R22\",";   // R22: nur-Panel-Trades abgeschaltet
   if(StringLen(dis)>0) dis=StringSubstr(dis,0,StringLen(dis)-1);

   string j="{";
   j=j+StringFormat("\"v\":\"%s\",\"srvtime\":\"%s\",", EA_VER, TimeToString(SrvTime(),TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   j=j+StringFormat("\"account\":\"%s\",\"symbol\":\"%s\",\"tf\":\"%s\",\"port\":%d,\"profile\":\"%s\",\"funded\":%s,", IntegerToString(AccountNumber()), Symbol(), PeriodStr(), InpCockpitPort, PropFirmName(InpPropFirm), JB(InpFundedMode));   // v0.37: Kontonummer (String, ueberlauf-sicher) -> Dashboard zeigt, WELCHES Konto (bei mehreren Terminals)
   j=j+StringFormat("\"equity\":%s,\"balance\":%s,\"ccy\":\"%s\",\"initBal\":%s,", DoubleToString(eq,2), DoubleToString(bal,2), AccountCurrency(), DoubleToString(g_initialBalance,2));
   j=j+StringFormat("\"status\":\"%s\",\"statusColor\":\"%s\",\"protectOff\":%s,", st, sc, JB(disabled));
   j=j+StringFormat("\"dailyDD\":%s,\"dailyLimit\":%s,\"dayBase\":%s,\"weekBase\":%s,", DoubleToString(dailyDD,2), DoubleToString(EffDailyLoss(),2), DoubleToString(GlobalVariableGet(GV_DAYSTART_EQ),2), DoubleToString(GlobalVariableGet(GV_WEEKSTART_EQ),2));   // v0.39: Basen fuer die €-Umrechnung im Dashboard (Puffer-Tacho)
   j=j+StringFormat("\"totalDD\":%s,\"maxLoss\":%s,\"maxLossWarn\":%s,", DoubleToString(TotalDDpct(),2), DoubleToString(EffMaxLoss(),2), DoubleToString(EffMaxLossWarn(),2));
   j=j+StringFormat("\"protOff\":%d,\"tightenOnly\":%s,", (int)GlobalVariableGet(GV_PROTOFF), JB(TightenOn()));   // v0.30: Schutz-aus-Zaehler + Selbst-Sperre-Status (§06: gelatchter Ist-Zustand, nicht der Roh-Input)
   j=j+StringFormat("\"dayRisk\":%s,\"dayBudget\":%s,", DoubleToString(dayR,2), DoubleToString(EffDay(),2));
   j=j+StringFormat("\"heat\":%s,\"heatCap\":%s,\"ideaCap\":%s,\"riskPerTrade\":%s,\"riskNextWeek\":%s,", DoubleToString(heat,2), DoubleToString(EffHeat(),2), DoubleToString(EffIdeaCap(),2), DoubleToString(EffRiskPct(),2), DoubleToString(PendingWeekRisk(),2));   // v0.36: wirksames Risiko/Trade (Wochenwahl) + vorgemerkte Erhoehung
   j=j+StringFormat("\"consec\":%d,\"lockAfter\":%d,\"cooldownAfter\":%d,\"cooldownSec\":%d,\"cooldownMin\":%d,", consec, EffLockAfter(), EffCooldownAfter(), cdSec, EffCooldownMin());
   j=j+StringFormat("\"weekDD\":%s,\"weekLimit\":%s,", DoubleToString(weekDD,2), DoubleToString(EffWeekLoss(),2));
   j=j+StringFormat("\"targetPct\":%s,\"profitPct\":%s,\"givebackPct\":%s,", DoubleToString(InpDailyTargetPct,2), DoubleToString(profitPct,2), DoubleToString(EffGivebackPct(),2));
   j=j+StringFormat("\"dayLock\":%s,\"hardLock\":%s,\"weekLock\":%s,\"targetHit\":%s,\"baseWarn\":%s,\"cooldown\":%s,\"offSession\":%s,\"maxWarn\":%s,\"weekRiskPending\":%s,\"lockWhy\":%d,", JB(IsDayLocked()), JB(IsHardLocked()), JB(IsWeekLocked()), JB(TargetHit()), JB(BaseWarn()), JB(CooldownActive()), JB(OffSession()), JB(maxw), JB(WeekRiskPending()), (IsLocked() && GlobalVariableCheck(GV_LOCK_WHY)) ? (int)GlobalVariableGet(GV_LOCK_WHY) : 0);   // §06-fix: maxWarn als eigenes Flag — das Dashboard zeigte sonst gruen "Alles frei", waehrend der EA jeden Trade blockte; v0.62: weekRiskPending (R23) ebenso
   j=j+StringFormat("\"minStopPips\":%s,\"rr\":%s,\"scope\":%d,", DoubleToString(InpMinStopPips,0), DoubleToString(InpRR,1), (int)InpWatchScope);
   j=j+StringFormat("\"fills\":%d,\"blocks\":%d,\"riskEstimate\":%s,", (int)GlobalVariableGet(GV_FILLS), (int)GlobalVariableGet(GV_BLOCKS), JB(g_tvEstimate));   // §07-fix: GV_FILLS wurde gepflegt, aber nirgends gelesen; riskEstimate macht die TickValue-Schaetzung sichtbar
   j=j+StringFormat("\"disabled\":[%s]", dis);
   j=j+"}";

   int h=FileOpen(COCKPIT_TMP,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   FileWriteString(h,j);
   FileClose(h);
   FileMove(COCKPIT_TMP,0,COCKPIT_FILE,FILE_REWRITE);   // atomar ersetzen
   // v0.37: Wegweiser in den Common-Ordner (fester Pfad, egal ob Portable/Terminal-Hash).
   // Verraet dem Server den ECHTEN Files-Ordner dieses Terminals -> Server findet JSON/Journal/Trigger immer.
   // v0.38-fix (Verify): Wegweiser nur EINMAL pro Session/Konto schreiben — nicht alle 2s.
   //   (Spart I/O und beseitigt das Lese-Race auf eine halb geschriebene Pfadzeile.)
   static long beaconAcct=-2;
   if((long)AccountNumber()!=beaconAcct)
   {
      int hp=FileOpen(COCKPIT_PATHS,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(hp!=INVALID_HANDLE){ FileWriteString(hp,TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL4\\Files"); FileClose(hp); }
      // v0.38: PRO KONTO ein Wegweiser (mamal_files_<login>.txt) — mehrere Terminals/Konten
      //   ueberschreiben sich so nicht mehr; der Server bietet daraus den Konto-Umschalter an.
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
   if(!InpCockpit){ Notify(T("cfg.cockpitDisabled")); return; }   // v0.40: sonst wundert man sich ueber 'Daten veraltet'
   Notify(TF("info.cockpit",IntegerToString(InpCockpitPort)), true);   // v0.37: ehrlicher Hinweis + URL statt rotem Fehler
}

// v0.40: Close-Buttons — schliesst offene Positionen sofort (Risiko-Reduktion: KEINE Gates, keine Bestaetigung).
//   chartOnly=true -> nur Symbol dieses Charts; half=true -> jede Position um 50% verkleinern (Lot-Step-gerundet,
//   Floor rundet zugunsten des Rests ab). Reichweite bewusst KONTOWEIT inkl. fremder Magics (User-Entscheidung) —
//   Pending-Orders bleiben unberuehrt. KEIN MarkEaClosed: fuer EA-/Panel-eroeffnete Trades zaehlen Verluste damit
//   normal in Serie/Cooldown (Trader-Entscheidung, kein Laundering); FREMDE Magics werden nur journalisiert,
//   ihr P/L bleibt ausserhalb der Wertung (Scope-Design).
void PanelClose(bool chartOnly,bool half)
{
   if(IsTradeContextBusy()){ Notify(T("info.tradeContextBusy"),true); return; }
   // Phase 1 (Verify v0.40): Ziel-Tickets VOR dem ersten Close einfrieren — der Pool mutiert waehrend der
   //   Closes (50%-Rest bekommt ein NEUES Ticket) und MQL4 garantiert die Pool-Sortierung nicht; positional
   //   koennte ein frischer Rest sonst erneut halbiert werden.
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
         // +Epsilon (Verify v0.40): Binaer-FP macht sonst z.B. 0.06*0.5/0.01 = 2.9999... -> 0.02 statt 0.03
         lots=NormalizeDouble(MathFloor(all*0.5/stp + 0.0000001)*stp,LotDigits(stp));
         if(lots<mn-0.0000001 || all-lots<mn-0.0000001){ skipped++; continue; }   // Haelfte ODER Rest unter Minimum -> unveraendert lassen
      }
      RefreshRates();
      double px=(ty==OP_BUY)?MarketInfo(sy,MODE_BID):MarketInfo(sy,MODE_ASK);
      if(OrderClose(tk,lots,px,InpSlippage,clrOrange))
      {
         closed++;
         Journal("PANEL_CLOSE",sy,(ty==OP_BUY?"BUY":"SELL"),lots,px,0,0,0,StringFormat("%s%s per Panel-Button (#%d)",half?"50%":"Voll",chartOnly?" · Chart":" · Konto",tk),tk);
         if(half && GlobalVariableCheck(OpnKey(tk)))   // Rest-Ticket unseres Trades registrieren -> Close-Erkennung findet auch ihn
         {
            // Verify v0.40: bevorzugt am MT4-Standard-Kommentar "from #<tk>" erkennen; Fallback nur bei
            //   EXAKTEM Match aus Zeit/Preis/Magic/Rest-Lots (zwei gleichzeitige Positionen gleicher
            //   Sekunde/Preis duerfen nie das falsche Ticket registrieren).
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

// v0.46: "RISK FREE" — SL aller Positionen IM GEWINN auf Break-Even ziehen (Einstieg + optionaler Puffer).
//   Reine Risiko-SENKUNG: keine Regel wird beruehrt, laeuft daher auch bei Sperre/Cooldown.
//   Reichweite: nur Positionen, die das Tool verantwortet (InScope ODER registriertes Panel-Ticket) — fremde
//   EAs bleiben unangetastet, weil deren Logik auf ihrem eigenen SL beruhen kann.
//   Break-Even ist exakt OrderOpenPrice(): MT4 eroeffnet BUY zum Ask und schliesst zum Bid (und umgekehrt),
//   der Spread steckt also bereits im Einstiegspreis. InpBreakEvenBufferPts deckt zusaetzlich die Kommission.
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
      // schon auf/ueber Break-Even? -> nichts zu tun (SL nie lockern!)
      if(curSL>0 && ((ty==OP_BUY && curSL>=target-pt/2) || (ty==OP_SELL && curSL<=target+pt/2))) continue;
      RefreshRates();
      double cur=(ty==OP_BUY)?MarketInfo(sy,MODE_BID):MarketInfo(sy,MODE_ASK);
      if(cur<=0) continue;
      // nur wenn wirklich im Gewinn
      if((ty==OP_BUY && cur<=target) || (ty==OP_SELL && cur>=target)){ skipped++; continue; }
      // Broker-Mindestabstand einhalten, sonst lehnt der Server das Modify ab (err 130)
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
   if(skipped>0) m=m+StringFormat(", %d noch nicht im Gewinn/zu nah",skipped);
   if(failed>0)  m=m+StringFormat(", %d FEHLER (Journal)",failed);
   if(done==0 && skipped==0 && failed==0) m=T("riskfree.none");
   Notify(m, failed==0);
   g_panelSig="";
}

// v0.44: Manuelle / fremde Trades (nicht vom Panel, ausserhalb des WatchScope) fuers Cockpit sichtbar machen —
//   eigenes Event "CLOSE_MAN". Sie aendern KEINE Regel (keine Verlustserie, kein Cooldown, kein Tagesbudget):
//   das Enforcement bleibt exakt wie definiert, das Dashboard markiert sie nur als "manuell".
//   Fenster = heutiger Servertag (bounded); Dedup ueber eigenen Namespace RGM_ (RGP_ gehoert dem Regel-Pfad).
void ResolveManualHistory()
{
   datetime dayStart=ServerDayStart();
   if(dayStart<=0 || dayStart>SrvTime()) return;                    // v0.45: unplausible Zeitbasis -> nichts tun
   // v0.45 (Verify): Aggregations-Fenster BREITER als das Melde-Fenster. Ein Teil-Close von gestern gehoert
   //   zum selben Positions-Netto wie der heute geschlossene Rest — sonst meldet CLOSE_MAN nur einen Teilbetrag.
   datetime scanFrom=dayStart-7*86400;
   string   gKey[]; string gSym[]; int gType[]; int gMagic[]; double gNet[]; double gLots[];
   datetime gMax[]; datetime gOpen[]; double gPrice[];
   int gN=0, tot=OrdersHistoryTotal();
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      // v0.45 (Verify): billige Filter ZUERST — GlobalVariableCheck ist O(N_GV) und lief vorher auf jeder
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
      if(gMax[g2]<dayStart) continue;                                                          // aelter als heute -> nur Aggregations-Kontext
      string mk=ManKey(gKey[g2]);
      if(GlobalVariableCheck(mk)) continue;                                                    // schon angezeigt/gewertet
      // v0.45 (Verify): Quervergleich mit dem REGEL-Pfad. Ohne ihn konnte ein Trade, den ResolveHistory
      //   ueber die Ticket-Registrierung gewertet hat (Magic-Divergenz/Scope-Wechsel), zusaetzlich als
      //   CLOSE_MAN erscheinen -> doppeltes Netto im Dashboard.
      string kleg=ProcKeyLegacy(gOpen[g2],gType[g2],gSym[g2],gMagic[g2],gPrice[g2]);
      if(IsProcessedAny(gKey[g2],kleg)){ GlobalVariableSet(mk,(double)gMax[g2]); g_gvDirty=true; continue; }
      if(HasOpenRemainder(gOpen[g2],gSym[g2],gType[g2],gMagic[g2],gPrice[g2])) continue;        // Teil-Close: erst wenn ganz zu
      // v0.45 (Verify): Marker VOR dem Journal setzen und Erfolg pruefen — schlaegt die GV-Anlage fehl
      //   (Namenslaenge/GV-Limit), wuerde dieselbe Zeile sonst alle 2s neu geschrieben (Journal-Flut).
      if(!GlobalVariableSet(mk,(double)gMax[g2]))
      {
         if(!s_manMarkerFail)
         { s_manMarkerFail=true;
           Journal("INFO","-","-",0,0,0,0,0,StringFormat("CLOSE_MAN-Marker nicht persistierbar (err=%d) — manuelle Trades werden NICHT angezeigt",GetLastError())); }
         continue;
      }
      g_gvDirty=true;
      Journal("CLOSE_MAN",gSym[g2],(gType[g2]==OP_BUY?"BUY":"SELL"),gLots[g2],gPrice[g2],0,0,0,
              StringFormat("Manueller/fremder Trade (Magic %d) — ausserhalb der Tool-Regeln, nur Anzeige",gMagic[g2]),0,gNet[g2]);
   }
}

// v0.40: Sicherheitsnetz — verarbeitet VOLL geschlossene, registrierte Panel-Tickets per SELECT_BY_TICKET
//   (unabhaengig vom History-Tab-Zeitraumfilter und vom GV_LAST_CLOSE-Floor). Gleiche Dedup-Keys wie
//   ResolveHistory -> nie doppelt gezaehlt.
// v0.40-fix (Verify): GRUPPEN-AGGREGATION — alle registrierten Legs derselben Position (gleicher ProcKey,
//   z.B. nach Panel-50%-Close) werden GEMEINSAM gewertet. Vorher wertete der Fallback nur das zuerst
//   iterierte Leg und AddProcessed verschluckte das P/L der Geschwister (Laundering-Fenster: Gewinn-Bein
//   zuerst -> Serie-Reset trotz Netto-Verlust). Registry wird vorab eingefroren (GV-Neuanlagen durch
//   ApplyResult verschieben die Iteration sonst); Keys offener Positionen werden aufgefrischt (4-Wochen-Expiry).
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
   // v0.41/v0.45: Diagnose nur noch bei ECHTER Anomalie ins Journal (nicht aufloesbare Tickets), sonst Log-Print.
   //   Vorher schrieb der 60s-Takt dauerhaft INFO-Zeilen und verdraengte echte Ereignisse aus der Cockpit-Liste.
   static uint s_diagMs=0;
   if(nReg==0) return;
   if(GetTickCount()-s_diagMs>=60000)
   {
      s_diagMs=GetTickCount();
      int unres=0; for(int d=0; d<nReg; d++) if(!OrderSelect(regT[d],SELECT_BY_TICKET)) unres++;
      if(unres>0) Journal("INFO","-","-",0,0,0,0,0,StringFormat("Registry-Diag: %d vorgemerkt, %d NICHT aufloesbar (History-Cache pruefen), HistTotal=%d",nReg,unres,OrdersHistoryTotal()));
      else        PrintFormat("Mamal Registry-Diag: %d vorgemerkt, alle aufloesbar, HistTotal=%d",nReg,OrdersHistoryTotal());
   }
   bool done[]; ArrayResize(done,nReg); ArrayInitialize(done,false);

   for(int i=0;i<nReg;i++)
   {
      if(done[i]) continue;
      int tk=regT[i];
      if(!OrderSelect(tk,SELECT_BY_TICKET))
      {
         // Nicht aufloesbar (History gepurgt / Tab-Cache?): 1x pro Stunde sichtbar machen, Key behalten.
         double reg=GlobalVariableGet(OpnKey(tk));
         if(reg>0 && SrvTime()-(datetime)reg>3600)
         { GlobalVariableSet(OpnKey(tk),(double)SrvTime()); g_gvDirty=true;
           Journal("INFO","-","-",0,0,0,0,0,StringFormat("Ticket-Registry: #%d seit >1h nicht aufloesbar — bleibt vorgemerkt (History-Cache pruefen)",tk)); }
         continue;
      }
      if(OrderCloseTime()==0)
      { GlobalVariableSet(OpnKey(tk),GlobalVariableGet(OpnKey(tk))); continue; }   // offen -> Key auffrischen (nur hier: Orphans verfallen weiter nach 4 Wochen)
      int ty=OrderType();
      if(ty!=OP_BUY && ty!=OP_SELL){ GlobalVariableDel(OpnKey(tk)); done[i]=true; continue; }
      datetime ot=OrderOpenTime(); string sy=OrderSymbol(); int mg=OrderMagicNumber(); double op=OrderOpenPrice();
      string key   =ProcKey      (ot,ty,sy,mg,op);
      string keyLeg=ProcKeyLegacy(ot,ty,sy,mg,op);
      if(IsProcessedAny(key,keyLeg)){ GlobalVariableDel(OpnKey(tk)); done[i]=true; continue; }   // Gruppen-Pfad war schneller
      if(HasOpenRemainder(ot,sy,ty,mg,op)) continue;   // (auch unregistrierter) Rest noch offen -> spaeter
      // Alle registrierten Geschwister-Legs derselben Position einsammeln und aggregieren
      double manNet=0, eaNet=0; bool hasMan=false, eaFault=false, defer=false;
      datetime maxCt=0; int grp[]; int nG=0;
      for(int j=i;j<nReg;j++)
      {
         if(done[j]) continue;
         if(!OrderSelect(regT[j],SELECT_BY_TICKET)) continue;
         if(OrderOpenTime()!=ot || OrderType()!=ty || OrderSymbol()!=sy) continue;
         if(OrderMagicNumber()!=mg || MathAbs(OrderOpenPrice()-op)>0.0000001) continue;
         if(OrderCloseTime()==0){ defer=true; break; }   // registriertes Geschwister noch offen -> ganze Gruppe spaeter
         double lnet=OrderProfit()+OrderSwap()+OrderCommission();
         if(GlobalVariableCheck(EaKey(OrderTicket()))){ eaNet+=lnet; if(GlobalVariableCheck(EacfKey(OrderTicket()))) eaFault=true; }
         else                                         { manNet+=lnet; hasMan=true; }
         if(OrderCloseTime()>maxCt) maxCt=OrderCloseTime();
         ArrayResize(grp,nG+1); grp[nG]=j; nG++;
      }
      if(defer || nG==0) continue;
      // v0.65b: dasselbe Ticket waehlen wie der Gruppen-Pfad (kleinstes = Einstieg). Sonst journalisiert
      //   derselbe Trade je nach Aufloesungspfad ein anderes Ticket und die Akte findet ihn nicht wieder.
      for(int k3=0;k3<nG;k3++) if(regT[grp[k3]]<tk) tk=regT[grp[k3]];
      bool sameDay=(DayKeyOf(maxCt-EffResetHour()*3600)==(long)ServerDayKey());
      double tot=manNet+eaNet;
      if(!sameDay)      Journal("CLOSE",sy,"-",0,0,0,0,0,"Close aus vorherigem Servertag — zaehlt nicht fuer die heutige Serie, net "+DoubleToString(tot,2),tk,tot);
      else if(hasMan)   ApplyResult(manNet,tk,sy,ty);   // wie Gruppen-Pfad: Trader-Anteil zaehlt fuer die Serie
      else if(eaFault)  ApplyResult(eaNet, tk,sy,ty);
      else              Journal("CLOSE",sy,"-",0,0,0,0,0,"EA-Schutz-Close (zaehlt nicht fuer die Serie), net "+DoubleToString(tot,2),tk,tot);
      Shot("close",tk);                                              // v0.47: Ausstiegs-Bild fuer den Vorher/Nachher-Vergleich
      GlobalVariableDel(SlSeenKey(tk)); GlobalVariableDel(TpSeenKey(tk));   // v0.47: Tracking-Marker des geschlossenen Tickets aufraeumen
      AddProcessed(key,maxCt);
      for(int k2=0;k2<nG;k2++){ GlobalVariableDel(OpnKey(regT[grp[k2]])); done[grp[k2]]=true; }
      g_gvDirty=true;
   }
}

//--- R5/R6/R19/R25: history-basierte, idempotente Verlustauflösung (P0-2/P0-4) ---
// v0.65: Klartext zum Sperrgrund. Leer, wenn nichts gespeichert ist (Sperre aus einer aelteren Version
//   oder aus der Lockstate-Datei wiederhergestellt) — dann bleibt es bei der neutralen Formulierung.
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
// v0.65: Einmaliger Nachtrag aus der Kontohistorie. Schreibt AUSSCHLIESSLICH Journal-Zeilen —
//   keine Regel-Wertung, kein Anfassen von Verlustserie, Tagesbudget, Sperren oder Dedup-Markern.
//   Das Event heisst bewusst CLOSE_HIST und nicht CLOSE: Kalender und Statistik werten nur "CLOSE",
//   sonst zaehlte jeder nachgetragene Trade ein zweites Mal ins Netto.
//   Grenze, die der Nutzer kennen muss: OrdersHistoryTotal() sieht nur, was der History-Tab anzeigt.
//   Steht dort ein Zeitfilter, wird auch nur dieser Ausschnitt nachgetragen.
void BackfillHistory()
{
   if(!InpHistoryBackfill) return;
   if(GlobalVariableCheck(GV_BACKFILL) && (long)GlobalVariableGet(GV_BACKFILL)==(long)AccountNumber()) return;
   int tot=OrdersHistoryTotal();
   if(tot<=0) return;   // Historie noch nicht geladen -> naechster Cycle. KEIN Guard setzen.
   int cnt=0, skipType=0, skipScope=0, seenMagic=-1; double sum=0;
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int ty=OrderType();
      if(ty!=OP_BUY && ty!=OP_SELL){ skipType++; continue; }   // Ein-/Auszahlungen
      int mg=OrderMagicNumber(); if(seenMagic<0) seenMagic=mg;
      if(!InScope(mg)){ skipScope++; continue; }               // fremde Magics haben keine Akte
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      Journal("CLOSE_HIST",OrderSymbol(),(ty==OP_BUY?"BUY":"SELL"),OrderLots(),OrderOpenPrice(),
              OrderStopLoss(),OrderTakeProfit(),0,
              "Nachtrag aus der Kontohistorie (geschlossen "+TimeToString(OrderCloseTime())+"), net "+DoubleToString(net,2),
              OrderTicket(),net);
      cnt++; sum+=net;
   }
   // IMMER protokollieren, auch bei 0 Treffern — sonst ist hinterher nicht feststellbar, ob der
   //   Nachtrag ueberhaupt lief und woran er scheiterte (genau dieser Fall ist eingetreten).
   Journal("INFO","-","-",0,0,0,0,0,StringFormat(
      "Backfill: %d nachgetragen (Summe %.2f) | Historie=%d, uebersprungen: %d kein Trade, %d ausser Reichweite | InpMagic=%d, erste Magic in der Historie=%d, Scope=%d",
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
   // v0.41-fix: ZUKUNFTS-Floor abfangen. Wurde GV_LAST_CLOSE je mit kaputtem Server-Offset geseedet
   //   (Erst-Attach in tickloser Phase), lag der Anker in der Zukunft -> ct<floor uebersprang JEDEN
   //   Close fuer immer (0 CLOSE-Zeilen seit Tag 1). Selbstheilung: auf Tagesbeginn zuruecksetzen.
   if(floor>SrvTime()+60)
   {
      Journal("INFO","-","-",0,0,0,0,0,StringFormat("GV_LAST_CLOSE lag in der ZUKUNFT (%s) -> zurueckgesetzt auf Tagesbeginn (Close-Wertung war dadurch blockiert)",TimeToString(floor)));
      floor=ServerDayStart(); GlobalVariableSet(GV_LAST_CLOSE,(double)floor); g_gvDirty=true;
   }
   // History nach POSITION gruppieren (Key=OpenTime_Type_Symbol) -> Partial-Closes werden zu EINEM Ergebnis aggregiert
   string   gKey[]; string gKeyLeg[]; datetime gOpen[]; string gSym[]; int gType[]; datetime gMin[]; datetime gMax[]; double gNet[]; double gEaNet[]; double gManNet[]; bool gHasMan[]; bool gEaFault[]; double gPrice[]; int gMagic[]; int gTick[];   // B4/6 (+§05 gEaFault, +§07 gKeyLeg fuer die Key-Migration, +v0.65 gTick)
   // v0.65: gTick = kleinstes Ticket der Gruppe. Bis v0.64 schrieb dieser Pfad die CLOSE-Zeile mit Ticket 0 —
   //   die Trade-Akte konnte eine Schliessung damit NIE ihrem Einstieg zuordnen und zeigte jeden Trade als
   //   "offen", ohne Ergebnis und mit einer Zusammenfassung, die auf ewig "noch nicht verbucht" behauptete.
   int gN=0, tot=OrdersHistoryTotal();
   for(int i=0;i<tot;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      // v0.40-fix: registrierte Panel-Tickets IMMER verarbeiten — laeuft die Master-Instanz mit anderem
      //   InpMagic (Input-Verstellung/Chart-Divergenz), fielen unsere eigenen Trades sonst aus der Wertung
      //   (genau so gingen die CLOSE-Eintraege verloren: Master hatte InpMagic=0, Trades Magic 990201).
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
         gTick[gi]=OrderTicket();   // v0.65: Einstiegs-Ticket der Gruppe
         gMin[gi]=ct; gMax[gi]=ct; gNet[gi]=0; gEaNet[gi]=0; gManNet[gi]=0; gHasMan[gi]=false; gEaFault[gi]=false; gN++;
      }
      gNet[gi]+=net; if(ct<gMin[gi]) gMin[gi]=ct; if(ct>gMax[gi]) gMax[gi]=ct;
      if(OrderTicket()<gTick[gi]) gTick[gi]=OrderTicket();   // v0.65: kleinstes = das urspruengliche Einstiegs-Ticket
      if(ea){ gEaNet[gi]+=net; if(fault) gEaFault[gi]=true; } else { gManNet[gi]+=net; gHasMan[gi]=true; }   // B4/6: EA- vs Trader-Anteil getrennt (+§05-fix: Fault-EA-Close markieren)
   }
   if(gN==0) return;
   // P1: Gruppen chronologisch nach Close-Zeit (gMax) aufsteigend werten -> Verlustserie/Cooldown in echter Reihenfolge (Broker-History ist nicht garantiert sortiert)
   int ord[]; ArrayResize(ord,gN); for(int a=0;a<gN;a++) ord[a]=a;
   for(int a=1;a<gN;a++){ int kk=ord[a]; int b=a-1; while(b>=0 && gMax[ord[b]]>gMax[kk]){ ord[b+1]=ord[b]; b--; } ord[b+1]=kk; }
   datetime earliestDeferred=0; bool haveDeferred=false; datetime maxProcessed=floor;
   for(int oi=0;oi<gN;oi++)
   {
      int g=ord[oi];
      // Teil-Schliessung: solange ein Rest-Ticket dieser Position offen ist -> NICHT werten (nur diese Gruppe ueberspringen)
      if(HasOpenRemainder(gOpen[g],gSym[g],gType[g],gMagic[g],gPrice[g]))
      {
         // §06-fix (mittel): Deferral zeitlich deckeln. Ein 0.01-Lot-Rest konnte die Verlustwertung (R5/R6/R25) UNBEGRENZT
         //   aufhalten, obwohl der Verlust laengst realisiert ist ("0.99 von 1.0 Lot schliessen, Rest offen lassen").
         //   Nach 10 min wird ein bereits realisierter VERLUST gewertet — nur Verluste, damit ein realisierter Teil-Gewinn
         //   die Serie nicht vorzeitig zuruecksetzt, falls der Rest noch ins Minus dreht.
         double effNet = gHasMan[g] ? gManNet[g] : (gEaFault[g] ? gEaNet[g] : 0);
         bool   stale  = (SrvTime()-gMax[g] >= 600);
         if(!(stale && effNet<0 && !IsProcessedAny(gKey[g],gKeyLeg[g])))
         { if(!haveDeferred || gMin[g]<earliestDeferred){ earliestDeferred=gMin[g]; haveDeferred=true; } continue; }
         Journal("CLOSE",gSym[g],"-",0,0,0,0,0,"Teil-Close: realisierter Verlust nach 10 min gewertet (Rest noch offen), net "+DoubleToString(effNet,2),gTick[g],effNet);
      }
      if(IsProcessedAny(gKey[g],gKeyLeg[g])) continue;          // schon gewertet (idempotent, inkl. Alt-Marker)
      // B4/6: gab es einen Trader-Close-Anteil -> der zaehlt fuer Serie/Cooldown/Revenge.
      // §05-fix (hoch): auch ein reiner EA-Close mit TRADER-VERSCHULDEN (R7 SL entfernt / R1 Ueberrisiko / R8) zaehlt —
      //   sonst waescht "SL entfernen und den EA schliessen lassen" die Verlustserie (Laundering). NUR echte Schutz-Flats
      //   (Lock-SafeCloseAll / R12) bleiben ausgeschlossen (kein Trader-Verschulden).
      // §07-fix: Verluste eines VERGANGENEN Servertags nicht mehr in die Serie des neuen Tages zaehlen (RollNewDay hat
      //   CONSEC bereits genullt) — sonst startete der neue Tag mit geerbten Verlusten und Cooldown/Sperre feuerten zu frueh.
      bool sameDay = (DayKeyOf(gMax[g]-EffResetHour()*3600) == (long)ServerDayKey());
      if(!sameDay)         Journal("CLOSE",gSym[g],"-",0,0,0,0,0,"Close aus vorherigem Servertag — zaehlt nicht fuer die heutige Serie, net "+DoubleToString(gNet[g],2),gTick[g],gNet[g]);
      else if(gHasMan[g])  ApplyResult(gManNet[g],gTick[g],gSym[g],gType[g]);
      else if(gEaFault[g]) ApplyResult(gEaNet[g], gTick[g],gSym[g],gType[g]);
      else                 Journal("CLOSE",gSym[g],"-",0,0,0,0,0,"EA-Schutz-Close (zaehlt nicht fuer die Serie), net "+DoubleToString(gEaNet[g],2),gTick[g],gEaNet[g]);   // P0-3
      AddProcessed(gKey[g],gMax[g]);
      if(gMax[g]>maxProcessed) maxProcessed=gMax[g];
   }
   // Floor sicher setzen: nie ueber einen noch offenen (deferred) Close hinaus -> spaeter erneut scannbar
   datetime newFloor = haveDeferred ? (earliestDeferred>1?earliestDeferred-1:floor) : maxProcessed;
   if(newFloor<floor) newFloor=floor;
   GlobalVariableSet(GV_LAST_CLOSE,(double)newFloor);
   // v0.22: die drei O(N_GlobalVariables)-Sweeps NICHT bei jedem Close (Wine-Freeze-Schutz) — reine Aufraeum-Housekeeping, 60s reicht
   static uint s_lastPruneMs=0;
   if(GetTickCount()-s_lastPruneMs >= 60000)
   {
      s_lastPruneMs=GetTickCount();
      // v0.43-fix (KRITISCH): Karenz von 6h. Frueher wurden die Dedup-Marker SOFORT mit dem Floor gepruned
      //   (nur der allerletzte ueberlebte). Fuer ResolveHistory war das ok (der Floor selbst schuetzt), aber
      //   der Ticket-Fallback prueft genau diese Marker -> er fand keine und wertete ALLES ein zweites Mal
      //   (doppelte CLOSE-Zeilen, doppelte Verlustserie, doppeltes Netto im Kalender).
      PruneGV("RGP_",   newFloor-21600);           // verarbeitete Positionen erst nach 6h vergessen (Dedup fuer beide Pfade)
      PruneGV("RGM_",   SrvTime()-2*86400);        // v0.45: "im Cockpit gezeigt"-Marker erst nach 2 Tagen (hier im 60s-Block, nicht alle 2s)
      PruneShots();                                // v0.47: alte Screenshots loeschen (InpShotKeepDays)
      PruneGV("RGEACF_",SrvTime()-2*86400);     // §05-fix: Fault-Marker VOR RGEAC_ pruenen (RGEAC_ ist kein Praefix von RGEACF_, aber Reihenfolge egal)
      PruneGV("RGEAC_", SrvTime()-2*86400);     // alte EA-Close-Marker aufraeumen
      PruneRevenge();                              // R25: abgelaufene Revenge-Fenster (v0.17)
      PruneNaked();                                // §06-fix: R7-Grace-Marker geschlossener Tickets (O(N_GV) -> nur hier, nicht je Enforcement-Cycle)
   }
   g_gvDirty=true;                                 // v0.22: Flush gebuendelt am Cycle-Ende (nicht hier synchron im Close-Tick)
}

//--- R7: naked = ohne SL/TP. Frist ab OrderOpenTime (restart-fest, kein In-Memory-State) ----------

//--- Close-Queue: ticketbasiert, Retry-Limit, Backoff, Error-Codes, Journal je Versuch ---
int  QFind(int ticket){ for(int i=0;i<ArraySize(g_qTicket);i++) if(g_qTicket[i]==ticket) return i; return -1; }
void QRemoveAt(int idx)
{
   int n=ArraySize(g_qTicket);
   for(int i=idx;i<n-1;i++){ g_qTicket[i]=g_qTicket[i+1]; g_qReason[i]=g_qReason[i+1]; g_qTries[i]=g_qTries[i+1]; g_qNextMs[i]=g_qNextMs[i+1]; }
   ArrayResize(g_qTicket,n-1); ArrayResize(g_qReason,n-1); ArrayResize(g_qTries,n-1); ArrayResize(g_qNextMs,n-1);
}
void RequestClose(int ticket,string reason)   // Lots werden beim Close live aus OrderLots() gelesen (partial-close-fest)
{
   if(QFind(ticket)>=0) return;            // schon eingereiht -> kein Doppel-Close
   int n=ArraySize(g_qTicket);
   ArrayResize(g_qTicket,n+1); ArrayResize(g_qReason,n+1); ArrayResize(g_qTries,n+1); ArrayResize(g_qNextMs,n+1);
   g_qTicket[n]=ticket; g_qReason[n]=reason; g_qTries[n]=0; g_qNextMs[n]=GetTickCount();
}
bool IsRetryableClose(int err)
{
   switch(err)
   {  // transiente Fehler -> kurzer Backoff, erneut versuchen
      case 4:   case 6:   case 8:   case 128: case 129:   // 132=ERR_MARKET_CLOSED wird in ProcessCloseQueue separat behandelt (langer Backoff)
      case 135: case 136: case 137: case 138: case 146: return true;
   }
   return false;   // sonst: harter Backoff, schneller Richtung FINAL-FAIL
}
uint CloseBackoffMs(int tries)
{
   double ms=(double)InpCloseBackoffMs*MathPow(2.0,(double)(tries-1));
   if(ms>(double)InpCloseMaxBackoffMs) ms=(double)InpCloseMaxBackoffMs;
   if(ms<1) ms=1;
   return (uint)ms;
}
// v0.31: Signatur der In-Scope-Positionen (Ticket + SL + TP) -> Aenderung bei GLEICHER Anzahl = User hat SL/TP modifiziert.
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
// §06-fix (mittel): Zwischen Enqueue und tatsaechlichem Close koennen Sekunden bis (bei err=132 Markt zu) Stunden liegen.
//   Bisher pruefte die Queue nur "existiert/offen", nie ob der GRUND noch besteht: eine inzwischen geheilte Position
//   (SL/TP nachgetragen, Risiko verkleinert) oder eine Position nach abgelaufener Sperre wurde trotzdem zwangsgeschlossen
//   (Slippage-Kosten ohne Regelgrund). Jetzt wird der Grund unmittelbar vor dem Close re-validiert.
bool CloseReasonStillValid(int ticket,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return false;
   if(OrderCloseTime()!=0) return false;
   int ty=OrderType();
   if(StringFind(reason,"R22")==0) return (InpCloseManualTrades && OrderMagicNumber()==0);   // R22 bleibt gueltig, solange die Order manuell und die Regel aktiv ist
   if(StringFind(reason,"Lock")==0) return IsLocked();               // Sperre inzwischen abgelaufen (z.B. ueber Mitternacht)?
   if(ty!=OP_BUY && ty!=OP_SELL) return true;                        // Pending: Loeschen kostet nichts -> nicht weiter pruefen
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
   if(StringFind(reason,"R2 Idee")==0) return (IdeaOpenRiskPct(OrderSymbol(),(ty==OP_BUY)) > EffIdeaCap()*InpRiskTolFactor);
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
      if(OrderCloseTime()!=0){ QRemoveAt(i); continue; }                     // bereits geschlossen (nicht durch uns)
      int    tp =OrderType();
      string sym=OrderSymbol();
      // Grund re-validieren — VOR beiden Zweigen. Vorher stand die Pruefung erst hinter dem Pending-Zweig, dadurch wurde
      // eine eingereihte Pending-Order auch dann noch geloescht, wenn der Grund inzwischen entfallen war (z.B. Sperre
      // abgelaufen oder InpCloseManualTrades zwischenzeitlich aus).
      if(!CloseReasonStillValid(ticket,g_qReason[i]))
      { Journal("CLOSE",sym,"-",0,0,0,0,0,"Queue verworfen — Grund entfallen: "+g_qReason[i],ticket); QRemoveAt(i); continue; }
      if(!OrderSelect(ticket,SELECT_BY_TICKET)){ QRemoveAt(i); continue; }   // Auswahl nach der Pruefung wiederherstellen
      if(tp!=OP_BUY && tp!=OP_SELL)                                          // Pending -> loeschen
      {
         if(IsTradeContextBusy()) return;   // v0.31: Kontext KURZ vor OrderDelete erneut pruefen -> nicht in einen laufenden User-Modify hinein (= Wine-Crash)
         if(OrderDelete(ticket)){ Journal("CLOSE",sym,"-",0,0,0,0,0,"Queue DELETE ok: "+g_qReason[i]); QRemoveAt(i); }
         else
         {
            int derr=GetLastError(); g_qTries[i]++; g_qNextMs[i]=nowMs+CloseBackoffMs(g_qTries[i]);
            if(g_qTries[i]>=InpCloseRetries){ Journal("CLOSE",sym,"-",0,0,0,0,0,StringFormat("Queue DELETE FINAL-FAIL err=%d: %s",derr,g_qReason[i])); QRemoveAt(i); }
            else                              Journal("CLOSE",sym,"-",0,0,0,0,0,StringFormat("Queue DELETE RETRY %d err=%d: %s",g_qTries[i],derr,g_qReason[i]));
         }
         continue;
      }
      RefreshRates();   // (Grund-Re-Validierung ist oben, vor dem Pending-Zweig, passiert)
      double lots =OrderLots();
      double price=(tp==OP_BUY) ? MarketInfo(sym,MODE_BID) : MarketInfo(sym,MODE_ASK);
      if(IsTradeContextBusy()) return;   // v0.31: Kontext UNMITTELBAR vor OrderClose erneut pruefen -> kein Schliessen in einen laufenden User-Modify (= Wine-Crash, Kernursache)
      if(OrderClose(ticket,lots,price,InpSlippage,clrRed))
      {
         MarkEaClosed(ticket,g_qReason[i]);                                  // B5/B8: Marker ERST nach bestaetigtem Close (+ §05-fix: Fault-Grund fuer Verlustserie)
         Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue OK (Versuch %d): %s",g_qTries[i]+1,g_qReason[i]),ticket);
         QRemoveAt(i);
      }
      else
      {
         int  err  =GetLastError();
         if(OrderSelect(ticket,SELECT_BY_TICKET) && OrderCloseTime()!=0)     // B5: false-Rueckgabe, aber serverseitig DOCH geschlossen (Requote/Timeout)
         {
            MarkEaClosed(ticket,g_qReason[i]);
            Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue OK (nach false-Rueckgabe err=%d): %s",err,g_qReason[i]),ticket);
            QRemoveAt(i);
         }
         else if(err==132)                                                  // P1: ERR_MARKET_CLOSED -> langer Backoff, NICHT eskalieren (kein Request-Storm uebers Wochenende)
         {
            g_qNextMs[i] = nowMs + 900000;   // 15 min warten, Ticket bleibt in der Queue
            Journal("CLOSE",sym,"-",lots,0,0,0,0,StringFormat("Queue WAIT Markt geschlossen (err=132, 15min Backoff): %s",g_qReason[i]));
         }
         else                                                               // echter Fehlversuch -> Backoff/Retry, KEIN Marker
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
uint LsHash(string s)   // gesalzene djb2-Variante (HMAC-light, kein echtes Crypto)
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
          DoubleToString(g_initBalConfirmed ? g_initialBalance : 0,2);   // §04-fix (mittel): R4b-Basis in der Datei — ueberlebt den 4-Wochen-GV-Ablauf (Feld 9, ans Ende = alte 8-Feld-Dateien lesbar). NUR bestaetigte Basis — sonst wuerde die Auto-Basis ueber die Datei zur "bestaetigten"
}
// §04-fix (mittel): gespeicherte R4b-Basis aus der (signierten) Lockstate-Datei — fuer die OnInit-Kaskade,
// wenn die GlobalVariables nach >4 Wochen Pause abgelaufen sind und InpInitialBalance nicht gesetzt ist.
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
   if(line==g_lockSig) return;            // unveraendert -> kein Disk-Write
   // v0.63-FIX (fail-open, im Test gefunden): Dieser Spiegel lief JEDEN Cycle (~1s), der Abgleich
   //   ReconcileLockstate nur alle 5s. Wer RG_HARD_LOCK per F3 loeschte, sah die Sperre binnen einer
   //   Sekunde AUCH aus der signierten Datei verschwinden — der Spiegel ueberholte den Waechter und
   //   loeschte genau das Beweisstueck, aus dem die Sperre haette zurueckgeholt werden sollen.
   //   Jetzt gilt: bevor eine GEAENDERTE Lage auf die Platte geht, wird gegen die Datei abgeglichen.
   //   Eine dort noch AKTIVE Sperre wandert vorher in die GVs zurueck (ReconcileLockstate schreibt selbst).
   //   KEIN IsTradeContextBusy-Gate hier (Verify-Fund gegen die erste Fassung dieses Fixes): dieser Spiegel ist
   //   die vom GV-Flush UNABHAENGIGE, absturzsichere Persistenz. PersistLatch() ueberspringt bei belegtem
   //   Trade-Kontext den Flush und verlaesst sich darauf, dass die .dat trotzdem geschrieben wird. Haette man
   //   hier ebenfalls gegatet, schwiegen bei R4b-Ausloesung waehrend einer Close-Queue-Retry BEIDE Schichten
   //   gleichzeitig — ein Absturz in diesem Fenster haette den Hard-Lock verloren. Der zusaetzliche Lesezugriff
   //   ist dieselbe winzige Datei, die hier ohnehin geschrieben wird.
   if(!g_lsGuard)
   {
      g_lsGuard=true; ReconcileLockstate(true); g_lsGuard=false;
      payload=LsPayload();               // Abgleich kann Sperren zurueckgeholt haben
      line="MMTLS1;"+payload+";"+IntegerToString((long)LsHash(payload));
      if(line==g_lockSig) return;        // ReconcileLockstate hat bereits geschrieben
   }
   int h=FileOpen(LOCKFILE,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE){ PrintFormat("Mamal: Lockstate-Schreibfehler %d",GetLastError()); return; }
   FileWriteString(h,line+"\r\n");
   FileClose(h);
   g_lockSig=line;
   if(!GlobalVariableCheck(GV_LS_SEEN) || GlobalVariableGet(GV_LS_SEEN)<=0.5)
   { GlobalVariableSet(GV_LS_SEEN,1); g_gvDirty=true; }   // ab jetzt ist ein Fehlen der Datei ein Befund
}
bool ReadLockstateRaw(string &payloadOut)   // true=Datei vorhanden; payloadOut="CORRUPT" wenn ungueltig
{
   payloadOut="";
   if(!FileIsExist(LOCKFILE)) return false;
   // §06-fix (mittel): Datei EXISTIERT, laesst sich aber nicht oeffnen (Sharing-Lock durch Virenscanner/Backup/Sync, I/O-Fehler).
   //   Das wurde bisher wie "Erststart" behandelt -> der restriktivere Datei-Zustand wurde ueberschrieben (fail-OPEN).
   //   Jetzt: kurzer Retry, danach wie CORRUPT behandeln (fail-closed) statt die Sperre stillschweigend zu verlieren.
   int h=INVALID_HANDLE;
   for(int a=0;a<3 && h==INVALID_HANDLE;a++)
   { h=FileOpen(LOCKFILE,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE); if(h==INVALID_HANDLE) Sleep(20); }
   if(h==INVALID_HANDLE){ PrintFormat("Mamal: Lockstate vorhanden, aber nicht lesbar (err=%d) -> fail-closed.",GetLastError()); payloadOut="CORRUPT"; return true; }
   string line=FileReadString(h);
   FileClose(h);
   string parts[]; int k=StringSplit(line,(ushort)';',parts);
   if(k<3 || parts[0]!="MMTLS1"){ payloadOut="CORRUPT"; return true; }
   string payload=""; for(int i=1;i<k-1;i++) payload+=(i>1?";":"")+parts[i];
   if((uint)StringToInteger(parts[k-1]) != LsHash(payload)){ payloadOut="CORRUPT"; return true; }
   payloadOut=payload;
   return true;
}
// §05-fix (hoch): auch PERIODISCH aus Cycle aufrufbar. ReconcileLockstate() lief bisher nur in OnInit — intraday las
//   Cycle die Sperren direkt aus den GlobalVariables, die per F3 loeschbar sind (Sperre weg, und WriteLockstate spiegelte
//   danach den entsperrten Zustand mit gueltiger Signatur zurueck = EA wusch seine eigene Tamper-Erkennung). Jetzt holt
//   der periodische Aufruf noch AKTIVE Sperren aus der signierten Datei zurueck und journalt die GV-Loeschung als TAMPER.
void ReconcileLockstate(bool periodic=false)   // restriktivsten Zustand aus GV + Datei; fail-closed bei Beschaedigung
{
   string payload; bool had=ReadLockstateRaw(payload);
   // v0.63 (Verify-Fund, kritisch): Eine FEHLENDE Datei galt bisher als Erststart und blieb folgenlos —
   //   damit liess sich der Schutz mit einem Explorer-Klick plus einem F3-Loeschen sauber aushebeln:
   //   erst die Datei weg (faellt niemandem auf), dann die GlobalVariable weg, und der naechste Schreibvorgang
   //   legte die Datei aus dem entschaerften Zustand korrekt signiert neu an. Kein Race, voll reproduzierbar.
   //   Ab dem ersten erfolgreichen Schreiben merkt sich der EA deshalb, dass es die Datei GAB (GV_LS_SEEN);
   //   verschwindet sie danach, ist das ein Manipulationsbefund und wird wie eine korrupte Datei behandelt.
   if(!had)
   {
      if(GlobalVariableCheck(GV_LS_SEEN) && GlobalVariableGet(GV_LS_SEEN)>0.5)
      { GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,6); GlobalVariablesFlush();
        // v0.64: Erzwungener Alert NUR beim Zustandswechsel. Heilt der Zustand nicht aus (schreibgeschuetzter
        //   Ordner, Datei-Rechte), feuerte der Zweig sonst in JEDEM Cycle einen modalen Dialog — das haette
        //   das Terminal unbedienbar gemacht und waere schlimmer als die verpasste Meldung, die es behebt.
        if(!g_lsMissWarned)
        { g_lsMissWarned=true;
          Notify(T("tamper.lockstateMissing"),false,true);
          Journal("TAMPER","-","-",0,0,0,0,0,"Lockstate-Datei fehlt (geloescht?) -> fail-closed (Tagessperre)"); }
        g_lsGuard=true; WriteLockstate(); g_lsGuard=false;   // direkt schreiben: der Abgleich hat nichts mehr zu lesen
        return; }
      if(!periodic) WriteLockstate(); return;   // echter Erststart: anlegen, kein Alarm
   }
   if(payload=="CORRUPT")
   {
      GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,6); GlobalVariablesFlush();
      if(!g_lsCorruptWarned)
      { g_lsCorruptWarned=true;
        Notify(T("tamper.lockstateCorrupt"),false,true);
        Journal("TAMPER","-","-",0,0,0,0,0,"Lockstate korrupt -> fail-closed (Tagessperre)"); }
      g_lsGuard=true; WriteLockstate(); g_lsGuard=false;   // v0.64: ohne Guard rief WriteLockstate den Abgleich
      return;                                              //   erneut auf -> zwei Alerts und zwei TAMPER-Zeilen je Korruption
   }
   g_lsMissWarned=false; g_lsCorruptWarned=false;   // Datei ist wieder lesbar und gueltig -> Latches frei fuer den naechsten echten Befund
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
      bool   restored=false;   // eine noch AKTIVE Sperre musste aus der Datei zurueckgeholt werden -> GV manipuliert
      if(fHard==1 && !IsHardLocked()){ GlobalVariableSet(GV_HARD_LOCK,1); restored=true; if(!periodic) Notify(T("tamper.hardLockRestored"),false,true); }
      datetime gLockU=GlobalVariableCheck(GV_LOCK_UNTIL)?(datetime)GlobalVariableGet(GV_LOCK_UNTIL):0;
      if((datetime)fLockU>gLockU && (datetime)fLockU>SrvTime()){ GlobalVariableSet(GV_LOCK_UNTIL,(double)fLockU); restored=true; }   // nur noch AKTIVE Tagessperre zurueckholen (abgelaufene nicht -> RollNewDay-Clear bleibt)
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
      if(k>=9)   // §04-fix (mittel): R4b-Basis aus der Datei zuruecklesen, falls die GVs (4-Wochen-Ablauf) sie verloren haben — Feld 9 enthaelt nur BESTAETIGTE Basen
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
// damit das Risiko in der Enforcement nie faelschlich als 0 erscheint (sonst wuerde R1/R12/R17 nicht greifen).
double TickVal(string s)
{
   double tv=MarketInfo(s,MODE_TICKVALUE);
   if(tv>0){ return tv; }
   double ts=MarketInfo(s,MODE_TICKSIZE), cs=MarketInfo(s,MODE_LOTSIZE);
   if(ts>0 && cs>0)   // grobe Schaetzung in Quote-Waehrung (ohne FX-Konvertierung) -> besser als 0
   {
      // §07-fix: Die Schaetzung ist SELBSTKONSISTENT — CalcLot und EnforceRisk rechnen mit demselben falschen Wert,
      //   der Fehler blieb dadurch unsichtbar. Eine verlaessliche FX-Konvertierung ist ohne Broker-spezifische
      //   Symbolnamen nicht seriös herzuleiten; also wird der Zustand jetzt wenigstens SICHTBAR gemacht
      //   (Panel/Cockpit-Flag + taegliche Warnung), damit man das Symbol/die Kontowaehrung prueft.
      g_tvEstimate=true;
      if(DayKeyOf(g_lastTvWarnDay)!=DayKeyOf(SrvTime()))
      { g_lastTvWarnDay=SrvTime(); PrintFormat("Mamal: WARN TickValue fuer %s nicht verfuegbar -> Schaetzung in QUOTE-Waehrung (Risiko ungenau, NICHT konvertiert!). Symbol/Kontowaehrung pruefen.", s);
        Journal("INFO",s,"-",0,0,0,0,0,"TickValue fehlt -> Risiko-Schaetzung ohne FX-Konvertierung (ungenau)"); }
      return ts*cs;
   }
   return 0;
}
// R3-Basis: EINE %-Basis fuer additiven Pfad UND Rekonstruktion (stabile Tagesbasis, kein Live-Equity-Drift)
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

//--- R3-Reconciliation: Tagesbudget (RG_DAY_RISK) aus Broker-Daten rekonstruieren (crash-fest) ---
// R3 zaehlt HEUTE EROEFFNETES Risiko ("Schuesse"), KEIN Refund. Nach Crash/Restart kann der additive
// RG_DAY_RISK fehlen -> aus offenen + heute geschlossenen TOOL-Trades (Magic) rekonstruieren, jede
// Position EINMAL (ProcKey-Gruppierung, Partial-Closes summieren zur Entry-Lotzahl). Denominator =
// stabile Tagesbasis (RG_DAYSTART_EQ), NICHT Live-Equity -> kein intraday-Drift. Anwendung via max(persisted,rekonstruiert).
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
   double base  = DayRiskBase(); if(base<=0) return 0;   // gleiche Basis wie der additive R3-Pfad

   string gKey[]; double gLots[]; double gOpen[]; string gSym[]; int gType[]; double gSL[]; bool gHasSL[];
   int gN=0;
   // (1) offene Tool-Positionen, heute eroeffnet
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int ty=OrderType(); if(ty!=OP_BUY && ty!=OP_SELL) continue;
      if(OrderMagicNumber()!=InpMagic) continue;                       // R3 = nur Tool-Trades (wie der additive Pfad)
      if(DayKeyOf(OrderOpenTime()-InpDayResetHour*3600)!=today) continue;                   // gestern eroeffnet -> kein heutiger Schuss
      RDR_Add(gKey,gLots,gOpen,gSym,gType,gSL,gHasSL,gN,
              ProcKey(OrderOpenTime(),ty,OrderSymbol(),OrderMagicNumber(),OrderOpenPrice()),
              OrderLots(),OrderOpenPrice(),OrderSymbol(),ty,OrderStopLoss());
   }
   // (2) heute eroeffnete Tool-Positionen aus History (Teil-Closes summieren zur Entry-Lotzahl, EINMAL pro Position)
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
      // §07-fix: Diese Zeile lief alle 15 s erneut und hat die Audit-CSV den ganzen Tag mit identischen INFO-Zeilen
      //   geflutet (eine SL-lose Position = ~5.760 Zeilen/Tag). Jetzt nur noch als Print, max. 1x/Tag.
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
   if(reconstructed > persisted + 0.0001)   // nur RAISEN (kein Refund) -> max(persisted, rekonstruiert)
   {
      GlobalVariableSet(GV_DAY_RISK, reconstructed); GlobalVariablesFlush();
      Journal("INFO","-","-",0,0,0,0,reconstructed,StringFormat("R3 Reconcile DayRisk %.2f%% -> %.2f%% (rekonstruiert)",persisted,reconstructed));
   }
}

// v0.28: Master-Wahl per Heartbeat (terminal-weite GlobalVariables). Nur der Master erzwingt/schreibt.
// Master stirbt/entfernt -> Heartbeat wird stale (>6s) -> naechste Instanz uebernimmt. Fail-safe: solange
// mind. eine Instanz laeuft, ist das Konto ueberwacht. Enforcement ist kontoweit (nach Magic, nicht Symbol),
// also reicht EINE Instanz voellig.
//  Fixe nach Verify: Identitaet in DOUBLE (ChartID>2^53 -> long->double->long verlor sich); Uhr = TimeLocal
//  (fuer alle Instanzen im Terminal identisch, kein Server-Offset-Drift); Stale bidirektional (Uhr-Ruecksprung).
bool ClaimMaster()
{
   double   myKey = (double)ChartID();
   datetime now   = TimeLocal();
   double   mid = GlobalVariableCheck(GV_MASTER)    ? GlobalVariableGet(GV_MASTER)             : 0.0;
   datetime hb  = GlobalVariableCheck(GV_MASTER_HB) ? (datetime)GlobalVariableGet(GV_MASTER_HB) : 0;
   double   dt  = (double)((long)now-(long)hb); if(dt<0.0) dt=-dt;   // Betrag: vergangen ODER zukunft = stale
   if(mid==myKey)   // ich bin bereits Master -> Heartbeat auffrischen (double round-trip exakt -> erkenne mich wieder)
   { GlobalVariableSet(GV_MASTER_HB,(double)now); return true; }
   if(mid==0.0)   // §07-fix: freien Slot ATOMAR beanspruchen — zwei gleichzeitig startende Instanzen konnten sich sonst
   {              //   beide als Master sehen (Set war nicht atomar). SetOnCondition setzt nur, wenn der Wert noch 0 ist.
      // v0.42-fix (KRITISCH): SetOnCondition legt eine FEHLENDE Variable NICHT an (Err 4058) -> nach einem
      //   GlobalVariableDel(GV_MASTER) (alte Deinit-Freigabe / F3) war NIE wieder eine Master-Wahl moeglich.
      //   Slot bei Bedarf erst anlegen (Temp, Wert 0.0) — die Claim-Atomik bleibt: es gewinnt genau EINER.
      if(!GlobalVariableCheck(GV_MASTER)) GlobalVariableTemp(GV_MASTER);
      if(!GlobalVariableSetOnCondition(GV_MASTER,myKey,0.0)) return false;   // ein anderer war schneller
      GlobalVariableSet(GV_MASTER_HB,(double)now); return true;
   }
   if(dt>10.0)   // verwaist (>10s Schwelle: Puffer gegen langsame/eingefrorene Cycles unter Wine; Hysterese verhindert Doppel-Handeln bei Wett-Claim)
   { if(!GlobalVariableSetOnCondition(GV_MASTER,myKey,mid)) return false;    // nur uebernehmen, wenn der Slot noch dem stalen Master gehoert
     GlobalVariableSet(GV_MASTER_HB,(double)now); return true; }
   return false;   // anderer ist frischer Master
}
void Cycle()
{
   UpdateSrvOffset();   // §04-fix (mittel): Offset auch aus OnTimer nachziehen — TimeCurrent bewegt sich mit JEDER Market-Watch-Quote, nicht nur mit Chart-Ticks
   if(g_armed!=0 && GetTickCount()-g_armMs > 30000) g_armed=0;   // v0.28: FOMO-Arm-Timeout auf JEDER Instanz (nicht nur Master)

   // v0.28: Einzel-Instanz-Sperre + Hysterese. Nur der bestaetigte Master (>=2 Cycles in Folge) erzwingt + schreibt Dateien
   // (Journal/Lockstate/Cockpit/Flush). Verhindert Datei-Kollision bei EA auf mehreren Charts (= Wine-Crash beim TP/SL-Verschieben)
   // UND Startup-/Wett-Claim-Bursts. Passive Instanzen zeigen nur ihr Panel; BUY/SELL funktioniert auf jedem Chart (Klick-Pfad).
   g_masterStreak = ClaimMaster() ? (g_masterStreak+1) : 0;
   if(g_masterStreak < 2)
   {
      // v0.38 (Verify): abweichendes InpMagic auf einem passiven Chart = dessen Panel-Trades waeren fuer den
      //   Master unsichtbar (weder InScope noch R22) -> unbewacht. Einmalig deutlich warnen.
      static bool magicWarned=false;
      if(!magicWarned && GlobalVariableCheck(GV_MAGIC) && (int)GlobalVariableGet(GV_MAGIC)!=InpMagic)
      { magicWarned=true; Notify(TF("cfg.magicMismatchMaster",IntegerToString(InpMagic),IntegerToString((int)GlobalVariableGet(GV_MAGIC)))); }
      // v0.42-fix: KEIN Master heisst KEIN Enforcement, KEINE Close-Wertung, KEINE Cockpit-Daten.
      //   Dieser Zustand war bisher voellig unsichtbar (Panel lief weiter) — jetzt laut melden.
      // v0.43-fix: NUR alarmieren, wenn WIRKLICH NIEMAND Master ist (Slot frei/verwaist). Eine passive
      //   Instanz ist der Normalfall (genau EINE ist Master) — die darf nicht dauernd warnen.
      bool someoneIsMaster = (GlobalVariableCheck(GV_MASTER) && GlobalVariableGet(GV_MASTER)!=0.0
                              && GlobalVariableCheck(GV_MASTER_HB)
                              && MathAbs((double)((long)TimeLocal()-(long)GlobalVariableGet(GV_MASTER_HB)))<=10.0);
      // v0.45 (Verify): zeitbasiert statt cycle-basiert (Cycle-Takt haengt an InpTimerSeconds) und Latch
      //   wird beim Wechsel in den Master-Zustand ebenfalls entschaerft (g_noMasterSince=0 im Master-Pfad).
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
   GlobalVariableSet(GV_MAGIC,(double)InpMagic);   // v0.38: Master publiziert sein InpMagic (Divergenz-Check der passiven Charts)
   g_noMasterSince=0; g_noMasterWarned=false;      // v0.45: als Master ist der Ausfall-Latch entschaerft
   // v0.38-fix (Verify): Selbstheilung — startete der EA VOR dem Broker-Handshake (Autostart-Race:
   //   Balance/Historie noch leer -> Basis 0, fail-closed), Basis nachziehen sobald Kontodaten da sind.
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
   // §07-fix (hoch): Tages-Roll nur mit Bestaetigung durch die (lokal nicht faelschbare) Broker-Zeit -> PC-Uhr vorstellen
   //   wischt Sperre/Basis/Serie nicht mehr weg.
   if(!GlobalVariableCheck(GV_DAYSTART_DAY)) RollNewDay(false);
   else if((long)GlobalVariableGet(GV_DAYSTART_DAY)!=today)
   { if(ServerDayRollConfirmed((long)GlobalVariableGet(GV_DAYSTART_DAY))) RollNewDay(false);
     else WarnUnconfirmedRoll("Tageswechsel"); }
   // v0.30-fix: EFF-Limits + Schutz-aus-Zaehler EINMAL pro Tag, NUR vom Master (hier sind wir im Master-Pfad) -> deterministisch = Master-Input, kein loses Limit durch Init-Reihenfolge/Handoff
   if(!GlobalVariableCheck(GV_EFF_DAY) || (long)GlobalVariableGet(GV_EFF_DAY)!=today)
   { GlobalVariableSet(GV_EFF_DAY,(double)today);
     if(InpDailyLossPct>0) GlobalVariableSet(GV_EFF_DL,InpDailyLossPct);   // Tageswechsel: ein evtl. gelockertes Limit greift jetzt
     if(InpMaxLossPct>0)   GlobalVariableSet(GV_EFF_ML,InpMaxLossPct);
     // §06-fix: alle uebrigen sperr-relevanten Inputs ebenfalls erst am Tageswechsel aus dem Input uebernehmen (Lockern nur hier)
     GlobalVariableSet(GV_EFF_WEEK,   InpWeeklyLossPct);
     GlobalVariableSet(GV_EFF_WARN,   InpMaxLossWarnPct);
     GlobalVariableSet(GV_EFF_GIVE,   InpGivebackPct);
     GlobalVariableSet(GV_EFF_RISK,   DesiredRiskPct());   // v0.36: Wochenwahl (oder Input-Default) — nicht mehr der Roh-Input
     GlobalVariableSet(GV_EFF_LOCKAFT,(double)InpLockAfter);
     GlobalVariableSet(GV_EFF_CDAFT,  (double)InpCooldownAfter);
     GlobalVariableSet(GV_EFF_CDMIN,  (double)InpCooldownMin);
     GlobalVariableSet(GV_EFF_REQSL,  InpRequireSL?1:0);
     GlobalVariableSet(GV_EFF_REQTP,  InpRequireTP?1:0);
     GlobalVariableSet(GV_EFF_CORR,   InpUseCorrCap?1:0);
     GlobalVariableSet(GV_TIGHT_LATCH,InpTightenOnly?1:0);   // Latch nur hier neu setzen -> intraday nicht abschaltbar
     GlobalVariableSet(GV_PROTOFF,0); GlobalVariableSet(GV_PROT_LATCH,0);
     GlobalVariableSet(GV_BLOCKS,0); GlobalVariableSet(GV_FILLS,0); GlobalVariableSet(GV_BLK_BURST,0);   // v0.32: Versuche-Zaehler taeglich zuruecksetzen
     g_gvDirty=true; }

   double eq   = AccountEquity();
   double base = GlobalVariableGet(GV_DAYSTART_EQ);
   if(base<=0){ base=MathMax(AccountBalance(),eq); if(base<=0) base=1; GlobalVariableSet(GV_DAYSTART_EQ,base); }

   double dailyDDpct = (base-eq)/base*100.0;   if(dailyDDpct<0) dailyDDpct=0;
   double totalDDpct = TotalDDpct();           // P0-2: guarded (g_initialBalance<=0 -> 0, keine Division durch 0)

   // R18: Wochenwechsel + Wochenlimit
   long wk=WeekIdx();   // mit gespeichertem (effektivem) Wochenstart -> eine Input-Aenderung verschiebt den Key NICHT (kein kuenstlicher Roll)
   bool wkOk = (!GlobalVariableCheck(GV_WEEK_IDX)) || ServerWeekRollConfirmed((long)GlobalVariableGet(GV_WEEK_IDX));   // §07-fix: auch der Wochen-Roll braucht Broker-Bestaetigung
   if(GlobalVariableCheck(GV_WEEK_IDX) && (long)GlobalVariableGet(GV_WEEK_IDX)!=wk && !wkOk) WarnUnconfirmedRoll("Wochenwechsel");
   if(wkOk && (!GlobalVariableCheck(GV_WEEK_IDX) || (long)GlobalVariableGet(GV_WEEK_IDX)!=wk))
   { if(InpWeekStartDay!=EffWeekStart()){ GlobalVariableSet(GV_EFF_WS,(double)InpWeekStartDay); wk=WeekIdx(); }   // §05-fix: geaenderten Wochenstart NUR am echten Rollover uebernehmen, dann konsistent neu berechnen
     GlobalVariableSet(GV_WEEK_IDX,(double)wk);
     GlobalVariableSet(GV_WEEKSTART_EQ,MathMax(MathMax(AccountBalance(),eq),ReconstructedBalanceAt(ServerWeekStart())));   // §04-fix (mittel): verspaeteter Wochen-Roll (Weekend-Gap) -> Anker-Balance aus History statt gefallenem Ist-Stand
     GlobalVariableSet(GV_WEEK_LOCK,0);
     // v0.36: Wochen-Risiko in die neue Woche uebernehmen; eine vorgemerkte Erhoehung greift JETZT.
     // v0.62-FIX (R23): Der Roll schreibt GV_WEEK_RISK_IDX NICHT mehr. Vorher setzte er ihn auf die neue
     //   Woche -> WeekRiskSet() blieb dauerhaft true -> das geforderte woechentliche Festlegen fand faktisch
     //   nur EIN einziges Mal statt (beim allerersten Mal). Der Index bedeutet jetzt ausschliesslich
     //   "in DIESER Woche bestaetigt" und wird nur noch von SetWeekRisk() gesetzt — also nur durch eine
     //   echte Bestaetigung des Traders.
     //   Wichtig: der WERT wandert weiter (GV_WEEK_RISK/GV_EFF_RISK), sonst faellt EffRiskPct() auf den
     //   Input-Default und R1/R2/R12 wuerden Wochenend-Positionen am Montag zwangsschliessen.
     //   Wichtig 2: die Entscheidung "Pflicht ja/nein" faellt NICHT hier. Der Roll laeuft nur auf dem
     //   Master; haenge dieses Gate an dessen Inputs, koennte ein Chart mit InpRequireWeeklyRisk=false
     //   die Pflicht fuer alle anderen Instanzen aufheben. Gegatet wird lokal ueber WeekRiskPending().
     //   Wichtig 3 (v0.62): Eine VORGEMERKTE Aenderung wird bei aktiver Pflicht NICHT vom Roll aktiviert.
     //   Sie ist ein Vorschlag des Traders, keine Anweisung — und R23 verlangt fuer jede Woche eine
     //   Bestaetigung. Sonst gaebe es zwei Schaeden: (a) eine vorgemerkte SENKUNG wuerde GV_EFF_RISK
     //   autonom druecken, und EnforceRisk (R1) liefe im SELBEN Cycle -> Wochenend-Positionen wuerden am
     //   Montag zwangsliquidiert, der Verlust-Close zaehlte als Trader-Verschulden in Serie/Cooldown;
     //   (b) eine vorgemerkte ERHOEHUNG wuerde die ganze Auto-Scale-Kaskade (Idee/Heat/Tagesbudget) in
     //   einer Woche lockern, die der Trader nie bestaetigt hat. Die Vormerkung bleibt deshalb stehen und
     //   wird erst von SetWeekRisk() verbraucht — sie belegt bis dahin nur das Eingabefeld vor.
     if(GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0)
     { double pend=PendingWeekRisk(); double old=GlobalVariableGet(GV_WEEK_RISK);
       bool   hold = WeekRiskPending();                       // Bestaetigung steht aus -> nichts autonom aendern
       double nr = (pend>0 && !hold) ? pend : old; if(nr>RiskCap()) nr=RiskCap();
       GlobalVariableSet(GV_WEEK_RISK,nr);
       GlobalVariableSet(GV_EFF_RISK,nr);   // Wert wandert mit; ohne das faellt EffRiskPct() auf den Input-Default (R1-Zwangsclose)
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
   if(eq>peak){ peak=eq; GlobalVariableSet(GV_PEAK_EQ,eq); g_gvDirty=true; }   // §07-fix: Peak wurde nie als dirty markiert -> ging bei Crash verloren (R13-Giveback-Anker)
   double profitPct     = (eq-base)/base*100.0;
   double peakProfitPct = (peak-base)/base*100.0;
   double dropFromPeak  = (peak-eq)/base*100.0;
   if(!TargetHit() && profitPct>=InpDailyTargetPct)
   { GlobalVariableSet(GV_TARGET_HIT,1); PersistLatch(); Notify(TF("lock.targetReached",DoubleToString(profitPct,2))); }
   if(EffGivebackPct()>0 && !IsLocked() && peakProfitPct>=InpGivebackArmPct && dropFromPeak>=EffGivebackPct())
   { GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,3); g_gvDirty=true; Notify(TF("lock.giveback",DoubleToString(peakProfitPct,2),DoubleToString(profitPct,2))); }

   TightenOnlyLimits();   // v0.30: Verlust-Limits nur enger stellbar; Lockern erst zum Tageswechsel

   bool tradingDisabled = !IsTradeAllowed();
   bool protLatch = (GlobalVariableGet(GV_PROT_LATCH)>0.5);   // v0.30-fix: GETEILTER Latch -> Master-Handoff zaehlt dieselbe Schutz-aus-Episode nicht doppelt
   if(tradingDisabled && !protLatch)
   { double poc=GlobalVariableGet(GV_PROTOFF)+1; GlobalVariableSet(GV_PROTOFF,poc); GlobalVariableSet(GV_PROT_LATCH,1);
     GlobalVariableSet(GV_PROT_SINCE,(double)SrvTime()); PersistLatch();   // §07-fix: Beginn der Schutz-aus-Phase merken
     Notify(TF("watchdog.autoTradingOff",IntegerToString((int)poc))); Journal("PROTECT_OFF","-","-",0,0,0,0,0,StringFormat("AutoTrading AUS — Watchdog kann NICHT schliessen (heute #%d)",(int)poc)); }
   if(!tradingDisabled && protLatch)
   {
      // §07-fix: Der AutoTrading-Schalter ist der billigste Ein-Klick-Bypass — das Enforcement steht still, waehrend die
      //   zeitbasierten Fristen (Cooldown, Tages-/Wochensperre, Revenge) ungebremst weiterliefen. Aussitzen brachte also
      //   einen Vorteil. Jetzt: die Ausfallzeit wird auf alle noch AKTIVEN Fristen aufgeschlagen.
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

   // §05-fix (hoch): Sperren periodisch (5s) gegen die signierte Lockstate-Datei abgleichen. Faengt das intraday-Loeschen
   //   der RG_*-GlobalVariables per F3 -> aktive Sperre wird aus der Datei wiederhergestellt (nicht vom EA ueberschrieben).
   if(!IsTradeContextBusy() && GetTickCount()-g_lastLockReconcileMs >= 5000){ g_lastLockReconcileMs=GetTickCount(); ReconcileLockstate(true); }   // nicht waehrend einer Trade-Op (Wine-Schutz, wie GV-Flush/History-Scan)

   // v0.22: Voll-History-Scan NICHT 2-3x/Sek (Wine-Freeze-Schutz). Trigger: History-Anzahl geaendert (echter Close -> sofort erfasst, KEIN Enforcement-Loch fuer R5/R6) ODER 2s-Heartbeat (deferred Partial-Close / count-maskierte Faelle).
   // v0.23: waehrend eine Handelsoperation laeuft (User zieht SL/TP ODER EA schliesst) KEIN schwerer History-Scan/Flush -> nicht mit MT4s eigenem Trade-I/O kollidieren (Wine-Crash beim SL/TP-Verschieben). Wird sofort nachgeholt sobald frei (idempotent, Heartbeat/OnTimer).
   static int  s_lastHistTot   = -1;
   static uint s_lastResolveMs = 0;
   int histTot = OrdersHistoryTotal();
   // v0.42/v0.45: Cycle-Puls nur noch als Log-Print (nicht mehr ins Audit-Journal — 1.440 INFO-Zeilen/Tag
   //   verdraengten echte Ereignisse aus der Cockpit-Ansicht). Diagnose bleibt im Experten-Log verfuegbar.
   static uint s_pulseMs=0;
   if(GetTickCount()-s_pulseMs>=60000)
   { s_pulseMs=GetTickCount();
     PrintFormat("Mamal CycleDiag: Ctx=%s HistTotal=%d RGOPN=%d Floor=%s",IsTradeContextBusy()?"BUSY":"frei",histTot,CountOpn(),TimeToString((datetime)GlobalVariableGet(GV_LAST_CLOSE))); }
   if(!IsTradeContextBusy() && (histTot != s_lastHistTot || GetTickCount()-s_lastResolveMs >= 2000))
   { s_lastHistTot = histTot; s_lastResolveMs = GetTickCount(); BackfillHistory(); ResolveHistory(); ResolveByTicketRegistry(); ResolveManualHistory(); HistoryVisibilityWatch(); }   // P0-2/P0-4: Verlustserie aus History (+§06 Sichtbarkeits-Wachhund, +v0.40 Ticket-Fallback, +v0.44 manuelle Trades fuers Cockpit)
   if(GetTickCount()-g_lastReconcileMs >= 15000){ g_lastReconcileMs=GetTickCount(); ReconcileDayRisk(); }   // R3: Tagesbudget gedrosselt (15s) aus Broker-Daten abgleichen

   // v0.31: User-Modify erkennen (gleiche Anzahl In-Scope-Orders, aber SL/TP geaendert) -> ~2s KEINE neue Enforcement-Enqueue, damit die EA keinen Trade schliesst, den der User gerade bearbeitet (= Wine-Crash-Kernursache).
   int scN; double scSig=OrderScopeSig(scN);
   if(scN==g_lastScopeN && MathAbs(scSig-g_lastScopeSig)>0.0000001)
   { if(GetTickCount()-g_modifyQuietMs >= 2000) g_modifyQuietStart=GetTickCount();   // vorherige Serie war abgelaufen -> neue Serie beginnt
     g_modifyQuietMs=GetTickCount(); }
   g_lastScopeN=scN; g_lastScopeSig=scSig;
   // §06-fix (mittel): das Quiet-Fenster ist gleitend und war dadurch UNBEGRENZT verlaengerbar — fortlaufendes SL/TP-Wackeln
   //   konnte R1/R7/R8/R12 dauerhaft unterdruecken (R7 wurde de facto freiwillig). Jetzt hart gedeckelt: nach 10 s
   //   ununterbrochener Modify-Serie laeuft das Enforcement wieder, egal wie oft weitergewackelt wird.
   bool modifyQuiet = (GetTickCount()-g_modifyQuietMs < 2000) && (GetTickCount()-g_modifyQuietStart < 10000);

   // v0.47: SL/TP-Verschiebungen je Ticket protokollieren (Verhaltens-Analyse im Cockpit). Bewusst NICHT
   //   waehrend einer laufenden User-Modify-Serie — sonst wuerde jeder Zwischenschritt des Ziehens
   //   einzeln als eigene Verschiebung gezaehlt. Erst wenn der Nutzer losgelassen hat, zaehlt das Ergebnis.
   { static uint s_trackMs=0;
     if(!modifyQuiet && !IsTradeContextBusy() && GetTickCount()-s_trackMs>=2000){ s_trackMs=GetTickCount(); TrackSLTP(); } }

   // P0-1: Close-Operationen gedrosselt (Wine-Schutz; volle Close-Queue mit Retry-Limit folgt)
   bool canEnforce = (GetTickCount()-g_lastEnforceMs >= (uint)InpCloseThrottleMs);
   if(!tradingDisabled && canEnforce)
   {
      g_lastEnforceMs = GetTickCount();
      if(!modifyQuiet)        EnforceManualTrades();                            // R22: unabhaengig von der Sperre — nur Panel-Trades sind erlaubt
      if(IsLocked())          SafeCloseAll();                                   // Sperre = flat, dringend (Close-Site prueft Kontext erneut)
      else if(!modifyQuiet)   { EnforceSLTP(); EnforceRisk(); EnforceRR(); EnforceHeat(); EnforceIdea(); EnforceEntryState(); }   // waehrend User-Modify: NICHT neu enqueuen (+§05: R5/R13/R16/R25, +§06: R2-Monitor)
      ProcessCloseQueue();   // Detection hat enqueued -> jetzt tatsaechlich schliessen (Retry/Backoff/Journal; Kontext-Recheck an der Close-Site)
   }

   uint now=GetTickCount();
   if(now - g_lastPanelMs >= (uint)InpPanelMs){ g_lastPanelMs=now; DrawPanel(dailyDDpct,totalDDpct,tradingDisabled); }
   WriteLockstate();   // Lockstate-Spiegel aktuell halten (nur bei Aenderung -> Disk; fail-closed .dat, unabhaengig vom GV-Flush)
   if(g_gvDirty && !IsTradeContextBusy()){ GlobalVariablesFlush(); g_gvDirty=false; }   // v0.22: EIN gebuendelter Flush pro Cycle statt bis zu 4 synchronen; v0.23: nicht waehrend einer Trade-Op flushen (.dat-Spiegel oben bleibt crash-sichere fail-closed Sperr-Persistenz, Flush kommt naechsten Cycle)
   if(InpCockpit && GetTickCount()-g_lastCockpitMs>=2000){ g_lastCockpitMs=GetTickCount(); WriteCockpit(); }   // v0.26/v0.37: Live-Zustand fuers Cockpit alle 2s. KEIN IsTradeContextBusy-Gate — WriteCockpit macht nur Datei-I/O, fasst den Trade-Thread nie an (sonst veraltete die JSON bei belegtem Kontext, z.B. Close-Queue-Retries)
   // v0.39: Dashboard-Kommando (Tighten-Only). Einzig erlaubtes Kommando: "endday" = freiwillige Selbstsperre
   //   bis Server-Mitternacht. Lockern ist ueber diesen Kanal PRINZIPIELL unmoeglich (nur Sperre setzen).
   if(FileIsExist(COCKPIT_CMD))
   {
      string cmd="";
      int hc=FileOpen(COCKPIT_CMD,FILE_READ|FILE_TXT|FILE_ANSI);
      if(hc!=INVALID_HANDLE){ cmd=FileReadString(hc); FileClose(hc); }
      // v0.39-fix (Verify): FileDelete-Ergebnis pruefen — eine nicht loeschbare Datei (Read-Only/AV-Lock)
      //   wuerde sonst JEDEN Cycle erneut verarbeitet (Journal-/Alert-Spam im Sekundentakt).
      static bool cmdStuck=false;
      if(!FileDelete(COCKPIT_CMD))
      { if(!cmdStuck){ cmdStuck=true; PrintFormat("Mamal: mamal_cmd.txt nicht loeschbar (err=%d) — Kommando wird ignoriert bis Datei entfernt.",GetLastError()); } }
      else
      {
         cmdStuck=false;
         if(StringFind(cmd,"endday")==0)
         {
            // MathMax: eine evtl. bereits LAENGERE Sperre darf durch endday nie verkuerzt werden (strict tighten-only).
            // Guard: nur wirken, wenn die Sperre sich tatsaechlich VERLAENGERT (kein Doppel-Journal bei erneutem Klick).
            double cur=GlobalVariableCheck(GV_LOCK_UNTIL)?GlobalVariableGet(GV_LOCK_UNTIL):0;
            double nxt=(double)NextServerMidnight();
            if(nxt>cur)
            {
               GlobalVariableSet(GV_LOCK_UNTIL,nxt); GlobalVariableSet(GV_LOCK_WHY,4);
               GlobalVariablesFlush(); WriteLockstate();   // v0.39-fix (Verify): SOFORT persistieren — die cmd-Datei ist bereits geloescht, ein Crash im 1s-Fenster darf die freiwillige Sperre nicht verlieren
               Journal("SELF_LOCK","-","-",0,0,0,0,0,"Tag beendet per Dashboard — Selbstsperre bis Server-Mitternacht");
               Notify(T("lock.selfLock"));
            }
         }
      }
   }
   GlobalVariableSet(GV_MASTER_HB,(double)TimeLocal());   // v0.28: Heartbeat auch am Cycle-ENDE (langsamer Cycle -> Passive sehen ihn nicht faelschlich stale -> kein Wett-Claim mitten im Schreiben)
}

// v0.33: R7-Grace-Uhr pro Ticket ab dem Moment, in dem SL/TP ENTFERNT wurde (nicht ab OrderOpenTime).
//        Sonst haette ein alter Trade nach SL-Entfernen 0s Grace (elapsed-ab-Open laengst > 4s).
// §06-fix (mittel): Grace-Uhr PERSISTENT pro Ticket (GlobalVariable statt Instanz-Array). Vorher lebte sie nur im RAM:
//   Terminal-Neustart, Recompile, Timeframe-Wechsel oder ein Master-Handoff schenkten jedes Mal eine frische Frist, und
//   ein kurzes Wieder-Setzen des SL setzte die Uhr sofort zurueck -> eine nackte Position liess sich beliebig lange halten.
//   Jetzt: Uhr ueberlebt Neustarts, und nach dem Wieder-Setzen von SL/TP wird sie erst nach einer HEILFRIST (60 s) geloescht.
string NkKey(int t){  return "RG_NK_" +IntegerToString(t); }   // seit wann nackt
string NkhKey(int t){ return "RG_NKH_"+IntegerToString(t); }   // seit wann wieder geheilt (SL/TP gesetzt)
datetime NakedSince(int ticket, datetime now)
{
   if(GlobalVariableCheck(NkhKey(ticket))){ GlobalVariableDel(NkhKey(ticket)); g_gvDirty=true; }   // wieder nackt -> Heilfrist verfaellt
   if(GlobalVariableCheck(NkKey(ticket)))  return (datetime)GlobalVariableGet(NkKey(ticket));
   GlobalVariableSet(NkKey(ticket),(double)now); g_gvDirty=true;
   return now;
}
void NakedClear(int ticket, datetime now)   // SL/TP wieder da -> Uhr erst nach Heilfrist loeschen (kein Reset per Kurz-Toggle)
{
   if(!GlobalVariableCheck(NkKey(ticket))) return;
   if(!GlobalVariableCheck(NkhKey(ticket))){ GlobalVariableSet(NkhKey(ticket),(double)now); g_gvDirty=true; return; }
   if(now-(datetime)GlobalVariableGet(NkhKey(ticket)) >= 60)
   { GlobalVariableDel(NkKey(ticket)); GlobalVariableDel(NkhKey(ticket)); g_gvDirty=true; }
}
void PruneNaked()   // Marker fuer nicht mehr offene Tickets entfernen (O(N_GV) -> nur im 60s-Housekeeping aufrufen)
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

void EnforceSLTP()   // R7 (v0.33: 4s Grace ab SL/TP-ENTFERNUNG, gilt auch fuer Panel-Trades; News-Blackout -> sofort)
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
      bool naked  =( (EffRequireSL() && OrderStopLoss()==0.0) || (EffRequireTP() && OrderTakeProfit()==0.0) );   // §06-fix: SL/TP-Pflicht tighten-only (nicht intraday abschaltbar)
      if(!naked){ NakedClear(ticket, now); continue; }       // SL/TP (wieder) da -> Uhr erst nach Heilfrist loeschen
      datetime since   = NakedSince(ticket, now);            // seit wann nackt (persistent, ueberlebt Neustart)
      int      elapsed = (int)(now - since);
      if(elapsed >= grace)                                    // 4s abgelaufen (News: sofort) -> TRADE schliessen (nicht MT4)
         RequestClose(ticket,StringFormat("R7 SL/TP fehlt (%ds nach Entfernen, Grace %ds)",elapsed,grace));
      // sonst: noch innerhalb der Frist -> Zeit, SL/TP nachzutragen
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
      double rp=RiskPctOfBase(OrderSymbol(),OrderLots(),OrderOpenPrice(),sl,DayRiskBase());   // B11: stabile Tagesbasis statt Live-Equity (fallende Equity schliesst keine korrekte Position)
      if(rp > EffRiskPct()*InpRiskTolFactor)   // §06-fix: Risiko/Trade tighten-only
         RequestClose(OrderTicket(),StringFormat("R1 Risiko zu gross (%.2f%%)",rp));
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
      // §07-fix: Tool-Trades waren KATEGORISCH ausgenommen (B3) — ein nachtraeglich verschlechterter TP blieb damit bei
      //   aktivem R8 unenforced. Der eigentliche Zweck war nur, Fill-Slippage direkt nach dem Entry zu tolerieren:
      //   deshalb jetzt nur noch eine Schonfrist von 60 s statt einer Dauer-Ausnahme.
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

// §06-fix (mittel): R2-Monitor. Fuer den Idee-Cap gab es NUR ein Entry-Gate — eine einmal ueberschrittene Idee
//   (z.B. per SL-Entfernen durchs Gate geschmuggelt) blieb dauerhaft ueber dem Cap, ohne dass irgendetwas korrigierte.
//   Analog zu EnforceHeat: die JUENGSTE Position der betroffenen Idee schliessen, eine Korrektur pro Cycle.
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
      if(newest>0) RequestClose(newest,"R2 Idee-Cap ueberschritten");
      return;                                                // eine Korrektur pro Cycle (wie EnforceHeat)
   }
}

// §06-fix (mittel): History-Sichtbarkeits-Wachhund. R5/R6/R25 und die R3-Rekonstruktion lesen ueber OrdersHistoryTotal(),
//   das in MT4 NUR die im Kontohistorie-Tab eingestellte Periode liefert. Stellt der Nutzer den Tab auf einen alten
//   Zeitraum, sind die heutigen Closes unsichtbar -> Verlustserie/Cooldown/Sperre feuern nie, ohne jede Erkennung.
//   Wachhund: verschwundene In-Scope-Tickets muessen in der History auffindbar sein. Zwei-Pass-Verfahren (Verdachtsliste),
//   damit ein kurzer Timing-Versatz direkt nach dem Close keinen Fehlalarm ausloest.
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
   // Pass 2: alte Verdachtsfaelle erneut pruefen -> immer noch unsichtbar = History gefiltert
   for(int s=ArraySize(g_suspTicket)-1;s>=0;s--)
   {
      int t=g_suspTicket[s];
      if(OrderSelect(t,SELECT_BY_TICKET) && OrderCloseTime()!=0) continue;   // jetzt sichtbar -> Entwarnung
      Notify(T("watchdog.historyTradeMissing"));
      Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("Ticket %d nach dem Schliessen nicht in der History sichtbar — History-Filter? -> Tagessperre",t));
      GlobalVariableSet(GV_LOCK_UNTIL,(double)NextServerMidnight()); GlobalVariableSet(GV_LOCK_WHY,5); g_gvDirty=true;
   }
   ArrayResize(g_suspTicket,0);
   // Pass 1: seit dem letzten Lauf verschwundene Tickets, die (noch) nicht in der History stehen -> Verdacht
   for(int a=0;a<ArraySize(g_seenTicket);a++)
   {
      int t=g_seenTicket[a]; bool still=false;
      for(int b=0;b<n;b++) if(cur[b]==t){ still=true; break; }
      if(still) continue;
      if(OrderSelect(t,SELECT_BY_TICKET) && OrderCloseTime()!=0) continue;   // sauber in der History
      int m=ArraySize(g_suspTicket); ArrayResize(g_suspTicket,m+1); g_suspTicket[m]=t;
   }
   ArrayResize(g_seenTicket,n);
   for(int c=0;c<n;c++) g_seenTicket[c]=cur[c];
}

// §05-fix (hoch): Entry-Regeln (R5 Cooldown / R13 Tagesziel / R16 Session / R25 Revenge) NACHTRAEGLICH durchsetzen.
//   Bisher lebten sie NUR im DoEntry-Klickpfad -> eine per Terminal/Mobile/Pending-Fill entstandene In-Scope-Position
//   blieb offen (nur R1/R7/R12/Lock wurden revertiert). Jetzt: In-Scope-Pendings im Sperrfenster loeschen und In-Scope-
//   Positionen schliessen, die WAEHREND eines aktiven Sperrfensters eroeffnet wurden (Locks deckt SafeCloseAll separat ab).
void EnforceEntryState()
{
   if(IsTradeContextBusy()) return;
   bool cd = CooldownActive();
   bool th = TargetHit();
   bool blockNew = cd || th || OffSession();   // Zustaende, in denen ein NEUER Entry blockiert wuerde
   datetime cend   = (datetime)GlobalVariableGet(GV_COOLDOWN);
   datetime cstart = (EffCooldownMin()>0) ? cend-(datetime)(EffCooldownMin()*60) : cend;   // Cooldown-Beginn (= Zeit des ausloesenden Verlusts), effektive Dauer
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!InScope(OrderMagicNumber())) continue;             // P1-11: fremde Magics nur bei TOOL_PLUS_MANUAL/ALL_POSITIONS
      int      ty=OrderType();
      datetime ot=OrderOpenTime();
      if(ty!=OP_BUY && ty!=OP_SELL)                          // Pending -> im Sperrfenster gar nicht erst fuellen lassen
      {
         bool pBuy=(ty==OP_BUYLIMIT || ty==OP_BUYSTOP);
         if(blockNew || RevengeBlocked(OrderSymbol(),pBuy)) RequestClose(OrderTicket(),"R5/R13/R16/R25 Pending im Sperrfenster");
         continue;
      }
      bool isBuy=(ty==OP_BUY);
      if(cd && EffCooldownMin()>0 && ot>=cstart)             // waehrend Cooldown eroeffnet (haette R5-Gate blockiert)
      { RequestClose(OrderTicket(),"R5 Cooldown-Entry (nachtraeglich revertiert)"); continue; }
      if(OffSessionAt(ot))                                   // ausserhalb Session / im News-Fenster eroeffnet (R16)
      { RequestClose(OrderTicket(),"R16 Off-Session-Entry (nachtraeglich revertiert)"); continue; }
      if(InpRevengeMin>0 && RevengeBlocked(OrderSymbol(),isBuy))   // Gegen-Trade im aktiven Revenge-Fenster (R25)
      {
         datetime ru=(datetime)GlobalVariableGet(RevUntilKey(OrderSymbol()));
         datetime rs=ru-(datetime)(InpRevengeMin*60);
         if(ot>=rs){ RequestClose(OrderTicket(),"R25 Revenge-Entry (nachtraeglich revertiert)"); continue; }
      }
      // R13 TargetHit: keine verlaessliche Open-Zeit-Referenz fuer laufende Positionen -> nur Pendings (oben) werden geloescht;
      //   eine bereits offene Position laeuft weiter (Vertrag: Ziel blockt NEUE Trades, flatten nicht).
   }
}

// R22 (v0.35): NUR PANEL-TRADES. Alles, was NICHT ueber den BUY/SELL-Knopf des Tools entstanden ist, wird sofort
//   geschlossen — denn nur der Panel-Pfad durchlaeuft die Entry-Gates (R1 Lot-Berechnung, R2/R3/R12/R17-Budgets,
//   Cooldown, Session, Revenge). Ein Handy-Trade umging bisher saemtliche Regeln und wurde bei aktiver Sperre nicht
//   einmal geschlossen (nur 1x/min gewarnt) — das war die letzte grosse Luecke im Detect-and-Revert.
//   BEWUSSTE ABGRENZUNG: nur Magic 0 (= manuell/Handy/Orderfenster). Trades anderer EAs haben eine eigene
//   Magic-Nummer und bleiben unangetastet, damit ein zweiter EA auf dem Konto nicht abgeraeumt wird.
void EnforceManualTrades()
{
   if(!InpCloseManualTrades) return;
   if(InpMagic==0) return;   // FAILSAFE: bei Magic 0 waeren die eigenen Panel-Trades von manuellen nicht unterscheidbar -> R22 wuerde sie abraeumen (Warnung in OnInit)
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

void SafeCloseAll()   // bei Lock: alle In-Scope-Positionen/Pendings in die Close-Queue (Retry/Backoff/Journal)
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
   // P0-1: GESPERRT, aber ausserhalb des Scope offene Positionen -> der Watchdog schliesst sie NICHT -> laut warnen (max 1x/min)
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
// §07-fix: Fehlen Tickdaten (TICKSIZE/TickValue = 0), lieferten die Risiko-Funktionen 0 % — eine womoeglich riesige
//   Position war fuer R1/R12/R17 damit UNSICHTBAR (fail-open), ohne jede Warnung. Jetzt: konservativ mit Risiko/Trade
//   bewerten (zaehlt in den Summen mit, loest aber allein keinen Zwangs-Close aus, da EnforceRisk gegen Limit*Toleranz
//   prueft) + taeglich einmal warnen.
double RiskUnknownPct(string s)
{
   g_tvEstimate=true;
   if(DayKeyOf(g_lastTvWarnDay)!=DayKeyOf(SrvTime()))
   { g_lastTvWarnDay=SrvTime(); PrintFormat("Mamal: WARN keine Tickdaten fuer %s — Risiko wird konservativ mit %.2f%% angesetzt (Symbol im Market Watch?).", s, EffRiskPct()); }
   return EffRiskPct();
}
double RiskPctOf(string s,double lots,double open,double sl)
{
   double eq=AccountEquity(); if(eq<=0 || sl==0.0) return 0;
   double ts=MarketInfo(s,MODE_TICKSIZE), tv=TickVal(s);
   if(ts<=0 || tv<=0) return RiskUnknownPct(s);
   return (MathAbs(open-sl)/ts)*tv*lots/eq*100.0;
}
// §06-fix (mittel): Positionen OHNE SL trugen 0 % zu Heat/Idee/R17 bei. Damit liess sich jedes Portfolio-Gate umgehen:
//   SL kurz entfernen -> neuer Trade passiert R12/R2 -> SL binnen der R7-Grace zurueck. Fuer die ENTRY-Gates werden nackte
//   Positionen jetzt konservativ mit Risiko/Trade bewertet (conservative=true). Die MONITOR-Pfade (EnforceHeat/EnforceIdea)
//   rechnen bewusst weiter SL-basiert, damit eine nackte Position nicht faelschlich eine ANDERE Position schliessen laesst
//   (dafuer ist R7 zustaendig, das die nackte Position selbst schliesst).
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

int LotDigits(double step){ if(step>=1.0) return 0; if(step>=0.1) return 1; if(step>=0.01) return 2; if(step>=0.001) return 3; return 4; }   // §07-fix: Nachkommastellen aus dem Broker-Lotstep statt fix 2
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
   // §07-fix: NormalizeDouble(lot,2) rundete bei LOTSTEP<0.01 (z.B. 0.001) wieder AUF — aus 0.014 wurde 0.01->0.01,
   //   aus 0.015 aber 0.02 = bis zu +100 % Risiko ueber dem Limit (und sofortiger Self-Close durch R1). Jetzt wird auf
   //   die Nachkommastellen des BROKER-Lotstep normalisiert, nie ueber den abgerundeten Wert hinaus.
   lot=MathFloor(lot/step + 0.0000001)*step; lot=NormalizeDouble(lot,LotDigits(step));   // +eps (v0.40): Binaer-FP verlor sonst gelegentlich einen Lot-Step
   if(mx>0 && lot>mx) lot=mx;   // B16: nur klemmen, wenn Broker einen gueltigen MaxLot liefert (sonst wuerde mx=0 das Lot auf 0 setzen)
   if(lot>0) riskPctOut=((dist/ts)*tv*lot)/eq*100.0;
   return lot;
}

void DoEntry(bool isBuy)
{
   string dir=isBuy?"BUY":"SELL";
   if(!IsTradeAllowed()){ Notify(T("block.autoTradingOff")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"AutoTrading aus"); return; }
   if(IsLocked()){ Notify(T("block.locked")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"gesperrt"); return; }
   if(BaseWarn()){ Notify(T("block.baseUnsure")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"P1-2 Basis unsicher"); return; }
   // v0.49: Wochen-Risiko muss BEWUSST festgelegt sein, bevor gehandelt wird. Jede neue Woche
   //   erzwingt die Entscheidung erneut — das ist der Kern der Wochendisziplin, kein technischer Zwang.
   if(WeekRiskPending())
   { Notify(T("block.weekRiskMissing"));
     Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"Wochen-Risiko nicht festgelegt"); return; }
   if(MaxLossWarnActive()){ Notify(TF("block.maxLossWarn",DoubleToString(TotalDDpct(),2),DoubleToString(EffMaxLoss(),1))); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R4b Warn-Gate"); return; }
   if(TargetHit()){ Notify(T("block.targetHit")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R13 Tagesziel"); return; }
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
   // §07-fix (R11-Luecken): diese Ablehnpfade schrieben bisher KEIN Journal — im "audit-tauglichen" Journal fehlten damit
   //   genau die Fehlversuche, die fuer die Disziplin-Statistik interessant sind.
   if(slp<=0){ Notify(T("block.noSlLine")); Journal("BLOCKED",Symbol(),dir,0,0,0,0,0,"R7 keine SL-Linie gesetzt"); return; }
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
     lot=NormalizeDouble(MathFloor(InpMaxLot/stp + 0.0000001)*stp,LotDigits(stp));   // §07-fix: nach dem Klemmen wieder auf den Lot-Step ausrichten (sonst OrderSend err 131 "invalid volume"); +eps v0.40 (FP)
     rp=RiskPctOf(Symbol(),lot,entry,slp); }
   if(lot<mn || lot<=0){ Notify(TF("block.lotBelowMin",DoubleToString(mn,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R15 Lot unter Broker-Minimum"); return; }
   double r3rp = RiskPctOfBase(Symbol(), lot, entry, slp, DayRiskBase());   // R3 nutzt dieselbe Tagesbasis wie die Rekonstruktion (nicht Live-Equity)

   double ideaR=IdeaOpenRiskPct(Symbol(),isBuy,true); double ic=EffIdeaCap();   // §06-fix: nackte Positionen konservativ mitzaehlen
   if(ideaR + rp > ic + 0.01)
   { Notify(TF("block.ideaCap",Symbol(),DoubleToString(ideaR,2),DoubleToString(ic,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R2 Idee-Cap"); return; }

   ReconcileDayRisk();   // R3: vor dem Gate Tagesbudget abgleichen (max persisted/rekonstruiert)
   double dayR=GlobalVariableGet(GV_DAY_RISK); double db=EffDay();
   if(dayR + r3rp > db + 0.01)
   { Notify(TF("block.dayBudget",DoubleToString(dayR,2),DoubleToString(r3rp,2),DoubleToString(db,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,r3rp,"R3 Tagesbudget"); return; }

   double heat=TotalOpenRiskPct(true); double hc=EffHeat();   // §06-fix: nackte Positionen konservativ mitzaehlen (Gate nicht per SL-Entfernen umgehbar)
   if(heat + rp > hc + 0.01)
   { Notify(TF("block.heat",DoubleToString(heat,2),DoubleToString(rp,2),DoubleToString(hc,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R12 Heat"); return; }

   if(EffUseCorrCap())   // §06-fix: R17 tighten-only (einmal an -> intraday nicht abschaltbar)
   {
      double cc = EffCorrCap();
      double mx = MaxCurrencyExposurePct(Symbol(), isBuy, rp, true);
      if(mx > cc + 0.01)
      { Notify(TF("block.correlation",DoubleToString(mx,2),DoubleToString(cc,2))); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"R17 Korrelation"); return; }
   }

   int    dig=(int)MarketInfo(Symbol(),MODE_DIGITS);
   // v0.46: gezogene TP-Linie hat Vorrang — aber nur, wenn sie auf der richtigen Seite liegt.
   //   Sonst (und wenn InpTpLine=false) bleibt der Auto-TP aus InpRR. R8-Mindest-CRV prueft weiter unten.
   double tp =isBuy ? entry+dist*InpRR : entry-dist*InpRR;
   double tpl=TPLinePrice();
   if(tpl>0 && ((isBuy && tpl>entry) || (!isBuy && tpl<entry))) tp=tpl;
   double slN=NormalizeDouble(slp,dig), tpN=NormalizeDouble(tp,dig), pxN=NormalizeDouble(entry,dig);

   // §07-fix: vor dem Senden Kontext pruefen und Preis auffrischen — zwischen der Lot-/Gate-Rechnung (mehrere
   //   Order-Scans) und dem OrderSend konnte der Preis veraltet sein, und ein laufender Trade-Kontext fuehrte
   //   unter Wine zum Fehlschlag. Ausserdem war ein fehlgeschlagener OrderSend bisher NICHT im Journal (R11-Luecke).
   if(IsTradeContextBusy()){ Notify(T("misc.tradeContextBusy")); Journal("BLOCKED",Symbol(),dir,lot,entry,slp,0,rp,"Handelskontext belegt"); return; }
   RefreshRates();
   pxN = NormalizeDouble(isBuy ? MarketInfo(Symbol(),MODE_ASK) : MarketInfo(Symbol(),MODE_BID), dig);
   int ticket=OrderSend(Symbol(), isBuy?OP_BUY:OP_SELL, lot, pxN, InpSlippage, slN, tpN, "Mamal", InpMagic, 0, isBuy?clrDodgerBlue:clrTomato);
   if(ticket<0){ int oerr=GetLastError(); Notify(TF("misc.orderSendFailed",IntegerToString(oerr),DoubleToString(lot,2))); Journal("BLOCKED",Symbol(),dir,lot,pxN,slN,tpN,rp,StringFormat("OrderSend fehlgeschlagen err=%d",oerr)); return; }
   GlobalVariableSet(GV_DAY_RISK, dayR+r3rp);   // R3-Budget auf Tagesbasis (gleiche Einheit wie Rekonstruktion)
   GlobalVariableSet(GV_LAST_ENTRY,(double)SrvTime());
   GlobalVariableSet(OpnKey(ticket),(double)SrvTime());   // v0.40: Panel-Ticket registrieren (Close-Erkennung magic-/tab-unabhaengig)
   GlobalVariablesFlush();
   Journal("OPEN",Symbol(),dir,lot,pxN,slN,tpN,rp,"in-plan "+CandleThirdTag(TimeCurrent()),ticket);   // v0.52: in welchem Kerzendrittel ausgefuehrt
   Shot("open",ticket);   // v0.47: Einstiegs-Bild mit Ticket-Bezug
   PrintFormat("Mamal: %s %.2f Lot SL %s TP %s (Risiko %.2f%%, Heat %.2f%%, Tag %.2f%%)", dir, lot, DoubleToString(slN,dig), DoubleToString(tpN,dig), rp, heat+rp, dayR+r3rp);
   g_panelSig="";
}

// v0.21: SL-Linie erst nach InpSlClicksToMove Klicks in dieselbe Zone setzen (verhindert versehentliches Setzen beim ersten Klick).
void SlZoneClick(double price)
{
   int  need = (InpSlClicksToMove<1 ? 1 : InpSlClicksToMove);
   uint now  = GetTickCount();
   double tol = price*0.0015; double tpip=InpSlZonePips*Pip(); if(tpip>tol) tol=tpip; if(tol<=0) tol=Pip();   // ~0,15% des Preises oder Pip-Untergrenze
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
   double riskEur = rp/100.0*AccountEquity();   // rp = %% der Equity -> €-Risiko per Definition
   // Format: "<DIR> <detail>" — DrawPanel splittet am ersten Space fuer die farbige Richtung
   return StringFormat("%s %.2f Lot  %.0f %s  %s%%  %s%.0f", isBuy?"BUY":"SELL", lot, dist/Pip(), UnitStr(), Dec2(rp), CurSym(), riskEur);
}

//--- Panel (v0.24 Redesign: Fintech-Terminal-Look) ------------------
double Frac(double v,double lim){ if(lim<=0) return 0.0; double f=v/lim; if(f<0)f=0; if(f>1)f=1; return f; }
color  BarCol(double f){ if(f<0.5) return C'38,194,129'; if(f<0.8) return C'244,183,64'; return C'240,73,90'; }   // gruen / amber / rot

// Tausender-Gruppierung (deutsch: Punkt) fuer Equity-Anzeige
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
// v0.25: deutsches Dezimal-Komma (Anzeige) — konsistent zur Punkt-Tausendertrennung der Equity
// v0.53: Panel-Texte DE/EN — automatisch aus der Uebersetzungstabelle erzeugt.
//   T(key) liefert den Text in der eingestellten Sprache. Ein unbekannter Schluessel gibt
//   den Schluessel selbst zurueck: faellt im Panel sofort auf, statt leer zu bleiben.
// v0.54: Uebersetzten Text mit Werten fuellen. Die Tabelle nutzt {0}/{1}/{2} statt %s/%d,
//   damit die Reihenfolge der Werte je Sprache frei bleibt (im Englischen steht sie oft anders).
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
   if(k=="test.resetReasonNoDemo") return en?"not a demo account":"kein Demo-Konto";
   if(k=="test.resetReasonNoTestLock") return en?"no test lock active":"keine Test-Sperre aktiv";
   if(k=="test.locksReset") return en?"TEST: test locks reset (demo). Hard-Lock stays.":"TEST: Test-Sperren zurueckgesetzt (Demo). Hard-Lock bleibt.";
   if(k=="test.cooldown") return en?"TEST: cooldown set (R5).":"TEST: Cooldown gesetzt (R5).";
   if(k=="test.dayLock") return en?"TEST: daily lock set (R4) -> SafeCloseAll expected.":"TEST: Tagessperre gesetzt (R4) -> SafeCloseAll erwartet.";
   if(k=="test.maxLock") return en?"TEST: MAX-LOSS lock set (R4b) -> SafeCloseAll expected. (Reset does NOT clear the hard lock — delete it via F3 on demo.)":"TEST: MAX-LOSS-Sperre gesetzt (R4b) -> SafeCloseAll erwartet. (Reset entsperrt den Hard-Lock NICHT — auf Demo per F3 loeschen.)";
   if(k=="test.revenge") return en?"TEST: revenge (BUY loss) set (R25) -> counter-SELL blocked, survives restart.":"TEST: Revenge (BUY-Verlust) gesetzt (R25) -> Gegen-SELL gesperrt, ueberlebt Restart.";
   return k;
}
string Dec2(double v){ string s=StringFormat("%.2f",v); StringReplace(s,".",","); return s; }
// v0.25: Panel-Text hart begrenzen (kein Ueberlauf auf den Chart); Volltext bleibt im Log
string Clip(string s,int mx){ return (StringLen(s)<=mx) ? s : (StringSubstr(s,0,mx-1)+"…"); }
// v0.37: einfacher Wort-Umbruch fuer die Meldungsbox — MT4-OBJ_LABEL bricht nicht selbst um, also Text in maxLines Zeilen
//   à perLine Zeichen aufteilen. Passt nicht alles rein, bekommt die letzte Zeile ein "…". Ergebnis in out[0..maxLines-1].
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
      if(line>=maxLines-1)                                                       // letzte Zeile: Rest anhaengen + Clip setzt das "…"
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

// v0.37: Panel-Geometrie skalieren. Bei Windows-Skalierung >100% rendert MT4 die SCHRIFT groesser, laesst die Pixel-
//   Koordinaten aber unskaliert -> Ueberlappung. Loesung: alle Positionen/Groessen (NICHT die Fontgroesse, die MT4 selbst
//   skaliert) mit demselben Faktor multiplizieren. Zentral in den 5 Zeichen-Helfern angewandt.
double PScale()
{
   double s=InpPanelScale;
   if(s<=0)   // v0.37: AUTO — aus Bildschirm-DPI ableiten (96 dpi = 100%, 144 = 150%)
   {
      int dpi=(int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
      s = (dpi>0) ? (dpi/96.0) : 1.0;   // DPI nicht verfuegbar -> neutral
      if(s<1.0) s=1.0;                  // AUTO nie unter 100% (kleine DPI-Werte sollen nichts schrumpfen)
   }
   // v0.48-fix: ein MANUELL gesetzter Wert darf ausdruecklich auch verkleinern (0.7 = 70%).
   //   Vorher klemmte die 1.0-Untergrenze jeden Wunsch nach einem kleineren Panel weg.
   if(s<0.5) s=0.5; if(s>3.0) s=3.0;
   // v0.46: Auto-Fit — passt das Panel herunter, wenn es sonst hoeher als das Chart-Fenster waere.
   //   Verhindert abgeschnittene Buttons auf kleinen Charts / geteiltem Bildschirm.
   if(InpPanelAutoFit)
   {
      int ph=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      if(ph>120)
      {
         double need=(PanelH()+28)*s;                     // Panel + Rand oben/unten (PanelH rechnet unskaliert)
         if(need>ph) s=s*((double)ph/need);
         if(s<0.6) s=0.6;                                  // nicht unlesbar klein werden
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
// Rechteck mit separater Rahmenfarbe (fuer Karten-Rand / Chips)
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
// rechtsbuendiges Label (Anker rechts) fuer Zahlen/Werte
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
// v0.49: Eingabefeld fuer das Wochen-Risiko. Der Text wird NUR dann neu geschrieben, wenn sich der
//   gueltige Wert geaendert hat — sonst wuerde DrawPanel (2x/Sekunde) dem Nutzer beim Tippen
//   staendig die Eingabe unter den Fingern wegloeschen.
// v0.52: Kerzen-Drittel bestimmen — in welchem Abschnitt der laufenden Kerze wurde ausgefuehrt?
//   0 = erstes Drittel (frueh, gruen), 1 = zweites (orange), 2 = letztes (spaet/hinterherlaufend, rot).
//   Aussagekraft: Einstiege im letzten Drittel sind haeufig Reaktionen auf eine schon gelaufene Bewegung.
int CandleThird(datetime t)
{
   int per=PeriodSeconds(); if(per<=0) return 0;
   int el=(int)(t%per); if(el<0) el=0;
   int th=(el*3)/per; if(th>2) th=2;
   return th;
}
string CandleThirdTag(datetime t){ return StringFormat("K%d/3",CandleThird(t)+1); }   // "K1/3".."K3/3" (maschinenlesbar fuers Cockpit)

// v0.52: Countdown direkt neben der laufenden Kerze (wie ein Chart-Indikator), zusaetzlich zum Panel.
//   Anker: naechster Kerzen-Slot auf Hoehe des aktuellen Preises -> steht rechts neben der Kerze mit.
void DrawCandleClock()
{
   string n=PFX+"cclock";
   if(!InpCandleTimeOnChart || !InpShowCandleTime)
   { if(ObjectFind(0,n)>=0) ObjectDelete(0,n); return; }
   int rest=(int)(Time[0]+PeriodSeconds()-TimeCurrent()); if(rest<0) rest=0;
   int per=PeriodSeconds(); if(per<=0) per=60;
   // Farbe nach VERSTRICHENEM Drittel — gleiche Logik wie die Trade-Protokollierung
   int th=CandleThird(TimeCurrent());
   color c=(th==0)?C'61,220,146':((th==1)?C'244,183,64':C'240,73,90');
   string txt=StringFormat("%02d:%02d",rest/60,rest%60);
   double price=(MarketInfo(Symbol(),MODE_BID)>0)?MarketInfo(Symbol(),MODE_BID):Close[0];
   datetime anchor=Time[0]+per;                       // ein Slot rechts der laufenden Kerze
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
   // v0.50-fix: Altlasten der [-]/[+]-Variante entfernen. Ohne das blieben sie als "Geister"-Objekte
   //   auf dem Chart liegen (die Zahl lag dann doppelt ueber dem Eingabefeld).
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
   // v0.62: Steht die Wochenbestaetigung aus und hat der Trader in der Vorwoche schon eine Aenderung
   //   vorgemerkt, dann ist DAS sein zuletzt gefasster Vorsatz — er gehoert ins Feld, nicht der alte Wert.
   //   Bestaetigt wird trotzdem bewusst per SETZEN; ohne Bestaetigung bleibt die Vormerkung wirkungslos.
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
   { if(ObjectGetInteger(0,SLLINE,OBJPROP_COLOR)!=clrWhite) ObjectSetInteger(0,SLLINE,OBJPROP_COLOR,clrWhite); return; }   // v0.29: bestehende (rote) SL-Linie automatisch auf weiss umfaerben
   double bid=MarketInfo(Symbol(),MODE_BID); if(bid<=0) bid=Close[0];
   double p=bid - InpDefaultSLpips*Pip();
   ObjectCreate(0,SLLINE,OBJ_HLINE,0,0,p);
   ObjectSetDouble (0,SLLINE,OBJPROP_PRICE,0,p);
   ObjectSetInteger(0,SLLINE,OBJPROP_COLOR,clrWhite);   // v0.29: SL-Linie WEISS (Stop-Loss ist etwas Gutes, kein Gefahr-Rot)
   ObjectSetInteger(0,SLLINE,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,SLLINE,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,SLLINE,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,SLLINE,OBJPROP_SELECTED,true);
   ObjectSetInteger(0,SLLINE,OBJPROP_HIDDEN,false);
   ObjectSetString (0,SLLINE,OBJPROP_TEXT,"Mamal SL");
}
// v0.46: TP-Linie nur wenn eingeschaltet. Grün = Ziel; wird sie gezogen, hat sie Vorrang vor InpRR.
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
// #14 Rule-Test-Harness: manipuliert NUR Zustand/Datei (oeffnet KEINE Trades) -> Regelverhalten testen.
// Hart gegated: nur wenn InpTestMode && !InpFundedMode. Trade-basierte Szenarien (NoSL/BigLot/BadCRV)
// reproduziert der User per Hand auf Demo (BUY/SELL klicken).
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
   else if(which=="reset")   // §05-fix (hoch): KEIN Universal-Unlock mehr. Nur selbst gesetzte TEST-Sperren auf einem Demo-Konto; Hard-Lock (R4b permanent) bleibt IMMER.
   {
      bool demo        = IsDemo();
      bool testInduced = (GlobalVariableGet(GV_TEST_SET)>0.5);
      if(!demo || !testInduced)   // echtes Konto ODER Sperre stammt aus echtem Regel-Event -> ablehnen
      {
         Notify(TF("test.resetRejected",!demo?"kein Demo-Konto":"keine Test-Sperre aktiv"));
         Journal("TAMPER","-","-",0,0,0,0,0,StringFormat("Reset ABGELEHNT (demo=%d testInduced=%d) — echte Sperren bleiben",demo?1:0,testInduced?1:0));
         g_panelSig=""; return;
      }
      GlobalVariableSet(GV_LOCK_UNTIL,0); ClearLockWhy();
      // Hard-Lock (GV_HARD_LOCK) wird bewusst NICHT geloescht - R4b ist permanent.
      // v0.64 (verworfen): eine "nur Test-Sperren"-Ausnahme war nicht sicher zu bauen. Der Test-Knopf
      //   konnte eine bereits ECHT ausgeloeste Sperre nachtraeglich als Test umetikettieren, und ein
      //   echter Durchbruch WAEHREND einer Test-Sperre wurde gar nicht erst registriert. Vor allem aber
      //   traegt die Demo-Bedingung nicht: Prop-Firm-Challenge-Konten laufen in MT4 ALS Demo-Konten -
      //   genau dort waere das Aufheben am teuersten. Bleibt permanent; auf Demo per F3 loeschen.
      GlobalVariableSet(GV_COOLDOWN,0);   GlobalVariableSet(GV_TARGET_HIT,0);
      if(GlobalVariableCheck(RevUntilKey(Symbol()))) GlobalVariableDel(RevUntilKey(Symbol()));
      if(GlobalVariableCheck(RevDirKey(Symbol())))   GlobalVariableDel(RevDirKey(Symbol()));
      GlobalVariableSet(GV_TEST_SET,0);
      GlobalVariablesFlush(); g_lockSig="";
      // v0.63: Das hier ist die EINZIGE legitime Entsperrung. Sie muss den Spiegel direkt schreiben —
      //   ginge sie durch den neuen Abgleich, holte der die eben geloeschte Test-Sperre sofort zurueck.
      //   Der Hard-Lock bleibt trotzdem, er wurde oben bewusst nicht angefasst.
      g_lsGuard=true; WriteLockstate(); g_lsGuard=false;
      Notify(T("test.locksReset"));
      Journal("TAMPER","-","-",0,0,0,0,0,"TEST Reset (nur Test-Sperren, Hard-Lock unberuehrt)");
   }
   g_panelSig="";
}
// v0.25: Panel-Kartengeometrie an EINER Stelle (CreateControls + Klick-Guard nutzen dieselbe)
int RiskRowOff(){ return InpRiskChooser ? 46 : 0; }   // v0.36: Risiko-Zeile schiebt alles darunter nach unten (v0.48: 32->46 fuer die Erklaer-Unterzeile)
int PanelH(){ int h=372; h+=RiskRowOff(); if(InpBreakEvenBtn) h+=26; if(InpTestMode && !InpFundedMode) h+=72; return h; }   // v0.26: +Cockpit, v0.36: +Risiko-Waehler, v0.37: +16 Meldungsbox, v0.40: +52 Close-Buttons, v0.46: +26 Risk-Free
void CreateControls()
{
   int  cardH = PanelH();
   int  ro    = RiskRowOff();
   RectB(PFX+"card",12,16,300,cardH,C'14,18,25',C'33,42,56');   // Karte mit feinem Rand
   if(InpRiskChooser)   // v0.36: Risiko-Waehler [-] / Wert / [+]
   {
      // v0.49: Eingabefeld statt [-]/[+] — der Wochenwert wird bewusst getippt und bestaetigt.
      // v0.50-fix: Feld 170..228, Knopf 234..298 -> 6px Luft dazwischen, Knopf breit genug fuer "SETZEN".
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
   DrawCandleClock();   // v0.52: Countdown neben der Kerze   // v0.46: TP-Linie mitfuehren (nur wenn InpTpLine=true)
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
   DrawCandleClock();   // v0.52: Countdown neben der Kerze   // v0.46: TP-Linie mitfuehren (nur wenn InpTpLine=true)
   if(g_fgTries>0){ g_fgTries--; if(ChartGetInteger(0,CHART_FOREGROUND)!=0) ChartSetInteger(0,CHART_FOREGROUND,false); }   // v0.28: nur begrenzt oft (kein ChartSetInteger-Spam je Cycle); haelt es nicht -> User: F8 „Chart im Vordergrund" aus
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
   else if(BaseWarn()) { st=T("status.baseWarn");    stcol=C'244,183,64'; }   // §07-fix: blockt jeden Entry -> darf nicht als "AKTIV" erscheinen
   else if(WeekRiskPending())
                       { st=T("status.setWeekRisk");  stcol=C'61,123,255'; }   // v0.49: Wochenentscheidung steht aus -> blockt Entries
   else if(maxw)       { st=T("status.maxLossWarn");  stcol=C'244,183,64'; }
   else if(cool)       { st=T("status.cooldown");          stcol=C'244,183,64'; }
   else if(tgt)        { st=T("status.targetHit");     stcol=C'61,220,146'; }
   else if(off)        { st=T("status.offSession");    stcol=C'160,170,186'; }
   else                { st=T("status.active");             stcol=C'61,220,146'; }
   // Pill-Tint aus dem Zustand ableiten (gruen / rot / amber / neutral)
   if(stcol==C'61,220,146')      { pillBg=C'15,36,25'; pillBd=C'28,77,52'; }
   else if(stcol==C'240,73,90')  { pillBg=C'40,18,22'; pillBd=C'90,34,40'; }
   else if(stcol==C'244,183,64') { pillBg=C'40,31,15'; pillBd=C'88,64,26'; }
   else                          { pillBg=C'22,28,38'; pillBd=C'40,50,64'; }

   bool noTrade=(IsLocked()||disabled||cool||tgt||off||maxw||BaseWarn()
                 ||(WeekRiskPending()));   // §07-fix: BaseWarn graut die Buttons aus; v0.49: ausstehende Wochenwahl ebenfalls
   color bbuy = noTrade?C'46,53,66':C'21,156,100';
   color bsell= noTrade?C'46,53,66':C'216,63,80';
   color bacc = noTrade?C'70,80,96':C'61,220,146';
   color sacc = noTrade?C'70,80,96':C'255,107,120';
   color HAIR = C'30,38,52';   // v0.25: EIN Hairline-Token fuer alle internen Trennlinien
   color CAP  = C'146,158,178';// v0.25: EIN Caption-Token (Groesse 8)

   string prev=PreviewText();
   bool   flashOn=(g_flash!="" && (GetTickCount()-g_flashMs)<g_flashHold);
   string dv=StringFormat("%.2f",dd), gv=StringFormat("%.2f",tdd);
   string eqs=CurSym()+GroupInt(eq);
   string cHeat=Dec2(heat)+"/"+Dec2(EffHeat());
   bool   budFull=(EffDay()>0 && dayR >= EffDay()-0.01);
   string cBud =TF("tile.limit.value",Dec2(MathMax(0,EffDay()-dayR)));                          // v0.25: verbleibendes Budget statt verbrauchtem
   string cStp =StringFormat("%d/%d",consec,EffLockAfter());   // §06-fix: effektive Schwelle anzeigen (nicht den ggf. gelockerten Roh-Input)
   color  stpCol = (consec>=EffLockAfter())?C'240,73,90':((consec>=EffLockAfter()-1 && consec>0)?C'244,183,64':C'205,214,228');   // amber 1 vor Sperre, rot bei Sperre

   // Zwei-Ton: Richtung (BUY/SELL) faerben, Rest mono — nur im normalen Handelszustand
   string pdir="", pdet=prev;
   if(!flashOn && g_armed==0 && !noTrade)
   {
      if(StringSubstr(prev,0,4)=="BUY ")      { pdir="BUY";  pdet=StringSubstr(prev,4); }
      else if(StringSubstr(prev,0,5)=="SELL "){ pdir="SELL"; pdet=StringSubstr(prev,5); }
   }

   // v0.36: Risiko-Waehler-Anzeige (wirksamer Wert; bei vorgemerkter Erhoehung "→ X")
   // v0.48: Risiko-Zeile lesbar machen — der Wert bleibt kurz (passt zwischen die Knoepfe),
   //   die Erklaerung (Euro-Betrag + Wochenbindung) steht in einer eigenen Unterzeile.
   string rkv="", rkSub="";
   if(InpRiskChooser)
   {
      rkv=StringFormat("%s %%",Dec2(EffRiskPct()));
      double rEur=AccountEquity()*EffRiskPct()/100.0;
      string eurTxt=CurSym()+GroupInt(rEur);   // v0.55: "je Trade"/"per trade" steckt in risk.sub.* (uebersetzt)
      // v0.62: "unset" nur zeigen, wenn wirklich eine Bestaetigung AUSSTEHT. Ohne die Pflicht
      //   (InpRequireWeeklyRisk=false) gilt der zuletzt gewaehlte Wert weiter — dann waere
      //   "Wochenwert eintippen ..." eine Aufforderung ins Leere.
      bool chosen=(GlobalVariableCheck(GV_WEEK_RISK) && GlobalVariableGet(GV_WEEK_RISK)>0
                   && !WeekRiskPending());
      if(WeekRiskPending())     rkSub=T("risk.sub.unset");
      else if(PendingWeekRisk()>0) rkSub=TF("risk.sub.pending",eurTxt,Dec2(PendingWeekRisk()));
      else if(chosen)           rkSub=TF("risk.sub.fixed",eurTxt);
      else                      rkSub=T("risk.sub.unset");
   }
   // v0.65b: nach Sperrart aufloesen. Ein gespeicherter Tages-Grund darf nie unter einer Hard- oder
   //   Wochensperre erscheinen — sonst stuende dort mit voller Bestimmtheit etwas Falsches.
   string lockWhy = IsHardLocked() ? T("why.maxloss")
                  : (IsWeekLocked() ? T("why.week")
                  : (IsDayLocked()  ? LockWhyText() : ""));
   int ro=RiskRowOff();

   // v0.46: Spread + Kerzen-Restsekunde in die Signatur — sonst wuerde der Cache das Panel einfrieren
   //   und der Countdown stuende still (DrawPanel zeichnet nur bei geaenderter Signatur).
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
   Lbl  (PFX+"br2",90,25,"·TRADING",C'107,118,136',11,"Arial");     // v0.25: Luecke geschlossen (99->90; nach F7 ggf. 88-92 justieren)
   string cxs=Symbol()+" · "+PeriodStr(); int cw=14+StringLen(cxs)*5; if(cw>150) cw=150;   // v0.25: Chip dynamisch, rechtsbuendig
   RectB(PFX+"chip",298-cw,25,cw,18,C'20,27,38',C'33,42,56');
   LblR (PFX+"chiptx",293,28,cxs,CAP,8,"Tahoma");
   // v0.46: Spread live + Restzeit der laufenden Kerze (gruen -> amber -> rot, je naeher der Schluss)
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
   int pw=24+StringLen(st)*8+12; if(pw>184) pw=184;   // v0.25: fette Grossbuchstaben (8px/Zeichen) + Klemme, kein Ueberlauf
   RectB(PFX+"pill",26,62,pw,22,pillBg,pillBd);
   Rect (PFX+"pdot",36,70,7,7,stcol);
   Lbl  (PFX+"ptx",50,66,st,stcol,10,"Arial Bold");
   // v0.65: WARUM gesperrt. Ohne das steht dort nur "TAG GESPERRT" und der Trader raet — im Zweifel rechnet
   //   er seinen Tagesverlust nach, findet 0,28 % von 2,00 % und haelt das Tool fuer kaputt, obwohl in
   //   Wahrheit die Verlustserie gesperrt hat.
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

   // v0.36: Risiko-Waehler-Zeile (Buttons kommen aus CreateControls; hier nur Label + Wert)
   if(InpRiskChooser)
   {
      // v0.50-fix: KEIN separates Wert-Label mehr — den Wert zeigt das Eingabefeld selbst.
      //   Vorher lag die alte Beschriftung genau ueber dem Feld (doppelte Zahl im Bild).
      Lbl (PFX+"rkl", 26,200,T("risk.label"),CAP,8,"Tahoma");
      Lbl (PFX+"rksub",26,216,rkSub,(PendingWeekRisk()>0?C'244,183,64':C'126,138,158'),8,"Tahoma");
      Rect(PFX+"rkdiv",26,194+ro,272,1,HAIR);
   }

   // "Nächster Trade"/Hinweis-Box (v0.37: hoch genug fuer bis zu 3 Zeilen Volltext statt Abschneiden)
   bool   infoFlash = flashOn && g_flashInfo;   // v0.37: neutraler Hinweis (z.B. Cockpit) statt rotem "NICHT MOEGLICH"
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
   else           // Meldung / Vorschau umgebrochen ueber bis zu 3 Zeilen
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
