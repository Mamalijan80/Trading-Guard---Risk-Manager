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
