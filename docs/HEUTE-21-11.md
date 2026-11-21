# Heute, Samstag 21.11.2026 — Klick für Klick

> **Dieses Blatt arbeitest du heute ab.** [UMZUG-HEUTE.md](UMZUG-HEUTE.md) ist das Nachschlagewerk
> mit den Begründungen — hier stehen nur die Handgriffe, in der Reihenfolge, in der du sie machst.
>
> **Heute endet nach Teil 5.** Der EA wird heute **nicht** angehängt und **nicht** scharfgeschaltet.

## Zwei Tasten, die gleich heißen und Verschiedenes tun

| Taste | Wo | Was sie tut |
|---|---|---|
| **F7** | im **MetaEditor** | übersetzt den Quelltext |
| **F7** | im **Terminal** auf dem Chart | öffnet die **Eigenschaften** des angehängten EA |
| **F3** | im **Terminal** | zeigt die Liste der GlobalVariables |

Ich schreibe jedes Mal dazu, welches gemeint ist.

---

# TEIL 1 — auf deinem PC

**Der Schutz läuft die ganze Zeit weiter.** Du änderst in Teil 1 nichts am laufenden Betrieb.

## 1.1 Die laufende `.ex4` sichern

1. Explorer öffnen, in den Ordner `…\TradingGuard-v0.33\TradingGuard\ea\mt4\`
2. Rechtsklick auf **`MamalTrading.ex4`** → **Kopieren**
3. Rechtsklick auf freie Fläche im selben Ordner → **Einfügen**
4. Die neue Datei umbenennen in **`MamalTrading_2026-09-24.ex4`**

**Warum:** Gleich überschreibt F7 die `.ex4`. Sie steht in `.gitignore`, es gibt also keine zweite
Kopie — ohne diesen Schritt ist der Build, der bei dir seit September läuft, weg.

✅ **Geschafft, wenn:** zwei `.ex4`-Dateien im Ordner liegen.

---

## 1.2 Die echten Zahlen ablesen — in **jedem** Terminal

Das ist der wichtigste Schritt in Teil 1. Ohne ihn hat der EA auf dem Server keine richtige Basis.

1. Ins **erste** Terminal klicken
2. **F3** drücken (Terminal, nicht MetaEditor) → Fenster **„Globale Variablen"**
3. Diese Zeilen suchen und **auf Papier** schreiben:

```
RG_INIT_BAL      = ______________     <- die wichtigste
RG_DAYSTART_EQ   = ______________
RG_CONSEC        = ______________
RG_LOCK_UNTIL    = ______________
RG_WEEK_RISK     = ______________
```

4. Fenster schließen, ins **zweite** Terminal klicken, **dasselbe** noch einmal auf ein zweites Blatt

**Schreib auf jedes Blatt, zu welchem Terminal es gehört** (`A` oder `B`).

**Warum:** `RG_INIT_BAL` ist der Startsaldo, mit dem dein EA heute rechnet. Genau diese Zahl muss
gleich ins Preset. Und wenn nach dem Umzug etwas lockerer eingestellt ist als vorher, sind diese
Zettel der einzige Weg, das zu sehen.

✅ **Geschafft, wenn:** zwei beschriftete Zettel mit je fünf Zahlen.

---

## 1.3 Das Preset speichern — in **jedem** Terminal

1. Auf dem Chart mit dem EA: **F7** drücken (Terminal!) → der Eigenschaften-Dialog geht auf
2. Reiter **Eingaben** (englisch: *Inputs*)
3. In der Liste diese fünf Zeilen suchen und den **Wert** prüfen bzw. ändern (Doppelklick in die
   Wertspalte macht sie editierbar):

| Eingabe | Wert | Prüfen |
|---|---|---|
| `InpInitialBalance` | die Zahl von deinem Zettel (`RG_INIT_BAL`) | **ohne Tausenderpunkt, ohne Komma.** `10000`, nicht `10.000` |
| `InpLang` | **`LANG_EN`** | aus der Auswahlliste |
| `InpFundedMode` | `true` | |
| `InpJournal` | `true` | |
| `InpCockpit` | `true` | |

4. Knopf **Speichern** unten im Dialog drücken
5. Dateiname: **`A`** (beim zweiten Terminal: **`B`**) → speichern
6. **Dann `Abbrechen` drücken, nicht `OK`.**

> **Warum `Abbrechen`:** `Speichern` schreibt die Preset-Datei sofort. `OK` würde den EA auf dem
> Chart neu starten — unnötig, solange alles läuft. `Abbrechen` schließt den Dialog, ohne den
> laufenden EA anzufassen. Die Preset-Datei ist trotzdem geschrieben.

> **Warum keine Kontonummer im Dateinamen:** Der Name wandert ins Paket, auf den Server und in
> jeden Snapshot.

**Achtung bei `InpInitialBalance`:** Ein Wert unter 10 % des Kontostands wird als Tippfehler
verworfen (`:569-574`) — ein Tausenderpunkt macht aus `10.000` schnell `10`. Dann steht die Sperre
völlig falsch.

✅ **Geschafft, wenn:** in **beiden** Datenordnern unter `MQL4\Presets` je eine neue Datei liegt
(`A.set` und `B.set`). Den Ordner findest du über **Datei → Datenordner öffnen**.

---

## 1.4 Den EA neu übersetzen

1. **MetaEditor** öffnen (im Terminal: **Extras → MetaQuotes Language Editor**, oder F4)
2. **Datei → Öffnen**, und zwar **genau diese Datei**:

```
…\TradingGuard-v0.33\TradingGuard\ea\mt4\MamalTrading.mq4
```

3. **F7** drücken (MetaEditor!)
4. Unten im Reiter **Fehler** muss stehen: **`0 errors, 0 warnings`** (Warnungen sind erlaubt,
   Fehler nicht)

> **Nicht öffnen:** `MamalTrading.mq4.dblnl` und `MamalTrading.mq4.mojibake` im selben Ordner.
> Die sind vom August und veraltet.
>
> **Und nicht** die Kopie aus dem `MQL4\Experts` deines laufenden Terminals übersetzen — MT4 lädt
> den EA dann auf allen Live-Charts sofort neu, mitten im Betrieb.

✅ **Geschafft, wenn:** `0 errors`, und `MamalTrading.ex4` im Ordner `ea\mt4\` trägt das heutige
Datum.

---

## 1.5 Die Equity-Reihen in Sicherheit bringen

1. Einen Ordner anlegen, der **nicht** in OneDrive und **nicht** im Repo liegt, z. B.
   `C:\TradingGuard-Archiv\`
2. Alle Dateien `equity_*.csv` aus `…\TradingGuard\cockpit\data\` dorthin **kopieren**

**Warum:** Das Cockpit kürzt jede dieser Dateien, sobald sie über 2 MB wächst, stündlich und
unwiderruflich auf die letzten 20.000 Zeilen. Es gibt keine zweite Quelle für diese Kurve.

✅ **Geschafft, wenn:** die Kopien außerhalb des Projekts liegen.

---

## 1.6 Das Paket packen

Einen Ordner `C:\Umzug\` anlegen und **hineinkopieren** (nie ausschneiden):

```
MamalTrading.ex4            <- die frische aus 1.4
A.set                       <- aus dem Datenordner von Terminal A
B.set                       <- aus dem Datenordner von Terminal B
TradingGuard\               <- der ganze Projektordner
```

**Diese Dinge kommen ausdrücklich NICHT mit:**

| Nicht mitnehmen | Grund |
|---|---|
| `gvariables.dat` | du startest frisch |
| `MamalTrading_Lockstate.dat` | dito |
| `cockpit\.env.local` | enthält Relais-Adresse und Token — der Server würde ab Sekunde eins Live-Daten nach außen schieben |
| der Ordner `Common\Files` | alte Konten erscheinen sonst als Geisterkarten im Umschalter |

> **Liegt dein Projekt in OneDrive?** Dann vorher alle Dateien auf **„Immer auf diesem Gerät
> behalten"** stellen und nach dem Kopieren die Byte-Größen vergleichen. Online-Platzhalter
> kopieren sich als 0 Byte, ohne Fehlermeldung.

✅ **Geschafft, wenn:** `C:\Umzug\` die drei Dateien und den Projektordner enthält.

---

# TEIL 2 — auf den Server bringen

## 2.1 RDP einmal mit Laufwerk

1. `Windows` + `R` → `mstsc` → Enter
2. **Optionen einblenden** anklicken
3. Reiter **Lokale Ressourcen** → unten **Weitere…**
4. Haken bei **Laufwerke** (oder nur bei `C:`) setzen → **OK**
5. Computer: `178.18.249.131` → **Verbinden**, anmelden als **`admin`**

✅ **Geschafft, wenn:** im Explorer des Servers unter *Dieser PC* dein PC-Laufwerk auftaucht.

## 2.2 Kopieren

Im Explorer des Servers: `C:\Umzug\` von deinem Laufwerk nach **`C:\TradingGuard\`** kopieren.

Danach **die Verbindung trennen, den Laufwerks-Haken aus 2.1 wieder entfernen** und neu verbinden.

## 2.3 Virenscanner-Ausnahmen

Auf dem Server, **Windows-Sicherheit** → **Viren- & Bedrohungsschutz** → *Einstellungen verwalten*
→ ganz unten **Ausschlüsse** → *Ausschlüsse hinzufügen oder entfernen* → **Ordner** hinzufügen:

```
C:\MT4
C:\TradingGuard
C:\Users\trader\AppData\Roaming\MetaQuotes
```

**Warum:** Wenn der Scanner die Datei `MamalTrading_Lockstate.dat` auch nur kurz sperrt, zählt sie
nach drei Versuchen als **beschädigt** — und das sperrt dir einen ganzen Handelstag.

---

# TEIL 3 — in der Sitzung von `trader`

## 3.1 Über VNC hinein

1. Contabo-Kundenbereich → deine Instanz → **VNC Information**
2. Mit dem TightVNC-Viewer verbinden
3. Du landest **direkt auf dem Desktop von `trader`** — kein Anmeldebildschirm

> **Zum Schluss das VNC-Fenster einfach zuklappen. Niemals „Sign out" / „Abmelden".**

## 3.2 Die Kontrollfrage

Auf dem Desktop von `trader`: Start → `powershell` → Enter, dann:

```powershell
whoami
```

**Es muss `mamal-vps\trader` dastehen.** Steht dort `admin`, bist du im falschen Fenster — dann
bist du über RDP drin, nicht über VNC. **Alles Weitere in Teil 3 muss in diesem Fenster
passieren**, sonst richtest du den Server für einen Benutzer ein, der ihn nie benutzt.

## 3.3 Beide Terminals je **einmal einzeln** starten

1. `C:\MT4\FTMO-A\terminal.exe` doppelklicken, warten bis es offen ist
2. **File → Open Data Folder** (deutsch: *Datei → Datenordner öffnen*) → ein Explorer-Fenster geht auf
3. Dort die Datei **`origin.txt`** öffnen und notieren: *dieser Datenordner gehört zu FTMO-**A***
4. Terminal **schließen** über **File → Exit**
5. Dasselbe mit `C:\MT4\FTMO-B\terminal.exe`

> **Nicht beide gleichzeitig beim ersten Mal.** Sonst weißt du nicht, welcher Ordner zu welchem
> gehört.

**Dann zur Kontrolle, im PowerShell-Fenster von `trader`:**

```powershell
Get-ChildItem "C:\Users\trader\AppData\Roaming\MetaQuotes\Terminal" -Directory | ForEach-Object { $o=Join-Path $_.FullName 'origin.txt'; if(Test-Path $o){[PSCustomObject]@{Ordner=$_.Name;Herkunft=(Get-Content $o -Raw).Trim()}} } | Format-Table -AutoSize
```

✅ **Geschafft, wenn:** **genau zwei Zeilen** mit **zwei verschiedenen** Herkunftspfaden
(einer endet auf `FTMO-A`, einer auf `FTMO-B`).

❌ **Stehen beide auf denselben Pfad**, hat der zweite Installationslauf den ersten überschrieben.
Dann hier aufhören und mir Bescheid sagen.

## 3.4 Die Dateien einsetzen — je Datenordner

Für **jeden** der zwei Datenordner aus 3.3:

```
MQL4\Experts\MamalTrading.ex4     <- aus C:\TradingGuard\
MQL4\Presets\A.set                <- NUR die Datei dieses Kontos!
```

Im Ordner von FTMO-A also `A.set`, im Ordner von FTMO-B **nur** `B.set`.

> Eine `.ex4`, die du nach `C:\MT4\FTMO-A\MQL4\Experts` legst, erzeugt **keinen Fehler** und taucht
> **nie** im Navigator auf. Es muss der Ordner sein, den *Open Data Folder* geöffnet hat.

Danach im Terminal: Navigator öffnen (`Strg`+`N`), Rechtsklick auf *Expert Advisors* → **Refresh**
(*Aktualisieren*). `MamalTrading` muss in der Liste stehen.

## 3.5 Zwei Einstellungen in **beiden** Terminals

**Tools → Options** (`Strg`+`O`), deutsch: *Extras → Optionen*

**Reiter `Expert Advisors`:** Die drei Haken *„Disable Auto Trading when …"* ansehen und
aufschreiben, wie sie stehen. Besonders **„… when the account has been changed"** — der greift
gleich bei der Anmeldung in Teil 5 und schaltet AutoTrading still wieder aus.

**Reiter `Notifications`:** Deine **MetaQuotes-ID** eintragen, Haken bei *Enable Push
Notifications*, dann **Test** drücken. Auf deinem Handy muss eine Nachricht ankommen.

> **Warum:** Auf einem frischen Server ist keine ID hinterlegt. Ohne sie scheitert **jede**
> Sperr- und Schutz-aus-Meldung lautlos — auf einer Maschine, bei der du absichtlich nicht
> daneben sitzt.

**Optional:** Wenn dir die englischen Menüs im Weg sind — **View → Languages → German**, dann
Terminal neu starten. Das ändert nur die Oberfläche, sonst nichts.

## 3.6 Cockpit-Passwort setzen

Im PowerShell-Fenster von `trader`:

```powershell
cd C:\TradingGuard\cockpit
```

```powershell
node server.js --set-password
```

Passwort eingeben, **mindestens 10 Zeichen**. Dann beweisen, dass der Riegel sitzt:

```powershell
try { Invoke-WebRequest -Uri "http://127.0.0.1:8730/state" -UseBasicParsing | Out-Null; 'UNGESCHUETZT' } catch { $_.Exception.Response.StatusCode.value__ }
```

✅ **Geschafft, wenn dort `401` steht.** Das ist der **Erfolg**, kein Fehler — es heißt: ohne
Anmeldung kommt niemand an die Daten.

❌ Steht dort `UNGESCHUETZT`, ist kein Passwort gesetzt. Dann nicht weitermachen.

> **Warum jetzt und nicht später:** Ohne Passwort ist der Befehlskanal des Cockpits **ohne jede
> Anmeldung** erreichbar, und er kennt `buy`, `sell`, `flat` und `closesym`. Ein Cockpit ohne
> Passwort ist ein offenes Orderterminal.

---

# TEIL 4 — den PC stilllegen

**Erst jetzt.** Ab hier wacht auf dem PC nichts mehr — aber der Markt ist zu und du bist flach,
also ist das heute folgenlos.

In **jedem** der beiden PC-Terminals, in dieser Reihenfolge:

1. **AutoTrading** ausschalten (der Knopf in der Werkzeugleiste)
2. Auf **jedem** Chart: Rechtsklick auf die Chartfläche → im Kontextmenü den Eintrag
   **Expert Advisors** / *Experten* → **Entfernen** (*Remove*). Das Panel verschwindet dann vom
   Chart — daran siehst du, dass es geklappt hat. Chart für Chart, bis auf keinem mehr ein Panel
   ist.
3. **Datei → Profile → Speichern unter** (damit die Chartanordnung erhalten bleibt)
4. **Datei → Beenden** — **nicht** über das rote X, nicht über den Task-Manager

Dann noch auf dem PC:

5. Das laufende **Node**-Fenster schließen (das Cockpit)
6. `Windows` + `R` → `shell:startup` → Enter. Die Datei **`MamalCockpit.vbs`** oder die
   Verknüpfung darauf **löschen**

> **Warum Punkt 6:** Sonst startet bei jeder Anmeldung auf deinem PC wieder ein Cockpit und schiebt
> weiter Daten zum Relais — parallel zum Server.

✅ **Geschafft, wenn:** beide Terminals zu, kein Node-Fenster mehr offen, Autostart-Ordner leer.

---

# TEIL 5 — Konten auf dem Server anmelden

**Wieder in der VNC-Sitzung von `trader`.** Der EA wird dabei **nicht** angehängt.

Für **jedes** Terminal:

1. Terminal starten (`C:\MT4\FTMO-A\terminal.exe`)
2. **File → Login to Trade Account** (*Datei → Am Handelskonto anmelden*)
3. Kontonummer, **Handelspasswort** (nicht das Investorpasswort!), Server auswählen
4. Haken bei **Save account information** (*Kontoinformationen speichern*) → **Login**
5. Warten, bis unten rechts eine Verbindung angezeigt wird und die Kontonummer in der Titelzeile steht
6. **Tools → Options → Server**: Haken bei **Keep personal settings and data at startup** prüfen
7. Im Fenster **Terminal** (`Strg`+`T`) den Reiter **Account History** öffnen → **Rechtsklick** →
   **All History** (*Gesamte Historie*)

> **Punkt 6 ist nicht optional:** Ohne ihn steht nach jedem Neustart ein Anmeldefenster — und im
> Cockpit verschwindet das Konto dann **ganz** aus dem Umschalter, statt als veraltet aufzufallen.
>
> **Punkt 7 muss vor dem EA passieren.** Aus dieser Historie liest der EA die Einzahlung und
> damit seine Basis. Nachträgliches Erweitern rechnet **nichts** neu.
>
> **Investorpasswort:** Mit ihm besteht alles jede Prüfung — und jedes Schließen scheitert.

✅ **Geschafft, wenn:** beide Terminals angemeldet, beide mit „All History", Kurse stehen (am
Wochenende bewegen sie sich nicht — das ist richtig).

---

# Schluss für heute

**Den EA heute nicht anhängen und AutoTrading nicht einschalten.** Beides passiert bei
Marktöffnung, mit tickenden Kursen — der Grund steht im Kasten oben in
[UMZUG-HEUTE.md](UMZUG-HEUTE.md).

**Beide Terminals kannst du laufen lassen.** Sie sind angemeldet, aber ohne EA passiert nichts.

## Was du mir meldest

1. Die zwei Zeilen aus der Prüfung in **3.3** (die zwei Datenordner mit ihrer Herkunft)
2. Ob in **3.6** die **`401`** kam
3. Wie die drei Haken in **3.5** standen, besonders *„when the account has been changed"*
4. Ob die Testnachricht aufs Handy angekommen ist
5. Ob beide Konten angemeldet sind

Dann gebe ich dir den letzten Teil für die Marktöffnung — das sind zehn Minuten.
