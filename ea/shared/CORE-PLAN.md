# Geteilte Logik & Bauplan (Plan-Stand v0.14)
> **Hinweis:** Die v0.15-Patchliste unten ist in v0.15–v0.18 **weitgehend erledigt** (inkl. #11 R17-Währungsvektor, #12 Journal-Audit). Aktueller Reifegrad: [`../../docs/STATUS.md`](../../docs/STATUS.md). MT5-Spiegel weiter offen.

Aktive Datei: **`ea/mt4/MamalTrading.mq4`** (MT4). Der MT5-Spiegel **`ea/mt5/MamalTrading.mq5`** ist noch nicht gebaut.
*(Die alten `RiskGuard.mq4/.mq5` sind obsolete Vorgänger und können gelöscht werden.)*

Die komplette technische Umsetzung steht in [../../docs/TECHNISCHE-DOKU.md](../../docs/TECHNISCHE-DOKU.md); der Regel-Vertrag in [../../RULES.md](../../RULES.md).

## Implementiert (R1–R19 + R25, R9 aus)
Risiko/Trade (Auto-Lot), Idee-Cap, Tagesbudget, Tages-/Max-/Wochen-Verlust-Sperre, Cooldown/Verlustserie, SL+TP-Pflicht, Min-CRV, No-Override, Journal, Gesamtrisiko-Deckel, Tagesziel+Giveback, Mindestpause, Min-SL/Max-Lot, Session/News, Korrelation (Netto-USD), De-Risk, Revenge-Fenster. Auto-Scale-Caps. Crash-Härtung (Trades nur OnTick, Drossel, gedrosseltes Panel).

## MT4 ↔ MT5 Unterschiede (für den Spiegel)
| Thema | MT4 (aktiv) | MT5 (offen) |
|------|-------------|-------------|
| Manuellen Fill fangen | Polling (`OnTimer`/`OnTick`) | `OnTradeTransaction` |
| Schließen | `OrderClose` + Preis je Symbol via `MarketInfo` | `CTrade.PositionClose(ticket)` |
| Positionen vs. Pendings | gemeinsam (`OrdersTotal`+`OrderType`) | getrennt |
| Equity/Balance | `AccountEquity()` / `AccountBalance()` | `AccountInfoDouble(...)` |
| Serverzeit | `SrvTime()` = PC-Uhr + Server-Offset (ab v0.16; MQL4 hat kein `TimeTradeServer`) | `TimeTradeServer()` (MQL5 hat es) |

## Nächster Schritt: v0.15-Patch-Reihenfolge (aus der Review)
Vor MT5-Spiegel zuerst die P0/P1-Patches auf MT4 (Details: [../../docs/REVIEW-v0.14.md](../../docs/REVIEW-v0.14.md) §6):
1. `MathMax(Balance,Equity)` als Tagesbasis (P0-5)
2. Enforce vom Tick entkoppeln, `OnTimer→Cycle(false,true)` (P0-1)
3. `g_eaClosed[]`-Ausschluss für eigene Closes (P0-3)
4. History-basierte, idempotente Verlust-Auflösung statt `g_known` (P0-2/P0-4)
5. Magic-Filter in allen Enforce-/Streak-Funktionen (P1-11)
6. Max-Loss 8→6 % + Warn-Entry-Gate (P0-6)
7. Lockstate-Datei (Checksum, fail-closed) (P0-7)
8. `GV_DAY_RISK`-Reconciliation + Flush (P1-5)
9. Zeitquelle = tickunabhängige Server-Zeit `SrvTime()` (PC-Uhr + Offset; MQL4 hat kein `TimeTradeServer`) (P1-4)
10. R7-Frist: Anker `OrderOpenTime`, `GetTickCount`, Grace 3–5 s, News-Grace 0 (P1-7)
11. R17 echtes Währungs-Vektor-Exposure (Cross-Pairs) (P1-8)
12. Journal-Felder erweitern (P1-10)
13. `#define EA_VERSION`, Doku-Hygiene (P3-6/P3-7)
14. Windows-VPS + Heartbeat + Prop-Firm-Regel-Compliance (Multi-Prop-Firm; FTMO = Default-Profil) (P1-12/P1-13)
15. P2-Rest (Feinschliff)

Erst nach grünem **Rule-Test-Harness/Visual-Test** der Regelmatrix (Regelverhalten, kein Profit-Backtest) → MT5-Spiegel.
