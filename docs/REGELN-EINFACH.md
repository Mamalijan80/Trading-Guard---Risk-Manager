# Mamal-Trading — Die Regeln einfach erklärt

*Für alle, ohne Technik-Wissen. Stell dir das Tool wie einen strengen, ruhigen Trainer vor, der neben dir sitzt: Er sagt dir nie, **was** du traden sollst — das entscheidest du. Aber er passt auf, dass du dich nicht selbst ruinierst.*

**Beispiel-Konto in diesem Text: 20.000 €. Risiko pro Trade: 50 € (das sind 0,25 %).** Alle Zahlen sind die aktuellen Einstellungen und lassen sich anpassen.

**Wichtig zu den Euro-Beträgen:** Jede €-Zahl in diesem Text gilt für ein **20.000-€-Konto**. Das Tool ist auch für **10.000 €** und **25.000 €** gedacht — dann ändern sich alle Beträge mit (bei 10k die Hälfte, bei 25k ein Viertel mehr). Was **immer** gilt, ist der **Prozentwert**: Das Tool rechnet nie mit einer festen Euro-Summe, sondern immer in Prozent deines echten Kontos.

---

## Das Wichtigste in einem Satz
Du ziehst eine **rote Linie** dorthin, wo dein Stop sein soll, und klickst **Kaufen** oder **Verkaufen**. Das Tool rechnet die richtige Größe aus, eröffnet den Trade mit Absicherung — und greift ein, wenn du gegen eine deiner Schutzregeln verstößt.
*Die rote Linie setzt du entweder durch **direktes Ziehen**, oder indem du **3× in dieselbe Zone klickst** (Schutz gegen versehentliches Verschieben beim ersten Klick). Das Panel zeigt „noch 2× / 1× klicken".*

---

## Schnellüberblick (alle Regeln in einer Tabelle)

| Regel | Was sie für dich tut | Kurzes Beispiel |
|---|---|---|
| **Trade-Größe automatisch** | Rechnet die Lot-Größe so, dass du nie mehr als 50 € pro Trade riskierst | Stop nah = kleinere Größe, Stop weit = größere Größe — immer 50 € |
| **Eine Idee = ein Limit** | Mehrfach dasselbe in dieselbe Richtung = max. 100 € zusammen | 2× Gold-Kauf = voll, 3. wird blockiert |
| **Tages-Budget** | Pro Tag max. **400 €** Risiko aufmachen (ca. 8 Trades) | Nach 8 Trades ist für heute Schluss |
| **Tages-Verlust-Bremse** | −400 € am Tag → alles zu, gesperrt bis morgen | 20.000 → 19.600 → Notbremse |
| **Gesamt-Verlust-Schutzschild** | −1.000 € → Frühwarnung, −1.200 € → dauerhaft gesperrt | schützt dein ganzes Konto |
| **Pause nach 3 Verlusten** | 3 Verluste in Folge → 45 Min Pause | kurz durchatmen statt weiter im Frust |
| **Stopp nach 5 Verlusten** | 5 Verluste in Folge → für heute Schluss | schlechte Tage werden begrenzt |
| **Absicherung Pflicht** | Jeder Trade braucht Stop **und** Ziel | ohne Stop → nach 4 Sek. geschlossen |
| ~~Lohnt sich der Trade?~~ | *(auf deinen Wunsch **AUS**)* | — |
| **Doppel-Bestätigung** | *(auf deinen Wunsch aus)* | ein Klick öffnet sofort |
| **Kein Schummeln** | Kein eingebauter Entsperr-Knopf, Sperren überleben Neustart | starke Reibung gegen Impulse (wirklich un-umgehbar erst auf einem gesperrten VPS) |
| **Tagebuch** | Alles wird mitgeschrieben (mit Grund) | später nachvollziehbar |
| **Gesamt-Risiko-Deckel** | Alle offenen Trades zusammen max. 200 € | 4 Trades offen = voll |
| **Tagesziel sichern** | +600 € → keine neuen Trades; Gewinn nicht verspielen | grüner Tag bleibt grün |
| ~~Kurze Pause~~ | *(auf deinen Wunsch **AUS**)* | — |
| **Mindest-Stop-Abstand** | ~~min. 5 Pips~~ **AUS** (seit v0.22) — es gilt nur noch der Mindestabstand deines Brokers | „Mini-Stop"-Trick wird nur noch vom Broker begrenzt |
| **Handelszeiten/News** | *(optional)* nur in einem Zeitfenster traden | z. B. nicht nachts |
| **Nicht zu viel in eine Währung** | Zählt eine Währung über mehrere Paare zusammen | 2× „Dollar-short" = viel, 3. blockiert |
| **Wochen-Limit** | −1.000 € über die Woche → Woche gesperrt | begrenzt schlechte Wochen |
| ~~Risiko runter nach Verlusten~~ | *(auf deinen Wunsch **AUS**)* | — |
| ~~Kein Rache-Trade~~ | *(auf deinen Wunsch **AUS**)* | — |
| **Nur Panel-Trades** | Trades, die nicht über das Panel laufen, macht das Tool wieder zu | Kauf per Handy-App → meist nach etwa einer Sekunde wieder geschlossen |

