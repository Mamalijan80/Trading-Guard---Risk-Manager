# Mamal-Trading Cockpit (localhost)

Live dashboard that shows **where you stand on every rule** — tailored dynamically to your
account and your settings, plus plain-language explanations and a journal.

DLL-free: the MT4 EA writes its state as JSON into `MQL4/Files/`, this small
Node server reads that and serves the page. No interference with trading.

## One-time setup
1. Open MT4, drag the EA **Mamal-Trading** onto a chart (v0.26+), enable AutoTrading.
   The EA input **`InpCockpit` must be `true`** (default).
2. Start the server:
   - **Windows:** double-click **`start.bat`**.
   - **macOS:** double-click **`start.command`**.
   - or in the terminal: `node server.js`.

   On startup the browser opens at `http://localhost:8730`. The server window
   shows at the top **which MT4 folders were found** — if it stays at "keiner gefunden"
   (none found), see *Troubleshooting* (portable mode).

## After that
- In the MT4 panel, click **"COCKPIT: REGELN & FORTSCHRITT"** (cockpit: rules & progress) → the browser
  opens automatically (or the existing tab is focused).
- The dashboard refreshes itself every 1–2 seconds.

## What it shows
- **Status and locks** at the top (green = trading allowed, red = locked + reason).
- **Per rule** (R1–R18, R25): your value + current state + traffic light / progress bar.
- **Deliberately disabled rules** as grey chips.
- **Journal**: the most recent trades, blocks, locks and cooldowns.

## Troubleshooting
- **Clicking "COCKPIT" opens nothing?** Maybe an **old** server instance is still running?
  The server remembers the MT4 folder **at startup** — an old instance started before the EA
  never sees the click. **Close the old server window and restart `start.bat`.**
  (A second instance cannot bind port 8730 and exits with "Port belegt" / port in use.)
- **"Warte auf MetaTrader…"** (waiting for MetaTrader) → MT4 is not running, the EA is not on the chart, or
  `InpCockpit=false`. Check the line `Cockpit=an` (cockpit=on) in the MT4 *Experts* tab.
- **"Ordner: — keiner gefunden" (folder: none found) / portable mode?** If MT4 starts with `/portable`, the
  files live under `<installation folder>\MQL4\Files` instead of under `%APPDATA%\MetaQuotes\…`.
  Then set the folder explicitly — uncomment the `set MAMAL_FILES=…` line in `start.bat`,
  e.g. `set MAMAL_FILES=C:\MT4\MQL4\Files`, or in the terminal `MAMAL_FILES="…/MQL4/Files" node server.js`.
- **Port in use?** `MAMAL_PORT=8731 node server.js` (then also adjust `InpCockpitPort` in the EA).
- The server runs purely locally (127.0.0.1), nothing goes out to the internet.

## Files
- `server.js` — the local server (zero-dependency, Node).
- `dashboard.html` — the user interface.
- `start.bat` — double-click starter (Windows).
- `start.command` — double-click starter (macOS).
