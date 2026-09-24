# Mamal-Trading — Rule Cheat Sheet

**Baseline:** account 20,000 € · risk/trade **0.25 % = 50 €** · auto-scale on
(idea cap 0.5 % · total risk 1.0 % · daily budget **2.0 % = 400 €** (v0.20) — these scale automatically with the risk setting)

> **Every € figure on this page is a 20k example.** The binding value is the **percentage**; the profile allows 10k/20k/25k (on 10k the € numbers are halved, on 25k they are 25 % higher). Central clarification: [`../RULES.md`](../RULES.md).

| # | Name | Definition (what it does) | Value | Example (20,000 €) |
|---|------|--------------------------|------|---------------------|
| **R1** | Risk per trade (auto lot) | The tool sizes the lot so that entry→SL matches the risk exactly. Closes positions whose risk (based on the current SL) exceeds the limit. | 0.25 % = 50 € | SL 20 pips → 0.25 lots. SL 10 pips → 0.50 lots. Always 50 € of risk. |
| **R2** | Idea cap | Same symbol + same direction = one idea. The sum of open risk per idea is capped. | 0.5 % = 100 € (= 2×) | EURUSD buy #1 + #2 = 100 € = full → #3 blocked. |
| **R3** | Daily risk budget | Sum of the risk *opened* on a given day (winners count too, there is no refund). | **2.0 % = 400 €** (≈ 8 trades) — v0.20 | After 8 trades (8×50 €) → the 9th is blocked with "TAGESBUDGET" (daily budget). |
| **R4** | Daily loss lock | Equity loss against the day's starting equity → all **tool-monitored** positions closed + lock until the daily reset. Resets every day. (Trades from **foreign EAs** only trigger a warning, they are not closed; **manual magic-0 trades have been cleared out by R22 since v0.35**) | 2 % = 400 € | Equity 20,000 → 19,600 → tool trades closed, locked until tomorrow. |
| **R4b** | Total loss lock (+ warning gate) | Loss against starting capital → **permanent** lock; the warning gate stops new trades earlier | Lock 6 % = 1,200 € · warning 5 % = 1,000 € | Equity 19,000 → no new trades; 18,800 → permanently locked |
| **R5** | Cooldown | X losing trades in a row → pause on new trades. | 3 stops → 45 min | Stop, stop, stop → no new trades for 45 min. |
| **R6** | Losing-streak lock | X losses in a row → day locked. | 5 stops | 5th stop in a row → locked until tomorrow. |
| **R7** | SL + TP mandatory | Every position needs an SL **and** a TP. **4 s** grace period (news blackout 0 s) — the clock starts **when SL/TP is removed or missing**, not at open. Applies uniformly to all monitored positions — **there is no longer an immediate-close special case for tool trades** (v0.33; previously 5 s from open + tool trade closed immediately). The clock is **persistent** per ticket (it survives restart/recompile/timeframe change) and briefly re-setting the SL only resets it after a **60 s healing period** (v0.34). | on, **4 s** grace | Order without TP → closed after 4 s. SL removed after 2 h → closed 4 s later. |
| **R8** | Minimum RRR | **OFF** (by request, v0.20). The auto TP of tool trades still targets 2R. | **OFF** | (disabled) |
| **R9** | Anti-FOMO gate | Two-click confirmation with a waiting period. | **OFF** | (disabled by request) |
| **R10** | No override | No unlock button; locks survive a restart; warning when AutoTrading is off. | on | Restart MT4 → the lock remains. AutoTrading off → "SCHUTZ AUS" (protection off). |
| **R11** | Journal | Every trade / block / close is logged as CSV (with a reason tag). | on | `MQL4/Files/MamalTrading_Journal.csv` |
| **R12** | Total risk cap | Open risk across **all** positions combined is capped. | 1.0 % = 200 € (= 4 trades) | 4 trades of 50 € open = 200 € → the 5th is blocked. |
| **R13** | Daily target + giveback | At the target, no new trades; give back too much of the day's high → day locked. | Target +3 % (+600 €); giveback from +1 %, 1 % given back | +600 € → no new trades. Or +400 € → +200 € → day locked. |
| **R14** | Minimum pause | **OFF** (by request, v0.20). | **OFF** | (disabled) |
| **R15** | Min SL + max lot | **OFF** (v0.22: M1 scalping needs tight stops). Min SL distance `InpMinStopPips=0` = off, max lot cap `InpMaxLot=0` = off as well. Against the mini-SL→huge-lot trick, only the hard broker `STOPLEVEL` remains — plus R1, which caps the lot size at 50 € of risk anyway. | **OFF** (both 0) | SL of only 3 pips → goes through as long as the broker `STOPLEVEL` allows it; the lot is still capped by R1. |
| **R16** | Session / news | Trading only inside a time window + manual news blackout. **Available, but OFF by default** — it must be configured (`InpUseSession=true` and/or `InpNewsFrom`/`InpNewsTo` ≠ 0), otherwise the gate never fires. | **off (default)** | Outside 08:00–22:00 → blocked (only if enabled). |
| **R17** | Correlation cap (currency vector) | Net risk **per currency** across all positions is capped (correlated pairs + cross pairs count together, non-FX instruments get their own bucket). | 1.5 % | EURUSD buy + GBPUSD buy add up (short USD); a 3rd → blocked. EURUSD buy + USDJPY buy cancel each other out. |
| **R18** | Weekly loss limit | Equity loss over the week → week locked. | 5 % = 1,000 € | −1,000 € over the week → locked until the week rolls over. |
| **R19** | De-risk ladder | **OFF** (by request, v0.20). | **OFF** | (disabled) |
| **R22** | Panel trades only | Every order **without** the tool magic (i.e. opened by hand in the terminal or in the mobile app) is closed: positions at market, pending orders deleted. **Account-wide across all symbols**, not just the chart symbol. Foreign EAs with their own magic are left untouched. Reason: only the panel route passes through the entry gates (R1/R2/R3/R5/R7/R12/R13/R15/R16/R17 …). Applies in FundedMode too. A trade closed this way does **not** count towards R3/R5/R6/R19/R25 — but the loss hits R4/R4b/R18 in full. | on (`InpCloseManualTrades=true`) — v0.35 | You open an XAUUSD trade on your phone → it is closed within ~1 s (timer 1 s + throttle 0.3 s; up to 2 s if you happen to be dragging SL/TP). Spread and slippage are on you. |
| **R25** | Revenge window | **OFF** (by request, v0.20). | **OFF** | (disabled) |

