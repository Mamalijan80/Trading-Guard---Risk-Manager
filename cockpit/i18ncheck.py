#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prueft die Uebersetzungstabelle gegen den Code, der sie benutzt.

WARUM DIESES WERKZEUG EXISTIERT
-------------------------------
Eine Luecke in der Uebersetzung ist im Browser NICHT zu sehen. `t()` faellt
bei einem fehlenden Schluessel auf Deutsch zurueck und erst dann auf Leertext.
Das ist gut fuer den Nutzer -- die Oberflaeche steht nie leer -- heisst aber:
ein vergessener englischer oder persischer Eintrag sieht aus wie Absicht. Nur
ein Vergleich gegen die Tabelle findet ihn.

Dazu kommen Schluessel, die ZUSAMMENGEBAUT werden ('rules.'+id+'.name',
'insight.'+id). Die findet keine Textsuche im Code, also stehen die Listen
unten ausdruecklich hier.

Geprueft wird:
  1. Jeder t('...')- und data-i18n-Aufruf hat einen Eintrag in der Tabelle.
  2. Jede Sprache kennt jeden Schluessel, den Deutsch kennt.
  3. Die zusammengebauten Schluessel sind vollstaendig.
  4. Listen, die der Code zerlegt (Monate, Wochentage), haben die richtige
     Anzahl Glieder -- sonst steht im Kalender ein leerer Monatsname.
  5. Kein Eintrag enthaelt einen t(...)-Aufruf. Das ist die Dauerschleife aus
     v0.61: die Tabelle ist der Endpunkt, ein Massenlauf darf sie nie
     einschliessen, sonst ruft t() sich selbst bis zum Stapelueberlauf --
     ohne Compilerfehler, ohne Warnung.

    python i18ncheck.py

