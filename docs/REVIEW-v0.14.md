> ⛔ **FROZEN ARTIFACT — state of v0.14 (2026-06-26). NOT the current state.** This review describes v0.14; the P0/P1 items listed here were worked off in v0.15–v0.18. Current maturity level: [`STATUS.md`](STATUS.md). Mapping P0 → resolved in:
> - **P0-1** tick-only enforcement → v0.15: `Cycle()` from OnTick **and** OnTimer.
> - **P0-2/P0-4** loss streak / partial close → v0.15: history-based (`ResolveHistory`, `ProcKey`); v0.18-B4/6: EA share and trader share separated.
> - **P0-3** EA close counted as a loss → v0.15: `RGEAC_` marker; v0.18-B5/8: marker set only after a confirmed close.
> - **P0-5** FTMO day base `MathMax(Balance,Equity)` → v0.15; v0.18-B1: max-loss base (`InpInitialBalance` default 0=auto).
> - **P0-6** max-loss buffer → v0.15: 6 % + warn gate 5 %.
> - **P0-7** no-override → v0.16: lockstate file (HMAC-light, fail-closed) — local friction only, true immutability first on a VPS.
> - **P1-4** time source → v0.17: `SrvTime()` (MQL4 has no `TimeTradeServer`). **P1-7** R7 → v0.17: 5 s / news 0 / OpenTime anchor. **P1-8** R17 → v0.17: currency vector. **P1-10** journal → v0.17: 18-column audit. **P1-11** magic filter → v0.15: `WatchScope`.
>
> Verdict **C) not prop-firm-safe** still stands, because **stage 4 (live-tested)** is still missing — not because of the P0 items listed below (those are addressed in code + AI-fix-verified, but untested).

I am producing the final review report. Because the P0/P1 verdicts partly contain severity adjustments (e.g. F3/F4/F9 downgraded, FTMO-3 refuted), I group by the **verified** severities, not by the raw findings.

---

# FINAL REVIEW REPORT — MamalTrading.mq4 (FTMO risk engine)
Source: `/Users/mohammadrezatavakoli/Desktop/TradingGuard/ea/mt4/MamalTrading.mq4` (header v0.12 / print v0.14)

## 1. Executive Summary

The tool is conceptually sound, but **not reliable in its core purpose — enforcing discipline and FTMO limits inescapably**, and the header itself correctly declares it as "NUR DEMO / UNGETESTET" (demo only / untested). The most serious defects are systemic: the entire protection hangs on ticks (`allowTrades` comes only from `OnTick`), so `EnforceSLTP`/`SafeCloseAll` fail in exactly the tick-starved/gappy markets where they are needed (R7-1, R4-2); the loss-streak / revenge discipline lives in volatile in-memory arrays and does not survive the "~per-minute" Wine restarts that the documentation itself describes (P6-01, P8-03); the EA's own protective closes are falsely counted as trader losses and trigger false locks (P9-1); and the day base is not FTMO-compliant (`AccountEquity()` instead of `MathMax(Balance,Equity)`, F1-P0). The local "no-override" (R10) is trivially bypassable (delete the GVs, switch AutoTrading off) — genuine irreversibility exists only on the server/VPS side (P5-1). **Decision: C) not safe enough for FTMO** — ready for testing only after the P0/P1 patches prioritised below and a Strategy Tester run over the entire rule matrix.

---

## 2. Severity list (grouped by verified severity)

### P0 — Blocker (must be fixed before any money is at stake)

**P0-1 · R7/SafeCloseAll fire only on ticks — never in a dead/gappy market** (R7-1)
- **Problem:** The entire enforcement block in `Cycle()` (L344 `if(!tradingDisabled && allowTrades)`) runs only with `allowTrades=true`, which comes exclusively from `OnTick` (L127). `OnTimer` calls `Cycle(false)` (L129). Without ticks (weekend, rollover, illiquid symbol, feed stall) a naked position is neither detected nor closed; R1/R8/R12 and the lock `SafeCloseAll` are equally idle.
- **Impact:** A position without an SL can run unbounded → FTMO daily/max-loss breach in exactly the most dangerous market.
- **Fix:** Extend `Cycle()` with an `enforce` parameter; `OnTimer→Cycle(false,true)`. Couple enforcement to `(enforce && !tradingDisabled)` instead of to `allowTrades`; entries still only on `allowTrades`. That way the watchdog runs every `InpTimerSeconds` (1 s) independently of ticks.
- **Affected:** `Cycle` (L344-348), `OnTimer` (L129), `EnforceSLTP`, `SafeCloseAll`.

