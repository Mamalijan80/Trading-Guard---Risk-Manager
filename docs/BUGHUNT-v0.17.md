# Bug Hunt v0.17 — Findings (2026-06-27)

Multi-agent bug hunt (10 hunter lanes + 2 deep dives, 2 independent skeptics per candidate). 31 candidates → **20 confirmed, 4 probable**. Line numbers refer to the state of the code at the time of the hunt.

> **✅ FIXED in v0.18 (adversarially verified, 0 issues, brace sanity 247/247 1779/1779, F7 pending):** B1, B2, B3 (+B9 warning), B4+B6, B5+B8, B16, B17, B20. The fix-verify workflow confirmed for each fix: correct + valid MQL4 (`MqlDateTime`/`day_of_week` explicitly checked) + no regression.
> **✅ FIXED in v0.19 (static review batch, fix-verified, F7 pending):** **B11** (R1 uses a stable daily base instead of live equity), **B19** (SplitCcy ISO check), **L4** (net==0 resets the streak) — **plus new review findings:** P0 SafeCloseAll vs TOOL_ONLY (warning when foreign positions are open while locked), P0 division by 0 when `g_initialBalance<=0` (TotalDDpct guarded + fail-closed), P0/P1 prop-firm time profile (`InpDayResetHour`/`InpWeekStartDay`), P1 ResolveHistory sorted chronologically, P1 `ERR_MARKET_CLOSED` 15-minute backoff (no request storm), P1 `InpRR<InpMinRR` hard-clamped.
> **⏳ OPEN (to be proven in the rule test matrix):** B7 (PC timezone when `TimeCurrent==0`), B10 (HasOpenRemainder same-second), B12, B13, B15 (RollNewDay before ResolveHistory), B18 (throttle on context busy), L3 (FILE_SHARE with multiple charts). *Reason for deferral: low probability of occurrence, or a semantic decision that is better settled by observing live behavior.*
> **Semantics note B4/6:** On a mixed close (trader part + EA remainder), deliberately ONLY the net portion closed by the trader counts toward streak/cooldown/revenge (a discipline tool judges the trader's decision, not the position's P/L).

Severity legend: 🔴 critical · 🟠 high · 🟡 medium · ⚪ low

---

## 🔴 CRITICAL

### B1 — Max-loss base is tied to the default 20000 → R4b protection silently disabled on non-20k accounts
**Where:** `OnInit` (g_initialBalance selection) → `TotalDDpct()` → R4b hard lock + warning gate.
**Problem:** `InpInitialBalance` has the default **20000** (always >0), so `if(InpInitialBalance>0) g_initialBalance=InpInitialBalance;` ALWAYS wins; the fallbacks (GV_INIT_BAL / AccountBalance) are dead code. g_initialBalance is the base of the total drawdown.
**Trigger:** Any account ≠ 20,000 € without setting the value manually. **100k account at 95k (5% in reality) → TotalDDpct = (20000−95000)/20000 = −375% → clamped to 0 → R4b NEVER fires** (main protection off). **10k account → DD overestimated by ~2× → false lock** from the very first tick.
**Fix:** Default `InpInitialBalance=0` (→ real account base via GV_INIT_BAL/AccountBalance) **plus** a loud warning when an explicitly set value deviates strongly from AccountBalance.

---

## 🟠 HIGH

### B2 — R18 weekly limit resets in the middle of the week (Thursday 00:00)
**Where:** `WeekIdx()` = `SrvTime()/(7*86400)` (epoch grid = Thursday boundary); weekly reset in `Cycle()`.
**Problem/trigger:** Wednesday night at −4.9% (just under 5%) → Thursday 00:00 the weekly base and the weekly lock are reset → another full 5% is possible Thu–Fri → in reality ~10% weekly loss without R18 ever kicking in. Conversely: a lock set on Tue/Wed is lifted on Thursday 00:00.
**Fix:** Anchor the week at the real weekend, e.g. `WeekIdx(){ datetime t=SrvTime(); return (long)(t/86400) - TimeDayOfWeek(t); }` (Sunday-midnight boundary).

### B3 — R8 (EnforceRR) closes freshly opened tool trades because of fill slippage
**Where:** `EnforceRR()` vs `DoEntry()` TP calculation.
**Problem/trigger:** The TP is set at the *requested* entry, but the risk/reward ratio is computed from `OrderOpenPrice()` (the actual fill). With a tight stop plus slippage the RR can fall below InpMinRR → the in-plan trade that was just opened is immediately closed again.
**Fix:** Exempt tool trades (`Magic==InpMagic`) from R8 (they are RR-compliant by construction) — together with B9 (validate InpRR≥InpMinRR).

### B4 + B6 — A partial close by the trader is mislabeled as an EA close → the loss drops out of the streak
**Where:** `ResolveHistory()` `gEa` aggregation (OR semantics) + skip.
**Problem/trigger:** All partial closes of a position are grouped; `gEa` becomes TRUE as soon as **one** leg carries an EA marker → the WHOLE group counts as an "EA protective close (does not count)". If the trader closes one part at a loss and the EA closes the remainder → the trader's loss disappears from cooldown/streak/revenge.
**Fix:** Sum EA net and manual net **separately** per group; run `ApplyResult` on the manual portion and exclude only the EA portion.

