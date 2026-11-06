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

// Wo die Konfigurationsdatei liegt. MAMAL_CONFIG zeigt sie auf einen Datentraeger, der
// einen Deploy ueberlebt (Railway-Volume, Docker-Volume). Ist sie gesetzt, darf das Cockpit
// das Passwort SELBST schreiben — und damit im Browser aenderbar machen, ohne node.
const CONFIG = process.env.MAMAL_CONFIG || path.join(__dirname, 'cockpit-config.json');
const CONFIG_EXPLICIT = !!process.env.MAMAL_CONFIG;

// scrypt parameters. N=16384 is Node's default and lands around 60-100 ms on a small VPS —
//   slow enough to make offline guessing expensive, fast enough that a login does not hang.
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };
const SESSION_HOURS = 24 * 14;   // a phone should not have to log in every morning

// Woher das Passwort kommt — in genau dieser Reihenfolge:
//
//   1. MAMAL_PASS_PLAIN  Notzugang: das Passwort im Klartext in der Variablenliste des
//                        Hosters. Der einzige Weg zurueck in ein gehostetes Cockpit, fuer
//                        den man KEIN node auf dem eigenen Rechner braucht — Variable
//                        setzen, Dienst startet neu, anmelden. Danach gehoert sie geloescht.
//   2. die Datei         Sie ist der aktuelle Stand, denn nur sie laesst sich im Browser
//                        aendern (/passwort). Ohne Datentraeger ist sie beim naechsten
//                        Deploy weg, deshalb schreibt der Server sie nur, wenn MAMAL_CONFIG
//                        bewusst auf einen haltbaren Ort zeigt.
//   3. MAMAL_PASS_HASH/_SALT/_SESSION_SECRET  Der Startwert. In einem Container ohne
//                        Datentraeger der einzige Ort, der einen Deploy ueberlebt.
//
// WARUM DIE DATEI VOR DEN VARIABLEN STEHT: wer im Browser ein neues Passwort setzt, erwartet
// dass es gilt. In der umgekehrten Reihenfolge gewaenne der alte Hash aus der Variablenliste,
// und die Aenderung waere wirkungslos — ohne jede Fehlermeldung. Genau die Art stiller
// Fehlanzeige, die hier schon Abende gekostet hat.
function readConfigFile() {
  try { return JSON.parse(fs.readFileSync(CONFIG, 'utf8')); }
  catch (err) { return null; }
}

// scrypt kostet 60-100 ms. readConfig() laeuft bei JEDEM Aufruf (das Dashboard fragt alle
// 1,5 s), also wird die Ableitung aus dem Klartext einmal gerechnet und gemerkt.
let plainCache = null;
function configFromPlain() {
  const plain = process.env.MAMAL_PASS_PLAIN;
  if (!plain || String(plain).length < 10) return null;
  if (plainCache && plainCache.plain === plain) return plainCache.cfg;
  // Salt zufaellig, nicht aus dem Passwort abgeleitet: ein abgeleitetes Salt waere ein
  //   billiger Pruefwert fuer das Passwort und wuerde scrypt umgehen. Innerhalb des
  //   Prozesses bleibt es stabil, weil die Ableitung gemerkt wird.
  const salt = crypto.randomBytes(16).toString('hex');
  const cfg = {
    passSalt: salt,
    passHash: hashPassword(String(plain), salt),
    // Der Sitzungsschluessel muss ueber einen Neustart hinweg GLEICH bleiben, sonst ist man
    //   nach jedem Container-Neustart abgemeldet. Deshalb abgeleitet, nicht zufaellig.
    sessionSecret: process.env.MAMAL_SESSION_SECRET
      || crypto.createHash('sha256').update('mamal-session-v1:' + plain).digest('hex'),
    sessionEpoch: Number(process.env.MAMAL_SESSION_EPOCH || 1) || 1,
    fromEnv: true, fromPlain: true,
  };
  plainCache = { plain, cfg };
  return cfg;
}

// Ist MAMAL_PASS_PLAIN gesetzt, aber unbrauchbar? Dann wuerde sie stumm ignoriert — der
// Start-Hinweis sagt es stattdessen laut.
function plainProblem() {
  const plain = process.env.MAMAL_PASS_PLAIN;
  if (!plain) return '';
  if (String(plain).length < 10) return 'MAMAL_PASS_PLAIN ist kuerzer als 10 Zeichen und wird ignoriert.';
  return '';
}

function configFromEnv() {
  const e = process.env;
  if (e.MAMAL_PASS_HASH && e.MAMAL_PASS_SALT && e.MAMAL_SESSION_SECRET) {
    return {
      passHash: e.MAMAL_PASS_HASH,
      passSalt: e.MAMAL_PASS_SALT,
      sessionSecret: e.MAMAL_SESSION_SECRET,
      sessionEpoch: Number(e.MAMAL_SESSION_EPOCH || 1) || 1,
      fromEnv: true,
    };
  }
  return null;
}

function readConfig() {
  return configFromPlain() || readConfigFile() || configFromEnv();
}

