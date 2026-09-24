#!/usr/bin/env node
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
// NOT INVESTMENT ADVICE. Trading leveraged products can lead to total
// loss. This tool enforces rules, it makes no market decision
// and takes no responsibility for trading results.
// Mamal-Trading Cockpit — lokaler Server (Node, zero-dependency).
// Reads the live state + the journal that the MT4 EA writes into MQL4/Files,
// and serves a live dashboard from it (calendar, weaknesses, day details). DLL-free.
// v0.38: multi-account — the EA drops one signpost per login (mamal_files_<login>.txt)
// into the Common folder; from these the server offers an account switcher (?acct=...).
'use strict';
const http = require('http');
const fs   = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = Number(process.env.MAMAL_PORT) || 8730;

// §07-fix: the default path was hard-wired to macOS/Wine (and used $HOME, which does not exist that way on Windows).
// v0.37-fix: determine the folder DYNAMICALLY instead of once at startup (otherwise the server points
// permanently at a wrong/empty folder when node starts before the EA or several terminals are running).
// v0.38-fix (Verify): short-lived cache — the dashboard polls every 1.5s and every /state call
// otherwise triggered several directory scans + file reads (expensive on OneDrive/AV-scanned paths).
function memo(fn, ttlMs) {
  let t = 0, v = null;
  return () => { const now = Date.now(); if (now - t < ttlMs && v !== null) return v; v = fn(); t = now; return v; };
}
const winAllFilesDirs = memo(() => {
  const base = path.join(process.env.APPDATA || '', 'MetaQuotes', 'Terminal');
  try {
    return fs.readdirSync(base)
      .map(h => path.join(base, h, 'MQL4', 'Files'))
      .filter(p => fs.existsSync(p));
  } catch (e) { return []; }   // base folder missing -> no candidates
}, 1500);
function commonFilesDir() {
  return path.join(process.env.APPDATA || '', 'MetaQuotes', 'Terminal', 'Common', 'Files');
}
// v0.37: Legacy-Wegweiser (ein Terminal). v0.38: zusaetzlich pro Konto mamal_files_<login>.txt.
function beaconFilesDir() {
  try {
    const p = fs.readFileSync(path.join(commonFilesDir(), 'mamal_files.txt'), 'latin1').trim();
    if (p && fs.existsSync(p)) return p;
  } catch (e) { /* kein Wegweiser -> ignorieren */ }
  return '';
}
const accountBeacons = memo(() => {
  const out = [];
  try {
    for (const f of fs.readdirSync(commonFilesDir())) {
      const m = f.match(/^mamal_files_(\d+)\.txt$/);
      if (!m) continue;
      try {
        const p = fs.readFileSync(path.join(commonFilesDir(), f), 'latin1').trim();
        if (p && fs.existsSync(p)) out.push({ account: m[1], dir: p });
      } catch (e) { /* einzelner kaputter Wegweiser -> ueberspringen */ }
    }
  } catch (e) { /* Common fehlt -> leer */ }
  return out;
}, 1500);
function allFilesDirs() {
  if (process.env.MAMAL_FILES) return [process.env.MAMAL_FILES];
  if (process.platform === 'win32') {
    const dirs = winAllFilesDirs();
    for (const b of accountBeacons()) if (!dirs.includes(b.dir)) dirs.unshift(b.dir);
    const b = beaconFilesDir();
    if (b && !dirs.includes(b)) dirs.unshift(b);   // echter Live-Ordner zuerst
    return dirs;
  }
  const d = path.join(
    process.env.HOME || '',
    'Library/Application Support/net.metaquotes.wine.metatrader4',
    'drive_c/Program Files (x86)/MetaTrader 4/MQL4/Files'
  );
  return fs.existsSync(d) ? [d] : [];
}
// Active terminal WITHOUT an account given: override -> freshest cockpit.json.
// v0.38-fix (Verify): the legacy signpost has NO priority any more — with two terminals writing live,
// the last writer used to win in turn and the display jumped back and forth between the accounts.
// (Portable mode stays covered: the beacon folders sit in allFilesDirs.)
function currentFiles() {
  if (process.env.MAMAL_FILES) return process.env.MAMAL_FILES;
  const dirs = allFilesDirs();
  if (!dirs.length) return '';
  let best = dirs[0], bestM = -1;
  for (const d of dirs) {
    let m = 0;
    try { m = fs.statSync(path.join(d, 'mamal_cockpit.json')).mtimeMs; } catch (e) { m = 0; }
    if (m > bestM) { bestM = m; best = d; }
  }
  return best;
}
// v0.38: folder for a SPECIFIC account: account signpost (verified) -> cockpit.json content -> empty.
function dirForAccount(acct) {
  if (!acct) return currentFiles();
  const hit = accountBeacons().find(x => x.account === String(acct));
  if (hit) {
    // v0.38-fix (Verify): catch a stale beacon — after a login change in the same terminal the
    // old signpost points at a folder whose cockpit.json meanwhile belongs to a DIFFERENT account.
    try {
      const s = JSON.parse(fs.readFileSync(path.join(hit.dir, 'mamal_cockpit.json'), 'latin1'));
      if (String(s.account) === String(acct)) return hit.dir;
    } catch (e) { /* JSON fehlt/kaputt -> unten weitersuchen */ }
  }
  for (const d of allFilesDirs()) {
    try {
      const s = JSON.parse(fs.readFileSync(path.join(d, 'mamal_cockpit.json'), 'latin1'));
      if (String(s.account) === String(acct)) return d;
    } catch (e) { /* kein/kaputtes JSON -> weiter */ }
  }
  return '';
}
// v0.38: list of all known accounts (for the switcher) — freshest first.
function accountsList() {
  const seen = new Map();
  const add = (dir) => {
    try {
      const f = path.join(dir, 'mamal_cockpit.json');
      const s = JSON.parse(fs.readFileSync(f, 'latin1'));
      const acct = String(s.account || '');
      if (!acct) return;
      const age = Math.round(Date.now() - fs.statSync(f).mtimeMs);
      const prev = seen.get(acct);
      if (!prev || age < prev.ageMs)
        seen.set(acct, { account: acct, ageMs: age, equity: s.equity, ccy: s.ccy || '', symbol: s.symbol || '', status: s.status || '', profile: s.profile || '',
                         // v0.39: Felder fuers Multi-Konto-Grid (Puffer/Ampel pro Karte)
                         statusColor: s.statusColor || '', dailyDD: s.dailyDD, dailyLimit: s.dailyLimit, totalDD: s.totalDD, maxLoss: s.maxLoss,
                         dayBase: s.dayBase, initBal: s.initBal, v: s.v || '' });
    } catch (e) { /* Ordner ohne cockpit.json -> ignorieren */ }
  };
  for (const b of accountBeacons()) add(b.dir);
  for (const d of allFilesDirs()) add(d);
  // v0.48-fix: accounts that only exist in the journal any more (e.g. the old account in the same terminal — the
  // cockpit.json was overwritten by the new login) are additionally listed as "offline".
  // Without that no switcher appeared, and the metrics mixed both accounts.
  try {
    for (const d of allFilesDirs()) {
      const jf = path.join(d, 'MamalTrading_Journal.csv');
      let raw = '';
      try { raw = fs.readFileSync(jf, 'latin1'); } catch (e) { continue; }
      for (const line of raw.split(/\r?\n/)) {
        const c = line.split(';');
        if (c.length < 17) continue;
        const acct = (c[2] || '').trim();
        if (!/^\d+$/.test(acct) || seen.has(acct)) continue;
        seen.set(acct, { account: acct, ageMs: 9e9, equity: null, ccy: '', symbol: '',
                         status: 'nur Historie', statusColor: '', profile: '', v: '', historic: true });
      }
    }
  } catch (e) { /* Historie ist Komfort, kein Muss */ }
  return [...seen.values()].sort((a, b) => a.ageMs - b.ageMs);
}
const stateFile   = (acct) => { const d = dirForAccount(acct); return d ? path.join(d, 'mamal_cockpit.json') : ''; };
// v0.48-fix: an account's journal lies where its lines are — NOT necessarily where a
// matching cockpit.json lies. After a login change in the same terminal the JSON belongs to the new account,
// so the old account no longer found its own journal (history appeared empty).
const journalFile = (acct) => {
  const d = dirForAccount(acct);
  if (d) return path.join(d, 'MamalTrading_Journal.csv');
  if (!acct) return '';
  const needle = ';' + String(acct) + ';';
  for (const dir of allFilesDirs()) {
    const jf = path.join(dir, 'MamalTrading_Journal.csv');
    try { if (fs.readFileSync(jf, 'latin1').indexOf(needle) >= 0) return jf; } catch (e) { /* weiter */ }
  }
  return '';
};

