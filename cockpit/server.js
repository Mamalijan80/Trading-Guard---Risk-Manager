#!/usr/bin/env node
// TradingGuard — Risiko- und Disziplin-Tool fuer MetaTrader 4
// Copyright (C) 2026 Mohammadreza Tavakoli — https://itavakoli.com/
//
// Dieses Programm ist freie Software: Sie koennen es weitergeben und/oder
// veraendern unter den Bedingungen der GNU Affero General Public License,
// Version 3 oder (nach Ihrer Wahl) jeder spaeteren Version.
//
// Die Veroeffentlichung erfolgt in der Hoffnung, dass es nuetzlich ist, aber
// OHNE JEDE GEWAEHRLEISTUNG — sogar ohne die implizite Gewaehrleistung der
// MARKTGAENGIGKEIT oder EIGNUNG FUER EINEN BESTIMMTEN ZWECK. Einzelheiten in
// der GNU Affero General Public License: <https://www.gnu.org/licenses/>.
//
// KEINE ANLAGEBERATUNG. Handel mit Hebelprodukten kann zum Totalverlust
// fuehren. Dieses Werkzeug erzwingt Regeln, es trifft keine Marktentscheidung
// und uebernimmt keine Verantwortung fuer Handelsergebnisse.
// Mamal-Trading Cockpit — lokaler Server (Node, zero-dependency).
// Liest den Live-Zustand + das Journal, das der MT4-EA in MQL4/Files schreibt,
// und serviert daraus ein Live-Dashboard (Kalender, Schwächen, Tagesdetails). DLL-frei.
// v0.38: Multi-Konto — der EA legt pro Login einen Wegweiser (mamal_files_<login>.txt)
// in den Common-Ordner; der Server bietet daraus einen Konto-Umschalter (?acct=...).
'use strict';
const http = require('http');
const fs   = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = Number(process.env.MAMAL_PORT) || 8730;

