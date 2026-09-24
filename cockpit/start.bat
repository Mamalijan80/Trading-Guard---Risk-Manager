@echo off
REM Doppelklick startet das Mamal-Trading Cockpit unter Windows.
REM Das Fenster offen lassen - es zeigt die gefundenen MT4-Ordner und Fehler.
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   Node.js wurde nicht gefunden. Bitte von https://nodejs.org installieren
  echo   und dieses Fenster danach erneut oeffnen.
  echo.
  pause
  exit /b 1
)

echo Starte Mamal-Trading Cockpit ...
echo (Zum Beenden dieses Fenster schliessen oder Strg+C druecken.)
echo.
REM Optional: eigenen MT4-Files-Ordner erzwingen (z.B. bei Portable-Mode):
REM   set MAMAL_FILES=C:\Pfad\zu\MetaTrader\MQL4\Files
node server.js

echo.
echo   Cockpit-Server beendet. Fenster kann geschlossen werden.
pause
