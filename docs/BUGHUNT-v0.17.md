# Bug-Hunt v0.17 — Befunde (2026-06-27)

Mehr-Agenten-Bug-Hunt (10 Jäger-Lenten + 2 Tiefenbohrungen, je Kandidat 2 unabhängige Skeptiker). 31 Kandidaten → **20 bestätigt, 4 wahrscheinlich**. Zeilennummern beziehen sich auf den Stand zum Hunt-Zeitpunkt.

> **✅ GEFIXT in v0.18 (adversarial verifiziert, 0 Probleme, brace-sanity 247/247 1779/1779, F7 ausstehend):** B1, B2, B3 (+B9-Warnung), B4+B6, B5+B8, B16, B17, B20. Fix-Verify-Workflow bestätigte je Fix: korrekt + MQL4-valide (`MqlDateTime`/`day_of_week` explizit geprüft) + keine Regression.
> **✅ GEFIXT in v0.19 (statischer Review-Batch, fix-verifiziert, F7 ausstehend):** **B11** (R1 stabile Tagesbasis statt Live-Equity), **B19** (SplitCcy ISO-Check), **L4** (net==0 setzt Serie zurück) — **plus neue Review-Befunde:** P0 SafeCloseAll-vs-TOOL_ONLY (Warnung bei fremden offenen Positionen unter Lock), P0 Division-durch-0 bei `g_initialBalance<=0` (TotalDDpct-guarded + fail-closed), P0/P1 Prop-Firm-Zeitprofil (`InpDayResetHour`/`InpWeekStartDay`), P1 ResolveHistory chronologisch sortiert, P1 `ERR_MARKET_CLOSED` 15-min-Backoff (kein Request-Storm), P1 `InpRR<InpMinRR` hart geklemmt.
> **⏳ OFFEN (in Rule-Test-Matrix beweisen):** B7 (PC-TZ bei `TimeCurrent==0`), B10 (HasOpenRemainder Same-Second), B12, B13, B15 (RollNewDay vor ResolveHistory), B18 (Throttle bei Context-Busy), L3 (FILE_SHARE bei Mehrfach-Charts). *Begründung der Zurückstellung: niedrige Eintrittswahrscheinlichkeit bzw. semantische Entscheidung, die sich besser am Live-Verhalten zeigt.*
> **Semantik-Notiz B4/6:** Bei gemischtem Close (Trader-Teil + EA-Rest) zählt bewusst NUR der vom Trader geschlossene Netto-Anteil für Serie/Cooldown/Revenge (Disziplin-Tool wertet die Entscheidung des Traders, nicht die Positions-P/L).

Legende Severity: 🔴 kritisch · 🟠 hoch · 🟡 mittel · ⚪ niedrig

---

## 🔴 KRITISCH

### B1 — Max-Loss-Basis hängt am Default 20000 → R4b-Schutz auf Nicht-20k-Konten still abgeschaltet
**Wo:** `OnInit` (g_initialBalance-Auswahl) → `TotalDDpct()` → R4b Hard-Lock + Warn-Gate.
**Problem:** `InpInitialBalance` hat Default **20000** (immer >0), daher gewinnt `if(InpInitialBalance>0) g_initialBalance=InpInitialBalance;` IMMER; die Fallbacks (GV_INIT_BAL / AccountBalance) sind tot. g_initialBalance ist die Basis des Gesamt-Drawdowns.
**Auslöser:** Konto ≠ 20.000 € ohne manuelles Setzen. **100k-Konto bei 95k (5% echt) → TotalDDpct = (20000−95000)/20000 = −375% → auf 0 geklemmt → R4b feuert NIE** (Haupt-Schutz aus). **10k-Konto → DD ~2× überschätzt → Fehl-Sperre** ab erstem Tick.
**Fix:** Default `InpInitialBalance=0` (→ echte Konto-Basis via GV_INIT_BAL/AccountBalance) **+** lautes Warnen, wenn explizit gesetzter Wert stark von AccountBalance abweicht.

---

## 🟠 HOCH

