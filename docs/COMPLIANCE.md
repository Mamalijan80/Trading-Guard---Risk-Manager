# Mamal-Trading — Prop Firm Compliance Check

**Not legal advice.** What counts is solely the **current trading rules/terms of the respective firm at the time of YOUR sign-up** — rules change and are mostly enforced *case-by-case*. This check is an honest self-assessment of the tool plus a research snapshot (sources at the bottom). Research as of: 2026-06, **primary-source review 2026-07-21** (→ section 2.1). **Tool status: EA v0.36** — since v0.35 it includes **R22 "Nur Panel-Trades"** (panel trades only; → section 1.1); the v0.36 weekly risk selector is compliance-neutral (the trader picks their own risk percentage, no signal, no automated decision about direction/timing).

> **FTMO confirmed in writing (2026-07-22, ticket QVM-FSGGG-356):** "**Yes, you can**" — a **self-developed** EA of this category is permitted (details → section 2.0). Individual points (R22, order frequency) were not separately signed off; this is support information, not legally binding.

> **New from the primary sources (2026-07-21):** (1) **FTMO is a stronger fit than assumed** — FTMO's own *Risk Management Rules* use the term **"Risk per Trade Idea"** verbatim (clauses 7.5.3, 7.6.6), i.e. exactly the concept that R2 (idea cap) enforces in the tool. The tool *implements FTMO's own rules* instead of merely not violating them. (2) **The5ers is stricter than assumed** — the The5ers **T&C** you supplied requires **prior written approval** for automation (contradicting the more permissive help FAQ) → section 2.1 + corrected table.

---

## 1. What the EA actually does (honest, unvarnished)

**Generates NO signals** — and that is the decisive compliance point:
- No entry timing logic, no direction logic, no indicators that decide *when/what* is traded. **The human clicks BUY/SELL.**

**But it is NOT purely passive** (that belongs in the open):
- **One-click execution:** on the click, the EA computes the lot size for a fixed percentage risk (from the SL line) and sends **one** order via `OrderSend` (with a real SL + TP). = user-initiated execution helper, **one order per click** (human-paced).
- **Autonomous risk management:** closes/blocks on its own when a rule is broken (R1 risk, R7 missing SL/TP, R8 risk-reward ratio, R12 heat; SafeCloseAll on daily/max/weekly lock; cooldown/revenge/idea cap/daily budget block new trades). Locks survive a restart, there is no unlock button.
- **R22 "Nur Panel-Trades"** (panel trades only; since v0.35, default on): additionally closes **manually** opened positions and deletes manual pending orders on your own account — i.e. orders the EA did **not open itself**. That is a behavioral change compared with the previous assessment → **section 1.1**.

**Does NOT do** (the commonly forbidden patterns — all avoided):
- no HFT / tick scalping / sub-second holding
- no latency/feed arbitrage (does not compare feeds, does not chase a price update)
- no copy trading / mirroring across accounts, no signal groups
- no grid/martingale (on the contrary: caps risk, blocks stacking/revenge)
- no news straddle, no order spamming, no account management service
- acts only on **your own account** — no access to third-party accounts, no mirroring. *Restriction since v0.35:* "own trades only" **no longer holds without qualification** — `WatchScope=TOOL_ONLY` (hard-enforced in `InpFundedMode`) still governs all other enforcement functions, **but R22 deliberately bypasses this scope** (→ section 1.1). Positions of other EAs (their own magic ≠ 0) remain untouched.

**Classification:** **discretionary entry (no signals) + automated risk management** — the *most widely permitted* automation category across the landscape. This classification still holds; R22 does however shift the **reach** of the risk management within your own account (section 1.1).

---

### 1.1 R22 "Nur Panel-Trades" (panel trades only) — behavioral change, must be confirmed per firm

**What changed.** Up to v0.34 the rule was: the EA only touches what it opened itself (`InScope()`, hard-set to `TOOL_ONLY` in FundedMode). With **R22** (input `InpCloseManualTrades`, default `true`) the EA closes every order with **magic 0** — i.e. every trade you opened yourself in the MT4 terminal (or on your phone) — and deletes the corresponding pending orders. R22 is the **only** enforcement function that bypasses `InScope()`; it checks the magic directly. **This means it is also active in `InpFundedMode`**, where the previous design deliberately excluded exactly that. The reason is rule-mechanical, not strategic: only the panel path runs through the entry gates (R1 lot, R2 idea cap, R3 daily budget, R5 cooldown, R7 SL requirement, R12 heat, R13, R14, R15, R16, R17, R25) — a manual trade bypasses all of them.

