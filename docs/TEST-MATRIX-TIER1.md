# Tier-1 Rule Test Matrix — Mamal-Trading

_As of: 2026-07-20, against EA v0.35 (R22 "Nur Panel-Trades" / panel trades only + persistent R7 grace + healing period). Order = liability risk (axis 3), descending. Test on **demo** only. Check off: ☐ open · ✅ passed · ❌ bug._

> **Ground rule:** Every test is a promised feature. Anything marked ❌ here you may NOT promise in marketing until it is ✅.

**Configuration decision made:** PATH 1 — `WatchScope=TOOL_ONLY` stays. The tool monitors **panel trades only** (Magic 990201). Manual/mobile trades (Magic 0) are therefore outside **scope monitoring** (R7 SL check etc.) → customer's responsibility (see below). No FundedMode rebuild. **⚠ Since v0.35 this is only half the truth** — R22 closes Magic-0 trades anyway, see the addendum directly below.

**Addendum v0.35 (R22):** The scope stays `TOOL_ONLY`, but `InpCloseManualTrades=true` (default) closes manual trades (Magic 0) regardless — **account-wide across all symbols**, in FundedMode too. R22 is the only enforcement function that bypasses `InScope()` (magic comparison instead of scope check). The scope gap described below therefore only applies with `InpCloseManualTrades=false`.

---

## R7 behavior in v0.34 (your core feature)

- `InpRequireSL=true`, `InpRequireTP=true` → an in-scope trade is "naked" when **SL OR TP** is missing.
- **4 s grace from the moment of removal** (not from trade opening). The clock starts as soon as the tool sees the trade naked for the first time. Re-setting SL/TP within those 4 s → **no** close.
- **v0.34 — persistent clock + healing period:** the clock is stored per ticket in GlobalVariables (`RG_NK_<ticket>`) and survives **terminal restart, recompile, timeframe change and master handoff** (previously each of these cases granted a fresh grace period). It is only deleted once SL/TP have been set for **60 s in a row** (`RG_NKH_<ticket>`); if you go naked again before that, the healing period is forfeited and the **old** clock keeps running. So a brief SL toggle does not buy a new grace period.
- **v0.34 — tighten-only:** `InpRequireSL`/`InpRequireTP` can no longer be switched off intraday once active (`EffRequireSL()`/`EffRequireTP()`); loosening only takes effect at the day rollover.
- Applies **uniformly to panel trades as well** (no more instant close).
- After expiry **the trade is closed** — MT4 stays alive.
- News blackout: `InpSLTPGraceNews=0` → immediate close.
- Note: the modify-quiet window (2 s crash protection) pushes the clock start until after the last manual drag — in practice ~4 s _after you stop dragging_.

---

## Test 0 — CRASH REGRESSION (the blocker, v0.31 fix)

Without this ✅ everything else is worthless.

| # | Setup | Steps | Expected | Status |
|---|---|---|---|---|
| 0.1 | Panel trade open, SL removed (→ R7 wants to close) | During the 4 s grace period **keep dragging/modifying the SL/TP line** | **No MT4 crash.** Modify-quiet defers, then a clean close. | ☐ |
| 0.2 | Any trade | Move TP, release, immediately move again (several times, fast) | No crash; panel stays responsive. | ☐ |
| 0.3 | Close a trade manually while the tool cycle is running | Close the position in the terminal window | No crash (cause in v0.31: OrderClose inside user modify). | ☐ |

**If 0.x is ❌:** stop — back to reentrancy. No business step before that.

---

## Test 1 — R7 SL/TP requirement + 4 s grace (core promise)