// §07-fix: 'open' is macOS-only — on Windows/Linux the browser launch failed silently.
function openBrowser() {
  if (process.env.MAMAL_NOOPEN) return;
  const url = `http://localhost:${PORT}`;
  const cmd = process.platform === 'win32' ? `start "" "${url}"`
            : process.platform === 'darwin' ? `open "${url}"`
            : `xdg-open "${url}"`;
  exec(cmd, { windowsHide: true }, err => {
    if (err) console.log(`Cockpit: Browser konnte nicht geoeffnet werden (${err.message}) — bitte ${url} manuell aufrufen.`);
  });
}
function readState(acct) {
  const f = stateFile(acct); if (!f) return null;
  try {
    const s = JSON.parse(fs.readFileSync(f, 'latin1'));
    // v0.38-fix (Verify): never deliver data of a FOREIGN account under the requested label.
    if (acct && String(s.account) !== String(acct)) return null;
    return s;
  }
  catch (e) { return null; }
}
function stateAgeMs(acct) {
  const f = stateFile(acct); if (!f) return null;
  try { return Date.now() - fs.statSync(f).mtimeMs; }
  catch (e) { return null; }
}

// Fallback: derive RuleId from the tag text when the column is empty.
function ruleFromTag(tag) {
  const t = (tag || '').trim();
  if (!t) return '';
  if (/^queue\s/i.test(t)) { const m = t.match(/\bR(\d{1,2})\b/i); return m ? 'R' + m[1] : ''; }
  if (/gesperrt/i.test(t)) return 'R4';
  if (/cooldown/i.test(t)) return 'R5';
  if (/wochensperre|wochen-verlustlimit/i.test(t)) return 'R18';
  if (/tagesziel/i.test(t)) return 'R13';
  if (/revenge/i.test(t)) return 'R25';
  if (/session|news/i.test(t)) return 'R16';
  return '';
}