// Fuer die Passwort-Seite: woher gilt das Passwort gerade, und darf der Server ein neues
// selbst schreiben? Ohne haltbaren Ort darf er es NICHT — sonst gilt das neue Passwort bis
// zum naechsten Deploy und danach wieder das alte, ohne dass irgendwo etwas davon steht.
function configSource() {
  if (configFromPlain())  return { kind: 'plain', canWrite: CONFIG_EXPLICIT, path: CONFIG };
  if (readConfigFile())   return { kind: 'file',  canWrite: true,            path: CONFIG };
  if (configFromEnv())    return { kind: 'env',   canWrite: CONFIG_EXPLICIT, path: CONFIG };
  return { kind: 'none', canWrite: true, path: CONFIG };
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

// Baut den Satz Geheimnisse. Changing the password invalidates every open session: the
// secret is new, so no old cookie verifies any more — what you want when it leaked.
function buildSecrets(password, oldEpoch) {
  if (typeof password !== 'string' || password.length < 10) {
    throw new Error('Passwort muss mindestens 10 Zeichen haben.');
  }
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    passSalt: salt,
    passHash: hashPassword(password, salt),
    sessionSecret: crypto.randomBytes(32).toString('hex'),
    sessionEpoch: (oldEpoch || 0) + 1,
    createdAt: new Date().toISOString(),
  };
}

function setPassword(password) {
  const cfg = buildSecrets(password, (readConfig() || {}).sessionEpoch);
  writeConfig(cfg);
  return cfg;
}

// Fuer Container: dieselben Geheimnisse, aber als Umgebungsvariablen zum Einfuegen,
// statt in eine Datei, die der naechste Deploy wegwirft.
function envForPassword(password) {
  const c = buildSecrets(password, 0);
  return [
    'MAMAL_PASS_HASH=' + c.passHash,
    'MAMAL_PASS_SALT=' + c.passSalt,
    'MAMAL_SESSION_SECRET=' + c.sessionSecret,
    'MAMAL_SESSION_EPOCH=' + c.sessionEpoch,
  ];
}

// Gehoert dieses Passwort zu diesem Hash? Getrennt von verifyPassword(), damit `--check-password`
// gegen einen Hash pruefen kann, der gar nicht in dieser Installation steht — und zwar mit
// DERSELBEN Rechnung, statt mit einer zweiten, schwaecheren Zweitfassung daneben.
//
// Das .trim() ist kein Schoenheitsfehler-Fang: Hash und Salt reisen als Umgebungsvariable durch
// eine Weboberflaeche, und ein mitkopiertes Leerzeichen oder Zeilenende laesst Buffer.from(...,'hex')
// still frueher abbrechen. Das Ergebnis waere ein kuerzerer Puffer, ein Laengenunterschied und
// damit ein dauerhaftes "falsches Passwort" bei voellig richtigem Passwort — eine Stunde Suche,
// die niemand beim Hash vermutet. Beim Salt dasselbe: er geht als String in scrypt, ein
// angehaengtes Leerzeichen ergibt einen anderen Schluessel.
function matchesHash(password, passHash, passSalt) {
  if (!passHash || !passSalt) return false;
  const got  = Buffer.from(hashPassword(String(password), String(passSalt).trim()), 'hex');
  const want = Buffer.from(String(passHash).trim(), 'hex');
  // Equal length by construction, but timingSafeEqual throws on a mismatch, so check first.
  if (got.length === 0 || got.length !== want.length) return false;
  return crypto.timingSafeEqual(got, want);
}

function verifyPassword(password) {
  const c = readConfig();
  return c ? matchesHash(password, c.passHash, c.passSalt) : false;
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

// Hinter einem Anbieter, der TLS beendet (Railway, Fly, nginx), ist remoteAddress die Adresse
// des PROXYS — bei jedem Besucher dieselbe. Die Sperre haette dann einen einzigen Topf fuer
// alle: ein Bot, der die Anmeldung abklopft, sperrt den Eigentuemer aus seinem eigenen
// Cockpit aus. Mit MAMAL_TRUST_PROXY zaehlt deshalb die vorderste Adresse aus X-Forwarded-For.
//
// Die ist faelschbar, und das ist hier das kleinere Uebel: wer sie faelscht, umgeht seine
// eigene Bremse — gegen das Passwort selbst steht weiter scrypt mit 60-100 ms je Versuch.
// Ohne die Aenderung trifft es garantiert den Falschen.
const TRUST_PROXY_HDR = /^(1|true|yes)$/i.test(process.env.MAMAL_TRUST_PROXY || '');
function clientKey(req) {
  if (TRUST_PROXY_HDR) {
    const xff = req.headers && req.headers['x-forwarded-for'];
    if (xff) {
      const first = String(xff).split(',')[0].trim();
      if (first) return first.slice(0, 64);
    }
  }
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
  CONFIG, CONFIG_EXPLICIT, SESSION_HOURS,
  isConfigured, setPassword, envForPassword, verifyPassword, matchesHash, readConfig,
  configSource, plainProblem,
  makeSession, validSession, logoutEverywhere,
  parseCookies, lockedFor, noteFailure, noteSuccess,
};
