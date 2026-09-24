# Mamal-Trading — Rule Set (full description)

Account reference: **EUR 20,000 (FTMO demo)**, risk/trade **0.25 % = EUR 50** (FTMO-conservative). All values are parameters (inputs) and can be changed. (The EUR amounts of the loss limits R4/R4b/R18 below are independent of the per-trade risk.)

> **All EUR amounts in this document are converted to this 20k reference.** The profile covers 10k/20k/25k; the binding value is always the **percentage**, the EA calculates purely percentage-based against the real account base. Central clarification: [`../RULES.md`](../RULES.md).

## A — Position size & single-trade risk
**R1 — Risk per trade (auto-lot).** You drag the red SL line, the tool calculates the lot size so that your risk (entry→SL) is **exactly 0.25 % = EUR 50**. A monitor continuously checks every open position against the *current* SL: if the risk rises above 0.275 % (e.g. because you drag the SL further away), the position is closed. → kills "sized too big on gut feeling".

**R15 — Min-SL distance + max lot. OFF** (v0.22: M1 scalping needs tight stops; `InpMinStopPips=0`). The optional hard lot cap `InpMaxLot` is also **0 = off**, so by default R15 has no effect whatsoever. Against the extreme form "tiny SL → huge lot → slippage/gap" only the **hard broker minimum distance (`STOPLEVEL`)** remains — plus R1, which caps the lot size at 0.25 % risk. *(Doc correction: this previously said "at least 5 pips, otherwise blocked".)*

## B — Concentration (not everything on one/similar idea)
**R2 — Idea cap.** Same symbol **+** same direction = **one idea**. Sum of the open risk per idea ≤ **0.5 % = EUR 100** (auto-scale: 2× risk/trade) → max. 2 entries of 0.25 % each; the 3rd is blocked. → exactly your "4–5× on the same idea".

**R17 — Correlation cap (currency vector, since v0.17).** Calculates the net risk per **currency** across all positions (each position loads the base currency long / the quote currency short): EURUSD buy + GBPUSD buy = both USD short → they add up; EURUSD buy + USDJPY buy = USD cancels out. Largest |net currency exposure| ≤ **1.5 %**. Cross pairs (EURJPY …) are aggregated correctly; non-FX (US30) as a single bucket. → prevents hidden double risk across correlated pairs.

## C — Daily and total exposure
**R12 — Total risk cap (portfolio heat).** The **simultaneously open risk across ALL positions** combined ≤ **1.0 % = EUR 200** (auto-scale = 2× idea cap; fixed fallback 2 %). A new trade above that is blocked; a monitor closes the *newest* position if the sum is exceeded anyway. → your "unconsciously growing total risk".

**R3 — Daily risk budget.** Sum of the risk **opened** on one day ≤ **2.0 % = EUR 400** (auto-scale = 4× idea cap; ≈ 8 trades) — **v0.20 (was 1.5 %/EUR 300)**, so that R4 (daily loss brake) and the daily target are reachable at all. Winners count too, no "booking back". → limits the number of shots per day.

## D — Loss brakes (escalating)
**R4 — Daily loss hard lock.** If equity falls **−2 % = EUR 400** below the day's start → **all positions monitored by the tool** are closed (in-scope; in funded mode = only own tool trades) + **lock until the daily reset**. Resets daily. Sits below the FTMO 5 % limit. *Note: positions of **foreign EAs** (own magic ≠ 0) outside the scope are NOT closed by `SafeCloseAll` — the EA then warns loudly (close them yourself). **For manual magic-0 trades this no longer applies since v0.35:** R22 clears those away regardless of scope and lock (see R22 below).*

**R4b — Total loss lock.** Equity **−6 % = EUR 1,200** below the starting capital → **permanent** lock (never resets). **Warning gate at −5 % = EUR 1,000** → no new trades. Buffer before the FTMO 10 % maximum loss.

**R18 — Weekly loss limit.** **−5 %** in the current week → **week locked** (until the week rolls over).

**R5 — Cooldown.** **3 losing trades in a row** → **45 min** no new trades.

**R6 — Losing streak lock.** **5 losses in a row** → **day lock**.

**R19 — De-risk ladder. OFF** (by request, v0.20; `InpDeRiskFactor=1.0`). *(Risk stays constant at 0.25 %.)*

## E — Impulse / revenge / FOMO
**R25 — Revenge window. OFF** (by request, v0.20; `InpRevengeMin=0`). *(No counter-trade block; the hard limits R3/R4/R4b/R5/R6 enforce discipline.)*

**R14 — Minimum pause. OFF** (by request, v0.20; `InpMinGapSec=0`). *(No forced pause between trades.)*

**R16 — Session/news lock. Available, default OFF.** Trading only inside the defined time window (`InpUseSession=false` = off) + optional manual **news blackout window** (`InpNewsFrom=InpNewsTo=0` = off). As long as both are unconfigured, the entry gate **never** triggers — so R16 does not count as one of the active rules. *(Automatic news detection needs a calendar feed → coming with server/cockpit.)*

**R9 — Anti-FOMO click gate.** Two-click confirmation with a waiting period. **OFF by your request.**

## F — Securing profit
**R13 — Daily target + giveback protection.** (a) At **+3 % = +EUR 600** on the day → no new trades (open runners keep running). (b) If you were ≥ **+1 %** in profit and give back **1 %** from the day's high → **day locked** (profit secured). → against "giving green days back again".