**What did NOT change (the compliance-relevant points):**
- **No interference with third-party accounts.** R22 runs exclusively over `OrdersTotal()` of the terminal the EA runs on = your own account.
- **No copy trading, no mirroring, no signal generation.** R22 opens nothing, decides nothing about direction or timing. It only closes.
- **No contact with other EAs.** Everything with magic ≠ 0 is skipped.
- It remains **risk management on your own account** — the category from section 1 is not changed by this.

**Why it still has to be verified separately.** The self-assessment "automated risk management" was previously defended with the qualifier "only on own trades opened by the tool". That qualifier is no longer accurate. A prop firm rulebook that ties EAs to "trade/risk management" may specifically mean the management of **its own EA positions** — whether closing manually opened positions of the same account falls under that is **not** derivable from the sources researched. **We claim nothing here about individual firms and cite no rule on this — it is an open point to be clarified per firm before a funded account.**

**Concretely to be clarified before R22 runs on a funded account:**
1. Does automatically closing **manually** opened own positions still count as a "trade/risk management EA" at that firm?
2. Does the additional close volume (including retries) conflict with order frequency/hyperactivity rules?
3. Will a trade immediately closed again by R22 be counted by the firm as a standalone (losing) trade — relevant for consistency/minimum trading day rules?

**Way out if the answer stays unclear:** set `InpCloseManualTrades=false`. The EA then behaves as it did up to v0.34; R22 appears in the cockpit as a "— aus" (off) chip. That is the conservative state and the right choice whenever in doubt.

**⚠ Pitfall:** the distinction from panel trades rests solely on `Magic != 0`. Panel trades run with `InpMagic` (default `990201`). Anyone who sets `InpMagic=0` lets R22 clear out **their own panel trades** — the code has no protection against this. Never set `InpMagic` to 0.

---

## 2. Per firm (research snapshot — verify at sign-up)

| Firm | EAs in general | Risk manager EA (no-signal) | Pre-approval? | Verdict for this tool | Conf. |
|---|---|---|---|---|---|
| **FTMO** | **Yes — confirmed in writing by support (2026-07-22)**; self-developed = not a third-party EA | "most defensible" EA category; matches FTMO's own risk-per-trade-idea rule | No | **allowed (support-confirmed; details R22/frequency not clarified individually)** | 0.90 |
| **The5ers** | Yes, if **self-owned** + no forbidden strategies | permitted; risk enforcement fits the house rules | No | **likely-allowed (conditions)** | 0.78 |
| **FundedNext** | Yes on **MT4/MT5** (tool is MT4 ✓); SL/TP/lot tool counts as an **EA, not exempt** | permitted as an EA | No, but **EA fee/add-on** + consistency rules | **likely-allowed (conditions)** | 0.78 |
| **FundingPips** | Third-party EA explicitly permitted "**only as a trade/risk manager**" (strongest hit) | **explicitly named permitted category** | No, but **may ask for source ownership** (a binary alone is not enough) | **likely-allowed (conditions)** | 0.78 |
| **Alpha Capital** | EAs **only** for trade management/risk control (exactly our category) | fits, but … | **YES — mandatory pre-approval** (submit the file, written clearance; process is MT5/EX5-based) | **likely-allowed (conditions)** | 0.72 |

> **Table corrections after the primary-source review (section 2.1):** FTMO row conf. **0.82 → 0.88** (risk-per-trade-idea coverage, see below). The5ers row pre-approval **"No" → "per T&C YES (in writing); help FAQ is more permissive — contradiction, clarify directly"**, verdict therefore **"only with written approval (per T&C)"**. FundedNext/FundingPips/Alpha unchanged (no new primary source reviewed).

---

## 2.0 FTMO — written support confirmation (2026-07-22, ticket QVM-FSGGG-356)

Inquiry submitted via support ticket (description of the tool: no-signal, discretionary entry, automated risk management including R22, <2,000 requests/day; three concrete questions). FTMO support (Thomas Taylor) replied:

> "**Yes, you can.** If you intend to use trading robots (Expert Advisors – EAs), keep in mind that if you use an EA **from a third party**, you run into a risk of being denied the FTMO Account if you exceed the maximum capital allocation rule."

After the clarification "I developed the EA myself, so it is not a third-party EA" came: "**Understood.** … we wish you much luck with your trading!"

**What this reliably confirms:**
- A **self-developed** EA of this category is **permitted on FTMO without prior approval**. The only caveat FTMO mentioned — third-party EAs + the max capital allocation rule (several accounts with the same external strategy) — **does not apply here** (own development, single account). FTMO explicitly acknowledged this with "Understood".