**P0-2 · R5/R6/R19/R25 miss every close during downtime (g_known in memory)** (P6-01)
- **Problem:** `g_known[]` (L92) is purely in-memory and empty after every `OnInit`. `UpdateStreak` (L271-288) builds `cur[]` only from open tickets and overwrites `g_known` unconditionally (L286-287); `ResolveClosed` runs only for tickets that were previously known and are now missing. Closes that occur during a crash/restart window are never resolved → `GV_CONSEC` does not increase, no cooldown/lock/de-risk/revenge. Documentation: "restarts ~every minute".
- **Impact:** Core discipline (R5/R6/R19/R25) is practically blind on the target platform.
- **Fix:** History-based, idempotent resolution. Persistent GV `RG_LAST_CLOSE` (watermark, do NOT reset it in `RollNewDay`); in `OnInit`+`Cycle`, process via `MODE_HISTORY` all closes with `OrderCloseTime()>RG_LAST_CLOSE` (Magic==InpMagic) **sorted by CloseTime**, extract the threshold logic from `ResolveClosed` into `ApplyConsecThresholds()` and share it. Idempotency via a monotonically increasing watermark + a resolved-ticket file.
- **Affected:** `g_known`, `UpdateStreak`, `ResolveClosed`, new `ResolveClosedHistory`/`ApplyConsecThresholds`.

**P0-3 · EA-forced closes count as a "loss streak" → false cooldown/day lock + revenge** (P9-1)
- **Problem:** `ResolveClosed` (L252-270) evaluates every disappeared ticket purely by `net<0` (L256), without checking the close reason or the magic number. `EnforceSLTP/Risk/RR/Heat` and `SafeCloseAll` close at market price (in practice almost always at a loss) → `GV_CONSEC++` (L260), `SetRevenge` (L259), up to the R6 day lock (L262). The tool punishes the user for its own protective interventions.
- **Impact:** A single heat/naked intervention with 2-3 open losing positions can lock the FTMO day for no reason.
- **Fix:** In-memory exclusion list `g_eaClosed[]`. Before EVERY watchdog `OrderClose` (L372/378/401/424/446/461) call `MarkEaClosed(ticket)`; on a failed close, revert the entry. In `ResolveClosed` (before L256): `if(TakeEaClosed(ticket)){ Journal(...EA-Schutz-Close...); return; }`. A magic filter alone is NOT sufficient (tool trades keep InpMagic).
- **Affected:** `ResolveClosed`, all enforce functions, `SafeCloseAll`.

**P0-4 · Partial close counts every partial as a complete trade exit** (P9-2)
- **Problem:** `UpdateStreak` treats a ticket as "closed" as soon as it drops out of `OrdersTotal()`. An MT4 partial close moves the remaining volume onto a NEW ticket → the old ticket counts as a full close (the partial net is scored into the streak), and the remainder ticket is scored AGAIN later (double counting).
- **Impact:** The R5/R6 loss streak is over-/under-counted on every partial close → premature/unpredictable false locks; partial closing (standard management) becomes unusable.
- **Fix:** Aggregate the trade result per position from `MODE_HISTORY` (key `OrderOpenTime`+symbol+type) into ONE `net`; score it only once NO open remainder ticket with the same identity exists. Aligns with the P0-2 history rebuild.
- **Affected:** `UpdateStreak`, `ResolveClosed`.

