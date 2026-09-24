# Mamal-Trading — Regel-Spickzettel

**Basis:** Konto 20.000 € · Risiko/Trade **0,25 % = 50 €** · Auto-Scale an
(Idee-Cap 0,5 % · Gesamtrisiko 1,0 % · Tagesbudget **2,0 % = 400 €** (v0.20) — skalieren automatisch mit dem Risiko)

> **Alle €-Beträge auf dieser Seite sind 20k-Beispiele.** Verbindlich ist der **Prozentwert**; das Profil erlaubt 10k/20k/25k (auf 10k halbieren sich die €-Zahlen, auf 25k liegen sie 25 % höher). Zentrale Klarstellung: [`../RULES.md`](../RULES.md).

| # | Name | Definition (was sie tut) | Wert | Beispiel (20.000 €) |
|---|------|--------------------------|------|---------------------|
| **R1** | Risiko pro Trade (Auto-Lot) | Tool berechnet das Lot so, dass Entry→SL genau dem Risiko entspricht. Schließt Positionen, deren Risiko (aktueller SL) das Limit übersteigt. | 0,25 % = 50 € | SL 20 Pips → 0,25 Lot. SL 10 Pips → 0,50 Lot. Immer 50 € Risiko. |
| **R2** | Idee-Cap | Gleiches Symbol + gleiche Richtung = eine Idee. Summe des offenen Risikos je Idee gedeckelt. | 0,5 % = 100 € (= 2×) | EURUSD-Buy #1 + #2 = 100 € = voll → #3 blockiert. |
| **R3** | Tages-Risiko-Budget | Summe des an einem Tag *eröffneten* Risikos (auch Gewinner zählen, kein Refund). | **2,0 % = 400 €** (≈ 8 Trades) — v0.20 | Nach 8 Trades (8×50 €) → 9. blockiert „TAGESBUDGET". |
| **R4** | Tagesverlust-Sperre | Equity-Verlust ggü. Tagesstart → alle **Tool-überwachten** Positionen zu + Sperre bis Tagesreset. Reset täglich. (Trades **fremder EAs** werden nur gewarnt, nicht geschlossen; **manuelle Magic-0-Trades räumt seit v0.35 R22 weg**) | 2 % = 400 € | Equity 20.000 → 19.600 → Tool-Trades zu, gesperrt bis morgen. |
| **R4b** | Gesamtverlust-Sperre (+Warn-Gate) | Verlust ggü. Startkapital → **dauerhafte** Sperre; Warn-Gate stoppt neue Trades früher | Sperre 6 % = 1.200 € · Warn 5 % = 1.000 € | Equity 19.000 → keine neuen Trades; 18.800 → dauerhaft gesperrt |
| **R5** | Cooldown | X Verlust-Trades in Folge → Pause für neue Trades. | 3 Stops → 45 Min | Stop, Stop, Stop → 45 Min keine neuen Trades. |
| **R6** | Verlustserie-Sperre | X Verluste in Folge → Tagessperre. | 5 Stops | 5. Stop in Folge → gesperrt bis morgen. |
| **R7** | SL + TP Pflicht | Jede Position braucht SL **und** TP. **4 s** Frist (News-Blackout 0 s) — die Uhr läuft **ab dem Entfernen/Fehlen von SL/TP**, nicht ab Eröffnung. Gilt einheitlich für alle überwachten Positionen — **kein Sofort-Close-Sonderfall für Tool-Trades mehr** (v0.33; vorher 5 s ab Eröffnung + Tool-Trade sofort zu). Die Uhr ist pro Ticket **persistent** (übersteht Neustart/Recompile/Timeframe-Wechsel) und wird durch kurzes Wieder-Setzen des SL erst nach **60 s Heilfrist** zurückgesetzt (v0.34). | an, **4 s** Frist | Order ohne TP → nach 4 s geschlossen. SL nach 2 h entfernt → 4 s später zu. |
| **R8** | Mindest-CRV | **AUS** (auf Wunsch, v0.20). Auto-TP der Tool-Trades bleibt bei 2R als Ziel. | **AUS** | (deaktiviert) |
| **R9** | Anti-FOMO-Gate | Zwei-Klick-Bestätigung mit Wartezeit. | **AUS** | (deaktiviert auf Wunsch) |
| **R10** | No-Override | Kein Entsperr-Knopf; Sperren überleben Neustart; Warnung bei AutoTrading-aus. | an | MT4 neu starten → Sperre bleibt. AutoTrading aus → „SCHUTZ AUS". |
| **R11** | Journal | Jeder Trade / Block / Close wird als CSV protokolliert (mit Grund-Tag). | an | `MQL4/Files/MamalTrading_Journal.csv` |
| **R12** | Gesamtrisiko-Deckel | Offenes Risiko über **alle** Positionen zusammen gedeckelt. | 1,0 % = 200 € (= 4 Trades) | 4 Trades à 50 € offen = 200 € → 5. blockiert. |
| **R13** | Tagesziel + Giveback | Bei +Ziel keine neuen Trades; gibst du zu viel vom Tages-Hoch zurück → Tag gesperrt. | Ziel +3 % (+600 €); Giveback ab +1 %, 1 % Rückgabe | +600 € → keine neuen Trades. Oder +400 € → +200 € → Tag gesperrt. |
| **R14** | Mindestpause | **AUS** (auf Wunsch, v0.20). | **AUS** | (deaktiviert) |
| **R15** | Min-SL + Max-Lot | **AUS** (v0.22: M1-Scalping braucht enge Stops). Min-SL-Abstand `InpMinStopPips=0` = aus, Max-Lot-Cap `InpMaxLot=0` = ebenfalls aus. Gegen den Mini-SL→Riesen-Lot-Trick bleibt nur der **harte Broker-`STOPLEVEL`** — plus R1, das über die Lotgröße ohnehin auf 50 € Risiko deckelt. | **AUS** (beide 0) | SL nur 3 Pips → geht durch, solange der Broker-`STOPLEVEL` es zulässt; das Lot bleibt durch R1 gedeckelt. |
| **R16** | Session / News | Handel nur im Zeitfenster + manuelles News-Blackout. **Verfügbar, aber Default AUS** — muss konfiguriert werden (`InpUseSession=true` und/oder `InpNewsFrom`/`InpNewsTo` ≠ 0), sonst feuert das Gate nie. | **aus (Standard)** | Außerhalb 8–22 Uhr → blockiert (nur wenn aktiviert). |
| **R17** | Korrelations-Deckel (Währungsvektor) | Netto-Risiko **je Währung** über alle Positionen gedeckelt (korrelierte Paare + Cross-Pairs zählen zusammen, Nicht-FX als Einzel-Bucket). | 1,5 % | EURUSD-Buy + GBPUSD-Buy addieren (USD-short); + 3. → blockiert. EURUSD-Buy + USDJPY-Buy heben sich auf. |
| **R18** | Wochen-Verlustlimit | Equity-Verlust über die Woche → Woche gesperrt. | 5 % = 1.000 € | Über die Woche −1.000 € → bis Wochenwechsel gesperrt. |
| **R19** | De-Risk-Leiter | **AUS** (auf Wunsch, v0.20). | **AUS** | (deaktiviert) |
| **R22** | Nur Panel-Trades | Jede Order **ohne** Tool-Magic (= von Hand im Terminal oder in der Handy-App eröffnet) wird geschlossen: Positionen zu Marktpreis, Pending-Orders gelöscht. **Kontoweit über alle Symbole**, nicht nur das Chart-Symbol. Fremde EAs mit eigener Magic bleiben unangetastet. Grund: nur der Panel-Weg durchläuft die Entry-Gates (R1/R2/R3/R5/R7/R12/R13/R15/R16/R17 …). Gilt auch im FundedMode. Ein so geschlossener Trade zählt **nicht** auf R3/R5/R6/R19/R25 — der Verlust schlägt aber voll auf R4/R4b/R18 durch. | an (`InpCloseManualTrades=true`) — v0.35 | Du öffnest am Handy einen XAUUSD-Trade → wird binnen ~1 s geschlossen (Timer 1 s + Drossel 0,3 s; ziehst du gerade an SL/TP, bis 2 s). Spread und Slippage trägst du. |
| **R25** | Revenge-Fenster | **AUS** (auf Wunsch, v0.20). | **AUS** | (deaktiviert) |