**What was NOT confirmed individually (honestly):**
- The answer is a **generic support "Yes"**, not a detailed review. **Question 2 (R22 — automatic closing of manually opened positions)** and **question 3 (order frequency/hyperactivity)** were **not answered separately** (only a pointer to the strategy FAQ). They fall under the general "Yes", but are not specifically signed off.
- Support statements are **not legally binding**; FTMO reserves everything "at our sole discretion". The backstop remains the server-side limit.

**Recommendation:** if you want to arm R22 on a funded account, a **short follow-up specifically on question 2** (only the manual-close point) is worth it, so you have it explicitly in writing. For general EA use, the existing confirmation is sufficient.

---

## 2.1 Primary-source review (2026-07-21) — FTMO T&C (PDF) + FTMO Forbidden Practices + The5ers T&C

**Sources for this review:** FTMO *General Terms and Conditions* (22 pp., supplied by you), FTMO *Forbidden Trading Practices* (website), The5ers *Terms and Conditions* (website). All read in the original; quotes verbatim.

### FTMO — very good fit, with clear conditions

- **EAs are permitted.** The general T&C does **not** forbid automation; the actual prohibition list is separate (clause 7.3 refers to it). The *Forbidden Trading Practices* only forbid EAs when they make the account **hyperactive**: trades *"operated or managed by automated robots / EAs … which cause the trading account to become hyperactive … more than 2,000 server requests per day"*. → By construction the tool stays far below that (close only on rule breach, enforcement throttled to 300 ms, human-paced entries). ✓
- **The tool implements FTMO's *own* Risk Management Rules.** Clause **7.5.3** requires **avoiding** *"undertaking repeated simulated trading activity that results in higher **Risk per Trade Idea**, thereby exposing your simulated account to cumulative exposure in a specific symbol or correlated symbols"*; clause **7.6.6** allows FTMO to enforce *"the limitation on **Risk per Trade Idea** … as a percentage of the Initial Simulated Capital … on any single simulated trade or combination of simulated trades out of one trade idea"*. **That is verbatim R2 (idea cap = symbol + direction, capped as a percentage of equity)** — plus R17 (correlation) and R12 (heat). Clause **7.5.1** ("no substantially larger positions") = R1/R15. The tool is therefore an **automatic enforcer of the FTMO risk rules**, not a borderline case.
- **What the TRADER (not the tool) must observe** — forbidden practices that depend on trading style: **gap/news trading** (*"opening simulated trades when major global news … are scheduled"*, or ≤2 h before a ≥2 h market closure), HFT/seconds scalping, exploiting price errors/a slow feed. → **R16 (session/news blackout) can enforce the news window, but is OFF by default** — anyone trading at FTMO should configure R16.
- **R22 is compatible with the FTMO rules.** Nothing in the T&C or the Forbidden Practices prohibits closing **your own** positions on **your own** account with your own software — on the contrary, clauses 7.4–7.6 frame exactly that as desirable risk management. The earlier caveat (section 1.1) is therefore largely defused for FTMO; it remains "confirm if in doubt", because FTMO interprets everything *at our sole discretion*.

### The5ers — contradiction between T&C and help FAQ, written approval needed

- The **T&C** (the binding document) contains a clause *"Use of Automated Trading Software"*: **no automated software without prior written approval** by the firm; **third-party EAs forbidden**, only **self-developed** EAs after approval, and the trader **must own the source code**. → You own the source code ✓, but the **written approval is missing** and is a precondition per the T&C.
- This is in tension with The5ers' more permissive **help FAQ** ("Can I use an EA?"), on which the previous "likely-allowed" assessment was based. **Both cannot be true at the same time** — clarify directly which regime applies before opening a The5ers account. Until then: treat The5ers like Alpha Capital (**obtain written prior approval**).
- Forbidden practices (T&C): HFT (*"majority of trades duration … measured within a few seconds"*), **tick scalping**, arbitrage variants, **copy trading**, *"Expert advisors which scalp during the rollover-night"*, shared/third-party EAs. → The tool is none of these; a very fast M1 scalping **style** could however touch on "seconds HFT"/rollover scalping — that is on the user, not the tool.

**Important:** the section numbers of The5ers clauses come from an automatic fetch of their T&C page and may not be exact; the **substance** (written approval for automation, source code ownership) is the reliable, actionable point.

---

## 3. Conditions so that it STAYS permitted (tool guardrails)

