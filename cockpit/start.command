#!/bin/bash
# Doppelklick startet das Cockpit. (Rechtsklick → Öffnen, falls macOS blockt.)
cd "$(dirname "$0")" || exit 1
echo "Starte Mamal-Trading Cockpit …"
exec node server.js
