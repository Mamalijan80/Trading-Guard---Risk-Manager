# Live-Umzug auf MAMAL-VPS — Ablaufblatt

> Jeder Schritt ist mit `[PC]` oder `[VPS]` markiert. Abhaken, nicht überspringen.
> Erstellt 17.11.2026, jede Aussage gegen den Quelltext geprüft (Datei:Zeile in Klammern).

---

## Stand 21.11.2026 (Samstag) — die Entscheidungen sind gefallen

| Frage | Antwort | Folge |
|---|---|---|
| Offene Positionen? | **keine** | Das Fenster ist harmlos. Kein Broker-Stop nötig, kein FULL CLOSE, keine Pending-Orders. |
| Zustandsdateien? | **keine mitnehmen — echter Erststart** | Zulässig, kein Alarm (`:2445` *„genuine first start: create it, no alert"*). **Dafür ist `InpInitialBalance` im Preset ab jetzt der EINZIGE Träger der richtigen Basis.** |
| Panel-Sprache? | **Englisch** | `InpLang = LANG_EN` im Preset (`:170-171`). |
| Markt | **geschlossen** | Siehe den Kasten direkt darunter. |

### ⚠ Die Wochenend-Regel: einrichten heute, SCHARFSCHALTEN bei Marktöffnung

**Den EA erst anhängen und AutoTrading erst einschalten, wenn wieder Kurse ticken.**

Begründung aus dem Quelltext selbst (`:328-332`):

> *„After a restart in a tickless phase (weekend) `TimeCurrent()` returns the cache from the last
> tick — an offset built from it makes `SrvTime()` lag by the whole tick gap (up to ~2.5 days):
> expired locks re-activate themselves, SafeCloseAll closes at the Monday open."*

Der Schutz dagegen (`:345-352`) greift nur, wenn bereits ein Offset **gespeichert** ist. Bei
einem echten Erststart ist er das nicht: `:354` nimmt dann die Freitagszeit als Serverzeit an.
Der EA liefe das ganze Wochenende rund zwei Tage in der Vergangenheit — Tagesschlüssel,
nächste Server-Mitternacht und Schlussschwelle alle falsch gesetzt.

Es kostet dich **nichts**: bei geschlossenem Markt gibt es nichts zu schützen.

- **Heute:** Schritte 1–22 (alles bis einschließlich Kontoanmeldung und Historie)
- **Bei Marktöffnung:** Schritte 23–33 (EA anhängen, prüfen, scharfschalten, Cockpit)

### Und eine Eigenheit des Wochenendes

Die Woche beginnt laut `InpWeekStartDay = 0` am **Sonntag** (`:164`). Ein heute gesetztes
Wochenrisiko gilt für die **ablaufende** Woche. Nach dem Wochenwechsel musst du es **erneut**
setzen, sonst bleiben BUY/SELL grau und jede Eröffnung ist blockiert (`:3345-3347`).
Das ist der Schutz, der arbeitet — kein Fehler.

---

## Die goldene Regel

**Erster Befehl in jedem Fenster, bevor du irgendetwas anderes tippst:**

```powershell
whoami
```

Für alle MT4-Arbeiten muss dort **`MAMAL-VPS\trader`** stehen.

`trader` hat absichtlich kein RDP-Recht. Jede RDP-Verbindung ist also `admin` — eine **andere**
Sitzung mit einem **anderen** `%APPDATA%`. Startest du MetaTrader dort, landet die komplette
Einrichtung in `C:\Users\admin\...`, während die echten Terminals als `trader` laufen. Nichts
meldet einen Fehler. Du merkst es beim ersten Neustart, mit ungeschütztem Konto dazwischen.

**MT4-Oberfläche, Preset, Zustandsdateien, Autostart und der erste Cockpit-Start: alles in der
VNC-Konsole von `trader`.** Prüfbefehle aus der RDP-Sitzung nehmen den ausgeschriebenen Pfad
`C:\Users\trader\AppData\Roaming\...`, niemals `$env:APPDATA`.

---

## Phase 0 — drei Entscheidungen vorab

**E1 — Welche Zustandsdateien reisen mit?**

Die Regel aus 4.3 ist **nicht symmetrisch**:

| Variante | Urteil |
|---|---|
| **beide** (`gvariables.dat` + `MamalTrading_Lockstate.dat`) | **Empfohlen.** Tagesbasis, Wochenbasis, Verlustserie, Cooldown, Sperren und Wochenrisiko bleiben erhalten. |
| nur `Lockstate.dat` | zulässig und nützlich — Sperren, Cooldown und Basis kommen zurück |
| keine von beiden | zulässig, echter Erststart — **dann muss `InpInitialBalance` im Preset stehen** |
| nur `gvariables.dat` | **VERBOTEN.** `RG_LS_SEEN` ist auf deinem Konto gesetzt; das fehlende Lockstate gilt als Manipulation → garantierte Tagessperre (`:2431-2443`) |

**E2 — Hast du offene Positionen?**

Wenn ja: sie sind während des Fensters nur noch durch ihren **brokerseitigen Stop** geschützt.
**Setz vor Schritt 12 von Hand einen Stop beim Broker.** Und wenn der mitgebrachte Zustand eine
aktive Sperre enthält, schließt der EA sie wenige Sekunden nach Schritt 21 am Markt.

**E3 — Sprache des Panels.** Kommt aus dem EA-Eingabewert `InpLang` (`:170-171`, Vorgabe
Deutsch), **nicht** aus Windows. Auf dem englischen Server steht trotzdem `SCHUTZ AUS` / `AKTIV`,
solange du nichts änderst. Das ist richtig so — nur wissen musst du es.

---

## Phase A — `[PC]`, Schutz bleibt die ganze Zeit an

**1. `[PC]` Die laufende `.ex4` sichern.**
`ea\mt4\MamalTrading.ex4` kopieren nach `MamalTrading_2026-09-24.ex4`.
`*.ex4` ist ignoriert — F7 überschreibt sonst die einzige Kopie des Builds, der bei dir läuft.

**2. `[PC]` Neu übersetzen — die Datei im REPO.**
MetaEditor → `…\TradingGuard\ea\mt4\MamalTrading.mq4` → **F7** → **0 errors**.

- **Nicht** `MamalTrading.mq4.dblnl` oder `.mojibake` öffnen (gleicher Ordner, August, veraltet).
- **Nicht** die Kopie im `MQL4\Experts` deines laufenden Terminals übersetzen — MT4 lädt den EA
  dann auf allen Live-Charts sofort neu, mitten im Betrieb.

**3. `[PC]` Die zwei Presets erzeugen.** Je Terminal: EA-Eigenschaften → **Eingaben** →
**Speichern**. Vor dem Speichern mit eigenen Augen prüfen:

- `InpInitialBalance` = der echte Startsaldo des Kontos, **ohne Tausenderpunkt und ohne Komma**.
  Ein Wert unter 10 % des Saldos wird als Tippfehler verworfen (`:569-574`).
- `InpFundedMode = true`, `InpTestMode = false`
- `InpJournal = true` (`:101`) — sonst fehlen BootDiag, PROTECT_OFF und TAMPER ersatzlos
- `InpCockpit = true` (`:2945`) — sonst entsteht gar keine `mamal_cockpit.json`
- `InpMagic` auf allen Charts eines Terminals gleich

**Neutral benennen: `A` und `B`.** Keine Kontonummer im Dateinamen — der wandert ins Paket, auf
den Server und in jeden Snapshot.

**4. `[PC]` Das alte Preset im Terminal löschen oder umbenennen.** Im `MQL4\Presets` liegt eins
für ein älteres Konto. Einen Klick daneben im Lade-Dialog, und du fährst mit fremder Basis.
**Nie den Presets-Ordner als Ganzes kopieren** — nur die zwei neuen Dateien.

**5. `[PC]` Aufschreiben, auf Papier.** Im laufenden Terminal **F3** drücken und notieren:
`RG_INIT_BAL`, `RG_DAYSTART_EQ`, `RG_CONSEC`, `RG_LOCK_UNTIL`, `RG_WEEK_RISK`.
Das ist hinterher der einzige Weg zu sehen, ob der Umzug etwas gelockert hat.

**6. `[PC]` Equity-Reihen außerhalb des Projekts sichern.**
`cockpit\data\equity_*.csv` in einen Ordner **außerhalb von OneDrive und außerhalb des Repos**.
Das Cockpit kürzt jede Datei über 2 MB stündlich und unwiderruflich auf die letzten 20.000 Zeilen
(`cockpit/server.js:696-706`). Es gibt keine zweite Quelle.

**7. `[PC]` `cockpit\.env.local` NICHT mitnehmen.** Darin stehen die aktive Relais-Adresse und
der Ingest-Token. Mitkopiert schiebt der VPS ab der ersten Sekunde Live-Zustand und Journal nach
außen. Die Datei auf dem Server tippst du später neu, mit drei Zeilen.

**8. `[PC]` Den Ordner `Common\Files` NICHT mitnehmen.** Die Wegweiser darin bauen sich selbst
neu. Mitkopiert erscheinen alte Konten als Geisterkarten im Umschalter.

**9. `[PC]` Paket packen** — **kopieren, nie ausschneiden**: die frische `.ex4`, die zwei
`.set`-Dateien, je Datenordner `MamalTrading_Journal.csv` und `MamalTrading_Coverage.csv`, dazu
das Repo selbst.

> Liegt das Repo in OneDrive: vorher alle Dateien **lokal verfügbar** machen und hinterher die
> Byte-Größen vergleichen. Online-Platzhalter kopieren sich als 0 Byte.

**Die Zustandsdateien sind noch NICHT im Paket.** Die kommen in Schritt 14.

---

## Phase B — `[VPS]` vorbereiten. Noch kein Konto angemeldet, noch kein EA. Schutz läuft auf dem PC.

**10. `[VPS]` Repo nach `C:\TradingGuard`**, Rechte hast du schon gesetzt.

**11. `[VPS]` Virenscanner-Ausnahmen setzen für `C:\MT4`, beide `MQL4\Files`-Ordner und
`C:\TradingGuard\cockpit\data`.**
Eine Dateisperre auf `MamalTrading_Lockstate.dat` zählt nach drei Versuchen als **beschädigt** →
volle Tagessperre (`:2405-2412`, `:2446-2455`).

**12. `[VPS, als trader an der Konsole]` Beide Terminals je **einmal einzeln** starten** —
erst A, dann B, nicht gleichzeitig. In jedem: **Datei → Datenordner öffnen**, `origin.txt` lesen,
aufschreiben welcher Datenordner zu welcher Installation gehört.

```powershell
Get-ChildItem "C:\Users\trader\AppData\Roaming\MetaQuotes\Terminal" -Directory | ForEach-Object { $o=Join-Path $_.FullName 'origin.txt'; if(Test-Path $o){[PSCustomObject]@{Ordner=$_.Name;Herkunft=(Get-Content $o -Raw).Trim()}} } | Format-Table -AutoSize
```

**Genau zwei Zeilen mit zwei verschiedenen Herkünften.** Gleiche Herkunft heißt: der zweite
Installationslauf hat den ersten aktualisiert — dann zurück zu Abschnitt 3.1.

**13. `[VPS]` Je Datenordner einsetzen** (zweimal, in den Ordner, den *Datenordner öffnen* geöffnet hat):

```
MQL4\Experts\MamalTrading.ex4
MQL4\Presets\<die eine .set für GENAU dieses Konto>
MQL4\Files\MamalTrading_Journal.csv
MQL4\Files\MamalTrading_Coverage.csv
```

Danach im Navigator Rechtsklick → **Aktualisieren**. Eine `.ex4` in `C:\MT4\FTMO-A\MQL4\Experts`
erzeugt keinen Fehler und taucht nie im Navigator auf.

**14. `[VPS]` In BEIDEN Terminals: `Extras → Optionen → Expert Advisors`.**
Die drei Haken *„AutoTrading abschalten, wenn …"* ansehen. **„wenn das Konto gewechselt wurde"**
greift bei der Anmeldung in Schritt 16 und schaltet AutoTrading still wieder aus, nachdem du es
geprüft hast.

Im selben Dialog unter **Benachrichtigungen** die MetaQuotes-ID eintragen und **eine Testnachricht
senden** — auf einem frischen Server ist keine ID hinterlegt, und dann scheitert jede
Sperr- und PROTECT_OFF-Meldung lautlos (`:1005-1026`).

**15. `[VPS]` Cockpit-Passwort setzen — jetzt, vor jeder Anmeldung.**

In der Konsole von `trader`, im Cockpit-Ordner, in einem echten PowerShell-Fenster:

```powershell
node server.js --set-password
```

Mindestens 10 Zeichen. Dann beweisen, dass der Riegel sitzt:

```powershell
try { Invoke-WebRequest -Uri "http://127.0.0.1:8730/state" -UseBasicParsing | Out-Null; 'UNGESCHUETZT' } catch { $_.Exception.Response.StatusCode.value__ }
```

**Erwartet: `401`.** Das ist der Beweis, dass es funktioniert — kein Fehler.

> **Warum vor der Anmeldung:** Solange kein Passwort gesetzt ist, ist `/cmd/send` ohne jede
> Anmeldung erreichbar, und sein Befehlskatalog enthält `buy`, `sell`, `flat` und `closesym`
> (`server.js:345-354`, `:1193-1209`). Ein Cockpit ohne Passwort ist ein offenes Orderterminal.
>
> **Nicht `MAMAL_PASS_PLAIN` benutzen:** unter 10 Zeichen bleibt gar kein Passwort gesetzt, und
> solange die Variable existiert, schlägt sie jedes später gesetzte Passwort.

---

## Phase C — DAS FENSTER

**16. `[PC]` Den PC stilllegen — in dieser Reihenfolge.**
⚠ **Ab hier ist dein Konto ungeschützt.**

a) Falls geschlossen werden soll: **FULL CLOSE** im Panel drücken, **solange AutoTrading noch an
   ist**. Danach im Terminal-Fenster unter **Handel** die **Pending-Orders von Hand löschen** —
   FULL CLOSE rührt sie nicht an (`:1691`).
