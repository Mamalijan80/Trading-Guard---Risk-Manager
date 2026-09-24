# Mamal-Trading — Regelwerk (vollständige Beschreibung)

Konto-Referenz: **20.000 € (FTMO-Demo)**, Risiko/Trade **0,25 % = 50 €** (FTMO-konservativ). Alle Werte sind Parameter (Inputs) und änderbar. (Die €-Beträge der Verlust-Limits R4/R4b/R18 unten sind unabhängig vom Trade-Risiko.)

> **Alle €-Beträge in diesem Dokument sind auf diese 20k-Referenz umgerechnet.** Das Profil deckt 10k/20k/25k ab; verbindlich ist immer der **Prozentwert**, der EA rechnet ausschließlich prozentual gegen die reale Kontobasis. Zentrale Klarstellung: [`../RULES.md`](../RULES.md).

## A — Positionsgröße & Einzelrisiko
**R1 — Risiko pro Trade (Auto-Lot).** Du ziehst die rote SL-Linie, das Tool berechnet die Lotgröße so, dass dein Risiko (Entry→SL) **genau 0,25 % = 50 €** ist. Ein Monitor prüft jede offene Position laufend mit dem *aktuellen* SL: steigt das Risiko über 0,275 % (z. B. weil du den SL weiter ziehst), wird die Position geschlossen. → killt „aus dem Bauch zu groß".

**R15 — Min-SL-Abstand + Max-Lot. AUS** (v0.22: M1-Scalping braucht enge Stops; `InpMinStopPips=0`). Der optionale harte Lot-Deckel `InpMaxLot` ist ebenfalls **0 = aus**, R15 ist damit per Default vollständig wirkungslos. Gegen die Extremform „winziger SL → riesiges Lot → Slippage/Gap" bleibt nur der **harte Broker-Mindestabstand (`STOPLEVEL`)** — plus R1, das die Lotgröße auf 0,25 % Risiko deckelt. *(Doku-Korrektur: hier standen bisher „mind. 5 Pips, sonst blockiert".)*

## B — Konzentration (nicht alles auf eine/ähnliche Idee)
**R2 — Idee-Cap.** Gleiches Symbol **+** gleiche Richtung = **eine Idee**. Summe des offenen Risikos je Idee ≤ **0,5 % = 100 €** (Auto-Scale: 2× Risiko/Trade) → max. 2 Einstiege à 0,25 %; der 3. wird blockiert. → genau dein „4–5× auf dieselbe Idee".

**R17 — Korrelations-Deckel (Währungsvektor, seit v0.17).** Rechnet je **Währung** das Netto-Risiko über alle Positionen (jede Position belastet Basis-Währung long / Quote-Währung short): EURUSD-Buy + GBPUSD-Buy = beide USD-short → addieren sich; EURUSD-Buy + USDJPY-Buy = USD hebt sich auf. Größte |Netto-Währungs-Exposition| ≤ **1,5 %**. Cross-Pairs (EURJPY …) zählen korrekt zusammen; Nicht-FX (US30) als Einzel-Bucket. → verhindert verstecktes Doppelrisiko über korrelierte Paare.

## C — Tages- und Gesamt-Exposure
**R12 — Gesamtrisiko-Deckel (Portfolio-Heat).** Das **gleichzeitig offene Risiko über ALLE Positionen** zusammen ≤ **1,0 % = 200 €** (Auto-Scale = 2× Idee-Cap; fix-Fallback 2 %). Neuer Trade darüber wird blockiert; ein Monitor schließt die *neueste* Position, falls die Summe doch überschritten wird. → dein „unbewusst steigendes Gesamtrisiko".

**R3 — Tages-Risiko-Budget.** Summe des an einem Tag **eröffneten** Risikos ≤ **2,0 % = 400 €** (Auto-Scale = 4× Idee-Cap; ≈ 8 Trades) — **v0.20 (war 1,5 %/300 €)**, damit R4 (Tagesverlust-Bremse) und das Tagesziel überhaupt erreichbar sind. Zählt auch Gewinner mit, kein „Zurückbuchen". → begrenzt die Anzahl der Schüsse pro Tag.

## D — Verlust-Bremsen (eskalierend)
**R4 — Tagesverlust-Hard-Lock.** Fällt die Equity **−2 % = 400 €** unter den Tagesstart → **alle vom Tool überwachten Positionen** geschlossen (In-Scope; in Funded = nur eigene Tool-Trades) + **Sperre bis Tagesreset**. Resettet täglich. Liegt unter dem FTMO-5 %-Limit. *Hinweis: Positionen **fremder EAs** (eigene Magic ≠ 0) außerhalb des Scope schließt `SafeCloseAll` NICHT — der EA warnt dann laut (selbst schließen). **Für manuelle Magic-0-Trades gilt das seit v0.35 nicht mehr:** die räumt R22 unabhängig von Scope und Sperre weg (siehe R22 unten).*

**R4b — Gesamtverlust-Sperre.** Equity **−6 % = 1.200 €** unter dem Startkapital → **dauerhafte** Sperre (resettet nie). **Warn-Gate bei −5 % = 1.000 €** → keine neuen Trades mehr. Puffer vor dem FTMO-10 %-Maximalverlust.

