# Mamal-Trading — Technical Documentation (Archive)

Status line (head of the document)

Status: **v0.61 (EA, `EA_VER`) / v0.62 (cockpit server)** — compiles with 0 errors / 0 warnings. New since the last documentation status: multi-language support (panel DE/EN via `InpLang`, dashboard DE/EN/FA — section 8b) · behaviour tracking `TrackSLTP`, screenshots per action and the trade file in the cockpit (section 9b) · candle-third capture (section 9c) · panel scaling with auto-fit (section 8a) · "RISK FREE" (SL to break-even, `PanelBreakEven`) · weekly risk as a mandatory input (`InpRequireWeeklyRisk`) · multi-account separation in the server. Core bugs fixed along the way: endless recursion of the translation table (section 8b), dedup grace period for the `RGP_` markers (section 7a), master deadlock (section 3a). Rule configuration unchanged: R3 daily budget 400 €, R8/R14/R19/R25 OFF. · MetaTrader 4 (MQL4) · demo · **multi-prop-firm** (FTMO = default profile, example account 20,000 €)

---

## 1. Purpose & basic principle
A risk/discipline tool built as an MT4 expert advisor. It does **not** find a strategy, it **enforces** risk and execution behaviour: automatic position sizing, hard loss locks, concentration and correlation caps, cooldowns, journal. Operated through an on-chart panel with risk-based one-click entry.

**Core architectural decision:** the EA runs *inside* MetaTrader (not as an external app), because only code inside the terminal can execute or undo order operations. An external app could not stop a manual click. Real irreversibility exists only on the server side (prop firm) or on a locked-down VPS.

---

## 2. Project structure
```
~/Desktop/TradingGuard/
  ea/mt4/MamalTrading.mq4     # the active EA (v0.35)
  ea/mt5/  (MT5 mirror still open)
  RULES.md                   # rule contract (parameters)
  docs/ARCHITECTURE.md       # architecture decision
  docs/RULES-DETAILED.md     # rule description
  docs/RULES-CHEATSHEET.md   # cheat sheet
  docs/TECHNICAL.md          # this document
```
**Installation path (Mac/Wine):**
`~/Library/Application Support/net.metaquotes.wine.metatrader4/drive_c/Program Files (x86)/MetaTrader 4/MQL4/Experts/MamalTrading.mq4`
**Logs:** terminal `…/MetaTrader 4/logs/YYYYMMDD.log` · expert `…/MQL4/Logs/YYYYMMDD.log` · journal CSV `…/MQL4/Files/MamalTrading_Journal.csv`

---

## 3. Event model & flow
- `OnInit()` — determine the starting balance (input → persisted → account balance), day/week init, `ChartSetInteger(CHART_FOREGROUND,false)` (panel on top of the candles), create controls, `EventSetTimer(1)`. **v0.35:** additionally counts pre-existing Magic-0 orders → notice + `INFO` journal entry for **R22** (does not close anything yet by itself, see section 7).
- `OnTick()` — throttled (`InpMinActionMs`=500 ms) → calls `Cycle()`.
- `OnTimer()` (1 s) → `Cycle()`. **Enforcement runs from BOTH** (tick-independent); close operations throttled via `InpCloseThrottleMs` (300 ms) + `IsTradeContextBusy`.
- `OnChartEvent()` — buttons (BUY/SELL → `GateClick`), dragging the SL line (preview), click into the chart (set the SL line).
- `OnDeinit()` — kill the timer, **`PROTECT_OFF` into the journal** (EA stopped = watchdog inactive), delete panel objects.

**`Cycle()` (the heart), in order:**
1. Check for a day change (`RollNewDay`).
2. Compute equity, day start, daily/total drawdown.
3. **R18** week change + weekly limit.
4. **R13** daily high, daily target, giveback.
5. Tamper check (AutoTrading off?).
6. **R4b** max loss, **R4** daily loss set.
7. `ResolveHistory()` (**R5/R6/R19/R25** — history-based, idempotent).
8. Close-throttled (`InpCloseThrottleMs`): **detection** — first **R22** `EnforceManualTrades()` (only outside the modify-quiet window, **before** the lock branch), then if locked `SafeCloseAll()`, otherwise `EnforceSLTP()` (R7) + `EnforceRisk()` (R1) + `EnforceRR()` (R8) + `EnforceHeat()` (R12); these **only queue tickets into the close queue** (`RequestClose`). Afterwards `ProcessCloseQueue()` performs the actual closes with retry/backoff/journal. All loops are `InScope`-filtered — **exception R22** (compares the magic directly, see section 7).
   The whole enforcement block is reached only by the **confirmed master instance** (`ClaimMaster()` true for ≥2 consecutive cycles) and only while AutoTrading is on (`IsTradeAllowed()`); passive instances return before it. `IsTradeContextBusy()` causes an immediate return.
9. Draw the panel (throttled by `InpPanelMs`=1500 ms, only on change).
10. `WriteLockstate()` — keep the lockstate file current (writes to disk only on change).

**Background:** in v0.8 trades ran **from the tick only** (to avoid Wine crashes). **From v0.15 on** enforcement runs from OnTick **and** OnTimer (tick-independent); close operations are throttled (`InpCloseThrottleMs`) + guarded by `IsTradeContextBusy`. **From v0.16 on** the actual closing goes through the real close queue (`ProcessCloseQueue`, retry limit/backoff/journal).

## 3a. Master election (single-instance lock) — heartbeat, hysteresis, deadlock fix

**Why:** the EA typically sits on several charts. Enforcement, however, is **account-wide** (filtered by magic, not by symbol) — **one** instance is enough. Several active instances would write the same files (journal CSV, lockstate, cockpit JSON) and count the same closes twice. Since v0.28 a terminal-wide election therefore decides which chart is the **master**.

| Key | Meaning |
|---|---|
| `RG_MASTER` | `ChartID()` of the master, held as a **double**; `0` = slot free (but the variable exists) |
| `RG_MASTER_HB` | heartbeat of the master, **`TimeLocal()`** |

**Why double and why `TimeLocal()`:** `ChartID()` can exceed 2^53 — the detour `long→double→long` lost the identity, so the comparison stays in `double` throughout. The clock is deliberately `TimeLocal()`: identical for all instances of **one** terminal, no drift via the server offset (`SrvTime()` is maintained per instance). *(Documentation correction: the `#define` comment on `RG_MASTER_HB` says "server time" — the code writes `TimeLocal()`.)*

**`ClaimMaster()` — three branches:**
1. `RG_MASTER == my ChartID` → refresh the heartbeat, `true`.
2. `RG_MASTER == 0` (slot free) → claim it **atomically**: `GlobalVariableSetOnCondition(RG_MASTER, myKey, 0.0)`. Only one wins; the loser gets `false`. If the variable is missing entirely, it is created **beforehand** via `GlobalVariableTemp()` with 0.0 (v0.42 fix, see below).
3. Heartbeat **stale** (`|TimeLocal()−HB| > 10 s`, absolute value → also covers clock jumps backwards) → take over via `SetOnCondition(RG_MASTER, myKey, mid)`, i.e. only if the slot still belongs to the stale master.

Otherwise `false` = someone else is the fresher master. The 10 s threshold is a buffer against slow/frozen cycles under Wine; in addition the master writes the heartbeat **at the end of the cycle as well** (`GlobalVariableSet(GV_MASTER_HB, TimeLocal())`), so a long cycle does not make it look stale mid-write.

**Hysteresis:** `g_masterStreak = ClaimMaster() ? g_masterStreak+1 : 0`. Only from **≥2 consecutive cycles** does the instance act. This prevents startup bursts and double action on a contested claim.

**Only the confirmed master does:** enforcement (R4/R6/R22 …, close queue), the entire **close evaluation** (`ResolveHistory`/`ResolveByTicketRegistry`/`ResolveManualHistory`, `HistoryVisibilityWatch`), journal/lockstate/cockpit writing, the GV flush, reading `mamal_cmd.txt` and the base self-healing (v0.38). Passive instances only draw their panel; the **click path (BUY/SELL, close buttons) works on every chart**.

**Magic divergence (v0.38):** the master publishes its `InpMagic` in `RG_MAGIC`. A passive instance with a deviating `InpMagic` warns clearly **once** — its panel trades would be neither `InScope()` nor R22 for the master, i.e. unguarded.

### The v0.42 deadlock (the project's most critical finding)
`OnDeinit()` released the master by **deleting** `RG_MASTER` (`GlobalVariableDel`). But `GlobalVariableSetOnCondition()` cannot create a **missing** variable (err 4058) — branch 2 of `ClaimMaster()` failed forever afterwards. Consequence: **after removing the master chart a master election was never possible again.** Enforcement, close evaluation and cockpit updates stood still — and **invisibly so**, because the panel kept running normally on every instance (panel drawing does not depend on the master).

**Fix, in three parts:**
- `OnDeinit()` releases via **`Set(RG_MASTER, 0.0)`** (plus `RG_MASTER_HB=0`), and only if the instance really was master. The slot continues to exist → the next instance takes over immediately via branch 2.
- `ClaimMaster()` creates a **missing** slot itself when needed (`GlobalVariableTemp`, value 0.0) and only then claims it via `SetOnCondition` — the claim atomicity is preserved, exactly one wins. This also heals a slot deleted via F3.
- **No-master alarm:** if the slot is free/orphaned (`RG_MASTER` missing or `==0`, or the heartbeat older than 10 s), a latch starts. After **30 s** without a master: `Notify("KEIN Master aktiv — Enforcement + Close-Wertung stehen STILL…")` (no master active — enforcement and close evaluation are STOPPED) + journal event **`PROTECT_OFF`** with the tag "KEIN Master seit Ns — Slot belegt/FEHLT" (no master for N s — slot taken/MISSING).

**Follow-up improvements:** *v0.43* — only raise the alarm when **really nobody** is master; a passive instance is the normal case (exactly one is master) and must not warn permanently. *v0.45* — the 30 s run **time-based** (`SrvTime()`) instead of cycle-based (the cycle rate depends on `InpTimerSeconds`), and the latch is also cleared on the transition **into** the master state (`g_noMasterSince=0`, `g_noMasterWarned=false` in the master path).

**Honest limit:** the alarm reports the state, it does not repair it. If no chart with the EA is left, there is no watchdog either — that is by design and identical to the case "EA removed / AutoTrading off".

---

## 4. Persistence (GlobalVariables)
MT4 GlobalVariables survive a terminal restart (they are stored on disk). Prefix `RG_`:

| Key | Meaning |
|---|---|
| `RG_INIT_BAL` | starting capital (for R4b) |
| `RG_DAYSTART_EQ` / `RG_DAYSTART_DAY` | equity at day start / day key (yyyymmdd) |
| `RG_LOCK_UNTIL` | server time until which the daily/giveback lock applies |
| `RG_HARD_LOCK` | 1 = permanent max-loss lock (R4b) |
| `RG_DAY_RISK` | cumulative risk % opened during the day (R3) |
| `RG_CONSEC` | consecutive losses (R5/R6/R19) |
| `RG_COOLDOWN` | server time until the cooldown ends (R5) |
| `RG_PEAK_EQ` | daily high of the equity (R13 giveback) |
| `RG_TARGET_HIT` | 1 = daily target reached (R13) |
| `RG_LAST_ENTRY` | time of the last trade (R14) |
| `RG_WEEKSTART_EQ` / `RG_WEEK_IDX` / `RG_WEEK_LOCK` | week-start equity / week index / weekly lock (R18) |
| `RG_BASE_WARN` | daily base uncertain (first start) → new trades blocked (P1-2) |
| `RG_LAST_CLOSE` | watermark of the history loss resolution (P0-2/P0-4) |
| `RGP_<…>` (per position) | position already evaluated, idempotent (P0-2/P0-4) |
| `RGEAC_<ticket>` (per ticket) | closed by the EA → does not count as a loss (P0-3, **flushed immediately**) |