Rueckgabewert 0 = sauber, 1 = mindestens ein Fund.
"""
import io
import json
import os
import re
import subprocess
import sys

# Windows-Konsole ist cp1252 und wirft bei jedem Mittelpunkt einen Fehler.
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HERE = os.path.dirname(os.path.abspath(__file__))

# Seiten, die die Tabelle benutzen. trade/day/report laden sie noch nicht --
#   sie stehen hier, damit der Tag auffaellt, an dem sie es tun.
PAGES = ['dashboard.html', 'trade.html', 'day.html', 'report.html',
         'login.html', 'passwort.html']

# ---- Schluessel, die der Code ZUSAMMENBAUT (keine Textsuche findet sie) ----
RULE_IDS = ['R1', 'R2', 'R3', 'R4', 'R4b', 'R5', 'R6', 'R7', 'R8', 'R9',
            'R12', 'R13', 'R14', 'R15', 'R16', 'R17', 'R18', 'R19', 'R22', 'R25']
BUILT = ['rules.%s.name' % i for i in RULE_IDS] \
      + ['rules.%s.sub' % i for i in RULE_IDS]

# Die elf Karten unter "Wo stehe ich" holen ihre Erklaerung ueber
#   'rule.'+id+'.desc'. Fehlt eine, steht die Karte ohne Erklaerung da --
#   im Browser sieht das nach Absicht aus.
CARD_IDS = ['R1', 'R2', 'R3', 'R4', 'R4b', 'R5', 'R6', 'R7', 'R12', 'R13', 'R18']
BUILT += ['rule.%s.desc' % i for i in CARD_IDS]

# Die Bildsorten der Trade-Akte holt kindLabel() ueber 'trade.kind.'+kind.
#   Die Namen kommen aus den Screenshot-Dateien, die der EA schreibt.
SHOT_KINDS = ['open', 'close', 'slmove', 'tpmove']
BUILT += ['trade.kind.%s' % k for k in SHOT_KINDS]

# insight.<id> gibt es absichtlich nur fuer einen Teil der Regeln: wo keine
#   Einsicht hinterlegt ist, zeigt die Seite zu Recht nichts. Geprueft wird
#   darum nur, dass eine vorhandene deutsche Einsicht auch en/fa hat.
OPTIONAL_PREFIX = ['insight.']

# Listen, die der Code zerlegt: Schluessel -> (Trennzeichen, erwartete Anzahl)
LISTS = {
    'calendar.months': (',', 12),
    'calendar.dow': (',', 7),
}

ATTR = re.compile(r"""data-i18n(?:-ph|-title|-html)?\s*=\s*(['"])([^'"]+)\1""")
RECURSION = re.compile(r"""\bt\(\s*['"`]""")

# Ein t('...')-Aufruf. Die Gruppe hinter dem Literal entscheidet, ob der
#   Schluessel VOLLSTAENDIG ist: folgt ein +, wird er zusammengebaut
#   (t('rules.'+id+'.name')) und steht als Praefix da, nicht als Schluessel.
#   Ohne diese Unterscheidung meldete der Pruefer ewig t('rules.') und
#   t('insight.') als fehlend -- zwei Geister, die niemand beheben kann.
CALL = re.compile(r"""(?:^|[^A-Za-z0-9_$.])t\(\s*(['"`])([^'"`]+)\1\s*(\+?)""")

# `t` als Variable oder als Parameter -- beides verdeckt die Uebersetzer-
#   funktion in seinem Gueltigkeitsbereich.
SHADOW_VAR = re.compile(r'\b(?:const|let|var)\s+t\s*=')
SHADOW_ARG = re.compile(r'(?:function\s+[A-Za-z0-9_$]*\s*\(\s*t\s*[,)]'   # function f(t)
                        r'|\(\s*t\s*\)\s*=>'                              # (t) =>
                        r'|(?<![A-Za-z0-9_$.])t\s*=>)')                   # t =>


def load_table():
    """Liest window.MAMAL_I18N ueber node aus -- i18n.js ist JavaScript."""
    script = (
        "global.window={};"
        "require(process.argv[1]);"
        "process.stdout.write(JSON.stringify(global.window.MAMAL_I18N));"
    )
    p = subprocess.run(['node', '-e', script, os.path.join(HERE, 'i18n.js')],
                       capture_output=True, text=True, encoding='utf-8')
    if p.returncode != 0:
        print('i18n.js laesst sich nicht laden:')
        print(p.stderr.strip())
        sys.exit(1)
    return json.loads(p.stdout)


def main():
    T = load_table()
    langs = sorted(T.keys())
    assert 'de' in T, 'Deutsch ist die Rueckfallsprache und fehlt'
    de_keys = set(T['de'])
    print('Tabelle: %s · %d Schluessel in Deutsch'
          % ('/'.join(langs), len(de_keys)))

    findings = []

    # ---- 1. Aufrufe ohne Eintrag ------------------------------------------
    used = {}
    prefixes = set()
    for name in PAGES:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            continue
        text = io.open(path, encoding='utf-8', newline='').read()
        for i, line in enumerate(text.split('\n'), 1):
            for m in CALL.finditer(line):
                if m.group(3) == '+':        # zusammengebaut, siehe BUILT
                    prefixes.add(m.group(2))
                    continue
                used.setdefault(m.group(2), []).append('%s:%d' % (name, i))
            for m in ATTR.finditer(line):
                used.setdefault(m.group(2), []).append('%s:%d' % (name, i))
    if prefixes:
        print('zusammengebaute Schluessel im Code: %s (gegen die Listen unten geprueft)'
              % ', '.join(sorted(p + '…' for p in prefixes)))
    void = sorted(k for k in used if k not in de_keys)
    for k in void:
        findings.append("Aufruf ohne Eintrag: t('%s')  <- %s"
                        % (k, ', '.join(used[k])))
    print('%d Aufrufe im Code, %d ohne Eintrag' % (len(used), len(void)))

    # ---- 2. zusammengebaute Schluessel -------------------------------------
    missing_built = [k for k in BUILT if k not in de_keys]
    for k in missing_built:
        findings.append('zusammengebauter Schluessel fehlt in Deutsch: ' + k)
    print('%d zusammengebaute Schluessel, %d fehlen'
          % (len(BUILT), len(missing_built)))

    # ---- 3. Luecken je Sprache --------------------------------------------
    for lang in langs:
        if lang == 'de':
            continue
        gaps = sorted(k for k in de_keys if k not in T[lang])
        if gaps:
            findings.append('%s fehlen %d Schluessel: %s'
                            % (lang, len(gaps), ', '.join(gaps[:12])))
        # Eintraege, die wortgleich mit dem Deutschen sind, sind VERDAECHTIG,
        #   aber kein Fehler: "Symbol" heisst auf Englisch auch Symbol.
        same = [k for k in de_keys
                if k in T[lang] and T[lang][k] == T['de'][k]
                and isinstance(T['de'][k], str) and len(T['de'][k]) > 14]
        print('%s: %d Luecken · %d Eintraege wortgleich mit de (nur ein Hinweis)'
              % (lang, len(gaps), len(same)))
        for k in sorted(same):
            print('     wortgleich: %s' % k)

    # ---- 4. Listenlaengen --------------------------------------------------
    for key, (sep, want) in LISTS.items():
        for lang in langs:
            val = T[lang].get(key)
            if val is None:
                findings.append('%s/%s fehlt' % (lang, key))
                continue
            have = len([x for x in val.split(sep)])
            if have != want:
                findings.append('%s/%s hat %d Glieder, erwartet %d'
                                % (lang, key, have, want))

    # ---- 4b. Verdeckung von t() -------------------------------------------
    #   Heisst irgendwo eine Variable oder ein Parameter `t`, ist die
    #   Uebersetzerfunktion in diesem Gueltigkeitsbereich unerreichbar und
    #   jeder Aufruf darin stirbt als "t is not a function" -- syntaktisch
    #   einwandfrei, Seite halb leer. Genau so blieb die Trade-Liste leer:
    #   dort hiess der PARAMETER von netUnknown() t, weshalb die Suche nach
    #   `const t=` ihn nicht fand. Beide Formen werden jetzt gesucht.
    for name in PAGES:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            continue
        text = io.open(path, encoding='utf-8', newline='').read()
        for i, line in enumerate(text.split('\n'), 1):
            if line.lstrip().startswith('//'):
                continue
            for rx, what in ((SHADOW_VAR, 'Variable'), (SHADOW_ARG, 'Parameter')):
                if rx.search(line):
                    findings.append('%s:%d verdeckt t() als %s: %s'
                                    % (name, i, what, line.strip()[:70]))

    # ---- 5. Die Dauerschleife aus v0.61 -----------------------------------
    for lang in langs:
        for k, v in T[lang].items():
            if isinstance(v, str) and RECURSION.search(v):
                findings.append('REKURSION %s/%s -- die Tabelle ist der '
                                'Endpunkt, hier steht ein Aufruf: %s'
                                % (lang, k, v[:70]))

    # ---- 6. optionale Praefixe: wenn de es hat, muessen en/fa es auch haben -
    for pref in OPTIONAL_PREFIX:
        have_de = [k for k in de_keys if k.startswith(pref)]
        for lang in langs:
            if lang == 'de':
                continue
            gaps = [k for k in have_de if k not in T[lang]]
            for k in gaps:
                findings.append('%s fehlt %s (Deutsch hat es)' % (lang, k))
        print('%s*: %d in Deutsch hinterlegt' % (pref, len(have_de)))

    print()
    if findings:
        print('%d Fund%s:' % (len(findings), '' if len(findings) == 1 else 'e'))
        for f in findings:
            print('  - ' + f)
        return 1
    print('Tabelle und Code passen zusammen.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