### B2 — R18 Wochenlimit resettet mitten in der Woche (Donnerstag 00:00)
**Wo:** `WeekIdx()` = `SrvTime()/(7*86400)` (Epoch-Grid = Donnerstag-Grenze); Wochen-Reset in `Cycle()`.
**Problem/Auslöser:** Mi-Nacht −4,9% (knapp unter 5%) → Do 00:00 wird Wochenbasis + Wochensperre zurückgesetzt → Do–Fr nochmal volle 5% möglich → real ~10% Wochenverlust ohne dass R18 greift. Umgekehrt: Di/Mi gesetzte Sperre wird Do 00:00 aufgehoben.
**Fix:** Woche am echten Wochenende ankern, z. B. `WeekIdx(){ datetime t=SrvTime(); return (long)(t/86400) - TimeDayOfWeek(t); }` (Sonntag-Mitternacht-Grenze).

### B3 — R8 (EnforceRR) schließt frisch eröffnete Tool-Trades wegen Fill-Slippage
**Wo:** `EnforceRR()` vs `DoEntry()` TP-Berechnung.
**Problem/Auslöser:** TP wird am *angefragten* Entry gesetzt, das CRV aber aus `OrderOpenPrice()` (echter Fill) berechnet. Bei engem Stop + Slippage kann CRV < InpMinRR → der gerade eröffnete In-Plan-Trade wird sofort wieder geschlossen.
**Fix:** Tool-Trades (`Magic==InpMagic`) von R8 ausnehmen (sind per Konstruktion RR-konform) — zusammen mit B9 (InpRR≥InpMinRR validieren).

### B4 + B6 — Teil-Close durch Trader wird als EA-Close fehletikettiert → Verlust fällt aus der Serie
**Wo:** `ResolveHistory()` `gEa`-Aggregation (ODER-Semantik) + Skip.
**Problem/Auslöser:** Alle Teil-Closes einer Position werden gruppiert; `gEa` wird TRUE, sobald **ein** Bein einen EA-Marker trägt → die GANZE Gruppe gilt als „EA-Schutz-Close (zählt nicht)". Schließt der Trader einen Teil mit Verlust und der EA den Rest → Trader-Verlust verschwindet aus Cooldown/Serie/Revenge.
**Fix:** EA-Netto und Manuell-Netto je Gruppe **getrennt** summieren; `ApplyResult` auf den manuellen Anteil, nur den EA-Anteil ausschließen.

### B5 + B8 — EA-Close-Marker: false-negative-Unmark + Mark-vor-Close-Fenster → Schutz-Close zählt als Trader-Verlust (Fehl-Sperre)
**Wo:** `ProcessCloseQueue()` (MarkEaClosed vor OrderClose; UnmarkEaClosed bei OrderClose==false).
**Problem/Auslöser:** (B5) OrderClose kann `false` liefern, obwohl die Position serverseitig schloss (Requote/Timeout) → Code unmarkt → echter EA-Close zählt als Trader-Verlust → falsche Tagessperre/Cooldown. (B8) Mark-vor-Close-Crash-Fenster → echter Verlust evtl. als EA-Close ausgeschlossen.
**Fix:** Marker erst **nach bestätigtem** Close setzen: OrderClose→true → MarkEaClosed; OrderClose→false → Ticket neu selektieren, wenn `OrderCloseTime()!=0` (doch geschlossen) → MarkEaClosed+entfernen, sonst Retry ohne Marker. Pre-Mark + Unmark-on-fail entfernen.

---

## 🟡 MITTEL

### B7 — Locks/Tagesschlüssel in PC-Zeitzone, wenn `TimeCurrent()==0` bei OnInit
**Wo:** OnInit + `SrvTime()`-Fallback. Brandneuer Chart ohne Quote → Offset ungesetzt → SrvTime = PC-Zeit (lokale TZ) → Tagesschlüssel/Locks falsch, springen beim ersten Tick.
**Fix:** Schwere Init (RollNewDay/Reconcile/GV_LAST_CLOSE-Seed) erst ausführen, wenn Serverzeit bekannt (`g_srvOffsetSet`/TimeCurrent>0); sonst auf ersten Tick verschieben.

### B9 — Keine `InpRR ≥ InpMinRR`-Prüfung → Öffnen-dann-Sofort-Schließen-Schleife bei Fehlkonfiguration
**Wo:** OnInit (fehlende Validierung); DoEntry-TP vs EnforceRR.
**Fix:** In OnInit prüfen: `InpMinRR<=0 || InpRR>=InpMinRR`; sonst InpRR hochklemmen + Notify oder Entries sperren.