**R25 revenge (v0.17, persistent):** `RG_REVD_<sym>` = losing direction (OP_BUY/OP_SELL), `RG_REVU_<sym>` = valid-until (server time). `PruneRevenge()` deletes expired pairs. Survives a restart (previously in-memory).

**Additional file mirror (v0.16):** `…/MQL4/Files/MamalTrading_Lockstate.dat` — one line `MMTLS1;<DayKey>;<Hard>;<LockUntil>;<WeekLock>;<TargetHit>;<Cooldown>;<DayRisk>;<Consec>;<Checksum>`. The checksum is a salted djb2 (HMAC-light) over the fields. At startup (`ReconcileLockstate`) the **most restrictive** state out of GV **and** file is adopted (hard lock/week lock/target/cooldown OR-combined, LockUntil/Cooldown = the later point in time, DayRisk/Consec = maximum). **Corrupted/tampered file → fail closed** (daily lock + `TAMPER` journal entry). The file is only a cross-check/backstop; the GlobalVariables remain primary.

**Resets:** `RollNewDay()` (on a server-time date change) resets the daily values (DAYSTART, DAY_RISK, CONSEC, COOLDOWN, PEAK_EQ, TARGET_HIT, LOCK_UNTIL). Weekly values on a `WeekIdx` change. `RG_HARD_LOCK` is never reset automatically. **Time base (v0.16): `SrvTime()`** = `TimeLocal()` (PC clock) + server offset (maintained on ticks from `TimeCurrent()−TimeLocal()` via `UpdateSrvOffset()`; **MQL4 has no `TimeTradeServer()`** — that is MQL5). It keeps running without ticks too; fallback is raw `TimeCurrent()`/`TimeLocal()` as long as the offset is unset. All "now" comparisons (day key `ServerDayKey`, `NextServerMidnight`, `WeekIdx`, cooldown/lock/revenge/minimum pause, markers) go through it → tick-independent, and PC clock tricks do not unlock anything. (**Documentation correction:** the R7 grace period also runs on `SrvTime()` — `EnforceSLTP` compares `SrvTime()` against the persisted naked timestamp; the earlier statement "deliberately uses `TimeLocal()`" was wrong.)

---