---

## Jede Regel ausführlich, mit Beispiel

### 1) Trade-Größe automatisch — „Du musst nie selbst rechnen"
**Was:** Du ziehst die rote Linie dorthin, wo dein Stop-Loss sein soll (oder **klickst 3× in dieselbe Zone**). Das Tool berechnet sofort, wie groß dein Trade sein darf, damit du **höchstens 50 €** verlierst.
**Beispiel:** Du willst Gold kaufen.
- Rote Linie 20 Pips unter dem Preis → Tool öffnet **0,25 Lot**.
- Rote Linie nur 10 Pips weg → Tool öffnet **0,50 Lot**.
- In **beiden** Fällen riskierst du genau **50 €**.
**Extra-Schutz:** Schiebst du nach dem Einstieg den Stop weiter weg (mehr Risiko), schließt das Tool den Trade, sobald das Risiko über 50 € klettert. Den Stop **näher** ziehen ist immer erlaubt.

### 2) Eine Idee = ein Limit — „Verrenn dich nicht in eine Richtung"
**Was:** Mehrere Käufe im selben Markt in dieselbe Richtung zählen als **eine Idee**. Zusammen höchstens **100 €** Risiko.
**Beispiel:** Gold-Kauf (50 €), nochmal Gold-Kauf (50 €) → zusammen 100 € = voll. Ein **dritter** Gold-Kauf wird blockiert. Ein Gold-**Verkauf** oder ein anderer Markt geht weiter.