### B10 — `HasOpenRemainder` kann bei Same-Second-Re-Entry false-positiv → realer Verlust unendlich aufgeschoben
**Wo:** `HasOpenRemainder()` matcht OpenTime+Type+Symbol+Magic+OpenPrice (nicht eindeutig).
**Fix:** Identität verschärfen (Entry-Ticket-Lineage je Position), statt nur die ProcKey-Felder.

### B11 — Live-Equity-Nenner in EnforceRisk schließt korrekt dimensionierte Positionen, wenn Equity fällt
**Wo:** `EnforceRisk()` via `RiskPctOf()` (Nenner AccountEquity). Fallende Equity erhöht das gemessene %-Risiko → R1 schließt eine bei Eröffnung korrekte Position.
**Fix:** R1-Enforcement gegen stabile Basis (Entry-Equity/DayRiskBase) statt Live-Equity rechnen.

---

## ⚪ NIEDRIG (Auswahl)

- **B12** — `nowMs=GetTickCount()` wird in `ProcessCloseQueue` einmal vor der Schleife gesampelt; nach langsamem OrderClose ist der Backoff für Folge-Tickets verzerrt. *Fix:* nowMs je Iteration neu lesen.
- **B13** — Bei FINAL-FAIL wird ein noch offenes Ticket aus der Queue entfernt; Re-Enqueue hängt am Detektor. *Fix:* `Notify`/Alert bei FINAL-FAIL (nicht nur Journal).
- **B15** — `RollNewDay()` (resettet GV_CONSEC) läuft VOR `ResolveHistory()` → ein kurz vor Mitternacht geschlossener Verlust wird dem neuen Tag zugeschlagen und verliert Cooldown/Serie. *Fix:* ResolveHistory vor dem Consec-Reset.
- **B16** — `MODE_MAXLOT`==0 vom Broker → `if(lot>mx) lot=mx` setzt Lot auf 0 → Entry blockiert. *Fix:* `if(mx<=0) mx=lot;`.
- **B17 (+L1/L2)** — Close-Queue-Backoff-Gate nutzt nicht-wrap-sicheren Vergleich `nowMs < g_qNextMs[i]`; bei GetTickCount-Wrap (~49,7 Tage) friert der Close ein. *Fix:* wrap-sicher `(int)(nowMs - g_qNextMs[i]) < 0`.
- **B18** — `g_lastEnforceMs` wird auch verbraucht, wenn `IsTradeContextBusy` alles blockt → 300ms-Fenster „verschenkt". *Fix:* Throttle nur setzen, wenn wirklich enforced wurde.
- **B19** — `SplitCcy` steckt 6-buchstabige Nicht-FX-Symbole in Phantom-Währungs-Buckets (R17). *Fix:* Währungs-Code-Plausibilität/FX-Check vor dem Split.
- **B20** — `OnInit` `ObjectsDeleteAll(0,"RG_")` nutzt falschen Präfix; Panel-Objekte heißen `MMT_` → Cleanup ist ein No-Op. *Fix:* `ObjectsDeleteAll(0,PFX)`.
- **L3** — Journal/Lockstate-`FileOpen` ohne `FILE_SHARE_*` → bei mehreren Charts desselben Kontos Schreib-/Leseverlust. *Fix:* `FILE_SHARE_READ|FILE_SHARE_WRITE`; leeren Read als „busy" statt „CORRUPT" behandeln.
- **L4** — `ApplyResult` behandelt `net==0` (Break-even) weder Reset noch Verlust → Serie bleibt unverändert. *Fix:* `net>=0`-Semantik explizit machen.

---

## Einordnung
Keiner dieser Bugs verhindert das Kompilieren (F7=0) — es sind **Laufzeit-/Logik-Bugs**, genau die Klasse, die F7 nicht fängt und die Tests/Reviews fangen. **B1 (kritisch)** und **B2/B4+B6/B5+B8 (hoch)** betreffen direkt Geld/Schutz und sollten vor jedem Demo-Test gefixt werden.