b) EA von jedem Chart entfernen
c) AutoTrading aus
d) Chart-Profil speichern
e) Node beenden
f) `MamalCockpit.vbs` aus dem Autostart-Ordner des PCs löschen — sonst startet dort bei jeder
   Anmeldung wieder ein Cockpit und schiebt weiter zum Relais

**17. `[PC]` Beide Terminals über `Datei → Beenden` schließen.** Nie abschießen: Chart-Profil und
Terminal-Konfiguration werden nur beim sauberen Beenden geschrieben.

**18. `[PC]` Erst JETZT die zwei Zustandsdateien kopieren**, je Datenordner:

```
<Datenordner>\profiles\gvariables.dat
<Datenordner>\MQL4\Files\MamalTrading_Lockstate.dat
```

**Kopieren, nie ausschneiden.** Jedes Paar **sofort mit `A` oder `B` beschriften** — die
Lockstate-Datei enthält **keine** Kontonummer; ein ins falsche Terminal gelegtes Paar wird
klaglos angenommen und gibt dem Konto fremde Basis und fremde Sperren.

> **Niemals `MamalTrading_Lockstate.dat` im Editor öffnen.** Eine geänderte Kodierung lässt die
> Prüfsumme scheitern → beschädigt → Tagessperre.

**19. `[VPS, trader]` Terminal A: Live-Konto anmelden.**
**„Kontoinformationen speichern"** anhaken. Dann unter `Extras → Optionen → Server` prüfen, dass
**„Persönliche Einstellungen und Daten beim Start behalten"** gesetzt ist — ohne das steht nach
jedem Neustart ein Anmeldefenster, und im Cockpit verschwindet das Konto dann **ganz** aus dem
Umschalter, statt als veraltet aufzufallen (`server.js:286-287`).