## Panel-Status (oben links im Chart)
Es gibt **genau diese 9 Anzeigen** — Panel und Cockpit zeigen denselben String. Ein generisches „GESPERRT" gibt es **nicht**; die Sperre wird immer benannt. Reihenfolge = Priorität von oben nach unten (bei mehreren Sperren gewinnt die härteste):

| Anzeige | Bedeutung |
|---|---|
| **SCHUTZ AUS** (orange) | AutoTrading ist aus — EA kann nicht schützen! |
| **MAX-LOSS GESPERRT** (rot) | Gesamtverlust-Sperre, dauerhaft (R4b) |
| **WOCHE GESPERRT** (rot) | Wochen-Verlustlimit (R18) |
| **TAG GESPERRT** (rot) | Tagessperre (R4 Tagesverlust / R6 Verlustserie / R13 Giveback) |
| **MAX-LOSS WARNUNG** (orange) | Gesamtverlust ≥ Warn-Gate (5 %) — keine neuen Trades (R4b) |
| **COOLDOWN** (orange) | Pause nach 3 Verlusten (R5) |
| **ZIEL ERREICHT** (grün) | Tagesziel erreicht, keine neuen Trades (R13) |
| **AUSSER SESSION** | außerhalb Zeitfenster / News-Sperre (R16) |
| **AKTIV** (grün) | alles frei, du kannst traden |

