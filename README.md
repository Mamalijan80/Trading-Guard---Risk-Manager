# TradingGuard

**License:** AGPL-3.0 · **Version:** EA v0.66, Cockpit v0.65 · **Maturity:** demo — not prop-firm-ready yet
**Author:** Mohammadreza Tavakoli — [itavakoli.com](https://itavakoli.com/)

> ⚠️ **Before you let it near a real or funded account: don't.** The code compiles without errors
> and has been through several adversarial reviews, but out of 258 test cases only about a dozen have been
> verified live, and a demo forward test over several weeks is still completely missing. The binding
> classification: [`docs/STATUS.md`](docs/STATUS.md). **No investment advice, no warranty.**


A personal **risk/discipline tool** for MetaTrader 4 (an MT5 mirror is planned). Its purpose is **not** to find a strategy, but to **enforce** risk and execution behavior. Not a strategy bot — a discipline tool for **prop-firm challenges** (FTMO as the default profile, **multi-prop-firm** planned). Example account base: 20,000 € (FTMO).

> **Source of truth = [`RULES.md`](RULES.md).** Every other document is derived from it.

## What it actually is (as of v0.35)
**All enforcement** lives in a **single Expert Advisor** (`ea/mt4/MamalTrading.mq4`) inside the MT4 terminal, with:
- An **on-chart panel** (status, loss/risk bars, BUY/SELL buttons) as the main interface. **Additionally since v0.26:** an optional localhost cockpit (`cockpit/`, Node server + `dashboard.html` + `day.html`) — a pure **view** over the DLL-free file bridge (the EA writes JSON), with **no** rule logic, switchable off via `InpCockpit=false`.
- **Risk-based one-click entry:** drag/click the red SL line → the tool calculates the lot size for a fixed risk → BUY/SELL opens the trade (SL at the line, TP at the RR target).
- **Panel trades only (R22, since v0.35, on by default):** orders opened by hand in the MT4 window (Magic 0) are detected **account-wide** and **closed after the fact** — positions at market price, pendings deleted. Reason: only the panel path passes through the entry gates (R1/R2/R3/R7/R12/R17 …). **Honest limitation:** this is *detect-and-revert*, not prevention — the trade does open and is reversed afterwards, and **the trader pays the spread and slippage**; detection typically takes a fraction of a second up to several seconds. Foreign EAs (with their own Magic ≠ 0) are left untouched. Switchable off via `InpCloseManualTrades=false`.
- **Rule set R1–R19 + R22 + R25** (R9 off), **auto-scale caps**, loss/week locks, cooldown, revenge window, CSV journal.
- Persistence via `GlobalVariables` + a lockstate file (fail-closed); enforcement runs from `OnTick` **and** `OnTimer` (tick-independent, since v0.15) plus a real close queue (v0.16); tick-independent server time (`SrvTime()` = PC clock + a server offset maintained on each tick; MQL4 has **no** `TimeTradeServer`).

## ⚠️ Important note (compliance)
Contrary to the original plan, **the tool opens trades itself** — via a one-click `OrderSend` with a calculated lot size and its own TP. This is **click-triggered** (no autonomous auto-trading, **no signal generation**) plus autonomous risk management (closing/blocking). That puts it in the **most widely permitted** prop-firm automation category. **Compliance check (5 firms, with sources): [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md)** — FTMO/The5ers/FundedNext/FundingPips are "likely-allowed" (with conditions), **Alpha Capital requires written pre-approval**. Verify firm-specifically before any real/funded account; set `InpFundedMode=true`.
**Additional item to check since v0.35:** R22 closes orders that the EA did **not open itself** — **even in FundedMode**. It is the only enforcement function that bypasses the `InScope()` filter. Whether a firm accepts that has to be clarified firm by firm.

## Status & safety
- **v0.35 is DEMO ONLY and not prop-firm-ready.** Maturity = **fix-verified (AI review), but UNTESTED LIVE** — the binding maturity model: [`docs/STATUS.md`](docs/STATUS.md). The P0/P1 items from the initial review [`docs/REVIEW-v0.14.md`](docs/REVIEW-v0.14.md) (frozen, describes v0.14, decision **C**) were worked off in v0.15–v0.18 and hardened further by a bug hunt ([`docs/BUGHUNT-v0.17.md`](docs/BUGHUNT-v0.17.md)). Roadmap: [`docs/PROP-FIRM-READINESS.md`](docs/PROP-FIRM-READINESS.md).
- **Safety rule no. 1:** nothing touches a real/funded account before the roadmap is green: F7 + **rule test harness/rule matrix** + demo forward test + **prop-firm rule compliance** + Windows VPS.
- **Deployment:** locally first (demo). For stability *and* a genuine "No-Override" → a **Windows VPS** (MT4 via Wine on Apple Silicon is unstable).

## Quick start

1. **Install the EA:** copy `ea/mt4/MamalTrading.mq4` to `<MT4 data folder>/MQL4/Experts/`,
   compile it in MetaEditor with **F7**, then drag it onto a chart. Turn AutoTrading on.
2. **Set the base:** set `InpInitialBalance` to the real challenge starting balance — **without a thousands separator**
   (`10000`, not `10.000`; otherwise MetaTrader reads 10.0).
3. **Define the weekly risk:** type the percentage into the panel and press **SETZEN** (set). Without
   a deliberate weekly decision, no trading happens (rule R23) — that is intentional, not a bug.
4. **Cockpit (optional):** start `cockpit/start.bat` (Windows) or `cockpit/start.command` (macOS),
   then open `http://localhost:8730`. Node.js is enough — no dependencies, no DLL. Switchable off via
   `InpCockpit=false`.

The cockpit is a **pure view**. All rule enforcement sits in the EA and keeps running even when
the server is off.

## Contributing

Bug reports are welcome — especially from real demo operation, because that is exactly where coverage is
missing. Whoever reports a finding helps most by including: the MT4 build, the EA version from the
`BootDiag` line in the journal, the affected journal lines, and what you would have expected.

## License

**GNU Affero General Public License v3.0** — see [`LICENSE`](LICENSE).

Free for everyone, commercial use included. The only condition that matters: **attribution stays
intact.** Anyone who redistributes, modifies, or operates TradingGuard as a network service must
disclose the source code under the same license and name the author and the origin:

> TradingGuard — © Mohammadreza Tavakoli, [itavakoli.com](https://itavakoli.com/)

The AGPL was chosen deliberately: it prevents anyone from reselling this tool as a closed
subscription product. For prop traders, open source is an advantage anyway — The5ers, for
instance, forbids EAs whose source code the trader does not own (see [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md)).

**Disclaimer:** This tool enforces rules. It makes no market decision, gives no investment advice and
takes no responsibility for trading results. Trading leveraged products can lead to a total loss. The
software is provided without any warranty whatsoever.

## Documents
- [`RULES.md`](RULES.md) — the rule contract (source of truth)
- [`docs/RULES-PLAIN.md`](docs/RULES-PLAIN.md) — **rules explained in plain language** (no technical detail, with extensive examples)
- [`docs/RULES-DETAILED.md`](docs/RULES-DETAILED.md) — detailed rule description
- [`docs/RULES-CHEATSHEET.md`](docs/RULES-CHEATSHEET.md) — cheat sheet
- [`docs/TECHNICAL.md`](docs/TECHNICAL.md) — technical implementation
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture decision
- [`docs/REVIEW-v0.14.md`](docs/REVIEW-v0.14.md) — critical review + v0.15 patch plan (frozen artifact)
- [`docs/PROP-FIRM-READINESS.md`](docs/PROP-FIRM-READINESS.md) — roadmap to "prop-firm-ready" (multi-prop-firm)
- [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) — prop-firm compliance check (5 firms, with sources)
- [`docs/STATUS.md`](docs/STATUS.md) — **maturity model** (built/compiled/fix-verified/tested) — governs "how finished is it"
- [`docs/BUGHUNT-v0.17.md`](docs/BUGHUNT-v0.17.md) — bug hunt findings (fixed vs. open)

## Folder structure
```
TradingGuard/
├─ README.md
├─ RULES.md                     # source of truth
├─ LICENSE                      # AGPL-3.0
├─ ea/
│  ├─ mt4/MamalTrading.mq4      # the active EA — all rule enforcement (v0.66)
│  ├─ mt5/RiskGuard.mq5         # obsolete predecessor, kept around for reference
│  └─ shared/CORE-PLAN.md       # shared logic + plan
├─ cockpit/                     # localhost view (Node, no dependencies)
│  ├─ server.js                 # file bridge + HTTP endpoints
│  ├─ dashboard.html            # live cockpit (DE/EN/FA)
│  ├─ trade.html                # trade file: screenshots, SL/TP history, evaluation
│  ├─ day.html · report.html    # daily detail and weekly report
│  └─ i18n.js                   # translations
└─ docs/                        # rules, technical details, maturity, compliance, roadmap
```
*Note: `ea/mt5/RiskGuard.mq5` is an obsolete predecessor (replaced by MamalTrading) and can be deleted. The `ea/mt4/RiskGuard.mq4` previously listed here does not exist (any more) — only the MT5 file is still there.*

## Rules at a glance (details in RULES.md)
R1 risk per trade (auto lot, 0.25 %) · R2 idea cap · R3 daily budget · R4 daily loss · R4b max loss · R5 cooldown · R6 losing-streak lock · R7 SL/TP mandatory · R8 min. RRR · R9 anti-FOMO (off) · R10 no-override · R11 journal · R12 total risk · R13 daily target + giveback · R14 minimum break · R15 min. SL/max. lot · R16 session/news · R17 correlation · R18 weekly limit · R19 de-risk · **R22 panel trades only** (manual orders are closed, since v0.35) · **R23 mandatory weekly risk** (no trade without a deliberate weekly decision, since v0.49) · R25 revenge window.
