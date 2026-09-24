# Shared Logic & Blueprint (plan status v0.14)
> **Note:** The v0.15 patch list below is **largely done** as of v0.15–v0.18 (including #11 R17 currency vector, #12 journal audit). Current maturity level: [`../../docs/STATUS.md`](../../docs/STATUS.md). The MT5 mirror is still open.

Active file: **`ea/mt4/MamalTrading.mq4`** (MT4). The MT5 mirror **`ea/mt5/MamalTrading.mq5`** has not been built yet.
*(The old `RiskGuard.mq4/.mq5` are obsolete predecessors and can be deleted.)*

The complete technical implementation is documented in [../../docs/TECHNICAL.md](../../docs/TECHNICAL.md); the rule contract in [../../RULES.md](../../RULES.md).

## Implemented (R1–R19 + R25, R9 off)
Risk per trade (auto lot), idea cap, daily budget, daily/max/weekly loss lock, cooldown/losing streak, mandatory SL+TP, minimum risk-reward ratio, no-override, journal, total risk cap, daily target + giveback, minimum break, min SL/max lot, session/news, correlation (net USD), de-risk, revenge window. Auto-scale caps. Crash hardening (trades only in `OnTick`, throttling, throttled panel).

## MT4 ↔ MT5 differences (for the mirror)
| Topic | MT4 (active) | MT5 (open) |
|------|-------------|-------------|
| Catching a manual fill | polling (`OnTimer`/`OnTick`) | `OnTradeTransaction` |
| Closing | `OrderClose` + price per symbol via `MarketInfo` | `CTrade.PositionClose(ticket)` |
| Positions vs. pendings | combined (`OrdersTotal`+`OrderType`) | separate |
| Equity/balance | `AccountEquity()` / `AccountBalance()` | `AccountInfoDouble(...)` |
| Server time | `SrvTime()` = PC clock + server offset (since v0.16; MQL4 has no `TimeTradeServer`) | `TimeTradeServer()` (MQL5 has it) |

## Next step: v0.15 patch order (from the review)
Before the MT5 mirror, first apply the P0/P1 patches to MT4 (details: [../../docs/REVIEW-v0.14.md](../../docs/REVIEW-v0.14.md) §6):
1. `MathMax(Balance,Equity)` as the daily baseline (P0-5)
2. Decouple enforcement from the tick, `OnTimer→Cycle(false,true)` (P0-1)
3. `g_eaClosed[]` exclusion for the EA's own closes (P0-3)
4. History-based, idempotent loss resolution instead of `g_known` (P0-2/P0-4)
5. Magic filter in all enforce/streak functions (P1-11)
6. Max loss 8→6 % + warning entry gate (P0-6)
7. Lockstate file (checksum, fail-closed) (P0-7)
8. `GV_DAY_RISK` reconciliation + flush (P1-5)
9. Time source = tick-independent server time `SrvTime()` (PC clock + offset; MQL4 has no `TimeTradeServer`) (P1-4)
10. R7 deadline: anchor `OrderOpenTime`, `GetTickCount`, grace 3–5 s, news grace 0 (P1-7)
11. R17 real currency vector exposure (cross pairs) (P1-8)
12. Extend journal fields (P1-10)
13. `#define EA_VERSION`, documentation hygiene (P3-6/P3-7)
14. Windows VPS + heartbeat + prop firm rule compliance (multi prop firm; FTMO = default profile) (P1-12/P1-13)
15. Remaining P2 items (polish)

Only after a green **rule test harness / visual test** of the rule matrix (rule behavior, not a profit backtest) → MT5 mirror.