## G — Execution hygiene
**R7 — SL+TP requirement.** Every position needs **SL and TP**. If one is missing, you have **4 s** to add it (during a news blackout **0 s**), otherwise it is closed. The deadline runs **from the moment SL/TP is missing or was removed** — not from the opening; otherwise an old trade would have no deadline at all after the SL was removed. **Tool trades no longer have an immediate-close special case** — it applies uniformly to every position in the watch scope (default `TOOL_ONLY` = panel trades). **Hardening v0.34:** the clock runs **persistently per ticket** (a GlobalVariable per ticket — it survives terminal restart, recompile, timeframe change and master handoff) and is only deleted after a **60 s grace period** once SL/TP have been set again; if you go naked again before that, the old clock keeps running. So briefly tapping in an SL does not buy you a new deadline. In addition, the SL/TP requirement is **tighten-only**: once active, it cannot be switched off intraday via input — loosening only takes effect at the day change. *(Doc correction v0.33: previously "5 s from opening, tool trade closed immediately".)* **Important:** what gets closed is the **trade** — MetaTrader/the program stays open (no crash; the close runs through the throttled close queue). Dragging the SL **tighter** is allowed; dragging it **wider** is caught by R1.

**R8 — Minimum RRR. OFF** (by request, v0.20; `InpMinRR=0`). *(No minimum-RRR enforcement. The auto-TP of tool trades still targets 2R.)*

**R10 — No override.** No unlock button; locks survive a terminal restart; warning "SCHUTZ AUS" (protection off) when AutoTrading is disabled. *(Locally = strong friction; truly un-bypassable only on a locked-down VPS + FTMO server limit.)*

**R11 — Journal.** Every trade, every block and every rule-driven close is logged as CSV (`MQL4/Files/MamalTrading_Journal.csv`) with a tag (in-plan / which rule). Screenshots optional.

**R22 — Panel trades only (since v0.35).** `InpCloseManualTrades=true` (default). Every order **without** the tool magic (magic 0 = opened by hand in the terminal or in the mobile app) is queued into the close queue: positions are closed at bid/ask with `InpSlippage`, pending orders are deleted. **Account-wide across all symbols**, not just on the EA's chart symbol. Foreign EAs with **their own** magic (≠ 0 and ≠ `InpMagic`) are left untouched. **Why:** only the panel route passes through the entry gates — in order: AutoTrading, lock, base uncertain, R4b warning gate, R13 daily target, R5 cooldown, R16 session/news, R25 revenge, R14 minimum pause, R7 SL line/side, R15 broker `STOPLEVEL`+min SL, R1 lot calculation, R2 idea cap, R3 daily budget, R12 heat, R17 correlation. A manual trade bypasses this whole chain completely; previously, with an active lock under `WatchScope=TOOL_ONLY` (default, and enforced in funded mode), it was not even closed, only flagged once per minute. R22 is the **only** enforcement function that bypasses the `InScope()` filter — it compares the magic directly and therefore also works in funded mode. **Configuration warning:** the distinction hangs solely on "magic ≠ 0". `InpMagic` defaults to `990201`; if someone sets `InpMagic=0`, R22 will clear away **your own panel trades** — there is no protection against that in the code.

**R22 — what it *cannot* do (honest limits).** It is **detect-and-revert**, not prevention: the trade goes through, R22 closes it afterwards at market price — **spread and slippage are on you**. The detection latency is made up of the timer (1 s) or tick (≥ 500 ms), the close throttle (300 ms) and possibly the modify quiet window (up to 2 s sliding, hard-capped at 10 s in a series — so whoever keeps dragging SL/TP around delays R22). Realistically: **fractions of a second up to several seconds**; with a closed market (error 132) up to 15 min per attempt. If the EA is not running, AutoTrading is off or the timer fails, R22 does **not** work at all — like the entire enforcement. Only the confirmed master instance (≥ 2 cycles in a row) enforces, passive instances do nothing. After 5 failed attempts the ticket is dropped from the queue with FINAL-FAIL and **stays open** — although it is re-queued on the next pass. **No grandfathering at startup:** OnInit counts pre-existing magic-0 orders and reports them (journal event `INFO`, tag "R22 Start: N manuelle Order(s) vorgefunden -> werden geschlossen" — R22 start: N manual order(s) found -> will be closed), but closes nothing itself — the close only happens in the next or the one after next cycle, and on a passive instance not at all. **Interaction with the loss rules:** a manual trade closed by R22 is out of scope and is **not** counted by the history evaluation → no contribution to R5 cooldown, R6 losing streak, R19 de-risk, R25 revenge, and **no** consumption of the R3 daily budget. The realized loss does however hit the equity-based limits in full: **R4, R4b and R18 count it completely.** In the on-chart panel R22 appears **nowhere**; in the cockpit it shows up as a "— aus" (— off) chip when `InpCloseManualTrades=false`, and otherwise under "Deine Schwächen" (your weaknesses) — there, however, **multiple times per manual trade**, because every retry, every FINAL-FAIL and every discard writes its own CLOSE line. So the counter is an upper bound, not a trade count. **Compliance:** this means the EA also closes positions in funded mode that it did not open itself — whether that is compatible with your prop firm is something you have to check firm by firm.

---

## Honest limits (apply to all rules)
1. **Detect-and-close**, not prevent: on the client side the EA reacts with ~0.5 s delay (polling). Within that window a rule can be briefly violated — the damage is capped by R4/R4b. With **R22** (manual trades) the window can be longer — fractions of a second up to several seconds, see there.
2. **No-override is only friction locally** — as an admin you can switch the EA off. Real immutability = a VPS without your own admin access + the FTMO server limit.
3. **Mac/Wine** is unstable; continuous operation belongs on a Windows VPS.