**Das Handelspasswort nehmen, nicht das Investorpasswort.** Ein Investor-Login besteht jede
Prüfung in diesem Blatt — und jedes Schließen scheitert.

**20. `[VPS]` Auf eine echte Verbindung und tickende Kurse warten, bevor irgendetwas weitergeht.**
Ohne Kurs übernimmt der EA beim ersten Start die falsche Zeitzone für Tageswechsel und
Schlussschwelle (`:354`, `:359-375`).

**21. `[VPS]` Kontohistorie → Rechtsklick → „Gesamte Historie"**, je Terminal.
Das speist vier Schutzfunktionen, und alle vier scheitern **locker** und **lautlos**. Muss
**vor** dem Anhängen des EA stehen — nachträgliches Erweitern rechnet nichts neu.

**22. `[VPS]` Terminal A über `Datei → Beenden` schließen, die zwei Zustandsdateien einsetzen,
Terminal wieder starten.** Ein laufendes Terminal hält seine GlobalVariables im Speicher und
überschreibt die eingesetzte Datei beim Beenden. Byte-Größen gegen die PC-Originale vergleichen.

**23. `[VPS]` EA auf EINEN Chart ziehen — AutoTrading noch AUS.**
Eingaben → **Laden** → die `.set` dieses Kontos → `InpInitialBalance` mit den Augen prüfen →
Reiter *Allgemein* → **„Live-Handel erlauben"** anhaken → OK.