// Parse the journal robustly (old 10-column and new 18-column lines mixed).
// v0.38: optionally filter by account — if another login was active earlier in a terminal,
// its lines stay out (column 3 = account number; old short lines without an account stay in).
// v0.45-fix (Verify): result cache. The dashboard polls /journal every 1.5s and /analytics every 15s —
// before, the (daily growing) CSV was completely re-read and re-parsed on EVERY request, noticeably
// expensive on a OneDrive-/AV-scanned path. Invalidation via mtime+size of the file.
const parseCache = new Map();
function parseAll(acct) {
  let raw;
  const jf = journalFile(acct); if (!jf) return [];
  let ck = '';
  try { const st = fs.statSync(jf); ck = st.mtimeMs + '|' + st.size; } catch (e) { return []; }
  const ckey = (acct || '') + '@' + jf;
  const hit = parseCache.get(ckey);
  if (hit && hit.ck === ck) return hit.rows;
  try { raw = fs.readFileSync(jf, 'latin1'); } catch (e) { return []; }
  const out = [];
  const want = acct ? String(acct) : '';
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.indexOf(';') < 0) continue;
    const c = line.split(';');
    if (c[0] === 'ServerTime') continue;
    let ev;
    if (c.length >= 17) {
      if (want && c[2] && c[2].trim() !== want) continue;   // foreign account in the same terminal journal
      // v0.38-fix (Verify): tag is free text and may contain ';' -> reassemble the rest,
      // otherwise the "net X" detection loses the amount and the close is missing from the calendar.
      ev = { time: c[0], event: c[6], symbol: c[7], dir: c[8],
             ticket: (c[14] || '').trim(),   // v0.52: carry the ticket along — basis of the trade file
             raw: c,                         // v0.62: raw columns (Balance, Lot, Entry, SL, TP, Risk%) for the trade file
             net: parseFloat(c[15]) || 0, ruleId: (c[16] || '').trim(), tag: c.slice(17).join(';') };
    } else {
      if (want) continue;   // v0.38-fix (Verify): do not attribute short lines without an account column to EVERY account
      ev = { time: c[0], event: c[1] || '', symbol: c[2] || '', dir: c[3] || '',
             net: 0, ruleId: '', tag: c[c.length - 1] || '' };
    }
    ev.date = (ev.time || '').slice(0, 10);
    ev.hour = parseInt((ev.time || '').slice(11, 13), 10); if (isNaN(ev.hour)) ev.hour = -1;
    const m = (ev.tag || '').match(/net\s+(-?\d+(?:\.\d+)?)/);   // the real realized net is (also) in the tag
    ev.tagNet = m ? parseFloat(m[1]) : null;
    if (!ev.ruleId) ev.ruleId = ruleFromTag(ev.tag);
    out.push(ev);
  }
  parseCache.set(ckey, { ck, rows: out });
  if (parseCache.size > 8) parseCache.delete(parseCache.keys().next().value);   // klein halten (wenige Konten)
  return out;
}

// Session bucket from the hour (roughly: night / morning / afternoon).
function sess(h) { return (h < 0 || h >= 22 || h < 7) ? 'Nacht' : (h < 14 ? 'Vormittag' : 'Nachmittag'); }