## Panel status (top left on the chart)
There are **exactly these 9 states** — panel and cockpit show the same string. There is **no** generic "GESPERRT" (locked); the lock is always named. Order = priority top to bottom (with several locks active, the hardest one wins):

| Display | Meaning |
|---|---|
| **SCHUTZ AUS** (protection off, orange) | AutoTrading is off — the EA cannot protect you! |
| **MAX-LOSS GESPERRT** (max loss locked, red) | Total loss lock, permanent (R4b) |
| **WOCHE GESPERRT** (week locked, red) | Weekly loss limit (R18) |
| **TAG GESPERRT** (day locked, red) | Day lock (R4 daily loss / R6 losing streak / R13 giveback) |
| **MAX-LOSS WARNUNG** (max loss warning, orange) | Total loss ≥ warning gate (5 %) — no new trades (R4b) |
| **COOLDOWN** (orange) | Pause after 3 losses (R5) |
| **ZIEL ERREICHT** (target reached, green) | Daily target reached, no new trades (R13) |
| **AUSSER SESSION** (outside session) | Outside the time window / news lock (R16) |
| **AKTIV** (active, green) | All clear, you can trade |

**R22 has no panel display** — you only see that a manual trade was closed in the journal/cockpit, not in the chart panel.

## Auto-scale (important)
If you change **risk/trade** or **`InpIdeaXrisk`**, the idea cap, total risk and daily budget adjust automatically. The *number* of permitted trades (2 per idea / 4 at the same time / **8 per day** as of v0.20) stays constant. `InpAutoScale=false` → fixed % values.

## Disabled by request (v0.20 / v0.22)
**R8** (minimum RRR), **R9** (double confirmation), **R14** (minimum pause), **R19** (de-risk ladder), **R25** (revenge window) — v0.20.
**R15** (min SL distance **and** max lot cap, both inputs set to 0) — v0.22, because M1 scalping needs tight stops; what remains is the hard broker `STOPLEVEL`.
The discipline comes from the hard limits R3/R4/R4b/R12/R5/R6.
**Not disabled, but inactive:** **R16** (session/news) is OFF by default and has to be configured first.

## Honest limits
- Client-side "detect and close" (~0.5 s reaction); the damage is capped by R4/R4b.
- **R22** does not prevent the manual trade, it reverses it: detection takes a fraction of a second up to several seconds (with the market closed, up to 15 min per attempt), and spread and slippage are on you. EA off or AutoTrading off → R22 does not kick in at all.
- The **R22** counter under "Deine Schwächen" (your weaknesses) in the cockpit can count a single manual trade **multiple times** (each retry writes its own line) — it is an upper bound, not a trade count.
- "No override" is only friction locally; it is truly un-circumventable only on a VPS + FTMO server-side limit.
- Mac/Wine is unstable → run continuously on a Windows VPS.
