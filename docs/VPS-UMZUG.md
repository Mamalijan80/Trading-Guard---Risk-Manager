# Umzug auf den VPS — Schritt für Schritt

**Stand: 14.11.2026.** Für den bestellten Contabo Cloud VPS 4 (4 vCPU, 8 GB, 100 GB, Windows
Server, Region EU, monatlich kündbar — 16,07 €/Monat). Ziel: **zwei** FTMO-Challenges, also
**zwei** getrennte MetaTrader-Installationen plus ein Cockpit, im Dauerbetrieb 24/5.

Jeder Handgriff hier ist belegt — aus dem Quelltext dieses Projekts oder aus einer genannten
Quelle. Wo etwas unsicher ist, steht das dabei.

---

## 0. Was der VPS kauft — und was nicht

**Er kauft Verlässlichkeit und Laufzeit.** Dein PC muss nicht mehr durchlaufen, kein
Windows-Update reißt dir mitten am Handelstag den Wächter weg, kein versehentliches Zuklappen
des Notebooks.

**Er kauft keine Unumgehbarkeit.** Das steht ausführlich in [VPS-NO-OVERRIDE-PLAN.md]
(VPS-NO-OVERRIDE-PLAN.md): FTMO verlangt, dass **nur du** Zugang zum Konto hast. Wer alleinigen
Zugang hat, kann AutoTrading auch auf dem VPS wieder ausschalten. Ein echter „No-Override"
bräuchte einen Dritten mit Admin-Rechten — und genau den verbietet FTMO.

Wer sich auf „jetzt kann ich nicht mehr" verlässt, verlässt sich an der teuersten Stelle auf
etwas Falsches. Der VPS macht es **unbequemer**, nicht unmöglich. Das ist viel wert, aber es ist
etwas anderes.

---

## 1. Erster Zugang und Grundhärtung

### 1.1 Zugangsdaten sammeln — und das Passwort sofort sichern
Nach der Freischaltung kommt die Mail „Ihre Login Daten". IP und Benutzername (`Administrator`)
stehen auch im Kundenbereich. Alles in den Passwortmanager, **dann die Mail löschen**.

> **Der Grund, warum das hier wichtiger ist als sonst:** Contabo kann ein
> Windows-Administrator-Passwort **nicht** per Knopfdruck zurücksetzen. Verlierst du es, bleibt
> Rettungssystem oder Neuinstallation. Es ist dein einziger Schlüssel.

Panel-Zugang und Server-Zugang sind **zwei verschiedene Konten** — nicht verwechseln.

### 1.2 Die VNC-Konsole EINMAL ausprobieren, bevor du irgendetwas änderst
Im Kundenbereich den VPS öffnen, VNC-/KVM-Konsole starten, den Windows-Anmeldeschirm sehen,
wieder schließen. Nicht anmelden, nichts tun.

**Warum zuerst:** VNC ist dein einziger Weg zurück, wenn eine Firewall-Regel dich aus RDP
aussperrt. Einen Rettungsweg probiert man aus, *bevor* man ihn braucht.

### 1.3 Erste RDP-Verbindung
`mstsc` auf deinem Laptop. Vor dem Verbinden unter **Optionen → Lokale Ressourcen → Weitere**
**keine lokalen Laufwerke** einbinden. (Für den Dateitransfer in Schritt 4 machst du das einmal
bewusst und danach wieder aus.)

### 1.4 Administrator-Passwort ändern — in dieser Reihenfolge
1. Im Passwortmanager einen neuen Eintrag anlegen, 25+ Zeichen generieren, **speichern**.
2. *Dann* in der RDP-Sitzung `Strg+Alt+Ende` → Kennwort ändern.

Umgekehrt als gewohnt, aus dem Grund in 1.1.

### 1.5 Zeitzone und Name
```powershell
tzutil /s "W. Europe Standard Time"
Rename-Computer -NewName MAMAL-VPS -Restart
```

