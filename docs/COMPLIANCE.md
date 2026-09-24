# Mamal-Trading — Prop-Firm-Compliance-Check

**Kein Rechtsrat.** Maßgeblich sind allein die **aktuellen Trading-Rules/Terms der jeweiligen Firma bei DEINER Anmeldung** — Regeln ändern sich und werden meist *case-by-case* durchgesetzt. Dieser Check ist eine ehrliche Selbst-Einordnung des Tools + ein Recherche-Snapshot (Quellen unten). Stand der Recherche: 2026-06, **Primärquellen-Prüfung 2026-07-21** (→ Abschnitt 2.1). **Stand des Tools: EA v0.36** — enthält seit v0.35 **R22 „Nur Panel-Trades"** (→ Abschnitt 1.1); der v0.36-Wochen-Risiko-Wähler ist compliance-neutral (der Trader wählt seinen eigenen Risiko-%-Satz, kein Signal, keine Automatik-Entscheidung über Richtung/Timing).

> **FTMO hat schriftlich bestätigt (2026-07-22, Ticket QVM-FSGGG-356):** „**Yes, you can**" — ein **selbst entwickelter** EA dieser Kategorie ist erlaubt (Details → Abschnitt 2.0). Einzelne Punkte (R22, Order-Frequenz) wurden nicht gesondert abgesegnet; Support-Auskunft, nicht rechtsverbindlich.

> **Neu aus den Primärquellen (2026-07-21):** (1) **FTMO stärker als gedacht** — FTMOs eigene *Risk Management Rules* benutzen wörtlich den Begriff **„Risk per Trade Idea"** (Klauseln 7.5.3, 7.6.6), also genau das Konzept, das R2 (Idee-Cap) im Tool erzwingt. Das Tool *setzt FTMOs eigene Regeln um*, statt sie nur nicht zu verletzen. (2) **The5ers strenger als gedacht** — die von dir übergebene The5ers-**T&C** verlangt für Automatisierung eine **vorherige schriftliche Freigabe** (Widerspruch zur permissiveren Help-FAQ) → Abschnitt 2.1 + korrigierte Tabelle.

---

## 1. Was der EA tatsächlich tut (ehrlich, ungeschönt)

**Generiert KEINE Signale** — und das ist der entscheidende Compliance-Punkt:
- Keine Entry-Timing-Logik, keine Richtungs-Logik, keine Indikatoren, die entscheiden *wann/was* getradet wird. **Der Mensch klickt BUY/SELL.**

**Ist aber NICHT rein passiv** (das gehört offen dazu):
- **One-Click-Ausführung:** Auf den Klick berechnet der EA die Lotgröße für ein festes %-Risiko (aus der SL-Linie) und sendet **eine** Order via `OrderSend` (mit echtem SL + TP). = nutzer-initiierter Ausführungshelfer, **ein Auftrag pro Klick** (menschen-getaktet).
- **Autonomes Risk-Management:** schließt/blockt eigenständig bei Regelbruch (R1 Risiko, R7 fehlender SL/TP, R8 CRV, R12 Heat; SafeCloseAll bei Tages-/Max-/Wochensperre; Cooldown/Revenge/Idee-Cap/Tagesbudget blocken neue Trades). Sperren überleben Neustart, kein Entsperr-Knopf.
- **R22 „Nur Panel-Trades" (seit v0.35, Default an):** schließt zusätzlich **manuell** eröffnete Positionen und löscht manuelle Pending-Orders auf dem eigenen Konto — also Orders, die der EA **nicht selbst geöffnet** hat. Das ist eine Verhaltensänderung gegenüber der bisherigen Einordnung → **Abschnitt 1.1**.

**Tut NICHT** (die üblich verbotenen Muster — alle vermieden):
- kein HFT / Tick-Scalping / Sub-Sekunden-Halten
- keine Latenz-/Feed-Arbitrage (vergleicht keine Feeds, rennt keinem Kurs-Update hinterher)
- kein Copy-Trading / Mirroring über Konten, keine Signal-Gruppen
- kein Grid/Martingale (im Gegenteil: deckelt Risiko, blockt Stacking/Revenge)
- kein News-Straddle, kein Order-Spamming, kein Account-Management-Service
- wirkt nur auf **dein eigenes Konto** — kein Zugriff auf fremde Konten, kein Mirroring. *Einschränkung seit v0.35:* „nur eigene Trades" gilt **nicht mehr uneingeschränkt** — `WatchScope=TOOL_ONLY` (im `InpFundedMode` hart erzwungen) steuert weiterhin alle anderen Enforcement-Funktionen, **R22 umgeht diesen Scope aber bewusst** (→ Abschnitt 1.1). Positionen anderer EAs (eigene Magic ≠ 0) bleiben unangetastet.

