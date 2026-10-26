# Level indicators

One MetaTrader 4 indicator, [`TG_Levels.mq4`](mt4/TG_Levels.mq4), carrying three groups of
price levels. It draws and nothing else — no orders, no signals, no DLL imports, no network
access, no file access. It is independent of the TradingGuard EA and works on its own.

| Group | Master switch | Draws |
|---|---|---|
| Round Levels | `InpShowRoundLevels` | Horizontal lines on round price numbers, each labelled with its value |
| Previous Day | `InpShowPrevDay` | Previous day's high, low, mid, open and close — bounded to each day |
| Weekly Map | `InpShowWeeklyMap` | 13 levels from the previous week's range, plus the weekend gap |

Each group has its own settings block in the Inputs dialog, prefixed `InpRL_`, `InpPD_` and
`InpWM_`. Switch a group off and its lines disappear immediately — the check runs on every
pass, not only at startup, so you can toggle groups while the chart is live.

Each group also keeps its own object namespace (`TGL_RL_`, `TGL_PD_`, `TGL_WM_`), none of
which overlaps the EA panel's `MMT_`. Taking the indicator off the chart removes all of them
and nothing else.

**Why one file and not three:** an Expert Advisor occupies the single EA slot on a chart —
that is `MamalTrading`. Indicators are unlimited per chart, which is why the levels can run
alongside it. Keeping them out of the EA is deliberate: the EA is the only file that acts on
the account, closing positions and setting locks, and drawing code has no business in the
same file as the emergency brake.

## Install

Copy `TG_Levels.mq4` into `<MT4 data folder>/MQL4/Indicators/`, press **F7** in MetaEditor to
compile, then refresh the Navigator and drag it onto a chart. Settings are in the **Inputs**
tab (`Ctrl` + `I` on the chart, then pick the indicator).

---

## Round Levels

Round numbers are where orders cluster. The indicator draws them so you stop eyeballing
where "4250" actually is.

**Automatic spacing** (default) picks a step of roughly `InpRL_AutoPercent` % of the current
price and rounds it to a readable number — 1, 2, 2.5 or 5 times a power of ten. Gold at
4000 gets 20-dollar steps, EURUSD at 1.1000 gets 50 pips, the Dow at 46000 gets 250 points.

The step is **sticky**: it is only recalculated once the price has moved more than
`InpRL_RecalcPercent` (default 20 %) from where it was last computed. Without that, the grid
would jump around during normal trading and while zooming.

Levels are counted **from zero**, so every line is an exact multiple of the step. The number
on the line is genuinely round and does not depend on where the price happens to be.

Only the visible price range is drawn, and the lines are rebuilt when you scroll or zoom —
not on every tick. If more than `InpRL_MaxLines` levels (default 300) fall inside the view, the
ones around the centre of the screen are drawn and a small note appears at the bottom left
explaining why the rest are missing. Widen the spacing if you need the whole range.

**Note on line styles:** MetaTrader only renders dotted and dashed lines at width 1. At
width 2 or more, every style looks solid.

---

## Previous Day

Five lines taken from the previous day's candle and drawn on the current one: **high** and
**low** (solid), the **mid** between them (dotted), the **open** (dash-dot) and the **close**
(dashed). `InpPD_Days` controls how far back the history goes, up to 1000 days, which makes
visual backtesting straightforward.

Every line is bounded to its own day. They are drawn as segments rather than horizontal
lines, so a Friday level does not run across the weekend. Nothing is drawn on the weekly
and monthly charts, where one candle spans several days.

### One deliberate difference from the usual implementation

Some brokers produce a very short daily candle for Sunday — a few hours of thin trading. If
that candle is taken as "yesterday", Monday's levels come from those few hours instead of
from the full Friday session. The levels are then simply wrong, and they look perfectly
normal while being wrong.

`InpPD_SkipStubCandle` (**on** by default) detects such a stub — its range is below
`InpPD_StubMaxPercent` (default 25 %) of the average range of the preceding 20 days — and steps
back to the candle before it. The candidate is excluded from that average so a stub cannot
hide itself, and with too little history to judge, the check abstains rather than guesses.

Turn it off if you want the plain behaviour.

---

## Weekly Map

Thirteen levels derived from the **previous week's range**, drawn across the current week:

- **High**, **Low** and the **50 %** midpoint — solid
- **25 %** and **75 %** of the range — dotted
- Four extensions above the high and four below the low, at 25 %, 50 %, 75 % and 100 % of
  the range. With a 40-dollar week, the first extension sits 10 dollars above the high.

`InpWM_Weeks` controls how many weeks stay on the chart. Each week keeps its own lines, so the
previous weeks remain readable. Everything is recalculated at the week rollover, not on
every tick.

**Weekend gap:** if the new week opens away from the previous week's close, two lines mark
the gap — green when it opened higher, orange-red when lower. `InpWM_GapMinPoints` sets the
minimum distance that counts as a gap, so normal spread noise is ignored.

**Picking levels:** rather than fourteen separate on/off switches, `InpWM_Levels` takes a list:

```
H,L,50,25,75,+25,+50,+75,+100,-25,-50,-75,-100
```

Leave it empty for all of them. Drop the entries you do not want. Fourteen checkboxes in a
dialog that is already long is not a setting anyone would actually use.

---

## Origin

This is an independent implementation, written from published feature descriptions of
comparable commercial indicators. No third-party code was decompiled, copied or adapted.
It is licensed under the AGPL-3.0 like the rest of this repository.

## Maturity

It compiles without errors or warnings and the spacing arithmetic is verified against
worked examples. It has **not** been through an extended live test. Check it on a demo
chart before you rely on the levels for anything.
