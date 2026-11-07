#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prueft jeden Inline-<script>-Block der Cockpit-Seiten mit `node --check`.

WARUM DIESES WERKZEUG EXISTIERT (v0.68, stiller Totalausfall)
-------------------------------------------------------------
Bei einer Uebersetzung geriet in `dashboard.html` ein englisches `you're` in
einen **einfach gequoteten** JS-String. Der Apostroph beendete den String, `re`
war danach ein freier Bezeichner -> SyntaxError -> das **gesamte Inline-Skript**
wurde nicht geparst. Die Seite rendert dann nur ihr statisches HTML und bleibt
auf "Warte auf MetaTrader..." stehen. Das sieht exakt so aus wie "der EA
liefert nichts", obwohl EA und Server einwandfrei arbeiten.

Nach `grep` auf bekannte Kontraktionen zu suchen findet nur, woran man denkt.
Dieses Skript findet jeden Syntaxfehler, auch den, an den niemand gedacht hat,
und rechnet die Fehlerzeile auf die **HTML-Zeile** zurueck.

NACH JEDER UEBERSETZUNG ODER TEXTAENDERUNG AN DEN COCKPIT-DATEIEN LAUFEN LASSEN.

    python jscheck.py              # alle Seiten im eigenen Ordner
    python jscheck.py dashboard.html

Rueckgabewert 0 = alles sauber, 1 = mindestens ein Block ist kaputt.
"""
import io
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = ['dashboard.html', 'trade.html', 'day.html', 'report.html',
           'login.html', 'passwort.html']

# <script> ohne src= (externe Dateien pruefen wir direkt, nicht eingebettet)
SCRIPT = re.compile(r'<script\b([^>]*)>(.*?)</script\s*>', re.S | re.I)
HAS_SRC = re.compile(r'\bsrc\s*=', re.I)
# type="module" muss node anders pruefen; alles andere ist klassisches Skript
IS_MODULE = re.compile(r'type\s*=\s*[\'"]module[\'"]', re.I)


def check_source(src, as_module):
    """Gibt None zurueck, wenn node den Quelltext akzeptiert, sonst die Meldung."""
    suffix = '.mjs' if as_module else '.js'
    fd, path = tempfile.mkstemp(suffix=suffix, prefix='jscheck_')
    try:
        with io.open(fd, 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(src)
        p = subprocess.run(['node', '--check', path],
                           capture_output=True, text=True, encoding='utf-8',
                           errors='replace')
        if p.returncode == 0:
            return None
        return ((p.stderr or '') + (p.stdout or '')).replace(path, '<block>')
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def line_of(text, index):
    """1-basierte Zeilennummer des Zeichens an Position `index`."""
    return text.count('\n', 0, index) + 1


def check_file(name):
    path = name if os.path.isabs(name) else os.path.join(HERE, name)
    if not os.path.exists(path):
        print('  ?? %s - nicht gefunden' % name)
        return 0, 0
    text = io.open(path, encoding='utf-8', newline='').read()

    # Eine externe .js-Datei pruefen wir als Ganzes.
    if path.endswith('.js'):
        err = check_source(text, False)
        if err:
            print('  !! %s' % name)
            print(indent(err))
            return 1, 1
        print('  ok %s (ganze Datei)' % name)
        return 0, 1

    bad = total = 0
    for m in SCRIPT.finditer(text):
        attrs, body = m.group(1), m.group(2)
        if HAS_SRC.search(attrs):
            continue                      # laedt eine Datei, kein Inline-Code
        if not body.strip():
            continue
        total += 1
        start_line = line_of(text, m.start(2))
        err = check_source(body, bool(IS_MODULE.search(attrs)))
        if err is None:
            continue
        bad += 1
        print('  !! %s - Inline-Block ab HTML-Zeile %d' % (name, start_line))
        # node zaehlt ab Blockanfang; auf die HTML-Zeile zurueckrechnen
        def shift(mo):
            return '<html-zeile %d>' % (start_line + int(mo.group(1)) - 1)
        print(indent(re.sub(r'<block>:(\d+)', shift, err)))
    if not bad:
        print('  ok %s (%d Inline-Block%s)'
              % (name, total, '' if total == 1 else 'e'))
    return bad, total


def indent(s):
    return '\n'.join('       ' + ln for ln in s.rstrip().split('\n'))


def main(argv):
    names = argv[1:] or DEFAULT
    print('jscheck - Inline-Skripte gegen `node --check`')
    bad = blocks = 0
    for n in names:
        b, t = check_file(n)
        bad += b
        blocks += t
    print()
    if bad:
        print('FEHLER: %d von %d Block/Bloecken kaputt.' % (bad, blocks))
        print('Eine Seite mit SyntaxError rendert nur ihr statisches HTML und')
        print('bleibt auf "Warte auf MetaTrader..." stehen - sie sieht dann aus')
        print('wie ein EA-Problem. Erst das hier beheben.')
        return 1
    print('Alle %d Block/Bloecke sauber.' % blocks)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
