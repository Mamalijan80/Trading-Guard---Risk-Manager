# Mamal-Trading — The Rules in Plain Language

*For everyone, no technical knowledge required. Think of the tool as a strict, calm coach sitting next to you: it never tells you **what** to trade — that is your decision. But it makes sure you do not ruin yourself.*

**Example account used throughout this text: 20,000 €. Risk per trade: 50 € (that is 0.25 %).** All numbers are the current settings and can be adjusted.

**Important note on the euro amounts:** Every € figure in this text applies to a **20,000 € account**. The tool is also intended for **10,000 €** and **25,000 €** — in which case all amounts change accordingly (half at 10k, a quarter more at 25k). What **always** holds is the **percentage**: the tool never calculates with a fixed euro sum, always in percent of your actual account.

---

## The Most Important Thing in One Sentence
You drag a **red line** to where your stop should be and click **Buy** or **Sell**. The tool calculates the correct size, opens the trade with protection in place — and intervenes when you violate one of your protective rules.
*You set the red line either by **dragging it directly**, or by **clicking 3× into the same zone** (protection against accidentally moving it on the first click). The panel shows "noch 2× / 1× klicken" (2× / 1× more clicks to go).*

---

## Quick Overview (all rules in one table)

| Rule | What it does for you | Short example |
|---|---|---|
| **Automatic trade size** | Calculates the lot size so that you never risk more than 50 € per trade | Stop near = smaller size, stop far = larger size — always 50 € |
| **One idea = one limit** | The same thing repeatedly in the same direction = max. 100 € combined | 2× gold buy = full, the 3rd is blocked |
| **Daily budget** | Open at most **400 €** of risk per day (approx. 8 trades) | After 8 trades the day is over |
| **Daily loss brake** | −400 € on the day → everything closed, locked until tomorrow | 20,000 → 19,600 → emergency brake |
| **Total loss shield** | −1,000 € → early warning, −1,200 € → permanently locked | protects your entire account |
| **Break after 3 losses** | 3 losses in a row → 45 min break | catch your breath instead of trading on in frustration |
| **Stop after 5 losses** | 5 losses in a row → done for today | bad days get capped |
| **Protection mandatory** | Every trade needs a stop **and** a target | without a stop → closed after 4 sec. |
| ~~Is the trade worth it?~~ | *(**OFF** at your request)* | — |
| **Double confirmation** | *(off at your request)* | one click opens immediately |
| **No cheating** | No built-in unlock button, locks survive a restart | strong friction against impulses (truly un-bypassable only on a locked-down VPS) |
| **Journal** | Everything is written down (with a reason) | traceable later |
| **Total risk cap** | All open trades together max. 200 € | 4 trades open = full |
| **Secure the daily target** | +600 € → no new trades; do not give the profit back | a green day stays green |
| ~~Short break~~ | *(**OFF** at your request)* | — |
| **Minimum stop distance** | ~~min. 5 pips~~ **OFF** (since v0.22) — only your broker's minimum distance still applies | the "mini stop" trick is now limited only by the broker |
| **Trading hours / news** | *(optional)* trade only within a time window | e.g. not at night |
| **Not too much in one currency** | Adds up one currency across several pairs | 2× "dollar short" = a lot, the 3rd is blocked |
| **Weekly limit** | −1,000 € over the week → week locked | caps bad weeks |
| ~~Reduce risk after losses~~ | *(**OFF** at your request)* | — |
| ~~No revenge trade~~ | *(**OFF** at your request)* | — |
| **Panel trades only** | Trades that do not go through the panel are closed again by the tool | buy from the phone app → usually closed again after about a second |

---

## Every Rule in Detail, with an Example

### 1) Automatic trade size — "You never have to do the math yourself"
**What:** You drag the red line to where your stop loss should be (or **click 3× into the same zone**). The tool immediately calculates how large your trade may be so that you lose **at most 50 €**.
**Example:** You want to buy gold.
- Red line 20 pips below the price → the tool opens **0.25 lots**.
- Red line only 10 pips away → the tool opens **0.50 lots**.
- In **both** cases you risk exactly **50 €**.
**Extra protection:** If you move the stop further away after entry (more risk), the tool closes the trade as soon as the risk climbs above 50 €. Moving the stop **closer** is always allowed.