**R18 — Wochen-Verlustlimit.** **−5 %** in der laufenden Woche → **Woche gesperrt** (bis Wochenwechsel).

**R5 — Cooldown.** **3 Verlust-Trades in Folge** → **45 Min** keine neuen Trades.

**R6 — Verlustserie-Sperre.** **5 Verluste in Folge** → **Tagessperre**.

**R19 — De-Risk-Leiter. AUS** (auf Wunsch, v0.20; `InpDeRiskFactor=1.0`). *(Das Risiko bleibt konstant 0,25 %.)*

## E — Impuls / Revenge / FOMO
**R25 — Revenge-Fenster. AUS** (auf Wunsch, v0.20; `InpRevengeMin=0`). *(Kein Gegen-Trade-Block; die harten Grenzen R3/R4/R4b/R5/R6 sorgen für Disziplin.)*

**R14 — Mindestpause. AUS** (auf Wunsch, v0.20; `InpMinGapSec=0`). *(Keine erzwungene Pause zwischen Trades.)*

**R16 — Session-/News-Sperre. Verfügbar, Default AUS.** Handel nur im definierten Zeitfenster (`InpUseSession=false` = aus) + optionales manuelles **News-Blackout-Fenster** (`InpNewsFrom=InpNewsTo=0` = aus). Solange beides unkonfiguriert ist, greift das Entry-Gate **nie** — R16 zählt also nicht zu den aktiven Regeln. *(Automatische News-Erkennung braucht einen Kalender-Feed → kommt mit Server/Cockpit.)*

**R9 — Anti-FOMO-Klick-Gate.** Zwei-Klick-Bestätigung mit Wartezeit. **Auf deinen Wunsch AUS.**

## F — Gewinn sichern
**R13 — Tagesziel + Giveback-Schutz.** (a) Bei **+3 % = +600 €** am Tag → keine neuen Trades mehr (offene Runner laufen weiter). (b) Warst du ≥ **+1 %** im Plus und gibst **1 %** vom Tages-Hoch zurück → **Tag gesperrt** (Gewinn gesichert). → gegen „grüne Tage wieder herschenken".

