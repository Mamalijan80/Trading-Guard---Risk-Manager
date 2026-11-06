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
that is currently in force. That page is the only route that works on a host where there is no
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

## Two things worth saying plainly

**The login is yours alone.** Handing it to anyone else is third-party access to the trading
account under FTMO clause 7.2, the same clause that rules out an accountability partner. It is a
password for you on the road, not a shared door.

**Without TLS the session cookie is readable in transit**, and anyone holding it is logged in until
it expires. On an untrusted network — hotel, café, mobile hotspot — treat plaintext mode as if
there were no login at all.

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
| `MAMAL_CONFIG` | `/data/cockpit-config.json` — only with a volume mounted at `/data` |

`PORT` is supplied by the platform and is picked up automatically.

**With a volume, the cockpit administers itself.** Mount one at `/data`, set `MAMAL_CONFIG` to
a path inside it, and a password set under `/passwort` is written there and survives every
deploy. Without a volume the page deliberately refuses to write the file and prints the four
variables instead — a password that works until the next deploy and then silently reverts to
the old one is worse than no password change at all. The volume also keeps the ingested account
data across deploys; today every deploy empties it until the agent pushes again.

## Where the password comes from

Three sources, in this order — the first one that answers wins:

| Order | Source | Why it is where it is |
|---|---|---|
| 1 | `MAMAL_PASS_PLAIN` | the emergency door. It has to beat the stored hash, because the usual reason for needing it is that the stored hash is not the one you think it is |
| 2 | the file at `MAMAL_CONFIG` | the current state: it is the only one `/passwort` can change |
| 3 | `MAMAL_PASS_HASH` / `_SALT` / `_SESSION_SECRET` | the seed. In a container without a volume, the only place that survives a deploy |

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

Behind a proxy that address needs care. `remoteAddress` is then the proxy's — the same for every
visitor — so the brake would have a single bucket for everyone and a bot hammering the login page
would lock the owner out of his own cockpit. With `MAMAL_TRUST_PROXY` the count therefore goes by
the first entry in `X-Forwarded-For`. That one is forgeable, and that is the lesser evil here:
forging it evades your own brake, while the password itself is still behind scrypt at 60-100 ms a
try. The alternative hits the wrong person every time.

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

**Screenshots are not relayed.** `/shot/...` reads image files that are not pushed, so trade
screenshots stay blank on the relay. They work on the local cockpit.