### 2) One idea = one limit — "Do not run yourself into one direction"
**What:** Several buys in the same market in the same direction count as **one idea**. Together at most **100 €** of risk.
**Example:** Gold buy (50 €), another gold buy (50 €) → 100 € together = full. A **third** gold buy is blocked. A gold **sell** or another market still works.

### 3) Daily budget — "Do not blast away all day"
**What:** Over the day the tool adds up how much risk you have **opened** — winners count too (nothing is given back). At **400 €** (approx. 8 trades) the day is over.
**Example:** You open 8 trades of 50 € each → the **9th is blocked** ("Tagesbudget erreicht" — daily budget reached), even if all 8 are in profit. Tomorrow the budget starts again at zero. *(The budget is deliberately set exactly as high as the 400 € daily loss brake, so that the brake is actually reachable and the daily target stays achievable.)*

### 4) Daily loss brake — "The emergency stop for the day"
**What:** If your account slips **−400 €** into the red on a single day (measured against the start of the day), the tool closes **everything** and locks until midnight.
**Example:** Start 20,000 €, over the course of the day down to 19,600 € → all trades **opened by the tool** are closed, no new ones until tomorrow. That way you do not break the prop firm's limit. **Important:** In live/funded mode the tool does **not** close trades belonging to **another trading program** — instead it **warns** loudly that you have to close them yourself. Trades you open **by hand** (outside the panel) are no longer an issue here: rule 22 clears those away continuously anyway.

### 5) Total loss shield — "Protection for the whole account" (two stages)
**What:**
- **−1,000 € (5 %): early warning** → no new trades (you may still manage open ones).
- **−1,200 € (6 %): permanently locked.**
**Example:** The account falls from 20,000 to 19,000 € → "Max-Loss-Warnung" (max-loss warning). If it falls further to 18,800 € → completely and permanently shut. That is your safety margin to the firm's 10 % limit.

### 6) Break after 3 losses — "Catch your breath"
**What:** 3 losing trades in a row → **45 minutes** of pause for new trades.
**Example:** Stop, stop, stop → "Cooldown 45 Min" (45-minute cooldown). Instead of carrying on in frustration, you take a break first.

### 7) Stop after 5 losses — "Cap the bad days"
**What:** 5 losses in a row → locked for today.
**Example:** After the 5th stop in a row: "gesperrt bis morgen" (locked until tomorrow).

### 8) Protection mandatory — "Never without a stop and a target"
**What:** Every trade needs a **stop loss** (protection) **and** a **take profit** (target). Trades from the tool have both automatically. If one is missing, you have **4 seconds** to add it — for tool trades just as for all other monitored trades (the earlier instant ejection for tool trades is gone). The clock starts the moment the protection **is missing or is removed** (not when the trade is opened): if you remove the stop after two hours, the trade is closed 4 seconds later. The clock remembers this per trade: restarting MetaTrader or switching the timeframe does **not** reset it, and briefly touching the stop back in does not either — only once stop and target have been set again **for a full minute** is the deadline really off the table.
**Example:** A monitored trade without a stop → after **4 seconds** the tool closes it. During important news it even happens **immediately**. *(Whatever you open by hand, bypassing the panel, is usually gone even earlier — rule 22 takes care of that.)*
**Important (no crash):** If you **change or remove** the stop or the target on a trade, only the **trade** is closed — **MetaTrader itself stays open** and keeps running. You may drag the stop **closer** to the price at any time; dragging it **further away** is recognized by the tool as "too much risk" and the trade is closed.

### 9) ~~Is the trade worth it?~~ — **OFF at your request**
This rule (minimum target-to-risk ratio) is **switched off**. The tool no longer checks the reward-to-risk ratio. *(The automatic target of your tool trades is still 2× the risk — as a suggestion only, not as a constraint.)*

### 10) Double confirmation — *off*
You have **switched off** this additional safety prompt. One click opens immediately.

### 11) No cheating — "No-Override"
**What:** There is **no** button to lift a lock early. Locks even survive a restart of the program. If you switch off auto trading, the tool warns clearly ("SCHUTZ AUS" — protection off).
**Example:** You are locked and restart MetaTrader — the **lock stays**.

### 12) Journal — "Everything is written down"
**What:** Every trade, every block, every close ends up in a file together with a **reason**.
**Example:** Later you see: "13:42 — Trade blockiert: Tagesbudget" (trade blocked: daily budget). Good for review and as evidence towards the prop firm.