**P0-5 · Day-start equity not FTMO-compliant (bare `AccountEquity`)** (F1-P0)
- **Problem:** `RollNewDay` L165/L171 sets `GV_DAYSTART_EQ`/`GV_PEAK_EQ = AccountEquity()`. FTMO measures against `max(Balance,Equity)` at 00:00. With an overnight losing float, equity < balance → base too low → `dailyDDpct` (L306) too small → R4 locks too late, the FTMO limit can be breached while the EA still shows "green".
- **Impact:** Directly undermines the contractual purpose (R4).
- **Fix:** `double base = MathMax(AccountBalance(), AccountEquity());` for `GV_DAYSTART_EQ` AND `GV_PEAK_EQ`. (Pure balance would likewise be wrong with an overnight profit — hence `MathMax`, not the original finding's proposal.) Snapshot timing: gated, log the first-start case. No history reconstruction needed.
- **Affected:** `RollNewDay` (L165, L171).

**P0-6 · R4b max loss 8 % is a trigger, not a buffer** (P4-1)
- **Problem:** `GV_HARD_LOCK` is only set AFTER `totalDDpct>=InpMaxLossPct(8.0)` has been reached (L336-337); `SafeCloseAll` runs with a delay (OnTick only). The remaining 2 % margin has to absorb polling latency, slippage (`InpSlippage=30`), spread spikes, multiple positions and gaps → the FTMO 10 % hard limit can be breached before the close.
- **Impact:** Immediate end of the challenge.
- **Fix:** (a) Proactive entry gate in `DoEntry`: new input `InpMaxLossWarnPct` (~6.0); no new trades at `tdd>=Warn`. (b) `InpMaxLossPct` default 8.0→6.0 (4 % buffer). Document the residual weekend/overnight gap risk (SafeCloseAll on OnTick) as a fundamental limit.
- **Affected:** `DoEntry` (L534ff), Cycle hard lock (L336-337), `InpMaxLossPct` (L17).

**P0-7 · Local no-override trivially bypassable — no fail-closed/checksum/lockfile** (P5-1)
- **Problem:** Lock state lives only in GVs (deletable via the F3 editor); switching AutoTrading off disables the ENTIRE enforce block (L332-334/344, notify only); the EA can be removed. No disk lockfile, no HMAC, no fail-closed behaviour.
- **Impact:** R10 — the central pillar of the value proposition — can be defeated in seconds, precisely at the moment of emotional pressure.
- **Fix:** (1) Persistent lockstate file (`MQL4/Files`) with HMAC/checksum over a compiled-in secret key; in `OnInit` read both the GVs and the file and adopt the most restrictive state (fail-closed). (2) Mirror revenge/streak as well. (3) On `!IsTradeAllowed()` set a "bypassed" marker + penalty lock instead of merely warning. (4) Communicate honestly: complete irreversibility only on the server/VPS side.
- **Affected:** `OnInit`, lock defines (L64-77), L332-334.

### P1 — High (mandatory before funded; otherwise the tool is unreliable)

**P1-1 · Lock detection is effectively ~1 s polling, and the close additionally hangs on `IsTradeContextBusy`** (P4-2) — the lock is set ungated, but the close runs only in the OnTick path; in tick-starved phases the latency is unbounded. Fix as in P0-1 (close from the timer) + retry loop with `RefreshRates()` instead of a single `return` (L452). Affected: `Cycle`, `SafeCloseAll`.

**P1-2 · Day-start equity captured at attach time — wrong R4 base on a first start in the middle of the day** (P4-3) — `RollNewDay` L165 freezes midday equity if the EA only starts after broker midnight → R4 allows more than FTMO does. Fix: detect the first-start case (`!GlobalVariableCheck(GV_DAYSTART_DAY)`), use a conservative `base=AccountBalance()` + warning banner; leave the genuine date-change path unchanged. Affected: `RollNewDay`.

**P1-3 · Loss streak misses closes in the restart gap (g_known) — R5/R6/R19 under-count** (F10) — a subset of P0-2 (narrowly focused on the restart gap); fully resolved by the history-based resolution from P0-2. Affected: `UpdateStreak`, `OnInit`.

**P1-4 · ServerDayKey/NextServerMidnight use `TimeCurrent()` instead of `TimeTradeServer()`** (F2) — they freeze without ticks (weekend/illiquid) → delayed RollNewDay / stale day base. Symmetric to IsDayLocked/CooldownActive, hence the direction is "locks later", but the core guarantee is broken. Fix: switch L98/99/100 to `TimeTradeServer()`; align L177/180/537/543/590 too; `TimeLocal()` at L292/376 stays. Affected: `ServerDayKey`, `NextServerMidnight`, `WeekIdx`.

**P1-5 · R3 day budget can under-count permanently after a crash → over-risk** (P7-02) — `GV_DAY_RISK` is only additive after OrderSend (L589), no flush, no reconciliation; a crash between L587 and L589 → rp is never booked. Fix: in `Cycle` set `GV_DAY_RISK = max(persisted, OpenedTodayToolRiskPct())` (sum of open tool risks since day start) before the R3 gate; `GlobalVariablesFlush()` after L589. Affected: `Cycle`, `DoEntry` (L589).

**P1-6 · R25 revenge purely in memory — gone after a restart** (P8-03 / FTMO-5) — `g_revSym/Dir/Time` (L93-95) without GV persistence; with ~per-minute crashes it is effectively never in force. Fix: per symbol `RG_REVDIR_<sym>`/`RG_REVT_<sym>` as GVs; switch `SetRevenge`/`RevengeBlocked` to them; delete expired keys in `Cycle` via a prefix scan. Affected: `SetRevenge`, `RevengeBlocked`.

**P1-7 · R7 naked grace period & 10 s in fast markets** (R7-3) — timestamp/comparison at second granularity (`TimeLocal`, L292/376) + OnTick throttle → real exposure ~11 s, precisely during news/high volatility. Fix: measure with `GetTickCount()`, default grace 3-5 s, grace=0 while `InNewsBlackout()`, decouple the enforce path from the 500 ms entry throttle. Affected: `AddNaked`, `EnforceSLTP`. (The separate crash reset of the grace period is tracked as P2/P8-04.)

**P1-8 · R17 correlation cap ignores ALL cross pairs** (Exposure-F1) — `UsdSign()` returns 0 for EURJPY/GBPJPY/EURGBP → 3× JPY cross long pass R17 uncapped; only R12 heat brakes, without a correlation surcharge. Fix: split the symbol into base+quote, keep a risk vector per currency, apply a net cap per currency; respect broker suffixes (`.m`/`pro`). Affected: `UsdSign`, `NetUsdRiskPct`, `DoEntry` (L576-581).

**P1-9 · R3 day budget is never reduced + too restrictive vs. the docs** (Exposure-F2) — an additive accumulator (intended: "shots per day"), but with scalping it is closed after ~3 trades instead of the documented ~6; that pushes the trader to switch the EA off (an R10 bypass). Fix: resolve the discrepancy 1.5 % vs. 3 % (align default and docs), communicate the scope clearly. (Correct on the code side — primarily tuning/docs.) Affected: `EffDay`, `DoEntry` (L568-570).

**P1-10 · Journal CSV not fit for audit/reconstruction** (R11-1) — `Journal()` (L238/244-246) has no ticket/magic/account/balance/equity/ServerDayKey/structured ruleId/realised net; OPEN↔CLOSE cannot be joined, no drawdown evidence. Fix: extend the signature and the written line, pull the context-free fields inside `Journal()` itself (AccountNumber/Balance/Equity/Server/GMT offset/DayKey), pass `ticket`/`ruleId`/`net` per call site, write a header row when the file is empty. Affected: `Journal`, all 18 call sites.

**P1-11 · Autonomously closing FOREIGN positions (no magic filter)** (FTMO-1) — `SafeCloseAll`/`EnforceRisk`/`EnforceRR`/`EnforceHeat` (L387-464) close/delete every order without checking `OrderMagicNumber()==InpMagic`. Fix: in every loop, directly after the OrderType check, `if(OrderMagicNumber()!=InpMagic) continue;` (L456-457/395/415/439 + the summing functions L481/493/506). Obtain FTMO approval for a self-closing watchdog before going funded. Affected: all enforce functions, `SafeCloseAll`, risk aggregators.

**P1-12 · One-click OrderSend + EA sizing/SL/TP — requires approval before funded** (FTMO-2) — `DoEntry`/`OrderSend` (L587) with a `CalcLot` lot, EA TP, magic 990201; click-triggered, no auto-open. Fix: archive written FTMO approval, demo only until then; optionally an `InpFundedApproved=false` gate before OrderSend. Affected: `DoEntry`, `GateClick`.

**P1-13 · Mac/Wine not acceptable for a real challenge** (P18-1) — a host crash with an open position = an unprotected downtime window (enforce only on ticks). Fix: Windows VPS mandatory from the paid challenge onwards; make sure every tool trade carries a broker-side SL (L587); heartbeat/watchdog (P18-2). Affected: deployment + DoEntry SL.

**P1-14 · Detect-and-revert instead of prevent: a forbidden click fills real risk** (FTMO-6) — manual platform trades bypass the `DoEntry` gates; enforcement reacts tick-driven, and the window is unbounded during tick silence. Fix: move the close enforcer into the timer path (see P0-1), use a dedicated ~200 ms throttle instead of the 500 ms OnTick throttle; point the trader to the tool buttons + VPS/FTMO server-side limits; keep the documented limitation. Affected: `Cycle`, `InpMinActionMs`.

### P2 — Medium (correctness/robustness gaps, conditional)

- **P2-1 · net==0 does not reset the loss streak** (F9/P9-3) — no `else` branch for `net==0` (L257/265). Fix: define a loss as `OrderProfit() < -(|Comm|+|Swap|)`; treat break-even as deliberately neutral. The current behaviour is conservative. Affected: `ResolveClosed`.
- **P2-2 · EA outage overnight → stale day base** (F5) — `RollNewDay` catches the date change up late; the lock part of the finding is refuted (`GV_LOCK_UNTIL=NextServerMidnight` expires correctly). Fix: write `GV_PREV_CLOSE_EQ` continuously and use it on a late roll + warning banner; VPS. Affected: `RollNewDay`, `Cycle`.
- **P2-3 · Day base after a reinit with open positions** (P7-05) — downtime across midnight → the depressed boot equity becomes the base. Fix: persist `RG_LAST_EQ`/`RG_LAST_EQ_DAY` and use them as the base for a skipped day. Affected: `RollNewDay`, `Cycle`.
- **P2-4 · Streak/cooldown/revenge reset on restart** (P5-2) — the capital locks (R4/R4b/R13/R18) survive correctly; only the behaviour-based layer is affected. Resolved together with P0-2 + P1-6. Affected: `g_known`, revenge arrays.
- **P2-5 · R7 naked grace period reset by crash timing** (P8-04) — `g_nakedSince` is in memory → the grace period restarts after a restart. Fix: anchor on `OrderOpenTime()` instead of `TimeLocal()`, compare against `TimeCurrent()` (fail-closed). Affected: `AddNaked`, `EnforceSLTP`.
- **P2-6 · OrderSelect error / history gap → silent under-count** (P9-6) — `ResolveClosed` silently discards unresolved tickets (L254-255). Fix: a pending list with retry; largely resolved by the P0-2 history path. Affected: `ResolveClosed`, `UpdateStreak`.
- **P2-7 · Foreign trades count into the tool's loss streak** (P9-7) — `UpdateStreak`/`ResolveClosed` without a magic filter; a foreign profit resets a legitimate streak. Fix: `if(OrderMagicNumber()!=InpMagic) continue;` in both. Affected: `UpdateStreak`, `ResolveClosed`.
- **P2-8 · Ordering / multi-close determinism** (P9-5) — on a tick with mixed profits and losses, the result depends on the order of `g_known` (overshoot lands conservatively on the stricter level). Fix: process the closes of a tick sorted by `OrderCloseTime`, run the threshold check once afterwards. Affected: `UpdateStreak`, `ResolveClosed`.
- **P2-9 · R16 session/news only blocks the tool button, closes nothing** (R16-1) — `OffSession()` is only an entry gate (L538); manual platform trades are uncovered. Off by default. Fix: sharpen the panel warning, optionally `InpFlatInNews`. Affected: `Cycle`, `DrawPanel`.
- **P2-10 · News blackout is only a daily HHMM window without a date** (R16-2) — single events (NFP/FOMC) cannot be expressed. Fix: a dated window list, medium term a calendar feed. Affected: `InNewsBlackout`.
- **P2-11 · F6/F7/F8/F11 (documentation bundle P2):** two midnight definitions (F6), R19 de-risk does not couple the caps to `EffectiveRiskPct` (F7 — twice the number of trades per idea after a de-risk), R3 tracks planned rather than executed rp (F8), R3 does not capture manual orders (F11). In each case documentation/tuning fixes as stated in the findings.
- **P2-12 · Exposure-F3/F4/F5/F6/R7-4/R11-2:** EnforceHeat closes the newest instead of the riskiest position (F3), naked trades count as 0 heat (F4), R13 giveback includes the floating peak → false positives (F5), R2 only captures identical symbols (F6), R7 does not distinguish a modify error from "no SL" (R7-4), journal time base inconsistent + no FILE_SHARE/integrity hash (R11-2).
- **P2-13 · RR/tick value P2 (Risk-F4/F5):** R8 measures RR without spread/commission/slippage (F4), entry rp underestimates the worst-case distance (F5) → R2/R3/R12 slightly too loose.

### P3 — Low (documentation/hygiene/rare edge cases)

- **P3-1 · F3 refuted — the midnight arithmetic already uses broker server time** (confirmed=false). No arithmetic rebuild; only make the assumption "broker==CE(S)T" visible via an `OnInit` offset log / `InpAssertCetServer`.
- **P3-2 · F4 refuted — base=`AccountEquity()` at the moment of the roll is FTMO-compliant** (confirmed=false). Factoring the floating P/L out of the base would actively introduce a mis-measurement. Purely a risk-comfort option `InpForceFlatBeforeMinutes`.
- **P3-3 · FTMO-3 refuted — the day lock is timestamp-gated, not a tick counter; it triggers correctly** (confirmed=false). Advisory: verify broker server time alignment, VPS.
- **P3-4 · P9-4 refuted — `Cycle(false)` in `OnInit` already seeds g_known from the open tickets** (confirmed=false). The proposed seed is a no-op; the real gap is the offline close (= P0-2).
- **P3-5 · Risk-F1 downgraded — `NormalizeDouble(lot,2)` only causes harm with step<0.01** (confirmed=false). US30/GER40/XAUUSD are unaffected. Optionally step-compliant rounding with `lotDigits`.
- **P3-6 · Version inconsistency v0.12 vs v0.14 + R25 missing from the header** (FTMO-4/F4 doc) — introduce `#define EA_VERSION` and feed header/print/panel from it.
- **P3-7 · Documentation contradictions (F1-F5, R9-10, FTMO-7/9):** RULES.md fixed caps vs. the AutoScale default; RULES-DETAILED.md mixes 0.25 % / 0.5 %; R19 0.5%→0.25% vs 0.125 %; implemented rules listed as "open"; the compliance classification order-active vs passive is missing. → RULES.md at v2 as the single source of truth, derive the others from it.
- **P3-8 · P8-07/P8-08:** `ObjectsDeleteAll(0,"RG_")` is dead code (the objects are prefixed `MMT_`) → a stale SL line survives a chart change; make the "restart-proof" claims in the documentation more precise.
- **P3-9 · Risk-F2/F3/F6:** `MODE_TICKVALUE` without an account-currency check (EUR account, USD/JPY symbols) and a CFD pip heuristic (`Pip()` derived from Digits) → sizing is inaccurate depending on currency/CFD; give `MarketInfo`-returns-0-on-first-tick its own message.

---

## 3. Answers to the 20 review questions

1. **Is the detect-and-close buffer sufficient?** No. R4b is a trigger without a buffer, and the close hangs on ticks (P0-6/P4-1, P1-1/P4-2). 6 % + a soft gate are needed.
2. **Is the no-override (R10) effective?** No — trivially bypassable, not fail-closed (P0-7/P5-1).
3. **Mac/Wine vs. VPS?** VPS mandatory from funded onwards; a Wine crash = a downtime hole (P1-13/P18-1).
4. **Persistence across restarts?** Capital locks yes (GVs), discipline layer no (P0-2/P6-01, P1-6/P8-03, P2-4/P5-2).
5. **Is the R3 day budget correct?** The logic is conservative, but there is crash under-counting (P1-5/P7-02) plus it is too restrictive / inconsistent with the docs (P1-9/Exposure-F2).
6. **Is the loss definition correct?** No — EA closes (P0-3/P9-1), partials (P0-4/P9-2), net==0 (P2-1/F9), foreign trades (P2-7/P9-7).
7. **Is day-start equity FTMO-compliant?** No — bare equity instead of `max(Balance,Equity)` (P0-5/F1) + the first-start snapshot (P1-2/P4-3).
8. **Overnight protection for R4?** Including the floating P/L in the base is FTMO-correct (P3-2/F4 refuted); the real risk is timing/downtime (P0-5, P2-2, P2-3).
9. **Time logic (midnight/week)?** `TimeCurrent` instead of `TimeTradeServer` (P1-4/F2); the arithmetic itself is correct (P3-1/F3 refuted); WeekIdx Thursday boundary (F6, P2).
10. **Is the risk/lot calculation universal?** No — tick value/account currency + CFD pip (P3-9/Risk-F2,F3); `NormalizeDouble` is uncritical (P3-5/F1 refuted).
11. **Is R8/RR realistic?** Overstated — without spread/commission/slippage (P2-13/F4).
12. **Exposure model (R2/R12/R13/R17)?** R17 ignores crosses (P1-8/Exposure-F1); R2 only identical symbols, heat closes the newest, giveback uses the floating peak (P2-12).
13. **R7 SL/TP obligation?** Incomplete — tick-dependent (P0-1/R7-1), grace reset (P2-5/P8-04), granularity (P1-7/R7-3).
14. **R5/R6/R19/R25 triggers?** They miss downtime closes (P0-2), false-trigger on EA closes (P0-3); revenge is volatile (P1-6).
15. **Lock reaction time ~0.5 s?** No — effectively ~1 s, and unbounded during tick silence (P1-1/P4-2).
16. **R16 session/news?** Tool button only, no close, no date (P2-9/P2-10).
17. **Is the R11 journal fit for audit?** No — core fields missing (P1-10/R11-1), integrity/time base (P2-12/R11-2).
18. **FTMO compliance (auto-close/one-click)?** The magic filter is missing (P1-11/FTMO-1), approval is required (P1-12/FTMO-2); detect-not-prevent (P1-14/FTMO-6).
19. **Version/maturity?** v0.12/v0.14 drift, "ungetestet" (untested) (P3-6); never compiled/tested as a whole.
20. **Do docs match code?** No — fixed caps vs. AutoScale, the R19 value, "open vs implemented" (P3-7).

---

## 4. Test matrix

*(carried over in full — the "cross-cutting notes" are binding during testing)*

**Reference account: 20,000 EUR @ 0.25 %/trade (50 EUR). AutoScale=true. EffIdeaCap(R2)=0.50 %/100 EUR · EffHeat(R12)=1.00 %/200 EUR · EffDay(R3)=1.50 %/300 EUR. RiskTolFactor=1.10. +0.01 % slack in the entry gates.**

| Rule | Test goal | Setup | Expected | Persistence/restart | Key edge cases | PASS criterion |
|---|---|---|---|---|---|---|
| **R1** EnforceRisk L387-405 | foreign position with rp>0.275 % is closed | manual EURUSD position, SL set, rp=0.40 % | OrderClose, `CLOSE…rp=0.40 "R1 Risiko zu gross"` (R1 risk too large) | no state; re-enforce on 1st Cycle after restart | 0.27 %→stays; 0.28 %→close; sl==0→continue (R7) | only >0.275 % is closed |
| **R2** entry L564-566 | idea cap per symbol+direction ≤0.50 % | EURUSD BUY #1 0.25 %; #2; #3 | #2 passes, #3 `BLOCKED "R2 Idee-Cap"` (R2 idea cap) | live from orders; block persists after restart | SELL #3→passes; GBPUSD #3→passes; #2 exactly at the limit→passes | >0.51 % in the same direction blocks, cross/opposite direction passes |
| **R3** entry L568-570, GV RG_DAY_RISK | accumulates ≤1.50 %, never decreases | 6× 0.25 % → 1.50 %; then the 7th | 1-6 pass, 7 `BLOCKED "R3 Tagesbudget"` (R3 day budget) | GV survives restart; day change→0 | close before #7→still blocked; de-risk→more trades | the 7th blocks, the block is restart-stable, a day change clears it |
| **R4** Cycle L338-339, RG_LOCK_UNTIL | DD≥2.0 % locks + SafeCloseAll | DAYSTART 20000, eq≤19600 | IsLocked, SafeCloseAll, entries BLOCKED, panel "GESPERRT" (locked) | GV survives; until server-time midnight | 1.99 %→no lock; recovery after the lock→stays; RollNewDay sets LOCK_UNTIL=0 | triggers at 2.0 %, closes everything, expires correctly |
| **R4b** Cycle L336-337, RG_HARD_LOCK | DD≥8.0 % vs INIT_BAL → permanent | INIT_BAL 20000, eq≤18400 | IsLocked permanently, SafeCloseAll, panel "MAX-LOSS" | GV, NOT in RollNewDay → survives everything | 7.99 %→no lock; recovery→stays; verify the INIT_BAL base | 8.0 % is permanent, NO auto reset |
| **R5** ResolveClosed L263, RG_COOLDOWN | 3 losses<5 → 45 min cooldown | CONSEC 0; 3 closes with net<0 | entry BLOCKED, panel "COOLDOWN", notify R5 | GV survives; until TimeCurrent<COOLDOWN | net==0→neither increment nor reset; 2 losses+1 win→0; day change→0 | from the 3rd loss a 45 min block, GV restart-stable |
| **R6** ResolveClosed L262, RG_LOCK_UNTIL | 5 losses → day lock | CONSEC 0; 5× net<0 | IsDayLocked, SafeCloseAll, notify R6 | LOCK_UNTIL+CONSEC GVs survive | #5 takes only the lock branch (no cooldown); 4L+1W+1L→no lock | exactly 5 uninterrupted losses lock |
| **R7** EnforceSLTP L354-385, g_nakedSince | tool naked immediately, foreign after 10 s | A remove the tool SL; B foreign position without SL | A closed immediately; B closed after ≥10 s | g_naked in memory → the foreign grace period restarts after a restart | only TP missing→counts as naked; SL re-set→no close; TimeLocal basis | tool immediately, foreign at exactly 10 s |
| **R8** EnforceRR L407-428 | RR<1.49 is closed | SL 20 / TP 25 pips → 1.25 | OrderClose `"R8 CRV 1.25 < 1.50"` (R8 risk/reward 1.25 < 1.50) | no state; re-enforce after restart | 1.50→stays; 1.49→close; TP/SL==0→continue; MinRR=0→off | only <1.49 is closed |
| **R12** entry L572-574 + EnforceHeat L430-448 | heat ≤1.00 % (gate) / close >1.10 % | 4× 0.25 %=1.00 %; #5; foreign→1.20 % | #5 BLOCKED; the monitor closes the NEWEST until ≤1.10 % | live; consistent after restart | the gate is stricter than the monitor; sl==0→0 heat; 1 close per Cycle | >1.01 % blocks, >1.10 % closes iteratively |
| **R13** Cycle L321-330 | (a) +3 %→TARGET_HIT (b) giveback arm 1 %/drop 1 % | (a) eq≥20600 (b) peak 20300→20100 | (a) BLOCKED R13 day target (b) lock + SafeCloseAll | GVs survive; reset on day change | giveback requires !IsLocked; arm 0.99 %→no; drop/base | +3 % blocks until the day change, giveback only after arming |
| **R14** entry L540-545, RG_LAST_ENTRY | gap ≥10 s | trade→LAST_ENTRY; a 2nd within <10 s | BLOCKED "noch N s" (N s remaining); ≥10 s allowed | GV, NOT in RollNewDay → survives restart and day change | MinGap=0→off; LAST_ENTRY=0→passes; exactly 10 s→allowed | <10 s blocks, ≥10 s passes |
| **R15** entry L556-562 | (a) SL<5 pips blocks (b) lot>MaxLot is capped | (a) 3 pips (b) MaxLot 0.10 | (a) BLOCKED R15 (b) lot=0.10, rp recomputed | no state | MinStop=0→off; broker StopLevel notify only; capping below MinLot→no trade | <5 pips blocks, MaxLot caps and rp follows |
| **R16** entry L538, OffSession | blocks outside session/news | session 8-22 @23h; news 1400-1500 @14:30 | BLOCKED, panel "AUSSER SESSION" (outside session) | no state; time-based | Start==End→always in session; over-midnight; From==To→no blackout | outside blocks, over-midnight handled correctly |
| **R17** entry L576-581, NetUsdRiskPct | \|net USD\| ≤1.5 % | USD long up to 1.50 %; +0.25 % | BLOCKED "R17 Korrelation" (R17 correlation) | live; consistent after restart | opposite directions net out; non-USD→0; USDJPY sign 0; CorrCap=false→off | >1.51 % blocks, netting correct, non-USD ignored |
| **R18** Cycle L309-319, RG_WEEK_* | weekly DD≥5 % locks | WEEKSTART 20000, eq≤19000 | IsWeekLocked, SafeCloseAll, panel "WOCHE GESPERRT" (week locked) | GV, NOT in RollNewDay → persists across days | 4.99 %→no lock; week change (Thu 00:00 UTC)→free; double-lock protection | 5 % locks, a day change does NOT release, a week change does |
| **R19** EffectiveRiskPct L201-206 | from 2 losses onwards risk ×0.5 | CONSEC=2; a normal trade | lot halved, rp≈0.125 %, `OPEN rp≈0.12` | RG_CONSEC GV → de-risk active after restart | C=1→full; a win→0; Factor=1.0→off; half below MinLot→no trade | from 2 losses exactly 0.125 % |
| **R25** entry L539, RevengeBlocked | counter-trade blocked for 10 min | EURUSD BUY with net<0; SELL within <10 min | BLOCKED "R25 Revenge" | g_rev in memory → GONE after restart (FAIL if persistence is required) | same direction allowed; different symbol; >10 min free; net==0→no SetRevenge | opposite direction blocks, document the restart loss |

**Cross-cutting obligations:** The gate order in `DoEntry` (AutoTrading→lock→TargetHit→cooldown→OffSession→revenge→MinGap→SL line/side/broker→MinSL→lot/MaxLot→idea→day→heat→correlation→OrderSend) — later gates are only testable if the earlier ones pass. Test the two midnight definitions (ServerDayKey vs NextServerMidnight) explicitly. The net==0 gap (R5/R6/R19/R25). RG_DAY_RISK is additive. Identify the version from the print string.

---

## 5. DECISION

**C) Not safe enough for FTMO.**