1. **SL/TP must be real, broker-visible orders — no "stealth"/virtual SL.** The5ers explicitly forbids hidden stops. → R7 sets real `OrderSend` SL/TP ✓. **Never** build in a purely internal/virtual SL.
2. **Keep server request volume low** (FTMO: <2,000 requests/day; The5ers/FundedNext: hyperactivity). In normal operation very low (close only on rule breach, enforcement throttled to 300 ms; close queue with retry limit 5 + backoff up to 4 s caps storms). → stays human-paced ✓. *Watch item: do not add tight polling loops; a daily request counter would be a sensible extra hardening.* **With R22** additional close volume is added that the trader triggers themselves (every manual order → 1 close request, up to 5 attempts with backoff on errors); anyone who clicks manually a lot generates correspondingly more requests.
3. **`TOOL_ONLY` / own account, own trades** — `InpFundedMode=true` for real/funded (enforces TOOL_ONLY, blocks TestMode). No second account, no mirroring, no third-party access ✓. **Exception R22:** acts on magic-0 orders of the same account regardless of scope (section 1.1) — still your own account, but no longer "own trades only".
4. **Source ownership** — you own the source code (`MamalTrading.mq4`). For FundingPips/Alpha, be able to show source + version history if needed ✓.
5. **Obtain written approval at Alpha Capital AND The5ers** (each only if you intend to trade there): Alpha Capital explicitly requires it (submit the file, MT5/EX5 process). The5ers requires it **per their T&C** as well (section 2.1) — even though their help FAQ sounds more permissive; resolve the contradiction directly with The5ers before signing up. **Not a general blocker** — per the current sources, FTMO/FundedNext/FundingPips need no prior approval.
6. **FundedNext:** activate the EA add-on/fee; observe the consistency rules.
7. **TestMode (`InpTestMode`) never on funded** — hard-disabled by `InpFundedMode` ✓.
8. **Confirm R22 per firm before the funded account** (section 1.1) — until then, when in doubt, `InpCloseManualTrades=false`. And: **never** set `InpMagic` to 0, otherwise R22 closes your own panel trades.

---

## 4. Honest remaining limits

- **Client-side = detect-and-close (~0.5 s), not the hard firm limit.** The real backstop is the **firm's server-side daily/max loss limit**. The EA *lowers the probability* of a breach, it does not replace the firm limit.
- The firm rules are in part **deliberately broad + discretionary** (case-by-case decisions). "likely-allowed" ≠ guarantee.
- Research sources are partly secondary pages (some firm pages returned 403/404 on automatic fetch) — **verify against the original at sign-up**.
- **R22 is likewise detect-and-revert, not prevention.** The manual trade runs first — the EA closes it afterwards at market price. **Spread and slippage are borne by the trader**, a loss can arise. The detection latency follows from the timer (1 s) or tick (≥500 ms) + close throttle (300 ms) + possibly up to 2 s modify quiet window + retry/backoff: realistically **fractions of a second up to several seconds**, and with the market closed (error 132) up to 15 min per attempt. If the EA is not running or AutoTrading is off, R22 does not act at all.
- **R22 closes and the loss rules:** a manual trade closed by R22 does **not** count towards R5 cooldown, R6 losing streak, R19 de-risk, R25 revenge, and consumes **no** R3 daily budget (out of scope / wrong magic). The realized loss does however feed through to the **equity-based** limits: R4 daily loss, R4b max loss, R18 weekly limit. Everything is therefore covered for the firm limits; the tool's discipline statistics see these trades only partially.
- Per your specification, a written firm confirmation is **not a general mandatory blocker**. It is mandatory **only at Alpha Capital** — **and only if you want to trade there**; for FTMO/The5ers/FundedNext/FundingPips no prior approval is required. Under FTMO's discretionary regime, a written support confirmation is the only way to fully de-risk it voluntarily (optional).

---

## 5. Verdict

At **all five** researched firms the tool sits in the **most widely permitted** automation category: a **non-signal-generating, single-account, discretionary-entry risk management EA** that avoids **every** commonly forbidden pattern. It is explicitly **not** a "challenge passer"/signal seller.