// Aggregation: calendar + rule weaknesses + discipline + edge (symbol×session) + blocked-hours heatmap.
function analytics(acct) {
  const all = parseAll(acct);
  const cal = {}, rules = {}, edge = {};
  const blockByHour = new Array(24).fill(0);
  const netByHour = new Array(24).fill(0);   // v0.39: when money is really earned/lost
  let netTotal = 0, tradesTotal = 0, blocksTotal = 0, fillsTotal = 0;
  let winSum = 0, winN = 0, lossSum = 0, lossN = 0;   // v0.39: Expectancy/Profit-Factor
  let manualN = 0, manualNet = 0;
  const thirds = [0,0,0];            // v0.52: entries per candle third (early/middle/late)
  const byTicketThird = {};          // ticket -> third, so that the CLOSE can attribute the result
  const thirdNet = [0,0,0];          // Net per third: does entering early pay off?                     // v0.44: report manual/foreign trades separately
  for (const e of all) {
    if (!e.date) continue;
    if (!cal[e.date]) cal[e.date] = { date: e.date, net: 0, closes: 0, wins: 0, losses: 0, blocks: 0, fills: 0, rules: 0, manual: 0, thirds: [0,0,0] };
    const d = cal[e.date];
    if (e.event === 'OPEN') {
      d.fills++; fillsTotal++;
      // v0.52: in which third of the running candle was the entry? The EA writes "K1/3".."K3/3"
      // into the tag. Entering late (K3/3) usually means: chasing the move.
      const km = (e.tag || '').match(/\bK([123])\/3\b/);
      if (km) { const i = +km[1] - 1; thirds[i]++; d.thirds[i]++; byTicketThird[e.ticket] = i; }
    }
    // Only REAL position results (tag "net X"), not mechanical queue/DELETE closes.
    // v0.44: CLOSE_MAN = manual/foreign trade (not from the panel) — counts toward the account truth
    //   (net/calendar/statistics) and is additionally reported separately as "manuell" (manual).
    const isMan = (e.event === 'CLOSE_MAN');
    if ((e.event === 'CLOSE' && e.tagNet !== null) || isMan) {
      const nt = isMan ? (e.net || 0) : e.tagNet;
      if (isMan) { d.manual++; manualN++; manualNet += nt; }
      d.net += nt; d.closes++; tradesTotal++; netTotal += nt;
      { const th = byTicketThird[e.ticket]; if (th !== undefined) thirdNet[th] += nt; }   // v0.52
      if (nt > 0) { d.wins++; winSum += nt; winN++; } else if (nt < 0) { d.losses++; lossSum += nt; lossN++; }
      if (e.hour >= 0) netByHour[e.hour] += nt;
      const sym = e.symbol || '?', s = sess(e.hour);
      if (!edge[sym]) edge[sym] = { symbol: sym, total: { net: 0, n: 0, w: 0, l: 0 }, sess: {} };
      if (!edge[sym].sess[s]) edge[sym].sess[s] = { net: 0, n: 0, w: 0, l: 0 };
      for (const b of [edge[sym].total, edge[sym].sess[s]]) { b.net += nt; b.n++; if (nt > 0) b.w++; else if (nt < 0) b.l++; }
    }
    if (e.event === 'BLOCKED') { d.blocks++; blocksTotal++; if (e.hour >= 0) blockByHour[e.hour]++; }
    if (e.ruleId && (e.event === 'BLOCKED' || e.event === 'CLOSE')) {
      d.rules++;
      if (!rules[e.ruleId]) rules[e.ruleId] = { id: e.ruleId, count: 0, blocked: 0, closed: 0, lastDate: e.date };
      const r = rules[e.ruleId];
      r.count++; r.lastDate = e.date;
      if (e.event === 'BLOCKED') r.blocked++; else r.closed++;
    }
  }
  const dates = Object.keys(cal).sort();
  const cells = [];
  for (const sym in edge) for (const s in edge[sym].sess) cells.push({ sym, s, ...edge[sym].sess[s] });
  cells.sort((a, b) => b.net - a.net);
  const best = cells[0] || null, worst = cells.length > 1 ? cells[cells.length - 1] : null;
  const attempts = fillsTotal + blocksTotal;
  return {
    calendar: cal,
    rules: Object.values(rules).sort((a, b) => b.count - a.count),
    edge: Object.values(edge).sort((a, b) => b.total.net - a.total.net),
    blockByHour,
    discipline: { fills: fillsTotal, blocks: blocksTotal, attempts, ratio: attempts ? fillsTotal / attempts : 0 },
    verdict: { best, worst },
    totals: { days: dates.length, netTotal, tradesTotal, blocksTotal, fillsTotal, manualN, manualNet },   // v0.44: manuelle Trades getrennt sichtbar
    // v0.39: metrics for the trade statistics card
    stats: {
      winN, lossN,
      winRate: (winN + lossN) ? winN / (winN + lossN) : 0,
      avgWin: winN ? winSum / winN : 0,
      avgLoss: lossN ? lossSum / lossN : 0,                       // negativ
      profitFactor: lossSum < 0 ? winSum / -lossSum : (winSum > 0 ? Infinity : 0),
      expectancy: (winN + lossN) ? netTotal / (winN + lossN) : 0,
      netByHour,
      thirds, thirdNet          // v0.52: entry timing within the candle
    },
    range: { first: dates[0] || null, last: dates[dates.length - 1] || null }
  };
}

// One day in detail (for the day page).
function dayDetail(d, acct) {
  const all = parseAll(acct).filter(e => e.date === d);
  let net = 0, closes = 0, wins = 0, losses = 0, blocks = 0, manual = 0;
  const rules = {};
  for (const e of all) {
    const man = (e.event === 'CLOSE_MAN');   // v0.44: manueller/fremder Trade
    if ((e.event === 'CLOSE' && e.tagNet !== null) || man) {
      const nt = man ? (e.net || 0) : e.tagNet;
      if (man) manual++;
      net += nt; closes++; if (nt > 0) wins++; else if (nt < 0) losses++;
    }
    if (e.event === 'BLOCKED') blocks++;
    if (e.ruleId && (e.event === 'BLOCKED' || e.event === 'CLOSE')) rules[e.ruleId] = (rules[e.ruleId] || 0) + 1;
  }
  return {
    date: d, net, closes, wins, losses, blocks, manual,
    rules: Object.entries(rules).map(([id, count]) => ({ id, count })).sort((a, b) => b.count - a.count),
    events: all.reverse()
  };
}

