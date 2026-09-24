> ⛔ **EINGEFRORENES ARTEFAKT — Stand v0.14 (2026-06-26). NICHT der aktuelle Stand.** Dieser Review beschreibt v0.14; die genannten P0/P1 sind in v0.15–v0.18 abgearbeitet. Aktueller Reifegrad: [`STATUS.md`](STATUS.md). Mapping P0 → erledigt in:
> - **P0-1** tick-only Enforcement → v0.15: `Cycle()` aus OnTick **und** OnTimer.
> - **P0-2/P0-4** Verlustserie/Teil-Close → v0.15: history-basiert (`ResolveHistory`, `ProcKey`); v0.18-B4/6: EA-/Trader-Anteil getrennt.
> - **P0-3** EA-Close als Verlust gezählt → v0.15: `RGEAC_`-Marker; v0.18-B5/8: Marker erst nach bestätigtem Close.
> - **P0-5** FTMO-Tagesbasis `MathMax(Balance,Equity)` → v0.15; v0.18-B1: Max-Loss-Basis (`InpInitialBalance` Default 0=auto).
> - **P0-6** Max-Loss-Puffer → v0.15: 6 % + Warn-Gate 5 %.
> - **P0-7** No-Override → v0.16: Lockstate-Datei (HMAC-light, fail-closed) — lokal Reibung, echtes Immutable erst VPS.
> - **P1-4** Zeitquelle → v0.17: `SrvTime()` (MQL4 hat kein `TimeTradeServer`). **P1-7** R7 → v0.17: 5 s/News 0/OpenTime-Anker. **P1-8** R17 → v0.17: Währungsvektor. **P1-10** Journal → v0.17: 18-Spalten-Audit. **P1-11** Magic-Filter → v0.15: `WatchScope`.
> 
> Verdikt **C) nicht Prop-Firm-sicher** bleibt gültig, weil **Stufe 4 (live-getestet)** noch fehlt — nicht wegen der unten gelisteten P0 (die sind code-seitig adressiert + KI-fix-verifiziert, aber ungetestet).

Ich erstelle den finalen Review-Bericht. Da P0/P1-Verdikte teils Severity-Anpassungen enthalten (z. B. F3/F4/F9 herabgestuft, FTMO-3 widerlegt), gruppiere ich nach den **verifizierten** Schweregraden, nicht den Roh-Findings.

---

# FINALER REVIEW-BERICHT — MamalTrading.mq4 (FTMO Risk-Engine)
Quelle: `/Users/mohammadrezatavakoli/Desktop/TradingGuard/ea/mt4/MamalTrading.mq4` (Header v0.12 / Print v0.14)

## 1. Executive Summary

Das Tool ist konzeptionell sinnvoll, aber in seinem **Kernzweck — Disziplin und FTMO-Limits unausweichlich erzwingen — nicht verlässlich**, und der Header deklariert es selbst korrekt als „NUR DEMO / UNGETESTET". Die schwerwiegendsten Defekte sind systemisch: Der gesamte Schutz hängt an Ticks (`allowTrades` nur aus `OnTick`), sodass `EnforceSLTP`/`SafeCloseAll` in genau den tickarmen/gappy Märkten ausfallen, in denen man sie braucht (R7-1, R4-2); die Verlustserien-/Revenge-Disziplin lebt in flüchtigen In-Memory-Arrays und überlebt die laut Doku „~minütlichen" Wine-Neustarts nicht (P6-01, P8-03); EA-eigene Schutz-Closes werden fälschlich als Trader-Verluste gezählt und lösen Fehl-Sperren aus (P9-1); und die Tagesbasis ist nicht FTMO-konform (`AccountEquity()` statt `MathMax(Balance,Equity)`, F1-P0). Der lokale „No-Override" (R10) ist trivial umgehbar (GV löschen, AutoTrading aus) — echte Unwiderruflichkeit gibt es nur server-/VPS-seitig (P5-1). **Entscheidung: C) für FTMO nicht sicher genug** — testbereit erst nach den unten priorisierten P0/P1-Patches und einem Strategy-Tester-Durchlauf der gesamten Regel-Matrix.

---

## 2. Severity-Liste (gruppiert nach verifiziertem Schweregrad)

### P0 — Blocker (müssen vor jedem Geld-Einsatz behoben sein)

**P0-1 · R7/SafeCloseAll feuern nur bei Ticks — in totem/gappy Markt nie** (R7-1)
- **Problem:** Der gesamte Enforcement-Block in `Cycle()` (Z344 `if(!tradingDisabled && allowTrades)`) läuft nur mit `allowTrades=true`, das ausschließlich aus `OnTick` kommt (Z127). `OnTimer` ruft `Cycle(false)` (Z129). Ohne Ticks (Wochenende, Rollover, illiquides Symbol, Feed-Stall) wird eine nackte Position weder erkannt noch geschlossen; auch R1/R8/R12/Lock-`SafeCloseAll` stehen still.
- **Impact:** SL-lose Position kann unbegrenzt laufen → FTMO-Daily/Max-Loss-Bruch genau im gefährlichsten Markt.
- **Fix:** `Cycle()` um Parameter `enforce` erweitern; `OnTimer→Cycle(false,true)`. Enforcement an `(enforce && !tradingDisabled)` statt an `allowTrades` koppeln; Entries weiter nur bei `allowTrades`. So greift der Watchdog jede `InpTimerSeconds` (1 s) tickunabhängig.
- **Betroffen:** `Cycle` (Z344-348), `OnTimer` (Z129), `EnforceSLTP`, `SafeCloseAll`.

