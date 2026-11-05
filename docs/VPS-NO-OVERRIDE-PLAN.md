# VPS / "No-Override" — Plan & honest limits

**As of: 2026-07-08.** Researched (multi-agent workflow) + the central facts verified directly with FTMO. The question was: *"How do we get the account to carry the limits without the user bypassing them by switching AutoTrading off?"*

---

## 0. Core finding (the one that decides everything)

FTMO's **Forbidden Trading Practices** prohibit, **literally**:

> "You must not allow any **third party to access or otherwise use your FTMO Account** or your FTMO Challenge/Verification account."
> "…nor **engage or cooperate with any third party** in order to have such a third party perform simulated trades for you or in coordination with you."
> — Source (verified 2026-07): <https://ftmo.com/en/forbidden-trading-practices/>

**Real "No-Override" mandatorily requires that someone/something OTHER than you controls enforcement** (an accountability partner holds VPS admin + broker password; or an external service accesses the account). **That is exactly what FTMO forbids.**

➡️ **On an FTMO account, real no-override is NOT possible in a rule-compliant way** — not because of our tool, but because FTMO demands that **only you** have access. Whoever has sole access can also always unlock themselves again (AutoTrading off). This is a direct consequence of the FTMO rules, not a bug.

**The only truly unbypassable account floor on FTMO is FTMO's own server-side limit (5 % daily / 10 % total).** Your tighter limits (2 %/6 %) can only be a **self-imposed discipline aid** on FTMO — bypassable by you.

---

## 1. What is ALLOWED on FTMO (verified)

| Topic | Status | Source |
|---|---|---|
| Your own **VPS** | allowed (not forbidden, FTMO is VPS-friendly) | — |
| Your own **EA/automation** (your own strategy) | allowed, **as long as < 2,000 server requests/day** (no "hyperactive" EAs) — our EA is normally far below that | ftmo.com/forbidden-trading-practices |
| **Third-party access** to the account / coordinated trading | **FORBIDDEN** | ftmo.com/forbidden-trading-practices |
| "Unfair advantage" software | forbidden (does not concern us — risk tool, no advantage) | same |

➡️ **Your own VPS running your own risk EA** is allowed and sensible (stability + "always on" fixes the Wine crashes **and** the FTMO midnight-baseline requirement). What does *not* work: having a partner/service control the account.

---

## 2. Where real no-override DOES work

On **your own broker account or a demo account that belongs to you** (not a prop challenge) the third-party access rule does not apply. There you can build the full **"Ulysses contract"**. **Ideal for training the discipline habit** — alongside or ahead of FTMO.

---

## 3. Technical building blocks (researched — they only amount to real no-override on your own/demo account)

- **MT4 headless as a Windows service** (session-0 isolation, GUI visible to no user; e.g. AlwaysUp). An AutoTrading button you cannot see is one you cannot switch off. **Downside:** through that MT4 you can no longer trade manually either → order entry must go through a separate channel (the cockpit). Source: coretechnologies.com (MT4 as a Service).
- **Windows kiosk (Assigned Access)** does NOT work for MT4 (UWP/Edge only) and **not over RDP**; only "Shell Launcher" (Windows Enterprise/Education) — and even that does not stop toggling *inside* a running MT4. → The practical lockdown is **headless service + non-admin account + NTFS ACLs**, not kiosk. Source: learn.microsoft.com.
- **DLL-free file bridge** (DWX Connect pattern — fits our existing `MQL4/Files` JSON bridge exactly): cockpit writes an order command file → EA reads it + calls `OrderSend` **with SL/TP together**. No DLL required. (ZeroMQ would be faster but needs `libzmq`/`libsodium` DLLs = compliance/security risk.) Source: github.com/darwinex/dwxconnect.
- **Investor password** (read-only, **server-enforced**): you can see your account (charts/positions) but cannot place/close anything outside the cockpit. Source: ea-coder.com.
- **Master password = the whole lever:** MT4 allows the same account in several terminals at once → whoever holds the master password opens a 2nd terminal and bypasses everything. No-override therefore reduces to **keeping the master password secret** (only on the VPS, never with you). **That is exactly what is forbidden on FTMO and allowed on your own account.** Source: ea-coder.com.
- **The pre-execution block** must sit in the cockpit/relay (not only in the EA), because an EA only sees orders that pass through *its* terminal. SL/TP on market orders is not always atomic → "fill without stop" = emergency close required. Source: docs.mql4.com/trading/ordersend.

---

## 4. Recommendation (for you: solo, FTMO target, Mac)