// Trigger-Datei in ALLEN Terminal-Ordnern beobachten -> Browser oeffnen + Datei loeschen.
let lastOpen = 0;
setInterval(() => {
  for (const dir of allFilesDirs()) {
    const f = path.join(dir, 'mamal_cockpit_open.txt');
    fs.stat(f, (err, st) => {
      if (err) return;
      // v0.38-fix (Verify): only clean up ancient triggers (a click while the server was dead),
      // do NOT open — otherwise the browser pops up unexpectedly at the next Windows login.
      const stale = st && (Date.now() - st.mtimeMs > 120000);
      // Open ONLY if the file was actually removed (otherwise an endless loop on an unlink error).
      fs.unlink(f, (uerr) => {
        if (uerr || stale) return;
        const now = Date.now();
        if (now - lastOpen < 1500) return;    // Doppel-Events desselben Klicks entprellen
        lastOpen = now;
        openBrowser();
      });
    });
  }
}, 600);

// v0.39: equity time series — the server samples the equity of every LIVE writing account every 5s
// into cockpit/data/equity_<account>.csv (epochMs;equity;dayBase). The EA stays unchanged.
const DATA_DIR = path.join(__dirname, 'data');
try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch (e) { /* existiert */ }
function equityFile(acct) { return path.join(DATA_DIR, 'equity_' + String(acct).replace(/\D/g, '') + '.csv'); }
setInterval(() => {
  for (const a of accountsList()) {
    if (a.ageMs > 15000) continue;              // sample only accounts writing live
    if (typeof a.equity !== 'number') continue;
    if (!/^\d+$/.test(String(a.account))) continue;   // v0.39-fix (Verify): otherwise non-numeric IDs collide in equity_.csv (and the trim never kicks in)
    const line = Date.now() + ';' + a.equity + ';' + (a.dayBase != null ? a.dayBase : '') + '\n';
    fs.appendFile(equityFile(a.account), line, () => {});
  }
}, 5000);
// Cap the file: 1x per hour down to the last ~20k points (~1 day at 5s) + trim the rest of the week.
setInterval(() => {
  try {
    for (const f of fs.readdirSync(DATA_DIR)) {
      const p = path.join(DATA_DIR, f);
      if (!/^equity_\d+\.csv$/.test(f)) continue;
      if (fs.statSync(p).size < 2 * 1024 * 1024) continue;
      const lines = fs.readFileSync(p, 'latin1').split('\n');
      fs.writeFileSync(p, lines.slice(-20000).join('\n'), 'latin1');
    }
  } catch (e) { /* Trim ist Komfort, kein Muss */ }
}, 3600 * 1000);
function equitySeries(acct, n) {
  try {
    const raw = fs.readFileSync(equityFile(acct), 'latin1');
    const lines = raw.split('\n').filter(Boolean);
    return lines.slice(-(n || 2000)).map(l => {
      const c = l.split(';');
      return { t: Number(c[0]), eq: Number(c[1]), base: c[2] ? Number(c[2]) : null };
    }).filter(x => x.t > 0 && isFinite(x.eq));
  } catch (e) { return []; }
}

// ===== v0.62: Trade-Akte =====================================================
// Builds a complete file out of the journal lines of ONE ticket and formulates
// a plain-text summary from it — including the question whether moving
// SL/TP helped or hurt the trade.
function shotsFor(ticket, acct) {
  const dir = dirForAccount(acct) || currentFiles();
  if (!dir) return [];
  let files = [];
  try { files = fs.readdirSync(dir); } catch (e) { return []; }
  const re = new RegExp('^Mamal_' + ticket + '_([a-z0-9]+)_(\\d+)\\.png$', 'i');
  return files.map(f => { const m = f.match(re); return m ? { file: f, kind: m[1], ts: +m[2] } : null; })
              .filter(Boolean).sort((a, b) => a.ts - b.ts);
}
function num(x) { const v = parseFloat(String(x).replace(',', '.')); return isFinite(v) ? v : 0; }

// v0.65: rescue legacy data. Up to EA v0.64 the group path of the close resolution wrote the CLOSE line with
//   ticket 0 — the result could not be attributed to its entry, the file showed EVERY trade as "offen" (open).
//   After the fact only CLOSING is still possible: same symbol, same direction, oldest still open position
//   first (FIFO). That is a reasoned guess, not a fact — every number obtained that way is marked
//   as "zugeordnet" (attributed), so that nobody takes it for ticket-accurate. New closes no longer need this.
function orphanCloseMap(rows) {
  const opens = [], map = new Map();
  for (const e of rows) {
    if (e.event === 'OPEN' && e.ticket && String(e.ticket) !== '0') {
      opens.push({ ticket: String(e.ticket), symbol: e.symbol, dir: e.dir, used: false });
      continue;
    }
    if (e.event !== 'CLOSE' || e.tagNet === null) continue;
    const tk = String(e.ticket || '');
    if (tk && tk !== '0') {                       // ab v0.65: Ticket steht dran, nichts zu raten
      const o = opens.find(x => !x.used && x.ticket === tk); if (o) o.used = true;
      continue;
    }
    const dir  = (e.dir && e.dir !== '-') ? e.dir : null;   // Schutz-Closes tragen "-"
    const cand = opens.filter(x => !x.used && x.symbol === e.symbol && (!dir || x.dir === dir));
    // Attribute ONLY when unambiguous. The obvious FIFO approach (oldest entry first) is
    // demonstrably wrong: a position opened later can close earlier. Checked against the user's
    // account statement — of nine lines, two were swapped. A wrong number with "circa"
    // in front of it is worse than an honest "unknown", because it looks like a measured value.
    if (cand.length !== 1) { for (const c of cand) c.ambiguous = true; continue; }
    cand[0].used = true;
    map.set(cand[0].ticket, e);
  }
  return map;
}