**Die Zeitzone ist hier nicht Kosmetik.** `cockpit/server.js` liest die MT4-Journalzeit mit
`Date.parse(...)` ohne Zeitzonen-Angabe, also als *lokale* Zeit — die Zeit kommt aber vom
Broker-Server. Die 6-Stunden-Schwelle in der Trade-Akte verschiebt sich damit um den Versatz.
Das betrifft nur einen Erklärsatz, keine Regel — aber wenn VPS und PC verschiedene Zeitzonen
haben, liest dieselbe Akte auf beiden Maschinen anders. Gleiche Zeitzone, gleiche Anzeige.

### 1.6 Windows-Updates ZUERST, Software danach
Updates vollständig durchziehen, **bevor** MT4 und Node installiert werden. So passieren die
Neustarts, solange noch nichts läuft, was dabei ausfällt.

> **Konkret für diese Maschine (Stand 15.11.2026):** Contabo liefert Windows Server 2025 als
> **Build 26100.1742** aus — das ist die Erstausgabe vom **1. November 2024**. Aktuelle Stände
> liegen bei 26100.3xxxx. Es fehlt also **rund ein Jahr** an Updates. Das sind nicht zwei bis
> drei Runden, sondern eher vier bis sechs, mit Neustarts dazwischen, und es dauert.
>
> Nach jeder Runde erneut „Nach Updates suchen" — Windows zeigt erst nach einem Neustart, was als
> Nächstes fällig ist. Fertig bist du, wenn zweimal hintereinander nichts mehr kommt.
> `winver` zeigt danach eine deutlich höhere Build-Nummer als 1742.

### 1.7 RDP absichern — was wirkt und was nicht
**Wirkt:**
- Contabo-Cloud-Firewall davor (eingehend alles verwerfen außer RDP von deiner IP) — kostenlos
- Langes Passwort
- Kontosperre nach Fehlversuchen:
  ```powershell
  net accounts            # erst ansehen
  net accounts /lockoutthreshold:10 /lockoutduration:15 /lockoutwindow:15
  ```

**Wirkt nicht:** Den RDP-Port von 3389 wegzulegen. Angreifer finden RDP über Portscans auf
beliebigen Ports; die ersten Anmeldeversuche kommen typischerweise innerhalb von Minuten nach dem
Öffnen. Das ist Aufwand ohne Gegenwert.

### 1.8 Windows Defender
Kann bleiben. **Erst ohne Ausnahmen anfangen und messen.** Wenn der Verzeichnis-Scan des Cockpits
spürbar langsam wird, höchstens die `MQL4\Files`-Ordner und `cockpit\data` ausnehmen — **nicht**
`terminal.exe` und nicht die Installationsverzeichnisse.

---

## 2. Dauerbetrieb — der Teil, an dem so ein Aufbau still ausfällt

**Das Problem in einem Satz:** Nach einem Neustart ist niemand angemeldet. Dann startet
MetaTrader nicht, das Cockpit nicht, und der Schutz ist weg — ohne dass es dir jemand sagt.

### 2.1 Eigenen Benutzer für den Betrieb
```powershell
net user trader <langes-eigenes-Passwort> /add
net localgroup "Remote Desktop Users" trader /add
```
**Nicht** in die Administratorengruppe. MT4 und Node brauchen zum *Laufen* keine Adminrechte.

