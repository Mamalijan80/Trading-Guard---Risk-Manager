# Mamal-Trading Cockpit (localhost)

Live-Dashboard, das zeigt **wo du bei jeder Regel stehst** — dynamisch auf dein
Konto/deine Einstellungen zugeschnitten, plus Klartext-Erklärungen und ein Journal.

DLL-frei: Der MT4-EA schreibt seinen Zustand als JSON in `MQL4/Files/`, dieser
kleine Node-Server liest das und serviert die Seite. Kein Eingriff in den Handel.

## Einmal einrichten
1. MT4 öffnen, EA **Mamal-Trading** auf einen Chart ziehen (v0.26+), AutoTrading an.
   Der EA-Input **`InpCockpit` muss `true`** sein (Standard).
2. Server starten:
   - **Windows:** Doppelklick auf **`start.bat`**.
   - **macOS:** Doppelklick auf **`start.command`**.
   - oder im Terminal: `node server.js`.

   Beim Start öffnet sich der Browser auf `http://localhost:8730`. Das Server-Fenster
   zeigt oben, **welche MT4-Ordner gefunden wurden** — bleibt es bei „keiner gefunden",
   siehe *Troubleshooting* (Portable-Mode).

## Danach
- Im MT4-Panel auf **„COCKPIT: REGELN & FORTSCHRITT"** klicken → der Browser öffnet
  sich automatisch (bzw. der Tab wird angesteuert).
- Das Dashboard aktualisiert sich alle 1–2 Sekunden von selbst.

## Was es zeigt
- **Status & Sperren** oben (grün = handeln erlaubt, rot = gesperrt + Grund).
- **Pro Regel** (R1–R18, R25): dein Wert + aktueller Stand + Ampel/Fortschrittsbalken.
- **Bewusst ausgeschaltete Regeln** als graue Chips.
- **Journal**: die letzten Trades, Blocks, Sperren und Cooldowns.

## Troubleshooting
- **Klick auf „COCKPIT" öffnet nichts?** Läuft evtl. noch eine **alte** Server-Instanz?
  Der Server merkt sich den MT4-Ordner **beim Start** — eine vor dem EA gestartete alte
  Instanz sieht den Klick nie. **Altes Server-Fenster schließen und `start.bat` neu starten.**
  (Eine zweite Instanz kann Port 8730 nicht binden und beendet sich mit „Port belegt".)
- **„Warte auf MetaTrader…"** → MT4 läuft nicht, EA nicht auf dem Chart, oder
  `InpCockpit=false`. Prüfe im MT4-Reiter *Experten* die Zeile `Cockpit=an`.
- **„Ordner: — keiner gefunden" / Portable-Mode?** Startet MT4 mit `/portable`, liegen die
  Dateien unter `<Installationsordner>\MQL4\Files` statt unter `%APPDATA%\MetaQuotes\…`.
  Dann den Ordner explizit setzen — in `start.bat` die `set MAMAL_FILES=…`-Zeile einkommentieren,
  z. B. `set MAMAL_FILES=C:\MT4\MQL4\Files`, oder im Terminal `MAMAL_FILES="…/MQL4/Files" node server.js`.
- **Port belegt?** `MAMAL_PORT=8731 node server.js` (dann auch `InpCockpitPort` im EA angleichen).
- Der Server läuft rein lokal (127.0.0.1), nichts geht ins Internet.

## Dateien
- `server.js` — der lokale Server (zero-dependency, Node).
- `dashboard.html` — die Oberfläche.
- `start.bat` — Doppelklick-Starter (Windows).
- `start.command` — Doppelklick-Starter (macOS).