**P0-2 · R5/R6/R19/R25 verpassen jeden Close während Downtime (g_known in-memory)** (P6-01)
- **Problem:** `g_known[]` (Z92) ist rein in-memory und nach jedem `OnInit` leer. `UpdateStreak` (Z271-288) baut `cur[]` nur aus offenen Tickets und überschreibt `g_known` bedingungslos (Z286-287); `ResolveClosed` läuft nur für vorher bekannte, jetzt fehlende Tickets. Closes, die während eines Crash/Neustart-Fensters fallen, werden nie aufgelöst → `GV_CONSEC` steigt nicht, kein Cooldown/Lock/De-Risk/Revenge. Doku: „Neustarts ~jede Minute".
- **Impact:** Kern-Disziplin (R5/R6/R19/R25) auf der Zielplattform praktisch blind.
- **Fix:** History-basierte, idempotente Auflösung. Persistente GV `RG_LAST_CLOSE` (Wasserstand, in `RollNewDay` NICHT zurücksetzen); in `OnInit`+`Cycle` über `MODE_HISTORY` alle Closes mit `OrderCloseTime()>RG_LAST_CLOSE` (Magic==InpMagic) **nach CloseTime sortiert** verarbeiten, Schwellenlogik aus `ResolveClosed` in `ApplyConsecThresholds()` extrahieren und gemeinsam nutzen. Idempotenz über monoton steigenden Wasserstand + resolved-Ticket-Datei.
- **Betroffen:** `g_known`, `UpdateStreak`, `ResolveClosed`, neue `ResolveClosedHistory`/`ApplyConsecThresholds`.

**P0-3 · EA-erzwungene Closes zählen als „Verlust-Serie" → Fehl-Cooldown/Tagessperre + Revenge** (P9-1)
- **Problem:** `ResolveClosed` (Z252-270) wertet jedes verschwundene Ticket nur über `net<0` (Z256), ohne Schliessungsursache/Magic-Check. `EnforceSLTP/Risk/RR/Heat` und `SafeCloseAll` schließen zum Marktpreis (praktisch immer im Minus) → `GV_CONSEC++` (Z260), `SetRevenge` (Z259), bis R6-Tagessperre (Z262). Das Tool bestraft den Nutzer für seine eigenen Schutzeingriffe.
- **Impact:** Eine einzige Heat-/Naked-Intervention mit 2-3 offenen Verlust-Positionen kann den FTMO-Tag grundlos sperren.
- **Fix:** In-Memory-Ausschlussliste `g_eaClosed[]`. Vor JEDEM Watchdog-`OrderClose` (Z372/378/401/424/446/461) `MarkEaClosed(ticket)`; bei fehlgeschlagenem Close Eintrag zurücknehmen. In `ResolveClosed` (vor Z256): `if(TakeEaClosed(ticket)){ Journal(...EA-Schutz-Close...); return; }`. Magic-Filter allein genügt NICHT (Tool-Trades behalten InpMagic).
- **Betroffen:** `ResolveClosed`, alle Enforce-Funktionen, `SafeCloseAll`.

**P0-4 · Partial Close zählt jeden Teil-Close als kompletten Trade-Ausgang** (P9-2)
- **Problem:** `UpdateStreak` erkennt ein Ticket als „geschlossen", sobald es aus `OrdersTotal()` fällt. MT4-Teil-Close legt das Restvolumen auf ein NEUES Ticket → altes Ticket gilt als voller Close (Teil-net wertet die Serie), Rest-Ticket wird später ERNEUT gewertet (Doppelzählung).
- **Impact:** Verlustserie R5/R6 wird bei jedem Teil-Close über-/unterzählt → verfrühte/unvorhersehbare Fehlsperren; Teilschließen (Standard-Management) wird unbenutzbar.
- **Fix:** Trade-Ergebnis aus `MODE_HISTORY` pro Position (Schlüssel `OrderOpenTime`+Symbol+Type) aggregieren, EIN `net`; erst werten, wenn KEIN offenes Restticket gleicher Identität existiert. Deckt sich mit P0-2-History-Umbau.
- **Betroffen:** `UpdateStreak`, `ResolveClosed`.

**P0-5 · Tagesstart-Equity nicht FTMO-konform (bare `AccountEquity`)** (F1-P0)
- **Problem:** `RollNewDay` Z165/Z171 setzt `GV_DAYSTART_EQ`/`GV_PEAK_EQ = AccountEquity()`. FTMO misst gegen `max(Balance,Equity)` um 00:00. Bei Overnight-Verlust-Float ist Equity < Balance → Basis zu niedrig → `dailyDDpct` (Z306) zu klein → R4 sperrt zu spät, FTMO-Limit reißbar während EA „grün" zeigt.
- **Impact:** Untergräbt direkt den Vertragszweck (R4).
- **Fix:** `double base = MathMax(AccountBalance(), AccountEquity());` für `GV_DAYSTART_EQ` UND `GV_PEAK_EQ`. (Reine Balance wäre bei Overnight-Gewinn ebenfalls falsch — daher `MathMax`, nicht der ursprüngliche Finding-Vorschlag.) Snapshot-Zeitpunkt: gated, Erststart-Fall loggen. Keine History-Rekonstruktion nötig.
- **Betroffen:** `RollNewDay` (Z165, Z171).

**P0-6 · R4b Max-Loss 8 % ist Trigger, kein Puffer** (P4-1)
- **Problem:** `GV_HARD_LOCK` wird erst gesetzt, NACHDEM `totalDDpct>=InpMaxLossPct(8.0)` erreicht ist (Z336-337); `SafeCloseAll` läuft verzögert (nur OnTick). 2 % Restmarge müssen Polling-Latenz, Slippage (`InpSlippage=30`), Spread-Spike, Multi-Position und Gaps abfangen → FTMO-10 %-Hard-Limit reißbar vor dem Close.
- **Impact:** Sofortiges Challenge-Aus.
- **Fix:** (a) Proaktives Entry-Gate in `DoEntry`: neuer Input `InpMaxLossWarnPct` (~6.0); bei `tdd>=Warn` keine neuen Trades. (b) `InpMaxLossPct` Default 8.0→6.0 (4 % Puffer). Restrisiko Wochenend-/Overnight-Gap (SafeCloseAll an OnTick) als prinzipielle Grenze dokumentieren.
- **Betroffen:** `DoEntry` (Z534ff), Cycle-Hard-Lock (Z336-337), `InpMaxLossPct` (Z17).