**R22 hat keine Panel-Anzeige** — dass ein manueller Trade geschlossen wurde, siehst du nur im Journal/Cockpit, nicht im Chart-Panel.

## Auto-Scale (wichtig)
Änderst du **Risiko/Trade** oder **`InpIdeaXrisk`**, passen sich Idee-Cap, Gesamtrisiko und Tagesbudget automatisch an. Die *Anzahl* erlaubter Trades (2 je Idee / 4 gleichzeitig / **8 pro Tag** ab v0.20) bleibt konstant. `InpAutoScale=false` → feste %-Werte.

## Auf Wunsch abgeschaltet (v0.20 / v0.22)
**R8** (Mindest-CRV), **R9** (Doppel-Bestätigung), **R14** (Mindestpause), **R19** (De-Risk-Leiter), **R25** (Revenge-Fenster) — v0.20.
**R15** (Min-SL-Abstand **und** Max-Lot-Cap, beide Inputs auf 0) — v0.22, weil M1-Scalping enge Stops braucht; übrig bleibt der harte Broker-`STOPLEVEL`.
Die Disziplin kommt aus den harten Grenzen R3/R4/R4b/R12/R5/R6.
**Nicht abgeschaltet, aber inaktiv:** **R16** (Session/News) ist Default AUS und muss erst konfiguriert werden.

## Ehrliche Grenzen
- Client-seitig „erkennen-und-schließen" (~0,5 s Reaktion); Schaden durch R4/R4b gedeckelt.
- **R22** verhindert den manuellen Trade nicht, es dreht ihn zurück: Erkennung Bruchteile einer Sekunde bis mehrere Sekunden (bei geschlossenem Markt bis 15 Min pro Versuch), Spread und Slippage trägst du. EA aus oder AutoTrading aus → R22 greift gar nicht.
- Der **R22**-Zähler unter „Deine Schwächen" im Cockpit kann einen einzelnen manuellen Trade **mehrfach** zählen (jeder Retry schreibt eine eigene Zeile) — Obergrenze, keine Trade-Zählung.
- „No-Override" lokal nur Reibung; wirklich un-umgehbar erst auf VPS + FTMO-Serverlimit.
- Mac/Wine instabil → Dauerbetrieb auf Windows-VPS.