### 13) Total risk cap — "All trades together"
**What:** No matter how many trades are open — **together** never more than **200 €** of risk (4 trades of 50 € each).
**Example:** 4 trades open = 200 € = full, the 5th is blocked. If the total risk becomes too high anyway, the tool closes the **newest** trade.

### 14) Secure the daily target — "A green day stays green"
**What:** Once you reach **+600 €** (3 %), the tool takes **no new** trades. And if you give back too much from a daily high, it locks the day.
**Example:** You are +600 € → "Ziel erreicht" (target reached; open trades keep running, but nothing new). Or: you were +400 € and fall back to +200 € → the day is locked, so that green does not turn into red.

### 15) ~~Short break~~ — **OFF at your request**
There is **no** enforced pause between two trades anymore. You can click again immediately.

### 16) ~~Minimum stop distance~~ — **OFF at your request** (v0.22)
**What:** The 5-pip minimum distance is **switched off** — M1 scalping needs tight stops. The optional lot cap is off as well.
**What still protects you:** your **broker's hard minimum distance** and rule 1 — with a tiny stop a large lot is indeed calculated, but always only as large as keeps your risk at 50 €. **Honest limitation:** the extreme case "mini stop → slippage/gap tears away more than 50 €" is no longer covered by this.

### 17) Trading hours / news — *optional*
**What:** If you want: trading only within a time window plus a manual news lock. **Default: off.**
**Example (when on):** outside 8:00–22:00 everything is blocked.

### 18) Not too much in one currency — "Across different pairs too"
**What:** The tool adds up how strongly you are betting on **one currency** — even when different pairs are involved.
**Example:** You buy EUR/USD **and** GBP/USD — both are bets on a **weak dollar**. Together that is a lot of "dollar short" → a third such trade is blocked. Opposing trades cancel each other out (e.g. a EUR/USD buy plus a USD/JPY buy).
**Why:** So that **one** currency move does not hit all of your trades at the same time.

### 19) Weekly limit — "Cap a bad week"
**What:** If you lose **−1,000 €** (5 %) over the week, the week is locked.
**Example:** Mon–Wed together −1,000 € → no new trades until the week rolls over.

### 20) ~~Reduce risk after losses~~ — **OFF at your request**
Your risk per trade stays **constant** (50 €). It is no longer halved automatically after losses.

### 21) ~~No revenge trade~~ — **OFF at your request**
There is **no** block on counter-trades after a loss anymore. Discipline is handled by the hard limits (daily / total / weekly brake, cooldown after 3, stop after 5).

### 22) Panel trades only — "Going around the coach is not possible"
**Why this rule exists:** All the other rules hang off the panel. When you click Buy or Sell there, your trade runs through the complete control chain: correct size (1), idea limit (2), daily budget (3), daily target (14), cooldown after 3 losses (6), trading hours (17), total risk (13), currency concentration (18) and everything else. If you open the trade **beside it** — directly in the chart, in the market window, from the phone app while you are out —, then **none** of that runs. No size calculation, no counting, no limit. A single such trade defeats, at that moment, everything the other rules are there for. That is exactly why this rule exists: what does not come through the panel does not stay open. **Default: on.**

**What happens concretely:** You are sitting on the train, open the phone app and buy gold. The tool sees this trade and closes it again — usually **after about one second**. The same goes for pending orders you enter by hand: they are deleted. It applies to **all** markets on your account, not just the chart the tool is running on. And there is **no grandfathering**: if trades opened by hand are already open when the tool starts, those are closed too — the tool tells you at startup how many it found.

**Trades from other programs are left untouched:** If another trading program is running alongside the tool on the same account, the tool leaves its trades **alone**. It recognizes them by their own identifier. Only what carries **no** identifier is closed — and that is exactly what a human clicks by hand.