**P0-7 · Lokaler No-Override trivial umgehbar — kein Fail-Closed/Checksum/Lockfile** (P5-1)
- **Problem:** Lock-State nur in GVs (über F3-Editor löschbar); AutoTrading-Aus deaktiviert den GESAMTEN Enforce-Block (Z332-334/344, nur Notify); EA entfernbar. Kein Disk-Lockfile, kein HMAC, kein fail-closed.
- **Impact:** R10 — die zentrale Wertversprechen-Säule — ist in Sekunden defeatbar, genau im emotionalen Druckmoment.
- **Fix:** (1) Persistente Lockstate-Datei (`MQL4/Files`) mit HMAC/Checksum über kompilierten Secret-Key; in `OnInit` GV+Datei lesen, restriktivsten Zustand übernehmen (fail-closed). (2) Revenge/Streak mitspiegeln. (3) Bei `!IsTradeAllowed()` „Umgangen"-Marker + Strafsperre statt nur warnen. (4) Ehrlich kommunizieren: vollständige Unwiderruflichkeit nur server-/VPS-seitig.
- **Betroffen:** `OnInit`, Lock-Defines (Z64-77), Z332-334.

### P1 — Hoch (vor Funded zwingend; Tool sonst unzuverlässig)

**P1-1 · Lock-Erkennung faktisch ~1 s-Polling, Close hängt zusätzlich an `IsTradeContextBusy`** (P4-2) — Sperre wird ungated gesetzt, aber der Close läuft nur im OnTick-Pfad; in tickarmen Phasen unbeschränkte Latenz. Fix wie P0-1 (Close aus Timer) + Retry-Schleife mit `RefreshRates()` statt einmaligem `return` (Z452). Betroffen: `Cycle`, `SafeCloseAll`.

**P1-2 · Tagesstart-Equity beim Aufziehen erfasst — falsche R4-Basis bei Erststart mitten am Tag** (P4-3) — `RollNewDay` Z165 friert Mittags-Equity ein, wenn EA erst nach Broker-Mitternacht startet → R4 erlaubt mehr als FTMO. Fix: Erststart-Fall (`!GlobalVariableCheck(GV_DAYSTART_DAY)`) erkennen, konservativ `base=AccountBalance()` + Warnbanner; echten Datumswechsel-Pfad unverändert. Betroffen: `RollNewDay`.

**P1-3 · Verlustserie verpasst Closes im Restart-Gap (g_known) — R5/R6/R19 unterzählen** (F10) — Teilmenge von P0-2 (eng auf den Restart-Gap fokussiert); mit der History-Auflösung aus P0-2 vollständig erledigt. Betroffen: `UpdateStreak`, `OnInit`.

**P1-4 · ServerDayKey/NextServerMidnight nutzen `TimeCurrent()` statt `TimeTradeServer()`** (F2) — frieren ohne Ticks ein (Wochenende/illiquide) → verspäteter RollNewDay/stale Tagesbasis. Symmetrisch zu IsDayLocked/CooldownActive, daher Richtung „sperrt später", aber Kern-Garantie defekt. Fix: Z98/99/100 auf `TimeTradeServer()`; auch Z177/180/537/543/590 angleichen; `TimeLocal()` an Z292/376 bleibt. Betroffen: `ServerDayKey`, `NextServerMidnight`, `WeekIdx`.

**P1-5 · R3 Tagesbudget kann nach Crash dauerhaft unterzählen → Über-Risiko** (P7-02) — `GV_DAY_RISK` nur additiv nach OrderSend (Z589), kein Flush, keine Reconciliation; Crash zwischen Z587 und Z589 → rp nie gebucht. Fix: in `Cycle` `GV_DAY_RISK = max(persistiert, OpenedTodayToolRiskPct())` (Summe offener Tool-Risiken seit Tagesstart) vor dem R3-Gate; `GlobalVariablesFlush()` nach Z589. Betroffen: `Cycle`, `DoEntry` (Z589).

**P1-6 · R25 Revenge rein in-memory — bei Neustart weg** (P8-03 / FTMO-5) — `g_revSym/Dir/Time` (Z93-95) ohne GV-Persistenz; bei ~minütlichen Crashs faktisch nie wirksam. Fix: pro Symbol `RG_REVDIR_<sym>`/`RG_REVT_<sym>` als GV; `SetRevenge`/`RevengeBlocked` darauf umstellen; abgelaufene Keys in `Cycle` per Präfix-Scan löschen. Betroffen: `SetRevenge`, `RevengeBlocked`.

**P1-7 · R7 Naked-Frist & 10 s in schnellen Märkten** (R7-3) — Stempel/Vergleich sekundengrob (`TimeLocal`, Z292/376) + OnTick-Drossel → reale Exposure ~11 s, genau in News/High-Vol. Fix: `GetTickCount()`-Messung, Default-Grace 3-5 s, bei `InNewsBlackout()` Grace=0, Enforce-Pfad von der 500 ms-Entry-Drossel entkoppeln. Betroffen: `AddNaked`, `EnforceSLTP`. (Der separate Crash-Reset der Frist ist als P2/P8-04 geführt.)

**P1-8 · R17 Korrelations-Deckel ignoriert ALLE Cross-Pairs** (Exposure-F1) — `UsdSign()` liefert 0 für EURJPY/GBPJPY/EURGBP → 3× JPY-Cross long passieren R17 ungedeckelt; nur R12-Heat bremst ohne Korrelations-Aufschlag. Fix: Symbol in Basis+Quote zerlegen, pro Währung Risiko-Vektor, je Währung Netto-Deckel; Broker-Suffixe (`.m`/`pro`) beachten. Betroffen: `UsdSign`, `NetUsdRiskPct`, `DoEntry` (Z576-581).