Ein Chart genügt für den Schutz; die Durchsetzung ist kontoweit.

**24. `[VPS]` ⭐ DIE PRÜFUNG VOR DEM SCHARFSCHALTEN — AutoTrading noch AUS.**

```powershell
Get-Content "C:\Users\trader\AppData\Roaming\MetaQuotes\Terminal\<Ordner>\MQL4\Files\mamal_cockpit.json" -Raw | ConvertFrom-Json | Select-Object account,v,initBal,dayBase,dailyLimit,lockWhy,hardLock,protectOff,status
```

Vier Werte müssen stimmen:

| Feld | Sollwert |
|---|---|
| `account` | die richtige Kontonummer |
| `v` | `0.73` |
| `initBal` | der echte Startsaldo |
| `dayBase` | der Mitternachtsstand des Brokers, **nicht** der schon reduzierte Tagesstand |
| `lockWhy` / `hardLock` | `0` / `0` |

**Nicht nach der Statusanzeige urteilen** — solange AutoTrading aus ist, überdeckt sie jede
darunterliegende Sperre. Urteile nach `lockWhy` und `hardLock`.

> **Stimmt `initBal` nicht: STOPP. AutoTrading nicht einschalten.**
> Die Basis wird in dem Moment festgeschrieben, in dem der EA sie bestätigt (`:607-609`), und
> danach nur noch nach unten verweigert bis zum nächsten Server-Tageswechsel (`:581-586`).
> Für eine R4b-Hartsperre gibt es **keinen** Lösemechanismus. Das hier ist der letzte
> umkehrbare Moment des gesamten Umzugs.