function tradeDossier(ticket, acct) {
  if (!ticket) return { ok: false, error: 'kein Ticket' };
  const rows = parseAll(acct).filter(e => String(e.ticket || '') === String(ticket));
  if (!rows.length) return { ok: false, error: 'kein Eintrag zu Ticket ' + ticket };
  const open  = rows.find(e => e.event === 'OPEN') || null;
  let   close = rows.find(e => e.event === 'CLOSE' && e.tagNet !== null) || null;
  let   inferred = false, backfilled = false;
  // v0.65: order of truth: (1) CLOSE with ticket, (2) CLOSE_HIST from the MT4 account history
  //   (exact, from the broker), (3) only when unambiguous: attribution via symbol+order (a guess).
  if (!close) {
    const hist = rows.find(e => e.event === 'CLOSE_HIST' && e.tagNet !== null);
    if (hist) { close = hist; backfilled = true; }
  }
  if (!close) {
    const m = orphanCloseMap(parseAll(acct));
    if (m.has(String(ticket))) { close = m.get(String(ticket)); inferred = true; }
  }
  const moves = rows.filter(e => e.event === 'SLTP_MOVE');
  const panel = rows.filter(e => e.event === 'PANEL_CLOSE');
  const be    = rows.filter(e => e.event === 'BREAKEVEN');

  // Assessment of the moves: the EA already writes its verdict into the tag.
  let slWorse = 0, slBetter = 0, tpShorter = 0, tpLonger = 0;
  for (const m of moves) {
    const t = m.tag || '';
    if (/Risiko ERHOEHT|Risiko unbegrenzt/i.test(t)) slWorse++;
    else if (/Risiko gesenkt/i.test(t))              slBetter++;
    else if (/Gewinn abgekuerzt|Gewinn abgekürzt/i.test(t)) tpShorter++;
    else if (/Ziel vergroessert|Ziel vergrößert/i.test(t))  tpLonger++;
  }
  // Original risk in account currency: Risk% of the OPEN line applied to the balance of that same line.
  const plannedRisk = open ? num(open.raw && open.raw[3]) * num(open.raw && open.raw[13]) / 100 : 0;
  const net = close ? close.tagNet : null;
  const third = open ? ((open.tag || '').match(/\bK([123])\/3\b/) || [])[1] : null;

  // ---- Zusammenfassung formulieren -----------------------------------------
  const S = [];
  if (open) {
    S.push(`${open.dir} ${open.symbol} mit ${num(open.raw[9]).toFixed(2)} Lot um ${(open.time||'').slice(11)} eröffnet` +
           (plannedRisk ? ` — geplantes Risiko ${plannedRisk.toFixed(2)}.` : '.'));
    if (third) S.push(third === '1' ? 'Einstieg im ersten Kerzendrittel — früh, nicht hinterhergelaufen.'
                    : third === '2' ? 'Einstieg im mittleren Kerzendrittel.'
                    : 'Einstieg im letzten Kerzendrittel — spät; oft eine Reaktion auf eine schon gelaufene Bewegung.');
  }
  if (!moves.length) S.push('SL und TP blieben unverändert — der Plan wurde eingehalten.');
  else {
    S.push(`SL/TP wurde ${moves.length}× verschoben (${slBetter}× risikosenkend, ${slWorse}× risikoerhöhend` +
           `${tpShorter ? `, ${tpShorter}× Ziel verkürzt` : ''}${tpLonger ? `, ${tpLonger}× Ziel erweitert` : ''}).`);
    if (slWorse) S.push('Achtung: Der Stop wurde vom Einstieg weg bewegt — das erhöht den Verlust über den Plan hinaus. Das ist das teuerste wiederkehrende Muster im Trading.');
    if (slBetter && !slWorse) S.push('Der Stop wurde nur enger gezogen — sauberes Risikomanagement.');
    if (tpShorter) S.push('Das Ziel wurde näher geholt: Gewinne werden dadurch systematisch kleiner als die Verluste.');
  }
  if (be.length) S.push('Position wurde per RISK-FREE auf Break-Even abgesichert.');
  if (panel.length) S.push(`${panel.length}× per Panel-Knopf geschlossen (${panel.map(x => (x.tag||'').split(' ')[0]).join(', ')}).`);
  if (net !== null) {
    S.push(net >= 0 ? `Ergebnis: +${net.toFixed(2)} — im Plus.` : `Ergebnis: ${net.toFixed(2)}.`);
    if (backfilled) S.push('Dieses Ergebnis stammt aus der MT4-Kontohistorie (Nachtrag) — Ticket und Betrag exakt wie beim Broker.');
    if (inferred) S.push('Hinweis: Dieses Ergebnis wurde über Symbol und Reihenfolge zugeordnet, nicht über die Ticket-Nummer — bis EA v0.64 fehlte sie in der Close-Zeile. Bei mehreren gleichzeitigen Positionen im selben Symbol kann die Zuordnung danebenliegen; maßgeblich bleibt der Kontoauszug.');
    if (net < 0 && plannedRisk > 0 && Math.abs(net) > plannedRisk * 1.15)
      S.push(`Der Verlust liegt ${(Math.abs(net) / plannedRisk).toFixed(1)}× über dem geplanten Risiko — Ursache prüfen (verschobener Stop, Slippage oder Gap).`);
    if (net < 0 && plannedRisk > 0 && Math.abs(net) <= plannedRisk * 1.15)
      S.push('Der Verlust blieb im geplanten Rahmen — genau so soll ein Stop wirken.');
  } else {
    // v0.65: up to EA v0.64 the group path of the close resolution wrote the CLOSE line with ticket 0. A
    //   result could therefore never be attributed to its entry — the file claimed for EVERY trade
    //   "noch offen" (still open). For entries from that period this can no longer be repaired from the journal; better
    //   ehrlich benennen als weiter „offen" behaupten.
    const openTs = open && open.time ? Date.parse(open.time.replace(/\./g, '-').replace(' ', 'T')) : NaN;
    const stale  = Number.isFinite(openTs) && (Date.now() - openTs > 6 * 3600 * 1000);
    S.push(stale
      ? 'Ergebnis nicht zuordenbar: Der Einstieg liegt länger zurück, und bis EA v0.64 wurde in der Close-Zeile kein Ticket mitgeschrieben. Der echte Ausgang steht im Kontoauszug des Brokers. Ab v0.65 wird das Ergebnis wieder verbucht.'
      : 'Position ist noch offen — das Ergebnis wird verbucht, sobald sie geschlossen ist.');
  }

  return { ok: true, ticket, open, close, moves, panel, be,
           stats: { moves: moves.length, slWorse, slBetter, tpShorter, tpLonger, plannedRisk, net, third, inferred, backfilled },
           shots: shotsFor(ticket, acct), summary: S };
}
// List of all tickets with short info (for the overview)
function tradeList(acct) {
  const rows = parseAll(acct);
  const map = new Map();
  for (const e of rows) {
    const tk = String(e.ticket || '');
    if (!tk || tk === '0') continue;
    // v0.65: an addendum alone does not yet make a list entry — otherwise trades from BEFORE the
    //   EA showed up right at the top with the addendum's time. Only tickets that have an entry.
    if (!map.has(tk) && e.event === 'CLOSE_HIST') continue;
    if (!map.has(tk)) map.set(tk, { ticket: tk, symbol: e.symbol, dir: e.dir, time: e.time, net: null, moves: 0, shots: 0, third: null });
    const t = map.get(tk);
    if (e.event === 'OPEN') { t.time = e.time; t.symbol = e.symbol; t.dir = e.dir;
                              const m = (e.tag||'').match(/\bK([123])\/3\b/); if (m) t.third = +m[1]; }
    if (e.event === 'SLTP_MOVE') t.moves++;
    if (e.event === 'CLOSE' && e.tagNet !== null) { t.net = e.tagNet; t.inferred = false; t.backfilled = false; }
    else if (e.event === 'CLOSE_HIST' && e.tagNet !== null && t.net === null) { t.net = e.tagNet; t.backfilled = true; }
  }
  const out = [...map.values()];
  const orphan = orphanCloseMap(rows);          // v0.65: legacy data without a ticket in the close line
  for (const t of out) {
    if (t.net === null && orphan.has(t.ticket)) { t.net = orphan.get(t.ticket).tagNet; t.inferred = true; }
    if (t.backfilled) t.inferred = false;   // exakt schlaegt Vermutung
    t.shots = shotsFor(t.ticket, acct).length;
  }
  return out.sort((a, b) => String(b.time).localeCompare(String(a.time))).slice(0, 200);
}

