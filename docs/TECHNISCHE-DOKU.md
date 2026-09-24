# Mamal-Trading — Technische Dokumentation (Archiv)

Stand-Zeile (Kopf des Dokuments)

Stand: **v0.61 (EA, `EA_VER`) / v0.62 (Cockpit-Server)** — kompiliert 0 Errors / 0 Warnings. Neu seit dem letzten Doku-Stand: Mehrsprachigkeit (Panel DE/EN über `InpLang`, Dashboard DE/EN/FA — Abschnitt 8b) · Verhaltens-Tracking `TrackSLTP`, Screenshots je Aktion und Trade-Akte im Cockpit (Abschnitt 9b) · Kerzendrittel-Erfassung (Abschnitt 9c) · Panel-Skalierung mit Auto-Fit (Abschnitt 8a) · „RISK FREE" (SL auf Break-Even, `PanelBreakEven`) · Wochen-Risiko als Pflicht-Eingabe (`InpRequireWeeklyRisk`) · Multi-Konto-Trennung im Server. Behobene Kernfehler in der Historie: Endlosrekursion der Übersetzungstabelle (Abschnitt 8b), Dedup-Karenz der `RGP_`-Marker (Abschnitt 7a), Master-Deadlock (Abschnitt 3a). Regel-Konfig unverändert: R3-Tagesbudget 400 €, R8/R14/R19/R25 AUS. · MetaTrader 4 (MQL4) · Demo · **Multi-Prop-Firm** (FTMO = Default-Profil, Konto-Beispiel 20.000 €)



---

## 1. Zweck & Grundprinzip
Ein Risiko-/Disziplin-Tool als MT4-Expert-Advisor. Es findet **keine** Strategie, sondern **erzwingt** das Risiko- und Ausführungsverhalten: automatische Positionsgrößen, harte Verlust-Sperren, Konzentrations- und Korrelations-Deckel, Cooldowns, Journal. Bedienung über ein On-Chart-Panel mit Risk-basiertem One-Click-Entry.

**Architektur-Kernentscheidung:** Der EA läuft *innerhalb* von MetaTrader (nicht als externe App), weil nur Code im Terminal Order-Operationen ausführen/rückgängig machen kann. Eine externe App könnte einen manuellen Klick nicht stoppen. Echte Unwiderruflichkeit gibt es nur server-seitig (Prop-Firma) bzw. auf einem gesperrten VPS.

---

## 2. Projektstruktur
```
~/Desktop/TradingGuard/
  ea/mt4/MamalTrading.mq4     # der aktive EA (v0.35)
  ea/mt5/  (MT5-Spiegel noch offen)
  RULES.md                   # Regel-Vertrag (Parameter)
  docs/ARCHITECTURE.md       # Architektur-Entscheidung
  docs/REGELN.md             # Regel-Beschreibung
  docs/REGELN-TABELLE.md     # Spickzettel
  docs/TECHNISCHE-DOKU.md    # dieses Dokument
```
**Installations-Pfad (Mac/Wine):**
`~/Library/Application Support/net.metaquotes.wine.metatrader4/drive_c/Program Files (x86)/MetaTrader 4/MQL4/Experts/MamalTrading.mq4`
**Logs:** Terminal `…/MetaTrader 4/logs/JJJJMMTT.log` · Expert `…/MQL4/Logs/JJJJMMTT.log` · Journal-CSV `…/MQL4/Files/MamalTrading_Journal.csv`

---

## 3. Event-Modell & Ablauf
- `OnInit()` — Startbalance ermitteln (Input → persistiert → Kontostand), Tages-/Wochen-Init, `ChartSetInteger(CHART_FOREGROUND,false)` (Panel über die Kerzen), Controls erzeugen, `EventSetTimer(1)`. **v0.35:** zusätzlich Zählung vorgefundener Magic-0-Orders → Hinweis + `INFO`-Journal für **R22** (schließt selbst noch nichts, siehe Abschnitt 7).
- `OnTick()` — gedrosselt (`InpMinActionMs`=500 ms) → ruft `Cycle()`.
- `OnTimer()` (1 s) → `Cycle()`. **Enforcement läuft aus BEIDEN** (tickunabhängig); Close-Operationen per `InpCloseThrottleMs` (300 ms) + `IsTradeContextBusy` gedrosselt.
- `OnChartEvent()` — Buttons (BUY/SELL → `GateClick`), Ziehen der SL-Linie (Vorschau), Klick in den Chart (SL-Linie setzen).
- `OnDeinit()` — Timer killen, **`PROTECT_OFF` ins Journal** (EA gestoppt = Watchdog inaktiv), Panel-Objekte löschen.

**`Cycle()` (Herzstück), Reihenfolge:**
1. Tageswechsel prüfen (`RollNewDay`).
2. Equity, Tagesstart, Tages-/Gesamt-Drawdown berechnen.
3. **R18** Wochenwechsel + Wochenlimit.
4. **R13** Tages-Hoch, Tagesziel, Giveback.
5. Tamper-Check (AutoTrading aus?).
6. **R4b** Max-Loss, **R4** Tagesverlust setzen.
7. `ResolveHistory()` (**R5/R6/R19/R25** — history-basiert, idempotent).
8. Close-gedrosselt (`InpCloseThrottleMs`): **Detection** — zuerst **R22** `EnforceManualTrades()` (nur ausserhalb des Modify-Quiet-Fensters, **vor** dem Sperr-Zweig), dann bei Sperre `SafeCloseAll()`, sonst `EnforceSLTP()` (R7) + `EnforceRisk()` (R1) + `EnforceRR()` (R8) + `EnforceHeat()` (R12); diese **reihen Tickets nur in die Close-Queue ein** (`RequestClose`). Danach `ProcessCloseQueue()` führt die tatsächlichen Closes mit Retry/Backoff/Journal aus. Alle Schleifen `InScope`-gefiltert — **Ausnahme R22** (vergleicht die Magic direkt, siehe Abschnitt 7).
   Den ganzen Enforcement-Block erreicht nur die **bestätigte Master-Instanz** (≥2 Cycles in Folge `ClaimMaster()`) und nur, wenn AutoTrading an ist (`IsTradeAllowed()`); passive Instanzen kehren vorher zurück. `IsTradeContextBusy()` führt zum sofortigen Rücksprung.
9. Panel zeichnen (gedrosselt `InpPanelMs`=1500 ms, nur bei Änderung).
10. `WriteLockstate()` — Lockstate-Datei aktuell halten (nur bei Änderung → Disk).

**Hintergrund:** In v0.8 liefen Trades **nur aus dem Tick** (Wine-Crash-Vermeidung). **Ab v0.15** läuft Enforcement aus OnTick **und** OnTimer (tickunabhängig); Close-Operationen sind gedrosselt (`InpCloseThrottleMs`) + `IsTradeContextBusy`-Guard. **Ab v0.16** läuft die eigentliche Schliessung über die echte Close-Queue (`ProcessCloseQueue`, Retry-Limit/Backoff/Journal).

## 3a. Master-Election (Einzel-Instanz-Sperre) — Heartbeat, Hysterese, Deadlock-Fix

**Warum:** Der EA liegt typischerweise auf mehreren Charts. Enforcement ist aber **kontoweit** (Filter nach Magic, nicht nach Symbol) — **eine** Instanz reicht. Mehrere aktive Instanzen würden dieselben Dateien schreiben (Journal-CSV, Lockstate, Cockpit-JSON) und dieselben Closes doppelt werten. Seit v0.28 entscheidet deshalb eine terminalweite Wahl, welcher Chart **Master** ist.

| Schlüssel | Bedeutung |
|---|---|
| `RG_MASTER` | `ChartID()` des Masters, als **double** gehalten; `0` = Slot frei (existiert aber) |
| `RG_MASTER_HB` | Heartbeat des Masters, **`TimeLocal()`** |

**Warum double und warum `TimeLocal()`:** `ChartID()` kann > 2^53 sein — der Umweg `long→double→long` verlor die Identität, der Vergleich bleibt darum durchgehend in `double`. Die Uhr ist bewusst `TimeLocal()`: für alle Instanzen **eines** Terminals identisch, kein Drift über den Server-Offset (`SrvTime()` wird pro Instanz gepflegt). *(Doku-Korrektur: der `#define`-Kommentar zu `RG_MASTER_HB` sagt „Server-Zeit" — der Code schreibt `TimeLocal()`.)*

**`ClaimMaster()` — drei Zweige:**
1. `RG_MASTER == meine ChartID` → Heartbeat auffrischen, `true`.
2. `RG_MASTER == 0` (Slot frei) → **atomar** beanspruchen: `GlobalVariableSetOnCondition(RG_MASTER, myKey, 0.0)`. Nur einer gewinnt; der Verlierer bekommt `false`. Fehlt die Variable ganz, wird sie **vorher** per `GlobalVariableTemp()` mit 0.0 angelegt (v0.42-Fix, siehe unten).
3. Heartbeat **stale** (`|TimeLocal()−HB| > 10 s`, Betrag → deckt auch Uhr-Rücksprünge ab) → Übernahme per `SetOnCondition(RG_MASTER, myKey, mid)`, d. h. nur, wenn der Slot noch dem stalen Master gehört.

Sonst `false` = ein anderer ist frischer Master. Die 10-s-Schwelle ist Puffer gegen langsame/eingefrorene Cycles unter Wine; zusätzlich schreibt der Master den Heartbeat **auch am Cycle-Ende** (`GlobalVariableSet(GV_MASTER_HB, TimeLocal())`), damit ein langer Cycle ihn nicht mitten im Schreiben stale aussehen lässt.

**Hysterese:** `g_masterStreak = ClaimMaster() ? g_masterStreak+1 : 0`. Erst ab **≥2 Cycles in Folge** handelt die Instanz. Verhindert Startup-Bursts und Doppel-Handeln bei einem Wett-Claim.

**Nur der bestätigte Master macht:** Enforcement (R4/R6/R22 …, Close-Queue), die gesamte **Close-Wertung** (`ResolveHistory`/`ResolveByTicketRegistry`/`ResolveManualHistory`, `HistoryVisibilityWatch`), Journal-/Lockstate-/Cockpit-Schreiben, den GV-Flush, das Einlesen von `mamal_cmd.txt` und die Basis-Selbstheilung (v0.38). Passive Instanzen zeichnen nur ihr Panel; der **Klick-Pfad (BUY/SELL, Close-Buttons) funktioniert auf jedem Chart**.

**Magic-Divergenz (v0.38):** Der Master publiziert sein `InpMagic` in `RG_MAGIC`. Eine passive Instanz mit abweichendem `InpMagic` warnt **einmalig** deutlich — deren Panel-Trades wären für den Master weder `InScope()` noch R22, also unbewacht.

### Der v0.42-Deadlock (kritischster Fund des Projekts)
`OnDeinit()` gab den Master frei, indem es `RG_MASTER` **löschte** (`GlobalVariableDel`). `GlobalVariableSetOnCondition()` kann eine **fehlende** Variable aber nicht anlegen (Err 4058) — Zweig 2 von `ClaimMaster()` scheiterte danach für immer. Folge: **nach dem Entfernen des Master-Charts war nie wieder eine Master-Wahl möglich.** Enforcement, Close-Wertung und Cockpit-Updates standen still — und zwar **unsichtbar**, weil das Panel auf jeder Instanz normal weiterlief (Panel-Zeichnen hängt nicht am Master).

**Fix, dreiteilig:**
- `OnDeinit()` gibt per **`Set(RG_MASTER, 0.0)`** frei (plus `RG_MASTER_HB=0`), und nur, wenn die Instanz wirklich Master war. Der Slot existiert weiter → die nächste Instanz übernimmt sofort über Zweig 2.
- `ClaimMaster()` legt einen **fehlenden** Slot bei Bedarf selbst an (`GlobalVariableTemp`, Wert 0.0) und beansprucht ihn erst danach per `SetOnCondition` — die Claim-Atomik bleibt erhalten, es gewinnt genau einer. Damit heilt auch ein per F3 gelöschter Slot.
- **Kein-Master-Alarm:** Ist der Slot frei/verwaist (`RG_MASTER` fehlt oder `==0`, oder Heartbeat älter als 10 s), startet ein Latch. Nach **30 s** ohne Master: `Notify("KEIN Master aktiv — Enforcement + Close-Wertung stehen STILL…")` + Journal-Event **`PROTECT_OFF`** mit Tag „KEIN Master seit Ns — Slot belegt/FEHLT".

**Nachbesserungen:** *v0.43* — nur alarmieren, wenn **wirklich niemand** Master ist; eine passive Instanz ist der Normalfall (genau eine ist Master) und darf nicht dauerwarnen. *v0.45* — die 30 s laufen **zeitbasiert** (`SrvTime()`) statt cycle-basiert (der Cycle-Takt hängt an `InpTimerSeconds`), und der Latch wird beim Wechsel **in** den Master-Zustand ebenfalls entschärft (`g_noMasterSince=0`, `g_noMasterWarned=false` im Master-Pfad).

**Ehrliche Grenze:** Der Alarm meldet den Zustand, er repariert ihn nicht. Bleibt kein Chart mit EA übrig, ist auch kein Watchdog da — das ist bauartbedingt und identisch zum Fall „EA entfernt / AutoTrading aus".


---

## 4. Persistenz (GlobalVariables)
MT4-GlobalVariables überleben Terminal-Neustart (auf Disk gespeichert). Präfix `RG_`:

| Schlüssel | Bedeutung |
|---|---|
| `RG_INIT_BAL` | Startkapital (für R4b) |
| `RG_DAYSTART_EQ` / `RG_DAYSTART_DAY` | Equity bei Tagesstart / Tagesschlüssel (yyyymmdd) |
| `RG_LOCK_UNTIL` | Serverzeit, bis wann Tages-/Giveback-Sperre gilt |
| `RG_HARD_LOCK` | 1 = permanente Max-Loss-Sperre (R4b) |
| `RG_DAY_RISK` | kumuliertes am Tag eröffnetes Risiko % (R3) |
| `RG_CONSEC` | Verluste in Folge (R5/R6/R19) |
| `RG_COOLDOWN` | Serverzeit bis Cooldown-Ende (R5) |
| `RG_PEAK_EQ` | Tages-Hoch der Equity (R13 Giveback) |
| `RG_TARGET_HIT` | 1 = Tagesziel erreicht (R13) |
| `RG_LAST_ENTRY` | Zeit des letzten Trades (R14) |
| `RG_WEEKSTART_EQ` / `RG_WEEK_IDX` / `RG_WEEK_LOCK` | Wochenstart-Equity / Wochenindex / Wochensperre (R18) |
| `RG_BASE_WARN` | Tagesbasis unsicher (Erststart) → neue Trades gesperrt (P1-2) |
| `RG_LAST_CLOSE` | Wasserstand der History-Verlustauflösung (P0-2/P0-4) |
| `RGP_<…>` (pro Position) | bereits gewertete Position, idempotent (P0-2/P0-4) |
| `RGEAC_<ticket>` (pro Ticket) | vom EA geschlossen → zählt nicht als Verlust (P0-3, **sofort geflusht**) |

**R25-Revenge (v0.17, persistent):** `RG_REVD_<sym>` = verlorene Richtung (OP_BUY/OP_SELL), `RG_REVU_<sym>` = gültig-bis (Server-Zeit). `PruneRevenge()` löscht abgelaufene Paare. Überlebt Neustart (vorher in-memory).

**Zusätzlicher Datei-Spiegel (v0.16):** `…/MQL4/Files/MamalTrading_Lockstate.dat` — eine Zeile `MMTLS1;<DayKey>;<Hard>;<LockUntil>;<WeekLock>;<TargetHit>;<Cooldown>;<DayRisk>;<Consec>;<Checksum>`. Checksumme = gesalzene djb2 (HMAC-light) über die Felder. Beim Start (`ReconcileLockstate`) wird der **restriktivste** Zustand aus GV **und** Datei übernommen (Hard-Lock/Week-Lock/Target/Cooldown ODER-verknüpft, LockUntil/Cooldown = spätester Zeitpunkt, DayRisk/Consec = Maximum). **Beschädigte/manipulierte Datei → fail-closed** (Tagessperre + `TAMPER`-Journal). Die Datei ist nur ein Cross-Check/Backstop; primär bleiben die GlobalVariables.

**Resets:** `RollNewDay()` (bei Serverzeit-Datumswechsel) setzt Tageswerte zurück (DAYSTART, DAY_RISK, CONSEC, COOLDOWN, PEAK_EQ, TARGET_HIT, LOCK_UNTIL). Wochenwerte bei `WeekIdx`-Wechsel. `RG_HARD_LOCK` wird nie automatisch zurückgesetzt. **Zeitbasis (v0.16): `SrvTime()`** = `TimeLocal()` (PC-Uhr) + Server-Offset (am Tick aus `TimeCurrent()−TimeLocal()` via `UpdateSrvOffset()` gepflegt; **MQL4 hat kein `TimeTradeServer()`** — das ist MQL5). Läuft auch ohne Ticks weiter; Fallback roher `TimeCurrent()`/`TimeLocal()`, solange der Offset ungesetzt ist. Alle „Jetzt"-Vergleiche (Tagesschlüssel `ServerDayKey`, `NextServerMidnight`, `WeekIdx`, Cooldown/Lock/Revenge/Mindestpause, Marker) laufen darüber → tickunabhängig + PC-Uhr-Tricks entsperren nicht. (**Doku-Korrektur:** auch die R7-Grace läuft über `SrvTime()` — `EnforceSLTP` vergleicht `SrvTime()` gegen den persistierten Naked-Zeitstempel; die frühere Aussage „nutzt bewusst `TimeLocal()`" stimmte nicht.)