// §07-fix: Der Default-Pfad war fest auf macOS/Wine verdrahtet (und nutzte $HOME, das es unter Windows so nicht gibt).
// v0.37-fix: Ordner DYNAMISCH ermitteln statt einmalig beim Start (sonst zeigt der Server dauerhaft
// auf einen falschen/leeren Ordner, wenn node vor dem EA startet oder mehrere Terminals laufen).
// v0.38-fix (Verify): kurzlebiger Cache — das Dashboard pollt alle 1,5s und jeder /state-Aufruf
// loeste sonst mehrere Verzeichnis-Scans + Datei-Reads aus (auf OneDrive/AV-gescannten Pfaden teuer).
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
  } catch (e) { return []; }   // Basisordner fehlt -> keine Kandidaten
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
// Aktives Terminal OHNE Konto-Angabe: Override -> frischeste cockpit.json.
// v0.38-fix (Verify): der Legacy-Wegweiser hat KEINE Prioritaet mehr — bei zwei live schreibenden
// Terminals gewann sonst abwechselnd der letzte Schreiber und die Anzeige sprang zwischen den Konten.
// (Portable-Mode bleibt abgedeckt: die Beacon-Ordner stecken in allFilesDirs.)
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
// v0.38: Ordner fuer ein BESTIMMTES Konto: Konto-Wegweiser (verifiziert) -> cockpit.json-Inhalt -> leer.
function dirForAccount(acct) {
  if (!acct) return currentFiles();
  const hit = accountBeacons().find(x => x.account === String(acct));
  if (hit) {
    // v0.38-fix (Verify): Stale-Beacon abfangen — nach einem Login-Wechsel im selben Terminal zeigt der
    // alte Wegweiser auf einen Ordner, dessen cockpit.json inzwischen einem ANDEREN Konto gehoert.
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
// v0.38: Liste aller bekannten Konten (fuer den Umschalter) — frischeste zuerst.
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
  // v0.48-fix: Konten, die NUR noch im Journal stehen (z.B. altes Konto im selben Terminal — die
  // cockpit.json wurde vom neuen Login ueberschrieben), zusaetzlich als "offline" auffuehren.
  // Ohne das erschien kein Umschalter, und die Kennzahlen mischten beide Konten.
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
// v0.48-fix: Das Journal eines Kontos liegt dort, wo seine Zeilen stehen — NICHT zwingend dort, wo eine
// passende cockpit.json liegt. Nach einem Login-Wechsel im selben Terminal gehoert die JSON dem neuen Konto,
// das alte Konto fand sein eigenes Journal dadurch nicht mehr (Historie erschien leer).
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

// §07-fix: 'open' ist macOS-only — unter Windows/Linux schlug der Browser-Start still fehl.
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
    // v0.38-fix (Verify): nie Daten eines FREMDEN Kontos unter angefragtem Label liefern.
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

// Fallback: RuleId aus dem Tag-Text ableiten, wenn die Spalte leer ist.
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

// Journal robust parsen (alte 10-Spalten- und neue 18-Spalten-Zeilen gemischt).
// v0.38: optional nach Konto filtern — falls in einem Terminal frueher ein anderes Login aktiv war,
// bleiben dessen Zeilen aussen vor (Spalte 3 = Kontonummer; alte Kurzzeilen ohne Konto bleiben drin).
// v0.45-fix (Verify): Ergebnis-Cache. Das Dashboard pollt /journal alle 1,5s und /analytics alle 15s —
// vorher wurde die (taeglich wachsende) CSV bei JEDEM Request komplett neu gelesen und geparst, auf einem
// OneDrive-/AV-gescannten Pfad spuerbar teuer. Invalidierung ueber mtime+size der Datei.
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
      if (want && c[2] && c[2].trim() !== want) continue;   // fremdes Konto im selben Terminal-Journal
      // v0.38-fix (Verify): Tag ist Freitext und kann ';' enthalten -> Rest wieder zusammensetzen,
      // sonst verliert die "net X"-Erkennung den Betrag und der Close fehlt im Kalender.
      ev = { time: c[0], event: c[6], symbol: c[7], dir: c[8],
             ticket: (c[14] || '').trim(),   // v0.52: Ticket mitführen — Grundlage der Trade-Akte
             raw: c,                         // v0.62: Rohspalten (Balance, Lot, Entry, SL, TP, Risk%) für die Trade-Akte
             net: parseFloat(c[15]) || 0, ruleId: (c[16] || '').trim(), tag: c.slice(17).join(';') };
    } else {
      if (want) continue;   // v0.38-fix (Verify): Kurzzeilen ohne Kontospalte nicht JEDEM Konto zurechnen
      ev = { time: c[0], event: c[1] || '', symbol: c[2] || '', dir: c[3] || '',
             net: 0, ruleId: '', tag: c[c.length - 1] || '' };
    }
    ev.date = (ev.time || '').slice(0, 10);
    ev.hour = parseInt((ev.time || '').slice(11, 13), 10); if (isNaN(ev.hour)) ev.hour = -1;
    const m = (ev.tag || '').match(/net\s+(-?\d+(?:\.\d+)?)/);   // echtes realisiertes Netto steht (auch) im Tag
    ev.tagNet = m ? parseFloat(m[1]) : null;
    if (!ev.ruleId) ev.ruleId = ruleFromTag(ev.tag);
    out.push(ev);
  }
  parseCache.set(ckey, { ck, rows: out });
  if (parseCache.size > 8) parseCache.delete(parseCache.keys().next().value);   // klein halten (wenige Konten)
  return out;
}

// Session-Bucket aus der Stunde (grob: Nacht / Vormittag / Nachmittag).
function sess(h) { return (h < 0 || h >= 22 || h < 7) ? 'Nacht' : (h < 14 ? 'Vormittag' : 'Nachmittag'); }