**Einordnung:** **diskretionärer Entry (keine Signale) + automatisiertes Risk-Management** — die landschaftsweit *am stärksten erlaubte* Automations-Kategorie. Diese Einordnung gilt weiterhin; R22 verschiebt jedoch die **Reichweite** des Risk-Managements innerhalb des eigenen Kontos (Abschnitt 1.1).

---

### 1.1 R22 „Nur Panel-Trades" — Verhaltensänderung, firmenspezifisch zu bestätigen

**Was sich geändert hat.** Bis v0.34 galt: Der EA fasst nur an, was er selbst geöffnet hat (`InScope()`, im FundedMode hart auf `TOOL_ONLY`). Mit **R22** (Input `InpCloseManualTrades`, Default `true`) schließt der EA jede Order mit **Magic 0** — also jeden Trade, den du selbst im MT4-Terminal (oder auf dem Handy) eröffnet hast — und löscht entsprechende Pending-Orders. R22 ist die **einzige** Enforcement-Funktion, die `InScope()` umgeht; sie prüft die Magic direkt. **Damit wirkt sie auch im `InpFundedMode`**, wo das bisherige Design genau das bewusst ausschloss. Der Grund dafür ist regel-technisch, nicht strategisch: Nur der Panel-Pfad durchläuft die Entry-Gates (R1 Lot, R2 Idee-Cap, R3 Tagesbudget, R5 Cooldown, R7 SL-Pflicht, R12 Heat, R13, R14, R15, R16, R17, R25) — ein manueller Trade umgeht sie alle.

**Was sich NICHT geändert hat (die compliance-relevanten Punkte):**
- **Kein Eingriff in fremde Konten.** R22 läuft ausschließlich über `OrdersTotal()` des Terminals, auf dem der EA läuft = dein eigenes Konto.
- **Kein Copy-Trading, kein Mirroring, keine Signalgenerierung.** R22 eröffnet nichts, entscheidet nichts über Richtung oder Timing. Es schließt nur.
- **Keine Berührung fremder EAs.** Alles mit Magic ≠ 0 wird übersprungen.
- Es bleibt **Risk-Management auf dem eigenen Konto** — die Kategorie aus Abschnitt 1 ändert sich dadurch nicht.

**Warum es trotzdem gesondert zu verifizieren ist.** Die Selbst-Einordnung „automatisiertes Risk-Management" wurde bisher mit dem Zusatz „nur auf eigene, vom Tool eröffnete Trades" verteidigt. Dieser Zusatz stimmt so nicht mehr. Ein Prop-Firm-Regelwerk, das EAs an „Trade-/Risk-Management" knüpft, meint damit möglicherweise ausdrücklich das Management **eigener EA-Positionen** — ob das Schließen manuell eröffneter Positionen desselben Kontos darunter fällt, ist aus den recherchierten Quellen **nicht** ableitbar. **Wir behaupten hier nichts über einzelne Firmen und zitieren keine Regel dazu — es ist ein offener, vor einem Funded-Konto firmenspezifisch zu klärender Punkt.**

**Konkret zu klären, bevor R22 auf einem Funded-Konto läuft:**
1. Fällt automatisches Schließen **manuell** eröffneter eigener Positionen bei der Firma noch unter „Trade-/Risk-Management-EA"?
2. Erzeugt das zusätzliche Close-Volumen (inkl. Retries) Konflikte mit Order-Frequenz-/Hyperaktivitäts-Regeln?
3. Wird ein per R22 sofort wieder geschlossener Trade von der Firma als eigenständiger (Verlust-)Trade gewertet — relevant für Consistency-/Mindesthandelstage-Regeln?

**Ausweg, falls die Antwort unklar bleibt:** `InpCloseManualTrades=false` setzen. Dann verhält sich der EA wie bis v0.34; R22 erscheint im Cockpit als „— aus"-Chip. Das ist der konservative Zustand und in jedem Zweifelsfall die richtige Wahl.

