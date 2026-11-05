// TradingGuard — risk and discipline tool for MetaTrader 4
// Copyright (C) 2026 Mohammadreza Tavakoli — https://itavakoli.com/
//
// This program is free software: you may redistribute it and/or
// modify it under the terms of the GNU Affero General Public License,
// version 3 or (at your option) any later version.
//
// It is published in the hope that it will be useful, but
// WITHOUT ANY WARRANTY — not even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Details in
// the GNU Affero General Public License: <https://www.gnu.org/licenses/>.
//
// Authentication for the cockpit. Zero dependencies — everything here comes out of
// Node's own crypto module, like the rest of the server.
//
// WHY THIS EXISTS: on localhost a missing login costs nothing. The moment the cockpit is
// reachable from a phone it serves live account data, and in the planned setup it will
// place orders. Without a login, whoever finds the address owns both. So: a password,
// signed session cookies, and a server that REFUSES to listen on a public interface
// unless a password is set — the same fail-closed stance the EA takes.
'use strict';
const crypto = require('crypto');
const fs     = require('fs');
const path   = require('path');

const CONFIG = path.join(__dirname, 'cockpit-config.json');

// scrypt parameters. N=16384 is Node's default and lands around 60-100 ms on a small VPS —
//   slow enough to make offline guessing expensive, fast enough that a login does not hang.
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };
const SESSION_HOURS = 24 * 14;   // a phone should not have to log in every morning

function readConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG, 'utf8')); }
  catch (e) { return null; }
}

function writeConfig(cfg) {
  // mode 0600: on Linux/macOS the file is then unreadable for other accounts on the VPS.
  //   Windows ignores the mode — there the folder ACL has to do it. Documented, not pretended.
  fs.writeFileSync(CONFIG, JSON.stringify(cfg, null, 2), { mode: 0o600 });
}

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, SCRYPT.keylen, SCRYPT).toString('hex');
}

// Does this installation have a password at all?
function isConfigured() {
  const c = readConfig();
  return !!(c && c.passHash && c.passSalt && c.sessionSecret);
}

function setPassword(password) {
  if (typeof password !== 'string' || password.length < 10) {
    throw new Error('Passwort muss mindestens 10 Zeichen haben.');
  }
  const old = readConfig() || {};
  const salt = crypto.randomBytes(16).toString('hex');
  writeConfig({
    passSalt: salt,
    passHash: hashPassword(password, salt),
    // Changing the password invalidates every open session: the secret is new, so no old
    //   cookie verifies any more. That is what you want when the password leaked.
    sessionSecret: crypto.randomBytes(32).toString('hex'),
    sessionEpoch: (old.sessionEpoch || 0) + 1,
    createdAt: new Date().toISOString(),
  });
}

function verifyPassword(password) {
  const c = readConfig();
  if (!c || !c.passHash || !c.passSalt) return false;
  const got = Buffer.from(hashPassword(String(password), c.passSalt), 'hex');
  const want = Buffer.from(c.passHash, 'hex');
  // Equal length by construction, but timingSafeEqual throws on a mismatch, so check first.
  if (got.length !== want.length) return false;
  return crypto.timingSafeEqual(got, want);
}

// ── Sessions ────────────────────────────────────────────────────────────────────────────
// Stateless and signed: the cookie carries its own expiry, the HMAC makes it unforgeable.
// No server-side table, so a restart does not log you out — and `sessionEpoch` in the
// config is the kill switch that invalidates everything at once.
function makeSession() {
  const c = readConfig();
  if (!c) return null;
  const payload = JSON.stringify({
    exp: Date.now() + SESSION_HOURS * 3600 * 1000,
    epoch: c.sessionEpoch || 1,
    sid: crypto.randomBytes(12).toString('hex'),
  });
  const body = Buffer.from(payload).toString('base64url');
  const sig = crypto.createHmac('sha256', c.sessionSecret).update(body).digest('base64url');
  return body + '.' + sig;
}

function validSession(token) {
  if (!token || typeof token !== 'string') return false;
  const c = readConfig();
  if (!c || !c.sessionSecret) return false;
  const dot = token.lastIndexOf('.');
  if (dot < 1) return false;
  const body = token.slice(0, dot), sig = token.slice(dot + 1);
  const want = crypto.createHmac('sha256', c.sessionSecret).update(body).digest('base64url');
  const a = Buffer.from(sig), b = Buffer.from(want);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return false;
  let p;
  try { p = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); } catch (e) { return false; }
  if (!p || typeof p.exp !== 'number' || Date.now() > p.exp) return false;
  if ((p.epoch || 0) !== (c.sessionEpoch || 1)) return false;   // password changed since
  return true;
}

function logoutEverywhere() {
  const c = readConfig();
  if (!c) return;
  c.sessionEpoch = (c.sessionEpoch || 1) + 1;
  writeConfig(c);
}

function parseCookies(req) {
  const out = {};
  const raw = req.headers.cookie;
  if (!raw) return out;
  for (const part of raw.split(';')) {
    const i = part.indexOf('=');
    if (i < 1) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

// ── Brute-force brake ───────────────────────────────────────────────────────────────────
// Per client address, in memory. A restart clears it, which is acceptable: an attacker who
// can restart the server has already won. Doubling lockout, capped at 15 minutes.
const fails = new Map();
const MAX_TRIES = 5;

function clientKey(req) {
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}

function lockedFor(req) {
  const f = fails.get(clientKey(req));
  if (!f || !f.until) return 0;
  const left = f.until - Date.now();
  return left > 0 ? Math.ceil(left / 1000) : 0;
}

function noteFailure(req) {
  const k = clientKey(req);
  const f = fails.get(k) || { n: 0, until: 0 };
  f.n++;
  if (f.n >= MAX_TRIES) {
    const steps = f.n - MAX_TRIES;
    f.until = Date.now() + Math.min(900, 60 * Math.pow(2, steps)) * 1000;
  }
  fails.set(k, f);
}

function noteSuccess(req) { fails.delete(clientKey(req)); }

module.exports = {
  CONFIG, SESSION_HOURS,
  isConfigured, setPassword, verifyPassword,
  makeSession, validSession, logoutEverywhere,
  parseCookies, lockedFor, noteFailure, noteSuccess,
};
