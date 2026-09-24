# Tier-1 Regel-Test-Matrix — Mamal-Trading

_Stand: 2026-07-20, gegen EA v0.35 (R22 „Nur Panel-Trades" + R7-Grace persistent + Heilfrist). Reihenfolge = Haftungs-Risiko (Achse 3) absteigend. Nur auf **Demo** testen. Abhaken: ☐ offen · ✅ bestanden · ❌ Bug._

> **Grundregel:** Jeder Test ist ein versprochenes Feature. Was hier ❌ ist, darfst du im Marketing NICHT versprechen, bis es ✅ ist.

**Konfig-Entscheidung getroffen:** WEG 1 — `WatchScope=TOOL_ONLY` bleibt. Das Tool überwacht **nur Panel-Trades** (Magic 990201). Manuelle/Handy-Trades (Magic 0) sind damit außerhalb der **Scope-Überwachung** (R7-SL-Prüfung etc.) → Kundenverantwortung (siehe unten). Kein FundedMode-Umbau. **⚠ Seit v0.35 nur noch die halbe Wahrheit** — R22 schließt Magic-0-Trades trotzdem, siehe Nachtrag direkt darunter.

**Nachtrag v0.35 (R22):** Der Scope bleibt `TOOL_ONLY`, aber `InpCloseManualTrades=true` (Default) schließt manuelle Trades (Magic 0) trotzdem — **kontoweit über alle Symbole**, auch im FundedMode. R22 ist die einzige Enforcement-Funktion, die `InScope()` umgeht (Magic-Vergleich statt Scope-Prüfung). Die Scope-Lücke unten gilt daher nur noch für `InpCloseManualTrades=false`.

---

## R7-Verhalten in v0.34 (dein Kern-Feature)

- `InpRequireSL=true`, `InpRequireTP=true` → ein In-Scope-Trade ist „nackt", wenn **SL ODER TP** fehlt.
- **4 s Grace ab dem Entfernen** (nicht ab Trade-Eröffnung). Uhr startet, sobald das Tool den Trade zum ersten Mal nackt sieht. SL/TP innerhalb der 4 s wieder setzen → **kein** Close.
- **v0.34 — Uhr persistent + Heilfrist:** die Uhr liegt pro Ticket in GlobalVariables (`RG_NK_<ticket>`) und überlebt **Terminal-Neustart, Recompile, Timeframe-Wechsel und Master-Handoff** (vorher schenkte jeder dieser Fälle eine frische Frist). Gelöscht wird sie erst, wenn SL/TP **60 s am Stück** gesetzt waren (`RG_NKH_<ticket>`); wirst du vorher wieder nackt, verfällt die Heilfrist und die **alte** Uhr läuft weiter. Ein kurzes SL-Toggle kauft also keine neue Frist.
- **v0.34 — tighten-only:** `InpRequireSL`/`InpRequireTP` sind einmal aktiv intraday nicht mehr abschaltbar (`EffRequireSL()`/`EffRequireTP()`); Lockern greift erst zum Tageswechsel.
- Gilt **einheitlich auch für Panel-Trades** (kein Sofort-Close mehr).
- Nach Ablauf wird **der Trade geschlossen** — MT4 bleibt am Leben.
- News-Blackout: `InpSLTPGraceNews=0` → sofortiger Close.
- Hinweis: Das Modify-Quiet-Fenster (2 s Crash-Schutz) schiebt den Uhr-Start bis nach dem letzten manuellen Zug — real also ~4 s _nachdem du aufhörst zu ziehen_.

---

## Test 0 — CRASH-REGRESSION (der Blocker, v0.31-Fix)

Ohne dieses ✅ ist alles andere wertlos.

| # | Setup | Schritte | Erwartet | Status |
|---|---|---|---|---|
| 0.1 | Panel-Trade offen, SL entfernt (→ R7 will schließen) | Während der 4-s-Frist **SL/TP-Linie weiter ziehen/modifizieren** | **Kein MT4-Crash.** Modify-Quiet verschiebt, danach sauberer Close. | ☐ |
| 0.2 | Beliebiger Trade | TP verschieben, loslassen, sofort wieder verschieben (mehrfach schnell) | Kein Crash; Panel bleibt responsiv. | ☐ |
| 0.3 | Trade manuell schließen während Tool-Zyklus läuft | Position im Terminal-Fenster schließen | Kein Crash (Ursache v0.31: OrderClose in User-Modify). | ☐ |

**Wenn 0.x ❌:** stopp — zurück zur Reentrancy. Kein Business-Schritt vorher.

---

## Test 1 — R7 SL/TP-Pflicht + 4-s-Grace (Kern-Versprechen)

| # | Setup | Schritte | Erwartet | Status |
|---|---|---|---|---|
| 1.1 | Panel-BUY mit SL+TP | normal öffnen | bleibt offen | ☐ |
| 1.2 | Panel-Trade | SL entfernen, **nichts tun** | nach ~4 s Close, Journal „R7 SL/TP fehlt (Ns nach Entfernen, Grace 4s)" | ☐ |
| 1.3 | Panel-Trade | SL entfernen, **innerhalb 4 s wieder setzen** und **gesetzt lassen** (> 60 s) | **kein** Close; nach 60 s ist die Uhr abgeräumt (`RG_NK_`/`RG_NKH_` weg) | ☐ |
| 1.3b | Panel-Trade | SL entfernen, **innerhalb 4 s kurz wieder setzen und sofort wieder entfernen** (Toggle, deutlich unter 60 s) | **Close kommt** — die Heilfrist ist verfallen, die **alte** Uhr lief weiter; kein Frist-Reset per Toggle (v0.34) | ☐ |
| 1.3c | Panel-Trade **nackt** (SL entfernt), Frist läuft | **Terminal neu starten** / Recompile / Timeframe wechseln, dann nichts tun | Frist **läuft weiter statt neu zu beginnen** → Close sofort nach dem Wiederanlauf (Uhr steckt in `RG_NK_<ticket>`) | ☐ |
| 1.3d | Panel-Trade offen mit SL+TP | `InpRequireSL=false` setzen und EA neu initialisieren (intraday) | SL-Pflicht bleibt **aktiv** (tighten-only); Abschalten wirkt erst nach dem Tageswechsel | ☐ |
| 1.4 | Panel-Trade | **TP** entfernen, nichts tun | nach ~4 s Close (RequireTP=true) | ☐ |
| 1.5 | Manueller Trade **ohne SL** (`TOOL_ONLY`, Funded-Default), **`InpCloseManualTrades=false`** | öffnen, warten | **wird NICHT geschlossen** (R7-Scope-Lücke — Kundenverantwortung) | ☐ |
| 1.5b | dasselbe mit R22-Default **`InpCloseManualTrades=true`** | öffnen, warten | Trade **wird** geschlossen — aber wegen **R22**, nicht wegen R7 (R7 prüft ihn nach wie vor nicht) → siehe Test 1b | ☐ |
| 1.6 | Panel-Trade, News-Blackout aktiv | SL entfernen | **sofort** Close (Grace 0 bei News) | ☐ |

## Test 1b — R22 „Nur Panel-Trades" (v0.35, neu)

_Einsortiert direkt hinter R7: R22 ist die einzige Regel, die Positionen schließt, die der EA **nicht selbst geöffnet** hat — Haftungsrisiko entsprechend hoch (Fehlauslösung kostet echtes Geld)._

**Vorbedingung für alle Tests dieses Blocks (sonst passiert nichts):** AutoTrading an, EA ist die **bestätigte Master-Instanz** (mind. 2 Cycles in Folge — auf einer passiven Zweit-Instanz greift R22 nicht), `InpMagic=990201` (Default), Markt offen. Default `InpCloseManualTrades=true`.

| # | Setup | Schritte | Erwartet | Status |
|---|---|---|---|---|
| 1b.1 | `InpCloseManualTrades=true` (Default), keine Sperre | Manuellen **Markt-Trade** per MT4-Orderfenster (F9) öffnen, nichts weiter tun | Position wird **binnen ~1 s** geschlossen (Timer 1 s + Close-Throttle 300 ms). Journal-Zeile mit Grund **„R22 Manueller Trade — nur Panel-Trades erlaubt"**, Tag `Queue OK (Versuch 1): R22 …`. | ☐ |
| 1b.2 | **Aktive Tages-Sperre** (R4 ausgelöst, z. B. via Test 3.1), `WatchScope=TOOL_ONLY` | Manuellen Markt-Trade öffnen | Trade wird **ebenfalls geschlossen** — R22 läuft im Enforcement-Block **vor** dem Lock-Zweig. (Bis v0.34 gab es hier nur eine Warnung max. 1×/60 s und der Trade blieb offen.) | ☐ |
| 1b.3 | `InpCloseManualTrades=true` | Manuelle **Pending-Order** (Buy-Limit/Stop) mit deutlichem Abstand zum Markt setzen | Pending wird per `OrderDelete()` **gelöscht, bevor sie füllen kann**. Grund „R22 Manuelle Pending-Order — nur Panel-Trades erlaubt", Tag `Queue DELETE ok: R22 …`. | ☐ |
| 1b.4 | Manuelle Position offen, **EA vom Chart entfernt** | EA neu auf den Chart ziehen | Startmeldung (Notify + Journal-Event `INFO`) **nennt die Anzahl**: „R22 Start: N manuelle Order(s) vorgefunden -> werden geschlossen" — **kein Bestandsschutz**. Der Close passiert **nicht** in `OnInit`, sondern erst im 2./3. Cycle (Master-Streak ≥2), also typisch 1–3 s später. | ☐ |
| 1b.5 | _(optional, nur falls ein zweiter EA verfügbar ist)_ Fremder EA mit **eigener Magic ≠ 0** auf zweitem Chart | Fremd-EA einen Trade öffnen lassen | Trade bleibt **unangetastet** — R22 überspringt alles mit `OrderMagicNumber() != 0`. | ☐ |
| 1b.5b | _(Konfigurations-Falle, nur Demo)_ `InpMagic=0` setzen | Panel-BUY klicken | Der **eigene Panel-Trade** wird von R22 abgeräumt (die Abgrenzung hängt allein an `Magic != 0`, es gibt keinen Code-Schutz dagegen). Erwartung = dieses Verhalten bestätigen, dann `InpMagic` zurücksetzen. | ☐ |
| 1b.6 | **`InpCloseManualTrades=false`** | Manuellen Markt-Trade öffnen; danach Cockpit-Dashboard laden | Trade **bleibt offen**; Cockpit führt **R22 als deaktiviert** („— aus"-Chip aus der `disabled`-Liste). Damit gilt wieder die R7-Scope-Lücke (Test 1.5). | ☐ |
| 1b.7 | Cockpit nach genau **einem** manuellen Trade aus 1b.1 | „Deine Schwächen" öffnen | R22 taucht auf (Zuordnung nur über den Cockpit-Fallback `ruleFromTag()`, die RuleId-Spalte des EA bleibt bei R22 **leer**). **Bekannte Grenze:** jeder Retry, jeder FINAL-FAIL und jedes Verwerfen erzeugt eine eigene CLOSE-Zeile → der Zähler kann **einen** manuellen Trade mehrfach zählen. Zahl > 1 ist hier **kein** Bug. | ☐ |

**Ehrliche Grenzen von R22 (gehören ins Onboarding, nicht wegdiskutieren):**

- **detect-and-revert, kein Verhindern.** R22 hält den Trade nicht auf — er wird eröffnet und danach **zu Marktpreis** wieder geschlossen. Spread und Slippage (`InpSlippage`) trägt der Trader. Der Grund für die Regel ist der Umkehrschluss: nur der Panel-Pfad (`DoEntry()`) durchläuft die Entry-Gates R4b, R13, R5, R16, R25, R14, R7, R15, R1, R2, R3, R12, R17 — ein manueller Trade umgeht sie alle.
- **Erkennungs-Latenz, keine feste Zahl.** Takt: Timer 1 s bzw. Tick ≥500 ms, plus Close-Throttle 300 ms, plus ggf. bis zu 2 s **Modify-Quiet** (wer dauernd an SL/TP zieht, verzögert R22 — hart gedeckelt auf 10 s Serie), plus Backoff bei Fehlversuchen. Realistisch: **Bruchteile einer Sekunde bis mehrere Sekunden.** Bei geschlossenem Markt (Fehler 132) bis zu **15 min** pro Versuch.
- **Eine Pending direkt am Markt kann schneller füllen als R22 sie sieht.** Dann greift nicht 1b.3, sondern 1b.1 — die entstandene Position wird geschlossen.
- **Kein Schutz ohne laufenden EA.** EA nicht auf dem Chart, AutoTrading aus, passive Instanz oder gescheitertes `EventSetTimer` → R22 wirkt nicht.
- **Fehlversuche bleiben offen.** Nach 5 Versuchen (`InpCloseRetries`) fliegt das Ticket mit FINAL-FAIL aus der Queue und die Order **bleibt offen** — sie wird aber im nächsten Durchlauf erneut eingereiht.
- **Verlust zählt asymmetrisch.** Ein per R22 geschlossener manueller Trade fließt **nicht** in R5 Cooldown, R6 Verlustserie, R19 De-Risk, R25 Revenge und verbraucht **kein** R3-Tagesbudget (beide Auswertungen filtern auf In-Scope bzw. `InpMagic`). Der realisierte Verlust schlägt aber sehr wohl auf die equity-basierten Grenzen **R4, R4b und R18** durch.
- **Im On-Chart-Panel taucht R22 nicht auf** — Feedback gibt es nur über Notify, Journal und Cockpit.
- **Compliance firmenspezifisch prüfen.** Der EA schließt auch im FundedMode Positionen, die er nicht selbst geöffnet hat. Ob die jeweilige Prop-Firm das zulässt, ist **vor** dem Live-Einsatz zu klären; der bestehende Warnhinweis zu `ALL_POSITIONS` deckt diesen Fall nicht ab.

## Test 2 — R1 Risiko/Trade

Close, wenn Risiko(SL) > `InpRiskPerTradePct`×`InpRiskTolFactor` (0,25 %×1,10 = **0,275 %**). Nur Trades **mit** SL.

| # | Setup | Erwartet | Status |
|---|---|---|---|
| 2.1 | Trade mit SL, Risiko ~0,2 % | bleibt | ☐ |
| 2.2 | Trade mit SL, zu große Lot/weiter SL → Risiko ~0,5 % | Close „R1 Risiko zu gross (…%)" | ☐ |

## Test 3 — R4 Tages-Sperre & R4b Max-Loss

| # | Setup | Schritte | Erwartet | Status |
|---|---|---|---|---|
| 3.1 | `InpDailyLossPct=0.2` (Demo) | Verlust bis −0,2 % Tagesbasis | **Tages-Sperre**: SafeCloseAll + KEINE neuen Trades bis Mitternacht | ☐ |
| 3.2 | `InpMaxLossPct=0.3` (Demo) | Verlust bis −0,3 % gesamt | **Hard-Lock** + SafeCloseAll | ☐ |
| 3.3 | Bei Sperre ein manueller (out-of-scope) Trade offen, **`InpCloseManualTrades=false`** | — | Tool schließt ihn NICHT, warnt aber laut (1×/min) — `SafeCloseAll()` überspringt out-of-scope-Orders | ☐ |
| 3.3b | dasselbe mit R22-Default **`InpCloseManualTrades=true`** | — | Trade **wird geschlossen** (R22 läuft vor dem Lock-Zweig) → Test 1b.2 | ☐ |
| 3.4 | Tighten-Only: `InpDailyLossPct` intraday **hoch**setzen | — | greift NICHT sofort (Lockern erst zum Tageswechsel) | ☐ |

_(Alternativ Test-Trigger `daylock`/`maxlock` via `InpTestMode=true` — nur Demo.)_

## Test 4 — Panel BUY/SELL Korrektheit

| # | Setup | Erwartet | Status |
|---|---|---|---|
| 4.1 | Panel-BUY-Klick | Order korrekte Richtung, SL+TP gesetzt, Magic 990201 | ☐ |
| 4.2 | Klick auf SL-Linie vs. Button | Button löst Trade aus, SL-Linien-Klick NICHT (Bounds-Guard) | ☐ |

---

## Scope-Lücke = ehrliche Produkt-Grenze (Weg 1)

**Gilt ab v0.35 nur noch bei `InpCloseManualTrades=false`.** Mit dem Default `true` schließt R22 manuelle Trades stattdessen — die Lücke wird also nicht durch eine SL-Prüfung geschlossen, sondern dadurch, dass es solche Trades gar nicht erst geben soll (detect-and-revert, Slippage trägt der Trader → Test 1b).

Im `TOOL_ONLY` überwacht das Tool nur Panel-Trades. **Manuelle/Handy-Trades werden nicht auf SL geprüft.** Das ist die Voraussetzung, die der Kunde selbst erfüllen muss:
1. Immer selbst einen SL setzen.
2. Bei jedem geöffneten Trade selbst prüfen, dass ein SL dranhängt.

→ Muss in AGB/Onboarding/Panel **klar** kommuniziert werden. Das Tool ist Sicherheitsnetz für Panel-Trades + Disziplin-Wächter, kein Ersatz für den eigenen SL bei manuellen Trades.