### 3) Tages-Budget — „Nicht den ganzen Tag durchballern"
**Was:** Das Tool addiert über den Tag, wie viel Risiko du **eröffnet** hast — auch Gewinner zählen (es gibt nichts zurück). Bei **400 €** (ca. 8 Trades) ist für heute Schluss.
**Beispiel:** Du machst 8 Trades à 50 € auf → der **9. wird blockiert** („Tagesbudget erreicht"), selbst wenn alle 8 im Gewinn sind. Morgen beginnt das Budget wieder bei null. *(Das Budget ist bewusst genauso hoch wie die Tages-Verlust-Bremse von 400 €, damit die Bremse auch erreichbar ist und das Tagesziel machbar bleibt.)*

### 4) Tages-Verlust-Bremse — „Der Not-Aus für den Tag"
**Was:** Rutscht dein Konto an einem Tag **−400 €** ins Minus (gegenüber dem Tagesstart), schließt das Tool **alles** und sperrt bis Mitternacht.
**Beispiel:** Start 20.000 €, im Tagesverlauf auf 19.600 € → alle **vom Tool eröffneten** Trades zu, keine neuen bis morgen. So reißt du nicht das Limit der Prop-Firma. **Wichtig:** Trades eines **anderen Handelsprogramms** schließt das Tool im Echt-/Funded-Modus **nicht** — es **warnt** dann laut, dass du sie selbst schließen musst. Trades, die du **von Hand** (außerhalb des Panels) aufmachst, sind hier kein Thema mehr: die räumt Regel 22 ohnehin laufend weg.

### 5) Gesamt-Verlust-Schutzschild — „Schutz fürs ganze Konto" (zwei Stufen)
**Was:**
- **−1.000 € (5 %): Frühwarnung** → keine neuen Trades mehr (offene darfst du noch managen).
- **−1.200 € (6 %): dauerhaft gesperrt.**
**Beispiel:** Konto fällt von 20.000 auf 19.000 € → „Max-Loss-Warnung". Fällt es weiter auf 18.800 € → komplett & dauerhaft dicht. Das ist dein Sicherheitsabstand zum 10 %-Limit der Firma.

### 6) Pause nach 3 Verlusten — „Kurz durchatmen"
**Was:** 3 Verlust-Trades hintereinander → **45 Minuten** Pause für neue Trades.
**Beispiel:** Stop, Stop, Stop → „Cooldown 45 Min". Statt im Frust weiterzumachen, machst du erstmal Pause.

### 7) Stopp nach 5 Verlusten — „Schlechte Tage begrenzen"
**Was:** 5 Verluste in Folge → für heute gesperrt.
**Beispiel:** Nach dem 5. Stop in Folge: „gesperrt bis morgen".

### 8) Absicherung Pflicht — „Nie ohne Stop und Ziel"
**Was:** Jeder Trade braucht einen **Stop-Loss** (Absicherung) **und** ein **Take-Profit** (Ziel). Trades vom Tool haben beides automatisch. Fehlt eines, hast du **4 Sekunden**, es nachzutragen — bei Tool-Trades genauso wie bei allen anderen überwachten Trades (der frühere Sofort-Rauswurf für Tool-Trades ist weg). Die Uhr startet in dem Moment, in dem die Absicherung **fehlt oder entfernt wird** (nicht beim Öffnen des Trades): Nimmst du nach zwei Stunden den Stop weg, ist der Trade 4 Sekunden später zu. Die Uhr merkt sich das pro Trade: MetaTrader neu starten oder den Timeframe wechseln setzt sie **nicht** zurück, und ein kurzes Wieder-Antippen des Stops auch nicht — erst wenn Stop und Ziel **eine Minute lang** wieder gesetzt sind, ist die Frist wirklich vom Tisch.
**Beispiel:** Ein überwachter Trade ohne Stop → nach **4 Sekunden** schließt das Tool ihn. Während wichtiger Nachrichten („News") sogar **sofort**. *(Was du von Hand am Panel vorbei aufmachst, ist meist schon vorher weg — dafür sorgt Regel 22.)*
**Wichtig (kein Absturz):** Wenn du an einem Trade den Stop oder das Ziel **veränderst oder entfernst**, wird nur der **Trade** geschlossen — **MetaTrader selbst bleibt offen** und läuft weiter. Den Stop **näher** an den Preis ziehen darfst du jederzeit; ihn **weiter weg** ziehen erkennt das Tool als „zu viel Risiko" und schließt den Trade.

### 9) ~~Lohnt sich der Trade?~~ — **auf deinen Wunsch AUS**
Diese Regel (Mindest-Verhältnis Ziel:Risiko) ist **abgeschaltet**. Das Tool prüft das Chance-Risiko-Verhältnis nicht mehr. *(Das automatische Ziel deiner Tool-Trades liegt weiterhin bei 2× dem Risiko — nur als Vorschlag, nicht als Zwang.)*

### 10) Doppel-Bestätigung — *aus*
Diese zusätzliche Sicherheitsabfrage hast du **abgeschaltet**. Ein Klick öffnet sofort.

### 11) Kein Schummeln — „No-Override"
**Was:** Es gibt **keinen** Knopf, um eine Sperre vorzeitig aufzuheben. Sperren überleben sogar einen Neustart des Programms. Schaltest du den Auto-Handel ab, warnt das Tool deutlich („SCHUTZ AUS").
**Beispiel:** Du bist gesperrt und startest MetaTrader neu — die **Sperre bleibt**.

### 12) Tagebuch — „Alles wird mitgeschrieben"
**Was:** Jeder Trade, jede Blockade, jedes Schließen landet mit **Grund** in einer Datei.
**Beispiel:** Später siehst du: „13:42 — Trade blockiert: Tagesbudget". Gut zum Auswerten und als Nachweis gegenüber der Prop-Firma.

### 13) Gesamt-Risiko-Deckel — „Alle Trades zusammen"
**Was:** Egal wie viele Trades offen sind — **zusammen** nie mehr als **200 €** Risiko (4 Trades à 50 €).
**Beispiel:** 4 Trades offen = 200 € = voll, der 5. wird blockiert. Wird das Gesamtrisiko trotzdem zu hoch, schließt das Tool den **neuesten** Trade.

### 14) Tagesziel sichern — „Grüner Tag bleibt grün"
**Was:** Erreichst du **+600 €** (3 %), macht das Tool **keine neuen** Trades mehr. Und wenn du von einem Tageshoch zu viel zurückgibst, sperrt es den Tag.
**Beispiel:** Du bist +600 € → „Ziel erreicht" (offene Trades laufen weiter, aber nichts Neues). Oder: du warst +400 €, fällst zurück auf +200 € → Tag gesperrt, damit aus Grün nicht Rot wird.

### 15) ~~Kurze Pause~~ — **auf deinen Wunsch AUS**
Es gibt **keine** erzwungene Pause zwischen zwei Trades mehr. Du kannst sofort wieder klicken.

### 16) ~~Mindest-Stop-Abstand~~ — **auf deinen Wunsch AUS** (v0.22)
**Was:** Der Mindestabstand von 5 Pips ist **abgeschaltet** — M1-Scalping braucht enge Stops. Auch der optionale Lot-Deckel ist aus.
**Was noch schützt:** der **harte Mindestabstand deines Brokers** und Regel 1 — bei winzigem Stop wird zwar ein großes Lot berechnet, aber immer nur so groß, dass dein Risiko 50 € bleibt. **Ehrliche Grenze:** die Extremform „Mini-Stop → Slippage/Gap reißt mehr als 50 €" ist damit nicht mehr abgedeckt.

### 17) Handelszeiten / News — *optional*
**Was:** Wenn du willst: Handel nur in einem Zeitfenster + eine manuelle News-Sperre. **Standard: aus.**
**Beispiel (wenn an):** außerhalb 8–22 Uhr wird geblockt.

### 18) Nicht zu viel in eine Währung — „Auch über verschiedene Paare"
**Was:** Das Tool zählt zusammen, wie stark du auf **eine Währung** setzt — selbst wenn es verschiedene Paare sind.
**Beispiel:** Du kaufst EUR/USD **und** GBP/USD — beide wetten auf einen **schwachen Dollar**. Zusammen ist das viel „Dollar-short" → ein dritter solcher Trade wird blockiert. Gegenläufige Trades heben sich auf (z. B. EUR/USD-Kauf + USD/JPY-Kauf).
**Warum:** Damit nicht **eine** Währungsbewegung alle deine Trades gleichzeitig trifft.

### 19) Wochen-Limit — „Schlechte Woche begrenzen"
**Was:** Verlierst du über die Woche **−1.000 €** (5 %), ist die Woche gesperrt.
**Beispiel:** Mo–Mi zusammen −1.000 € → bis zum Wochenwechsel keine neuen Trades.

### 20) ~~Risiko runter nach Verlusten~~ — **auf deinen Wunsch AUS**
Dein Risiko pro Trade bleibt **konstant** (50 €). Es wird nach Verlusten nicht mehr automatisch halbiert.

### 21) ~~Kein Rache-Trade~~ — **auf deinen Wunsch AUS**
Es gibt **keine** Sperre für Gegen-Trades nach einem Verlust mehr. Für die Disziplin sorgen die harten Grenzen (Tages-/Gesamt-/Wochen-Bremse, Cooldown nach 3, Stopp nach 5).

### 22) Nur Panel-Trades — „Am Trainer vorbei geht nicht"
**Warum es diese Regel gibt:** Alle anderen Regeln hängen am Panel. Klickst du dort auf Kaufen oder Verkaufen, läuft dein Trade durch die komplette Kontrollkette: richtige Größe (1), Idee-Limit (2), Tagesbudget (3), Tagesziel (14), Cooldown nach 3 Verlusten (6), Handelszeiten (17), Gesamt-Risiko (13), Währungs-Häufung (18) und alles andere. Machst du den Trade **daneben** auf — direkt im Chart, im Marktfenster, per Handy-App unterwegs —, dann läuft **nichts** davon. Keine Größen-Rechnung, keine Zählung, kein Limit. Ein einziger solcher Trade hebelt in dem Moment alles aus, wofür die anderen Regeln da sind. Genau darum geht diese Regel: was nicht über das Panel kommt, bleibt nicht offen. **Standard: an.**

**Was konkret passiert:** Du sitzt im Zug, öffnest die Handy-App und kaufst Gold. Das Tool sieht diesen Trade und macht ihn wieder zu — meist **nach etwa einer Sekunde**. Dasselbe gilt für vorgemerkte Aufträge (Pendings), die du von Hand einträgst: die werden gelöscht. Es gilt für **alle** Märkte auf deinem Konto, nicht nur für den Chart, auf dem das Tool läuft. Und es gibt **keinen Bestandsschutz**: Sind beim Start des Tools schon Trades von Hand offen, werden auch die geschlossen — das Tool sagt dir beim Start, wie viele es gefunden hat.

**Trades anderer Programme bleiben unangetastet:** Läuft neben dem Tool noch ein anderes Handelsprogramm auf demselben Konto, lässt das Tool dessen Trades **in Ruhe**. Es erkennt sie an ihrer eigenen Kennung. Zugemacht wird nur, was **keine** Kennung trägt — und das ist genau das, was ein Mensch von Hand anklickt.

**Was diese Regel NICHT kann — ehrlich:**
- Sie **verhindert** den Trade nicht, sie **macht ihn rückgängig**. Der Trade war für ein paar Augenblicke echt am Markt. Du zahlst dafür den **Spread**, und beim Schließen den Preis, der gerade da ist — bei schnellen Bewegungen also möglicherweise etwas schlechter. Ein „Gratis-Zurück" gibt es nicht.
- **Etwa eine Sekunde** ist der Normalfall, keine Garantie. Je nachdem, was gerade läuft, kann es auch nur Bruchteile einer Sekunde oder mehrere Sekunden dauern. Ziehst du gleichzeitig ständig an Stops herum, verzögert das die Erkennung zusätzlich um ein paar Sekunden. Ist der Markt geschlossen, kann das Tool nichts schließen — es versucht es dann später wieder.
- Sie wirkt nur, wenn **MetaTrader läuft und der Auto-Handel an ist**. Ist der Auto-Handel aus, ist auch diese Regel aus — wie der ganze Schutz. Deshalb die orange Warnung „SCHUTZ AUS".
- Schlägt das Schließen mehrfach hintereinander fehl, gibt das Tool für diesen Trade zunächst auf und protokolliert das — beim nächsten Durchlauf versucht es ihn erneut. Ein Trade kann also in seltenen Fällen länger offen bleiben, als dir lieb ist.
- Der **Verlust** aus so einem Trade zählt für die großen Konto-Bremsen (Tages-Verlust, Gesamt-Verlust, Wochen-Limit) ganz normal mit — dein Konto merkt ihn ja. Er zählt aber **nicht** als „Verlust-Trade" für die Pause nach 3 und den Stopp nach 5, und er verbraucht auch **kein** Tagesbudget. Das Tool bewertet ihn nicht als deinen Trade, weil er nie durch die Kontrollkette lief.
- Im Cockpit taucht Regel 22 unter „Deine Schwächen" auf. Dort kann ein **einzelner** Trade von Hand **mehrfach** gezählt werden (jeder Schließ-Versuch erzeugt einen Eintrag). Nimm die Zahl als Hinweis, dass du am Panel vorbei getradet hast — nicht als exakte Stückzahl.

---

## Was du oben links im Chart siehst (die Anzeige)
Mehr als diese **9 Anzeigen** gibt es nicht. Ein einfaches „GESPERRT" steht **nie** da — das Tool sagt dir immer *welche* Sperre greift. Sind mehrere gleichzeitig aktiv, siehst du die **strengste** (die Liste ist von streng nach locker sortiert):

| Anzeige | Bedeutung |
|---|---|
| **SCHUTZ AUS** (orange) | Auto-Handel ist aus — das Tool kann gerade **nicht** schützen! |
| **MAX-LOSS GESPERRT** (rot) | Konto-Schutzschild — dauerhaft |
| **WOCHE GESPERRT** (rot) | Wochen-Verlustlimit erreicht |
| **TAG GESPERRT** (rot) | Für heute zu (Tagesverlust, 5 Verluste in Folge oder Gewinn-Rückgabe) |
| **MAX-LOSS WARNUNG** (orange) | Frühwarnung — keine neuen Trades |
| **COOLDOWN** (orange) | Pause nach 3 Verlusten |
| **ZIEL ERREICHT** (grün) | Tagesziel da — keine neuen Trades |
| **AUSSER SESSION** | Außerhalb der erlaubten Zeit / News-Sperre |
| **AKTIV** (grün) | Alles frei — du kannst traden |

*Im Cockpit im Browser steht oben derselbe Text — Panel und Cockpit können sich nicht widersprechen, beide lesen denselben Zustand.*

*Regel 22 („Nur Panel-Trades") hat **keine eigene Anzeige** im Panel — sie arbeitet still im Hintergrund. Dass sie zugeschlagen hat, merkst du daran, dass der Trade wieder weg ist; nachlesen kannst du es im Tagebuch und im Cockpit.*

---

## Zwei Schalter, die du kennen solltest
- **„Echtkonto/Funded"-Schalter:** Wenn du Richtung echtes oder Funded-Konto gehst, schaltest du diesen ein. Dann fasst das Tool nur **Trades aus dem Panel** an und der Übungsmodus ist gesperrt. **Eine Ausnahme, die du kennen musst:** Regel 22 gilt auch hier — Trades, die du **von Hand** aufmachst, schließt das Tool auch im Echtkonto-/Funded-Modus. Trades anderer Programme bleiben unangetastet.
- **„Übungsmodus":** Nur für Demo. Blendet Test-Knöpfe ein, mit denen du die Sperren absichtlich auslösen kannst, um zu sehen, dass alles funktioniert. Auf einem echten/Funded-Konto ist er **automatisch aus**.

---

## Ganz ehrlich: Was das Tool NICHT kann
- Es reagiert **sehr schnell, aber nicht in Null Sekunden** (ca. eine halbe Sekunde). Den größtmöglichen Schaden begrenzen die Tages- und Gesamt-Bremsen.
- Es kann einen Trade, den du **am Panel vorbei** aufmachst, nicht **verhindern** — nur **rückgängig machen** (Regel 22). Für die Sekunde dazwischen warst du echt im Markt: Spread bezahlt, Kurs kann sich bewegt haben. Die Regel schützt dein Regelwerk, nicht deinen Cent.
- Die **wirklich harte** Grenze ist das Limit deiner Prop-Firma (serverseitig). Das Tool sorgt dafür, dass du da gar nicht erst hinkommst — ersetzt es aber nicht.
- Auf dem **Mac** (über eine Hilfssoftware) kann MetaTrader instabil sein. Für echten Dauerbetrieb gehört es auf einen **Windows-Rechner/VPS**, der durchläuft.
- Es ist **kein Geld-Druck-Automat**. Es findet keine Trades für dich — es ist dein **Disziplin-Trainer**.

---

## Gut zu wissen: „Mitskalieren"
Wenn du dein **Risiko pro Trade** änderst (z. B. von 50 € auf 100 €), passen sich die anderen Limits (Idee, Gesamt-Risiko, Tagesbudget) **automatisch mit** an. Die Anzahl erlaubter Trades bleibt gleich. Du musst also nur an **einer** Stelle drehen.

---

*Ausführliche technische Fassung: `REGELN.md` · Spickzettel: `REGELN-TABELLE.md` · Compliance: `COMPLIANCE.md`.*
