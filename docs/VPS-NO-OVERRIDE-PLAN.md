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

- May an accountability partner hold the master password / VPS admin? *(The wording says: no — get it confirmed in writing.)*
- Are external order bridges (MetaApi/MTsocketAPI etc.) allowed, or are they "third-party access/automated"?
- Are DLL-based EAs (libzmq) allowed, or only the DLL-free file bridge?
- Does FTMO issue an **investor password** for MT4 (server-dependent)?
- Is a "cockpit-gated, no manual override" relay acceptable, or does pre-filtering your own orders count as coordinated/third-party?

---

## 6. Conclusion in one sentence

**"The account holds the limits and I cannot get at them" is structurally impossible on FTMO** (their rules demand sole access). Achievable & rule-compliant: **FTMO's server limit as the floor + alert accountability + your own VPS for stability**. You build the real self-lockout mechanism on your **own/demo account**.
