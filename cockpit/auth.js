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
// Eine unlesbare Datei faellt auf die Variablen zurueck — und damit auf das ALTE Passwort.
// Das darf passieren, aber nicht stumm: sonst sucht man den Grund beim Passwort, waehrend er
// auf der Platte liegt. Einmal je Zustand melden, nicht bei jedem Aufruf: readConfig() laeuft
// bei jeder einzelnen Anfrage.
let fileComplaint = '';
function readConfigFile() {
  let raw;
  try { raw = fs.readFileSync(CONFIG, 'utf8'); }
  catch (err) {
    // ENOENT ist der Normalfall (noch kein Passwort gesetzt, oder reiner Variablen-Betrieb).
    //   Alles andere — keine Rechte, Ein-/Ausgabefehler, Verzeichnis statt Datei — ist ein
    //   Ausfall und fuehrt stumm zum ALTEN Passwort. Genau das darf nicht stumm sein.
    if (err.code !== 'ENOENT') {
      const m = 'Die Passwortdatei ' + CONFIG + ' ist nicht lesbar (' + err.code + ').'
              + ' Es gelten die MAMAL_PASS_*-Variablen, also das vorige Passwort.';
      if (fileComplaint !== m) { fileComplaint = m; console.error('  WARNUNG: ' + m); }
    } else { fileComplaint = ''; }
    return null;
  }
  try {
    const cfg = JSON.parse(raw);
    fileComplaint = '';
    return cfg;
  } catch (err) {
    const msg = 'Die Passwortdatei ' + CONFIG + ' ist unlesbar (' + err.message + ').'
              + ' Es gelten die MAMAL_PASS_*-Variablen, also das vorige Passwort.';
    if (fileComplaint !== msg) { fileComplaint = msg; console.error('  WARNUNG: ' + msg); }
    return null;
  }
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
  // canWrite haengt nicht nur daran, DASS MAMAL_CONFIG gesetzt ist, sondern auch daran, dass
  //   das Verzeichnis wirklich da ist. Sonst meldet die Seite "ueberlebt Neustart und Deploy",
  //   waehrend der Datentraeger gar nicht eingehaengt ist — eine Zusage, die erst beim
  //   Speichern zusammenbricht. Lieber vorher ehrlich sein.
  const dir = path.dirname(CONFIG);
  let dirOk = false;
  try { dirOk = fs.existsSync(dir); } catch (e) { dirOk = false; }
  // Der haeufigste Grund, warum MAMAL_CONFIG gesetzt ist und trotzdem nichts gespeichert
  //   werden kann: der Datentraeger haengt nicht da, wo die Variable hinzeigt. Das gehoert
  //   gesagt, sonst sucht man den Fehler beim Passwort.
  const why = (CONFIG_EXPLICIT && !dirOk) ? dir : '';
  if (configFromPlain())  return { kind: 'plain', canWrite: CONFIG_EXPLICIT && dirOk, path: CONFIG, missingDir: why };
  if (readConfigFile())   return { kind: 'file',  canWrite: dirOk,                    path: CONFIG, missingDir: why };
  if (configFromEnv())    return { kind: 'env',   canWrite: CONFIG_EXPLICIT && dirOk, path: CONFIG, missingDir: why };
  return { kind: 'none', canWrite: dirOk, path: CONFIG, missingDir: why };
}

