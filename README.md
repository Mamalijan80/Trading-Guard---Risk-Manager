# TradingGuard

**Lizenz:** AGPL-3.0 · **Stand:** EA v0.66, Cockpit v0.65 · **Reifegrad:** Demo — noch nicht prop-firm-ready
**Autor:** Mohammadreza Tavakoli — [itavakoli.com](https://itavakoli.com/)

> ⚠️ **Bevor du es auf ein echtes oder Funded-Konto lässt: nicht.** Der Code kompiliert fehlerfrei
> und ist mehrfach adversarial reviewt, aber von 258 Testfällen sind erst rund ein Dutzend live
> geprüft, und ein Demo-Forward-Test über mehrere Wochen steht komplett aus. Verbindliche
> Einstufung: [`docs/STATUS.md`](docs/STATUS.md). **Keine Anlageberatung, keine Gewährleistung.**


Persönliches **Risiko-/Disziplin-Tool** für MetaTrader 4 (MT5-Spiegel geplant). Zweck: **nicht** Strategie finden, sondern Risiko- und Ausführungsverhalten **erzwingen**. Kein Strategie-Bot — ein Disziplin-Werkzeug für **Prop-Firm-Challenges** (FTMO als Default-Profil, **Multi-Prop-Firm** geplant). Konto-Basis Beispiel 20.000 € (FTMO).

> **Source of Truth = [`RULES.md`](RULES.md).** Alle anderen Dokumente leiten sich davon ab.

## Was es tatsächlich ist (Stand v0.35)
Die **gesamte Durchsetzung** steckt in einem **einzigen Expert Advisor** (`ea/mt4/MamalTrading.mq4`) im MT4-Terminal mit:
- **On-Chart-Panel** (Status, Verlust-/Risiko-Balken, BUY/SELL-Buttons) als Haupt-Bedienung. **Ergänzend seit v0.26:** ein optionales localhost-Cockpit (`cockpit/`, Node-Server + `dashboard.html` + `day.html`) — reine **Ansicht** über die DLL-freie Datei-Brücke (EA schreibt JSON), **keine** Regel-Logik, abschaltbar per `InpCockpit=false`.
- **Risk-basiertem One-Click-Entry:** rote SL-Linie ziehen/klicken → Tool berechnet das Lot für ein festes Risiko → BUY/SELL eröffnet den Trade (SL an der Linie, TP bei RR).
- **Nur Panel-Trades (R22, seit v0.35, Default an):** von Hand im MT4-Fenster eröffnete Orders (Magic 0) werden **kontoweit** erkannt und **nachträglich geschlossen** — Positionen zu Marktpreis, Pendings gelöscht. Grund: nur der Panel-Weg durchläuft die Entry-Gates (R1/R2/R3/R7/R12/R17 …). **Ehrliche Grenze:** das ist *detect-and-revert*, kein Verhindern — der Trade geht auf und wird danach zurückgedreht, **Spread und Slippage trägt der Trader**; Erkennung typisch Bruchteile einer Sekunde bis mehrere Sekunden. Fremde EAs (eigene Magic ≠ 0) bleiben unangetastet. Abschaltbar per `InpCloseManualTrades=false`.
- **Regelwerk R1–R19 + R22 + R25** (R9 aus), **Auto-Scale-Caps**, Verlust-/Wochen-Sperren, Cooldown, Revenge-Fenster, CSV-Journal.
- Persistenz über `GlobalVariables` + Lockstate-Datei (fail-closed); Enforcement aus `OnTick` **und** `OnTimer` (tickunabhängig, ab v0.15) + echte Close-Queue (v0.16); tickunabhängige Server-Zeit (`SrvTime()` = PC-Uhr + am Tick gepflegtem Server-Offset; MQL4 hat **kein** `TimeTradeServer`).

## ⚠️ Wichtiger Hinweis (Compliance)
Anders als ursprünglich geplant **öffnet das Tool Trades selbst** — per **One-Click `OrderSend`** mit berechnetem Lot und eigenem TP. Das ist **klick-ausgelöst** (kein autonomes Auto-Trading, **keine Signal-Generierung**) + autonomes Risk-Management (Schließen/Blocken). Damit sitzt es in der **meist-erlaubten** Prop-Firm-Automations-Kategorie. **Compliance-Check (5 Firmen, mit Quellen): [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md)** — FTMO/The5ers/FundedNext/FundingPips „likely-allowed" (Bedingungen), **Alpha Capital verlangt schriftliche Pre-Approval**. Vor jedem Real-/Funded-Konto firmenspezifisch verifizieren; `InpFundedMode=true` setzen.
**Seit v0.35 zusätzlich zu prüfen:** R22 schließt **auch im FundedMode** Orders, die der EA **nicht selbst geöffnet** hat — es ist die einzige Enforcement-Funktion, die den `InScope()`-Filter umgeht. Ob eine Firma das akzeptiert, ist firmenspezifisch zu klären.

## Status & Sicherheit
- **v0.35 ist NUR DEMO und nicht Prop-Firm-ready.** Reifegrad = **fix-verifiziert (KI-Review), aber LIVE-UNGETESTET** — verbindliches Reifegrad-Modell: [`docs/STATUS.md`](docs/STATUS.md). Die P0/P1 des Ausgangs-Reviews [`docs/REVIEW-v0.14.md`](docs/REVIEW-v0.14.md) (eingefroren, beschreibt v0.14, Entscheidung **C**) sind in v0.15–v0.18 abgearbeitet + per Bug-Hunt ([`docs/BUGHUNT-v0.17.md`](docs/BUGHUNT-v0.17.md)) nachgehärtet. Roadmap: [`docs/PROP-FIRM-READINESS.md`](docs/PROP-FIRM-READINESS.md).
- **Sicherheitsregel Nr. 1:** Nichts berührt ein echtes/Funded-Konto, bevor die Roadmap grün ist: F7 + **Rule-Test-Harness/Regelmatrix** + Demo-Forward-Test + **Prop-Firm-Regel-Compliance** + Windows-VPS.
- **Deployment:** erst lokal (Demo). Für Stabilität *und* echtes „No-Override" → **Windows-VPS** (MT4 über Wine auf Apple Silicon ist instabil).

## Schnellstart

1. **EA installieren:** `ea/mt4/MamalTrading.mq4` nach `<MT4-Datenordner>/MQL4/Experts/` kopieren,
   in MetaEditor mit **F7** kompilieren, dann auf einen Chart ziehen. AutoTrading einschalten.
2. **Basis setzen:** `InpInitialBalance` auf die echte Challenge-Startbalance — **ohne Tausender-Trennzeichen**
   (`10000`, nicht `10.000`; MetaTrader liest sonst 10,0).
3. **Wochen-Risiko festlegen:** Im Panel den Prozentwert eintippen und **SETZEN** drücken. Ohne
   bewusste Wochenentscheidung wird nicht gehandelt (Regel R23) — das ist Absicht, kein Fehler.
4. **Cockpit (optional):** `cockpit/start.bat` (Windows) bzw. `cockpit/start.command` (macOS) starten,
   dann `http://localhost:8730`. Node.js genügt, keine Abhängigkeiten, keine DLL. Abschaltbar per
   `InpCockpit=false`.

Das Cockpit ist **reine Ansicht**. Die gesamte Regel-Durchsetzung steckt im EA und läuft auch dann
weiter, wenn der Server aus ist.

## Mitmachen

Fehlerberichte sind willkommen — besonders aus dem echten Demo-Betrieb, denn genau dort fehlt die
Abdeckung. Wer einen Befund meldet, hilft am meisten mit: MT4-Build, EA-Version aus der
`BootDiag`-Zeile im Journal, die betroffenen Journal-Zeilen und was du erwartet hättest.

## Lizenz

**GNU Affero General Public License v3.0** — siehe [`LICENSE`](LICENSE).

Kostenlos für alle, auch kommerziell. Die einzige Bedingung, die zählt: **Urheberangabe bleibt
erhalten.** Wer TradingGuard weitergibt, verändert oder als Netzwerkdienst betreibt, muss den
Quelltext unter derselben Lizenz offenlegen und Autor und Herkunft nennen:

> TradingGuard — © Mohammadreza Tavakoli, [itavakoli.com](https://itavakoli.com/)

Die AGPL wurde bewusst gewählt: Sie verhindert, dass jemand dieses Werkzeug als geschlossenes
Abo-Produkt weiterverkauft. Für Prop-Trader ist offener Quelltext ohnehin ein Vorteil — The5ers
etwa untersagt EAs, deren Quelltext der Trader nicht besitzt (siehe [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md)).

**Haftungsausschluss:** Dieses Werkzeug erzwingt Regeln. Es trifft keine Marktentscheidung, gibt
keine Anlageberatung und übernimmt keine Verantwortung für Handelsergebnisse. Handel mit
Hebelprodukten kann zum Totalverlust führen. Die Software wird ohne jede Gewährleistung
bereitgestellt.

## Dokumente
- [`RULES.md`](RULES.md) — Regel-Vertrag (Source of Truth)
- [`docs/REGELN-EINFACH.md`](docs/REGELN-EINFACH.md) — **Regeln einfach erklärt** (ohne Technik, mit ausführlichen Beispielen)
- [`docs/REGELN.md`](docs/REGELN.md) — ausführliche Regel-Beschreibung
- [`docs/REGELN-TABELLE.md`](docs/REGELN-TABELLE.md) — Spickzettel
- [`docs/TECHNISCHE-DOKU.md`](docs/TECHNISCHE-DOKU.md) — technische Umsetzung
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — Architektur-Entscheidung
- [`docs/REVIEW-v0.14.md`](docs/REVIEW-v0.14.md) — kritische Review + v0.15-Patchplan (eingefrorenes Artefakt)
- [`docs/PROP-FIRM-READINESS.md`](docs/PROP-FIRM-READINESS.md) — Roadmap zu „Prop-Firm-ready" (Multi-Prop-Firm)
- [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) — Prop-Firm-Compliance-Check (5 Firmen, mit Quellen)
- [`docs/STATUS.md`](docs/STATUS.md) — **Reifegrad-Modell** (gebaut/kompiliert/fix-verifiziert/getestet) — gilt für „wie fertig"
- [`docs/BUGHUNT-v0.17.md`](docs/BUGHUNT-v0.17.md) — Bug-Hunt-Befunde (gefixt vs. offen)

## Ordnerstruktur
```
TradingGuard/
├─ README.md
├─ RULES.md                     # Source of Truth
├─ LICENSE                      # AGPL-3.0
├─ ea/
│  ├─ mt4/MamalTrading.mq4      # der aktive EA — die gesamte Regel-Durchsetzung (v0.66)
│  ├─ mt5/RiskGuard.mq5         # obsoleter Vorgänger, bleibt als Referenz liegen
│  └─ shared/CORE-PLAN.md       # geteilte Logik + Plan
├─ cockpit/                     # localhost-Ansicht (Node, ohne Abhängigkeiten)
│  ├─ server.js                 # Datei-Brücke + HTTP-Endpunkte
│  ├─ dashboard.html            # Live-Cockpit (DE/EN/FA)
│  ├─ trade.html                # Trade-Akte: Screenshots, SL/TP-Chronik, Auswertung
│  ├─ day.html · report.html    # Tagesdetail und Wochenbericht
│  └─ i18n.js                   # Übersetzungen
└─ docs/                        # Regeln, Technik, Reifegrad, Compliance, Roadmap
```
*Hinweis: `ea/mt5/RiskGuard.mq5` ist ein obsoleter Vorgänger (durch MamalTrading ersetzt) und kann gelöscht werden. Das früher hier genannte `ea/mt4/RiskGuard.mq4` existiert nicht (mehr) — nur die MT5-Datei ist noch da.*

## Regel-Kurzüberblick (Details in RULES.md)
R1 Risiko/Trade (Auto-Lot, 0,25 %) · R2 Idee-Cap · R3 Tagesbudget · R4 Tagesverlust · R4b Max-Loss · R5 Cooldown · R6 Verlustserie-Sperre · R7 SL/TP-Pflicht · R8 Min-CRV · R9 Anti-FOMO (aus) · R10 No-Override · R11 Journal · R12 Gesamtrisiko · R13 Tagesziel+Giveback · R14 Mindestpause · R15 Min-SL/Max-Lot · R16 Session/News · R17 Korrelation · R18 Wochenlimit · R19 De-Risk · **R22 Nur Panel-Trades** (manuelle Orders werden geschlossen, seit v0.35) · **R23 Wochen-Risiko-Pflicht** (ohne bewusste Wochenentscheidung kein Trade, seit v0.49) · R25 Revenge-Fenster.