**What this rule CANNOT do — honestly:**
- It does **not prevent** the trade, it **undoes** it. For a few moments the trade was genuinely in the market. You pay the **spread** for it, and on closing whatever price happens to be there — so in fast moves possibly a somewhat worse one. There is no "free undo".
- **About one second** is the normal case, not a guarantee. Depending on what else is going on, it can also take fractions of a second or several seconds. If you are constantly dragging stops around at the same time, that delays detection by a few more seconds. If the market is closed, the tool cannot close anything — it then tries again later.
- It only works while **MetaTrader is running and auto trading is on**. If auto trading is off, this rule is off too — like the entire protection. Hence the orange warning "SCHUTZ AUS" (protection off).
- If closing fails several times in a row, the tool gives up on that trade for the moment and logs it — on the next pass it tries again. So in rare cases a trade can stay open longer than you would like.
- The **loss** from such a trade counts perfectly normally towards the big account brakes (daily loss, total loss, weekly limit) — your account notices it, after all. But it does **not** count as a "losing trade" for the break after 3 and the stop after 5, and it consumes **no** daily budget either. The tool does not treat it as your trade, because it never ran through the control chain.
- In the cockpit, rule 22 shows up under "Deine Schwächen" (your weaknesses). There a **single** hand-opened trade can be counted **multiple times** (each close attempt creates an entry). Take the number as an indication that you traded past the panel — not as an exact count.

---

## What You See at the Top Left of the Chart (the display)
There are no more than these **9 displays**. A plain "GESPERRT" (locked) is **never** shown — the tool always tells you *which* lock is in force. If several are active at the same time, you see the **strictest** one (the list is sorted from strict to lenient):

| Display | Meaning |
|---|---|
| **SCHUTZ AUS** (orange) | Auto trading is off — the tool **cannot** protect you right now! |
| **MAX-LOSS GESPERRT** (red) | Account shield — permanent |
| **WOCHE GESPERRT** (red) | Weekly loss limit reached |
| **TAG GESPERRT** (red) | Done for today (daily loss, 5 losses in a row, or profit given back) |
| **MAX-LOSS WARNUNG** (orange) | Early warning — no new trades |
| **COOLDOWN** (orange) | Break after 3 losses |
| **ZIEL ERREICHT** (green) | Daily target reached — no new trades |
| **AUSSER SESSION** | Outside the permitted time / news lock |
| **AKTIV** (green) | All clear — you may trade |

*(Display labels above are shown in German because that is the literal text in the code: "SCHUTZ AUS" = protection off, "MAX-LOSS GESPERRT" = max loss locked, "WOCHE GESPERRT" = week locked, "TAG GESPERRT" = day locked, "MAX-LOSS WARNUNG" = max loss warning, "ZIEL ERREICHT" = target reached, "AUSSER SESSION" = outside session, "AKTIV" = active.)*

*In the cockpit in the browser the same text appears at the top — panel and cockpit cannot contradict each other, both read the same state.*

*Rule 22 ("Panel trades only") has **no display of its own** in the panel — it works silently in the background. You notice that it has struck because the trade is gone again; you can read up on it in the journal and in the cockpit.*

---

## Two Switches You Should Know About
- **"Live/funded account" switch:** When you move towards a real or funded account, you switch this on. The tool then only touches **trades from the panel**, and practice mode is locked out. **One exception you must know about:** rule 22 applies here too — trades you open **by hand** are closed by the tool in live/funded mode as well. Trades from other programs are left untouched.
- **"Practice mode":** Demo only. Shows test buttons with which you can trigger the locks deliberately, to see that everything works. On a real/funded account it is **automatically off**.

---

## Being Completely Honest: What the Tool CANNOT Do
- It reacts **very fast, but not in zero seconds** (about half a second). The worst possible damage is capped by the daily and total brakes.
- It cannot **prevent** a trade you open **past the panel** — only **undo** it (rule 22). For the second in between you were genuinely in the market: spread paid, the price may have moved. The rule protects your rulebook, not your cent.
- The **truly hard** limit is your prop firm's limit (server-side). The tool makes sure you never get there in the first place — but it does not replace it.
- On the **Mac** (via a compatibility layer) MetaTrader can be unstable. For genuine continuous operation it belongs on a **Windows machine/VPS** that runs around the clock.
- It is **not a money printing machine**. It does not find trades for you — it is your **discipline coach**.

---

## Good to Know: "Scaling Along"
If you change your **risk per trade** (e.g. from 50 € to 100 €), the other limits (idea, total risk, daily budget) adjust **automatically** along with it. The number of permitted trades stays the same. So you only have to turn **one** dial.

---

*Detailed technical version: `RULES-DETAILED.md` · Cheat sheet: `RULES-CHEATSHEET.md` · Compliance: `COMPLIANCE.md`.*