// Ganz oder gar nicht: erst daneben schreiben, dann umbenennen. rename() ist innerhalb
// desselben Dateisystems unteilbar — es gibt also keinen Moment, in dem an CONFIG eine halbe
// Datei steht.
//
// WARUM DAS HIER ZAEHLT: auf einem Datentraeger ueberlebt diese Datei den Container, und ein
// Deploy beendet den Container jederzeit. Ohne das Umbenennen koennte genau dazwischen ein
// abgeschnittenes JSON zurueckbleiben. Das Passwort waere dann nicht kaputt, sondern WEG —
// readConfig() faellt auf die Variablen zurueck, und es gilt wieder das alte Passwort, ohne
// dass irgendwo stuende warum.
function writeConfig(cfg) {
  const dir = path.dirname(CONFIG);

  // BEWUSST KEIN mkdir. Ein selbst angelegtes Verzeichnis sieht aus wie ein eingehaengter
  // Datentraeger und ist keiner: das Passwort liesse sich speichern, waere nach dem naechsten
  // Deploy weg, und es gaelte wieder das alte — stumm. Genau der Fall, den diese ganze Seite
  // verhindern soll. Fehlt das Verzeichnis, ist das die Antwort, nicht der Anfang einer
  // Rettung. Bei einem Hoster heisst es fast immer: MAMAL_CONFIG gesetzt, Volume nicht
  // eingehaengt (oder an einem anderen Pfad).
  if (!fs.existsSync(dir)) {
    throw new Error('Das Verzeichnis ' + dir + ' gibt es nicht. Bei einem Hoster bedeutet das'
      + ' meistens, dass der Datentraeger nicht (oder woanders) eingehaengt ist. Erst'
      + ' einhaengen, dann MAMAL_CONFIG dorthin zeigen lassen.');
  }

  // Eindeutiger Zwischenname: der Server und ein gleichzeitiges `--set-password` auf derselben
  //   Maschine teilten sich sonst eine Datei, und wessen rename() zuletzt kommt, dessen
  //   Passwort gilt — mit dem anderen Hash im selben Atemzug ueberschrieben.
  const tmp = CONFIG + '.neu.' + process.pid;
  const buf = Buffer.from(JSON.stringify(cfg, null, 2), 'utf8');

  // mode 0600: on Linux/macOS the file is then unreadable for other accounts on the VPS.
  //   Windows ignores the mode — there the folder ACL has to do it. Documented, not pretended.
  //
  // fsync vor dem Umbenennen: rename() ist unteilbar, aber das sagt nur, dass der NAME in
  //   einem Zug wechselt — die Daten dahinter stehen bis dahin bloss im Seitenpuffer. Ein
  //   Deploy ist damit harmlos, ein Absturz des Wirts oder ein hart abgetrennter Datentraeger
  //   kurz nach dem rename nicht: zurueck bliebe ein leerer Eintrag unter dem richtigen Namen.
  const fd = fs.openSync(tmp, 'w', 0o600);
  try {
    let off = 0;
    while (off < buf.length) off += fs.writeSync(fd, buf, off, buf.length - off);
    fs.fsyncSync(fd);
  } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, CONFIG);

  // Und der Verzeichniseintrag selbst. Auf Windows laesst sich ein Verzeichnis nicht oeffnen;
  //   dort ist es auch nicht noetig, weil dieser Pfad nur auf einem Datentraeger zaehlt.
  try {
    const dfd = fs.openSync(dir, 'r');
    try { fs.fsyncSync(dfd); } finally { fs.closeSync(dfd); }
  } catch (e) { /* Windows, oder ein Dateisystem ohne Verzeichnis-fsync */ }
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
// Cockpit aus.
//
// Mit MAMAL_TRUST_PROXY zaehlt deshalb X-Forwarded-For — und zwar der LETZTE Eintrag, nicht
// der erste. Das ist der Unterschied zwischen faelschbar und nicht faelschbar: schickt ein
// Angreifer eine eigene Kopfzeile mit, haengt der vorgelagerte Dienst die Adresse, die er
// wirklich sieht, HINTEN an. Der erste Eintrag ist dann die Erfindung des Angreifers, der
// letzte die Wahrheit. MAMAL_PROXY_HOPS sagt, wie viele vertrauenswuerdige Stationen davor
// liegen, falls es einmal mehr als eine ist.
const TRUST_PROXY_HDR = /^(1|true|yes)$/i.test(process.env.MAMAL_TRUST_PROXY || '');
const PROXY_HOPS = Math.max(1, Number(process.env.MAMAL_PROXY_HOPS || 1) || 1);
function clientKey(req) {
  if (TRUST_PROXY_HDR) {
    const xff = req.headers && req.headers['x-forwarded-for'];
    if (xff) {
      const parts = String(xff).split(',').map(x => x.trim()).filter(Boolean);
      const pick = parts[parts.length - PROXY_HOPS];
      if (pick) return pick.slice(0, 64);
    }
  }
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}

// Selbst mit dem letzten Eintrag bleibt ein Rest: liegen mehrere Stationen davor, landen
// wieder alle im selben Topf. Deshalb ist die Sperre so gebaut, dass sie den Eigentuemer auch
// dann nicht aussperren KANN — siehe allowTryWhileLocked() weiter unten.

