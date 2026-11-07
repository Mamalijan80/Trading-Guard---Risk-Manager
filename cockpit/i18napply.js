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

// ============================================================================
//  Uebersetzung fuer die Nebenseiten (trade.html, day.html, report.html)
// ============================================================================
//  Diese drei Seiten luden i18n.js ueberhaupt nicht. Sie waren deutsch --
//  mit englischen Einsprengseln wie "back to the cockpit", also derselben
//  Mischung wie das Dashboard, nur ohne jede Umschaltmoeglichkeit.
//
//  Warum nicht einfach t() aus dashboard.html kopieren: dreimal derselbe
//  Code heisst dreimal dieselbe Reparatur, und beim dritten Mal vergisst es
//  jemand. Das Dashboard behaelt sein eigenes t(), weil es nach dem Wechsel
//  zusaetzlich alles neu zeichnen muss (prevS=null, tick(), loadAnalytics()).
//  Hier genuegt: Text ersetzen, Seite neu aufbauen lassen.
//
//  Sprachwahl kommt aus localStorage.mamalLang -- derselbe Schluessel, den
//  das Dashboard setzt. Wer dort auf Englisch stellt und dann den Wochen-
//  Report oeffnet, bekommt ihn englisch, ohne noch einmal zu waehlen.
// ============================================================================

var LANG = (function () {
  try { return localStorage.getItem('mamalLang') || 'de'; }
  catch (e) { return 'de'; }        // privates Fenster, gesperrte Site-Daten
})();

// Ein fehlender Schluessel faellt auf Deutsch zurueck, nie auf Leertext --
//   eine Luecke zeigt sich als deutscher Satz, nicht als leere Seite.
//   Gefunden wird sie dafuer nur von `python i18ncheck.py`.
function t(key, params) {
  var T = window.MAMAL_I18N || {};
  var s = (T[LANG] && T[LANG][key]) || (T.de && T.de[key]) || '';
  if (params) for (var k in params) s = s.split('{' + k + '}').join(params[k]);
  return s;
}

// Setzt die Texte des statischen Geruests. Vier Attribute, wie im Dashboard:
//   data-i18n        -> Textknoten (Kindelemente bleiben stehen)
//   data-i18n-ph     -> placeholder
//   data-i18n-title  -> title
//   data-i18n-html   -> innerHTML (nur Werte aus unserer eigenen Tabelle)
function applyI18n() {
  var root = document.documentElement;
  root.lang = LANG;
  root.dir = (LANG === 'fa') ? 'rtl' : 'ltr';

  var els = document.querySelectorAll('[data-i18n]');
  for (var i = 0; i < els.length; i++) {
    var el = els[i], v = t(el.getAttribute('data-i18n'));
    if (!v) continue;
    // textContent loescht Kindelemente -- im Dashboard hat genau das einmal
    //   die Beschriftung des Equity-Verlaufs verschluckt. Also nur Textknoten.
    var hasKids = false, n;
    for (n = el.firstChild; n; n = n.nextSibling) if (n.nodeType === 1) hasKids = true;
    if (!hasKids) { el.textContent = v; continue; }
    var done = false, kids = [];
    for (n = el.firstChild; n; n = n.nextSibling) kids.push(n);
    for (var j = 0; j < kids.length; j++) {
      if (kids[j].nodeType !== 3) continue;
      if (!done) { kids[j].nodeValue = v + ' '; done = true; }
      else kids[j].nodeValue = '';
    }
    if (!done) el.insertBefore(document.createTextNode(v + ' '), el.firstChild);
  }
  var pairs = [['data-i18n-ph', 'placeholder'], ['data-i18n-title', 'title']];
  for (var p = 0; p < pairs.length; p++) {
    var sel = document.querySelectorAll('[' + pairs[p][0] + ']');
    for (var q = 0; q < sel.length; q++) {
      var w = t(sel[q].getAttribute(pairs[p][0]));
      if (w) sel[q][pairs[p][1]] = w;
    }
  }
  var htm = document.querySelectorAll('[data-i18n-html]');
  for (var h = 0; h < htm.length; h++) {
    var x = t(htm[h].getAttribute('data-i18n-html'));
    if (x) htm[h].innerHTML = x;
  }
  if (document.title) {
    var tk = document.documentElement.getAttribute('data-i18n-title-key');
    if (tk) { var tt = t(tk); if (tt) document.title = tt; }
  }
}

// Die Regelnamen zentral, damit trade/day/report nicht je eine eigene
//   Namensliste fuehren. report.html hatte eine -- und die wich schon ab
//   ("Risiko/Trade" gegen "Risiko / Trade").
function ruleName(id) { return t('rules.' + id + '.name') || id; }

document.addEventListener('DOMContentLoaded', applyI18n);
