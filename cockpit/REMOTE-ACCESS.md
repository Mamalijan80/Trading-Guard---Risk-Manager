# Cockpit from the phone — login and reachability

The cockpit shows live account data and accepts commands. In the planned setup it will place
orders. So the order is: **login first, reachability second.** Nothing here is optional once the
server leaves `localhost`.

## Nothing changes if you do nothing

Default bind is `127.0.0.1`, no password, exactly as before. The server only forces a login once
one is configured.

## 1. Set a password

```bash
node server.js --set-password
```

Writes `cockpit/cockpit-config.json` (scrypt hash, salt, session secret — gitignored, never
commit it). Changing the password invalidates every open session.

Once you are logged in, the same thing is available in the browser under **Passwort** (the key
in the header, or `/passwort`): set a new one, or check whether a password matches the hash
that is currently in force. Setting one asks for the current password as well — a session
cookie alone must not be enough, or a cookie that went astray turns a reader into someone who
locks you out for good. A cookie can be revoked; a changed password cannot. That page is the only route that works on a host where there is no
command line to run `node` on — see *Locked out of the hosted cockpit* below.

From then on the login applies to **everything, including localhost**. Sessions last 14 days in an
`HttpOnly; SameSite=Strict` cookie, `Secure` as soon as TLS is on. Five wrong attempts start a
doubling lockout up to 15 minutes, per client address.

## 2. Make it reachable

### Recommended: a private network, not the open internet