// Aggregation: Kalender + Regel-Schwächen + Disziplin + Edge (Symbol×Session) + Block-Stunden-Heatmap.
function analytics(acct) {
  const all = parseAll(acct);
  const cal = {}, rules = {}, edge = {};
  const blockByHour = new Array(24).fill(0);
  const netByHour = new Array(24).fill(0);   // v0.39: wann wird wirklich Geld verdient/verloren
  let netTotal = 0, tradesTotal = 0, blocksTotal = 0, fillsTotal = 0;
  let winSum = 0, winN = 0, lossSum = 0, lossN = 0;   // v0.39: Expectancy/Profit-Factor
  let manualN = 0, manualNet = 0;
  const thirds = [0,0,0];            // v0.52: Einstiege je Kerzendrittel (früh/mittig/spät)
  const byTicketThird = {};          // Ticket -> Drittel, damit der CLOSE das Ergebnis zuordnen kann
  const thirdNet = [0,0,0];          // Netto je Drittel: zahlt sich frühes Einsteigen aus?                     // v0.44: manuelle/fremde Trades separat ausweisen
  for (const e of all) {
    if (!e.date) continue;
    if (!cal[e.date]) cal[e.date] = { date: e.date, net: 0, closes: 0, wins: 0, losses: 0, blocks: 0, fills: 0, rules: 0, manual: 0, thirds: [0,0,0] };
    const d = cal[e.date];
    if (e.event === 'OPEN') {
      d.fills++; fillsTotal++;
      // v0.52: In welchem Drittel der laufenden Kerze wurde eingestiegen? Der EA schreibt "K1/3".."K3/3"
      // in den Tag. Spätes Einsteigen (K3/3) heisst meist: der Bewegung hinterhergelaufen.
      const km = (e.tag || '').match(/\bK([123])\/3\b/);
      if (km) { const i = +km[1] - 1; thirds[i]++; d.thirds[i]++; byTicketThird[e.ticket] = i; }
    }
    // Nur ECHTE Positions-Ergebnisse (Tag "net X"), nicht mechanische Queue-/DELETE-Closes.
    // v0.44: CLOSE_MAN = manueller/fremder Trade (nicht vom Panel) — zaehlt fuer die Konto-Wahrheit
    //   (Netto/Kalender/Statistik) und wird zusaetzlich separat als "manuell" ausgewiesen.
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
    // v0.39: Kennzahlen fuer die Trade-Statistik-Karte
    stats: {
      winN, lossN,
      winRate: (winN + lossN) ? winN / (winN + lossN) : 0,
      avgWin: winN ? winSum / winN : 0,
      avgLoss: lossN ? lossSum / lossN : 0,                       // negativ
      profitFactor: lossSum < 0 ? winSum / -lossSum : (winSum > 0 ? Infinity : 0),
      expectancy: (winN + lossN) ? netTotal / (winN + lossN) : 0,
      netByHour,
      thirds, thirdNet          // v0.52: Einstiegs-Timing innerhalb der Kerze
    },
    range: { first: dates[0] || null, last: dates[dates.length - 1] || null }
  };
}

// Ein Tag im Detail (fuer die Tagesseite).
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
      // v0.38-fix (Verify): uralte Trigger (Klick waehrend der Server tot war) nur aufraeumen,
      // NICHT oeffnen — sonst poppt beim naechsten Windows-Login unerwartet der Browser auf.
      const stale = st && (Date.now() - st.mtimeMs > 120000);
      // NUR oeffnen, wenn die Datei tatsaechlich entfernt wurde (sonst Endlosschleife bei unlink-Fehler).
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

// v0.39: Equity-Zeitreihe — der Server sampelt alle 5s die Equity jedes LIVE schreibenden Kontos
// in cockpit/data/equity_<konto>.csv (epochMs;equity;dayBase). Der EA bleibt unveraendert.
const DATA_DIR = path.join(__dirname, 'data');
try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch (e) { /* existiert */ }
function equityFile(acct) { return path.join(DATA_DIR, 'equity_' + String(acct).replace(/\D/g, '') + '.csv'); }
setInterval(() => {
  for (const a of accountsList()) {
    if (a.ageMs > 15000) continue;              // nur live schreibende Konten samplen
    if (typeof a.equity !== 'number') continue;
    if (!/^\d+$/.test(String(a.account))) continue;   // v0.39-fix (Verify): sonst kollidieren nicht-numerische IDs in equity_.csv (und der Trim greift nie)
    const line = Date.now() + ';' + a.equity + ';' + (a.dayBase != null ? a.dayBase : '') + '\n';
    fs.appendFile(equityFile(a.account), line, () => {});
  }
}, 5000);
// Datei begrenzen: 1x pro Stunde auf die letzten ~20k Punkte (~1 Tag bei 5s) + Rest der Woche kuerzen.
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
// Baut aus den Journalzeilen EINES Tickets eine vollstaendige Akte und formuliert
// daraus eine Zusammenfassung im Klartext — inklusive der Frage, ob das Verschieben
// von SL/TP dem Trade genutzt oder geschadet hat.
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