### 2.2 Automatische Anmeldung — mit Sysinternals, nicht per Registry
[Autologon](https://download.sysinternals.com/files/AutoLogon.zip) herunterladen, als
Administrator starten, Benutzer `trader`, Domain = Computername, Passwort, **Enable**.

> **Warum nicht von Hand in der Registry:** Dort landet das Passwort als **Klartext**, lesbar
> auch für die Gruppe „Authentifizierte Benutzer". Autologon legt es verschlüsselt ab.
>
> **Und warum ein eigener Benutzer statt Administrator:** Das hinterlegte Geheimnis ist dann
> nicht das Admin-Passwort der Maschine. Wer es ausliest, hat MT4 — nicht alles.

**Falle:** Meldest du dich später per VNC-Konsole als *Administrator* an, überschreibt Windows
den hinterlegten Benutzernamen. Beim nächsten Neustart passt die Kombination nicht mehr und die
automatische Anmeldung bleibt aus.

### 2.3 MT4 so einstellen, dass es ohne Dialog wieder am Konto hängt
In **jedem** Terminal als `trader`: Datei → Am Handelskonto anmelden, **„Kontoinformationen
speichern"** anhaken. Terminal über **Datei → Beenden** schließen, nie abschießen.

### 2.4 Beide Terminals über den Aufgabenplaner starten
`taskschd.msc` → **Aufgabe erstellen** (nicht „Einfache Aufgabe"), je Terminal eine:

- **Allgemein:** Benutzer `trader`; **„Nur ausführen, wenn der Benutzer angemeldet ist"**
- **Trigger:** Bei Anmeldung, Verzögerung 1 bzw. 3 Minuten (versetzt!)
- **Aktion:** `C:\MT4\FTMO-A\terminal.exe` bzw. `...\FTMO-B\terminal.exe`
- **Einstellungen:** Haken bei **„Aufgabe beenden, falls länger ausgeführt als: 3 Tage"
  ENTFERNEN**

> **Warum „nur wenn angemeldet":** Die Option „Unabhängig von der Benutzeranmeldung" lässt die
> Aufgabe in der nicht-interaktiven Sitzung 0 laufen. `terminal.exe` startet dort ohne Fenster
> und ohne Desktop — du siehst es nie und kannst nichts bedienen.
>
> **Warum der 3-Tage-Haken weg muss:** Er ist voreingestellt. Startet MT4 Sonntagabend, beendet
> Windows es Mittwochabend — mitten in der Handelswoche, ohne Grund und ohne Meldung.

**Versetzt starten:** Beide Terminals gleichzeitig und sehr früh nach dem Hochfahren zu starten
ist ein bekanntes Problem — Terminals starten und schließen sich teils wieder, ohne Fehler.

### 2.5 Cockpit in derselben Sitzung
Eine **Verknüpfung** auf `cockpit\MamalCockpit.vbs` in `shell:startup` des Benutzers `trader`.
Die Datei liegt im Repo und findet `server.js` neben sich — kein Pfad einzutragen.

> **Nicht als Windows-Dienst unter LocalSystem.** `server.js` sucht die Wegweiser in
> `%APPDATA%\MetaQuotes\Terminal\Common\Files`. Für LocalSystem zeigt `%APPDATA%` nach
> `C:\Windows\system32\config\systemprofile\...` — es findet dort nichts und meldet „keine
> Konten", ohne dass ein Fehler erscheint.

### 2.6 Windows-Update zähmen
`gpedit.msc` → Computerkonfiguration → Administrative Vorlagen → Windows-Komponenten →
Windows Update → **Manage end user experience** → **Automatische Updates konfigurieren =
Aktiviert**.

Dann in der Auswahlliste nachsehen, was dein Build anbietet:

| Option | Bedeutung | Verfügbar |
|---|---|---|
| **7** | herunterladen, zum Installieren **und** zum Neustarten nachfragen | Microsoft belegt sie für Server 2016/2019; die Richtlinienseite endet bei 2022. **Für Server 2025 nicht belegt** — nachsehen, ob sie in der Liste steht. |
| **2** | vor dem Herunterladen **und** vor dem Installieren nachfragen | überall vorhanden |

**Nimm 7, wenn sie da ist — sonst 2.** Beide verhindern, was hier zählt: dass sich die Maschine
unbeaufsichtigt neu startet. Option 2 ist etwas strenger (sie fragt schon vor dem Laden).

Danach `gpupdate /force`.

> **Nachgeprüft am 15.11.2026:** Für Server 2025 ließ sich Option 7 nicht belegen. Steht sie bei
> dir in der Liste, sag Bescheid — dann halte ich es hier fest.

**„Aktive Stunden" reichen nicht:** Sie gelten täglich und dürfen höchstens 18 Stunden umfassen —
24/5 lässt sich damit nicht abdecken.

### 2.6b Die Falle beim allerersten Update-Durchlauf (erlebt am 15.11.2026)

Ein frisch bereitgestellter Contabo-Server steht auf Build **26100.1742** (RTM). Wer dort
"install all updates" klickt, installiert unter anderem **KB5122871** (Build 26100.33438) —
und Microsoft führt dazu ein bekanntes Problem:

> *"Remote Desktop Services might stop responding after September 2026 security update"* —
> RDP-Verbindungen brechen nach einigen Minuten ab, Anmeldeprobleme, Hängen bei
> "Please wait for the Remote Desktop Configuration".
> Quelle: <https://support.microsoft.com/en-us/help/5122871>

**Das Bild:** Anmeldung per RDP wird angenommen, dann schwarzer Bildschirm, dann
*"Your Remote Desktop Services session has ended"*. Die Maschine läuft, nur der Fernzugang
ist tot.

**Behoben in jedem Update ab dem 14.09.2026** (KB5129235 und später). Wer den ganzen Stapel
auf einmal durchlaufen laesst, kommt ueber dieses Loch hinweg — wer mittendrin stehenbleibt,
sitzt darin fest.

**Der Ausweg und zugleich die Lehre:** ohne zweiten Zugang ist man an dieser Stelle blind.
Bei Contabo gibt es **VNC** (Kundenbereich -> Manage -> *VNC Password*, dann *VNC Information*);
das hängt am Wirtsystem und braucht weder RDP noch einen laufenden Netzwerkdienst im Gast.
Dafuer ist ein VNC-Betrachter auf dem eigenen PC nötig — es gibt **keine** Browser-Konsole.
**Diesen Zugang einrichten, BEVOR man ihn braucht**, und das VNC-Passwort in den
Passwortmanager legen.

> **Niemals hart aus- und einschalten, solange "Working on updates" oder "Undoing changes"
> auf dem Bildschirm steht.** Windows räumt beim Herunterfahren eine Update-Transaktion auf;
> ein Stromschlag mitten darin hinterlaesst einen halb angewandten Komponentenspeicher.
> Reihenfolge, wenn etwas hängt: erst gar nichts, dann die Sitzung sauber **abmelden**, dann
> aus dem Betriebssystem heraus neu starten, dann *shutdown* + *start*, und *stop* ganz zuletzt.

> **Ebenfalls nicht hilfreich:** immer wieder neu per RDP verbinden. Jeder Versuch hängt bei
> dieser Störung eine weitere Sitzung auf dem Server auf, und Windows Server erlaubt nur zwei.

**Erster, kostenloser Handgriff bei schwarzem RDP-Bild:** im schwarzen Fenster **Strg+Alt+Ende**
(nicht Strg+Alt+Entf — das fängt der eigene PC ab). Kommt der Windows-Sicherheitsbildschirm,
lebt die Sitzung: Task-Manager -> Datei -> *Neue Aufgabe ausführen* -> `explorer.exe`.

**Zweiter kostenloser Handgriff:** die Verwaltungssitzung ansteuern. Sie geht an einem Teil des
hängenden Sitzungs-Hosts vorbei und kommt manchmal durch, wenn die normale Verbindung abbricht:

```powershell
mstsc /v:<IP-des-Servers> /admin
```

**Und das Zeitfenster nutzen:** die Störung setzt erst nach einigen Minuten Betrieb ein. Direkt
nach einem Neustart ist die Chance am größten. Also neu starten, **sofort** verbinden und als
Allererstes Windows Update starten — nichts anderes öffnen, kein Explorer-Bummel.

### 2.7 Samstags-Ritual
Jeden Samstag bei geschlossenem Markt: Updates suchen, installieren, dann
```powershell
shutdown /r /t 60
```
(ohne `/f`). Danach **von außen** — Handy, nicht per RDP — prüfen, dass beide Kontonummern im
Cockpit frisch melden. Damit probst du die ganze Kette wöchentlich, statt sie im Ernstfall zum
ersten Mal zu testen.

### 2.8 RDP-Disziplin: trennen, nie abmelden
Fenster schließen oder **Verbindung trennen**. **Niemals „Abmelden"** — das beendet die Sitzung
und damit beide Terminals und das Cockpit. Der Schutz ist dann bis zum nächsten Neustart aus.

Einmal prüfen: `gpedit.msc` → Remotedesktopdienste → Sitzungszeitlimits — ein konfiguriertes
Zeitlimit für getrennte Sitzungen würde dasselbe anrichten.

### 2.9 Wie merkst du, dass etwas aus ist?
**Nicht am Alter von `mamal_cockpit.json` allein.** Der EA schreibt die Datei alle zwei Sekunden
über `OnTimer` — **auch mit ausgeschaltetem AutoTrading**. Sie ist dann taufrisch, während gar
nichts durchgesetzt wird.

Das Dashboard zeigt den Schutzzustand ausdrücklich an („SCHUTZ AUS", orange). Darauf schauen, nicht
auf die Frische.

Für Abwesenheit: ein Totmannschalter außerhalb der Maschine (z. B. healthchecks.io, kostenlos) ist
die ehrliche Antwort — er schlägt an, wenn die Maschine *nicht* meldet. Die Ping-URL ist ein
Geheimnis: wer sie hat, kann den Alarm beliebig stumm stellen.

---

## 3. Zwei MetaTrader-Installationen nebeneinander

### 3.1 Der eine Handgriff, auf den es ankommt
Beim **zweiten** Durchlauf des Installers: Haken bei der Lizenzvereinbarung setzen — **erst
dadurch wird „Einstellungen" anklickbar**. Dort den Zielordner ändern.

> **Die Falle:** Drückt man stattdessen „Weiter", **aktualisiert** der Installer die erste
> Installation. Danach gibt es weiterhin *ein* Terminal und *einen* Datenordner — und das zweite
> Konto kann gar nicht parallel laufen, weil ein Terminal nur einen Login hält.

Ordner: `C:\MT4\FTMO-A` und `C:\MT4\FTMO-B`. **Nicht** unter `Program Files`, **nicht**
`/portable`.

### 3.2 Beweisen, dass es wirklich zwei sind
In jedem Terminal: **Datei → Datenordner öffnen**. Dort `origin.txt` öffnen — darin steht der
Installationspfad. Er muss je Terminal ein anderer sein.

### 3.3 Was wohin
Je Datenordner (also **zweimal**):
```
MQL4\Experts\MamalTrading.ex4
MQL4\Presets\<je Konto eine .set>
```

> **Niemals** den `MQL4`-Ordner zweier Installationen per Junction teilen. Im Netz wird das
> empfohlen, um den EA nur einmal zu pflegen — hier bricht es alles: Zustandsdatei, Journal und
> **Befehlswarteschlange** beider Konten landen im selben Verzeichnis, und das Cockpit kann die
> Konten nicht mehr trennen.

### 3.4 Presets nicht verwechseln
Die `.set`-Dateien sehen gleich aus. Lädst du die des falschen Kontos, stehen
`InpInitialBalance` und die Tagesbasis falsch — **R4b rechnet die Max-Verlust-Sperre dann gegen
eine Basis, die es auf diesem Konto nie gab.** Benenne sie nach der Kontonummer.

### 3.4b Wenn der Zustand NICHT mitkommt (bewusster Neustart)
Entscheidung vom 15.11.2026: Journal, Equity-Reihen und Screenshots bleiben auf dem PC, der VPS
startet frisch. Das ist zulässig — es sind Aufzeichnungen, keine Schutzfunktion. **Dann muss aber
`InpInitialBalance` im Preset stehen.** Ohne `gvariables.dat` leitet der EA die R4b-Basis sonst
aus der **Einzahlungshistorie** ab und fällt auf den **aktuellen Kontostand** zurück, wenn die
Historie im Terminal nicht vollständig sichtbar ist (siehe 4.7). Bei Konto 421052619 wäre die
Basis dann 10.338 statt 10.000 — die Max-Verlust-Sperre also um 338 EUR zu locker.

Im Paket liegt dafür `MQL4\Presets\Mamal_Konto421052619.set` mit `InpInitialBalance=10000`.

> **Beide Zustandsdateien gemeinsam weglassen oder gemeinsam mitnehmen.** `MamalTrading_Lockstate.dat`
> allein weglassen geht nicht sauber: der EA merkt sich in `RG_LS_SEEN`, dass die Datei auf diesem
> Konto schon existiert hat, und wertet ihr **Fehlen** danach als Manipulation. Fehlt die
> GlobalVariable-Datei `gvariables.dat` mit, ist diese Erinnerung ebenfalls weg und der Start ist
> ein echter Erststart.

### 3.5 Starten
Immer die Verknüpfung auf die `terminal.exe` im **jeweiligen** Ordner. Zweimal dieselbe starten
holt nur das erste Fenster nach vorn — es sieht aus wie „läuft schon", aber ein Konto ist
unüberwacht.

### 3.6 Charts
4–6 je Terminal, auf allen Charts eines Terminals dieselbe `InpMagic`. Profil speichern, damit es
den Neustart übersteht. Jeder weitere Chart kostet Speicher und Rechenzeit.

### 3.7 Benachrichtigungen
Dieselbe MetaQuotes-ID in beiden Terminals bedeutet **doppelte** Push-Meldungen, ohne dass der
Text sagt, welches Konto gemeint ist. Entweder nur in einem Terminal einschalten, oder damit
leben.

---

## 4. Der Umzug selbst

### 4.1 Zeitpunkt: Freitag nach Handelsschluss, flach
**Null offene Positionen, null Vormerkungen.** Lässt sich etwas nicht schließen: Umzug
verschieben.

### 4.2 Was mitmuss — und was `git clone` NICHT mitbringt
Diese Dateien stehen in `.gitignore` und fehlen nach einem reinen Klon (nachgeprüft):
```
cockpit/data/            (die Equity-Reihen)
*.set                    (die Presets)
*.ex4                    (der kompilierte EA)
MamalTrading_Journal.csv
MamalTrading_Lockstate.dat
Mamal_*.png              (die Bildschirmfotos)
```
**Code und Oberfläche sehen nach einem Klon vollständig aus. Der Zustand ist es nicht.**

### 4.3 Die zwei Dateien, die zusammen gehören
`profiles\gvariables.dat` **und** `MQL4\Files\MamalTrading_Lockstate.dat` — **immer beide oder
keine**.

> **Warum:** `MamalTrading.mq4:220` — sobald die Sperrdatei einmal existiert hat, merkt der EA
> sich das in der GlobalVariable `RG_LS_SEEN`, und **ihr Fehlen gilt von da an als
> Manipulation**. Bringst du die GlobalVariables ohne die Datei mit, sperrt sich der EA
> den Tag mit lautem Alarm.

**`gvariables.dat` nur bei geschlossenem MT4 kopieren** — MT4 schreibt die GlobalVariables
regulär erst beim Beenden.

### 4.4 Equity-Reihen vorher archivieren
`cockpit/data/equity_*.csv` in ein Archiv **außerhalb** des Projekts kopieren.

> **Warum:** `server.js` kappt stündlich jede dieser Dateien über **2 MB** auf die letzten 20.000
> Zeilen. Dein Hauptkonto liegt heute bei 547 KB — noch ist nichts verloren, aber der Schnitt ist
> unwiederbringlich, wenn er kommt. Es gibt keine zweite Quelle für diese Kurve.

### 4.5 Was NICHT mitgeht
`history\`, `bases\`, `logs\`, `MQL4\Logs\`, `mamal_cockpit.json`, `mamal_cmdq.txt`,
`mamal_ack.csv` — und vor allem die **alten Wegweiser** aus
`%APPDATA%\MetaQuotes\Terminal\Common\Files`: dort liegen Dateien für vier nicht mehr genutzte
Konten. Mitkopiert erscheinen sie als **Geisterkonten** im Umschalter.

### 4.6 Reihenfolge
1. Paket schnüren (während die Identitätsprüfung noch läuft)
2. VPS vorbereiten: Zeitzone, automatische Anmeldung, Node, **beide MT4 installiert** — aber noch
   **kein Live-Konto angemeldet**
3. Freitag: PC-Terminals über **Datei → Beenden** schließen
4. *Erst danach* `gvariables.dat` und `Lockstate.dat` frisch ins Paket, ZIP neu bauen
5. Auf dem VPS einsetzen, **während MT4 geschlossen ist**
6. Konto anmelden, Kontohistorie auf **„Gesamte Historie"** stellen, Preset laden
7. EA auf den Chart — **AutoTrading noch AUS**. Panel prüfen: Basis, Tageslimit, kein Sperrgrund,
   Verlustserie plausibel. **Erst dann** AutoTrading einschalten.
8. Cockpit starten, von Laptop/Handy aufrufen — beide Konten im Umschalter?
9. PC kalt stellen: EA von allen Charts **entfernen**, AutoTrading aus, Node beenden,
   `MamalCockpit.vbs` aus dem Autostart nehmen

> **Nie beide Maschinen gleichzeitig mit AutoTrading auf demselben Konto.** MT4 erlaubt denselben
> Login zweimal, und TradingGuard hat **keine** maschinenübergreifende Sperre: jede Maschine wählt
> ihren eigenen Master und wacht eigenständig. Beide würden dieselbe Position schließen wollen.

### 4.7 Kontohistorie
Im Terminal-Fenster Reiter **Kontohistorie → Rechtsklick → „Gesamte Historie"**. Steht dort ein
kurzer Zeitraum, sieht der EA geschlossene Tickets nicht mehr — und der Sichtbarkeits-Wächter
wertet das als Problem.

**Zweiter, wichtigerer Grund bei einem Neustart ohne `gvariables.dat`:** aus dieser Historie liest
der EA die **Einzahlung** und damit die R4b-Basis. Steht der Reiter auf einem kurzen Zeitraum,
findet er sie nicht und nimmt den aktuellen Kontostand — eine zu hohe Basis, also eine zu lockere
Verlustsperre. Das Preset aus 3.4b fängt das ab, aber **beides** zusammen ist der sichere Weg:
erst Historie auf „Gesamte Historie", dann Preset laden, dann im Panel die Basis ablesen.

---

## 5. Abnahme, bevor der PC abgeschaltet wird

1. **Neustart-Test:** Im Kundenbereich „Reboot", dann **ohne RDP** von außen zusehen. Nach wie
   vielen Minuten melden beide Konten frisch im Cockpit? Zahl notieren.
2. **Testbefehl:** Freitagabend ein `closesym` auf ein Symbol ohne offene Position durchschicken —
   die Quittung muss „es war nichts offen" lauten, und im Tagebuch muss eine Zeile stehen.
3. **Eine Woche parallel beobachten**, bevor die PC-Installation endgültig stillgelegt wird (aber
   dort mit AutoTrading **aus** und EA von den Charts entfernt).

---

## 6. Die Fallen auf einen Blick

| Falle | Folge |
|---|---|
| „Weiter" statt „Einstellungen" beim zweiten Installer | Nur ein Terminal, zweites Konto läuft nie |
| `MQL4`-Ordner per Junction geteilt | Befehlswarteschlangen beider Konten kollidieren |
| `gvariables.dat` ohne `Lockstate.dat` | EA wertet es als Manipulation → Tagessperre |
| `gvariables.dat` bei laufendem MT4 kopiert | Veraltet oder halb geschrieben |
| Nur `git clone` auf dem VPS | Kein Zustand, keine Presets, kein kompilierter EA |
| Alte Wegweiser mitkopiert | Geisterkonten im Umschalter |
| Beide Maschinen mit AutoTrading am selben Konto | Doppeltes Schließen |
| In RDP „Abmelden" statt „Trennen" | MT4 und Cockpit beendet, Schutz aus |
| Aufgabenplaner „unabhängig von der Anmeldung" | MT4 ohne Fenster in Sitzung 0 |
| 3-Tage-Haken stehengelassen | Windows beendet MT4 mitten in der Woche |
| Autologon per Registry | Passwort im Klartext lesbar |
| Autologon als Administrator | Verlorenes Geheimnis = die ganze Maschine |
| RDP-Port verlegt und sich sicher gefühlt | Kein Gewinn, Scanner finden ihn trotzdem |
| Frische `cockpit.json` als „alles gut" gelesen | Wird auch mit AutoTrading AUS geschrieben |
| Preset des falschen Kontos geladen | R4b rechnet gegen eine falsche Basis |
| Equity-Reihen nicht archiviert | Lange Kurve bei 2 MB unwiederbringlich gekappt |

---

*Verwandt: [VPS-NO-OVERRIDE-PLAN.md](VPS-NO-OVERRIDE-PLAN.md) · [../cockpit/REMOTE-ACCESS.md](../cockpit/REMOTE-ACCESS.md)*