1. **Accept reality:** On FTMO the tool is a **discipline aid** (self-imposed, self-revocable). Hard floor = FTMO's 5 %/10 %. Buffer below that internally (2 %/6 %).
2. **Build an accountability/alert layer (RULE-COMPLIANT):** The EA reports immediately when you switch off/remove the protection → cockpit banner "SCHUTZ AUS seit …" (protection off since …) + alert to a partner (Telegram/e-mail). The partner **only receives alerts, NEVER accesses the account** → no third-party access → **allowed**. This is the most effective *permitted* lever (social commitment instead of technical coercion).
3. **Your own VPS for stability** (fixes the Wine crash **and** delivers the continuous midnight baseline) — allowed.
4. **Full no-override only on a demo/own account** — that is where you train "I cannot outsmart myself" without violating FTMO rules.

---

## 5. Clarify in writing with FTMO before ANY implementation

> **Partly answered — see the 2026-10-29 addendum below and [FTMO-INQUIRY.md](FTMO-INQUIRY.md).**

- May an accountability partner hold the master password / VPS admin? *(The wording says: no — get it confirmed in writing.)*
- Are external order bridges (MetaApi/MTsocketAPI etc.) allowed, or are they "third-party access/automated"?
- Are DLL-based EAs (libzmq) allowed, or only the DLL-free file bridge?
- Does FTMO issue an **investor password** for MT4 (server-dependent)?
- Is a "cockpit-gated, no manual override" relay acceptable, or does pre-filtering your own orders count as coordinated/third-party?

---

## 6. Conclusion in one sentence

**"The account holds the limits and I cannot get at them" is structurally impossible on FTMO** (their rules demand sole access). Achievable & rule-compliant: **FTMO's server limit as the floor + alert accountability + your own VPS for stability**. You build the real self-lockout mechanism on your **own/demo account**.

---

# Addendum 2026-10-29 — the investor-password route is refuted

The July plan named the investor password as a building block (section 3) and asked whether FTMO
issues one (section 5). Both are now answered, and the answer kills the architecture that was
built on top of them. Recorded here so it is not proposed again.

## 1. FTMO does issue a read-only password — and shows it to you next to the master password

FTMO's own FAQ, *How do I log in to MT4?*:

> "Both passwords are visible in the Credentials section."
> "Trading-related actions require the master password."
> — <https://ftmo.com/en/faq/how-do-i-log-in-to-mt4/> (verified 2026-10, identical wording on the MT5 page)

A master password that only the VPS knows is therefore **impossible on FTMO**: it is displayed in
your own Client Area under Account MetriX → Credentials. Logging yourself in read-only is two
clicks away from being undone. That is a reminder, not a commitment.

## 2. Worse: under investor login the EA cannot trade either

MetaQuotes' official MT4 help, *Authorization*:

> "Investor authorization allows you to see the account status, analyze prices, and work with your
> own Expert Advisors, but not trade."
> "Automated trading by Expert Advisors is not allowed either."
> — <https://www.metatrader4.com/en/trading-platform/help/userguide/authorization>

The restriction hangs on the authorization type of the **server session**, so it cannot be toggled
off in the terminal. In such a session TradingGuard could close nothing and delete nothing — the
watchdog would be disarmed along with the trader. An investor login is useful for giving a
*read-only observer* a view, and for nothing else here.

## 3. What is confirmed allowed (unchanged, now with sources)