// Die Karte darf nicht unbegrenzt wachsen. Ein Angreifer, der je Anfrage eine andere Adresse
// vortaeuscht, legte sonst je Versuch einen Eintrag an, bis der Speicher voll ist.
const FORGET_MS = 15 * 60 * 1000;   // so lange erinnert sich die Bremse an eine Adresse
const MAX_KEYS  = 5000;
function sweepFails() {
  const now = Date.now();
  for (const [k, f] of fails) if (now - (f.seen || 0) > FORGET_MS) fails.delete(k);
  if (fails.size <= MAX_KEYS) return;
  // Immer noch zu viele: die aeltesten zuerst. Map haelt die Einfuegereihenfolge, und ein
  //   neuer Fehlversuch setzt den Eintrag neu (delete + set), also steht vorne das Aelteste.
  const over = fails.size - MAX_KEYS;
  let i = 0;
  for (const k of fails.keys()) { if (i++ >= over) break; fails.delete(k); }
}

function lockedFor(req) {
  const f = fails.get(clientKey(req));
  if (!f || !f.until) return 0;
  const left = f.until - Date.now();
  return left > 0 ? Math.ceil(left / 1000) : 0;
}

function noteFailure(req) {
  const k = clientKey(req);
  const now = Date.now();
  const f = fails.get(k) || { n: 0, until: 0, seen: 0, lastTry: 0 };
  // Nach langer Ruhe wieder bei null anfangen. Ohne das bliebe jemand, der sich vor Stunden
  //   fuenfmal vertippt hat, fuer die ganze Laufzeit des Prozesses bei einem Versuch je
  //   Viertelstunde — die Strafe fuer einen Tippfehler waere unbefristet.
  if (f.seen && now - f.seen > FORGET_MS) { f.n = 0; f.until = 0; }
  f.n++;
  f.seen = now;
  f.lastTry = now;   // ab hier laeuft die 10-Sekunden-Uhr aus allowTryWhileLocked()
  if (f.n >= MAX_TRIES) {
    const steps = f.n - MAX_TRIES;
    f.until = now + Math.min(900, 60 * Math.pow(2, steps)) * 1000;
  }
  fails.delete(k); fails.set(k, f);   // ans Ende: siehe sweepFails()
  if (fails.size > MAX_KEYS) sweepFails();
}

function noteSuccess(req) { fails.delete(clientKey(req)); }

// Darf waehrend einer laufenden Sperre trotzdem geprueft werden?
//
// WARUM ES DAS GIBT: eine Sperre, die ein richtiges Passwort abweist, ist eine Waffe. Wer den
// Schluessel treffen kann — und sei es nur, weil alle Besucher hinter mehreren Stationen im
// selben Topf landen — sperrt damit den Eigentuemer aus seinem eigenen Cockpit aus, fuenfzehn
// Minuten lang, beliebig oft wiederholbar. Deshalb wird auch waehrend der Sperre geprueft,
// nur eben gedrosselt: ein Versuch alle 10 Sekunden. Wer das richtige Passwort hat, wartet
// hoechstens zehn Sekunden; wer raet, kommt von 60-100 ms je Versuch auf 10 s herunter, also
// deutlich schlechter als ohne Sperre.
const RETRY_MS = 10 * 1000;
function allowTryWhileLocked(req) {
  const k = clientKey(req);
  const f = fails.get(k);
  if (!f) return true;
  const now = Date.now();
  if (now - (f.lastTry || 0) < RETRY_MS) return false;
  f.lastTry = now;
  return true;
}

// Letzter Riegel, ueber alle Adressen hinweg: scryptSync kostet 60-100 ms und blockiert dabei
// die Ereignisschleife. Ohne eine globale Grenze legt eine Flut von Anmeldeversuchen das
// ganze Cockpit lahm, auch das Lesen der Kontodaten. 30 Pruefungen je 10 s sind fuer einen
// Menschen unerreichbar viel und fuer eine Maschine nichts.
const BUDGET_MAX = 30, BUDGET_MS = 10 * 1000;
let budgetLeft = BUDGET_MAX, budgetAt = 0;
function hashBudgetOk() {
  const now = Date.now();
  if (now - budgetAt > BUDGET_MS) { budgetAt = now; budgetLeft = BUDGET_MAX; }
  if (budgetLeft <= 0) return false;
  budgetLeft--;
  return true;
}

module.exports = {
  CONFIG, CONFIG_EXPLICIT, SESSION_HOURS,
  isConfigured, setPassword, envForPassword, verifyPassword, matchesHash, readConfig,
  configSource, plainProblem,
  makeSession, validSession, logoutEverywhere,
  parseCookies, lockedFor, noteFailure, noteSuccess, allowTryWhileLocked, hashBudgetOk,
};