**P1-9 · R3-Tagesbudget wird nie reduziert + zu restriktiv vs. Doku** (Exposure-F2) — additiver Akkumulator (gewollt: „Schüsse/Tag"), aber bei Scalping nach ~3 statt der dokumentierten ~6 Trades dicht; treibt zur EA-Abschaltung (R10-Umgehung). Fix: Diskrepanz 1.5 % vs. 3 % auflösen (Default/Doku angleichen), Scope klar kommunizieren. (Code-seitig korrekt — primär Tuning/Doku.) Betroffen: `EffDay`, `DoEntry` (Z568-570).

**P1-10 · Journal-CSV nicht audit-/rekonstruktionstauglich** (R11-1) — `Journal()` (Z238/244-246) ohne Ticket/Magic/Account/Balance/Equity/ServerDayKey/strukturierte ruleId/realisiertes net; OPEN↔CLOSE nicht joinbar, kein Drawdown-Nachweis. Fix: Signatur+Schreibzeile erweitern, kontextfreie Felder in `Journal()` selbst ziehen (AccountNumber/Balance/Equity/Server/GMT-Offset/DayKey), pro Call-Site `ticket`/`ruleId`/`net` nachreichen, Header-Zeile bei leerer Datei. Betroffen: `Journal`, alle 18 Call-Sites.

**P1-11 · Autonomes Schließen FREMDER Positionen (kein Magic-Filter)** (FTMO-1) — `SafeCloseAll`/`EnforceRisk`/`EnforceRR`/`EnforceHeat` (Z387-464) schließen/löschen jede Order ohne `OrderMagicNumber()==InpMagic`. Fix: in jeder Schleife direkt nach OrderType-Check `if(OrderMagicNumber()!=InpMagic) continue;` (Z456-457/395/415/439 + die Summenfunktionen Z481/493/506). Vor Funded FTMO-Freigabe für selbst-schließenden Watchdog einholen. Betroffen: alle Enforce-Funktionen, `SafeCloseAll`, Risk-Aggregatoren.

**P1-12 · One-Click-OrderSend + EA-Sizing/SL/TP — genehmigungspflichtig vor Funded** (FTMO-2) — `DoEntry`/`OrderSend` (Z587) mit `CalcLot`-Lot, EA-TP, Magic 990201; klickausgelöst, kein Auto-Open. Fix: schriftliche FTMO-Freigabe archivieren, bis dahin nur Demo; optional `InpFundedApproved=false`-Gate vor OrderSend. Betroffen: `DoEntry`, `GateClick`.

**P1-13 · Mac/Wine für echte Challenge nicht akzeptabel** (P18-1) — Host-Crash bei offener Position = ungeschütztes Downtime-Fenster (Enforce nur OnTick). Fix: Windows-VPS Pflicht ab bezahlter Challenge; sicherstellen, dass jeder Tool-Trade broker-seitigen SL trägt (Z587); Heartbeat/Watchdog (P18-2). Betroffen: Deployment + DoEntry-SL.

**P1-14 · Detect-and-revert statt prevent: verbotener Klick füllt echtes Risiko** (FTMO-6) — manuelle Plattform-Trades umgehen `DoEntry`-Gates; Enforce reagiert tickgetrieben, Fenster bei Tick-Stille unbegrenzt. Fix: Close-Enforcer in den Timer-Pfad (siehe P0-1), eigener ~200 ms-Throttle statt 500 ms-OnTick-Drossel; Trader auf Tool-Buttons + VPS/FTMO-Serverlimit verweisen; Doku-Grenze beibehalten. Betroffen: `Cycle`, `InpMinActionMs`.

### P2 — Mittel (Korrektheits-/Robustheitslücken, bedingt)

- **P2-1 · net==0 resettet die Verlustserie nicht** (F9/P9-3) — kein `else`-Zweig für `net==0` (Z257/265). Fix: Verlust = `OrderProfit() < -(|Comm|+|Swap|)`; Break-even bewusst neutral. Wirkt konservativ. Betroffen: `ResolveClosed`.
- **P2-2 · EA-Ausfall über Nacht → veraltete Tagesbasis** (F5) — `RollNewDay` holt Datumswechsel verspätet nach; Sperre-Teil des Findings widerlegt (`GV_LOCK_UNTIL=NextServerMidnight` läuft korrekt ab). Fix: `GV_PREV_CLOSE_EQ` laufend schreiben, bei verspätetem Roll nutzen + Warnbanner; VPS. Betroffen: `RollNewDay`, `Cycle`.
- **P2-3 · Tagesbasis nach Reinit bei offenen Positionen** (P7-05) — Downtime über Mitternacht → gedrückte Boot-Equity als Basis. Fix: `RG_LAST_EQ`/`RG_LAST_EQ_DAY` persistieren, bei übersprungenem Tag als Basis. Betroffen: `RollNewDay`, `Cycle`.
- **P2-4 · Streak/Cooldown/Revenge-Reset bei Neustart** (P5-2) — Kapital-Sperren (R4/R4b/R13/R18) überleben korrekt; nur verhaltensbasierte Schicht betroffen. Mit P0-2 + P1-6 erledigt. Betroffen: `g_known`, Revenge-Arrays.
- **P2-5 · R7 Naked-Frist-Reset durch Crash-Timing** (P8-04) — `g_nakedSince` in-memory → Frist startet nach Restart neu. Fix: Anker `OrderOpenTime()` statt `TimeLocal()`, Vergleich auf `TimeCurrent()` (fail-closed). Betroffen: `AddNaked`, `EnforceSLTP`.
- **P2-6 · OrderSelect-Fehler/History-Lücke → stille Unterzählung** (P9-6) — `ResolveClosed` verwirft nicht aufgelöste Tickets still (Z254-255). Fix: Pending-Liste mit Retry; mit P0-2-History-Pfad weitgehend erledigt. Betroffen: `ResolveClosed`, `UpdateStreak`.
- **P2-7 · Fremde Trades zählen in die Tool-Verlustserie** (P9-7) — `UpdateStreak`/`ResolveClosed` ohne Magic-Filter; Fremd-Gewinn resettet legitime Serie. Fix: `if(OrderMagicNumber()!=InpMagic) continue;` in beiden. Betroffen: `UpdateStreak`, `ResolveClosed`.
- **P2-8 · Reihenfolge-/Multi-Close-Determinismus** (P9-5) — bei gemischtem Gewinn/Verlust-Tick hängt das Ergebnis von `g_known`-Reihenfolge ab (Überschießen landet konservativ auf strengerer Stufe). Fix: Closes pro Tick nach `OrderCloseTime` sortiert verarbeiten, Schwellen-Check erst danach einmal. Betroffen: `UpdateStreak`, `ResolveClosed`.
- **P2-9 · R16 Session/News blockt nur Tool-Button, schließt nichts** (R16-1) — `OffSession()` nur Entry-Gate (Z538); manuelle Plattform-Trades ungedeckt. Default aus. Fix: Panel-Warnung verschärfen, optional `InpFlatInNews`. Betroffen: `Cycle`, `DrawPanel`.
- **P2-10 · News-Blackout nur tägliches HHMM-Fenster ohne Datum** (R16-2) — Einzel-Events (NFP/FOMC) nicht abbildbar. Fix: datierte Fenster-Liste, mittelfristig Kalender-Feed. Betroffen: `InNewsBlackout`.
- **P2-11 · F6/F7/F8/F11 (Doku-Bündel P2):** zwei Mitternachts-Definitionen (F6), R19-De-Risk koppelt Caps nicht an `EffectiveRiskPct` (F7 — nach De-Risk doppelte Trade-Anzahl/Idee), R3 trackt Plan- statt Ausführungs-rp (F8), R3 erfasst manuelle Orders nicht (F11). Jeweils Doku-/Tuning-Fixes wie in den Findings.
- **P2-12 · Exposure-F3/F4/F5/F6/R7-4/R11-2:** EnforceHeat schließt neueste statt riskanteste Position (F3), Naked-Trades zählen 0 Heat (F4), R13-Giveback inkl. Floating-Peak → Falsch-Positive (F5), R2 erfasst nur identische Symbole (F6), R7 trennt Modify-Fehler nicht von „kein SL" (R7-4), Journal-Zeitbasis inkonsistent + kein FILE_SHARE/Integritätshash (R11-2).
- **P2-13 · CRV/Tickwert P2 (Risiko-F4/F5):** R8 misst CRV ohne Spread/Komm/Slippage (F4), Entry-rp unterschätzt Worst-Case-Distanz (F5) → R2/R3/R12 leicht zu locker.

### P3 — Niedrig (Doku/Hygiene/seltene Edge-Cases)

- **P3-1 · F3 widerlegt — Mitternachts-Arithmetik ist bereits Broker-Serverzeit** (confirmed=false). Kein Arithmetik-Umbau; nur Annahme „Broker==CE(S)T" via `OnInit`-Offset-Log/`InpAssertCetServer` sichtbar machen.
- **P3-2 · F4 widerlegt — base=`AccountEquity()` im Roll-Moment ist FTMO-konform** (confirmed=false). Floating aus base herauszurechnen würde aktiv eine Fehlmessung einführen. Reine Risiko-Komfort-Option `InpForceFlatBeforeMinutes`.
- **P3-3 · FTMO-3 widerlegt — Day-Lock ist timestamp-gated, kein Tick-Zähler; löst korrekt aus** (confirmed=false). Advisory: Broker-Serverzeit-Alignment verifizieren, VPS.
- **P3-4 · P9-4 widerlegt — `Cycle(false)` in `OnInit` seedet g_known bereits aus offenen Tickets** (confirmed=false). Der vorgeschlagene Seed ist no-op; echte Lücke ist der Offline-Close (= P0-2).
- **P3-5 · Risiko-F1 herabgestuft — `NormalizeDouble(lot,2)` schadet nur bei Step<0.01** (confirmed=false). US30/GER40/XAUUSD unbetroffen. Optional step-konforme Rundung mit `lotDigits`.
- **P3-6 · Versions-Inkonsistenz v0.12 vs v0.14 + R25 im Header fehlt** (FTMO-4/F4-Doku) — `#define EA_VERSION`, Header/Print/Panel daraus speisen.
- **P3-7 · Doku-Widersprüche (F1-F5, R9-10, FTMO-7/9):** RULES.md feste Caps vs. AutoScale-Default; REGELN.md mischt 0,25 %/0,5 %; R19 0,5%→0,25% vs 0,125 %; implementierte Regeln als „offen" gelistet; Compliance-Klassifikation order-aktiv vs passiv fehlt. → RULES.md auf v2 als einzige Source of Truth, andere ableiten.
- **P3-8 · P8-07/P8-08:** `ObjectsDeleteAll(0,"RG_")` ist toter Code (Objekte tragen `MMT_`) → stale SL-Linie überlebt Chartwechsel; Doku-„restart-fest"-Aussagen präzisieren.
- **P3-9 · Risiko-F2/F3/F6:** `MODE_TICKVALUE` ohne Kontowährungs-Prüfung (EUR-Konto, USD/JPY-Symbole) und CFD-Pip-Heuristik (`Pip()` aus Digits) → Sizing waehrungs-/CFD-abhängig ungenau; `MarketInfo`-0-Beim-Ersttick eigene Meldung.

---

## 3. Antworten auf die 20 Prüfpunkte

1. **Detect-and-close-Puffer ausreichend?** Nein. R4b ist Trigger ohne Puffer, Close hängt an Ticks (P0-6/P4-1, P1-1/P4-2). 6 % + Soft-Gate nötig.
2. **No-Override (R10) wirksam?** Nein — trivial umgehbar, kein fail-closed (P0-7/P5-1).
3. **Mac/Wine vs. VPS?** VPS Pflicht ab Funded; Wine-Crash = Downtime-Loch (P1-13/P18-1).
4. **Persistenz nach Neustart?** Kapital-Locks ja (GV), Disziplin-Schicht nein (P0-2/P6-01, P1-6/P8-03, P2-4/P5-2).
5. **R3 Tagesbudget korrekt?** Logik konservativ, aber Crash-Unterzählung (P1-5/P7-02) + zu restriktiv/Doku-Diskrepanz (P1-9/Exposure-F2).
6. **Verlust-Definition korrekt?** Nein — EA-Closes (P0-3/P9-1), Partials (P0-4/P9-2), net==0 (P2-1/F9), Fremd-Trades (P2-7/P9-7).
7. **Tagesstart-Equity FTMO-konform?** Nein — bare Equity statt `max(Balance,Equity)` (P0-5/F1) + Erststart-Snapshot (P1-2/P4-3).
8. **Overnight-Absicherung R4?** Floating-im-base ist FTMO-korrekt (P3-2/F4 widerlegt); echtes Risiko = Timing/Downtime (P0-5, P2-2, P2-3).
9. **Zeitlogik (Mitternacht/Woche)?** `TimeCurrent` statt `TimeTradeServer` (P1-4/F2); Arithmetik selbst korrekt (P3-1/F3 widerlegt); WeekIdx Do-Grenze (F6, P2).
10. **Risiko-/Lot-Berechnung universell?** Nein — Tickwert/Kontowährung + CFD-Pip (P3-9/Risiko-F2,F3); `NormalizeDouble` unkritisch (P3-5/F1 widerlegt).
11. **R8/CRV realistisch?** Überschätzt — ohne Spread/Komm/Slippage (P2-13/F4).
12. **Exposure-Modell (R2/R12/R13/R17)?** R17 ignoriert Crosses (P1-8/Exposure-F1); R2 nur identische Symbole, Heat schließt neueste, Giveback Floating-Peak (P2-12).
13. **R7 SL/TP-Pflicht?** Lückenhaft — tickabhängig (P0-1/R7-1), Frist-Reset (P2-5/P8-04), Granularität (P1-7/R7-3).
14. **R5/R6/R19/R25 Trigger?** Verpassen Downtime-Closes (P0-2), Fehlauslösung durch EA-Closes (P0-3); Revenge flüchtig (P1-6).
15. **Lock-Reaktionszeit ~0,5 s?** Nein — faktisch ~1 s, bei Tick-Stille unbegrenzt (P1-1/P4-2).
16. **R16 Session/News?** Nur Tool-Button, kein Close, kein Datum (P2-9/P2-10).
17. **R11 Journal audit-tauglich?** Nein — Kernfelder fehlen (P1-10/R11-1), Integrität/Zeitbasis (P2-12/R11-2).
18. **FTMO-Compliance (Auto-Close/One-Click)?** Magic-Filter fehlt (P1-11/FTMO-1), Freigabe nötig (P1-12/FTMO-2); detect-not-prevent (P1-14/FTMO-6).
19. **Version/Reife?** v0.12/v0.14-Drift, „ungetestet" (P3-6); nie als Ganzes kompiliert/getestet.
20. **Doku = Code?** Nein — feste Caps vs. AutoScale, R19-Wert, „offen vs implementiert" (P3-7).

---

## 4. Test-Matrix

*(vollständig übernommen — die „Querschnitt-Hinweise" sind beim Testen verbindlich)*

**Bezugskonto: 20.000 EUR @ 0,25 %/Trade (50 EUR). AutoScale=true. EffIdeaCap(R2)=0,50 %/100 EUR · EffHeat(R12)=1,00 %/200 EUR · EffDay(R3)=1,50 %/300 EUR. RiskTolFactor=1,10. +0,01-%-Slack in Entry-Gates.**

| Regel | Testziel | Setup | Erwartet | Persistenz/Restart | Kern-Edge-Cases | PASS-Kriterium |
|---|---|---|---|---|---|---|
| **R1** EnforceRisk Z387-405 | Fremd-Pos mit rp>0,275 % wird geschlossen | manuelle EURUSD-Pos, SL gesetzt, rp=0,40 % | OrderClose, `CLOSE…rp=0.40 "R1 Risiko zu gross"` | kein State; Re-Enforce 1. Cycle n. Restart | 0,27 %→bleibt; 0,28 %→Close; sl==0→continue (R7) | nur >0,275 % geschlossen |
| **R2** Entry Z564-566 | Idee-Cap pro Symbol+Richtung ≤0,50 % | EURUSD BUY #1 0,25 %; #2; #3 | #2 durch, #3 `BLOCKED "R2 Idee-Cap"` | live aus Orders; Block n. Restart | SELL #3→durch; GBPUSD #3→durch; #2 an Grenze→durch | >0,51 % gleichgerichtet blockt, Cross/Gegenricht. durch |
| **R3** Entry Z568-570, GV RG_DAY_RISK | kumuliert ≤1,50 %, sinkt nie | 6× 0,25 % → 1,50 %; 7. | 1-6 durch, 7 `BLOCKED "R3 Tagesbudget"` | GV überlebt Restart; Tageswechsel→0 | Close vor #7→bleibt geblockt; De-Risk→mehr Trades | 7. blockt, Block restart-stabil, Tageswechsel hebt auf |
| **R4** Cycle Z338-339, RG_LOCK_UNTIL | DD≥2,0 % sperrt + SafeCloseAll | DAYSTART 20000, eq≤19600 | IsLocked, SafeCloseAll, Entries BLOCKED, Panel GESPERRT | GV überlebt; bis Serverzeit-Mitternacht | 1,99 %→keine; Erholung n. Lock→bleibt; RollNewDay setzt LOCK_UNTIL=0 | greift bei 2,0 %, schließt alles, verfällt korrekt |
| **R4b** Cycle Z336-337, RG_HARD_LOCK | DD≥8,0 % vs INIT_BAL → permanent | INIT_BAL 20000, eq≤18400 | IsLocked dauerhaft, SafeCloseAll, Panel MAX-LOSS | GV, NICHT in RollNewDay → überlebt alles | 7,99 %→kein; Erholung→bleibt; INIT_BAL-Basis prüfen | 8,0 % permanent, KEIN Auto-Reset |
| **R5** ResolveClosed Z263, RG_COOLDOWN | 3 Verluste<5 → 45 min Cooldown | CONSEC 0; 3 net<0-Closes | Entry BLOCKED, Panel COOLDOWN, Notify R5 | GV überlebt; bis TimeCurrent<COOLDOWN | net==0→weder inc/reset; 2V+1G→0; Tageswechsel→0 | ab 3. Verlust 45-min-Block, GV restart-stabil |
| **R6** ResolveClosed Z262, RG_LOCK_UNTIL | 5 Verluste → Tagessperre | CONSEC 0; 5 net<0 | IsDayLocked, SafeCloseAll, Notify R6 | LOCK_UNTIL+CONSEC GV überleben | #5 nur Lock-Zweig (kein Cooldown); 4V+1G+1V→keine | exakt 5 ununterbrochen sperrt |
| **R7** EnforceSLTP Z354-385, g_nakedSince | Tool-naked sofort, Fremd nach 10 s | A Tool-SL entfernen; B Fremd ohne SL | A sofort Close; B Close nach ≥10 s | g_naked in-memory → Fremd-Frist startet n. Restart neu | nur TP fehlt→naked; SL re-set→kein Close; TimeLocal-Basis | Tool sofort, Fremd exakt 10 s |
| **R8** EnforceRR Z407-428 | RR<1,49 wird geschlossen | SL 20 / TP 25 Pips → 1,25 | OrderClose `"R8 CRV 1.25 < 1.50"` | kein State; Re-Enforce n. Restart | 1,50→bleibt; 1,49→Close; TP/SL==0→continue; MinRR=0→aus | nur <1,49 geschlossen |
| **R12** Entry Z572-574 + EnforceHeat Z430-448 | Heat ≤1,00 % (Gate) / Close >1,10 % | 4× 0,25 %=1,00 %; #5; Fremd→1,20 % | #5 BLOCKED; Monitor schließt NEUESTE bis ≤1,10 % | live; konsistent n. Restart | Gate strenger als Monitor; sl==0→0 Heat; 1/Cycle | >1,01 % blockt, >1,10 % iterativ Close |
| **R13** Cycle Z321-330 | (a) +3 %→TARGET_HIT (b) Giveback Arm1 %/Drop1 % | (a) eq≥20600 (b) Peak 20300→20100 | (a) BLOCKED R13 Tagesziel (b) Lock+SafeCloseAll | GV überleben; Tageswechsel reset | Giveback braucht !IsLocked; Arm 0,99 %→kein; Drop/base | +3 % bis Tageswechsel blockt, Giveback nur n. Arm |
| **R14** Entry Z540-545, RG_LAST_ENTRY | Gap ≥10 s | Trade→LAST_ENTRY; <10 s 2. | BLOCKED "noch N s"; ≥10 s erlaubt | GV, NICHT in RollNewDay → überlebt Restart+Tag | MinGap=0→aus; LAST_ENTRY=0→durch; exakt 10 s→erlaubt | <10 s blockt, ≥10 s durch |
| **R15** Entry Z556-562 | (a) SL<5 Pips block (b) Lot>MaxLot kappen | (a) 3 Pips (b) MaxLot 0,10 | (a) BLOCKED R15 (b) Lot=0,10, rp neu | kein State | MinStop=0→aus; Broker-StopLevel nur Notify; Kappung<MinLot→kein Trade | <5 Pips blockt, MaxLot kappt + rp zieht nach |
| **R16** Entry Z538, OffSession | außerhalb Session/News block | Session 8-22 @23h; News 1400-1500 @14:30 | BLOCKED, Panel AUSSER SESSION | kein State; zeitbasiert | Start==End→immer Session; Over-Midnight; From==To→kein Blackout | außerhalb blockt, Over-Midnight korrekt |
| **R17** Entry Z576-581, NetUsdRiskPct | \|Netto-USD\| ≤1,5 % | USD-long bis 1,50 %; +0,25 % | BLOCKED "R17 Korrelation" | live; konsistent n. Restart | Gegenricht. nettet; Nicht-USD→0; USDJPY Pos.0; CorrCap=false→aus | >1,51 % blockt, Netting korrekt, Nicht-USD ignoriert |
| **R18** Cycle Z309-319, RG_WEEK_* | Wochen-DD≥5 % sperrt | WEEKSTART 20000, eq≤19000 | IsWeekLocked, SafeCloseAll, Panel WOCHE GESPERRT | GV, NICHT in RollNewDay → über Tage hinweg | 4,99 %→kein; Wochenwechsel (Do 00:00 UTC)→frei; Doppel-Lock-Schutz | 5 % sperrt, Tageswechsel löst NICHT, Wochenwechsel löst |
| **R19** EffectiveRiskPct Z201-206 | ab 2 Verlusten Risiko ×0,5 | CONSEC=2; normaler Trade | Lot halb, rp≈0,125 %, `OPEN rp≈0.12` | RG_CONSEC GV → De-Risk n. Restart aktiv | C=1→voll; Gewinn→0; Factor=1.0→aus; halb<MinLot→kein Trade | ab 2 exakt 0,125 % |
| **R25** Entry Z539, RevengeBlocked | Gegen-Trade 10 min gesperrt | EURUSD BUY net<0; <10 min SELL | BLOCKED "R25 Revenge" | g_rev in-memory → n. Restart WEG (FAIL falls Persistenz gefordert) | gleichricht. erlaubt; anderes Symbol; >10 min frei; net==0→kein SetRevenge | Gegenricht. blockt, Restart-Verlust dokumentieren |

**Querschnitt-Pflichten:** Gate-Reihenfolge in `DoEntry` (AutoTrading→Lock→TargetHit→Cooldown→OffSession→Revenge→MinGap→SL-Linie/Seite/Broker→MinSL→Lot/MaxLot→Idee→Tag→Heat→Korrelation→OrderSend) — spätere Gates nur testbar, wenn frühere passieren. Zwei Mitternachts-Defs (ServerDayKey vs NextServerMidnight) explizit testen. net==0-Lücke (R5/R6/R19/R25). RG_DAY_RISK additiv. Version am Print-String identifizieren.

---

## 5. ENTSCHEIDUNG

**C) Für FTMO nicht sicher genug.**

Begründung: Sieben P0-Defekte treffen alle drei tragenden Säulen des Tools gleichzeitig — (a) der Schutz schließt nicht zuverlässig (P0-1: Enforce nur bei Ticks; P0-6: 8 %-Trigger ohne Puffer), (b) die Disziplin-Buchführung ist falsch/flüchtig (P0-2: Downtime-Closes verpasst; P0-3: Eigen-Closes als Verlust gezählt; P0-4: Partials doppelt; P0-5: nicht-FTMO-konforme Tagesbasis), und (c) die Unausweichlichkeit existiert lokal nicht (P0-7). Der Header sagt selbst „NUR DEMO / UNGETESTET", und der EA wurde nie als Ganzes kompiliert/getestet. Ein Tool, dessen einziger Zweck Risiko-Erzwingung ist und das auf der dokumentierten Zielplattform (Wine, ~minütliche Crashs) genau diese Erzwingung verliert, darf kein echtes/bezahltes FTMO-Konto berühren. Nach Abarbeitung der P0+P1-Patches, Umzug auf Windows-VPS und einem grünen Strategy-Tester-Lauf der kompletten Regel-Matrix ist „A) testbereit" erreichbar — aktuell nicht.

---

## 6. Konkrete Patch-Reihenfolge für v0.15

1. **`MathMax(AccountBalance(),AccountEquity())` in `RollNewDay` Z165/Z171** (P0-5) — FTMO-konforme R4-Basis; isolierter 2-Zeilen-Fix, Grundlage aller DD-Messungen.
2. **Enforce vom `allowTrades`-Gate entkoppeln, `OnTimer→Cycle(false,true)`** (P0-1, P1-1, P1-14) — Watchdog läuft tickunabhängig; fundamentaler Schutzpfad, blockiert sonst alle Close-Tests.
3. **`g_eaClosed[]`-Ausschlussliste + `TakeEaClosed` in `ResolveClosed`** (P0-3) — verhindert Selbst-Bestrafungs-Kaskade; muss VOR dem History-Umbau stehen, da dieser dieselben Close-Pfade nutzt.
4. **History-basierte, idempotente Verlust-Auflösung (`RG_LAST_CLOSE`, MODE_HISTORY, CloseTime-Sortierung, `ApplyConsecThresholds`)** (P0-2, P0-4, P1-3, P2-6, P2-8) — ersetzt g_known; behebt Downtime/Partials/Determinismus in einem Zug. Hängt von Patch 3 (EA-Close-Erkennung) ab.
5. **Magic-Filter in `UpdateStreak`/`ResolveClosed` + allen Enforce-Schleifen + Risk-Aggregatoren** (P2-7, P1-11) — nur eigene Tool-Trades managen/zählen; FTMO-Compliance + Serien-Sauberkeit.
6. **R4b: `InpMaxLossPct` 8→6 + `InpMaxLossWarnPct`-Entry-Gate in `DoEntry`** (P0-6) — proaktiver Puffer; unabhängig, nach den Streak-Fixes einbaubar.
7. **Persistente Lockstate-Datei (HMAC, fail-closed) in `OnInit`; Revenge/Streak mitspiegeln** (P0-7, P1-6) — No-Override-Härtung; baut auf der nun korrekten Streak-Persistenz (Patch 4) auf.
8. **`GV_DAY_RISK`-Reconciliation (`max(persistiert, OpenedTodayToolRiskPct())`) + `GlobalVariablesFlush()` nach Z589** (P1-5) — schließt Crash-Unterzählung von R3.
9. **Zeitquelle `TimeCurrent`→`TimeTradeServer` (Z98/99/100 + Sperr-Checks)** (P1-4) — zuverlässiger Tageswechsel ohne Ticks; isoliert, geringe Kollisionsgefahr.
10. **R7-Naked: Anker `OrderOpenTime()`, `GetTickCount`-Granularität, Grace 3-5 s, News-Grace 0** (P1-7, P2-5) — crash-immune, schnellere SL-Pflicht.
11. **R17 echtes Währungs-Vektor-Exposure (Basis+Quote, Cross-Pairs)** (P1-8) — schließt das größte Exposure-Loch; größerer, eigenständiger Umbau.
12. **Journal-Signatur erweitern (Ticket/Magic/Account/Balance/Equity/DayKey/ruleId/net) + FILE_SHARE** (P1-10, P2-12-R11-2) — Audit-Tauglichkeit; berührt alle Call-Sites, daher spät.
13. **`#define EA_VERSION`, Header/Print/Panel angleichen, R25 in Header** (P3-6) + RULES.md v2 als Source of Truth (P3-7) — Versions-/Doku-Hygiene vor Freigabe-Kommunikation.
14. **Deployment: Windows-VPS + Heartbeat; FTMO-Freigabe für Auto-Close/One-Click schriftlich einholen; `InpFundedApproved`-Gate** (P1-13, P1-12) — betrieblicher Abschluss; erst sinnvoll, wenn Code grün ist.
15. **P2-Rest (net==0-Toleranz, R8 netto-CRV, EnforceHeat=riskanteste Position, Giveback-Closed-Equity, Session/News-Härtung, Tickwert-Konvertierung)** — Feinschliff nach den Blockern; je nach Resttest-Befund.