Rationale: Seven P0 defects hit all three load-bearing pillars of the tool simultaneously — (a) the protection does not close reliably (P0-1: enforce only on ticks; P0-6: an 8 % trigger without a buffer), (b) the discipline bookkeeping is wrong/volatile (P0-2: downtime closes missed; P0-3: the tool's own closes counted as losses; P0-4: partials double-counted; P0-5: a non-FTMO-compliant day base), and (c) inescapability does not exist locally (P0-7). The header itself says "NUR DEMO / UNGETESTET" (demo only / untested), and the EA has never been compiled or tested as a whole. A tool whose sole purpose is risk enforcement, and which loses exactly that enforcement on the documented target platform (Wine, crashes roughly every minute), must not touch a real or paid FTMO account. After the P0+P1 patches are worked off, after a move to a Windows VPS, and after a green Strategy Tester run over the complete rule matrix, "A) ready for testing" is reachable — it is not reached today.

---

## 6. Concrete patch order for v0.15

1. **`MathMax(AccountBalance(),AccountEquity())` in `RollNewDay` L165/L171** (P0-5) — an FTMO-compliant R4 base; an isolated two-line fix and the foundation of every DD measurement.
2. **Decouple enforcement from the `allowTrades` gate, `OnTimer→Cycle(false,true)`** (P0-1, P1-1, P1-14) — the watchdog runs independently of ticks; a fundamental protection path that otherwise blocks all close tests.
3. **`g_eaClosed[]` exclusion list + `TakeEaClosed` in `ResolveClosed`** (P0-3) — prevents the self-punishment cascade; must come BEFORE the history rebuild, because that rebuild uses the same close paths.
4. **History-based, idempotent loss resolution (`RG_LAST_CLOSE`, MODE_HISTORY, CloseTime sorting, `ApplyConsecThresholds`)** (P0-2, P0-4, P1-3, P2-6, P2-8) — replaces g_known; fixes downtime, partials and determinism in one go. Depends on patch 3 (EA close detection).
5. **Magic filter in `UpdateStreak`/`ResolveClosed` + all enforce loops + the risk aggregators** (P2-7, P1-11) — manage/count only the tool's own trades; FTMO compliance + clean streak accounting.
6. **R4b: `InpMaxLossPct` 8→6 + an `InpMaxLossWarnPct` entry gate in `DoEntry`** (P0-6) — a proactive buffer; independent, can be added after the streak fixes.
7. **Persistent lockstate file (HMAC, fail-closed) in `OnInit`; mirror revenge/streak** (P0-7, P1-6) — hardening the no-override; builds on the now-correct streak persistence (patch 4).
8. **`GV_DAY_RISK` reconciliation (`max(persisted, OpenedTodayToolRiskPct())`) + `GlobalVariablesFlush()` after L589** (P1-5) — closes the crash under-counting of R3.
9. **Time source `TimeCurrent`→`TimeTradeServer` (L98/99/100 + the lock checks)** (P1-4) — a reliable day change without ticks; isolated, low risk of collisions.
10. **R7 naked: anchor on `OrderOpenTime()`, `GetTickCount` granularity, grace 3-5 s, news grace 0** (P1-7, P2-5) — crash-immune, faster SL obligation.
11. **R17 real currency-vector exposure (base+quote, cross pairs)** (P1-8) — closes the largest exposure hole; a larger, self-contained rebuild.
12. **Extend the journal signature (ticket/magic/account/balance/equity/DayKey/ruleId/net) + FILE_SHARE** (P1-10, P2-12-R11-2) — audit readiness; touches all call sites, hence late.
13. **`#define EA_VERSION`, align header/print/panel, R25 in the header** (P3-6) + RULES.md v2 as the source of truth (P3-7) — version/documentation hygiene before any release communication.
14. **Deployment: Windows VPS + heartbeat; obtain written FTMO approval for auto-close/one-click; `InpFundedApproved` gate** (P1-13, P1-12) — the operational closing steps; only meaningful once the code is green.
15. **Remaining P2 items (net==0 tolerance, R8 net RR, EnforceHeat=riskiest position, giveback on closed equity, session/news hardening, tick value conversion)** — polishing after the blockers; depending on what the remaining tests find.