**Pre-approval gate after the primary-source review (2026-07-21) + support confirmation (2026-07-22):** **FTMO** — no gate, **confirmed in writing as permitted** (self-developed EA, not third-party; section 2.0), and the strongest fit (the tool enforces FTMO's own "Risk per Trade Idea", section 2.1). Only the specific sign-off on R22/frequency remains open. **The5ers** — the T&C requires **written approval** (contradiction with the help FAQ, to be clarified). **Alpha Capital** — mandatory approval. **FundedNext/FundingPips** — per the current (secondary) sources no approval gate, but conditions (EA add-on/consistency, or source proof); for these two there is still **no** primary-source review.

**One point has been open since v0.35:** the research in section 2 was done before **R22** and does **not** cover the case "EA also closes manually opened positions of the same account". The category classification stays unchanged (single account, no signal, no copy trading), but whether the behavior falls under the respective "trade/risk management EA" permission is **to be confirmed per firm** (section 1.1). The conservative state until then: `InpCloseManualTrades=false`.

**Status remains: demo-only, not prop-firm-ready** — the compliance assessment is favorable, but it does not replace F7 + rule test matrix + demo forward testing + the firm-specific verification/approval.

---

## Sources (full URLs — check against the firm's current page at sign-up)

**FTMO** — *primary sources reviewed 2026-07-21 (★); support confirmation 2026-07-22 (★★)*
- ★★ FTMO support ticket **QVM-FSGGG-356** (email thread 2026-07-22, "Yes, you can"; self-developed EA = not third-party) — in the trader's private correspondence, section 2.0
- ★ FTMO *General Terms and Conditions* (PDF, 22 pp., supplied by the user 2026-07-21; Risk Management Rules clauses 7.4–7.6, "Risk per Trade Idea" 7.5.3/7.6.6; Forbidden Practices reference 7.3)
- ★ https://ftmo.com/en/forbidden-trading-practices/ (EAs permitted <2,000 requests/day; gap/news prohibition)
- https://ftmo.com/en/faq/which-instruments-can-i-trade-and-what-strategies-am-i-allowed-to-use/
- https://ftmo.com/en/what-does-profitable-trading-look-like-with-a-working-ea/

**The5ers** — *T&C reviewed 2026-07-21 (★)*
- ★ https://the5ers.com/terms-and-conditions/ (clause "Use of Automated Trading Software": prior written approval required, third-party EAs forbidden, source code ownership; forbidden practices: HFT/tick scalping/copy trading/rollover scalping)
- https://help.the5ers.com/can-i-use-an-ea-expert-advisor-can-i-set-a-stealth-mode-stop-loss/ (help FAQ — more permissive; **contradicts the T&C**, clarify directly)
- https://help.the5ers.com/prohibited-trading-practices/
- https://the5ers.com/faqs/
- https://www.eafunded.com/firms/the5ers (secondary)
- https://thetrustedprop.com/blogs/important-rules-to-know-before-trading-with-the5ers (secondary)

**FundedNext**
- https://help.fundednext.com/en/articles/8020763-is-ea-allowed-in-fundednext
- https://help.fundednext.com/en/articles/8020351-what-are-the-restricted-prohibited-trading-strategies
- https://help.fundednext.com/en/articles/11982271-does-fundednext-allow-hft-high-frequency-trading
- https://help.fundednext.com/en/articles/8388896-are-there-any-restrictions-on-my-trading-strategy
- https://help.fundednext.com/en/articles/11641338-can-i-use-ea-in-stellar-instant

**FundingPips**
- https://help.fundingpips.com/hc/en-us/articles/34505029138449-Trading-Conduct-and-Security-Standards
- https://fundingpips.com/terms-and-conditions
- https://help.fundingpips.com/hc/en-us/articles/34504137479441-News-Trading-Weekend-Holding
- https://thetrustedprop.com/blogs/rules-to-keep-in-mind-when-trading-with-funding-pips (secondary)
- https://sureshotfx.com/blog/prop-firms-that-allow-ea-trading (secondary)
- https://www.fxempire.com/prop-firms/fundingpips (secondary)

**Alpha Capital (AlphaCapitalGroup)**
- https://help.alphacapitalgroup.uk/en/articles/6934236-can-i-use-an-expert-advisor-ea
- https://help.alphacapitalgroup.uk/en/articles/6934275-what-are-prohibited-trading-strategies
- https://help.alphacapitalgroup.uk/en/articles/8786973-is-copy-trading-allowed
- https://www.eafunded.com/firms/alpha-capital (secondary)
- https://thetrustedprop.com/blogs/alpha-capital-group-trading-rules-allowed-vs-not-allowed (secondary)

**General / landscape**
- https://propfirmmatch.com/prop-firm-rules
- https://tttmarkets.com/articles/why-prop-firms-do-not-allow-high-frequency-trading/
- https://copygram.app/blog/education/equity-protector-automating-prop-firm-daily-loss-limit
- https://funderpro.com/blog/master-prop-firm-drawdown-rules-in-2025/
