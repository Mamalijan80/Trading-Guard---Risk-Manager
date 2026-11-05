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
| `MAMAL_PASS_*` | from `npm run set-password-env` |

`PORT` is supplied by the platform and is picked up automatically.

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
