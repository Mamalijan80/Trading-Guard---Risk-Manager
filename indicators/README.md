# Level indicators

Three standalone MetaTrader 4 indicators. They draw price levels and nothing else — no
orders, no signals, no DLL imports, no network access, no file access. They are
independent of the TradingGuard EA and can be used on their own.

Each one lives in its own object namespace (`TGRL_`, `TGPD_`, `TGWM_`), so they never
collide with each other or with the EA panel (`MMT_`), and each removes exactly its own
objects when you take it off the chart.

| Indicator | Draws |
|---|---|
| [`TG_RoundLevels.mq4`](mt4/TG_RoundLevels.mq4) | Horizontal lines on round price numbers, each labelled with its value |
| [`TG_PrevDayLevels.mq4`](mt4/TG_PrevDayLevels.mq4) | Previous day's high, low, mid, open and close — bounded to each day |
| [`TG_WeeklyMap.mq4`](mt4/TG_WeeklyMap.mq4) | 13 levels derived from the previous week's range, plus the weekend gap |

## Install

Copy the `.mq4` file into `<MT4 data folder>/MQL4/Indicators/`, press **F7** in MetaEditor
to compile, then refresh the Navigator and drag the indicator onto a chart. Settings are
in the **Inputs** tab (`Ctrl` + `I` on the chart, then pick the indicator).

---

## TG_RoundLevels

Round numbers are where orders cluster. The indicator draws them so you stop eyeballing
where "4250" actually is.

**Automatic spacing** (default) picks a step of roughly `InpAutoPercent` % of the current
price and rounds it to a readable number — 1, 2, 2.5 or 5 times a power of ten. Gold at
4000 gets 20-dollar steps, EURUSD at 1.1000 gets 50 pips, the Dow at 46000 gets 250 points.

The step is **sticky**: it is only recalculated once the price has moved more than
`InpRecalcPercent` (default 20 %) from where it was last computed. Without that, the grid
would jump around during normal trading and while zooming.

Levels are counted **from zero**, so every line is an exact multiple of the step. The number
on the line is genuinely round and does not depend on where the price happens to be.

Only the visible price range is drawn, and the lines are rebuilt when you scroll or zoom —
not on every tick. If more than `InpMaxLines` levels (default 300) fall inside the view, the
ones around the centre of the screen are drawn and a small note appears at the bottom left
explaining why the rest are missing. Widen the spacing if you need the whole range.

**Note on line styles:** MetaTrader only renders dotted and dashed lines at width 1. At
width 2 or more, every style looks solid.

---

## TG_PrevDayLevels

Five lines taken from the previous day's candle and drawn on the current one: **high** and
**low** (solid), the **mid** between them (dotted), the **open** (dash-dot) and the **close**
(dashed). `InpDays` controls how far back the history goes, up to 1000 days, which makes
visual backtesting straightforward.

Every line is bounded to its own day. They are drawn as segments rather than horizontal
lines, so a Friday level does not run across the weekend. Nothing is drawn on the weekly
and monthly charts, where one candle spans several days.

### One deliberate difference from the usual implementation

Some brokers produce a very short daily candle for Sunday — a few hours of thin trading. If
that candle is taken as "yesterday", Monday's levels come from those few hours instead of
from the full Friday session. The levels are then simply wrong, and they look perfectly
normal while being wrong.

`InpSkipStubCandle` (**on** by default) detects such a stub — its range is below
`InpStubMaxPercent` (default 25 %) of the average range of the preceding 20 days — and steps
back to the candle before it. The candidate is excluded from that average so a stub cannot
hide itself, and with too little history to judge, the check abstains rather than guesses.

Turn it off if you want the plain behaviour.

---

## TG_WeeklyMap

Thirteen levels derived from the **previous week's range**, drawn across the current week:

- **High**, **Low** and the **50 %** midpoint — solid
- **25 %** and **75 %** of the range — dotted
- Four extensions above the high and four below the low, at 25 %, 50 %, 75 % and 100 % of
  the range. With a 40-dollar week, the first extension sits 10 dollars above the high.

`InpWeeks` controls how many weeks stay on the chart. Each week keeps its own lines, so the
previous weeks remain readable. Everything is recalculated at the week rollover, not on
every tick.

**Weekend gap:** if the new week opens away from the previous week's close, two lines mark
the gap — green when it opened higher, orange-red when lower. `InpGapMinPoints` sets the
minimum distance that counts as a gap, so normal spread noise is ignored.

**Picking levels:** rather than fourteen separate on/off switches, `InpLevels` takes a list:

```
H,L,50,25,75,+25,+50,+75,+100,-25,-50,-75,-100
```

Leave it empty for all of them. Drop the entries you do not want. Fourteen checkboxes in a
dialog that is already long is not a setting anyone would actually use.

---

## Origin

These are independent implementations, written from published feature descriptions of
comparable commercial indicators. No third-party code was decompiled, copied or adapted.
They are licensed under the AGPL-3.0 like the rest of this repository.

## Maturity

They compile without errors or warnings and the spacing arithmetic is verified against
worked examples. They have **not** been through an extended live test. Check them on a demo
chart before you rely on the levels for anything.