// v0.65: Altbestand retten. Bis EA v0.64 schrieb der Gruppen-Pfad der Close-Aufloesung die CLOSE-Zeile mit
//   Ticket 0 — das Ergebnis war seinem Einstieg nicht zuzuordnen, die Akte zeigte JEDEN Trade als "offen".
//   Nachtraeglich geht nur noch SCHLIESSEN: gleiches Symbol, gleiche Richtung, aelteste noch offene Position
//   zuerst (FIFO). Das ist eine begruendete Vermutung, keine Tatsache — jede so gewonnene Zahl wird als
//   "zugeordnet" markiert, damit niemand sie fuer ticketgenau haelt. Neue Closes brauchen das nicht mehr.
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
    // NUR bei Eindeutigkeit zuordnen. Der naheliegende FIFO-Ansatz (aeltester Einstieg zuerst) ist
    // nachweislich falsch: eine spaeter eroeffnete Position kann frueher schliessen. Am Kontoauszug
    // des Nutzers gepruft — von neun Zeilen waren zwei vertauscht. Eine falsche Zahl mit "circa"
    // davor ist schlechter als ein ehrliches "unbekannt", weil sie wie ein Messwert aussieht.
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
  // v0.65: Reihenfolge der Wahrheit: (1) CLOSE mit Ticket, (2) CLOSE_HIST aus der MT4-Kontohistorie
  //   (exakt, vom Broker), (3) nur wenn eindeutig: Zuordnung ueber Symbol+Reihenfolge (Vermutung).
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

  // Bewertung der Verschiebungen: der EA schreibt sein Urteil bereits in den Tag.
  let slWorse = 0, slBetter = 0, tpShorter = 0, tpLonger = 0;
  for (const m of moves) {
    const t = m.tag || '';
    if (/Risiko ERHOEHT|Risiko unbegrenzt/i.test(t)) slWorse++;
    else if (/Risiko gesenkt/i.test(t))              slBetter++;
    else if (/Gewinn abgekuerzt|Gewinn abgekürzt/i.test(t)) tpShorter++;
    else if (/Ziel vergroessert|Ziel vergrößert/i.test(t))  tpLonger++;
  }
  // Ursprüngliches Risiko in Kontowährung: Risk% der OPEN-Zeile auf die Balance derselben Zeile.
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
    // v0.65: Bis EA v0.64 schrieb der Gruppen-Pfad der Close-Auflösung die CLOSE-Zeile mit Ticket 0. Ein
    //   Ergebnis liess sich dadurch nie seinem Einstieg zuordnen — die Akte behauptete für JEDEN Trade
    //   „noch offen". Für Einträge aus dieser Zeit ist das aus dem Journal nicht mehr reparierbar; lieber
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
// Liste aller Tickets mit Kurzinfo (fuer die Uebersicht)
function tradeList(acct) {
  const rows = parseAll(acct);
  const map = new Map();
  for (const e of rows) {
    const tk = String(e.ticket || '');
    if (!tk || tk === '0') continue;
    // v0.65: Ein Nachtrag allein macht noch keinen Listeneintrag — sonst tauchten Trades von VOR dem
    //   EA mit der Nachtrags-Uhrzeit ganz oben auf. Nur Tickets, zu denen es einen Einstieg gibt.
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
  const orphan = orphanCloseMap(rows);          // v0.65: Altbestand ohne Ticket in der Close-Zeile
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
  const acct = (u.searchParams.get('acct') || '').replace(/\D/g, '');   // nur Ziffern (Pfad-Injektion ausgeschlossen)
  // serverPort = der TATSAECHLICHE Port; state.port ist nur der EA-Input InpCockpitPort (reine Anzeige)
  if (p === '/state')     return sendJson(res, { ok: true, state: readState(acct), ageMs: stateAgeMs(acct), serverPort: PORT, accounts: accountsList() });
  if (p === '/accounts')  return sendJson(res, accountsList());
  // v0.45-fix (Verify): ERST filtern, DANN kappen. Vorher schnitt slice(-80) auf die Rohdaten, sodass
  // periodische INFO-Zeilen echte Ereignisse aus der Cockpit-Liste verdraengten.
  if (p === '/journal')   return sendJson(res, parseAll(acct)
    .filter(e => ['OPEN','CLOSE','CLOSE_MAN','BLOCKED'].includes(e.event)
              || /PROTECT/i.test(e.event || '')
              || /SPERRE|Cooldown|Ziel|GESPERRT/i.test(e.tag || ''))
    .slice(-120).reverse());
  if (p === '/analytics') return sendJson(res, analytics(acct));
  if (p === '/day')       return sendJson(res, dayDetail(u.searchParams.get('d') || '', acct));
  if (p === '/equity')    return sendJson(res, equitySeries(acct || (accountsList()[0] || {}).account || '', Number(u.searchParams.get('n')) || 2000));   // v0.39
  // v0.39: "Tag beenden" — schreibt das Tighten-Only-Kommando in den Files-Ordner des Kontos.
  // Nur POST; schlimmster Missbrauch waere eine ZUSAETZLICHE Sperre (nie eine Lockerung) — tighten-only by design.
  // Inhalt ist BOM-freies ASCII (latin1) — der EA-Prefix-Check "endday" verlaesst sich darauf.
  if (p === '/cmd/endday') {
    if (req.method !== 'POST') { res.writeHead(405); return res.end('POST only'); }
    // v0.39-fix (Verify): CSRF — ein Cross-Site-Form-POST traegt Host: localhost:8730 und passiert hostAllowed.
    // Origin pruefen: fehlt er (curl/CLI) -> ok; ist er gesetzt, muss er von localhost stammen.
    const orig = req.headers.origin;
    if (orig && !new RegExp('^http://(localhost|127\\.0\\.0\\.1):' + PORT + '$', 'i').test(orig)) {
      res.writeHead(403); return res.end('Cross-Site verboten');
    }
    // v0.39-fix (Verify): Konto verpflichtend — sonst koennte die Sperre bei 2 live schreibenden
    // Terminals im FALSCHEN Konto landen (currentFiles-Fallback kippt zwischen Polls).
    if (!acct) { res.writeHead(400); return res.end('acct erforderlich'); }
    const d = dirForAccount(acct);
    if (!d) { res.writeHead(404); return res.end('Konto nicht gefunden'); }
    try { fs.writeFileSync(path.join(d, 'mamal_cmd.txt'), 'endday ' + Date.now(), 'latin1'); }
    catch (e) { res.writeHead(500); return res.end('Schreiben fehlgeschlagen'); }
    return sendJson(res, { ok: true });
  }
  // v0.62: Screenshot ausliefern. Dateiname streng gepruft (nur Mamal_<ticket>_<tag>_<zeit>.png),
  // damit ueber diesen Weg NIE ein anderer Pfad gelesen werden kann.
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
  // v0.62: Trade-Akte — alles zu EINEM Ticket: Einstieg, SL/TP-Verschiebungen, Ergebnis,
  // Screenshots und eine automatisch formulierte Zusammenfassung.
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
  // v0.38: MAMAL_QUIETSTART=1 (Autostart) -> beim Hochfahren KEIN Browser-Popup;
  // der Cockpit-Klick im EA (Trigger-Datei) oeffnet ihn weiterhin.
  const quiet = /^(1|true|yes)$/i.test(process.env.MAMAL_QUIETSTART || '');
  if (!quiet) openBrowser();
});
