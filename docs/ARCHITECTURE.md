# Architecture (as of v0.35)
*Maturity, i.e. "how finished is it": see [`STATUS.md`](STATUS.md). Binding rule values: [`../RULES.md`](../RULES.md).*

## Current state: a single EA
The entire **rule logic and enforcement** lives in **one MQL4 Expert Advisor** (`ea/mt4/MamalTrading.mq4`) running inside the MT4 terminal. It is operated through an on-chart panel. **Since v0.26** the originally discarded **DLL-free file bridge** is back after all — but strictly as a **read-only view**: the EA writes its state as JSON, and a zero-dependency Node server (`cockpit/`) serves a localhost dashboard from it. The cockpit **decides nothing** and cannot unlock anything; if it fails, protection is unaffected (see "Discarded, then built anyway" below).

### Components inside the EA
- **Event loop:** `OnInit` / `OnTick` / `OnTimer` / `OnChartEvent`. Core = `Cycle()`.
  - **Enforcement runs from `OnTick` AND `OnTimer`** (since v0.15, tick-independent) — protection also applies in tick-poor/gappy markets. Detection queues tickets into the **real close queue** (v0.16: retry limit/backoff/error codes/journal entry per attempt); `ProcessCloseQueue()` performs the actual close. *(The "OnTick only" stopgap from v0.8 has been replaced.)*
- **Risk engine:** `CalcLot` (auto lot from SL distance), `RiskPctOf`, `EffectiveRiskPct` (R19), auto-scale caps `EffIdeaCap/EffHeat/EffDay`.
- **One-click entry:** red SL line (`OBJ_HLINE`), BUY/SELL buttons (`OBJ_BUTTON`), `DoEntry` with staged gates → `OrderSend`.
- **Enforcement:** `EnforceSLTP` (R7), `EnforceRisk` (R1), `EnforceRR` (R8), `EnforceHeat` (R12), `SafeCloseAll` (locks) — **since v0.35** additionally `EnforceManualTrades` (R22, closes Magic-0 orders; the only one of these functions **without** an `InScope()` filter).
- **Persistence:** `GlobalVariables` (`RG_*`), survive restarts; daily/weekly reset based on server time.
- **Panel:** chart objects (`MMT_*`), throttled redraw (only on change).
- **Journal:** CSV in `MQL4/Files/`.

Details: [TECHNICAL.md](TECHNICAL.md).

## The three honest truths (design foundation)
1. **Detect-and-close, not prevent.** MT4 has no pre-trade veto hook; the EA reacts with latency (polling) → a short damage window, capped by R4/R4b. Real prevention is only possible server-side.
2. **No-override locally = friction only.** GlobalVariables can be deleted, AutoTrading can be switched off, the EA can be removed. True irreversibility only exists on a **locked-down VPS + FTMO server-side limit**. *(Review P0-7: hardening via checksummed lockstate file / fail-closed built in v0.16 — a backstop, not real immutability.)*
3. **Mac/Wine is unstable.** For a real challenge the EA belongs on a **Windows VPS**.

## Compliance consequence
The EA **opens trades** (one-click `OrderSend`) and **closes/blocks** positions (no `OrderModify` — it does not retro-fit SL/TP, it closes instead; SL/TP are only set at `OrderSend` time). Click-triggered ≠ autonomous, but before going real/funded, **prop-firm rule compliance** must be checked — written FTMO confirmation is not a mandatory blocker, but copy-trading/EA rules must be clarified **per prop firm** (FTMO/The5ers/FundedNext/… ; see [PROP-FIRM-READINESS.md](PROP-FIRM-READINESS.md) item 13). Positions from **foreign EAs** (own magic ≠ 0) have not been touched by the watchdog since v0.15 (magic filter `InScope`/`WatchScope`, default `TOOL_ONLY`, review P1-11). **Limitation since v0.35:** R22 (`EnforceManualTrades`) bypasses this filter and closes **manual Magic-0 orders** on the own account account-wide — including in FundedMode. Must be verified per firm, see [COMPLIANCE.md](COMPLIANCE.md) section 1.1.

## Discarded → built anyway after all (file bridge, v0.26)
The first design was a **hybrid**: EA watchdog *plus* a separate **Tauri cockpit** + **DLL-free file bridge** in `MQL?/Files`. That was initially discarded in favor of a single EA with an on-chart panel (faster, fewer moving parts, no cockpit desync). **Since v0.26 the file bridge does exist** — but in a defused form: no Tauri client, instead EA→`mamal_cockpit.json` (atomic, every 2 s) → zero-dependency Node server `cockpit/server.js` → browser (`dashboard.html`, daily detail `day.html`). **One-way street:** the cockpit only reads, it cannot set, loosen or unlock any rule — which makes the desync objection from back then moot. The **Tauri client** remains discarded.

## Event loop & state (since v0.15/v0.16)
`Cycle()` runs from **OnTick and OnTimer** (P0-1) so that protection also applies without ticks ("trades only from OnTick" from v0.8 is obsolete). The losing streak is resolved **history-based** (`ResolveHistory`, watermark `RG_LAST_CLOSE`) instead of in-memory. **WatchScope** (`InpWatchScope`, default `TOOL_ONLY`): `TOOL_ONLY`/`TOOL_PLUS_MANUAL` do not touch foreign magics; `ALL_POSITIONS` touches everything (demo/debug only, **not real/funded** — with any prop firm strictly `TOOL_ONLY`). **v0.35:** R22 does not depend on `WatchScope`; with `InpCloseManualTrades=true`, `TOOL_PLUS_MANUAL` is effectively pointless because Magic-0 orders get closed anyway.

**v0.16:** a real **close queue** (`RequestClose`/`ProcessCloseQueue`: retry limit, exponential backoff, error-code handling, journal entry per attempt) instead of direct close; **lockstate file** (`MamalTrading_Lockstate.dat`, HMAC-light checksum, fail-closed on corruption) as a backstop next to the GlobalVariables; **protection-off logging** (`PROTECT_OFF`/`PROTECT_ON`/`TAMPER`); **R3 reconciliation** (`RG_DAY_RISK` reconstructed after a crash from tool trades opened today, `max(persisted, reconstructed)`, one stable % base); **tick-independent server time** (`SrvTime()` = `TimeLocal()` plus a server offset maintained on tick; MQL4 has **no** `TimeTradeServer`, that is MQL5). Status: **demo-only, not prop-firm-ready** — F7 through R3 = 0 errors, while `SrvTime` F7 + **rule test harness/rule matrix** + demo forward test + **prop-firm rule compliance** are still outstanding (see [PROP-FIRM-READINESS.md](PROP-FIRM-READINESS.md)).