**25. `[VPS]` AutoTrading einschalten. ✅ Der Schutz greift 1–3 Sekunden später.**
Sofort prüfen: Die Anzeige darf **nicht** `SCHUTZ AUS` zeigen, und es darf keine Tagessperre
erschienen sein.

**26. `[VPS]` Wochenrisiko ins Panel tippen und `SETZEN` drücken.**
Ohne gültiges Wochenrisiko blockiert der EA **jede** Eröffnung und BUY/SELL bleiben grau
(`:3345-3347`). Das ist der Schutz, der arbeitet — kein Fehler.

**27. `[VPS]` Restliche Charts ergänzen**, gleiches `InpMagic`, Preset auf jedem geladen,
„Live-Handel erlauben" auf jedem — **dann das Chart-Profil speichern.**
MT4 stellt den EA beim nächsten Start mit den Werten aus dem **Chart** wieder her, nicht aus der
`.set`. Ohne Profilspeicherung kommt er nach einem Neustart mit `InpInitialBalance = 0` zurück.

**28. `[VPS]` Schritte 19–27 für Terminal B wiederholen.**

---

## Phase D — Cockpit

**29. `[VPS, trader]` Erster Start sichtbar, in einem offenen Fenster:**

```powershell
node server.js
```

Die Startmeldung lesen: Adresse, Anmeldezustand, **`Ordner (n):`** und **`Konten:`**.
Eine fehlende `Konten:`-Zeile **ist** der Befund. `MamalCockpit.vbs` schluckt später jeden Fehler
und startet Node unsichtbar (`:29`, `:52`) — das hier ist deine einzige Gelegenheit zu sehen,
dass die Erkennung funktioniert hat.

**30. `[VPS]` Der Umschalter muss genau zwei Karten zeigen**, zwei verschiedene Kontonummern,
beide live.

**31. `[VPS]` Wegweiser zählen:**