### B5 + B8 — EA close marker: false-negative unmark + mark-before-close window → a protective close counts as a trader loss (false lock)
**Where:** `ProcessCloseQueue()` (MarkEaClosed before OrderClose; UnmarkEaClosed when OrderClose==false).
**Problem/trigger:** (B5) OrderClose can return `false` even though the position did close server-side (requote/timeout) → the code unmarks it → a genuine EA close counts as a trader loss → wrong daily lock/cooldown. (B8) Mark-before-close crash window → a real loss may be excluded as an EA close.
**Fix:** Set the marker only **after a confirmed** close: OrderClose→true → MarkEaClosed; OrderClose→false → reselect the ticket, and if `OrderCloseTime()!=0` (it did close after all) → MarkEaClosed + remove, otherwise retry without a marker. Remove the pre-mark and the unmark-on-fail.

---

## 🟡 MEDIUM

### B7 — Locks/day keys in the PC timezone when `TimeCurrent()==0` at OnInit
**Where:** OnInit + the `SrvTime()` fallback. A brand-new chart without a quote → offset unset → SrvTime = PC time (local TZ) → day keys/locks are wrong and jump on the first tick.
**Fix:** Run heavy init (RollNewDay/Reconcile/GV_LAST_CLOSE seed) only once server time is known (`g_srvOffsetSet`/TimeCurrent>0); otherwise defer it to the first tick.

### B9 — No `InpRR ≥ InpMinRR` check → open-then-close-immediately loop on misconfiguration
**Where:** OnInit (missing validation); DoEntry TP vs EnforceRR.
**Fix:** Check in OnInit: `InpMinRR<=0 || InpRR>=InpMinRR`; otherwise clamp InpRR upward + notify, or block entries.

### B10 — `HasOpenRemainder` can be a false positive on a same-second re-entry → a real loss is deferred indefinitely
**Where:** `HasOpenRemainder()` matches OpenTime+Type+Symbol+Magic+OpenPrice (not unique).
**Fix:** Tighten identity (entry-ticket lineage per position) instead of relying on the ProcKey fields alone.

### B11 — The live-equity denominator in EnforceRisk closes correctly sized positions when equity drops
**Where:** `EnforceRisk()` via `RiskPctOf()` (denominator AccountEquity). Falling equity raises the measured % risk → R1 closes a position that was correctly sized at open.
**Fix:** Compute R1 enforcement against a stable base (entry equity/DayRiskBase) instead of live equity.

---

## ⚪ LOW (selection)

- **B12** — `nowMs=GetTickCount()` is sampled once before the loop in `ProcessCloseQueue`; after a slow OrderClose the backoff for subsequent tickets is skewed. *Fix:* re-read nowMs on each iteration.
- **B13** — On FINAL-FAIL a still-open ticket is removed from the queue; re-enqueueing depends on the detector. *Fix:* `Notify`/alert on FINAL-FAIL (not just the journal).
- **B15** — `RollNewDay()` (which resets GV_CONSEC) runs BEFORE `ResolveHistory()` → a loss closed shortly before midnight is attributed to the new day and loses cooldown/streak. *Fix:* run ResolveHistory before the consec reset.
- **B16** — `MODE_MAXLOT`==0 from the broker → `if(lot>mx) lot=mx` sets the lot to 0 → entry blocked. *Fix:* `if(mx<=0) mx=lot;`.
- **B17 (+L1/L2)** — The close-queue backoff gate uses the non-wrap-safe comparison `nowMs < g_qNextMs[i]`; on a GetTickCount wrap (~49.7 days) the close freezes. *Fix:* wrap-safe `(int)(nowMs - g_qNextMs[i]) < 0`.
- **B18** — `g_lastEnforceMs` is consumed even when `IsTradeContextBusy` blocks everything → the 300 ms window is wasted. *Fix:* set the throttle only when enforcement actually happened.
- **B19** — `SplitCcy` puts 6-letter non-FX symbols into phantom currency buckets (R17). *Fix:* currency-code plausibility/FX check before the split.
- **B20** — `OnInit` `ObjectsDeleteAll(0,"RG_")` uses the wrong prefix; panel objects are named `MMT_` → the cleanup is a no-op. *Fix:* `ObjectsDeleteAll(0,PFX)`.
- **L3** — Journal/lockstate `FileOpen` without `FILE_SHARE_*` → with several charts on the same account, writes/reads are lost. *Fix:* `FILE_SHARE_READ|FILE_SHARE_WRITE`; treat an empty read as "busy" rather than "CORRUPT".
- **L4** — `ApplyResult` treats `net==0` (break-even) as neither a reset nor a loss → the streak stays unchanged. *Fix:* make the `net>=0` semantics explicit.

---

## Assessment
None of these bugs prevents compilation (F7=0) — they are **runtime/logic bugs**, exactly the class that F7 does not catch and that tests/reviews do. **B1 (critical)** and **B2/B4+B6/B5+B8 (high)** directly affect money/protection and should be fixed before any demo test.