**⚠ Fallstrick:** Die Abgrenzung zu Panel-Trades hängt allein an `Magic != 0`. Panel-Trades laufen mit `InpMagic` (Default `990201`). Wer `InpMagic=0` setzt, lässt R22 die **eigenen Panel-Trades** abräumen — im Code gibt es dagegen keinen Schutz. `InpMagic` niemals auf 0 setzen.

---

## 2. Pro Firma (Recherche-Snapshot — bei Anmeldung verifizieren)

| Firma | EAs generell | Risk-Manager-EA (no-signal) | Pre-Approval? | Verdikt für dieses Tool | Conf. |
|---|---|---|---|---|---|
| **FTMO** | **Ja — Support schriftlich bestätigt (2026-07-22)**; self-developed = kein Third-Party-EA | „am besten verteidigbare" EA-Kategorie; deckt sich mit FTMOs eigener Risk-per-Trade-Idea-Regel | Nein | **erlaubt (Support-bestätigt; Detail R22/Frequenz nicht einzeln geklärt)** | 0,90 |
| **The5ers** | Ja, wenn **selbst-besessen** + keine verbotenen Strategien | erlaubt; Risk-Enforcement passt zu Hausregeln | Nein | **likely-allowed (Bedingungen)** | 0,78 |
| **FundedNext** | Ja auf **MT4/MT5** (Tool ist MT4 ✓); SL/TP/Lot-Tool gilt als **EA, nicht exempt** | erlaubt als EA | Nein, aber **EA-Gebühr/Add-on** + Consistency-Regeln | **likely-allowed (Bedingungen)** | 0,78 |
| **FundingPips** | Third-party-EA „**nur als Trade-/Risk-Manager**" ausdrücklich erlaubt (stärkster Treffer) | **explizit benannte erlaubte Kategorie** | Nein, aber kann **Source-Eigentum nachfragen** (Binary allein reicht nicht) | **likely-allowed (Bedingungen)** | 0,78 |
| **Alpha Capital** | EAs **nur** für Trade-Management/Risk-Control (genau unsere Kategorie) | passt, aber … | **JA — Pflicht-Pre-Approval** (Datei einreichen, schriftliche Freigabe; Prozess MT5/EX5-basiert) | **likely-allowed (Bedingungen)** | 0,72 |

> **Tabellen-Korrekturen nach der Primärquellen-Prüfung (Abschnitt 2.1):** FTMO-Zeile Conf. **0,82 → 0,88** (Risk-per-Trade-Idea-Deckung, siehe unten). The5ers-Zeile Pre-Approval **„Nein" → „laut T&C JA (schriftlich); Help-FAQ sagt permissiver — Widerspruch, direkt klären"**, Verdikt daher **„nur mit schriftlicher Freigabe (per T&C)"**. FundedNext/FundingPips/Alpha unverändert (keine Primärquelle neu geprüft).

---

## 2.0 FTMO — schriftliche Support-Bestätigung (2026-07-22, Ticket QVM-FSGGG-356)

Anfrage per Support-Ticket gestellt (Beschreibung des Tools: no-signal, diskretionärer Entry, automatisiertes Risk-Management inkl. R22, <2.000 Requests/Tag; drei konkrete Fragen). FTMO-Support (Thomas Taylor) antwortete:

> „**Yes, you can.** If you intend to use trading robots (Expert Advisors – EAs), keep in mind that if you use an EA **from a third party**, you run into a risk of being denied the FTMO Account if you exceed the maximum capital allocation rule."

Auf die Klarstellung „ich habe den EA selbst entwickelt, also kein Third-Party-EA" folgte: „**Understood.** … we wish you much luck with your trading!"

**Was das belastbar bestätigt:**
- Ein **selbst entwickelter** EA dieser Kategorie ist auf FTMO **erlaubt, ohne Vorab-Freigabe**. Der einzige von FTMO genannte Vorbehalt — Third-Party-EAs + Max-Capital-Allocation-Regel (mehrere Konten mit derselben fremden Strategie) — **trifft hier nicht zu** (Eigenentwicklung, Einzelkonto). FTMO hat das ausdrücklich mit „Understood" quittiert.

**Was NICHT einzeln bestätigt wurde (ehrlich):**
- Die Antwort ist ein **generisches Support-„Yes"**, keine detaillierte Prüfung. **Frage 2 (R22 — automatisches Schließen manuell eröffneter Positionen)** und **Frage 3 (Order-Frequenz/Hyperaktivität)** wurden **nicht gesondert** beantwortet (nur Verweis auf die Strategie-FAQ). Sie fallen unter das allgemeine „Yes", sind aber nicht punktuell abgesegnet.
- Support-Auskünfte sind **nicht rechtsverbindlich**; FTMO behält sich alles „at our sole discretion" vor. Der Backstop bleibt das server-seitige Limit.