| Topic | Status | Source |
|---|---|---|
| Your own VPS | allowed — "The use of VPN/VPS is also generally allowed." Only documented limit: no US geolocation / US login | [FTMO FAQ](https://ftmo.com/en/faq/can-i-travel-or-use-vpn-vps/) |
| Your own EA / algo | allowed — "whether it's discretionary trading, algorithmic trading or EAs" | [FTMO FAQ](https://ftmo.com/en/faq/which-instruments-can-i-trade-and-what-strategies-am-i-allowed-to-use/) |
| Technical ceiling | ~200 simultaneous pending orders, ~2,000 server-side order actions/day ("hyperactivity") | same |
| Third-party access | forbidden — clause 7.2: "only you personally can access the Services and perform simulated trades"; 7.2.1 forbids granting access to or cooperating with any third party | T&C 2026-10-12 |
| Credentials | 4.3: must not be shared with any third party. 4.4: you are responsible for everything done with them | same |

Your own VPS is **not** a third party — software cannot be, or EAs would not be allowed, and FTMO
explicitly allows them. What matters is that nobody else can reach the VPS or the account.

## 4. The password question is settled — and it closes the route for good

The Client Area's *Login Credentials* dialog carries a **Change** button beside the master password
*and* beside the read-only password (observed on an FTMO-Server2 MT4 account, 2026-10-29).

Two consequences, and the second is the important one:

- **There is no irreversible-lockout risk.** A password change can always be undone from the Client
  Area, so nothing built on password rotation can strand you out of a funded account. The warning
  that stood here before is withdrawn.
- **Self-binding through passwords is impossible, permanently.** The lever sits in the account
  holder's own hands by design: both passwords are displayed, and both can be reset at will by the
  person the restriction is meant to bind. No arrangement of master and investor passwords can
  produce a stop its owner cannot lift.

Together with §1 and §2 above, the entire password-based branch is now closed by evidence rather
than by assumption.

## 4a. What is still worth asking

- **A self-requested pause.** FTMO already offers traders a *freeze* — "a pause of an account,
  especially in case of planned longer inactivity, for example, a holiday" — but neither the
  request route, the available durations, nor whether it can be made binding is published anywhere.
  This is the one mechanism that could deliver real no-override without a third party.
- **A soft limit at a self-chosen figure.** The behaviour already exists in FTMO's platform: on a
  *soft* breach "the platform closes your open positions and locks the account for the rest of the
  trading day. The account reopens for the next session, and you can continue trading" — the
  account is not failed. On the FTMO Futures Growth Sim-Funded Account the Daily Loss Limit is a
  soft limit by design. What is undocumented is whether the trigger can be set to a number the
  trader picks, well inside the hard limits.

Both go to support: [FTMO-INQUIRY.md](FTMO-INQUIRY.md).

## 5. Also noted

Clause 9.4.6 prohibits automated access to FTMO's own systems. Account data must come from MT4,
never from scraping the Client Area.

## 6. Conclusion

Section 0's core finding stands and is now better supported: **on FTMO, "the user has no option to
disable the protection" is not achievable.** All three candidate routes are closed — a third party
is forbidden by clause 7.2, FTMO documents no self-imposed server-side limit, and the investor
password is both visible to the trader and fatal to the EA. What remains on FTMO is an always-on
own VPS (so phone trades and a switched-off home PC are still covered), delay-based friction, and
alerting that makes switching the protection off visible. The genuine self-lockout belongs on an
own broker account.

---

# Addendum 2026-11-05 — FTMO answered in writing. The question is closed.

A support ticket put the five remaining questions to FTMO (full text and verbatim answers in
[FTMO-INQUIRY.md](FTMO-INQUIRY.md)). The two that decided the architecture:

> **Q: a self-requested trading pause you would not lift early?**
> "No, there is no option for your request."
>
> **Q: a threshold of my own that pauses without counting as a breach?**
> "No, there is no option for your request for CFDs."

Section 0 of this document predicted exactly this in July, from the rules alone. It is now
confirmed by FTMO directly, not inferred. **On an FTMO CFD account, a limit the trader sets cannot
be enforced against the trader. Every route is closed:**

| Route | Status |
|---|---|
| A third party holds the lever | forbidden — clause 7.2, "only you personally" |
| FTMO enforces a figure you choose | **"No" — in writing, 2026-11-05** |
| FTMO holds a cool-off you cannot lift | **"No" — in writing, 2026-11-05** |
| Self-lockout via the investor password | both passwords shown in the Client Area, and an investor session disarms the EA too |
| Self-lockout via the master password | changeable only in the Client Area, and **"if you lose it, you lose the account"** — no recovery path. Never build on it. |
| FTMO's own Mentor App | takes the parameters, but runs in your platform and only alerts; "Close error trades" is a button you press |

## What FTMO did clear

- **VPS: unrestricted.** "We do not have restrictions on IP addresses or the number of devices you
  use" — only restricted countries, and no USA IPs on MT4/MT5/cTrader. The shared-IP question that
  could have made a rented VPS look like account sharing is answered directly.
- **Own EAs: fine, no pre-approval.** "Your trading style is up to you… discretionary trading,
  algorithmic trading, EAs." Copy trading is allowed too; the cap is 400,000 USD per person or per
  strategy.

So the always-on VPS running TradingGuard is cleared without reservation. That is the part worth
spending money on: it covers phone trades and a switched-off home PC, which is where the real gap
was.

## The one qualifier worth chasing

"No option **for CFDs**". On **FTMO Futures** the Daily Loss Limit of the Growth Sim-Funded Account
is a *soft* limit by design: positions closed automatically, trading suspended for the remainder of
the day, account not failed, normal next session — server-side and not switchable off. Still FTMO's
threshold rather than a chosen figure, so not the 2 % stop, but it is the only unbypassable daily
pause in their range. Worth one question before dismissing it.

## Where this leaves TradingGuard

Unchanged in substance, but now settled rather than assumed:

1. **Always-on VPS** — cleared, and the single biggest real-world improvement.
2. **Delay-based pause** — friction instead of a wall: request, wait, bounded window, automatic
   re-arm. The best that is achievable on FTMO, and the user endorsed this design.
3. **Alerting plus a non-deletable coverage log** — switching the protection off becomes visible
   after the fact, which is the only lever left once technical coercion is ruled out.
4. **The genuine self-lockout belongs on an own broker account**, where clause 7.2 does not apply.

What does *not* change: the hard floor on FTMO stays FTMO's own 5 % daily / 10 % total. Everything
TradingGuard enforces below that is self-imposed and self-revocable, by design and by their rules.
Saying otherwise in any documentation would be a lie to the user.