[Tailscale](https://tailscale.com) or WireGuard put the phone and the server on one private
network. Nothing is published, there is no login page for strangers to hammer, and Tailscale hands
you real certificates:

```bash
tailscale cert cockpit.your-tailnet.ts.net          # writes .crt and .key
MAMAL_BIND=100.x.y.z \
MAMAL_HOSTS=cockpit.your-tailnet.ts.net \
MAMAL_TLS_CERT=cockpit.your-tailnet.ts.net.crt \
MAMAL_TLS_KEY=cockpit.your-tailnet.ts.net.key \
node server.js
```

### Alternative: public, behind a reverse proxy

Caddy or nginx terminates TLS with Let's Encrypt and forwards to `127.0.0.1:8730`. The cockpit
itself then stays on loopback and needs no TLS of its own — but set `MAMAL_HOSTS` to the public
name, or the host check rejects the proxied requests.

## 3. The startup guard

With `MAMAL_BIND` pointing anywhere other than loopback, the server **refuses to start** unless:

| Requirement | Why |
|---|---|
| a password is set | otherwise whoever finds the address owns the account view and the commands |
| `MAMAL_HOSTS` is set | DNS-rebinding protection: a request whose `Host` is not on the list is rejected |
| TLS is on | without it the password crosses the network in clear text |

`MAMAL_ALLOW_PLAINTEXT=1` overrides the TLS requirement. Only sensible inside a network that is
already encrypted — a WireGuard tunnel, for instance. It prints a warning on every start.

The point of the guard is that you cannot expose this by accident. Same stance as the EA: rather
not run at all than run unprotected.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `MAMAL_PORT` | `8730` | port |
| `MAMAL_BIND` | `127.0.0.1` | interface to listen on |
| `MAMAL_HOSTS` | — | comma-separated host names that are accepted |
| `MAMAL_TLS_CERT` / `MAMAL_TLS_KEY` | — | certificate and key; both present switches on HTTPS |
| `MAMAL_ALLOW_PLAINTEXT` | — | `1` permits a non-local bind without TLS |
| `MAMAL_QUIETSTART` | — | `1` suppresses the browser popup (autostart) |
| `MAMAL_FILES` | — | override for the MQL4 `Files` folder when the beacon fails |
| `MAMAL_CONFIG` | `cockpit/cockpit-config.json` | where the password file lives. Point it at a volume and the cockpit may write its own password — that is what makes `/passwort` self-sufficient in a container |
| `MAMAL_PASS_PLAIN` | — | emergency access: the password in clear text. Beats everything else, so it also gets you back in when the stored hash is wrong. Delete it again afterwards |
| `MAMAL_PROXY_HOPS` | `1` | how many trusted proxies sit in front, counted back from the end of `X-Forwarded-For` |

## Two things worth saying plainly

**The login is yours alone.** Handing it to anyone else is third-party access to the trading
account under FTMO clause 7.2, the same clause that rules out an accountability partner. It is a
password for you on the road, not a shared door.

**Without TLS the session cookie is readable in transit**, and anyone holding it is logged in until
it expires. On an untrusted network — hotel, café, mobile hotspot — treat plaintext mode as if
there were no login at all.

---

# Trading from the browser

The cockpit can place and manage orders. Everything below exists because of one property of
the EA, and it is worth stating first: **R22 closes any position carrying a foreign magic
number, account-wide, within seconds, regardless of any lock.** A second terminal, a bridge,
the broker's web platform, the MetaTrader phone app — each of them would have its position
closed at market moments after opening, paying spread and slippage for the attempt.

So there is exactly one route that survives, and the design did not choose it:

```
browser  ──▶  cockpit  ──▶  mamal_cmdq.txt  ──▶  the EA's own DoEntry  ──▶  OrderSend
                 ▲                                        │
                 └──────────  mamal_ack.csv  ◀────────────┘
```

## The queue, and why it is not a single file

`mamal_cmd.txt` had exactly one slot, which the server overwrote. Two commands inside one EA
cycle and one was gone — harmless for "end the day", unacceptable for "close EURUSD", where
the dashboard would report success and nothing anywhere would say otherwise.

One line per command: `id|cmd|symbol|a1|a2|issued`. **Exactly one writer per file:** the
cockpit writes only the queue, the EA writes only the receipts. There is no write conflict to
resolve, which is the whole reason the files are split that way.

| Rule | Why |
|---|---|
| marked done **before** executing | a crash mid-order loses the command instead of repeating it. For opening that is the only correct direction: a missing order is visible at once, a doubled one may never be noticed |
| nothing is deleted | deleting the file as a receipt made a failed READ indistinguishable from "no command". The EA only marks what it did; the cockpit clears the line once it has seen the receipt |
| read with share flags | without `FILE_SHARE_READ\|FILE_SHARE_WRITE` the open fails as soon as the server touches the same file — the journal already learned this in v0.44 |
| older than `InpCmdMaxAgeSec` (120 s) expires | a command that waited out a dead terminal must not fill on Monday at a price nobody saw |
| symbol-bound commands run in the instance holding that symbol | the master sits on whichever of the six charts it happens to sit on. A "close EURUSD" from it would have hit GBPJPY — the most expensive bug this design can produce |

Commands: `endday`, `flat`, `closesym`, `half`, `be`, `close <ticket>`, `buy <stop>`,
`sell <stop>`. The whitelist lives in one place in the server and nothing outside it reaches
the file. **The channel cannot loosen a rule** — it can set a lock, never shorten one.

## What an order carries, and what it does not

It carries a **symbol** and a **stop price**. That is all.

It does not carry a position size: `CalcLot()` derives that from your risk per trade and the
stop distance, in the EA, where it always has. Computing it in two places means computing it
differently in two places sooner or later, and that is the one number whose correctness
justifies the entire tool.

It does not carry a target either: the target still comes from the stop distance and `InpRR`,
or an order from the browser could undercut the reward-to-risk ratio R8 exists to enforce.

And it may never inherit the chart's stop line. That line can be two days old; the size hangs
off the stop distance, so the position would be sized against a distance nobody meant — and R1
would close it again seconds later.

`DoEntry` gained exactly one parameter for this, the stop price. Between the top of that
function and the single `OrderSend` there are nineteen checks, and a browser order walks all
of them. **A rejection names the rule**: the journal's reason travels back in the receipt, so
the browser says "refused: R3 daily budget" instead of a button that quietly did nothing.

## Three states, and the third always gives a reason

Sent → waiting for the terminal → done or refused. A button that merely stops spinning does
not tell you whether anything happened, and in a risk tool "you believe you are protected and
are not" is the worst failure there is. Receipts carry the ticket, the price and the reason.

The success signal is the ticket `DoEntry` actually opened, held in an ordinary variable
belonging to that one instance. It is deliberately **not** the fill counter: that lives in a
GlobalVariable shared by all six instances, so a click on another chart's panel in the same
second would have acknowledged a failed remote order as done.

## What this needs to work at all

The command file has to land in a `MQL4/Files` folder a MetaTrader actually reads. On a relay
it lands in a container instead, and the push agent beside MT4 only ever sends — it never
fetches. Both `/cmd/send` and the self-lock therefore refuse on a relay instance and say so,
rather than writing into the void and reporting success.

That restriction disappears by itself once MetaTrader and the cockpit sit on the same machine,
which is the point of moving to a VPS: the command becomes a local file again, and the round
trip drops from five to fifteen seconds to one or two.

**Not from a US address.** FTMO allows VPN and VPS without restriction on IP addresses or the
number of devices, confirmed in writing on 05.11.2026, but no US IPs on MT4/MT5/cTrader. The
classic forex VPS is New York; choose London, Frankfurt or Amsterdam.

---

# Relay mode — the cockpit in a container

A container has no MetaTrader and no MQL4 folder, so the cockpit there has nothing to read.
Relay mode fills that folder over HTTP instead: an agent beside MT4 pushes the state, the relay
writes it into one directory per account, and **every other part of the server works unchanged** —
for them it looks like an ordinary MQL4 `Files` folder.

```
MT4 + EA  ──writes──▶  MQL4/Files  ──reads──▶  agent  ──POST /ingest──▶  relay  ──▶  phone
 (your PC, later the Hetzner box)              (node server.js)          (Railway)
```

The EA stays DLL-free and has no network code of its own: Node makes the outbound connection,
not MQL4.

## The relay (Railway, Fly, any container)

| Variable | Value |
|---|---|
| `MAMAL_FILES_ROOT` | `/data/mamal` — one subfolder per account, created on ingest |
| `MAMAL_INGEST_TOKEN` | a long random string, the same on both sides |
| `MAMAL_BIND` | `0.0.0.0` |
| `MAMAL_HOSTS` | the service hostname |
| `MAMAL_TRUST_PROXY` | `1` — the platform terminates TLS, the cookie still gets `Secure` |
| `MAMAL_PASS_*` | from `npm run set-password-env`, or from `/passwort` in the browser |
| `MAMAL_CONFIG` | `/data/cockpit-config.json` — needs a volume mounted at `/data` |
| `MAMAL_FILES_ROOT` | `/data/mamal` with a volume, otherwise the data is gone on every deploy |
| `MAMAL_DATA_DIR` | `/data/equity` with a volume. The equity series is sampled here from the live accounts, not sent by the agent, so once a deploy wipes it nobody can supply it again |

`PORT` is supplied by the platform and is picked up automatically.

**With a volume, the cockpit administers itself.** Mount one at `/data`, set `MAMAL_CONFIG` to
a path inside it, and a password set under `/passwort` is written there and survives every
deploy. Without a volume the page deliberately refuses to write the file and prints the four
variables instead — a password that works until the next deploy and then silently reverts to
the old one is worse than no password change at all.

The volume is the whole storage layer, and it is deliberately not a database. What has to
persist is one record: a hash, a salt, a session secret and a counter. A database service for
that would mean a second thing to pay for, a second thing that can be down while you are
standing in front of the login page, and — because this server has no dependencies at all and
nobody speaks the Postgres wire protocol by hand — the first `npm install` in the project. The
file on the volume survives exactly the same events and needs none of that. Point
`MAMAL_FILES_ROOT` into the volume as well and the ingested account data stops being wiped on
every deploy too.

The write itself is all-or-nothing: the file is written beside the target and then renamed,
and `rename()` within one filesystem is indivisible. Without that, a deploy landing mid-write
would leave a truncated JSON behind — the password would not be broken but *gone*, the server
would quietly fall back to the `MAMAL_PASS_*` variables, the previous password would work
again, and nothing anywhere would say why. If the file ever does turn up unreadable, the
server says so in the log instead of falling back in silence.

## Where the password comes from

Three sources, in this order — the first one that answers wins:

| Order | Source | Why it is where it is |
|---|---|---|
| 1 | `MAMAL_PASS_PLAIN` | the emergency door. It has to beat the stored hash, because the usual reason for needing it is that the stored hash is not the one you think it is |
| 2 | the file at `MAMAL_CONFIG` | the current state: it is the only one `/passwort` can change |
| 3 | `MAMAL_PASS_HASH` / `_SALT` / `_SESSION_SECRET` | the seed. In a container without a volume, the only place that survives a deploy |

**Once the file works, the variables can go.** As long as `MAMAL_PASS_HASH` and friends sit in
the list, they stay a second, silent way in: lose the file and the old password is live again,
with the old session secret, so a cookie that should have died comes back with it. Deleting them
is safe — the authentication gate latches, so once a password has ever been configured the
cockpit will not serve a single page without a login again, whatever happens to the file
afterwards, and a restart with no password at all is refused outright by the startup guard.

The file beating the variables is the part worth remembering. The other way round, a password
set in the browser would lose against the old hash in the variable list and the change would do
nothing at all — without an error message. `/passwort` always names the source that is actually
in force, so you never have to guess which of the three you are looking at.

### Locked out of the hosted cockpit

There is no command line over there to run `--set-password` on. The way back in is one variable,
and it needs nothing installed anywhere:

1. At the host, set `MAMAL_PASS_PLAIN` to a password of at least 10 characters.
2. The service restarts by itself. Log in with exactly that.
3. Open **Passwort**, set a real password there.
4. Delete `MAMAL_PASS_PLAIN` again.

Step 4 is not cosmetic. A clear-text password in a variable list gets copied, screenshotted and
pasted into chats, and as long as it is there it beats the password set in step 3 — the page and
the startup log both say so, loudly.

Step 3 ends differently depending on whether the service has a volume: with one, the password is
written to `MAMAL_CONFIG` and that is the end of it. Without one, the page prints
`MAMAL_PASS_HASH`, `MAMAL_PASS_SALT`, `MAMAL_SESSION_SECRET` and `MAMAL_SESSION_EPOCH` for you to
paste into the variable list, which is the same four lines `node server.js --set-password --env`
produces locally — just without the local `node`.

Either way the new session secret logs out every open session, which is the point: it is also how
you throw out a cookie you think went astray. The ingest token is separate, so the agent beside
MT4 keeps pushing throughout.

### Is it the password, or is it the hash?

A 401 from the host looks the same either way, and guessing costs an evening. Ask instead.

If you can still get in, the answer is in the browser: **Passwort** → *Passwort pruefen* checks
against the hash that is in force on the very instance you are looking at, and answers nothing but
*passt* or *passt nicht*.

If you cannot get in, do it from your own machine — copy `MAMAL_PASS_HASH` and `MAMAL_PASS_SALT`
out of the host's variable list and check a password against them locally:

```bash
node server.js --check-password --hash <MAMAL_PASS_HASH> --salt <MAMAL_PASS_SALT>
```

The password is asked for hidden and never written anywhere; the answer is just *passt* or *passt
nicht*. Hash and salt are verifiers, not secrets of the same rank — they already sit in plain view
in that variable list. Without `--hash`/`--salt` it checks against this installation's own config.

*Passt nicht* means the password is simply a different one — reset it as above. *Passt*, while the
host still answers 401, means the two sides do not hold the same hash: compare the variables
character by character, and look for a trailing space or line break from pasting.

Five wrong attempts start a doubling lockout per client address, up to 15 minutes. It lives in
memory, so replacing the variables clears it along with the restart.

**The lockout throttles, it does not refuse.** While it runs, one attempt every ten seconds still
gets checked — so a correct password always gets in, at worst ten seconds late. A lockout that
turns a correct password away is a weapon: whoever can hit your bucket keeps you out of your own
cockpit for a quarter of an hour, as often as they like. Ten seconds a try is still four hundred
times worse for someone guessing than the 60-100 ms that scrypt costs, so nothing is given away.

Behind a proxy the address needs care. `remoteAddress` is the proxy's — the same for every
visitor — so the brake would have one bucket for everybody. With `MAMAL_TRUST_PROXY` the count
goes by `X-Forwarded-For`, and by the **last** entry, not the first: a proxy appends the address
it actually sees, so anything the caller made up sits in front of it and the truth sits at the
end. `MAMAL_PROXY_HOPS` says how many trusted stations to count back, if it is ever more than one.

Two more brakes sit behind that one. The table of failed attempts forgets an address after
fifteen minutes and is capped, so nobody can fill memory by inventing a new address per request.
And across all addresses together, at most thirty password checks run per ten seconds: each one
costs 60-100 ms during which the server does nothing else, so without that ceiling a flood of
login attempts would stall the whole cockpit, account data included.

## The agent (where MT4 runs)

```bash
MAMAL_PUSH_URL=https://your-service.up.railway.app/ingest \
MAMAL_INGEST_TOKEN=<same token> \
MAMAL_PUSH_SEC=5 \
node server.js
```

It stays a normal local cockpit on `localhost:8730` and pushes on the side. The journal only goes
over the wire when it has actually changed — it is large and rarely moves.

## Two details that are not obvious

**Source timestamps travel with the data.** Without that, every file on the relay carries the
moment of ingest, all accounts look equally fresh, and the account switcher picks at random — in
testing a two-day-old account beat the live one. The agent sends the source `mtime`, the relay
applies it, and is capped at "now" so a fast clock on the agent cannot fake freshness.

**Account data leaves your machine.** Balances, trades and the journal end up on someone else's
server. No credentials go with them — the relay never sees a broker password and cannot trade. If
that trade-off is unwelcome, the alternative is the private-network route above, where nothing is
published at all.

**Forgetting an account means two different things.** An expired challenge otherwise sits in
the switcher forever. On the relay each account has a directory this server created itself, so
the trash can beside the switcher really deletes it, equity series included. On the cockpit next
to MetaTrader those directories are the `MQL4/Files` folders of running terminals — journal,
state, lock record — so there the account is only hidden and nothing on disk is touched. Either
way it is refused while data is still arriving: a live account would be back within seconds, and
an action that undoes itself is worse than no action. An account that starts delivering again
reappears on its own; forgetting clears what is there, it is not a ban.

**Screenshots are not relayed.** `/shot/...` reads image files that are not pushed, so trade
screenshots stay blank on the relay. They work on the local cockpit.