**Empfehlung:** Wenn du R22 auf einem Funded-Konto scharf schalten willst, lohnt eine **kurze Nachfrage speziell zu Frage 2** (nur den manuellen-Close-Punkt), um ihn explizit im Schriftverkehr zu haben. Für den generellen EA-Einsatz reicht die vorliegende Bestätigung.

---

## 2.1 Primärquellen-Prüfung (2026-07-21) — FTMO-T&C (PDF) + FTMO Forbidden Practices + The5ers-T&C

**Quellen dieser Prüfung:** FTMO *General Terms and Conditions* (22 S., von dir übergeben), FTMO *Forbidden Trading Practices* (Website), The5ers *Terms and Conditions* (Website). Alles im Original gelesen; Zitate wörtlich.

### FTMO — passt sehr gut, mit klaren Bedingungen

- **EAs sind erlaubt.** Die allgemeine T&C verbietet Automatisierung **nicht**; die eigentliche Verbotsliste steht separat (Klausel 7.3 verweist darauf). Die *Forbidden Trading Practices* verbieten EAs nur, wenn sie das Konto **hyperaktiv** machen: Trades, *„operated or managed by automated robots / EAs … which cause the trading account to become hyperactive … more than 2,000 server requests per day"*. → Das Tool bleibt konstruktiv weit darunter (Close nur bei Regelbruch, Enforcement auf 300 ms gedrosselt, menschen-getaktete Entries). ✓
- **Das Tool implementiert FTMOs *eigene* Risk Management Rules.** Klausel **7.5.3** verlangt, *„undertaking repeated simulated trading activity that results in higher **Risk per Trade Idea**, thereby exposing your simulated account to cumulative exposure in a specific symbol or correlated symbols"* zu **vermeiden**; Klausel **7.6.6** erlaubt FTMO, *„the limitation on **Risk per Trade Idea** … as a percentage of the Initial Simulated Capital … on any single simulated trade or combination of simulated trades out of one trade idea"* zu erzwingen. **Das ist wörtlich R2 (Idee-Cap = Symbol+Richtung, gedeckelt in % der Equity)** — plus R17 (Korrelation) und R12 (Heat). Klausel **7.5.1** („keine substanziell größeren Positionen") = R1/R15. Das Tool ist damit ein **automatischer Vollstrecker der FTMO-Risk-Rules**, kein Grenzfall.
- **Was der TRADER (nicht das Tool) beachten muss** — verbotene Praktiken, die vom Handelsstil abhängen: **Gap-/News-Trading** (*„opening simulated trades when major global news … are scheduled"* bzw. ≤2 h vor einer ≥2-h-Marktschließung), HFT/Sekunden-Scalping, Ausnutzen von Kurs-Fehlern/langsamem Feed. → **R16 (Session/News-Blackout) kann das News-Fenster erzwingen, ist aber default AUS** — wer bei FTMO handelt, sollte R16 konfigurieren.
- **R22 ist mit den FTMO-Regeln vereinbar.** Nichts in der T&C oder den Forbidden Practices untersagt es, **eigene** Positionen auf dem **eigenen** Konto per eigener Software zu schließen — im Gegenteil, Klauseln 7.4–7.6 rahmen genau das als erwünschtes Risk-Management. Der frühere Vorbehalt (Abschnitt 1.1) ist für FTMO damit weitgehend entkräftet; er bleibt „im Zweifel bestätigen", weil FTMO alles *at our sole discretion* auslegt.

### The5ers — Widerspruch zwischen T&C und Help-FAQ, schriftliche Freigabe nötig

- Die **T&C** (bindendes Dokument) enthält eine Klausel *„Use of Automated Trading Software"*: **keine automatisierte Software ohne vorherige schriftliche Freigabe** der Firma; **Dritt-EAs verboten**, nur **selbst entwickelte** EAs nach Freigabe, und der Trader **muss den Quellcode besitzen**. → Du besitzt den Quellcode ✓, aber die **schriftliche Freigabe fehlt** und ist laut T&C Voraussetzung.
- Das steht in Spannung zu The5ers' permissiverer **Help-FAQ** („Kann ich einen EA nutzen?"), auf der die bisherige „likely-allowed"-Einordnung beruhte. **Beides gleichzeitig kann nicht stimmen** — vor einem The5ers-Konto direkt klären, welches Regime gilt. Bis dahin: The5ers wie Alpha Capital behandeln (**schriftliche Vorab-Freigabe einholen**).
- Verbotene Praktiken (T&C): HFT (*„majority of trades duration … measured within a few seconds"*), **Tick-Scalping**, Arbitrage-Varianten, **Copy-Trading**, *„Expert advisors which scalp during the rollover-night"*, geteilte/fremde EAs. → Das Tool ist keine davon; ein sehr schneller M1-Scalping-**Stil** könnte aber „Sekunden-HFT"/Rollover-Scalping berühren — das liegt am Nutzer, nicht am Tool.

**Wichtig:** Die Section-Nummern der The5ers-Klauseln stammen aus einem automatischen Abruf ihrer T&C-Seite und sind ggf. nicht exakt; die **Substanz** (schriftliche Freigabe für Automatisierung, Quellcode-Eigentum) ist der belastbare, handlungsrelevante Punkt.

---

## 3. Bedingungen, damit es erlaubt BLEIBT (Tool-Guardrails)

1. **SL/TP müssen echte, broker-sichtbare Orders sein — kein „Stealth"/virtueller SL.** The5ers verbietet versteckte Stops ausdrücklich. → R7 setzt echte `OrderSend`-SL/TP ✓. **Niemals** einen rein internen/virtuellen SL einbauen.
2. **Server-Request-Volumen niedrig halten** (FTMO: <2.000 Requests/Tag; The5ers/FundedNext: Hyperaktivität). Im Normalbetrieb sehr gering (Close nur bei Regelbruch, Enforcement auf 300 ms gedrosselt; Close-Queue mit Retry-Limit 5 + Backoff bis 4 s deckelt Storms). → bleibt menschen-getaktet ✓. *Watch-Item: keine engen Poll-Schleifen ergänzen; ein Tages-Request-Zähler wäre eine sinnvolle Zusatz-Härtung.* **Mit R22** kommt Close-Volumen dazu, das der Trader selbst auslöst (jede manuelle Order → 1 Close-Auftrag, bei Fehlern bis zu 5 Versuche mit Backoff); wer viel manuell klickt, erzeugt entsprechend mehr Requests.
3. **`TOOL_ONLY` / eigenes Konto, eigene Trades** — `InpFundedMode=true` für Real/Funded (erzwingt TOOL_ONLY, sperrt TestMode). Kein Zweitkonto, kein Mirroring, kein Dritt-Zugriff ✓. **Ausnahme R22:** greift unabhängig vom Scope auf Magic-0-Orders desselben Kontos (Abschnitt 1.1) — bleibt eigenes Konto, ist aber nicht mehr „nur eigene Trades".
4. **Source-Eigentum** — du besitzt den Quellcode (`MamalTrading.mq4`). Für FundingPips/Alpha ggf. Source + Versionsverlauf vorzeigen können ✓.
5. **Schriftliche Freigabe einholen bei Alpha Capital UND The5ers** (jeweils nur, falls du dort handeln willst): Alpha Capital verlangt sie ausdrücklich (Datei einreichen, Prozess MT5/EX5). The5ers verlangt sie **laut ihrer T&C** ebenfalls (Abschnitt 2.1) — auch wenn ihre Help-FAQ permissiver klingt; den Widerspruch vor der Anmeldung direkt mit The5ers auflösen. **Kein allgemeiner Blocker** — FTMO/FundedNext/FundingPips brauchen nach aktueller Quellenlage keine Vorab-Freigabe.
6. **FundedNext:** EA-Add-on/Gebühr aktivieren; Consistency-Regeln beachten.
7. **TestMode (`InpTestMode`) niemals auf Funded** — wird durch `InpFundedMode` hart deaktiviert ✓.
8. **R22 vor dem Funded-Konto firmenspezifisch bestätigen** (Abschnitt 1.1) — bis dahin im Zweifel `InpCloseManualTrades=false`. Und: `InpMagic` **nie** auf 0, sonst schließt R22 die eigenen Panel-Trades.

---

## 4. Ehrliche Restgrenzen

- **Client-seitig = erkennen-und-schließen (~0,5 s), nicht die harte Firmen-Grenze.** Das echte Backstop ist das **server-seitige Daily-/Max-Loss-Limit der Firma**. Der EA *senkt die Wahrscheinlichkeit* eines Bruchs, ersetzt das Firmenlimit nicht.
- Die Firmen-Regeln sind teils **bewusst breit + discretionary** (Einzelfallentscheidung). „likely-allowed" ≠ Garantie.
- Recherche-Quellen tlw. Sekundärseiten (einige Firmen-Seiten gaben 403/404 auf automatischen Abruf) — **bei Anmeldung am Original verifizieren**.
- **R22 ist ebenfalls detect-and-revert, nicht verhindern.** Der manuelle Trade läuft zuerst — der EA schließt ihn danach zu Marktpreis. **Spread und Slippage trägt der Trader**, ein Verlust kann entstehen. Die Erkennungs-Latenz ergibt sich aus Timer (1 s) bzw. Tick (≥500 ms) + Close-Throttle (300 ms) + ggf. bis zu 2 s Modify-Quiet-Fenster + Retry/Backoff: realistisch **Bruchteile einer Sekunde bis mehrere Sekunden**, bei geschlossenem Markt (Fehler 132) bis zu 15 min pro Versuch. Läuft der EA nicht oder ist AutoTrading aus, greift R22 gar nicht.
- **R22-Closes und die Verlust-Regeln:** Ein per R22 geschlossener manueller Trade zählt **nicht** in R5 Cooldown, R6 Verlustserie, R19 De-Risk, R25 Revenge und verbraucht **kein** R3-Tagesbudget (out of scope / falsche Magic). Der realisierte Verlust schlägt aber sehr wohl auf die **equity-basierten** Grenzen durch: R4 Tagesverlust, R4b Max-Loss, R18 Wochenlimit. Für die Firmen-Limits ist damit alles erfasst; die Disziplin-Statistik des Tools sieht diese Trades nur teilweise.
- Gemäß deiner Vorgabe ist eine schriftliche Firmen-Bestätigung **kein allgemeiner Pflicht-Blocker**. Sie ist **nur bei Alpha Capital** zwingend — **und auch nur, wenn du dort handeln willst**; für FTMO/The5ers/FundedNext/FundingPips ist keine Vorab-Freigabe nötig. Bei FTMOs discretionary Regime ist eine schriftliche Support-Bestätigung der einzige Weg, es freiwillig voll zu entrisiken (optional).

---

## 5. Verdikt

Das Tool sitzt bei **allen fünf** recherchierten Firmen in der **am stärksten erlaubten** Automations-Kategorie: ein **nicht-Signal-generierender, Einzelkonto-, diskretionär-Entry-Risk-Management-EA**, der **jedes** üblich verbotene Muster vermeidet. Es ist ausdrücklich **kein** „Challenge-Passer"/Signal-Seller.

**Pre-Approval-Gate nach der Primärquellen-Prüfung (2026-07-21) + Support-Bestätigung (2026-07-22):** **FTMO** — kein Gate, **schriftlich als erlaubt bestätigt** (selbst entwickelter EA, kein Third-Party; Abschnitt 2.0), und der stärkste Fit (das Tool erzwingt FTMOs eigenes „Risk per Trade Idea", Abschnitt 2.1). Offen bleibt nur die punktuelle Absegnung von R22/Frequenz. **The5ers** — die T&C verlangt eine **schriftliche Freigabe** (Widerspruch zur Help-FAQ, zu klären). **Alpha Capital** — Pflicht-Freigabe. **FundedNext/FundingPips** — nach bisheriger (Sekundär-)Quellenlage kein Freigabe-Gate, aber Bedingungen (EA-Add-on/Consistency bzw. Source-Nachweis); für diese beiden liegt noch **keine** Primärquellen-Prüfung vor.

**Ein Punkt ist seit v0.35 offen:** Die Recherche in Abschnitt 2 wurde vor **R22** gemacht und deckt den Fall „EA schließt auch manuell eröffnete Positionen desselben Kontos" **nicht** ab. Die Kategorie-Einordnung bleibt unverändert (Einzelkonto, kein Signal, kein Copy-Trading), aber ob das Verhalten unter die jeweilige „Trade-/Risk-Management-EA"-Erlaubnis fällt, ist **firmenspezifisch zu bestätigen** (Abschnitt 1.1). Der konservative Zustand bis dahin: `InpCloseManualTrades=false`.

**Status bleibt: Demo-only, nicht Prop-Firm-ready** — Compliance-Einordnung ist günstig, ersetzt aber nicht F7 + Rule-Test-Matrix + Demo-Forward + die firmenspezifische Verifikation/Freigabe.

---

## Quellen (vollständige URLs — bei Anmeldung gegen die jeweils aktuelle Firmen-Seite prüfen)

**FTMO** — *Primärquellen 2026-07-21 geprüft (★); Support-Bestätigung 2026-07-22 (★★)*
- ★★ FTMO-Support-Ticket **QVM-FSGGG-356** (E-Mail-Verlauf 2026-07-22, „Yes, you can"; selbst entwickelter EA = kein Third-Party) — im privaten Schriftverkehr des Traders, Abschnitt 2.0
- ★ FTMO *General Terms and Conditions* (PDF, 22 S., vom Nutzer übergeben 2026-07-21; Risk Management Rules Klauseln 7.4–7.6, „Risk per Trade Idea" 7.5.3/7.6.6; Forbidden-Practices-Verweis 7.3)
- ★ https://ftmo.com/en/forbidden-trading-practices/ (EAs erlaubt <2.000 Requests/Tag; Gap-/News-Verbot)
- https://ftmo.com/en/faq/which-instruments-can-i-trade-and-what-strategies-am-i-allowed-to-use/
- https://ftmo.com/en/what-does-profitable-trading-look-like-with-a-working-ea/

**The5ers** — *T&C 2026-07-21 geprüft (★)*
- ★ https://the5ers.com/terms-and-conditions/ (Klausel „Use of Automated Trading Software": vorherige schriftliche Freigabe nötig, Dritt-EAs verboten, Quellcode-Eigentum; Forbidden Practices: HFT/Tick-Scalping/Copy-Trading/Rollover-Scalping)
- https://help.the5ers.com/can-i-use-an-ea-expert-advisor-can-i-set-a-stealth-mode-stop-loss/ (Help-FAQ — permissiver; **Widerspruch zur T&C**, direkt klären)
- https://help.the5ers.com/prohibited-trading-practices/
- https://the5ers.com/faqs/
- https://www.eafunded.com/firms/the5ers (Sekundär)
- https://thetrustedprop.com/blogs/important-rules-to-know-before-trading-with-the5ers (Sekundär)

**FundedNext**
- https://help.fundednext.com/en/articles/8020763-is-ea-allowed-in-fundednext
- https://help.fundednext.com/en/articles/8020351-what-are-the-restricted-prohibited-trading-strategies
- https://help.fundednext.com/en/articles/11982271-does-fundednext-allow-hft-high-frequency-trading
- https://help.fundednext.com/en/articles/8388896-are-there-any-restrictions-on-my-trading-strategy
- https://help.fundednext.com/en/articles/11641338-can-i-use-ea-in-stellar-instant

**FundingPips**
- https://help.fundingpips.com/hc/en-us/articles/34505029138449-Trading-Conduct-and-Security-Standards
- https://fundingpips.com/terms-and-conditions
- https://help.fundingpips.com/hc/en-us/articles/34504137479441-News-Trading-Weekend-Holding
- https://thetrustedprop.com/blogs/rules-to-keep-in-mind-when-trading-with-funding-pips (Sekundär)
- https://sureshotfx.com/blog/prop-firms-that-allow-ea-trading (Sekundär)
- https://www.fxempire.com/prop-firms/fundingpips (Sekundär)

**Alpha Capital (AlphaCapitalGroup)**
- https://help.alphacapitalgroup.uk/en/articles/6934236-can-i-use-an-expert-advisor-ea
- https://help.alphacapitalgroup.uk/en/articles/6934275-what-are-prohibited-trading-strategies
- https://help.alphacapitalgroup.uk/en/articles/8786973-is-copy-trading-allowed
- https://www.eafunded.com/firms/alpha-capital (Sekundär)
- https://thetrustedprop.com/blogs/alpha-capital-group-trading-rules-allowed-vs-not-allowed (Sekundär)

**Allgemein / Landschaft**
- https://propfirmmatch.com/prop-firm-rules
- https://tttmarkets.com/articles/why-prop-firms-do-not-allow-high-frequency-trading/
- https://copygram.app/blog/education/equity-protector-automating-prop-firm-daily-loss-limit
- https://funderpro.com/blog/master-prop-firm-drawdown-rules-in-2025/