## 5. Risk engine & auto lot
- `RiskPctOf(sym,lots,open,sl)` = `|open−sl| / tickSize · tickValue · lots / Equity · 100`.
- `CalcLot(dist, &rp)` = `Equity · EffectiveRiskPct()/100 / ((dist/tickSize)·tickValue)`, normalised to `MODE_LOTSTEP`, capped at `MODE_MAXLOT`. Returns the lot size + the resulting risk %.
- `EffectiveRiskPct()` (**R19**) = halved (`InpDeRiskFactor`) from `InpDeRiskAfter` consecutive losses onwards, otherwise `InpRiskPerTradePct`.
- **Auto scale (dynamic caps):**
  - `EffIdeaCap()` = `AutoScale ? risk/trade · InpIdeaXrisk : InpIdeaCapPct`
  - `EffHeat()` = `AutoScale ? EffIdeaCap · InpHeatXidea : InpPortfolioHeatPct`
  - `EffDay()` = `AutoScale ? EffIdeaCap · InpDayXidea : InpDailyRiskBudgetPct`
  - Effect: change risk/trade or `InpIdeaXrisk` → idea cap, total risk and daily budget follow automatically; the trade counts (2/4/**8** from v0.20 on) stay constant.
  - **v0.20:** `InpDayXidea=4` → daily budget 2.0% = 400 €. **R19 (de-risk) is OFF** (`InpDeRiskFactor=1.0`), therefore `EffectiveRiskPct` stays constant = `InpRiskPerTradePct`.

---

## 6. Entry tool (one-click, risk-based)
- **SL line** = object `MMT_slline` (OBJ_HLINE, red, selectable). Set by **clicking into the chart** (`CHARTEVENT_CLICK` → `ChartXYToTimePrice` → `SlZoneClick`) or by **dragging** (`CHARTEVENT_OBJECT_DRAG`). **v0.21:** click-setting only takes effect after **`InpSlClicksToMove`=3** clicks into the same zone (`SlZoneClick`, tolerance ~0.15% of price or `InpSlZonePips`; 10 s window) — protection against accidentally moving it on the first click; dragging takes effect immediately.
- **BUY/SELL** = `OBJ_BUTTON`. Click → `GateClick()` → (R9 off) → `DoEntry()`.
- **`DoEntry(isBuy)` check order (all gates):**
  1. AutoTrading on? → 2. not locked (R4/R4b/R6/R13/R18)? → 3. daily target not reached (R13)? → 4. no cooldown (R5)? → 5. in session / no news blackout (R16)? → 6. no revenge counter-trade (R25)? → 7. minimum pause elapsed (R14)? → 8. SL line present + on the correct side + beyond the broker minimum distance? → 9. **R15** minimum SL distance? → 10. `CalcLot` + **R15** max lot cap + min lot? → 11. **R2** idea cap? → 12. **R3** daily budget? → 13. **R12** total risk? → 14. **R17** currency-vector correlation? → 15. `OrderSend` with the SL at the line, TP = `entry ± distance·InpRR` (magic 990201). → On success: set `RG_DAY_RISK` and `RG_LAST_ENTRY`, journal "OPEN", screenshot optional.
- **`PreviewText()`** shows direction/lot/pips/risk % live in the panel for the current SL line.
- **R22 relationship (v0.35):** only the panel path goes through this gate chain. An order opened manually in the terminal bypasses it **completely** (no sizing, no idea cap/daily budget/heat/correlation, no cooldown/session/revenge check) — which is exactly why **R22** closes such orders afterwards (section 7). R22 itself appears nowhere in the on-chart panel.

---

## 7. Rule-to-code mapping
| Rule | Implementation |
|---|---|
| R1 risk/trade | `CalcLot` (sizing) + `EnforceRisk` (closes when the current risk > limit·tolerance) |
| R2 idea cap | `IdeaOpenRiskPct(sym,dir)` + entry block in `DoEntry` (`EffIdeaCap`) |
| R3 daily budget | `RG_DAY_RISK` accumulated (additively after `OrderSend` + flushed immediately) + entry block (`EffDay`); **R3 reconciliation** `ReconcileDayRisk()` = `max(persisted, ReconstructedDayRiskPct())` |
| R4 / R4b | drawdown in `Cycle` → `RG_LOCK_UNTIL` / `RG_HARD_LOCK`; `SafeCloseAll` closes + locks. **Two separate bases:** R4 (day) against `RG_DAYSTART_EQ` = `MathMax(Balance,Equity)` at day start; R4b (total) against `RG_INIT_BAL` = starting capital (`g_initialBalance`) |
| R5 / R6 | `ResolveHistory`+`ApplyResult` evaluate losing closes (history-based) → `RG_COOLDOWN` / daily lock |
| R7 SL+TP | `EnforceSLTP` (v0.33: **4 s** deadline `InpSLTPGraceSeconds`, anchor = **since SL/TP removed/missing** via `NakedSince()`/`NakedClear()`, **not** `OrderOpenTime`; news blackout `InpSLTPGraceNews=0`; **tool trades treated identically**, no immediate-close special case; scope via `InScope(OrderMagicNumber())`). **v0.34 hardening:** the grace clock is **persistent in GlobalVariables** `RG_NK_<ticket>` (instead of an instance array) → survives restart/recompile/timeframe change/master handoff; `NakedClear(ticket,now)` does not delete immediately but starts `RG_NKH_<ticket>` and only clears after a **60 s healing period** (naked again → the healing period expires, the old clock keeps running); `PruneNaked()` clears markers of closed tickets during the 60 s housekeeping. SL/TP obligation is **tighten-only** via `EffRequireSL()`/`EffRequireTP()` (`RG_EFF_REQSL`/`RG_EFF_REQTP`) — cannot be switched off intraday |
| R8 min R:R | `EnforceRR` (reward/risk < `InpMinRR` → close) |
| R9 anti-FOMO | `GateClick` (disabled: `InpFomoGate=false`) |
| R10 no override | no unlock code; locks in GV (restart-proof); tamper warning on `!IsTradeAllowed()` |
| R11 journal | `Journal()` → CSV; `Shot()` → optional screenshot |
| R12 total risk | `TotalOpenRiskPct` + entry block + `EnforceHeat` (closes the newest) (`EffHeat`) |
| R13 daily target/giveback | `RG_PEAK_EQ`/`RG_TARGET_HIT` in `Cycle` |
| R14 minimum pause | `RG_LAST_ENTRY` + entry block |
| R15 min SL/max lot | entry block (`InpMinStopPips`) + lot cap (`InpMaxLot`) — **both default 0 = off** (v0.22, M1 scalping); only the broker `STOPLEVEL` check in the entry path remains effective |
| R16 session/news | `InSession()` + `InNewsBlackout()` → `OffSession()` entry block — **inert by default**: `InpUseSession=false` and `InpNewsFrom==InpNewsTo==0` ⇒ `OffSessionAt()` always returns `false` |
| R17 correlation | `SplitCcy`/`AddExposure`/`MaxCurrencyExposurePct` — currency vector, largest |net currency| ≤ limit (v0.17; replaces `UsdSign`/`NetUsdRiskPct`) |
| R18 weekly limit | `WeekIdx` + `RG_WEEKSTART_EQ`/`RG_WEEK_LOCK` |
| R19 de-risk | `EffectiveRiskPct()` (inside `CalcLot`) |
| R22 panel trades only (v0.35) | `EnforceManualTrades()` — loop over `OrdersTotal()`, skips anything with `OrderMagicNumber()!=0` (foreign EAs), queues every remaining order via `RequestClose`: positions (`OP_BUY/OP_SELL`) with the reason "R22 Manueller Trade — nur Panel-Trades erlaubt" (R22 manual trade — only panel trades allowed), pendings with "R22 Manuelle Pending-Order — nur Panel-Trades erlaubt" (R22 manual pending order — only panel trades allowed). **Call site: exactly one place** in the enforcement block of `Cycle()`, **before** the lock branch, only if `!modifyQuiet`. Execution is like any other close via `ProcessCloseQueue()` (positions at bid/ask with `InpSlippage`, pendings via `OrderDelete()`), retry/backoff/journal identical. Re-validation immediately before the position close: `CloseReasonStillValid()` → `StringFind(reason,"R22")==0` ⇒ `InpCloseManualTrades && OrderMagicNumber()==0`. **No symbol filter** (account-wide across all symbols), **no `InScope()`** |
| R25 revenge | `SetRevenge`/`RevengeBlocked` **persistent** in GlobalVariables `RG_REVD_`/`RG_REVU_` (v0.17; `PruneRevenge` cleans up) |

**Loss detection (R5/R6/R19/R25):** `ResolveHistory()` reads closed in-scope positions from `MODE_HISTORY`, groups them by `ProcKey` (OpenTime_Type_Symbol_Magic_OpenPrice, OpenPrice with symbol digits) → **aggregates partial closes into ONE net result**; idempotent via persistent `RGP_` markers (robust within the same second) + the watermark `RG_LAST_CLOSE`; `net<0` = loss → `RG_CONSEC++` + `SetRevenge`; profit → `RG_CONSEC=0`. EA protective closes (`RGEAC_`) do not count. Partial positions that are still open are deferred (only that group, not a global stop).

**R22 specifics (v0.35):**
- **Runs before the lock branch** → takes effect regardless of whether a lock is currently active (day/week/max loss). Previously manual trades were **not closed at all** under `TOOL_ONLY` while a lock was active: `SafeCloseAll()` skips out-of-scope orders and only warns at most once per 60 s. (Under `TOOL_PLUS_MANUAL` Magic-0 trades were already closed on a lock before.)
- **Deliberately not tied to `WatchScope`:** `EnforceManualTrades()` is the **only** enforcement function that bypasses `InScope()` and compares the magic directly. R22 therefore also takes effect in **FundedMode**, which forces `WatchScope` hard to `TOOL_ONLY`.
- **Interaction with `WatchScope=TOOL_PLUS_MANUAL`:** ineffective while `InpCloseManualTrades=true` — Magic-0 orders are already in the close queue through R22 before the scope-based enforce functions ever get to see them. The EA prints a notice about this at startup (only for exactly this combination).
- **⚠ The distinction rests solely on `Magic != 0`.** Panel trades go out with `InpMagic` (default `990201`). Anyone setting `InpMagic=0` lets R22 clear away their **own** panel trades — there is no protection against this in the code.
- **No grandfathering, but also no immediate close at startup:** `OnInit` counts pre-existing Magic-0 orders and reports them (notify + journal event **`INFO`**, tag "R22 Start: N manuelle Order(s) vorgefunden -> werden geschlossen" (R22 start: N manual order(s) found -> will be closed); with N=0 only a notify, no journal entry). **Nothing** is closed there — the first `Cycle()` is not yet master (`g_masterStreak<2`), the actual close happens in the next or the cycle after that, and on a passive instance not at all.
- **Re-validation only for positions:** pendings are deleted unconditionally in `ProcessCloseQueue()` before `CloseReasonStillValid()` is even called. A pending already queued therefore disappears even if `InpCloseManualTrades` is switched to `false` in the meantime.
- **No contribution to the streak/budget rules:** `ResolveHistory()` filters by `InScope(OrderMagicNumber())`, magic 0 is out of scope under `TOOL_ONLY`/FundedMode → a trade closed by R22 does **not** count for R5 cooldown, R6 losing streak, R19 de-risk, R25 revenge. `ReconcileDayRisk()` only counts `OrderMagicNumber()==InpMagic` → **no** consumption of the R3 daily budget. The realised loss, however, does very much hit the **equity-based** limits: R4 daily loss, R4b max loss, R18 weekly limit. `IsFaultCloseReason()` lists only R7/R1/R8 — R22 does **not** count as trader fault there.
- **Journal/cockpit:** the close tags read "Queue OK (Versuch n): R22 …" (queue OK, attempt n) or "Queue DELETE ok: R22 …" — they begin with "Queue", and `RuleIdFromTag()` only extracts a **leading** "Rxx". The EA's RuleId column therefore stays empty for R22; the mapping in the cockpit happens there through the fallback (`ruleFromTag()`). Honest limit of the statistics: every `CLOSE` line with a RuleId is counted, i.e. every RETRY, every FINAL-FAIL and every discard as well — **a single manual trade can count multiple times in "Deine Schwächen"** (your weaknesses). The `INFO` entry from `OnInit` is not counted.

## 7a. Close resolution: three paths, three dedup namespaces

Since v0.44/0.45 **three** resolvers run one after another, always in this order and only on the confirmed master:

```
if(!IsTradeContextBusy() && (OrdersHistoryTotal() != last value || ≥2000 ms elapsed))
   ResolveHistory();  ResolveByTicketRegistry();  ResolveManualHistory();  HistoryVisibilityWatch();
```
Triggered therefore by a **change of `OrdersHistoryTotal()`** or at the latest every **2 s**, never while the trade context is busy.

### Dedup namespaces and grace periods
| Namespace | Meaning | set by | Cleanup |
|---|---|---|---|
| `RGP_<OpenTime>_<Type>_<Symbol>_<Magic>_<OpenPrice>` (`ProcKey`) | position has been **rule-evaluated** | `AddProcessed()` (path 1 + 2) | `PruneGV` in the 60 s housekeeping, threshold `newFloor − 21600` → **6 h grace** |
| `RGM_<ProcKey without RGP_>` (`ManKey`) | position is **shown/counted in the cockpit** | `AddProcessed()` **and** path 3 | `SrvTime() − 2·86400` → **2 days** |
| `RGOPN_<ticket>` (`OpnKey`) | ticket **opened by the panel**, registered | `DoEntry()` (flushed immediately) + remaining ticket after a panel 50% close | **no time-based prune**: deleted deliberately as soon as the group has been evaluated / it is not a position type / it has already been processed. Tickets still open are refreshed on every run, otherwise MT4's own **4-week expiry** for GlobalVariables kicks in |
| `RGEAC_<ticket>` / `RGEACF_<ticket>` | EA close / EA close with **trader fault** (R7/R8/R1) | `MarkEaClosed()` | **2 days** each |

**v0.43 fix (critical):** previously the `RGP_` markers were pruned **immediately** along with the watermark (only the very last one survived). For `ResolveHistory` this had no consequences (the floor protects itself), but the **ticket fallback checks exactly these markers** — it found none and evaluated everything a second time: duplicate `CLOSE` lines, duplicate losing streak, duplicate net in the calendar. Since then there is a 6 h grace period.

*Documentation correction to section 7:* `ProcKey` renders the OpenPrice with **fixed precision (8 decimal places)**. The variant using `MarketInfo(MODE_DIGITS)` lives on only as `ProcKeyLegacy`; `IsProcessedAny(key, legacyKey)` honours both, so that an update does not trigger double evaluation.

### Path 1 — `ResolveHistory()` (rule path, R5/R6/R19/R25)
Scans `MODE_HISTORY` starting at the watermark `RG_LAST_CLOSE`. A line is processed if `InScope(Magic)` **or** the ticket is registered via `RGOPN_` (v0.40 fix: if the master runs with a deviating `InpMagic`, its own trades would otherwise drop out of the evaluation). Grouping by `ProcKey` → partial closes yield **one** net; the trader share (`gManNet`) and the EA share (`gEaNet`, plus a fault flag) are tracked separately. Evaluation is chronological by the latest close time, so that streak/cooldown follow the real order.
- **Future-floor self-healing (v0.41):** if `RG_LAST_CLOSE` > `SrvTime()+60`, every close would be skipped forever → reset to `ServerDayStart()` + an `INFO` journal entry.
- **Partial close:** open remainder → defer the group; but if the group is older than **10 min** and the effective net share is negative, the **realised loss is still** evaluated (losses only — a partial profit must not reset the streak prematurely).
- **Day boundary:** closes from a past server day only produce a `CLOSE` line ("does not count towards today's streak"), no `ApplyResult`.
- The new floor **never goes beyond a deferred group** and never goes backwards.

### Path 2 — `ResolveByTicketRegistry()` (safety net, v0.40)
Works exclusively through `RGOPN_` and `OrderSelect(..., SELECT_BY_TICKET)` — therefore **independent of the time-range filter of the account history tab and of the `RG_LAST_CLOSE` floor**, and independent of the magic. Flow: first **freeze** the registry (new GVs created by `ApplyResult` would otherwise shift the iteration), then per ticket:
- not resolvable → keep the key, `INFO` once per hour ("check the history cache");
- `OrderCloseTime()==0` → open, refresh the key; not a position type or already processed via `RGP_` → delete the key;
- open remainder of the position → later.

**Group aggregation (v0.40 fix):** all registered sibling legs of the same position (identical in OpenTime/type/symbol/magic/OpenPrice ±1e-7) are evaluated **together**; if one registered leg is still open, the whole group waits. Without this the fallback evaluated only the leg iterated first, and `AddProcessed` swallowed the siblings' P/L — a laundering window (profit leg first → streak reset despite a net loss). The decision afterwards is identical to path 1 (day boundary → trader share → fault EA share → otherwise "EA protective close (does not count)"), followed by `AddProcessed` and deletion of all `RGOPN_` of the group.

**Diagnostics:** at most every 60 s; into the journal (`INFO`) only on a **genuine** anomaly (unresolvable tickets), otherwise only `Print` — previously periodic INFO lines pushed real events out of the cockpit list (v0.41/0.45).

### Path 3 — `ResolveManualHistory()` (manual/foreign trades, v0.44/0.45)
Makes trades **outside** the tool (manual, mobile, foreign EAs) visible in the cockpit — as a separate event **`CLOSE_MAN`**. They change **no rule**: no losing streak, no cooldown, no daily budget; but they do count towards the net (real money) and therefore still hit the equity-based limits R4/R4b/R18.
- **Reporting window** = today's server day (`ServerDayStart()`, implausible time base → abort). The **aggregation window** is deliberately wider (`dayStart − 7 days`): a partial close from yesterday belongs to the same position net, otherwise `CLOSE_MAN` reports only a partial amount.
- **Filter order (v0.45):** the cheap checks first (close time, type, `InScope` → belongs to path 1, `RGOPN_` → belongs to path 2), only then the GV lookups. `GlobalVariableCheck` is O(N_GV) and previously ran on **every** history line — with "entire history" loaded that meant tens of thousands of lookups every 2 s (Wine freeze risk).
- **Double counting ruled out (v0.45):** before reporting, a cross-check against the rule path (`IsProcessedAny` over `RGP_`/legacy). If it hits, only the `RGM_` marker is set and nothing is journalled — otherwise a trade evaluated via the ticket registration (magic divergence/scope change) could **additionally** appear as `CLOSE_MAN` → duplicate net in the dashboard.
- **Marker before journal:** `RGM_` is set **before** the journal line and its success is checked; if the GV creation fails (name length/GV limit) there is a single `INFO` line instead of the same line every 2 s.
- Journal line: event `CLOSE_MAN`, net in the net column, tag "Manueller/fremder Trade (Magic n) — außerhalb der Tool-Regeln, nur Anzeige" (manual/foreign trade (magic n) — outside the tool rules, display only).

**Evaluation in the cockpit:** the server takes the net for `CLOSE_MAN` from the **net column** (whereas for normal `CLOSE` lines it takes it from the `net …` text in the tag), counts them in the calendar/net/trade statistics and additionally reports them separately (`totals.manualN`/`manualNet`, daily counter `manual`). The dashboard marks them orange or with "✋"; a day with manual trades does **not** count as a clean day and breaks the discipline streak.

**Honest limit:** paths 1 and 3 see only what the account history tab has loaded (`OrdersHistoryTotal()`) — `HistoryVisibilityWatch()` stands against that as a fail-closed watchdog. Only path 2 is independent of this filter, but it covers **registered panel tickets** exclusively.

---

## 8. On-chart panel
- Objects with the prefix `MMT_`: card (`OBJ_RECTANGLE_LABEL`), header line, status, two bar meters (daily/total loss), preview line, footer (heat/budget/stops), BUY/SELL buttons.
- **Performance/crash protection:** `DrawPanel` runs at most every `InpPanelMs`=1500 ms and only if a status signature (`g_panelSig`) changes → at rest there is **no** `ChartRedraw`. Static object properties are set only once, at creation.
- **Status strings (exact, 9 of them).** The panel (`DrawPanel`) and the cockpit JSON (`WriteCockpit`) use **the same** cascade in **this priority order** — the first hit wins:
  1. `SCHUTZ AUS` (protection off, amber) — AutoTrading off
  2. `MAX-LOSS GESPERRT` (max loss locked, red) — `IsHardLocked()`, R4b permanent
  3. `WOCHE GESPERRT` (week locked, red) — `IsWeekLocked()`, R18
  4. `TAG GESPERRT` (day locked, red) — `IsDayLocked()`, R4/R6/R13
  5. `MAX-LOSS WARNUNG` (max loss warning, amber) — R4b warn gate
  6. `COOLDOWN` (amber) — R5
  7. `ZIEL ERREICHT` (target reached, green) — R13
  8. `AUSSER SESSION` (out of session, neutral) — R16
  9. `AKTIV` (active, green)
  The three lock strings 2–4 come from **one** nested expression (`IsHardLocked() ? … : IsWeekLocked() ? … : "TAG GESPERRT"`), i.e. with multiple locks only the **hardest** one is displayed. *(Documentation correction v0.34: this used to say a generic "GESPERRT" — the code does not know that string.)*

## 8a. Panel scaling — `PScale`/`SScale`/`FScale` → `PS()`/`PF()` + auto-fit

**Two opposing problems.** With a Windows scaling > 100%, MT4 renders the *font* larger but leaves the pixel coordinates (`OBJPROP_XDISTANCE`/`YDISTANCE`/`XSIZE`/`YSIZE`) unscaled → the panel overlaps itself (v0.37). Conversely, on small or split charts the panel is taller than the chart window → the lower buttons lie outside the visible area and can no longer be clicked (v0.46).

**Three factors, two helpers:**

| Function | Source | Clamping | Affects |
|---|---|---|---|
| `PScale()` | `InpPanelScale`; **0 = AUTO** from `TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0` (144 dpi → 1.5; DPI unavailable → 1.0) | AUTO never < 1.0; then hard `0.5 … 3.0` | geometry **and** font |
| `SScale()` | `InpShapeScale` | `0.5 … 2.0` | geometry only |
| `FScale()` | `InpFontScale` | `0.5 … 2.0` | font size only |

- `PS(v) = round(v · PScale() · SScale())` — every X/Y distance, every width/height.
- `PF(v) = round(v · PScale() · FScale())`, the result **never below 6 pt** — every `OBJPROP_FONTSIZE`.

Both are applied **centrally** in the drawing helpers (`Lbl`, `LblR`, `RectB`, `Btn`, `EnsureRiskEdit`, `DrawCandleClock`); the call sites pass unscaled constants throughout and never compute anything themselves. The click hit test on the panel area also runs through `PS()` (`cx/cy` against `PS(12)…PS(312)` resp. `PS(16)+PS(PanelH())`) — otherwise a click on the scaled panel would fall through as an SL zone click (section 6).

**Auto-fit (`InpPanelAutoFit`, on by default)** runs as the last step *inside* `PScale()`, i.e. after the clamping:
```
ph = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
if (ph > 120) { need = (PanelH() + 28) * s;
                if (need > ph) s = s * (ph / need);
                if (s < 0.6)   s = 0.6; }
```
`PanelH()` computes **unscaled** (base 372 px) and grows with the optional rows: risk chooser (`RiskRowOff()`), RISK FREE button **+26**, test harness **+72**. Auto-fit therefore bites harder exactly when more controls are active. The 28 px are the top/bottom margin. Below a chart height of 120 px no adjustment happens at all (nothing sensible can be displayed there anyway). The floor of **0.6** prevents an unreadably small panel — if the window is flatter still, the panel deliberately sticks out again (better cut off than unreadable).

**v0.48 fix:** a **manually** set `InpPanelScale` may now also *shrink* the panel. Previously the 1.0 lower bound of the AUTO derivation sat on the whole path and clamped away any wish for a smaller panel (`InpPanelScale=0.7` had no effect). Since then the 1.0 lower bound applies **only** in the AUTO branch (`InpPanelScale<=0`).

**Documentation correction / honest limit:** the header comment of `PScale()` (v0.37) says that the font size is deliberately *not* scaled, "MT4 scales that itself". Since v0.46, however, `PF()` multiplies by `PScale()` as well. If the comment's assumption holds, font scaling in AUTO mode therefore takes effect **twice** (once through MT4, once through `PF()`). Remedy without a code change: lower `InpFontScale` accordingly (e.g. 0.7 at 150% Windows scaling) or set `InpPanelScale` manually. Second limit: `PScale()` re-reads `CHART_HEIGHT_IN_PIXELS` on **every** call — the scaling therefore follows a window resize immediately, but the objects are only repositioned at the next `DrawPanel` (at most every `InpPanelMs`=1500 ms, and only on a signature change); right after dragging the window edge the panel can briefly sit wrong.

---

## 8b. Multi-language support — panel (DE/EN) and dashboard (DE/EN/FA)

Two **independent** translation layers with separate switches. They share neither the table nor the placeholder convention and may deliberately diverge.

| Layer | Languages | Switch | Table | Keys |
|---|---|---|---|---|
| On-chart panel (MQL4) | DE / EN | EA input `InpLang` (`enum PanelLang { LANG_DE, LANG_EN }`), v0.53 | function `T()` in the EA | **153** |
| Dashboard (browser) | DE / EN / **FA** (Persian, RTL) | selector in the header, remembered in `localStorage.mamalLang` | `cockpit/i18n.js` → `window.MAMAL_I18N` | **346** per language |

### Panel: `T()` / `TF()`
- `T(key)` is a linear `if(k=="…") return en? "…" : "…";` cascade with `bool en = (InpLang==LANG_EN)` in one single place. An **unknown key returns the key itself** (`return k;` at the end) — the error shows up immediately in the panel instead of vanishing as empty text.
- `TF(key, a0, a1, a2, a3)` calls `T(key)` and then replaces `{0}`…`{3}` via `StringReplace` (v0.54; the fourth placeholder arrived with v0.57).

**Why `{0}` and not `%s`/`%d`:** `StringFormat` binds the order of the values to the format string. In English, however, word order is often different from German ("noch {0} Min" vs. "{0} min left"). With numbered placeholders every language version can **order its values freely, use them multiple times or omit them**, without the call site changing. That is exactly why the callers now pass only finished strings (`IntegerToString`/`DoubleToString`) — formatting happens before `TF()`, not inside it.

*Honest limit:* `TF()` replaces **sequentially** `{0}` → `{1}` → `{2}` → `{3}`. If a value inserted earlier itself contained the character sequence `{1}`, it would be replaced again in the next round. In practice the arguments are numbers, symbol names and percentages — the case does not occur, but it is not guarded against.

### The table is the end point — replacement runs must exclude it
**v0.61, endless recursion (critical finding).** An automatic search-and-replace run, meant to replace German literals in the code with `T("…")`, also replaced the German texts **inside the translation table**. Result: **22 entries** whose "translation" was another `T()` call → `T()` called itself, without bound. Consequence: **stack overflow** in the log, the EA died in the middle of drawing the panel, the panel was left half empty. There was no compile error and no warning — the recursion is syntactically flawless.

**Rule derived from this:** `T()`/`TF()` are the **terminal point** of the translation. Every replacement run (script, IDE refactoring, mass regex) must **explicitly exclude** the function body of `T()` — not "hopefully it won't hit it". The table may return literals only; a `T(`/`TF(` inside the body is by definition a bug and is trivially checkable (`grep` for `T(` between `string T(string k)` and its `return k;`).

**Residue of the same run (verifiable, still in the code today):** the table contains 18 keys with the prefix `misc.`, of which only **two** are ever queried (`misc.tradeContextBusy`, `misc.orderSendFailed`). The other **16** (`misc.fragment*`, `misc.artifact*`) carry truncated MQL4 code fragments as their "text" — the extraction run had cut arbitrary string literals out of the source. They are functionally harmless (nobody queries them, DE and EN are identical), but they are the visible evidence for the rule above and should be cleaned up.

### Dashboard: `t()` / `i18n.js`
- `t(key, params)` reads `MAMAL_I18N[LANG][key]`, falls back to **German** on a missing key (`T.de[key]`) and only then to the empty string — the interface is never empty.
- Placeholders here are **named** (`{account}`, `{n}`, `{min}`) and are replaced via `split/join`; individual keys additionally use `{0}`. This is deliberately a different convention from the panel: the dashboard has no format-string restriction, and named placeholders are self-explanatory when translating.
- `applyLang()` sets `document.documentElement.lang`, fills all `[data-i18n]` elements and then forces a complete rebuild (`prevS=null; g_forceRedraw=true; tick(); loadAnalytics(); loadEquity()`), so that dynamically generated texts switch as well.
- **Persian/RTL:** `root.dir = (LANG==='fa') ? 'rtl' : 'ltr'`. The CSS mirrors table alignment, the calendar accent stroke and the heading line. **Numbers stay left-to-right** via `html[dir="rtl"] .mono, .v, .lm-val { direction: ltr; unicode-bidi: embed }` — without this, amounts, times and percentages would be reordered by the bidi algorithm.
- The server serves `cockpit/i18n.js` through its own endpoint `/i18n.js` with `Cache-Control: no-store`.

### The journal stays German — deliberately, not by oversight
The journal CSV (section 9) is **not** translated: event names and the free-text tag remain German throughout. Two reasons, both hard:
1. **Audit trail.** A file whose texts change retroactively with an EA input is worthless as evidence; lines from yesterday and today must remain comparable word for word.
2. **The server parses the text.** `tradeDossier()` classifies the SL/TP moves by regex over the German tag (`/Risiko ERHOEHT|Risiko unbegrenzt/`, `/Risiko gesenkt/`, `/Gewinn abgekuerzt/`, `/Ziel vergroessert/`, see section 9b), and `RuleIdFromTag()` resp. `ruleFromTag()` extract the rule ID from the beginning of the tag. A translated journal would make this evaluation fail **silently** — no error message, just suddenly zeros everywhere.

**Honest limits of the conversion:**
- **The status string in the cockpit follows the panel language, not the dashboard language.** `WriteCockpit()` writes `status` through the same `T("status.*")` cascade as the panel (section 8), and the dashboard shows `s.status` **raw** (status pill, account list). With `InpLang=LANG_EN` it therefore says "DAY LOCKED" there, even if the dashboard is running in German or Persian. In addition, a legacy-EA fallback in the dashboard compares against the German literal `'MAX-LOSS WARNUNG'`; it only applies to EA versions without the `maxWarn` field and silently becomes ineffective with `LANG_EN`.
- **Coverage is not complete.** Individual dynamically built blocks in the dashboard are hard-wired in German — among them the tiles of the trade statistics ("Expectancy / Trade", "Beste Stunde" (best hour), "Einstieg in der Kerze" (entry within the candle) including früh/mittig/spät (early/middle/late)) and the entire trade file (`trade.html` plus the summary phrased in the server, section 9b). The language switch leaves these texts unchanged.

---

## 9. Journal format (CSV, separator `;`)

## 9a. Cockpit data bridge (EA → files → local server)

The bridge is **DLL-free**: the EA writes files into `…/MQL4/Files`, a local Node server (`cockpit/server.js`, zero dependencies) reads them and serves the dashboard from them on `127.0.0.1`. There is **no** back channel except the command file (below) — and that one can in principle only **tighten**.

### Files
| File | Location | Purpose |
|---|---|---|
| `mamal_cockpit.json` | `MQL4/Files` | live state, written by the master every **2 s** |
| `mamal_cockpit.tmp` | `MQL4/Files` | intermediate file; `FileMove(...,FILE_REWRITE)` replaces the JSON **atomically** → no torn read |
| `mamal_cockpit_open.txt` | `MQL4/Files` | trigger of the panel button "COCKPIT" → server opens the browser |
| `MamalTrading_Journal.csv` | `MQL4/Files` | event source for calendar/statistics (section 9) |
| `mamal_files.txt` | **Common**/Files | signpost (legacy, one terminal) to the real Files folder |
| `mamal_files_<login>.txt` | **Common**/Files | v0.38: signpost **per account** → account switcher in the dashboard |
| `mamal_cmd.txt` | `MQL4/Files` | v0.39: command from the dashboard, tighten-only |

### JSON state
`WriteCockpit()` builds the string by hand (no serializer) and writes, among others: `v`, `srvtime`, `account`, `symbol`, `tf`, `port`, `profile`, `funded`, `equity`, `balance`, `ccy`, `initBal`, `status`/`statusColor`/`protectOff`, `dailyDD`/`dailyLimit`, **`dayBase`/`weekBase`** (v0.39, the basis for the € buffer gauge), `totalDD`/`maxLoss`/`maxLossWarn`, `protOff`/`tightenOnly`, `dayRisk`/`dayBudget`, `heat`/`heatCap`/`ideaCap`/`riskPerTrade`/`riskNextWeek`, `consec`/`lockAfter`/`cooldownAfter`/`cooldownSec`/`cooldownMin`, `weekDD`/`weekLimit`, `targetPct`/`profitPct`/`givebackPct`, the flags `dayLock`/`hardLock`/`weekLock`/`targetHit`/`baseWarn`/`cooldown`/`offSession`/`maxWarn`, `minStopPips`/`rr`/`scope`, `fills`/`blocks`/`riskEstimate` as well as `disabled[]` (deactivated rules → dashboard chip "— aus" (off), among them `R22` when `InpCloseManualTrades=false`).

- The status cascade is **the same** as in the panel (section 8) — cockpit and panel cannot diverge.
- The write cycle deliberately has **no `IsTradeContextBusy()` gate**: `WriteCockpit()` does pure file I/O and never touches the trade thread. With a gate the JSON would go stale exactly when it becomes interesting (close queue retries).
- `account` is a **string** (overflow-safe) and serves the server as the account identity.

### Beacons (Common folder)
A terminal's Files folder depends on an instance hash or on the portable path — the server cannot guess it. The EA therefore places a signpost in the **Common** folder (`FILE_COMMON`, fixed path) containing `TerminalInfoString(TERMINAL_DATA_PATH)+"\MQL4\Files"`: once as `mamal_files.txt` (legacy) and once as `mamal_files_<login>.txt` (v0.38, per account → several terminals no longer overwrite each other).

It is written **once per session/account** (latch `beaconAcct`), not every 2 s — this saves I/O and removes the read race on a half-written path line. *Honest limit:* the latch is only set when `AccountNumber() > 0`; without a logged-in account the write attempt is repeated on every cycle.

### Server: folder discovery and endpoints
`allFilesDirs()` = `MAMAL_FILES` (override) → otherwise, on Windows, all `%APPDATA%\MetaQuotes\Terminal\<hash>\MQL4\Files`, with the beacon folders in front of them (covers portable mode); on macOS the known Wine path. Directory scans and the beacon list are **cached for 1.5 s** (the dashboard polls once per second and the paths often sit on OneDrive/AV-scanned drives).
- **Without `?acct=`** the **freshest** `mamal_cockpit.json` wins (mtime). Since v0.38 the legacy signpost has **no** priority any more — with two terminals writing live, the display used to jump between accounts.
- **With `?acct=`** (digits only, path injection ruled out): account beacon → but **verified** against `state.account` (stale beacon after a login change) → otherwise search all folders. `readState()` **never** returns data of a foreign account under the requested label.

- Endpoints: `/state`, `/accounts`, `/journal`, `/analytics`, `/day`, `/equity`, `POST /cmd/endday`, **`/trades`**, **`/trade?ticket=`**, **`/shot/<file>`** (v0.62, section 9b), `/i18n.js` (v0.53, section 8b) as well as the pages `/` `/day.html` `/report.html` `/trade.html`; `/favicon.ico` is acknowledged with 204, everything else with 404. The server binds to `127.0.0.1` and additionally checks the Host header (DNS rebinding protection). The `acct` parameter is reduced to digits centrally **in one place** (`replace(/\D/g,'')`) and then applies to all endpoints.

- `/journal` filters **first** (`OPEN`/`CLOSE`/`CLOSE_MAN`/`BLOCKED`, `PROTECT*`, lock/cooldown/target tags) and truncates to 120 lines **afterwards** (v0.45 fix — previously periodic INFO lines pushed out real events).
- CSV parsing is cached by **mtime+size** (max 8 entries); the free-text tag is reassembled after the split, otherwise a `;` inside the tag would lose the `net` amount.

### Command channel `mamal_cmd.txt` (strictly tighten-only)
Dashboard button "Tag beenden" (end the day) → `POST /cmd/endday`. Server-side safeguards: **POST only**; **origin check** (if the header is missing, e.g. curl → ok; if it is set, it must come from `localhost`/`127.0.0.1:PORT` — a cross-site form POST would otherwise carry a matching Host header); **`acct` is mandatory** (otherwise the lock could land in the wrong account when two terminals are writing live). What gets written is `endday <timestamp>` as BOM-free latin1 into **this** account's Files folder.

EA side (at the end of `Cycle()`, i.e. only on the master): read the file, **delete it immediately**, check the prefix `endday`. The only effect: `RG_LOCK_UNTIL` to `NextServerMidnight()` — and **only if that extends the lock** (`nxt > cur`); an already longer lock can never be shortened by `endday`, loosening is fundamentally impossible through this channel. Then **immediately** `GlobalVariablesFlush()` + `WriteLockstate()` (the command file is already gone; a crash within the 1 s window must not lose the voluntary lock) and the journal event **`SELF_LOCK`**. If the file cannot be deleted (read-only/AV lock), the command is **ignored** and logged once — otherwise it would be processed again every second.

*Addendum to section 9:* to the events listed there, the following have since been added: **`SELF_LOCK`** (v0.39), **`PANEL_CLOSE`** (v0.40, close buttons), **`CLOSE_MAN`** (v0.44, section 7a), **`BREAKEVEN`** (v0.46, the "RISK FREE" button — both success *and* failure with an error code are written) and **`SLTP_MOVE`** (v0.47, behaviour tracking, section 9b). For the `OPEN` event the tag has, since v0.52, additionally carried the candle third (`in-plan K2/3`, section 9c).

### Equity sampler (in the server, not in the EA)
The equity curve is produced **on the server side** — the EA stays unchanged for it. Every **5 s** the server reads the known accounts and, for every account that is **writing live**, appends a line `epochMs;equity;dayBase` to `cockpit/data/equity_<account>.csv`. Filtering: JSON older than **15 s** → skip (no sampling of dead terminals); `equity` must be a number; the account ID must be **purely numeric** (v0.39 fix — otherwise non-numeric IDs collided in `equity_.csv`).

**Capping:** hourly; files `equity_<digits>.csv` from **2 MiB** onwards are truncated to the last **20,000** lines (≈ 1 day at 5 s). `/equity?acct=&n=` returns the last `n` points (default 2000) as `{t, eq, base}`, implausible lines are dropped; without `acct` the freshest account is taken.

**Honest limits:** resolution 5 s, and sampling only happens while **the server is running** — if `node` is stopped, a gap appears even if MT4 keeps running. The value also comes from the JSON (2 s cycle), so it can be up to ~2 s old. The CSVs live in the project folder (`cockpit/data/`), not in `MQL4/Files` — if the cockpit folder is set up afresh, the history is gone.

## 9b. Behaviour tracking (`TrackSLTP`), screenshots and the trade file

Three parts that build on each other: the EA **logs** every SL/TP move with a substantive verdict (v0.47), it stores an **image with the ticket in the file name** for every action (v0.47), and the server builds a **trade file** per ticket out of that (v0.62). None of the parts interferes with rules — it is pure observation.

### `TrackSLTP()` — who drags the stop where
**Position in the cycle:** directly after the close resolution block, **before** the enforcement block. Three conditions must hold at the same time: `!modifyQuiet`, `!IsTradeContextBusy()` and ≥ **2000 ms** since the last run. Like the whole block, it only runs **on the confirmed master** (the `g_masterStreak<2` return lies before it).

**Why not during `modifyQuiet`:** dragging an SL line with the mouse produces dozens of intermediate values. Without this lock every intermediate step would count as a separate move, and the statistic "moved N times" would be pure noise. Only the **result after releasing the mouse** is counted (the quiet window is a sliding 2 s, hard-capped at a 10 s series — section 3).

**Reach:** `InScope(OrderMagicNumber()) || GlobalVariableCheck(RGOPN_<ticket>)` — identical to the rule in `PanelBreakEven`. A panel trade with a deviating magic therefore remains covered; foreign EAs stay out.

**State per ticket** (GlobalVariables, survive a restart):

| Key | Content |
|---|---|
| `RGSLS_<ticket>` | last seen **SL** |
| `RGTPS_<ticket>` | last seen **TP** |

On the **first sighting** of a ticket (`firstSight`: both markers missing) the markers are only set, **without** a journal line — otherwise every EA start would report every open position as "moved". The noise threshold is `eps = MarketInfo(sym, MODE_POINT)/2` (fallback `Point/2`): changes below half a point do not count as a move.

**Verdict** — what is judged is the **distance to the entry**, `dOld = |OrderOpenPrice() − old|` against `dNew = |OrderOpenPrice() − new|`:

| Case | Condition | Tag in the journal (German, untranslated) |
|---|---|---|
| SL set for the first time | `old == 0` | "SL erstmals gesetzt" (SL set for the first time) |
| SL removed | `new == 0` | "SL ENTFERNT — Risiko unbegrenzt (nachteilhaft)" (SL REMOVED — risk unlimited (disadvantageous)) |
| SL further away | `dNew > dOld+eps` | "SL WEITER weg vom Einstieg (alt -> neu) — **Risiko ERHOEHT (nachteilhaft)**" (SL moved FURTHER from the entry (old -> new) — risk INCREASED (disadvantageous)) |
| SL closer in | `dNew < dOld−eps` | "SL naeher an den Einstieg (alt -> neu) — Risiko gesenkt[, **Break-Even erreicht**] (vorteilhaft)" (SL moved closer to the entry (old -> new) — risk reduced[, break-even reached] (advantageous)) |
| SL sideways | otherwise | "SL seitlich verschoben (Risiko unveraendert)" (SL moved sideways (risk unchanged)) |
| TP removed | `new == 0` | "TP ENTFERNT — kein Ziel mehr definiert" (TP REMOVED — no target defined any more) |
| TP closer in | `dNew < dOld−eps` | "TP NAEHER an den Einstieg (alt -> neu) — **Gewinn abgekuerzt**" (TP moved CLOSER to the entry (old -> new) — profit cut short) |
| TP further away | `dNew > dOld+eps` | "TP WEITER weg (alt -> neu) — Ziel vergroessert" (TP moved FURTHER away (old -> new) — target enlarged) |

The break-even addition applies when `(BUY && sl >= entry−eps) || (SELL && sl <= entry+eps)`. Every detected move produces **one** `SLTP_MOVE` line (with ticket, symbol, direction, lot, entry, new SL/TP; the risk % column stays 0) plus a screenshot `slmove` or `tpmove`. SL and TP are checked separately — a change of both values in one `OrderModify` yields **two** lines and **two** images.

**Honest limits:**
- `TrackSLTP()` only sees *that* the value changed, not *who* changed it. A click on **RISK FREE** (`PanelBreakEven`, `OrderModify` to `OrderOpenPrice()`) therefore shows up on the next run **additionally** as an `SLTP_MOVE` with the verdict "risk reduced, break-even reached" and is counted in the trade file as a risk-reducing move. The only way to tell the two apart is the parallel `BREAKEVEN` line.
- The markers `RGSLS_`/`RGTPS_` are deleted **in one place only**: in `ResolveByTicketRegistry()` (path 2, section 7a), immediately after `Shot("close")`. If **path 1** (`ResolveHistory`) resolves the position — the normal case with a visible account history — path 2 bails out beforehand via `IsProcessedAny(...) → GlobalVariableDel(RGOPN_) ; continue` and never reaches the cleanup line. No `PruneGV` call covers these two prefixes (they carry prices, not timestamps, and a time-based prune would also be wrong). The markers therefore stay until MT4's **4-week expiry**. There is no collision risk (MT4 tickets are not reused), it is pure GV ballast — but measurable at a high trade frequency.

### Screenshots — naming scheme and cleanup
`Shot(tag, ticket)` writes via `ChartScreenShot` into `MQL4/Files`:
```
Mamal_<ticket>_<tag>_<epoch>.png        epoch = (int)SrvTime()
```
Controlled by `InpScreenshots` (default **on** since v0.47) plus `InpShotWidth`/`InpShotHeight` (1100 × 620). `ticket = 0` means "no trade reference". There are exactly **four** tags:

| Tag | Call site |
|---|---|
| `open` | `DoEntry()` immediately after a successful `OrderSend` |
| `close` | `ResolveByTicketRegistry()` after the group has been evaluated |
| `slmove` / `tpmove` | `TrackSLTP()` per detected move |

The ticket **in the file name** is the whole trick: server and dashboard assign every image to exactly one trade without an additional index, and the epoch part maintains the chronology.

`PruneShots()` runs in the **60 s housekeeping** (not at the enforcement rate): `FileFindFirst("Mamal_*.png")`, timestamp = the block of digits **after the last `_`**, and everything older than `InpShotKeepDays` is deleted (default 14; `0` = never clean up). Hard brake: **at most 200 deletions per run** (`killed<200` in the loop condition) — otherwise a single run would block the cycle with file I/O, which under Wine is the known crash path. The rest follows in the next housekeeping.

*Honest limits:* a file name without a parsable timestamp is skipped permanently. And the screenshot always shows **the chart on which the call happens** — `open` lies in the click path (i.e. the chart that was traded on), whereas `close`/`slmove`/`tpmove` run on the **master** chart. With several symbols the exit image can therefore show a different instrument than the trade. In addition, the `close` image only comes into being **if** path 2 actually resolves the position; if it is evaluated by path 1 (the normal case), there is no exit image.

### Trade file in the cockpit (v0.62): `/trades`, `/trade`, `/shot`

| Endpoint | Behaviour |
|---|---|
| `/trades` | `tradeList(acct)` — groups **all** journal lines by ticket (`ticket` empty or `0` is discarded). Time/symbol/direction/candle third come from the `OPEN` line, `SLTP_MOVE` is counted, `net` comes from the first `CLOSE` line with a net. Sorted by time descending, **capped at 200** tickets. |
| `/trade?ticket=` | `tradeDossier(...)` — `ticket` reduced to digits beforehand (`replace(/\D/g,'')`). Collects `OPEN`, the first `CLOSE` with a net, all `SLTP_MOVE`, all `PANEL_CLOSE` and all `BREAKEVEN`. |
| `/shot/<file>` | delivers the PNG from the account's Files folder (see path traversal protection below). |
| `/trade.html` | the page itself (list without `ticket`, file with `ticket`). |

**Key figures of the file** (`stats`): `moves` (number of moves), `slWorse`/`slBetter`/`tpShorter`/`tpLonger` (classification by regex over the German tags, see the table above and section 8b), `plannedRisk`, `net`, `third`.

**Planned risk in account currency** is reconstructed from **the same** `OPEN` line:
```
plannedRisk = balance(column 4) · risk%(column 14) / 100
```
Deliberately the balance of **that line** and not today's — otherwise the planned risk would shift retroactively with every change of the account balance.

**Automatic summary** (`summary`, plain sentences in a fixed order): opening with lot/time/planned risk → candle-third classification → move balance (or "SL und TP blieben unverändert — der Plan wurde eingehalten" (SL and TP remained unchanged — the plan was followed)) → a warning sentence on `slWorse` → praise when all moves were risk-reducing → a note on a shortened target → RISK FREE and panel close remarks → result. For closed losing trades, the **comparison of plan against result** follows, with a threshold factor of **1.15**:
- `|net| > plannedRisk · 1.15` → "The loss is X.X× above the planned risk — check the cause (moved stop, slippage or gap)."
- otherwise → "The loss stayed within the planned range — that is exactly how a stop should work."

**Screenshots** come from `shotsFor(ticket, acct)`: `readdirSync` of the account's Files folder, filter `^Mamal_<ticket>_([a-z0-9]+)_(\d+)\.png$`, sorted by epoch → entry, moves and exit lie chronologically side by side (full-screen zoom in `trade.html`).

**Path traversal protection on `/shot/`** — three stages, in this order:
1. `decodeURIComponent(p.slice(6))` **first**, the check **afterwards**. This order is the actual protection: `%2e%2e%2f` is first resolved to `../` and then fails the check. A check before decoding would be bypassable.
2. Whitelist instead of blacklist: `/^Mamal_\d+_[a-z0-9]+_\d+\.png$/i` — the name may consist **exclusively** of this pattern. Slash, backslash, `..`, drive letter, null byte and Unicode variants all fail it without having to be enumerated individually. Violation → `400`.
3. Only then `path.join(dir, name)` with `dir = dirForAccount(acct) || currentFiles()` — so nothing is ever read from anything but a known `MQL4/Files` folder. Missing file → `404`.

Delivery uses `Content-Type: image/png` and `Cache-Control: max-age=86400`; that is harmless because the epoch part makes the file name effectively immutable.

**Access:** the 📁 button in the dashboard header (opens `/trade.html` in a new tab); in addition, journal lines **with a ticket** are clickable and jump straight into the file.

**Honest limits:**
- The file is built **solely** from journal lines and file names — there is no broker query. If the `OPEN` line is missing (deleted journal, manual trade, trade before v0.47), there is neither planned risk nor candle third; without `InpScreenshots` there are no images.
- The classification of the moves reads the **German** tag text. Anyone translating the journal texts silently sets `slWorse`/`slBetter`/`tpShorter`/`tpLonger` to 0 (section 8b).
- `/trades` calls `shotsFor()` **per ticket**, and `shotsFor()` does its own `readdirSync` every time — with 200 tickets that means up to 200 uncached directory scans per call. On OneDrive/AV-scanned drives (section 9a) the list is noticeably sluggish because of this. The 1.5 s cache of the folder discovery does **not** apply here.
- The trade file is German-only (neither `trade.html` nor the `summary` sentences are hooked up to `/i18n.js`).

---

## 9c. Candle thirds — entry timing within the running candle

**The question being answered:** is the trade taken early in the candle (an own decision) or late (a reaction to a move that has already happened)? Until now the cockpit only showed *when during the day* the click happened, not *where in the candle*.

### Capture in the EA (v0.52)
```
int CandleThird(datetime t)
{
   int per = PeriodSeconds();  if(per<=0) return 0;
   int el  = (int)(t % per);   if(el<0) el=0;      // seconds elapsed in the candle
   int th  = (el*3)/per;       if(th>2) th=2;      // 0 = early, 1 = middle, 2 = late
   return th;
}
string CandleThirdTag(datetime t){ return StringFormat("K%d/3", CandleThird(t)+1); }
```
The modulo calculation exploits the fact that MT4 candles sit on a fixed grid (`Time[0]` is always a multiple of `PeriodSeconds()`) — it needs no access to the bar series and no special case for the first candle.

`DoEntry()` appends the result to the tag of the `OPEN` line: `"in-plan " + CandleThirdTag(TimeCurrent())` → e.g. `in-plan K2/3`. The format is deliberately machine-readable (`K1/3` … `K3/3`) and sits in the same column as the free text, so that no CSV field is added (section 9 stays at 18 columns).

**The time base is `TimeCurrent()`, not `SrvTime()`** — and that is not an oversight: the candle grid lies in **broker time**, and `Time[0]` comes from the same source. `SrvTime()` (PC clock + maintained offset, section 4) could be off by seconds when the offset is stale and determine the wrong third. *Honest limit:* `TimeCurrent()` stands still without fresh ticks — in a very tick-poor market the third can therefore be reported too **early**. For a third of an M1 candle (20 s) that is relevant, for M15 practically not.

### Countdown right next to the candle (`DrawCandleClock`, v0.52)
In addition to the countdown in the panel header, the EA draws an `OBJ_TEXT` (`MMT_cclock`) **onto the chart**, anchored at `Time[0] + PeriodSeconds()` (one slot to the right of the running candle) at the level of the current bid, with `ANCHOR_LEFT` — so it travels along with the candle. Text `mm:ss` (remaining time), font `InpPanelMono` at `PF(9)` (section 8a). The colour follows the **elapsed** third and therefore exactly the same `CandleThird()` logic as the logging: green → orange → red. Controlled via `InpCandleTimeOnChart && InpShowCandleTime`; if either is off, the object is deleted rather than merely hidden.

### Evaluation in the cockpit
`analytics()` maintains three parallel structures:
- `thirds[3]` — number of entries per third, in total **and** per calendar day (`d.thirds`),
- `byTicketThird[ticket]` — ticket → third from the `OPEN` line (regex `\bK([123])\/3\b`),
- `thirdNet[3]` — **net per third**; the `CLOSE` line finds its third via `byTicketThird`.

Only the combination carries the statement: frequency alone says nothing, what matters is in which third money is actually made. The dashboard shows this as the tile **"Einstieg in der Kerze"** (entry within the candle) — three counters `früh · mittig · spät` (early · middle · late) in green/amber/red, with a tooltip per third giving count and net, and below it the sentence "am besten läuft **<Drittel>** (<Netto>)" (**<third>** performs best (<net>)) naming the third with the highest net. The tile is hidden if not a single entry carries a third (journal from before v0.52). The trade file (section 9b) translates the same field individually into plain text ("Einstieg im letzten Kerzendrittel — spät; oft eine Reaktion auf eine schon gelaufene Bewegung." — entry in the last candle third — late; often a reaction to a move that has already happened).

**Honest limits:** the third refers to the **timeframe of the chart that was clicked on** — the same clock time yields different thirds on M1 and M15; aggregating across several timeframes therefore mixes unlike things. And `thirdNet` assigns the result through the ticket: partial closes of the same ticket sum up correctly, but a trade without an `OPEN` line in the loaded journal drops out of the assignment entirely.

---

## 10. Crash hardening (MetaTrader on Wine/Apple Silicon)

## 11. Important parameters (defaults v0.16)
Risk: `InpRiskPerTradePct=0.25`, `InpRiskTolFactor=1.10`.
Auto scale: `InpAutoScale=true`, `InpIdeaXrisk=2`, `InpHeatXidea=2`, **`InpDayXidea=4`** (v0.20 → day 2.0% = 400 €) (fixed fallback: `InpIdeaCapPct=1`, `InpPortfolioHeatPct=2`, `InpDailyRiskBudgetPct=2`).
Loss: `InpDailyLossPct=2`, `InpMaxLossPct=6`, `InpMaxLossWarnPct=5`, `InpWeeklyLossPct=5`.
Streaks: `InpCooldownAfter=3`, `InpCooldownMin=45`, `InpLockAfter=5`, `InpDeRiskAfter=2`, **`InpDeRiskFactor=1.0`** (R19 OFF, v0.20).
Target: `InpDailyTargetPct=3`, `InpGivebackArmPct=1`, `InpGivebackPct=1`.
Execution: `InpRR=2`, **`InpMinRR=0`** (R8 OFF, v0.20), **`InpMinStopPips=0`** (R15 min SL OFF, v0.22 — M1 scalping needs tight stops), **`InpMaxLot=0`** (R15 lot cap OFF), **`InpMinGapSec=0`** (R14 OFF, v0.20), **`InpRevengeMin=0`** (R25 OFF, v0.20), `InpRequireSL/TP=true`, **`InpSLTPGraceSeconds=4`** (v0.33; anchor = SL/TP removal), `InpSLTPGraceNews=0`.
Correlation/session: `InpUseCorrCap=true`, `InpCorrCapPct=1.5`, `InpUseSession=false`, `InpSessionStart=8`, `InpSessionEnd=22`, `InpNewsFrom/To=0`.
Technical: `InpMagic=990201`, `InpSlippage=30`, `InpTimerSeconds=1`, `InpMinActionMs=500`, `InpPanelMs=1500`, `InpUseAlert=false`, `InpJournal=true`, `InpScreenshots=false`, `InpFomoGate=false`.
v0.21 (SL handling): `InpSlClicksToMove=3` (clicks into the same zone to set the SL; 1=immediately), `InpSlZonePips=10` (lower bound of the zone tolerance).
Close queue (v0.16): `InpCloseThrottleMs=300`, `InpCloseRetries=5` (max attempts per ticket before FINAL-FAIL), `InpCloseBackoffMs=400` (base backoff, doubled per attempt), `InpCloseMaxBackoffMs=4000`.
v0.17: `InpPropFirm=PF_FTMO` (profile label), `InpFundedMode=false` (forces TOOL_ONLY + disables TestMode), `InpSLTPGraceNews=0` (R7 grace during a news blackout), `InpTestMode=false` (rule test harness, demo only), `InpSLTPGraceSeconds` default 10→**5** *(superseded in v0.33: →**4 s**, anchor = SL/TP removal instead of `OrderOpenTime`)*.
v0.35 (R22 panel trades only): **`InpCloseManualTrades=true`** (default **on**) — every order with `OrderMagicNumber()==0` is closed or deleted, **account-wide across all symbols**, independent of `InpWatchScope` and independent of active locks. `false` = R22 off; the rule then appears in the cockpit JSON in the `disabled` list (dashboard chip "— aus" (off)). The detection rate and delay follow from `InpTimerSeconds`/`InpMinActionMs` + `InpCloseThrottleMs` + possibly the modify-quiet window (see section 12).
v0.19 (prop firm time profile): `InpDayResetHour=0` (day reset hour in server time, 0=midnight=FTMO; shifts `ServerDayKey`/`NextServerMidnight`/the R3 day key), `InpWeekStartDay=0` (week start 0=Sunday..6=Saturday, R18). Default 0/0 = previous behaviour. **`InpInitialBalance` default is now 0 = auto** (real account base; set it explicitly on non-20k accounts).

## 11. Important parameters (defaults v0.16) — addenda v0.46–v0.53

v0.46 (handling/presentation): `InpBreakEvenBtn=true` (the "RISK FREE" button — pulls the SL of all positions **in profit** to `OrderOpenPrice()`; checks `MODE_STOPLEVEL`, never loosens an SL, works during a lock/cooldown too, does not touch foreign magics), `InpBreakEvenBufferPts=0` (additional buffer in points; 0 = exactly the entry — the spread is already in there because MT4 opens a BUY at the ask and closes it at the bid; the buffer covers the commission), `InpTpLine=false` (draggable TP line; when set it takes precedence over `InpRR`, but only on the correct side of the entry), `InpShowSpread=true`, `InpShowCandleTime=true`, `InpFontScale=1.0`, `InpShapeScale=1.0`, `InpPanelAutoFit=true` (all three: section 8a).
v0.47 (analysis): **`InpScreenshots` default is now `true`**, `InpShotWidth=1100`, `InpShotHeight=620`, `InpShotKeepDays=14` (0 = never clean up; deletion cap 200 per run) — section 9b.
v0.49–v0.52 (weekly risk + candle): **`InpRequireWeeklyRisk=true`** (without a defined weekly risk **no trading happens**: panel status "RISIKO FESTLEGEN" (define risk), BUY/SELL greyed out; the confirmation expires every week — **v0.62**: `RG_WEEK_RISK_IDX` is now only set by `SetWeekRisk()`, the week roll no longer touches it; the **value** still carries over so that R1 does not force-close weekend positions, and a **pre-selection** only becomes active by pressing SET), `InpRiskChooser=true` (since v0.49 an input field `OBJ_EDIT` + a "SETZEN" (set) button instead of `[-]`/`[+]`; a decimal comma is accepted), `InpRiskStep=0.05`, `InpRiskMaxPct=1.00` (the hard cap stays 1.0%), `InpCandleTimeOnChart=true` (countdown next to the running candle, section 9c).
v0.53 (language): `InpLang=LANG_DE` (`enum PanelLang { LANG_DE, LANG_EN }`) — affects **only** the on-chart panel and the EA messages; the dashboard switches independently of it, and the journal stays German in every case (section 8b).

---

## 12. Known limits / open points
1. **Detect-and-close, not prevent:** ~0.5 s reaction time (polling); a short window for violations, capped by R4/R4b. (Broken down more precisely for R22 in point 10 — there it can also be several seconds.)
2. **No-override locally = friction:** can be switched off as an admin (remove the EA, delete the GVs). Real immutability only via a VPS without your own admin rights + the FTMO server limit.
3. **Mac/Wine unstable** for continuous operation → VPS.
4. **R16 news** only covers time windows/a manual blackout — automatic news detection needs a calendar feed (planned via server/cockpit).
5. ~~R25 revenge in-memory~~ → **persistent since v0.17** (GlobalVariables `RG_REVD_`/`RG_REVU_`, survives a restart). *(done)*
6. **Two bases (do not confuse them):** the daily loss (R4) is computed against the **day-start equity** (`MathMax(Balance,Equity)`, captured when the EA is attached/at midnight — the EA must run from the session start onwards); the total loss (R4b) against the **starting capital** (`InpInitialBalance`, default **0 = auto = the real account base** since v0.18-B1, persisted in `RG_INIT_BAL`). On non-20k accounts set `InpInitialBalance` = the real challenge starting balance.
7. **MT5 mirror** (`MamalTrading.mq5`) not built yet.
8. **v0.17 compiles (F7 = 0 errors)** — the entire batch (R25 persistence, audit journal, R17 vector, R7 hardening, TickValue fallback, funded gate, profile, TestMode) is compile-clean. **Still untested:** the rule test harness/rule matrix and the demo forward test are outstanding.
9. **Compliance (honestly, not "purely passive"):** the EA generates **no entry signals** (a human clicks), but it does **place** orders via one-click `OrderSend` and **closes/blocks autonomously** (risk management automation; **no** `OrderModify` — SL/TP only when sending) = "discretionary entry + automated risk management". Before going real/funded, check **prop firm rule compliance** (per firm; FTMO = default profile) — details + sources in `COMPLIANCE.md`. **Additionally since v0.35:** with R22 the EA also closes positions in FundedMode that it did **not open itself**, and is thereby the only enforcement function deviating from the `InScope()` safety design. Verify this per firm; the existing warning notice for `ALL_POSITIONS` does **not** cover this case, because R22 acts independently of the scope.
10. **R22 is detect-and-revert, not prevention (honest limit):** the manual trade **is opened** and then closed at the **market price** — spread and slippage are borne by the trader. All that can be derived from the code is the **detection latency**: timer 1 s or tick ≥500 ms, plus the close throttle 300 ms, plus possibly up to 2 s of modify-quiet (hard-capped at a 10 s series — so anyone constantly dragging SL/TP delays R22), plus retry/backoff on errors. Realistically: **fractions of a second up to several seconds**; with the market closed (err 132) up to 15 min per attempt. If the EA is not running, AutoTrading is off, or `EventSetTimer` fails, R22 does not act at all — like the entire enforcement. After `InpCloseRetries` failed attempts the ticket drops out of the queue with FINAL-FAIL and **stays open**; it is, however, queued again on the next `EnforceManualTrades()` run (only entries currently in the queue are deduplicated).

---

## 13. Installation & build
1. Copy `MamalTrading.mq4` into `…/MQL4/Experts/`.
2. MetaEditor (F4) → open the file → **F7 compile** (0 errors).
3. MT4: drag the EA onto a chart → "Allow live trading" → AutoTrading on.
4. In the "Experts" tab this appears: `Mamal-Trading v0.35 aktiv (<Symbol>). Scope=… Profil=… Funded=… Test=… SL-Klicks=… R15-min-SL=… Cockpit=…(Port …). UNGETESTET bis F7=0 Errors.` (the version string comes from `EA_VER`).

---

## 14. Version history (short)
- v0.1 EA foundation: R4 daily loss, R4b max loss, R7 SL/TP, persistence.
- v0.2 crash hardening (throttle, context guard, alerts off), tamper warning, panel.
- v0.3 R1 risk/trade.
- v0.5 rebrand to "Mamal-Trading", pro panel with bars.
- v0.6 risk-based one-click entry (SL line + BUY/SELL).
- v0.7 panel redraw strongly reduced (drag crash).
- v0.8 trades from OnTick only.
- v0.9 full set: R2/R3/R5/R6/R8/R9/R11.
- v0.10 SL-removal hole closed (tool trade closed immediately).
- v0.11 R12 total risk, R13 daily target+giveback, R15 min SL/max lot.
- v0.12 R14 minimum pause, R16 session/news, R17 correlation, R18 weekly limit, R19 de-risk.
- v0.13 R14 → 10 s, R25 revenge window.
- v0.14 risk default 0.25%, dynamic auto-scale caps.
- v0.15 P0/P1 patches from REVIEW-v0.14.md → **F7 = 0 errors** (compile checkpoint).
- v0.16 (in progress) close queue + lockstate file + protection-off logging (see below).

## v0.15 — changes vs. the above (corrects earlier statements)
- **Enforcement is no longer "OnTick only".** `Cycle()` runs from OnTick *and* OnTimer (1 s) → protection takes effect tick-independently (P0-1). Close operations are throttled via `InpCloseThrottleMs` (300 ms) + guarded by `IsTradeContextBusy`. (The full close queue with retry limit/backoff was built in **v0.16** — see below.)
- **Losing streak (R5/R6/R19/R25) is history-based.** Instead of the volatile `g_known` there is now `ResolveHistory()` over `MODE_HISTORY`, idempotent via the watermark `RG_LAST_CLOSE` (sorted by CloseTime), with partial-close protection via `HasOpenRemainder`. Survives a restart (P0-2/P0-4).
- **EA protective closes excluded persistently.** `RGEAC_<ticket>` GlobalVariables (instead of in-memory) → the EA's own closes do not count as a loss even after a crash/restart (P0-3).
- **Daily base** = `MathMax(Balance,Equity)` (P0-5); a first start in the middle of the day = `max(InitialBalance,Balance,Equity)` + `BaseWarn` (blocks new trades) or a manual `InpDayStartBase` (adopted retroactively) (P1-2).
- **WatchScope (`InpWatchScope`)**: `TOOL_ONLY` (default, foreign magics untouched) / `TOOL_PLUS_MANUAL` (+magic 0) / `ALL_POSITIONS` (touches EVERYTHING — demo/debug only, **not real/funded**; hard `TOOL_ONLY` at every prop firm) (P1-11).
- **Implemented (untested):** R4b max loss 6% + warn gate 5% (C), immediate flush on all lock states. **v0.15 → F7 = 0 errors confirmed (compile checkpoint).**

## v0.16 — close queue + lockstate + protection-off logging (built, UNTESTED)
- **P0-3 immediate flush:** `MarkEaClosed()`/`UnmarkEaClosed()` now flush immediately (`GlobalVariablesFlush()`) → a crash directly after an EA protective close can no longer lose the `RGEAC_` marker (otherwise the protective close would later wrongly count as a trader loss).
- **Real close queue:** the enforce functions (R7/R1/R8/R12) and `SafeCloseAll` **no longer close directly** but queue tickets via `RequestClose(ticket,lots,reason)` (deduplicated per ticket). `ProcessCloseQueue()` works the queue off: per attempt `RefreshRates()`, `MarkEaClosed`+flush **before** the `OrderClose`, on error `UnmarkEaClosed`+flush (no false EA-close label on a broker SL), error code classification (`IsRetryableClose`: transient → exponential backoff `InpCloseBackoffMs`×2^n up to `InpCloseMaxBackoffMs`; hard → max backoff + faster towards the limit), retry limit `InpCloseRetries`. **Journal per attempt:** `Queue OK` / `Queue RETRY n err=…` / `Queue FINAL-FAIL …` / `Queue DELETE …` (pendings). After a FINAL-FAIL the ticket drops out and may be detected again in the next cycle (paced) — the watchdog never gives up permanently.
- **Lockstate file (fail-closed):** `MamalTrading_Lockstate.dat` mirrors the lock states with an HMAC-light checksum. `ReconcileLockstate()` adopts the **most restrictive** state from GV + file at startup; **corrupted/tampered → fail closed** (daily lock + `TAMPER` journal entry). `WriteLockstate()` keeps the file current at the end of the cycle (writes to disk only on change). Note: purely local = friction; real immutability only on a locked-down VPS + the FTMO server limit.
- **Protection-off logging:** AutoTrading off/on is written to the journal as `PROTECT_OFF`/`PROTECT_ON`; `OnDeinit` (EA removed/chart closed) also logs `PROTECT_OFF` with a `reason`.

### R3 reconciliation (v0.16, retrofitted)
`RG_DAY_RISK` no longer lives purely additively after `OrderSend`. `ReconstructedDayRiskPct()` reconstructs the tool risk **opened today** from broker data: open + today-closed positions with `OrderMagicNumber()==InpMagic`, filtered on `DayKeyOf(OrderOpenTime())==today` (opened yesterday does NOT count), grouped by `ProcKey` (partial closes sum up to the entry lot size, **each position once**); missing SL/tick data → the conservative floor `InpRiskPerTradePct` + an `INFO` journal entry. `ReconcileDayRisk()` sets `RG_DAY_RISK = max(persisted, reconstructed)` (RAISE only, **no refund**) + flush + `INFO` journal entry. Call sites: in `OnInit` (crash/restart recovery), in `Cycle()` throttled (15 s) and in `DoEntry` directly before the R3 gate.

**One uniform % base (v0.16 correction):** both the additive path and the reconstruction compute R3 over `DayRiskBase()` (= the stable daily base `RG_DAYSTART_EQ`, fallback initial balance/equity) via `RiskPctOfBase(sym,lots,open,sl,base)`. In `DoEntry` a separate `r3rp` is computed for this and used for the R3 gate **and** for `RG_DAY_RISK +=` — the normal `rp` (live equity from `CalcLot`) stays for the display, R1/R2/R12/R17 and the OPEN journal entry. This keeps the additive and the reconstructed daily consumption from drifting apart. Honest limit: the reconstruction uses the current/last SL (not the entry SL) → a best-effort backstop; the persisted additive value remains authoritative as soon as it exists.

**v0.16 addenda:** `ERR_MARKET_CLOSED` (132) added as a transient error in `IsRetryableClose`; the unused `g_qLots` removed from the close queue (lots are read live from `OrderLots()` at close time → partial-close-proof).
- **Done (built, untested):** R3 reconciliation (single base), `TimeCurrent`→the tick-independent server time `SrvTime()` (PC clock+offset; MQL4 has no `TimeTradeServer`), **+ the complete v0.17 batch (see below).** **Still open (procedural/infrastructure, see `docs/PROP-FIRM-READINESS.md`):** **playing the rule test harness matrix green + demo forward test + prop firm rule compliance per firm + Windows VPS**. **F7 = 0 up to SrvTime; F7 for v0.17 is outstanding.**

## v0.17 — full code build-out towards prop-firm-ready (built, UNTESTED, F7 outstanding)
- **#6 R25 persistent:** revenge window in GlobalVariables (`RG_REVD_`/`RG_REVU_`), `PruneRevenge` cleans up, survives a restart (in-memory arrays removed).
- **#7 audit journal:** `Journal()` fills the context automatically (ServerTime, DayKey, Account, Balance, Equity, Magic, RuleId-from-tag) + optionally Ticket/Net; header on the first write; call sites unchanged.
- **#8 R17 currency vector:** `SplitCcy`/`AddExposure`/`MaxCurrencyExposurePct` instead of USD-only; per position a base (long)/quote (short) load, largest |net currency exposure| ≤ `InpCorrCapPct`; cross pairs count together, non-FX gets its own bucket.
- **#9 R7 hardening:** the `EnforceSLTP` deadline runs from `OrderOpenTime()` (restart-proof, naked list removed); news blackout → `InpSLTPGraceNews` (default 0); tool naked = immediate; default grace 10→5 s. **⚠ superseded in v0.33** — the anchor is now the **SL/TP removal** (naked clock per ticket, persistent + healing period), grace **4 s**, tool trades without a special case. Current state: section 7 (rule-to-code) and 11 (parameters).
- **#10 TickValue robustness:** `TickVal()` with the fallback `TickSize×LotSize` if `MODE_TICKVALUE`=0, + a warning once per day → risk never wrongly appears as 0; used in `RiskPctOf`/`RiskPctOfBase`/`CalcLot`.
- **#11 funded hard gate:** `InpFundedMode=true` forces `InpWatchScope=TOOL_ONLY` and disables `InpTestMode` (runtime override of the `extern` variables in `ApplyFundedAndProfile`).
- **#13 prop firm profile:** `enum PropFirm` + `InpPropFirm` + `PropFirmName` → label/log/`PROFILE` journal entry. The limit numbers remain inputs (non-FTMO presets deliberately NOT guessed — verify per firm).
- **#14 TestMode harness:** `InpTestMode` (demo only, hard off in FundedMode) shows panel buttons (`TestAction`): cooldown/day lock/max lock/revenge/corrupt lock(+reconcile→fail closed)/reset — manipulates **state/file only, opens no trades**.
- **Adversarially verified** (workflow, 6 lenses including a strict MQL4-vs-MQL5 function audit) — 0 confirmed findings. **F7 = 0 errors confirmed.** Open: rule test matrix + demo forward test + firm-specific verification.

## v0.35 — R22 "panel trades only" (built, UNTESTED, F7 outstanding)
- **New rule R22** (`InpCloseManualTrades`, default `true`): `EnforceManualTrades()` queues every order with `OrderMagicNumber()==0` into the close queue — positions are closed, pendings deleted. Foreign EAs (magic ≠ 0) remain untouched. The rule number R22 was free; R20/R21/R26/R27 remain open, R23/R24 exist nowhere. Details: section 7 (rule-to-code + R22 specifics), section 11 (parameters), section 12 points 9/10 (compliance + honest limits).
- **Why:** only the panel path (`DoEntry`) goes through the gate chain (AutoTrading, lock, base, R4b warn gate, R13, R5, R16, R25, R14, R7 SL line/side, R15 + the broker `STOPLEVEL`, R1 sizing, R2, R3, R12, R17). A trade opened manually in the terminal bypasses all of it.
- **Position in the cycle:** one call in the enforcement block, **before** the lock branch (so it also applies while a lock is active) and deliberately **without** `InScope()` (so it also applies in FundedMode). This makes `WatchScope=TOOL_PLUS_MANUAL` ineffective while R22 is active — the EA points out exactly this combination at startup.
- **Documentation note (not part of this document):** the EA's file header comment still says "v0.21 … rules R1-R19 + R25" and is therefore out of date; `EA_VER` stands at `0.35`. (`RULES.md` now lists R22 — the contract was retrofitted with v0.35; the order required by the contract, "RULES.md first, then code", was violated here, however: cockpit and EA carried R22 before the entry existed.)