```powershell
Get-ChildItem "C:\Users\trader\AppData\Roaming\MetaQuotes\Terminal\Common\Files\mamal_files_*.txt"
```

**Genau zwei Dateien**, mit **verschiedenen** Pfaden darin. Stehen beide auf denselben Pfad,
teilen sich die Terminals einen Datenordner — dann sofort stoppen.

**32. `[VPS]` Lockstate in beiden Datenordnern vorhanden:**

```powershell
Get-ChildItem "C:\Users\trader\AppData\Roaming\MetaQuotes\Terminal\*\MQL4\Files\MamalTrading_Lockstate.dat"
```

Zwei Dateien. Fehlt eine, ist der Ordner für `trader` nicht beschreibbar — heute beschwert sich
nichts, und beim ersten Bedarf sperrt das Konto einen ganzen Handelstag.

**33. `[VPS]` Autostart-Verknüpfung** auf `C:\TradingGuard\cockpit\MamalCockpit.vbs` in
`C:\Users\trader\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`.

---

## Phase E — Abnahme

**34. Der Neustart-Test — am nächsten Handelsschluss, flach, nicht heute Nacht.**

Beide Profile speichern, Uhrzeit notieren, dann:

```powershell
shutdown /r /t 60
```

Kein `/f`. Zehn Minuten **nicht** verbinden, vom Handy zusehen. Danach Schritte 30, 31 und 24
erneut, und den Neustart beweisen:

```powershell
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
```

Muss nach der notierten Zeit liegen — ohne `/f` kann MetaTrader das Herunterfahren blockieren,
und der Test bestünde dann, ohne stattgefunden zu haben.

**35. Erste Stunde / erster Tag / erste Woche.**
Stunde: beide Konten im Cockpit frisch, `SchutzAus=False`, `initBal` unverändert, beide
Equity-Dateien wachsen. Nach dem ersten Server-Tageswechsel: `dayBase` und `dailyLimit` neu lesen.
Wöchentlich: beide Journale nach `FINAL-FAIL`, `TAMPER` und `PROTECT_OFF` durchsuchen.

---

## Verbotsliste

- **`gvariables.dat` ohne `Lockstate.dat` mitnehmen** → garantierte Tagessperre
- **`MamalTrading_Lockstate.dat` im Editor öffnen** → beschädigt → Tagessperre
- **Zustandsdateien ausschneiden statt kopieren** → kein Rückweg auf den PC
- **MT4 als `admin` einrichten** → alles landet in der falschen Sitzung
- **Cockpit ohne Passwort erreichbar lassen** → offenes Orderterminal
- **`MAMAL_PASS_PLAIN` als Abkürzung** → unter 10 Zeichen gar kein Passwort
- **`cockpit\.env.local` vom PC mitkopieren** → der VPS schiebt sofort Live-Daten nach außen
- **`MAMAL_BIND` setzen, um ans Handy zu kommen** → das Cockpit startet dann gar nicht
- **`closesym` als Funktionstest auf einem Symbol mit offener Position** → schließt am Markt
- **„Abmelden" statt „Trennen"** → beendet beide Terminals und das Cockpit
- **Auf einen Snapshot von vor dem 14.09.2026 zurückrollen** → zurück in die RDP-Aussperrung

---

## Rückweg

Klemmt es vor Schritt 16: nichts passiert, der PC schützt weiter.

Klemmt es zwischen 16 und 25: **zurück auf den PC.** Erst auf dem VPS sicherstellen, dass
AutoTrading aus und der EA von allen Charts entfernt ist, **dann** auf dem PC die Terminals
starten, Profil laden, EA anhängen, AutoTrading an. Die Zustandsdateien liegen dort noch, weil
du kopiert und nicht ausgeschnitten hast.

**Nie beide Maschinen gleichzeitig scharf.** MT4 erlaubt denselben Login zweimal, und
TradingGuard hat **keine** maschinenübergreifende Sperre — beide würden eigenständig wachen und
dieselbe Position schließen wollen.

Der Snapshot vom 16.11. ist **kein** Rückweg für einen misslungenen Kontoumzug: er setzt die
ganze Platte auf den Stand vor MT4 zurück und löscht neuere Snapshots mit.
