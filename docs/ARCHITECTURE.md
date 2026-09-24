# Architektur (Stand v0.35)
*Reifegrad „wie fertig": siehe [`STATUS.md`](STATUS.md). Regelwerte verbindlich: [`../RULES.md`](../RULES.md).*

## Ist-Zustand: ein einziger EA
Die gesamte **Regel-Logik und Durchsetzung** steckt in **einem MQL4-Expert-Advisor** (`ea/mt4/MamalTrading.mq4`), der im MT4-Terminal läuft. Bedienung über ein On-Chart-Panel. **Seit v0.26** kommt die ursprünglich verworfene **DLL-freie Datei-Brücke** doch dazu — aber ausschließlich als **Lese-Ansicht**: der EA schreibt seinen Zustand als JSON, ein zero-dependency Node-Server (`cockpit/`) serviert daraus ein localhost-Dashboard. Das Cockpit **entscheidet nichts** und kann nichts entsperren; fällt es aus, ändert sich am Schutz nichts (siehe unten „Nachträglich doch gebaut").

### Komponenten im EA
- **Event-Schleife:** `OnInit` / `OnTick` / `OnTimer` / `OnChartEvent`. Kern = `Cycle()`.
  - **Enforcement läuft aus `OnTick` UND `OnTimer`** (ab v0.15, tickunabhängig) — Schutz greift auch in tickarmen/gappy Märkten. Detection reiht Tickets in die **echte Close-Queue** (v0.16: Retry-Limit/Backoff/Error-Codes/Journal je Versuch); `ProcessCloseQueue()` schließt tatsächlich. *(Die „nur OnTick"-Notlösung aus v0.8 ist ersetzt.)*
- **Risiko-Engine:** `CalcLot` (Auto-Lot aus SL-Abstand), `RiskPctOf`, `EffectiveRiskPct` (R19), Auto-Scale-Caps `EffIdeaCap/EffHeat/EffDay`.
- **One-Click-Entry:** rote SL-Linie (`OBJ_HLINE`), BUY/SELL-Buttons (`OBJ_BUTTON`), `DoEntry` mit gestaffelten Gates → `OrderSend`.
- **Enforcement:** `EnforceSLTP` (R7), `EnforceRisk` (R1), `EnforceRR` (R8), `EnforceHeat` (R12), `SafeCloseAll` (Sperren) — **seit v0.35** zusätzlich `EnforceManualTrades` (R22, schließt Magic-0-Orders; die einzige dieser Funktionen **ohne** `InScope()`-Filter).
- **Persistenz:** `GlobalVariables` (`RG_*`), überleben Neustart; Tages-/Wochen-Reset über Serverzeit.
- **Panel:** Chart-Objekte (`MMT_*`), gedrosseltes Neuzeichnen (nur bei Änderung).
- **Journal:** CSV in `MQL4/Files/`.

Details: [TECHNISCHE-DOKU.md](TECHNISCHE-DOKU.md).

## Die drei ehrlichen Wahrheiten (Design-Fundament)
1. **Erkennen-und-schließen, nicht verhindern.** MT4 hat keinen Pre-Trade-Veto-Hook; der EA reagiert mit Latenz (Polling) → kurzes Schaden-Fenster, gedeckelt durch R4/R4b. Echte Prävention nur server-seitig.
2. **No-Override lokal = nur Reibung.** GlobalVariables löschbar, AutoTrading abschaltbar, EA entfernbar. Echte Unwiderruflichkeit erst auf **gesperrtem VPS + FTMO-Serverlimit**. *(Review P0-7: Härtung per Checksum-Lockstate-Datei/fail-closed in v0.16 gebaut — Backstop, kein echtes Immutable.)*
3. **Mac/Wine ist instabil.** Für eine echte Challenge gehört der EA auf einen **Windows-VPS**.

## Compliance-Konsequenz
Der EA **eröffnet Trades** (One-Click `OrderSend`) und **schließt/blockt** Positionen (kein `OrderModify` — er trägt keine SL/TP nach, sondern schließt; SL/TP werden nur beim `OrderSend` gesetzt). Klick-ausgelöst ≠ autonom, aber vor Real/Funded ist **Prop-Firm-Regel-Compliance** zu prüfen — keine schriftliche FTMO-Bestätigung als Pflicht-Blocker, aber Copy-Trading-/EA-Regeln **pro Prop Firm** abklären (FTMO/The5ers/FundedNext/… ; siehe [PROP-FIRM-READINESS.md](PROP-FIRM-READINESS.md) Punkt 13). Positionen **fremder EAs** (eigene Magic ≠ 0) fasst der Watchdog seit v0.15 nicht mehr an (Magic-Filter `InScope`/`WatchScope`, Default `TOOL_ONLY`, Review P1-11). **Einschränkung seit v0.35:** R22 (`EnforceManualTrades`) umgeht diesen Filter und schließt **manuelle Magic-0-Orders** des eigenen Kontos kontoweit — auch im FundedMode. Firmenspezifisch zu verifizieren, siehe [COMPLIANCE.md](COMPLIANCE.md) Abschnitt 1.1.

## Verworfen → nachträglich doch gebaut (Datei-Brücke, v0.26)
Der erste Entwurf war ein **Hybrid**: EA-Watchdog *plus* separates **Tauri-Cockpit** + **DLL-freie Datei-Brücke** in `MQL?/Files`. Das wurde zunächst zugunsten eines einzigen EA mit On-Chart-Panel verworfen (schneller, weniger bewegliche Teile, kein Cockpit-Desync). **Seit v0.26 existiert die Datei-Brücke doch** — aber in der entschärften Form: kein Tauri-Client, sondern EA→`mamal_cockpit.json` (atomar, alle 2 s) → zero-dependency Node-Server `cockpit/server.js` → Browser (`dashboard.html`, Tagesdetail `day.html`). **Einbahnstraße:** das Cockpit liest nur, es kann keine Regel setzen, lockern oder entsperren — der Desync-Einwand von damals bleibt damit gegenstandslos. Der **Tauri-Client** ist weiterhin verworfen.

## Event-Schleife & Zustand (ab v0.15/v0.16)
`Cycle()` läuft aus **OnTick und OnTimer** (P0-1), damit der Schutz auch ohne Ticks greift („Trades nur aus OnTick" aus v0.8 ist überholt). Die Verlustserie wird **history-basiert** (`ResolveHistory`, Wasserstand `RG_LAST_CLOSE`) statt in-memory aufgelöst. **WatchScope** (`InpWatchScope`, Default `TOOL_ONLY`): `TOOL_ONLY`/`TOOL_PLUS_MANUAL` fassen fremde Magics nicht an; `ALL_POSITIONS` fasst alles an (nur Demo/Debug, **nicht Real/Funded** — bei jeder Prop Firm hart `TOOL_ONLY`). **v0.35:** R22 hängt nicht am `WatchScope`; mit `InpCloseManualTrades=true` ist `TOOL_PLUS_MANUAL` praktisch wirkungslos, weil Magic-0-Orders ohnehin geschlossen werden.

**v0.16:** echte **Close-Queue** (`RequestClose`/`ProcessCloseQueue`: Retry-Limit, exponentieller Backoff, Error-Code-Handling, Journal je Versuch) statt Direkt-Close; **Lockstate-Datei** (`MamalTrading_Lockstate.dat`, HMAC-light-Checksumme, fail-closed bei Beschädigung) als Backstop neben den GlobalVariables; **Schutz-aus-Logging** (`PROTECT_OFF`/`PROTECT_ON`/`TAMPER`); **R3-Reconciliation** (`RG_DAY_RISK` nach Crash aus heute eröffneten Tool-Trades rekonstruiert, `max(persistiert, rekonstruiert)`, eine stabile %-Basis); **tickunabhängige Server-Zeit** (`SrvTime()` = `TimeLocal()` + am Tick gepflegtem Server-Offset; MQL4 hat **kein** `TimeTradeServer`, das ist MQL5). Status: **Demo-only, nicht Prop-Firm-ready** — F7 bis R3 = 0 Errors, `SrvTime`-F7 + **Rule-Test-Harness/Regelmatrix** + Demo-Forward-Test + **Prop-Firm-Regel-Compliance** stehen aus (siehe [PROP-FIRM-READINESS.md](PROP-FIRM-READINESS.md)).