| # | Setup | Steps | Expected | Status |
|---|---|---|---|---|
| 1.1 | Panel BUY with SL+TP | open normally | stays open | ☐ |
| 1.2 | Panel trade | remove SL, **do nothing** | close after ~4 s, journal "R7 SL/TP fehlt (Ns nach Entfernen, Grace 4s)" (R7 SL/TP missing, Ns after removal, grace 4s) | ☐ |
| 1.3 | Panel trade | remove SL, **re-set it within 4 s** and **leave it set** (> 60 s) | **no** close; after 60 s the clock is cleared (`RG_NK_`/`RG_NKH_` gone) | ☐ |
| 1.3b | Panel trade | remove SL, **briefly re-set it within 4 s and immediately remove it again** (toggle, clearly under 60 s) | **close happens** — the healing period is forfeited, the **old** clock kept running; no grace reset via toggle (v0.34) | ☐ |
| 1.3c | Panel trade **naked** (SL removed), grace period running | **restart the terminal** / recompile / change timeframe, then do nothing | grace period **continues instead of starting over** → close immediately after restart (the clock lives in `RG_NK_<ticket>`) | ☐ |
| 1.3d | Panel trade open with SL+TP | set `InpRequireSL=false` and re-initialize the EA (intraday) | SL requirement stays **active** (tighten-only); switching it off only takes effect after the day rollover | ☐ |
| 1.4 | Panel trade | remove **TP**, do nothing | close after ~4 s (RequireTP=true) | ☐ |
| 1.5 | Manual trade **without SL** (`TOOL_ONLY`, funded default), **`InpCloseManualTrades=false`** | open, wait | **is NOT closed** (R7 scope gap — customer's responsibility) | ☐ |
| 1.5b | same with the R22 default **`InpCloseManualTrades=true`** | open, wait | trade **is** closed — but because of **R22**, not because of R7 (R7 still does not check it) → see Test 1b | ☐ |
| 1.6 | Panel trade, news blackout active | remove SL | **immediate** close (grace 0 during news) | ☐ |

## Test 1b — R22 "Nur Panel-Trades" (panel trades only) (v0.35, new)

_Placed directly after R7: R22 is the only rule that closes positions the EA **did not open itself** — liability risk is correspondingly high (a false trigger costs real money)._

**Precondition for every test in this block (otherwise nothing happens):** AutoTrading on, EA is the **confirmed master instance** (at least 2 cycles in a row — R22 does not act on a passive secondary instance), `InpMagic=990201` (default), market open. Default `InpCloseManualTrades=true`.

| # | Setup | Steps | Expected | Status |
|---|---|---|---|---|
| 1b.1 | `InpCloseManualTrades=true` (default), no lock | Open a manual **market trade** via the MT4 order window (F9), do nothing else | Position is closed **within ~1 s** (timer 1 s + close throttle 300 ms). Journal line with reason **"R22 Manueller Trade — nur Panel-Trades erlaubt"** (R22 manual trade — only panel trades allowed), tag `Queue OK (Versuch 1): R22 …`. | ☐ |
| 1b.2 | **Active day lock** (R4 triggered, e.g. via Test 3.1), `WatchScope=TOOL_ONLY` | Open a manual market trade | Trade is **closed as well** — R22 runs in the enforcement block **before** the lock branch. (Up to v0.34 there was only a warning max. 1×/60 s here and the trade stayed open.) | ☐ |
| 1b.3 | `InpCloseManualTrades=true` | Place a manual **pending order** (buy limit/stop) at a clear distance from the market | Pending is **deleted via `OrderDelete()` before it can fill**. Reason "R22 Manuelle Pending-Order — nur Panel-Trades erlaubt" (R22 manual pending order — only panel trades allowed), tag `Queue DELETE ok: R22 …`. | ☐ |
| 1b.4 | Manual position open, **EA removed from the chart** | Drag the EA onto the chart again | Startup message (notify + journal event `INFO`) **states the count**: "R22 Start: N manuelle Order(s) vorgefunden -> werden geschlossen" (R22 start: found N manual order(s) -> will be closed) — **no grandfathering**. The close does **not** happen in `OnInit`, but only in the 2nd/3rd cycle (master streak ≥2), so typically 1–3 s later. | ☐ |
| 1b.5 | _(optional, only if a second EA is available)_ Foreign EA with **its own magic ≠ 0** on a second chart | Let the foreign EA open a trade | Trade stays **untouched** — R22 skips everything with `OrderMagicNumber() != 0`. | ☐ |
| 1b.5b | _(configuration trap, demo only)_ set `InpMagic=0` | Click panel BUY | The **EA's own panel trade** is cleared away by R22 (the distinction rests solely on `Magic != 0`, there is no code safeguard against this). Expectation = confirm this behavior, then reset `InpMagic`. | ☐ |
| 1b.6 | **`InpCloseManualTrades=false`** | Open a manual market trade; then load the cockpit dashboard | Trade **stays open**; the cockpit lists **R22 as disabled** ("— aus" / off chip from the `disabled` list). The R7 scope gap (Test 1.5) applies again. | ☐ |
| 1b.7 | Cockpit after exactly **one** manual trade from 1b.1 | Open "Deine Schwächen" (your weaknesses) | R22 shows up (mapping only via the cockpit fallback `ruleFromTag()`; the EA's RuleId column stays **empty** for R22). **Known limitation:** every retry, every FINAL-FAIL and every discard produces its own CLOSE line → the counter can count **one** manual trade several times. A number > 1 is **not** a bug here. | ☐ |

**Honest limits of R22 (these belong in onboarding, do not argue them away):**

- **Detect-and-revert, not prevention.** R22 does not stop the trade — it is opened and then closed again **at market price**. Spread and slippage (`InpSlippage`) are borne by the trader. The reason for the rule is the inverse argument: only the panel path (`DoEntry()`) passes the entry gates R4b, R13, R5, R16, R25, R14, R7, R15, R1, R2, R3, R12, R17 — a manual trade bypasses all of them.
- **Detection latency, no fixed number.** Cadence: timer 1 s or tick ≥500 ms, plus close throttle 300 ms, plus possibly up to 2 s of **modify-quiet** (whoever keeps dragging SL/TP delays R22 — hard-capped at a 10 s series), plus backoff on failed attempts. Realistically: **fractions of a second up to several seconds.** With the market closed (error 132) up to **15 min** per attempt.
- **A pending order placed right at the market can fill faster than R22 sees it.** Then 1b.3 does not apply, but 1b.1 does — the resulting position is closed.
- **No protection without a running EA.** EA not on the chart, AutoTrading off, passive instance or a failed `EventSetTimer` → R22 has no effect.
- **Failed attempts stay open.** After 5 attempts (`InpCloseRetries`) the ticket drops out of the queue with FINAL-FAIL and the order **stays open** — but it is queued again on the next pass.
- **Losses count asymmetrically.** A manual trade closed by R22 does **not** feed into R5 cooldown, R6 loss streak, R19 de-risk, R25 revenge, and consumes **no** R3 daily budget (both evaluations filter on in-scope or `InpMagic`). The realized loss does, however, very much hit the equity-based limits **R4, R4b and R18**.
- **R22 does not appear in the on-chart panel** — feedback comes only via notify, journal and cockpit.
- **Check compliance per firm.** The EA also closes positions it did not open itself in FundedMode. Whether the respective prop firm permits this must be clarified **before** live use; the existing warning about `ALL_POSITIONS` does not cover this case.

## Test 2 — R1 risk per trade

Close when risk(SL) > `InpRiskPerTradePct`×`InpRiskTolFactor` (0.25 %×1.10 = **0.275 %**). Only trades **with** an SL.

| # | Setup | Expected | Status |
|---|---|---|---|
| 2.1 | Trade with SL, risk ~0.2 % | stays | ☐ |
| 2.2 | Trade with SL, lot too large/SL too wide → risk ~0.5 % | close "R1 Risiko zu gross (…%)" (R1 risk too large) | ☐ |

## Test 3 — R4 day lock & R4b max loss

| # | Setup | Steps | Expected | Status |
|---|---|---|---|---|
| 3.1 | `InpDailyLossPct=0.2` (demo) | Lose down to −0.2 % of the daily base | **Day lock**: SafeCloseAll + NO new trades until midnight | ☐ |
| 3.2 | `InpMaxLossPct=0.3` (demo) | Lose down to −0.3 % overall | **Hard lock** + SafeCloseAll | ☐ |
| 3.3 | A manual (out-of-scope) trade open while locked, **`InpCloseManualTrades=false`** | — | Tool does NOT close it, but warns loudly (1×/min) — `SafeCloseAll()` skips out-of-scope orders | ☐ |
| 3.3b | same with the R22 default **`InpCloseManualTrades=true`** | — | Trade **is closed** (R22 runs before the lock branch) → Test 1b.2 | ☐ |
| 3.4 | Tighten-only: raise `InpDailyLossPct` intraday | — | does NOT take effect immediately (loosening only at the day rollover) | ☐ |

_(Alternatively the test triggers `daylock`/`maxlock` via `InpTestMode=true` — demo only.)_

## Test 4 — Panel BUY/SELL correctness

| # | Setup | Expected | Status |
|---|---|---|---|
| 4.1 | Panel BUY click | Order in the correct direction, SL+TP set, Magic 990201 | ☐ |
| 4.2 | Click on the SL line vs. the button | Button triggers a trade, clicking the SL line does NOT (bounds guard) | ☐ |

---

## Scope gap = honest product limit (path 1)

**As of v0.35 this only applies with `InpCloseManualTrades=false`.** With the default `true`, R22 closes manual trades instead — so the gap is not closed by an SL check, but by the fact that such trades are not supposed to exist in the first place (detect-and-revert, the trader bears the slippage → Test 1b).

Under `TOOL_ONLY` the tool monitors panel trades only. **Manual/mobile trades are not checked for an SL.** This is the precondition the customer has to fulfill themselves:
1. Always set an SL yourself.
2. For every open trade, check yourself that an SL is attached.

→ This must be communicated **clearly** in the terms of service / onboarding / panel. The tool is a safety net for panel trades plus a discipline watchdog, not a replacement for your own SL on manual trades.