## G — Ausführungs-Hygiene
**R7 — SL+TP-Pflicht.** Jede Position braucht **SL und TP**. Fehlt eines, hast du **4 s** zum Nachtragen (im News-Blackout **0 s**), sonst wird geschlossen. Die Frist läuft **ab dem Moment, in dem SL/TP fehlt bzw. entfernt wurde** — nicht ab Eröffnung; sonst hätte ein alter Trade nach dem SL-Entfernen gar keine Frist. **Tool-Trades haben keinen Sofort-Close-Sonderfall mehr** — es gilt einheitlich für jede Position im Watch-Scope (Default `TOOL_ONLY` = Panel-Trades). **Härtung v0.34:** die Uhr läuft **pro Ticket persistent** (GlobalVariable je Ticket — überlebt Terminal-Neustart, Recompile, Timeframe-Wechsel und Master-Handoff) und wird durch Wieder-Setzen von SL/TP erst nach **60 s Heilfrist** gelöscht; wirst du vorher wieder nackt, läuft die alte Uhr weiter. Ein kurzes SL-Antippen verschafft dir also keine neue Frist. Zusätzlich ist die SL/TP-Pflicht **tighten-only**: einmal aktiv, lässt sie sich intraday nicht mehr per Input abschalten — Lockern greift erst zum Tageswechsel. *(Doku-Korrektur v0.33: vorher „5 s ab Eröffnung, Tool-Trade sofort zu".)* **Wichtig:** geschlossen wird der **Trade** — MetaTrader/das Programm bleibt offen (kein Crash; der Close läuft über die gedrosselte Close-Queue). Den SL **enger** ziehen ist erlaubt; **weiter** ziehen fängt R1.

**R8 — Mindest-CRV. AUS** (auf Wunsch, v0.20; `InpMinRR=0`). *(Kein Mindest-CRV-Zwang. Der Auto-TP der Tool-Trades bleibt bei 2R als Ziel.)*

**R10 — No-Override.** Kein Entsperr-Knopf; Sperren überleben Terminal-Neustart; Warnung „SCHUTZ AUS" wenn AutoTrading deaktiviert wird. *(Lokal = starke Reibung; wirklich un-umgehbar erst auf einem gesperrten VPS + FTMO-Serverlimit.)*

**R11 — Journal.** Jeder Trade, jede Blockierung und jedes Regel-Schließen wird als CSV protokolliert (`MQL4/Files/MamalTrading_Journal.csv`) mit Tag (in-plan / welche Regel). Screenshots optional.

**R22 — Nur Panel-Trades (seit v0.35).** `InpCloseManualTrades=true` (Default). Jede Order **ohne** Tool-Magic (Magic 0 = von Hand im Terminal oder in der Handy-App eröffnet) wird in die Close-Queue gereiht: Positionen werden zu Bid/Ask mit `InpSlippage` geschlossen, Pending-Orders gelöscht. **Kontoweit über alle Symbole**, nicht nur auf dem Chart-Symbol des EA. Fremde EAs mit **eigener** Magic (≠ 0 und ≠ `InpMagic`) bleiben unangetastet. **Warum:** nur der Panel-Weg durchläuft die Entry-Gates — der Reihe nach AutoTrading, Sperre, Basis unsicher, R4b-Warn-Gate, R13 Tagesziel, R5 Cooldown, R16 Session/News, R25 Revenge, R14 Mindestpause, R7 SL-Linie/Seite, R15 Broker-`STOPLEVEL`+Min-SL, R1 Lot-Berechnung, R2 Idee-Cap, R3 Tagesbudget, R12 Heat, R17 Korrelation. Ein manueller Trade umgeht diese Kette komplett; vorher wurde er bei aktiver Sperre unter `WatchScope=TOOL_ONLY` (Default und im FundedMode erzwungen) nicht einmal geschlossen, sondern nur 1×/Minute angemahnt. R22 ist die **einzige** Enforcement-Funktion, die den `InScope()`-Filter umgeht — sie vergleicht die Magic direkt und wirkt deshalb auch im FundedMode. **Achtung Konfiguration:** die Abgrenzung hängt allein an „Magic ≠ 0". `InpMagic` steht default auf `990201`; setzt jemand `InpMagic=0`, räumt R22 die **eigenen Panel-Trades** ab — dagegen gibt es im Code keinen Schutz.

**R22 — was es *nicht* kann (ehrliche Grenzen).** Es ist **erkennen-und-zurückdrehen**, kein Verhindern: der Trade geht auf, R22 schließt ihn nachträglich zu Marktpreis — **Spread und Slippage trägst du**. Die Erkennungs-Latenz setzt sich zusammen aus Timer (1 s) bzw. Tick (≥ 500 ms), Close-Drossel (300 ms) und ggf. dem Modify-Quiet-Fenster (bis 2 s gleitend, hart gedeckelt auf 10 s Serie — wer dauernd an SL/TP zieht, verzögert R22 also). Realistisch: **Bruchteile einer Sekunde bis mehrere Sekunden**; bei geschlossenem Markt (Fehler 132) bis zu 15 Min pro Versuch. Läuft der EA nicht, ist AutoTrading aus oder scheitert der Timer, greift R22 **gar nicht** — wie das gesamte Enforcement. Nur die bestätigte Master-Instanz (≥ 2 Cycles in Folge) setzt durch, passive Instanzen tun nichts. Nach 5 Fehlversuchen fliegt das Ticket mit FINAL-FAIL aus der Queue und **bleibt offen** — es wird allerdings im nächsten Durchlauf erneut eingereiht. **Kein Bestandsschutz beim Start:** OnInit zählt vorgefundene Magic-0-Orders und meldet sie (Journal-Event `INFO`, Tag „R22 Start: N manuelle Order(s) vorgefunden -> werden geschlossen"), schließt aber selbst nichts — der Close passiert erst im nächsten oder übernächsten Cycle, auf einer passiven Instanz gar nicht. **Wechselwirkung mit den Verlust-Regeln:** ein per R22 geschlossener manueller Trade ist out of scope und wird von der Historien-Auswertung **nicht** gewertet → kein Beitrag zu R5 Cooldown, R6 Verlustserie, R19 De-Risk, R25 Revenge, und **kein** Verbrauch des R3-Tagesbudgets. Der realisierte Verlust schlägt aber sehr wohl auf die equity-basierten Grenzen durch: **R4, R4b und R18 zählen ihn voll mit.** Im On-Chart-Panel taucht R22 **nirgends** auf; im Cockpit erscheint es bei `InpCloseManualTrades=false` als „— aus"-Chip und sonst unter „Deine Schwächen" — dort allerdings **mehrfach pro manuellem Trade**, weil jeder Retry, jeder FINAL-FAIL und jedes Verwerfen eine eigene CLOSE-Zeile schreibt. Der Zähler ist also eine Obergrenze, keine Trade-Zählung. **Compliance:** der EA schließt damit auch im FundedMode Positionen, die er nicht selbst geöffnet hat — ob das mit deiner Prop-Firm vereinbar ist, musst du firmenspezifisch prüfen.

---

## Ehrliche Grenzen (gelten für alle Regeln)
1. **Erkennen-und-schließen**, nicht verhindern: client-seitig reagiert der EA mit ~0,5 s Verzögerung (Polling). In diesem Fenster kann eine Regel kurz verletzt sein — der Schaden ist durch R4/R4b gedeckelt. Bei **R22** (manuelle Trades) kann das Fenster länger sein — Bruchteile einer Sekunde bis mehrere Sekunden, siehe dort.
2. **No-Override ist lokal nur Reibung** — als Admin kannst du den EA abschalten. Echtes Immutable = VPS ohne eigenen Admin-Zugang + FTMO-Serverlimit.
3. **Mac/Wine** ist instabil; Dauerbetrieb gehört auf einen Windows-VPS.