function sendJson(res, obj) {
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}
// Host-Header pruefen (DNS-Rebinding-Schutz).
const HOST_OK = new RegExp('^(localhost|127\\.0\\.0\\.1)(:' + PORT + ')?$', 'i');
function hostAllowed(req) {
  const h = req.headers.host;
  if (!h) return false;
  return HOST_OK.test(h.trim());
}
function sendFile(res, name) {
  fs.readFile(path.join(__dirname, name), (err, buf) => {
    if (err) { res.writeHead(404); return res.end(name + ' nicht gefunden'); }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(buf);
  });
}

const server = http.createServer((req, res) => {
  let u;
  try { u = new URL(req.url, 'http://x'); } catch (e) { res.writeHead(400); return res.end('bad url'); }
  if (!hostAllowed(req)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('Verboten: nur localhost / 127.0.0.1 erlaubt.');
  }
  const p = u.pathname;
  const acct = (u.searchParams.get('acct') || '').replace(/\D/g, '');   // digits only (path injection ruled out)
  // serverPort = the ACTUAL port; state.port is only the EA input InpCockpitPort (display only)
  if (p === '/state')     return sendJson(res, { ok: true, state: readState(acct), ageMs: stateAgeMs(acct), serverPort: PORT, accounts: accountsList() });
  if (p === '/accounts')  return sendJson(res, accountsList());
  // v0.45-fix (Verify): filter FIRST, cap AFTERWARDS. Before, slice(-80) cut into the raw data, so that
  // periodic INFO lines pushed real events out of the cockpit list.
  if (p === '/journal')   return sendJson(res, parseAll(acct)
    .filter(e => ['OPEN','CLOSE','CLOSE_MAN','BLOCKED'].includes(e.event)
              || /PROTECT/i.test(e.event || '')
              || /SPERRE|Cooldown|Ziel|GESPERRT/i.test(e.tag || ''))
    .slice(-120).reverse());
  if (p === '/analytics') return sendJson(res, analytics(acct));
  if (p === '/day')       return sendJson(res, dayDetail(u.searchParams.get('d') || '', acct));
  if (p === '/equity')    return sendJson(res, equitySeries(acct || (accountsList()[0] || {}).account || '', Number(u.searchParams.get('n')) || 2000));   // v0.39
  // v0.39: "Tag beenden" (end day) — writes the tighten-only command into the account's Files folder.
  // POST only; the worst abuse would be an ADDITIONAL lock (never a loosening) — tighten-only by design.
  // Content is BOM-free ASCII (latin1) — the EA prefix check "endday" relies on that.
  if (p === '/cmd/endday') {
    if (req.method !== 'POST') { res.writeHead(405); return res.end('POST only'); }
    // v0.39-fix (Verify): CSRF — a cross-site form POST carries Host: localhost:8730 and passes hostAllowed.
    // Check Origin: if absent (curl/CLI) -> ok; if set, it must come from localhost.
    const orig = req.headers.origin;
    if (orig && !new RegExp('^http://(localhost|127\\.0\\.0\\.1):' + PORT + '$', 'i').test(orig)) {
      res.writeHead(403); return res.end('Cross-Site verboten');
    }
    // v0.39-fix (Verify): account mandatory — otherwise the lock could land in the WRONG account with 2 live
    // writing terminals (the currentFiles fallback flips between polls).
    if (!acct) { res.writeHead(400); return res.end('acct erforderlich'); }
    const d = dirForAccount(acct);
    if (!d) { res.writeHead(404); return res.end('Konto nicht gefunden'); }
    try { fs.writeFileSync(path.join(d, 'mamal_cmd.txt'), 'endday ' + Date.now(), 'latin1'); }
    catch (e) { res.writeHead(500); return res.end('Schreiben fehlgeschlagen'); }
    return sendJson(res, { ok: true });
  }
  // v0.62: serve a screenshot. File name strictly checked (only Mamal_<ticket>_<day>_<time>.png),
  // so that NO other path can ever be read this way.
  if (p.startsWith('/shot/')) {
    const name = decodeURIComponent(p.slice(6));
    if (!/^Mamal_\d+_[a-z0-9]+_\d+\.png$/i.test(name)) { res.writeHead(400); return res.end('ungueltiger Name'); }
    const dir = dirForAccount(acct) || currentFiles();
    if (!dir) { res.writeHead(404); return res.end('kein Ordner'); }
    return fs.readFile(path.join(dir, name), (err, buf) => {
      if (err) { res.writeHead(404); return res.end('Bild fehlt'); }
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'max-age=86400' });
      res.end(buf);
    });
  }
  // v0.62: trade file — everything about ONE ticket: entry, SL/TP moves, result,
  // screenshots and an automatically formulated summary.
  if (p === '/trade') return sendJson(res, tradeDossier((u.searchParams.get('ticket') || '').replace(/\D/g, ''), acct));
  if (p === '/trades') return sendJson(res, tradeList(acct));
  if (p === '/trade.html') return sendFile(res, 'trade.html');
  if (p === '/i18n.js') {   // v0.53: Uebersetzungstabelle (de/en/fa)
    return fs.readFile(path.join(__dirname, 'i18n.js'), (err, buf) => {
      if (err) { res.writeHead(404); return res.end('i18n.js fehlt'); }
      res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(buf);
    });
  }
  if (p === '/day.html')    return sendFile(res, 'day.html');
  if (p === '/report.html') return sendFile(res, 'report.html');   // v0.39: druckbarer Wochen-Report
  if (p === '/favicon.ico') { res.writeHead(204); return res.end(); }
  if (p === '/' || p === '/index.html') return sendFile(res, 'dashboard.html');
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  return res.end('404 — nicht gefunden');
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`\n  Port ${PORT} ist belegt. Laeuft das Cockpit schon? Sonst: MAMAL_PORT=8731 node server.js\n`);
    process.exit(1);
  }
  throw e;
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('\n  Mamal-Trading Cockpit laeuft');
  console.log('  → http://localhost:' + PORT);
  const dirs = allFilesDirs();
  console.log('  Ordner (' + dirs.length + '): ' + (currentFiles() || '— keiner gefunden'));
  const accts = accountsList();
  if (accts.length) console.log('  Konten: ' + accts.map(a => a.account).join(', '));
  if (stateAgeMs('') === null) {
    console.log('  Hinweis: noch keine mamal_cockpit.json — MT4 + EA (InpCockpit=true) noetig.');
  }
  console.log('');
  // v0.38: MAMAL_QUIETSTART=1 (autostart) -> NO browser popup at boot;
  // the cockpit click in the EA (trigger file) still opens it.
  const quiet = /^(1|true|yes)$/i.test(process.env.MAMAL_QUIETSTART || '');
  if (!quiet) openBrowser();
});