---

## 5. Risiko-Engine & Auto-Lot
- `RiskPctOf(sym,lots,open,sl)` = `|open−sl| / tickSize · tickValue · lots / Equity · 100`.
- `CalcLot(dist, &rp)` = `Equity · EffectiveRiskPct()/100 / ((dist/tickSize)·tickValue)`, normiert auf `MODE_LOTSTEP`, gedeckelt auf `MODE_MAXLOT`. Liefert die Lotgröße + resultierendes Risiko %.
- `EffectiveRiskPct()` (**R19**) = halbiert (`InpDeRiskFactor`) ab `InpDeRiskAfter` Verlusten in Folge, sonst `InpRiskPerTradePct`.
- **Auto-Scale (dynamische Caps):**
  - `EffIdeaCap()` = `AutoScale ? Risiko/Trade · InpIdeaXrisk : InpIdeaCapPct`
  - `EffHeat()` = `AutoScale ? EffIdeaCap · InpHeatXidea : InpPortfolioHeatPct`
  - `EffDay()` = `AutoScale ? EffIdeaCap · InpDayXidea : InpDailyRiskBudgetPct`
  - Wirkung: Risiko/Trade oder `InpIdeaXrisk` ändern → Idee-Cap, Gesamtrisiko, Tagesbudget folgen automatisch; Trade-Anzahlen (2/4/**8** ab v0.20) bleiben konstant.
  - **v0.20:** `InpDayXidea=4` → Tagesbudget 2,0 % = 400 €. **R19 (De-Risk) ist AUS** (`InpDeRiskFactor=1.0`), daher bleibt `EffectiveRiskPct` konstant = `InpRiskPerTradePct`.

---

## 6. Entry-Tool (One-Click, Risk-based)
- **SL-Linie** = Objekt `MMT_slline` (OBJ_HLINE, rot, selektierbar). Setzen per **Klick in den Chart** (`CHARTEVENT_CLICK` → `ChartXYToTimePrice` → `SlZoneClick`) oder **Ziehen** (`CHARTEVENT_OBJECT_DRAG`). **v0.21:** Klick-Setzen erst nach **`InpSlClicksToMove`=3** Klicks in dieselbe Zone (`SlZoneClick`, Toleranz ~0,15 % vom Preis bzw. `InpSlZonePips`; 10-s-Fenster) — gegen versehentliches Verschieben beim ersten Klick; Ziehen wirkt sofort.
- **BUY/SELL** = `OBJ_BUTTON`. Klick → `GateClick()` → (R9 aus) → `DoEntry()`.
- **`DoEntry(isBuy)` Prüf-Reihenfolge (alle Gates):**
  1. AutoTrading an? → 2. Nicht gesperrt (R4/R4b/R6/R13/R18)? → 3. Tagesziel nicht erreicht (R13)? → 4. Kein Cooldown (R5)? → 5. In Session / kein News-Blackout (R16)? → 6. Kein Revenge-Gegentrade (R25)? → 7. Mindestpause vorbei (R14)? → 8. SL-Linie vorhanden + richtige Seite + über Broker-Mindestabstand? → 9. **R15** Mindest-SL-Abstand? → 10. `CalcLot` + **R15** Max-Lot-Cap + Min-Lot? → 11. **R2** Idee-Cap? → 12. **R3** Tagesbudget? → 13. **R12** Gesamtrisiko? → 14. **R17** Währungsvektor-Korrelation? → 15. `OrderSend` mit SL an der Linie, TP = `Entry ± Abstand·InpRR` (Magic 990201). → Erfolg: `RG_DAY_RISK` und `RG_LAST_ENTRY` setzen, Journal „OPEN", Screenshot optional.
- **`PreviewText()`** zeigt live im Panel Richtung/Lot/Pips/Risiko % für die aktuelle SL-Linie.
- **R22-Bezug (v0.35):** Nur der Panel-Pfad durchläuft diese Gate-Kette. Eine manuell im Terminal geöffnete Order umgeht sie **komplett** (kein Sizing, kein Idee-Cap/Tagesbudget/Heat/Korrelation, keine Cooldown-/Session-/Revenge-Prüfung) — genau deshalb schließt **R22** solche Orders nach (Abschnitt 7). Im On-Chart-Panel selbst taucht R22 nirgends auf.

---

## 7. Regel-zu-Code-Zuordnung
| Regel | Implementierung |
|---|---|
| R1 Risiko/Trade | `CalcLot` (Sizing) + `EnforceRisk` (schließt, wenn aktuelles Risiko > Limit·Toleranz) |
| R2 Idee-Cap | `IdeaOpenRiskPct(sym,dir)` + Entry-Block in `DoEntry` (`EffIdeaCap`) |
| R3 Tagesbudget | `RG_DAY_RISK` kumuliert (additiv nach `OrderSend` + sofort geflusht) + Entry-Block (`EffDay`); **R3-Reconciliation** `ReconcileDayRisk()` = `max(persistiert, ReconstructedDayRiskPct())` |
| R4 / R4b | Drawdown in `Cycle` → `RG_LOCK_UNTIL` / `RG_HARD_LOCK`; `SafeCloseAll` schließt + sperrt. **Zwei getrennte Basen:** R4 (Tag) gegen `RG_DAYSTART_EQ` = `MathMax(Balance,Equity)` am Tagesstart; R4b (gesamt) gegen `RG_INIT_BAL` = Startkapital (`g_initialBalance`) |
| R5 / R6 | `ResolveHistory`+`ApplyResult` werten Verlust-Closes (history-basiert) → `RG_COOLDOWN` / Tagessperre |
| R7 SL+TP | `EnforceSLTP` (v0.33: **4 s** Frist `InpSLTPGraceSeconds`, Anker = **seit SL/TP entfernt/fehlend** via `NakedSince()`/`NakedClear()`, **nicht** `OrderOpenTime`; News-Blackout `InpSLTPGraceNews=0`; **Tool-Trades identisch behandelt**, kein Sofort-Close-Sonderfall; Scope per `InScope(OrderMagicNumber())`). **v0.34-Härtung:** Grace-Uhr **persistent in GlobalVariables** `RG_NK_<ticket>` (statt Instanz-Array) → überlebt Neustart/Recompile/Timeframe-Wechsel/Master-Handoff; `NakedClear(ticket,now)` löscht nicht sofort, sondern startet `RG_NKH_<ticket>` und räumt erst nach **60 s Heilfrist** ab (wieder nackt → Heilfrist verfällt, alte Uhr läuft weiter); `PruneNaked()` räumt Marker geschlossener Tickets im 60-s-Housekeeping. SL/TP-Pflicht **tighten-only** über `EffRequireSL()`/`EffRequireTP()` (`RG_EFF_REQSL`/`RG_EFF_REQTP`) — intraday nicht abschaltbar |
| R8 Min-CRV | `EnforceRR` (reward/risk < `InpMinRR` → schließen) |
| R9 Anti-FOMO | `GateClick` (deaktiviert: `InpFomoGate=false`) |
| R10 No-Override | kein Unlock-Code; Sperren in GV (restart-fest); Tamper-Warnung bei `!IsTradeAllowed()` |
| R11 Journal | `Journal()` → CSV; `Shot()` → optionaler Screenshot |
| R12 Gesamtrisiko | `TotalOpenRiskPct` + Entry-Block + `EnforceHeat` (schließt neueste) (`EffHeat`) |
| R13 Tagesziel/Giveback | `RG_PEAK_EQ`/`RG_TARGET_HIT` in `Cycle` |
| R14 Mindestpause | `RG_LAST_ENTRY` + Entry-Block |
| R15 Min-SL/Max-Lot | Entry-Block (`InpMinStopPips`) + Lot-Cap (`InpMaxLot`) — **beide Default 0 = aus** (v0.22, M1-Scalping); wirksam bleibt nur der Broker-`STOPLEVEL`-Check im Entry-Pfad |
| R16 Session/News | `InSession()` + `InNewsBlackout()` → `OffSession()` Entry-Block — **Default inert**: `InpUseSession=false` und `InpNewsFrom==InpNewsTo==0` ⇒ `OffSessionAt()` liefert immer `false` |
| R17 Korrelation | `SplitCcy`/`AddExposure`/`MaxCurrencyExposurePct` — Währungsvektor, größte |Netto-Währung| ≤ Limit (v0.17; ersetzt `UsdSign`/`NetUsdRiskPct`) |
| R18 Wochenlimit | `WeekIdx` + `RG_WEEKSTART_EQ`/`RG_WEEK_LOCK` |
| R19 De-Risk | `EffectiveRiskPct()` (in `CalcLot`) |
| R22 Nur Panel-Trades (v0.35) | `EnforceManualTrades()` — Schleife über `OrdersTotal()`, überspringt alles mit `OrderMagicNumber()!=0` (fremde EAs), reiht jede verbleibende Order per `RequestClose` ein: Positionen (`OP_BUY/OP_SELL`) mit Grund „R22 Manueller Trade — nur Panel-Trades erlaubt", Pendings mit „R22 Manuelle Pending-Order — nur Panel-Trades erlaubt". **Aufruf: genau eine Stelle** im Enforcement-Block von `Cycle()`, **vor** dem Sperr-Zweig, nur wenn `!modifyQuiet`. Ausführung wie jeder andere Close über `ProcessCloseQueue()` (Positionen zu Bid/Ask mit `InpSlippage`, Pendings via `OrderDelete()`), Retry/Backoff/Journal identisch. Re-Validierung direkt vor dem Positions-Close: `CloseReasonStillValid()` → `StringFind(reason,"R22")==0` ⇒ `InpCloseManualTrades && OrderMagicNumber()==0`. **Kein Symbolfilter** (kontoweit über alle Symbole), **kein `InScope()`** |
| R25 Revenge | `SetRevenge`/`RevengeBlocked` **persistent** in GlobalVariables `RG_REVD_`/`RG_REVU_` (v0.17; `PruneRevenge` räumt ab) |

**Verlust-Erkennung (R5/R6/R19/R25):** `ResolveHistory()` liest geschlossene In-Scope-Positionen aus `MODE_HISTORY`, gruppiert per `ProcKey` (OpenTime_Type_Symbol_Magic_OpenPrice, OpenPrice mit Symbol-Digits) → **aggregiert Partial-Closes zu EINEM Netto-Ergebnis**; idempotent über persistente `RGP_`-Marker (same-second-robust) + Wasserstand `RG_LAST_CLOSE`; `net<0` = Verlust → `RG_CONSEC++` + `SetRevenge`; Gewinn → `RG_CONSEC=0`. EA-Schutz-Closes (`RGEAC_`) zählen nicht. Noch offene Teil-Positionen werden zurückgestellt (nur diese Gruppe, kein globaler Stopp).

**R22-Besonderheiten (v0.35):**
- **Läuft vor dem Sperr-Zweig** → greift unabhängig davon, ob gerade eine Sperre aktiv ist (Tag/Woche/Max-Loss). Vorher wurden manuelle Trades bei aktiver Sperre unter `TOOL_ONLY` **gar nicht** geschlossen: `SafeCloseAll()` überspringt out-of-scope-Orders und warnt nur max. 1×/60 s. (Unter `TOOL_PLUS_MANUAL` wurden Magic-0-Trades bei Sperre schon vorher geschlossen.)
- **Bewusst nicht am `WatchScope`:** `EnforceManualTrades()` ist die **einzige** Enforcement-Funktion, die `InScope()` umgeht und die Magic direkt vergleicht. R22 wirkt damit auch im **FundedMode**, der `WatchScope` hart auf `TOOL_ONLY` zwingt.
- **Wechselwirkung `WatchScope=TOOL_PLUS_MANUAL`:** mit `InpCloseManualTrades=true` wirkungslos — Magic-0-Orders sind bereits von R22 in der Close-Queue, bevor die scope-basierten Enforce-Funktionen sie überhaupt zu sehen bekommen. Der EA gibt dafür beim Start einen Hinweis aus (nur bei genau dieser Kombination).
- **⚠ Abgrenzung hängt allein an `Magic != 0`.** Panel-Trades gehen mit `InpMagic` raus (Default `990201`). Wer `InpMagic=0` setzt, lässt R22 die **eigenen** Panel-Trades abräumen — im Code gibt es keinen Schutz dagegen.
- **Kein Bestandsschutz, aber auch kein Sofort-Close beim Start:** `OnInit` zählt vorgefundene Magic-0-Orders und meldet sie (Notify + Journal-Event **`INFO`**, Tag „R22 Start: N manuelle Order(s) vorgefunden -> werden geschlossen"; bei N=0 nur Notify, kein Journal-Eintrag). Geschlossen wird dort **nichts** — der erste `Cycle()` ist noch nicht Master (`g_masterStreak<2`), der tatsächliche Close passiert erst im nächsten oder übernächsten Cycle, auf einer passiven Instanz gar nicht.
- **Re-Validierung nur bei Positionen:** Pendings werden in `ProcessCloseQueue()` unbedingt gelöscht, bevor `CloseReasonStillValid()` überhaupt aufgerufen wird. Eine bereits gequeuete Pending verschwindet also auch dann, wenn `InpCloseManualTrades` zwischenzeitlich auf `false` gestellt wird.
- **Kein Beitrag zu den Serien-/Budget-Regeln:** `ResolveHistory()` filtert per `InScope(OrderMagicNumber())`, Magic 0 ist unter `TOOL_ONLY`/FundedMode out of scope → ein per R22 geschlossener Trade zählt **nicht** für R5 Cooldown, R6 Verlustserie, R19 De-Risk, R25 Revenge. `ReconcileDayRisk()` zählt nur `OrderMagicNumber()==InpMagic` → **kein** Verbrauch des R3-Tagesbudgets. Der realisierte Verlust schlägt dagegen sehr wohl auf die **equity-basierten** Grenzen durch: R4 Tagesverlust, R4b Max-Loss, R18 Wochenlimit. `IsFaultCloseReason()` listet nur R7/R1/R8 — R22 gilt dort **nicht** als Trader-Verschulden.
- **Journal/Cockpit:** Die Close-Tags lauten „Queue OK (Versuch n): R22 …" bzw. „Queue DELETE ok: R22 …" — sie beginnen mit „Queue", und `RuleIdFromTag()` zieht nur ein **führendes** „Rxx". Die RuleId-Spalte des EA bleibt bei R22 also leer; die Zuordnung im Cockpit passiert erst dort über den Fallback (`ruleFromTag()`). Ehrliche Grenze der Statistik: gezählt wird jede `CLOSE`-Zeile mit RuleId, also auch jeder RETRY, jeder FINAL-FAIL und jedes Verwerfen — **ein einzelner manueller Trade kann in „Deine Schwächen" mehrfach zählen.** Der `INFO`-Eintrag aus `OnInit` wird nicht mitgezählt.

## 7a. Close-Auflösung: drei Pfade, drei Dedup-Namespaces

Seit v0.44/0.45 laufen **drei** Auflöser hintereinander, immer in dieser Reihenfolge und nur auf dem bestätigten Master:

```
if(!IsTradeContextBusy() && (OrdersHistoryTotal() != letzter Wert || seit ≥2000 ms))
   ResolveHistory();  ResolveByTicketRegistry();  ResolveManualHistory();  HistoryVisibilityWatch();
```
Ausgelöst also durch **Änderung von `OrdersHistoryTotal()`** oder spätestens alle **2 s**, nie bei belegtem Trade-Kontext.

### Dedup-Namespaces und Karenzzeiten
| Namespace | Bedeutung | gesetzt von | Aufräumen |
|---|---|---|---|
| `RGP_<OpenTime>_<Type>_<Symbol>_<Magic>_<OpenPrice>` (`ProcKey`) | Position ist **regel-gewertet** | `AddProcessed()` (Pfad 1 + 2) | `PruneGV` im 60-s-Housekeeping, Schwelle `newFloor − 21600` → **6 h Karenz** |
| `RGM_<ProcKey ohne RGP_>` (`ManKey`) | Position ist **im Cockpit gezeigt/gezählt** | `AddProcessed()` **und** Pfad 3 | `SrvTime() − 2·86400` → **2 Tage** |
| `RGOPN_<Ticket>` (`OpnKey`) | vom **Panel eröffnetes Ticket** registriert | `DoEntry()` (sofort geflusht) + Rest-Ticket nach Panel-50 %-Close | **kein Zeit-Prune**: gezielt gelöscht, sobald die Gruppe gewertet ist / kein Positions-Typ / bereits verarbeitet. Noch offene Tickets werden bei jedem Lauf aufgefrischt, sonst greift MT4s eigener **4-Wochen-Verfall** für GlobalVariables |
| `RGEAC_<Ticket>` / `RGEACF_<Ticket>` | EA-Close / EA-Close mit **Trader-Verschulden** (R7/R8/R1) | `MarkEaClosed()` | je **2 Tage** |

**v0.43-Fix (kritisch):** Vorher wurden die `RGP_`-Marker **sofort** mit dem Wasserstand gepruned (nur der allerletzte überlebte). Für `ResolveHistory` war das folgenlos (der Floor schützt selbst), aber der **Ticket-Fallback prüft genau diese Marker** — er fand keine und wertete alles ein zweites Mal: doppelte `CLOSE`-Zeilen, doppelte Verlustserie, doppeltes Netto im Kalender. Seither 6 h Karenz.

*Doku-Korrektur zu Abschnitt 7:* `ProcKey` bildet den OpenPrice mit **fester Präzision (8 Nachkommastellen)**. Die Variante mit `MarketInfo(MODE_DIGITS)` lebt nur noch als `ProcKeyLegacy` weiter; `IsProcessedAny(key, legacyKey)` respektiert beide, damit ein Update keine Doppelwertung auslöst.

### Pfad 1 — `ResolveHistory()` (Regel-Pfad, R5/R6/R19/R25)
Scannt `MODE_HISTORY` ab dem Wasserstand `RG_LAST_CLOSE`. Eine Zeile wird verarbeitet, wenn `InScope(Magic)` **oder** das Ticket per `RGOPN_` registriert ist (v0.40-Fix: läuft der Master mit abweichendem `InpMagic`, fielen sonst die eigenen Trades aus der Wertung). Gruppierung per `ProcKey` → Partial-Closes ergeben **ein** Netto; getrennt geführt werden Trader-Anteil (`gManNet`) und EA-Anteil (`gEaNet`, plus Fault-Flag). Gewertet wird chronologisch nach spätester Close-Zeit, damit Serie/Cooldown der echten Reihenfolge folgen.
- **Zukunfts-Floor-Selbstheilung (v0.41):** liegt `RG_LAST_CLOSE` > `SrvTime()+60`, wurde jeder Close für immer übersprungen → Reset auf `ServerDayStart()` + `INFO`-Journal.
- **Teil-Close:** offener Rest → Gruppe zurückstellen; ist die Gruppe aber ≥ **10 min** alt und der effektive Netto-Anteil negativ, wird der **realisierte Verlust trotzdem** gewertet (nur Verluste — ein Teil-Gewinn darf die Serie nicht vorzeitig zurücksetzen).
- **Tagesgrenze:** Closes eines vergangenen Servertags erzeugen nur eine `CLOSE`-Zeile („zählt nicht für die heutige Serie"), kein `ApplyResult`.
- Der neue Floor geht **nie über eine zurückgestellte Gruppe hinaus** und nie zurück.

### Pfad 2 — `ResolveByTicketRegistry()` (Sicherheitsnetz, v0.40)
Arbeitet ausschließlich über `RGOPN_` und `OrderSelect(..., SELECT_BY_TICKET)` — damit **unabhängig vom Zeitraumfilter des Kontohistorie-Tabs und vom `RG_LAST_CLOSE`-Floor**, und unabhängig von der Magic. Ablauf: Registry zuerst **einfrieren** (GV-Neuanlagen durch `ApplyResult` würden die Iteration sonst verschieben), dann pro Ticket:
- nicht auflösbar → Key behalten, 1× pro Stunde `INFO` („History-Cache prüfen");
- `OrderCloseTime()==0` → offen, Key auffrischen; kein Positions-Typ oder bereits per `RGP_` verarbeitet → Key löschen;
- offener Rest der Position → später.

**Gruppen-Aggregation (v0.40-Fix):** Alle registrierten Geschwister-Legs derselben Position (identisch in OpenTime/Typ/Symbol/Magic/OpenPrice ±1e-7) werden **gemeinsam** gewertet; ist ein registriertes Leg noch offen, wartet die ganze Gruppe. Ohne das wertete der Fallback nur das zuerst iterierte Leg, und `AddProcessed` verschluckte das P/L der Geschwister — ein Laundering-Fenster (Gewinn-Bein zuerst → Serien-Reset trotz Netto-Verlust). Die Entscheidung danach ist identisch zu Pfad 1 (Tagesgrenze → Trader-Anteil → Fault-EA-Anteil → sonst „EA-Schutz-Close (zählt nicht)"), anschließend `AddProcessed` und Löschen aller `RGOPN_` der Gruppe.

**Diagnose:** höchstens alle 60 s; ins Journal (`INFO`) nur bei **echter** Anomalie (nicht auflösbare Tickets), sonst nur `Print` — vorher verdrängten periodische INFO-Zeilen echte Ereignisse aus der Cockpit-Liste (v0.41/0.45).

### Pfad 3 — `ResolveManualHistory()` (manuelle/fremde Trades, v0.44/0.45)
Macht Trades **außerhalb** des Tools (manuell, Handy, fremde EAs) im Cockpit sichtbar — als eigenes Event **`CLOSE_MAN`**. Sie ändern **keine Regel**: keine Verlustserie, kein Cooldown, kein Tagesbudget; sie zählen aber ins Netto (echtes Geld) und schlagen damit weiterhin auf die equity-basierten Grenzen R4/R4b/R18 durch.
- **Melde-Fenster** = heutiger Servertag (`ServerDayStart()`, unplausible Zeitbasis → Abbruch). **Aggregations-Fenster** ist bewusst breiter (`dayStart − 7 Tage`): ein Teil-Close von gestern gehört zum selben Positions-Netto, sonst meldet `CLOSE_MAN` nur einen Teilbetrag.
- **Filter-Reihenfolge (v0.45):** erst die billigen Prüfungen (Close-Zeit, Typ, `InScope` → gehört Pfad 1, `RGOPN_` → gehört Pfad 2), erst danach GV-Lookups. `GlobalVariableCheck` ist O(N_GV) und lief vorher auf **jeder** History-Zeile — bei „Gesamte Historie" alle 2 s zehntausende Lookups (Wine-Freeze-Risiko).
- **Doppelzählung ausgeschlossen (v0.45):** vor dem Melden Quervergleich mit dem Regel-Pfad (`IsProcessedAny` über `RGP_`/Legacy). Trifft er, wird nur der `RGM_`-Marker gesetzt und nichts journalisiert — sonst konnte ein über die Ticket-Registrierung gewerteter Trade (Magic-Divergenz/Scope-Wechsel) **zusätzlich** als `CLOSE_MAN` erscheinen → doppeltes Netto im Dashboard.
- **Marker vor Journal:** `RGM_` wird **vor** der Journalzeile gesetzt und der Erfolg geprüft; schlägt die GV-Anlage fehl (Namenslänge/GV-Limit), gibt es einmalig eine `INFO`-Zeile statt derselben Zeile alle 2 s.
- Journalzeile: Event `CLOSE_MAN`, Netto in der Net-Spalte, Tag „Manueller/fremder Trade (Magic n) — außerhalb der Tool-Regeln, nur Anzeige".

**Auswertung im Cockpit:** Der Server zieht das Netto bei `CLOSE_MAN` aus der **Net-Spalte** (bei normalen `CLOSE`-Zeilen dagegen aus dem `net …`-Text im Tag), zählt sie in Kalender/Netto/Trade-Statistik mit und weist sie zusätzlich separat aus (`totals.manualN`/`manualNet`, Tageszähler `manual`). Das Dashboard markiert sie orange bzw. mit „✋"; ein Tag mit manuellen Trades gilt **nicht** als sauberer Tag und unterbricht die Disziplin-Streak.

**Ehrliche Grenze:** Pfad 1 und 3 sehen nur, was der Kontohistorie-Tab geladen hat (`OrdersHistoryTotal()`) — dagegen steht `HistoryVisibilityWatch()` als fail-closed Wachhund. Nur Pfad 2 ist von diesem Filter unabhängig, deckt aber ausschließlich **registrierte Panel-Tickets** ab.


---

## 8. On-Chart-Panel
- Objekte mit Präfix `MMT_`: Karte (`OBJ_RECTANGLE_LABEL`), Kopfzeile, Status, zwei Balken-Meter (Tages-/Gesamtverlust), Vorschau-Zeile, Fußzeile (Heat/Budget/Stops), BUY/SELL-Buttons.
- **Performance/Crash-Schutz:** `DrawPanel` läuft max. alle `InpPanelMs`=1500 ms und nur, wenn sich eine Status-Signatur (`g_panelSig`) ändert → im Ruhezustand **kein** `ChartRedraw`. Statische Objekt-Eigenschaften werden nur einmal beim Erzeugen gesetzt.
- **Status-Strings (exakt, 9 Stück).** Panel (`DrawPanel`) und Cockpit-JSON (`WriteCockpit`) verwenden **dieselbe** Kaskade in **dieser Prioritäts-Reihenfolge** — der erste Treffer gewinnt:
  1. `SCHUTZ AUS` (amber) — AutoTrading aus
  2. `MAX-LOSS GESPERRT` (rot) — `IsHardLocked()`, R4b permanent
  3. `WOCHE GESPERRT` (rot) — `IsWeekLocked()`, R18
  4. `TAG GESPERRT` (rot) — `IsDayLocked()`, R4/R6/R13
  5. `MAX-LOSS WARNUNG` (amber) — R4b Warn-Gate
  6. `COOLDOWN` (amber) — R5
  7. `ZIEL ERREICHT` (grün) — R13
  8. `AUSSER SESSION` (neutral) — R16
  9. `AKTIV` (grün)
  Die drei Sperr-Strings 2–4 kommen aus **einem** verschachtelten Ausdruck (`IsHardLocked() ? … : IsWeekLocked() ? … : "TAG GESPERRT"`), d. h. bei Mehrfach-Sperre wird nur die **härteste** angezeigt. *(Doku-Korrektur v0.34: hier stand ein generisches „GESPERRT" — der Code kennt diesen String nicht.)*

## 8a. Panel-Skalierung — `PScale`/`SScale`/`FScale` → `PS()`/`PF()` + Auto-Fit

**Zwei gegenläufige Probleme.** Bei einer Windows-Skalierung > 100 % rendert MT4 die *Schrift* größer, lässt die Pixel-Koordinaten (`OBJPROP_XDISTANCE`/`YDISTANCE`/`XSIZE`/`YSIZE`) aber unskaliert → das Panel überlappt sich selbst (v0.37). Umgekehrt ist das Panel auf kleinen oder geteilten Charts höher als das Chartfenster → die unteren Buttons liegen außerhalb des sichtbaren Bereichs und sind nicht mehr klickbar (v0.46).

**Drei Faktoren, zwei Helfer:**

| Funktion | Quelle | Klemmung | wirkt auf |
|---|---|---|---|
| `PScale()` | `InpPanelScale`; **0 = AUTO** aus `TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0` (144 dpi → 1.5; DPI nicht verfügbar → 1.0) | AUTO nie < 1.0; danach hart `0.5 … 3.0` | Geometrie **und** Schrift |
| `SScale()` | `InpShapeScale` | `0.5 … 2.0` | nur Geometrie |
| `FScale()` | `InpFontScale` | `0.5 … 2.0` | nur Schriftgrad |

- `PS(v) = round(v · PScale() · SScale())` — jede X/Y-Distanz, jede Breite/Höhe.
- `PF(v) = round(v · PScale() · FScale())`, Ergebnis **nie unter 6 pt** — jeder `OBJPROP_FONTSIZE`.

Beide werden **zentral** in den Zeichen-Helfern angewandt (`Lbl`, `LblR`, `RectB`, `Btn`, `EnsureRiskEdit`, `DrawCandleClock`); die Aufrufstellen übergeben durchweg unskalierte Konstanten und rechnen nie selbst. Auch der Klick-Hit-Test auf die Panelfläche läuft über `PS()` (`cx/cy` gegen `PS(12)…PS(312)` bzw. `PS(16)+PS(PanelH())`) — sonst würde ein Klick auf das skalierte Panel als SL-Zonen-Klick durchschlagen (Abschnitt 6).

**Auto-Fit (`InpPanelAutoFit`, Default an)** läuft als letzter Schritt *innerhalb* von `PScale()`, also nach der Klemmung:
```
ph = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
if (ph > 120) { need = (PanelH() + 28) * s;
                if (need > ph) s = s * (ph / need);
                if (s < 0.6)   s = 0.6; }
```
`PanelH()` rechnet **unskaliert** (Basis 372 px) und wächst mit den optionalen Zeilen: Risiko-Wähler (`RiskRowOff()`), RISK-FREE-Knopf **+26**, Test-Harness **+72**. Auto-Fit greift also genau dann stärker, wenn mehr Bedienelemente aktiv sind. Die 28 px sind der Rand oben/unten. Unter 120 px Chart-Höhe wird gar nicht angepasst (dort ist ohnehin nichts sinnvoll darstellbar). Der Boden **0.6** verhindert ein unlesbar kleines Panel — ist das Fenster noch flacher, ragt das Panel bewusst wieder hinaus (lieber abgeschnitten als unlesbar).

**v0.48-Fix:** Ein **manuell** gesetztes `InpPanelScale` darf jetzt auch *verkleinern*. Vorher lag die 1.0-Untergrenze der AUTO-Ableitung auf dem gesamten Pfad und klemmte jeden Wunsch nach einem kleineren Panel weg (`InpPanelScale=0.7` blieb wirkungslos). Die Untergrenze 1.0 gilt seither **nur** noch im AUTO-Zweig (`InpPanelScale<=0`).

**Doku-Korrektur / ehrliche Grenze:** Der Kopfkommentar von `PScale()` (v0.37) sagt, die Fontgröße werde bewusst *nicht* skaliert, „die skaliert MT4 selbst". Seit v0.46 multipliziert `PF()` aber ebenfalls mit `PScale()`. Trifft die Annahme des Kommentars zu, wirkt die Schriftskalierung im AUTO-Modus damit **doppelt** (einmal durch MT4, einmal durch `PF()`). Gegenmittel ohne Codeänderung: `InpFontScale` entsprechend absenken (z. B. 0.7 bei 150 % Windows-Skalierung) oder `InpPanelScale` manuell setzen. Zweite Grenze: `PScale()` liest `CHART_HEIGHT_IN_PIXELS` bei **jedem** Aufruf neu — die Skalierung folgt einer Fenster-Größenänderung also sofort, aber die Objekte werden erst beim nächsten `DrawPanel` (max. alle `InpPanelMs`=1500 ms, nur bei Signatur-Änderung) neu positioniert; unmittelbar nach dem Ziehen des Fensterrands kann das Panel kurz falsch sitzen.


---

## 8b. Mehrsprachigkeit — Panel (DE/EN) und Dashboard (DE/EN/FA)

Zwei **unabhängige** Übersetzungsschichten mit getrennten Umschaltern. Sie teilen sich weder Tabelle noch Platzhalter-Konvention und können bewusst auseinanderlaufen.

| Schicht | Sprachen | Umschalter | Tabelle | Schlüssel |
|---|---|---|---|---|
| On-Chart-Panel (MQL4) | DE / EN | EA-Input `InpLang` (`enum PanelLang { LANG_DE, LANG_EN }`), v0.53 | Funktion `T()` im EA | **153** |
| Dashboard (Browser) | DE / EN / **FA** (Persisch, RTL) | Auswahlfeld im Kopf, gemerkt in `localStorage.mamalLang` | `cockpit/i18n.js` → `window.MAMAL_I18N` | **346** je Sprache |

### Panel: `T()` / `TF()`
- `T(key)` ist eine lineare `if(k=="…") return en? "…" : "…";`-Kaskade mit `bool en = (InpLang==LANG_EN)` an einer einzigen Stelle. Ein **unbekannter Schlüssel gibt den Schlüssel selbst zurück** (`return k;` am Ende) — der Fehler fällt im Panel sofort auf, statt als leerer Text unterzugehen.
- `TF(key, a0, a1, a2, a3)` ruft `T(key)` und ersetzt anschließend `{0}`…`{3}` per `StringReplace` (v0.54; der vierte Platzhalter kam mit v0.57 dazu).

**Warum `{0}` und nicht `%s`/`%d`:** `StringFormat` bindet die Reihenfolge der Werte an den Format-String. Im Englischen steht die Wortstellung aber oft anders als im Deutschen („noch {0} Min" vs. „{0} min left"). Mit nummerierten Platzhaltern kann jede Sprachfassung ihre Werte **frei anordnen, mehrfach verwenden oder weglassen**, ohne dass die Aufrufstelle sich ändert. Genau deshalb liefern die Aufrufer nur noch fertige Strings (`IntegerToString`/`DoubleToString`) — Formatierung passiert vor `TF()`, nicht darin.

*Ehrliche Grenze:* `TF()` ersetzt **sequenziell** `{0}` → `{1}` → `{2}` → `{3}`. Enthielte ein früher eingesetzter Wert selbst die Zeichenfolge `{1}`, würde er in der nächsten Runde erneut ersetzt. In der Praxis sind die Argumente Zahlen, Symbolnamen und Prozentwerte — der Fall tritt nicht auf, ist aber nicht abgesichert.

### Die Tabelle ist der Endpunkt — Ersetzungsläufe müssen sie ausklammern
**v0.61, Endlosrekursion (kritischer Fund).** Ein automatischer Such-und-Ersetze-Lauf, der deutsche Literale im Code durch `T("…")` ersetzen sollte, hat die deutschen Texte **auch innerhalb der Übersetzungstabelle** ersetzt. Ergebnis: **22 Einträge**, deren „Übersetzung" wieder ein `T()`-Aufruf war → `T()` rief sich selbst auf, unbegrenzt. Folge: **Stack overflow** im Log, der EA starb mitten im Panel-Zeichnen, das Panel blieb halb leer stehen. Es gab keinen Compile-Fehler und keine Warnung — die Rekursion ist syntaktisch einwandfrei.

**Regel daraus:** `T()`/`TF()` sind die **Terminalstelle** der Übersetzung. Jeder Ersetzungslauf (Skript, IDE-Refactoring, Massen-Regex) muss den Funktionsrumpf von `T()` **explizit ausschließen** — nicht „hoffentlich trifft er ihn nicht". Die Tabelle darf ausschließlich Literale zurückgeben; ein `T(`/`TF(` innerhalb des Rumpfs ist per Definition ein Fehler und lässt sich trivial prüfen (`grep` auf `T(` zwischen `string T(string k)` und dessen `return k;`).

**Rückstand desselben Laufs (prüfbar, bis heute im Code):** Die Tabelle enthält 18 Schlüssel mit Präfix `misc.`, von denen nur **zwei** je abgefragt werden (`misc.tradeContextBusy`, `misc.orderSendFailed`). Die übrigen **16** (`misc.fragment*`, `misc.artifact*`) tragen als „Text" abgeschnittene MQL4-Code-Fragmente — der Extraktionslauf hatte beliebige String-Literale aus dem Quelltext herausgeschnitten. Sie sind funktional harmlos (niemand fragt sie ab, DE und EN sind identisch), aber sie sind der sichtbare Beleg für die Regel oben und gehören aufgeräumt.

### Dashboard: `t()` / `i18n.js`
- `t(key, params)` liest `MAMAL_I18N[LANG][key]`, fällt bei fehlendem Schlüssel auf **Deutsch** zurück (`T.de[key]`) und erst dann auf den Leerstring — die Oberfläche wird nie leer.
- Platzhalter sind hier **benannt** (`{account}`, `{n}`, `{min}`) und werden per `split/join` ersetzt; einzelne Schlüssel nutzen zusätzlich `{0}`. Das ist bewusst eine andere Konvention als im Panel: das Dashboard hat keine Format-String-Beschränkung, benannte Platzhalter sind beim Übersetzen selbsterklärend.
- `applyLang()` setzt `document.documentElement.lang`, füllt alle `[data-i18n]`-Elemente und erzwingt danach einen vollständigen Neuaufbau (`prevS=null; g_forceRedraw=true; tick(); loadAnalytics(); loadEquity()`), damit auch die dynamisch erzeugten Texte umschalten.
- **Persisch/RTL:** `root.dir = (LANG==='fa') ? 'rtl' : 'ltr'`. Das CSS spiegelt Tabellen-Ausrichtung, Kalender-Akzentstrich und Überschriften-Linie. **Zahlen bleiben linksläufig** über `html[dir="rtl"] .mono, .v, .lm-val { direction: ltr; unicode-bidi: embed }` — ohne das würden Beträge, Uhrzeiten und Prozentwerte im Bidi-Algorithmus umsortiert.
- Der Server liefert `cockpit/i18n.js` über den eigenen Endpunkt `/i18n.js` mit `Cache-Control: no-store` aus.

### Journal bleibt deutsch — bewusst, nicht vergessen
Die Journal-CSV (Abschnitt 9) wird **nicht** übersetzt: Event-Namen und Tag-Freitext bleiben durchgehend deutsch. Zwei Gründe, beide hart:
1. **Audit-Spur.** Eine Datei, deren Texte sich rückwirkend mit einem EA-Input ändern, ist als Nachweis wertlos; Zeilen von gestern und heute müssen wortgleich vergleichbar bleiben.
2. **Der Server wertet den Text aus.** `tradeDossier()` klassifiziert die SL/TP-Verschiebungen per Regex über den deutschen Tag (`/Risiko ERHOEHT|Risiko unbegrenzt/`, `/Risiko gesenkt/`, `/Gewinn abgekuerzt/`, `/Ziel vergroessert/`, siehe Abschnitt 9b), und `RuleIdFromTag()` bzw. `ruleFromTag()` ziehen die Regel-ID aus dem Tag-Anfang. Ein übersetztes Journal würde diese Auswertung **still** ausfallen lassen — keine Fehlermeldung, nur plötzlich überall Null.

**Ehrliche Grenzen der Umstellung:**
- **Der Status-String im Cockpit folgt der Panel-Sprache, nicht der Dashboard-Sprache.** `WriteCockpit()` schreibt `status` über dieselbe `T("status.*")`-Kaskade wie das Panel (Abschnitt 8), das Dashboard zeigt `s.status` **roh** an (Status-Pille, Konto-Liste). Mit `InpLang=LANG_EN` steht dort also „DAY LOCKED", auch wenn das Dashboard auf Deutsch oder Persisch läuft. Zusätzlich vergleicht ein Alt-EA-Fallback im Dashboard gegen das deutsche Literal `'MAX-LOSS WARNUNG'`; er greift nur noch bei EA-Versionen ohne das Feld `maxWarn` und wird bei `LANG_EN` still wirkungslos.
- **Die Abdeckung ist nicht vollständig.** Einzelne dynamisch gebaute Blöcke im Dashboard sind fest deutsch verdrahtet — u. a. die Kacheln der Trade-Statistik („Expectancy / Trade", „Beste Stunde", „Einstieg in der Kerze" samt früh/mittig/spät) und die gesamte Trade-Akte (`trade.html` plus die im Server formulierte Zusammenfassung, Abschnitt 9b). Der Sprachumschalter lässt diese Texte unverändert.

---

## 9. Journal-Format (CSV, Trennzeichen `;`)


## 9a. Cockpit-Datenbrücke (EA → Dateien → lokaler Server)

Die Brücke ist **DLL-frei**: Der EA schreibt Dateien nach `…/MQL4/Files`, ein lokaler Node-Server (`cockpit/server.js`, zero-dependency) liest sie und serviert daraus das Dashboard auf `127.0.0.1`. Es gibt **keinen** Rückkanal außer der Kommando-Datei (unten) — und der kann prinzipiell nur **verschärfen**.

### Dateien
| Datei | Ort | Zweck |
|---|---|---|
| `mamal_cockpit.json` | `MQL4/Files` | Live-Zustand, alle **2 s** vom Master geschrieben |
| `mamal_cockpit.tmp` | `MQL4/Files` | Zwischendatei; `FileMove(...,FILE_REWRITE)` ersetzt die JSON **atomar** → kein Torn-Read |
| `mamal_cockpit_open.txt` | `MQL4/Files` | Trigger des Panel-Buttons „COCKPIT" → Server öffnet den Browser |
| `MamalTrading_Journal.csv` | `MQL4/Files` | Ereignis-Quelle für Kalender/Statistik (Abschnitt 9) |
| `mamal_files.txt` | **Common**/Files | Wegweiser (Legacy, ein Terminal) auf den echten Files-Ordner |
| `mamal_files_<login>.txt` | **Common**/Files | v0.38: Wegweiser **pro Konto** → Konto-Umschalter im Dashboard |
| `mamal_cmd.txt` | `MQL4/Files` | v0.39: Kommando vom Dashboard, tighten-only |

### JSON-Zustand
`WriteCockpit()` baut den String von Hand (kein Serializer) und schreibt u. a.: `v`, `srvtime`, `account`, `symbol`, `tf`, `port`, `profile`, `funded`, `equity`, `balance`, `ccy`, `initBal`, `status`/`statusColor`/`protectOff`, `dailyDD`/`dailyLimit`, **`dayBase`/`weekBase`** (v0.39, Basis für den €-Puffer-Tacho), `totalDD`/`maxLoss`/`maxLossWarn`, `protOff`/`tightenOnly`, `dayRisk`/`dayBudget`, `heat`/`heatCap`/`ideaCap`/`riskPerTrade`/`riskNextWeek`, `consec`/`lockAfter`/`cooldownAfter`/`cooldownSec`/`cooldownMin`, `weekDD`/`weekLimit`, `targetPct`/`profitPct`/`givebackPct`, die Flags `dayLock`/`hardLock`/`weekLock`/`targetHit`/`baseWarn`/`cooldown`/`offSession`/`maxWarn`, `minStopPips`/`rr`/`scope`, `fills`/`blocks`/`riskEstimate` sowie `disabled[]` (abgeschaltete Regeln → Dashboard-Chip „— aus", u. a. `R22`, wenn `InpCloseManualTrades=false`).

- Die Status-Kaskade ist **dieselbe** wie im Panel (Abschnitt 8) — Cockpit und Panel können nicht auseinanderlaufen.
- Der Schreibtakt hat **bewusst kein `IsTradeContextBusy()`-Gate**: `WriteCockpit()` macht reines Datei-I/O und fasst den Trade-Thread nie an. Mit Gate veraltete die JSON genau dann, wenn es interessant wird (Close-Queue-Retries).
- `account` ist ein **String** (überlaufsicher) und dient dem Server als Konto-Identität.

### Beacons (Common-Ordner)
Der Files-Ordner eines Terminals hängt an einem Instanz-Hash bzw. am Portable-Pfad — der Server kann ihn nicht raten. Der EA legt darum im **Common**-Ordner (`FILE_COMMON`, fester Pfad) einen Wegweiser mit dem Inhalt `TerminalInfoString(TERMINAL_DATA_PATH)+"\MQL4\Files"` an: einmal als `mamal_files.txt` (Legacy) und einmal als `mamal_files_<login>.txt` (v0.38, pro Konto → mehrere Terminals überschreiben sich nicht mehr).

Geschrieben wird **einmal pro Session/Konto** (Latch `beaconAcct`), nicht alle 2 s — spart I/O und beseitigt das Lese-Race auf eine halb geschriebene Pfadzeile. *Ehrliche Grenze:* der Latch wird nur bei `AccountNumber() > 0` gesetzt; ohne eingeloggtes Konto läuft der Schreibversuch bei jedem Zyklus erneut.

### Server: Ordner-Findung und Endpunkte
`allFilesDirs()` = `MAMAL_FILES` (Override) → sonst unter Windows alle `%APPDATA%\MetaQuotes\Terminal\<hash>\MQL4\Files`, davor die Beacon-Ordner (deckt Portable-Mode ab); unter macOS der bekannte Wine-Pfad. Verzeichnis-Scans und die Beacon-Liste sind **1,5 s gecacht** (das Dashboard pollt im Sekundentakt, die Pfade liegen oft auf OneDrive/AV-gescannten Laufwerken).
- **Ohne `?acct=`** gewinnt die **frischeste** `mamal_cockpit.json` (mtime). Der Legacy-Wegweiser hat seit v0.38 **keine** Priorität mehr — bei zwei live schreibenden Terminals sprang die Anzeige sonst zwischen den Konten.
- **Mit `?acct=`** (nur Ziffern, Pfad-Injektion ausgeschlossen): Konto-Beacon → aber **verifiziert** gegen `state.account` (Stale-Beacon nach Login-Wechsel) → sonst alle Ordner durchsuchen. `readState()` liefert **nie** Daten eines fremden Kontos unter dem angefragten Label.
Endpunkt-Liste in 9a (Server: Ordner-Findung und Endpunkte)

- Endpunkte: `/state`, `/accounts`, `/journal`, `/analytics`, `/day`, `/equity`, `POST /cmd/endday`, **`/trades`**, **`/trade?ticket=`**, **`/shot/<datei>`** (v0.62, Abschnitt 9b), `/i18n.js` (v0.53, Abschnitt 8b) sowie die Seiten `/` `/day.html` `/report.html` `/trade.html`; `/favicon.ico` wird mit 204 quittiert, alles Übrige mit 404. Der Server bindet auf `127.0.0.1` und prüft zusätzlich den Host-Header (DNS-Rebinding-Schutz). Der `acct`-Parameter wird **an einer Stelle** zentral auf Ziffern reduziert (`replace(/\D/g,'')`) und gilt danach für alle Endpunkte.


- `/journal` filtert **erst** (`OPEN`/`CLOSE`/`CLOSE_MAN`/`BLOCKED`, `PROTECT*`, Sperr-/Cooldown-/Ziel-Tags) und kappt **danach** auf 120 Zeilen (v0.45-Fix — vorher verdrängten periodische INFO-Zeilen echte Ereignisse).
- Das CSV-Parsing ist über **mtime+size** gecacht (max. 8 Einträge); der Tag-Freitext wird beim Split wieder zusammengesetzt, sonst geht bei einem `;` im Tag der `net`-Betrag verloren.

### Kommando-Kanal `mamal_cmd.txt` (strikt tighten-only)
Dashboard-Button „Tag beenden" → `POST /cmd/endday`. Server-seitige Absicherung: **nur POST**; **Origin-Check** (fehlt der Header, z. B. curl → ok; ist er gesetzt, muss er von `localhost`/`127.0.0.1:PORT` stammen — ein Cross-Site-Form-POST trüge sonst einen passenden Host-Header); **`acct` ist Pflicht** (sonst könnte die Sperre bei zwei live schreibenden Terminals im falschen Konto landen). Geschrieben wird `endday <timestamp>` als BOM-freies latin1 in den Files-Ordner **dieses** Kontos.

EA-Seite (am Ende von `Cycle()`, also nur auf dem Master): Datei lesen, **sofort löschen**, Prefix `endday` prüfen. Wirkung ausschließlich: `RG_LOCK_UNTIL` auf `NextServerMidnight()` — und **nur, wenn das die Sperre verlängert** (`nxt > cur`); eine bereits längere Sperre kann `endday` nie verkürzen, Lockern ist über diesen Kanal prinzipiell unmöglich. Danach **sofort** `GlobalVariablesFlush()` + `WriteLockstate()` (die Kommando-Datei ist schon weg; ein Crash im 1-s-Fenster darf die freiwillige Sperre nicht verlieren) und Journal-Event **`SELF_LOCK`**. Lässt sich die Datei nicht löschen (Read-Only/AV-Lock), wird das Kommando **ignoriert** und einmalig geloggt — sonst würde es im Sekundentakt erneut verarbeitet.

Event-Ergänzung zu Abschnitt 9 (in 9a)

*Ergänzung zu Abschnitt 9:* Zu den dort gelisteten Events kommen inzwischen **`SELF_LOCK`** (v0.39), **`PANEL_CLOSE`** (v0.40, Close-Buttons), **`CLOSE_MAN`** (v0.44, Abschnitt 7a), **`BREAKEVEN`** (v0.46, Knopf „RISK FREE" — Erfolg *und* Fehlschlag mit Error-Code werden geschrieben) und **`SLTP_MOVE`** (v0.47, Verhaltens-Tracking, Abschnitt 9b). Beim `OPEN`-Event trägt der Tag seit v0.52 zusätzlich das Kerzendrittel (`in-plan K2/3`, Abschnitt 9c).



### Equity-Sampler (im Server, nicht im EA)
Die Equity-Kurve entsteht **serverseitig** — der EA bleibt dafür unverändert. Alle **5 s** liest der Server die bekannten Konten und hängt für jedes **live schreibende** Konto eine Zeile `epochMs;equity;dayBase` an `cockpit/data/equity_<konto>.csv` an. Gefiltert wird: JSON älter als **15 s** → überspringen (kein Sampling toter Terminals); `equity` muss eine Zahl sein; die Konto-ID muss **rein numerisch** sein (v0.39-Fix — sonst kollidierten nicht-numerische IDs in `equity_.csv`).

**Begrenzung:** stündlich; Dateien `equity_<ziffern>.csv` ab **2 MiB** werden auf die letzten **20.000** Zeilen gekürzt (≈ 1 Tag bei 5 s). `/equity?acct=&n=` liefert die letzten `n` Punkte (Default 2000) als `{t, eq, base}`, unplausible Zeilen fallen raus; ohne `acct` wird das frischeste Konto genommen.

**Ehrliche Grenzen:** Auflösung 5 s, und gesampelt wird nur, solange **der Server läuft** — steht `node` still, entsteht eine Lücke, auch wenn MT4 weiterläuft. Der Wert stammt außerdem aus der JSON (2-s-Takt), ist also bis zu ~2 s alt. Die CSVs liegen im Projektordner (`cockpit/data/`), nicht in `MQL4/Files` — bei einem Neuaufsetzen des Cockpit-Ordners ist die Historie weg.

## 9b. Verhaltens-Tracking (`TrackSLTP`), Screenshots und Trade-Akte

Drei aufeinander aufbauende Teile: der EA **protokolliert** jede SL/TP-Verschiebung mit fachlichem Urteil (v0.47), er legt zu jeder Aktion ein **Bild mit Ticket im Dateinamen** ab (v0.47), und der Server baut daraus je Ticket eine **Trade-Akte** (v0.62). Keiner der Teile greift in Regeln ein — es ist reine Beobachtung.

### `TrackSLTP()` — wer den Stop wohin zieht
**Einordnung im Cycle:** direkt nach dem Close-Auflösungs-Block, **vor** dem Enforcement-Block. Drei Bedingungen müssen zugleich erfüllt sein: `!modifyQuiet`, `!IsTradeContextBusy()` und ≥ **2000 ms** seit dem letzten Lauf. Wie der gesamte Block läuft er **nur auf dem bestätigten Master** (der `g_masterStreak<2`-Rücksprung liegt davor).

**Warum nicht während `modifyQuiet`:** Wer eine SL-Linie mit der Maus zieht, erzeugt Dutzende Zwischenwerte. Ohne diese Sperre zählte jeder Zwischenschritt als eigene Verschiebung, und die Statistik „N-mal verschoben" wäre reines Rauschen. Gezählt wird erst das **Ergebnis nach dem Loslassen** (das Quiet-Fenster ist auf 2 s gleitend, hart gedeckelt auf 10 s Serie — Abschnitt 3).

**Reichweite:** `InScope(OrderMagicNumber()) || GlobalVariableCheck(RGOPN_<ticket>)` — identisch zur Regel bei `PanelBreakEven`. Ein Panel-Trade mit abweichender Magic bleibt damit erfasst; fremde EAs bleiben außen vor.

**Zustand pro Ticket** (GlobalVariables, überleben Neustart):

| Schlüssel | Inhalt |
|---|---|
| `RGSLS_<ticket>` | zuletzt gesehener **SL** |
| `RGTPS_<ticket>` | zuletzt gesehener **TP** |

Beim **ersten Sehen** eines Tickets (`firstSight`: beide Marker fehlen) werden die Marker nur gesetzt, **ohne** Journalzeile — sonst würde jeder EA-Start jede offene Position als „verschoben" melden. Als Rausch-Schwelle dient `eps = MarketInfo(sym, MODE_POINT)/2` (Fallback `Point/2`): Änderungen unterhalb eines halben Punktes gelten nicht als Verschiebung.

**Urteil** — bewertet wird der **Abstand zum Einstieg**, `dOld = |OrderOpenPrice() − alt|` gegen `dNew = |OrderOpenPrice() − neu|`:

| Fall | Bedingung | Tag im Journal (deutsch, unübersetzt) |
|---|---|---|
| SL erstmals gesetzt | `alt == 0` | „SL erstmals gesetzt" |
| SL entfernt | `neu == 0` | „SL ENTFERNT — Risiko unbegrenzt (nachteilhaft)" |
| SL weiter weg | `dNew > dOld+eps` | „SL WEITER weg vom Einstieg (alt -> neu) — **Risiko ERHOEHT (nachteilhaft)**" |
| SL näher heran | `dNew < dOld−eps` | „SL naeher an den Einstieg (alt -> neu) — Risiko gesenkt[, **Break-Even erreicht**] (vorteilhaft)" |
| SL seitlich | sonst | „SL seitlich verschoben (Risiko unveraendert)" |
| TP entfernt | `neu == 0` | „TP ENTFERNT — kein Ziel mehr definiert" |
| TP näher heran | `dNew < dOld−eps` | „TP NAEHER an den Einstieg (alt -> neu) — **Gewinn abgekuerzt**" |
| TP weiter weg | `dNew > dOld+eps` | „TP WEITER weg (alt -> neu) — Ziel vergroessert" |

Der Break-Even-Zusatz greift bei `(BUY && sl >= entry−eps) || (SELL && sl <= entry+eps)`. Jede erkannte Verschiebung erzeugt **eine** Zeile `SLTP_MOVE` (mit Ticket, Symbol, Richtung, Lot, Entry, neuem SL/TP; Risk%-Spalte bleibt 0) plus einen Screenshot `slmove` bzw. `tpmove`. SL und TP werden getrennt geprüft — eine Änderung beider Werte in einem `OrderModify` ergibt **zwei** Zeilen und **zwei** Bilder.

**Ehrliche Grenzen:**
- `TrackSLTP()` sieht nur *dass* sich der Wert geändert hat, nicht *wer* ihn geändert hat. Ein Klick auf **RISK FREE** (`PanelBreakEven`, `OrderModify` auf `OrderOpenPrice()`) erscheint deshalb im nächsten Lauf **zusätzlich** als `SLTP_MOVE` mit dem Urteil „Risiko gesenkt, Break-Even erreicht" und wird in der Trade-Akte als risikosenkende Verschiebung gezählt. Unterscheidbar ist der Vorgang nur über die parallele `BREAKEVEN`-Zeile.
- Die Marker `RGSLS_`/`RGTPS_` werden **nur an einer Stelle** gelöscht: in `ResolveByTicketRegistry()` (Pfad 2, Abschnitt 7a), unmittelbar nach `Shot("close")`. Löst **Pfad 1** (`ResolveHistory`) die Position auf — der Normalfall bei sichtbarer Kontohistorie —, springt Pfad 2 vorher per `IsProcessedAny(...) → GlobalVariableDel(RGOPN_) ; continue` heraus und erreicht die Aufräumzeile nie. Kein `PruneGV`-Aufruf deckt diese beiden Präfixe ab (sie tragen Preise, keine Zeitstempel, ein zeitbasierter Prune wäre auch falsch). Die Marker bleiben also bis zum **4-Wochen-Verfall** von MT4 stehen. Kollisionsgefahr besteht nicht (MT4-Tickets werden nicht wiederverwendet), es ist reiner GV-Ballast — bei hoher Trade-Frequenz aber messbar.

### Screenshots — Namensschema und Aufräumen
`Shot(tag, ticket)` schreibt per `ChartScreenShot` nach `MQL4/Files`:
```
Mamal_<ticket>_<tag>_<epoch>.png        epoch = (int)SrvTime()
```
Gesteuert über `InpScreenshots` (seit v0.47 Default **an**) sowie `InpShotWidth`/`InpShotHeight` (1100 × 620). `ticket = 0` bedeutet „kein Trade-Bezug". Es gibt genau **vier** Tags:

| Tag | Aufrufstelle |
|---|---|
| `open` | `DoEntry()` unmittelbar nach erfolgreichem `OrderSend` |
| `close` | `ResolveByTicketRegistry()` nach der Wertung der Gruppe |
| `slmove` / `tpmove` | `TrackSLTP()` je erkannter Verschiebung |

Das Ticket **im Dateinamen** ist der ganze Trick: Server und Dashboard ordnen jedes Bild ohne Zusatzindex genau einem Trade zu, der Epoch-Anteil hält die Chronologie.

`PruneShots()` läuft im **60-s-Housekeeping** (nicht im Enforcement-Takt): `FileFindFirst("Mamal_*.png")`, Zeitstempel = Ziffernblock **hinter dem letzten `_`**, gelöscht wird alles älter als `InpShotKeepDays` (Default 14; `0` = nie aufräumen). Harte Bremse: **maximal 200 Löschungen pro Durchlauf** (`killed<200` in der Schleifenbedingung) — sonst blockiert ein einzelner Durchlauf den Cycle mit Datei-I/O, was unter Wine der bekannte Crash-Pfad ist. Der Rest folgt im nächsten Housekeeping.

*Ehrliche Grenzen:* Ein Dateiname ohne parsbaren Zeitstempel wird dauerhaft übersprungen. Und der Screenshot zeigt immer **den Chart, auf dem der Aufruf stattfindet** — `open` liegt im Klick-Pfad (also der Chart, auf dem gehandelt wurde), `close`/`slmove`/`tpmove` laufen dagegen auf dem **Master**-Chart. Bei mehreren Symbolen kann das Ausstiegs-Bild also ein anderes Instrument zeigen als der Trade. Zusätzlich entsteht das `close`-Bild **nur**, wenn Pfad 2 die Position tatsächlich auflöst; wird sie von Pfad 1 gewertet (Regelfall), gibt es kein Ausstiegs-Bild.

### Trade-Akte im Cockpit (v0.62): `/trades`, `/trade`, `/shot`

| Endpunkt | Verhalten |
|---|---|
| `/trades` | `tradeList(acct)` — gruppiert **alle** Journalzeilen nach Ticket (`ticket` leer oder `0` wird verworfen). Aus der `OPEN`-Zeile stammen Zeit/Symbol/Richtung/Kerzendrittel, `SLTP_MOVE` wird gezählt, `net` kommt aus der ersten `CLOSE`-Zeile mit Netto. Sortiert nach Zeit absteigend, **gedeckelt auf 200** Tickets. |
| `/trade?ticket=` | `tradeDossier(...)` — `ticket` vorher auf Ziffern reduziert (`replace(/\D/g,'')`). Sammelt `OPEN`, die erste `CLOSE` mit Netto, alle `SLTP_MOVE`, alle `PANEL_CLOSE` und alle `BREAKEVEN`. |
| `/shot/<datei>` | liefert das PNG aus dem Files-Ordner des Kontos (siehe Pfad-Ausbruch-Schutz unten). |
| `/trade.html` | die Seite selbst (Liste ohne `ticket`, Akte mit `ticket`). |

**Kennzahlen der Akte** (`stats`): `moves` (Anzahl Verschiebungen), `slWorse`/`slBetter`/`tpShorter`/`tpLonger` (Klassifikation per Regex über die deutschen Tags, siehe Tabelle oben und Abschnitt 8b), `plannedRisk`, `net`, `third`.

**Geplantes Risiko in Kontowährung** wird aus **derselben** `OPEN`-Zeile rekonstruiert:
```
plannedRisk = Balance(Spalte 4) · Risk%(Spalte 14) / 100
```
Bewusst die Balance **dieser Zeile** und nicht die heutige — sonst verschöbe sich das geplante Risiko rückwirkend mit jedem Kontostand.

**Automatische Zusammenfassung** (`summary`, Klartext-Sätze in fester Reihenfolge): Eröffnung mit Lot/Uhrzeit/geplantem Risiko → Kerzendrittel-Einordnung → Verschiebungs-Bilanz (bzw. „SL und TP blieben unverändert — der Plan wurde eingehalten") → Warnsatz bei `slWorse` → Lob bei ausschließlich risikosenkenden Zügen → Hinweis bei verkürztem Ziel → RISK-FREE- und Panel-Close-Vermerke → Ergebnis. Bei geschlossenen Verlust-Trades folgt der **Abgleich Plan gegen Ergebnis** mit Schwellenfaktor **1,15**:
- `|net| > plannedRisk · 1,15` → „Der Verlust liegt X,X× über dem geplanten Risiko — Ursache prüfen (verschobener Stop, Slippage oder Gap)."
- sonst → „Der Verlust blieb im geplanten Rahmen — genau so soll ein Stop wirken."

**Screenshots** kommen aus `shotsFor(ticket, acct)`: `readdirSync` des Konto-Files-Ordners, Filter `^Mamal_<ticket>_([a-z0-9]+)_(\d+)\.png$`, sortiert nach Epoch → Einstieg, Verschiebungen und Ausstieg liegen chronologisch nebeneinander (Vollbild-Zoom in `trade.html`).

**Pfad-Ausbruch-Schutz bei `/shot/`** — drei Stufen, in dieser Reihenfolge:
1. `decodeURIComponent(p.slice(6))` **zuerst**, Prüfung **danach**. Diese Reihenfolge ist der eigentliche Schutz: `%2e%2e%2f` wird erst zu `../` aufgelöst und fällt dann durch die Prüfung. Eine Prüfung vor dem Dekodieren wäre umgehbar.
2. Whitelist statt Blacklist: `/^Mamal_\d+_[a-z0-9]+_\d+\.png$/i` — der Name darf **ausschließlich** aus diesem Muster bestehen. Slash, Backslash, `..`, Laufwerksbuchstabe, Nullbyte und Unicode-Varianten scheitern daran alle, ohne dass sie einzeln aufgezählt werden müssten. Verstoß → `400`.
3. Erst danach `path.join(dir, name)` mit `dir = dirForAccount(acct) || currentFiles()` — es wird also nie aus einem anderen als einem bekannten `MQL4/Files`-Ordner gelesen. Fehlt die Datei → `404`.

Ausgeliefert wird mit `Content-Type: image/png` und `Cache-Control: max-age=86400`; das ist unbedenklich, weil der Epoch-Anteil den Dateinamen faktisch unveränderlich macht.

**Zugang:** 📁-Knopf im Dashboard-Kopf (öffnet `/trade.html` in einem neuen Tab); zusätzlich sind Journal-Zeilen **mit Ticket** anklickbar und springen direkt in die Akte.

**Ehrliche Grenzen:**
- Die Akte entsteht **allein** aus Journalzeilen und Dateinamen — es gibt keine Broker-Abfrage. Fehlt die `OPEN`-Zeile (gelöschtes Journal, manueller Trade, Trade vor v0.47), gibt es weder geplantes Risiko noch Kerzendrittel; ohne `InpScreenshots` gibt es keine Bilder.
- Die Klassifikation der Verschiebungen liest den **deutschen** Tag-Text. Wer die Journal-Texte übersetzt, setzt `slWorse`/`slBetter`/`tpShorter`/`tpLonger` still auf 0 (Abschnitt 8b).
- `/trades` ruft `shotsFor()` **je Ticket** auf, und `shotsFor()` macht jedes Mal ein eigenes `readdirSync` — bei 200 Tickets also bis zu 200 ungecachte Verzeichnis-Scans pro Aufruf. Auf OneDrive-/AV-gescannten Laufwerken (Abschnitt 9a) ist die Liste dadurch spürbar träge. Der 1,5-s-Cache der Ordner-Findung greift hier **nicht**.
- Die Akte ist ausschließlich deutsch (weder `trade.html` noch die `summary`-Sätze hängen an `/i18n.js`).



---

## 9c. Kerzendrittel — Einstiegs-Timing innerhalb der laufenden Kerze

**Frage, die beantwortet wird:** Wird früh in der Kerze gehandelt (eigene Entscheidung) oder spät (Reaktion auf eine bereits gelaufene Bewegung)? Bisher zeigte das Cockpit nur *wann am Tag* geklickt wurde, nicht *wo in der Kerze*.

### Erfassung im EA (v0.52)
```
int CandleThird(datetime t)
{
   int per = PeriodSeconds();  if(per<=0) return 0;
   int el  = (int)(t % per);   if(el<0) el=0;      // verstrichene Sekunden in der Kerze
   int th  = (el*3)/per;       if(th>2) th=2;      // 0 = früh, 1 = mittig, 2 = spät
   return th;
}
string CandleThirdTag(datetime t){ return StringFormat("K%d/3", CandleThird(t)+1); }
```
Die Modulo-Rechnung nutzt aus, dass MT4-Kerzen auf einem festen Raster liegen (`Time[0]` ist stets ein Vielfaches von `PeriodSeconds()`) — es braucht keinen Zugriff auf die Bar-Serie und keine Sonderfälle für die erste Kerze.

`DoEntry()` hängt das Ergebnis an den Tag der `OPEN`-Zeile: `"in-plan " + CandleThirdTag(TimeCurrent())` → z. B. `in-plan K2/3`. Das Format ist bewusst maschinenlesbar (`K1/3` … `K3/3`) und steht in derselben Spalte wie der Freitext, damit kein CSV-Feld hinzukommt (Abschnitt 9 bleibt bei 18 Spalten).

**Zeitbasis ist `TimeCurrent()`, nicht `SrvTime()`** — und das ist kein Versehen: Das Kerzenraster liegt in **Broker-Zeit**, und `Time[0]` stammt aus derselben Quelle. `SrvTime()` (PC-Uhr + gepflegter Offset, Abschnitt 4) könnte bei stehendem Offset um Sekunden danebenliegen und das Drittel falsch bestimmen. *Ehrliche Grenze:* `TimeCurrent()` steht ohne frische Ticks still — in einem sehr tickarmen Markt kann das Drittel deshalb zu **früh** ausgewiesen werden. Für ein Drittel einer M1-Kerze (20 s) ist das relevant, für M15 praktisch nicht.

### Countdown direkt neben der Kerze (`DrawCandleClock`, v0.52)
Zusätzlich zum Countdown im Panelkopf zeichnet der EA ein `OBJ_TEXT` (`MMT_cclock`) **auf den Chart**, verankert auf `Time[0] + PeriodSeconds()` (ein Slot rechts der laufenden Kerze) auf Höhe des aktuellen Bid, mit `ANCHOR_LEFT` — es wandert also mit der Kerze mit. Text `mm:ss` (Restzeit), Schrift `InpPanelMono` in `PF(9)` (Abschnitt 8a). Die Farbe folgt dem **verstrichenen** Drittel und damit exakt derselben `CandleThird()`-Logik wie die Protokollierung: grün → orange → rot. Gesteuert über `InpCandleTimeOnChart && InpShowCandleTime`; ist eines aus, wird das Objekt gelöscht statt nur versteckt.

### Auswertung im Cockpit
`analytics()` führt drei parallele Strukturen:
- `thirds[3]` — Anzahl Einstiege je Drittel, gesamt **und** pro Kalendertag (`d.thirds`),
- `byTicketThird[ticket]` — Ticket → Drittel aus der `OPEN`-Zeile (Regex `\bK([123])\/3\b`),
- `thirdNet[3]` — **Netto je Drittel**; die `CLOSE`-Zeile findet ihr Drittel über `byTicketThird`.

Erst die Kombination trägt die Aussage: Häufigkeit allein sagt nichts, entscheidend ist, in welchem Drittel tatsächlich Geld verdient wird. Das Dashboard zeigt das als Kachel **„Einstieg in der Kerze"** — drei Zähler `früh · mittig · spät` in Grün/Amber/Rot, Tooltip je Drittel mit Anzahl und Netto, darunter der Satz „am besten läuft **<Drittel>** (<Netto>)" mit dem Drittel des höchsten Nettos. Die Kachel wird ausgeblendet, wenn kein einziger Einstieg ein Drittel trägt (Journal vor v0.52). Die Trade-Akte (Abschnitt 9b) übersetzt dasselbe Feld einzeln in Klartext („Einstieg im letzten Kerzendrittel — spät; oft eine Reaktion auf eine schon gelaufene Bewegung.").

**Ehrliche Grenzen:** Das Drittel bezieht sich auf den **Timeframe des Charts, auf dem geklickt wurde** — dieselbe Uhrzeit ergibt auf M1 und M15 verschiedene Drittel; die Aggregation über mehrere Timeframes mischt daher Ungleiches. Und `thirdNet` ordnet das Ergebnis über das Ticket zu: Teil-Closes desselben Tickets summieren korrekt, ein Trade ohne `OPEN`-Zeile im geladenen Journal fällt komplett aus der Zuordnung.

---

## 10. Crash-Hardening (MetaTrader auf Wine/Apple Silicon)


## 11. Wichtige Parameter (Defaults v0.16)
Risiko: `InpRiskPerTradePct=0.25`, `InpRiskTolFactor=1.10`.
Auto-Scale: `InpAutoScale=true`, `InpIdeaXrisk=2`, `InpHeatXidea=2`, **`InpDayXidea=4`** (v0.20 → Tag 2,0 % = 400 €) (Fallback fix: `InpIdeaCapPct=1`, `InpPortfolioHeatPct=2`, `InpDailyRiskBudgetPct=2`).
Verlust: `InpDailyLossPct=2`, `InpMaxLossPct=6`, `InpMaxLossWarnPct=5`, `InpWeeklyLossPct=5`.
Serien: `InpCooldownAfter=3`, `InpCooldownMin=45`, `InpLockAfter=5`, `InpDeRiskAfter=2`, **`InpDeRiskFactor=1.0`** (R19 AUS, v0.20).
Ziel: `InpDailyTargetPct=3`, `InpGivebackArmPct=1`, `InpGivebackPct=1`.
Ausführung: `InpRR=2`, **`InpMinRR=0`** (R8 AUS, v0.20), **`InpMinStopPips=0`** (R15 Min-SL AUS, v0.22 — M1-Scalping braucht enge Stops), **`InpMaxLot=0`** (R15 Lot-Cap AUS), **`InpMinGapSec=0`** (R14 AUS, v0.20), **`InpRevengeMin=0`** (R25 AUS, v0.20), `InpRequireSL/TP=true`, **`InpSLTPGraceSeconds=4`** (v0.33; Anker = SL/TP-Entfernung), `InpSLTPGraceNews=0`.
Korrelation/Session: `InpUseCorrCap=true`, `InpCorrCapPct=1.5`, `InpUseSession=false`, `InpSessionStart=8`, `InpSessionEnd=22`, `InpNewsFrom/To=0`.
Technik: `InpMagic=990201`, `InpSlippage=30`, `InpTimerSeconds=1`, `InpMinActionMs=500`, `InpPanelMs=1500`, `InpUseAlert=false`, `InpJournal=true`, `InpScreenshots=false`, `InpFomoGate=false`.
v0.21 (SL-Bedienung): `InpSlClicksToMove=3` (Klicks in dieselbe Zone zum SL-Setzen; 1=sofort), `InpSlZonePips=10` (Zonen-Toleranz-Untergrenze).
Close-Queue (v0.16): `InpCloseThrottleMs=300`, `InpCloseRetries=5` (max Versuche je Ticket vor FINAL-FAIL), `InpCloseBackoffMs=400` (Basis-Backoff, verdoppelt je Versuch), `InpCloseMaxBackoffMs=4000`.
v0.17: `InpPropFirm=PF_FTMO` (Profil-Label), `InpFundedMode=false` (erzwingt TOOL_ONLY + sperrt TestMode), `InpSLTPGraceNews=0` (R7-Grace im News-Blackout), `InpTestMode=false` (Rule-Test-Harness, nur Demo), `InpSLTPGraceSeconds` Default 10→**5** *(v0.33 abgelöst: →**4 s**, Anker = SL/TP-Entfernung statt `OrderOpenTime`)*.
v0.35 (R22 Nur Panel-Trades): **`InpCloseManualTrades=true`** (Default **an**) — jede Order mit `OrderMagicNumber()==0` wird geschlossen bzw. gelöscht, **kontoweit über alle Symbole**, unabhängig von `InpWatchScope` und unabhängig von aktiven Sperren. `false` = R22 aus; die Regel erscheint dann im Cockpit-JSON in der `disabled`-Liste (Dashboard-Chip „— aus"). Erkennungs-Takt und Verzögerung ergeben sich aus `InpTimerSeconds`/`InpMinActionMs` + `InpCloseThrottleMs` + ggf. Modify-Quiet-Fenster (siehe Abschnitt 12).
v0.19 (Prop-Firm-Zeitprofil): `InpDayResetHour=0` (Tagesreset-Stunde in Server-Zeit, 0=Mitternacht=FTMO; verschiebt `ServerDayKey`/`NextServerMidnight`/R3-Tagesschlüssel), `InpWeekStartDay=0` (Wochenstart 0=Sonntag..6=Samstag, R18). Default 0/0 = bisheriges Verhalten. **`InpInitialBalance` Default jetzt 0 = auto** (echte Kontobasis; auf Nicht-20k explizit setzen).

## 11. Wichtige Parameter (Defaults v0.16) — Nachträge v0.46–v0.53

v0.46 (Bedienung/Darstellung): `InpBreakEvenBtn=true` (Knopf „RISK FREE" — zieht den SL aller Positionen **im Gewinn** auf `OrderOpenPrice()`; prüft `MODE_STOPLEVEL`, lockert einen SL nie, läuft auch bei Sperre/Cooldown, fasst fremde Magics nicht an), `InpBreakEvenBufferPts=0` (Zusatzpuffer in Punkten; 0 = exakt Einstieg — der Spread steckt bereits darin, weil MT4 BUY zum Ask öffnet und zum Bid schließt; der Puffer deckt die Kommission), `InpTpLine=false` (ziehbare TP-Linie; gesetzt hat sie Vorrang vor `InpRR`, aber nur auf der richtigen Seite des Einstiegs), `InpShowSpread=true`, `InpShowCandleTime=true`, `InpFontScale=1.0`, `InpShapeScale=1.0`, `InpPanelAutoFit=true` (alle drei: Abschnitt 8a).
v0.47 (Analyse): **`InpScreenshots` Default jetzt `true`**, `InpShotWidth=1100`, `InpShotHeight=620`, `InpShotKeepDays=14` (0 = nie aufräumen; Löschdeckel 200 pro Durchlauf) — Abschnitt 9b.
v0.49–v0.52 (Wochen-Risiko + Kerze): **`InpRequireWeeklyRisk=true`** (ohne festgelegtes Wochen-Risiko wird **nicht gehandelt**: Panel-Status „RISIKO FESTLEGEN", BUY/SELL ausgegraut; die Bestätigung verfällt jede Woche — **v0.62**: `RG_WEEK_RISK_IDX` wird nur noch von `SetWeekRisk()` gesetzt, der Wochen-Roll fasst ihn nicht mehr an; der **Wert** wandert weiter, damit R1 keine Wochenend-Positionen zwangsschließt, und eine **Vormerkung** wird erst durch SETZEN aktiv), `InpRiskChooser=true` (seit v0.49 Eingabefeld `OBJ_EDIT` + Knopf „SETZEN" statt `[-]`/`[+]`; Dezimalkomma wird akzeptiert), `InpRiskStep=0.05`, `InpRiskMaxPct=1.00` (harte Kappe bleibt 1,0 %), `InpCandleTimeOnChart=true` (Countdown neben der laufenden Kerze, Abschnitt 9c).
v0.53 (Sprache): `InpLang=LANG_DE` (`enum PanelLang { LANG_DE, LANG_EN }`) — betrifft **nur** das On-Chart-Panel und die EA-Meldungen; das Dashboard schaltet unabhängig davon um, das Journal bleibt in jedem Fall deutsch (Abschnitt 8b).


---

## 12. Bekannte Grenzen / offene Punkte
1. **Erkennen-und-schließen, nicht verhindern:** ~0,5 s Reaktionszeit (Polling); kurzes Fenster für Verstöße, gedeckelt durch R4/R4b. (Für R22 genauer aufgeschlüsselt in Punkt 10 — dort können es auch mehrere Sekunden sein.)
2. **No-Override lokal = Reibung:** Als Admin abschaltbar (EA entfernen, GV löschen). Echtes Immutable nur via VPS ohne eigenen Admin + FTMO-Serverlimit.
3. **Mac/Wine instabil** für Dauerbetrieb → VPS.
4. **R16 News** nur Zeitfenster/manuelles Blackout — automatische News-Erkennung braucht einen Kalender-Feed (geplant via Server/Cockpit).
5. ~~R25 Revenge in-memory~~ → **seit v0.17 persistent** (GlobalVariables `RG_REVD_`/`RG_REVU_`, überlebt Neustart). *(erledigt)*
6. **Zwei Basen (nicht verwechseln):** Tagesverlust (R4) rechnet gegen die **Tagesstart-Equity** (`MathMax(Balance,Equity)`, beim Aufziehen/Mitternacht erfasst — EA muss ab Session-Start durchlaufen); Gesamtverlust (R4b) gegen das **Startkapital** (`InpInitialBalance`, Default **0 = auto = echte Kontobasis** seit v0.18-B1, persistiert in `RG_INIT_BAL`). Auf Nicht-20k-Konten `InpInitialBalance` = echte Challenge-Startbalance setzen.
7. **MT5-Spiegel** (`MamalTrading.mq5`) noch nicht gebaut.
8. **v0.17 kompiliert (F7 = 0 Errors)** — gesamter Batch (R25-persist, Audit-Journal, R17-Vektor, R7-Härtung, TickValue-Fallback, Funded-Gate, Profil, TestMode) compile-clean. **Noch ungetestet:** Rule-Test-Harness/Regelmatrix + Demo-Forward-Test stehen aus.
9. **Compliance (ehrlich, nicht „rein passiv"):** der EA generiert **keine Entry-Signale** (Mensch klickt), **platziert** aber per One-Click `OrderSend` und **schließt/blockt autonom** (Risk-Management-Automation; **kein** `OrderModify` — SL/TP nur beim Senden) = „diskretionärer Entry + automatisiertes Risk-Management". Vor Real/Funded **Prop-Firm-Regel-Compliance** prüfen (pro Firma; FTMO = Default-Profil) — Details + Quellen in `COMPLIANCE.md`. **Seit v0.35 zusätzlich:** mit R22 schließt der EA auch im FundedMode Positionen, die er **nicht selbst geöffnet** hat, und weicht damit als einzige Enforcement-Funktion vom `InScope()`-Sicherheitsdesign ab. Firmenspezifisch verifizieren; der bestehende Warnhinweis bei `ALL_POSITIONS` deckt diesen Fall **nicht** ab, weil R22 unabhängig vom Scope wirkt.
10. **R22 ist detect-and-revert, nicht Prävention (ehrliche Grenze):** Der manuelle Trade wird **eröffnet** und danach zu **Marktpreis** geschlossen — Spread und Slippage trägt der Trader. Aus dem Code ableitbar ist nur die **Erkennungs-Latenz**: Timer 1 s bzw. Tick ≥500 ms, plus Close-Throttle 300 ms, plus ggf. bis zu 2 s Modify-Quiet (hart gedeckelt auf 10 s Serie — wer dauernd an SL/TP zieht, verzögert R22 also), plus Retry/Backoff bei Fehlern. Realistisch: **Bruchteile einer Sekunde bis mehrere Sekunden**; bei geschlossenem Markt (err 132) bis zu 15 min pro Versuch. Läuft der EA nicht, ist AutoTrading aus oder scheitert `EventSetTimer`, greift R22 gar nicht — wie das gesamte Enforcement. Nach `InpCloseRetries` Fehlversuchen fällt das Ticket mit FINAL-FAIL aus der Queue und **bleibt offen**; es wird beim nächsten `EnforceManualTrades()`-Durchlauf allerdings erneut eingereiht (dedupliziert werden nur laufende Queue-Einträge).

---

## 13. Installation & Build
1. `MamalTrading.mq4` nach `…/MQL4/Experts/` kopieren.
2. MetaEditor (F4) → Datei öffnen → **F7 kompilieren** (0 errors).
3. MT4: EA auf einen Chart ziehen → „Allow live trading" → AutoTrading an.
4. Im „Experten"-Tab erscheint `Mamal-Trading v0.35 aktiv (<Symbol>). Scope=… Profil=… Funded=… Test=… SL-Klicks=… R15-min-SL=… Cockpit=…(Port …). UNGETESTET bis F7=0 Errors.` (Versions-String kommt aus `EA_VER`).

---

## 14. Versionsverlauf (Kurz)
- v0.1 EA-Boden: R4 Tagesverlust, R4b Max-Loss, R7 SL/TP, Persistenz.
- v0.2 Crash-Härtung (Drossel, Context-Guard, Alert aus), Tamper-Warnung, Panel.
- v0.3 R1 Risiko/Trade.
- v0.5 Rebrand „Mamal-Trading", Pro-Panel mit Balken.
- v0.6 Risk-based One-Click-Entry (SL-Linie + BUY/SELL).
- v0.7 Panel-Redraw stark reduziert (Drag-Crash).
- v0.8 Trades nur aus OnTick.
- v0.9 Voll: R2/R3/R5/R6/R8/R9/R11.
- v0.10 SL-Entfernen-Loch geschlossen (Tool-Trade sofort zu).
- v0.11 R12 Gesamtrisiko, R13 Tagesziel+Giveback, R15 Min-SL/Max-Lot.
- v0.12 R14 Mindestpause, R16 Session/News, R17 Korrelation, R18 Wochenlimit, R19 De-Risk.
- v0.13 R14 → 10 s, R25 Revenge-Fenster.
- v0.14 Risiko-Default 0,25 %, dynamische Auto-Scale-Caps.
- v0.15 P0/P1-Patches aus REVIEW-v0.14.md → **F7 = 0 Errors** (Compile-Checkpoint).
- v0.16 (in Arbeit) Close-Queue + Lockstate-Datei + Schutz-aus-Logging (siehe unten).

## v0.15 — Änderungen ggü. oben (korrigiert frühere Aussagen)
- **Enforcement nicht mehr „nur OnTick".** `Cycle()` läuft aus OnTick *und* OnTimer (1 s) → Schutz greift tickunabhängig (P0-1). Close-Operationen sind per `InpCloseThrottleMs` (300 ms) gedrosselt + `IsTradeContextBusy`-Guard. (Die volle Close-Queue mit Retry-Limit/Backoff ist in **v0.16** gebaut — siehe unten.)
- **Verlustserie (R5/R6/R19/R25) history-basiert.** Statt flüchtigem `g_known` jetzt `ResolveHistory()` über `MODE_HISTORY`, idempotent per Wasserstand `RG_LAST_CLOSE` (CloseTime-sortiert), Teil-Schliessungs-Schutz via `HasOpenRemainder`. Überlebt Neustart (P0-2/P0-4).
- **EA-Schutz-Closes persistent ausgeschlossen.** `RGEAC_<ticket>`-GlobalVariables (statt in-memory) → eigene Closes zählen auch nach Crash/Neustart nicht als Verlust (P0-3).
- **Tagesbasis** = `MathMax(Balance,Equity)` (P0-5); Erststart mitten am Tag = `max(InitialBalance,Balance,Equity)` + `BaseWarn` (blockt neue Trades) bzw. manuelle `InpDayStartBase` (wird nachträglich übernommen) (P1-2).
- **WatchScope (`InpWatchScope`)**: `TOOL_ONLY` (Default, fremde Magics unangetastet) / `TOOL_PLUS_MANUAL` (+Magic 0) / `ALL_POSITIONS` (fasst ALLES an — nur Demo/Debug, **nicht Real/Funded**; bei jeder Prop Firm hart `TOOL_ONLY`) (P1-11).
- **Umgesetzt (ungetestet):** R4b MaxLoss 6 % + Warn-Gate 5 % (C), sofortiger Flush bei allen Sperr-States. **v0.15 → F7 = 0 Errors bestätigt (Compile-Checkpoint).**

## v0.16 — Close-Queue + Lockstate + Schutz-aus-Logging (gebaut, UNGETESTET)
- **P0-3 sofort-Flush:** `MarkEaClosed()`/`UnmarkEaClosed()` flushen jetzt sofort (`GlobalVariablesFlush()`) → ein Crash direkt nach einem EA-Schutz-Close kann den `RGEAC_`-Marker nicht mehr verlieren (sonst würde der Schutz-Close später fälschlich als Trader-Verlust zählen).
- **Echte Close-Queue:** Die Enforce-Funktionen (R7/R1/R8/R12) und `SafeCloseAll` **schließen nicht mehr direkt**, sondern reihen Tickets via `RequestClose(ticket,lots,reason)` ein (dedupe pro Ticket). `ProcessCloseQueue()` arbeitet die Queue ab: pro Versuch `RefreshRates()`, `MarkEaClosed`+Flush **vor** dem `OrderClose`, bei Fehler `UnmarkEaClosed`+Flush (kein falsches EA-Close-Label bei Broker-SL), Error-Code-Klassifikation (`IsRetryableClose`: transient → exponentieller Backoff `InpCloseBackoffMs`×2^n bis `InpCloseMaxBackoffMs`; hart → max-Backoff + schneller Richtung Limit), Retry-Limit `InpCloseRetries`. **Journal je Versuch:** `Queue OK` / `Queue RETRY n err=…` / `Queue FINAL-FAIL …` / `Queue DELETE …` (Pendings). Nach FINAL-FAIL fällt das Ticket raus und wird im nächsten Cycle ggf. neu erkannt (gepaced) — der Watchdog gibt nie dauerhaft auf.
- **Lockstate-Datei (fail-closed):** `MamalTrading_Lockstate.dat` spiegelt die Sperr-States mit HMAC-light-Checksumme. `ReconcileLockstate()` beim Start übernimmt den **restriktivsten** Zustand aus GV + Datei; **beschädigt/manipuliert → fail-closed** (Tagessperre + `TAMPER`-Journal). `WriteLockstate()` hält die Datei am Cycle-Ende aktuell (nur bei Änderung → Disk). Hinweis: rein lokal = Reibung; echtes Immutable erst auf gesperrtem VPS + FTMO-Serverlimit.
- **Schutz-aus-Logging:** AutoTrading-aus/-an wird als `PROTECT_OFF`/`PROTECT_ON` ins Journal geschrieben; `OnDeinit` (EA entfernt/Chart zu) loggt ebenfalls `PROTECT_OFF` mit `reason`.

### R3-Reconciliation (v0.16, nachgezogen)
`RG_DAY_RISK` lebt nicht mehr nur additiv nach `OrderSend`. `ReconstructedDayRiskPct()` rekonstruiert das **heute eröffnete** Tool-Risiko aus Broker-Daten: offene + heute geschlossene Positionen mit `OrderMagicNumber()==InpMagic`, gefiltert auf `DayKeyOf(OrderOpenTime())==heute` (gestern eröffnet zählt NICHT), per `ProcKey` gruppiert (Partial-Closes summieren zur Entry-Lotzahl, **jede Position einmal**); fehlender SL/Tickdaten → konservativer Boden `InpRiskPerTradePct` + `INFO`-Journal. `ReconcileDayRisk()` setzt `RG_DAY_RISK = max(persistiert, rekonstruiert)` (nur RAISEN, **kein Refund**) + Flush + `INFO`-Journal. Aufruf: in `OnInit` (Crash-/Restart-Recovery), in `Cycle()` gedrosselt (15 s) und in `DoEntry` direkt vor dem R3-Gate.

**Einheitlich EINE %-Basis (v0.16-Korrektur):** Sowohl der additive Pfad als auch die Rekonstruktion rechnen R3 über `DayRiskBase()` (= stabile Tagesbasis `RG_DAYSTART_EQ`, Fallback Initial-Balance/Equity) via `RiskPctOfBase(sym,lots,open,sl,base)`. In `DoEntry` wird dafür ein separates `r3rp` berechnet und für R3-Gate **und** `RG_DAY_RISK +=` benutzt — das normale `rp` (Live-Equity aus `CalcLot`) bleibt für Anzeige, R1/R2/R12/R17 und das OPEN-Journal. So driften additiver und rekonstruierter Tagesverbrauch nicht mehr auseinander. Ehrliche Grenze: rekonstruiert wird mit dem aktuellen/letzten SL (nicht dem Entry-SL) → Best-Effort-Backstop; der persistierte additive Wert bleibt maßgeblich, sobald er da ist.

**v0.16-Nachträge:** `ERR_MARKET_CLOSED` (132) als transienter Fehler in `IsRetryableClose`; ungenutztes `g_qLots` aus der Close-Queue entfernt (Lots werden beim Close live aus `OrderLots()` gelesen → partial-close-fest).
- **Erledigt (gebaut, ungetestet):** R3-Reconciliation (Single-Basis), `TimeCurrent`→tickunabhängige Server-Zeit `SrvTime()` (PC-Uhr+Offset; MQL4 hat kein `TimeTradeServer`), **+ die komplette v0.17-Batch (siehe unten).** **Noch offen (prozessual/Infra, siehe `docs/PROP-FIRM-READINESS.md`):** **Rule-Test-Harness-Matrix grün durchspielen + Demo-Forward-Test + Prop-Firm-Regel-Compliance pro Firma + Windows-VPS**. **F7 = 0 bis SrvTime; F7 für v0.17 steht aus.**

## v0.17 — Code-Vollausbau Richtung Prop-Firm-ready (gebaut, UNGETESTET, F7 ausstehend)
- **#6 R25 persistent:** Revenge-Fenster in GlobalVariables (`RG_REVD_`/`RG_REVU_`), `PruneRevenge` räumt auf, überlebt Restart (In-Memory-Arrays entfernt).
- **#7 Audit-Journal:** `Journal()` füllt Kontext automatisch (ServerTime, DayKey, Account, Balance, Equity, Magic, RuleId-aus-Tag) + optional Ticket/Net; Header beim ersten Schreiben; Aufruf-Stellen unverändert.
- **#8 R17 Währungsvektor:** `SplitCcy`/`AddExposure`/`MaxCurrencyExposurePct` statt USD-only; je Position Basis-(long)/Quote-(short)-Belastung, größte |Netto-Währungs-Exposition| ≤ `InpCorrCapPct`; Cross-Pairs zählen zusammen, Nicht-FX = Einzel-Bucket.
- **#9 R7-Härtung:** `EnforceSLTP`-Frist ab `OrderOpenTime()` (restart-fest, Naked-Liste entfernt); News-Blackout → `InpSLTPGraceNews` (Default 0); Tool-naked = sofort; Default-Grace 10→5 s. **⚠ v0.33 abgelöst** — Anker ist jetzt die **SL/TP-Entfernung** (Naked-Uhr pro Ticket, persistent + Heilfrist), Grace **4 s**, Tool-Trades ohne Sonderfall. Aktueller Stand: Abschnitt 7 (Regel-zu-Code) und 11 (Parameter).
- **#10 TickValue-Robustheit:** `TickVal()` mit Fallback `TickSize×LotSize`, falls `MODE_TICKVALUE`=0, + 1×/Tag-Warnung → Risiko erscheint nie fälschlich als 0; genutzt in `RiskPctOf`/`RiskPctOfBase`/`CalcLot`.
- **#11 Funded-Hard-Gate:** `InpFundedMode=true` erzwingt `InpWatchScope=TOOL_ONLY` und deaktiviert `InpTestMode` (Laufzeit-Override der `extern`-Variablen in `ApplyFundedAndProfile`).
- **#13 Prop-Firm-Profil:** `enum PropFirm` + `InpPropFirm` + `PropFirmName` → Label/Log/`PROFILE`-Journal. Limit-Zahlen bleiben Inputs (nicht-FTMO-Presets bewusst NICHT geraten — pro Firma verifizieren).
- **#14 TestMode-Harness:** `InpTestMode` (nur Demo, in FundedMode hart aus) blendet Panel-Buttons ein (`TestAction`): Cooldown/DayLock/MaxLock/Revenge/Corrupt-Lock(+Reconcile→fail-closed)/Reset — manipuliert **nur Zustand/Datei, öffnet keine Trades**.
- **Adversarial verifiziert** (Workflow, 6 Lenten inkl. striktem MQL4-vs-MQL5-Funktions-Audit) — 0 bestätigte Befunde. **F7 = 0 Errors bestätigt.** Offen: Rule-Test-Matrix + Demo-Forward + firmenspezifische Verifikation.

## v0.35 — R22 „Nur Panel-Trades" (gebaut, UNGETESTET, F7 ausstehend)
- **Neue Regel R22** (`InpCloseManualTrades`, Default `true`): `EnforceManualTrades()` reiht jede Order mit `OrderMagicNumber()==0` in die Close-Queue — Positionen werden geschlossen, Pendings gelöscht. Fremde EAs (Magic ≠ 0) bleiben unangetastet. Regel-Nummer R22 war frei; R20/R21/R26/R27 bleiben offen, R23/R24 existieren nirgends. Details: Abschnitt 7 (Regel-zu-Code + R22-Besonderheiten), Abschnitt 11 (Parameter), Abschnitt 12 Punkt 9/10 (Compliance + ehrliche Grenzen).
- **Warum:** Nur der Panel-Pfad (`DoEntry`) durchläuft die Gate-Kette (AutoTrading, Sperre, Basis, R4b-Warn-Gate, R13, R5, R16, R25, R14, R7 SL-Linie/Seite, R15 + Broker-`STOPLEVEL`, R1 Sizing, R2, R3, R12, R17). Ein manuell im Terminal geöffneter Trade umgeht das komplett.
- **Einordnung im Cycle:** ein Aufruf im Enforcement-Block, **vor** dem Sperr-Zweig (greift also auch bei aktiver Sperre) und bewusst **ohne** `InScope()` (greift also auch im FundedMode). Damit wird `WatchScope=TOOL_PLUS_MANUAL` bei aktivem R22 wirkungslos — der EA weist beim Start auf genau diese Kombination hin.
- **Doku-Hinweis (nicht Teil dieses Dokuments):** Der Datei-Kopfkommentar des EA nennt weiterhin „v0.21 … Regeln R1-R19 + R25" und ist damit veraltet; `EA_VER` steht auf `0.35`. (`RULES.md` führt R22 inzwischen — der Vertrag wurde mit v0.35 nachgezogen; die vom Vertrag geforderte Reihenfolge „erst RULES.md, dann Code" war hier allerdings verletzt: Cockpit und EA führten R22 vor dem Eintrag.)
