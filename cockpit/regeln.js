// TradingGuard — risk and discipline tool for MetaTrader 4
// Copyright (C) 2026 Mohammadreza Tavakoli — https://itavakoli.com/
//
// This program is free software under the GNU Affero General Public License,
// version 3 or later. NOT INVESTMENT ADVICE.

// ============================================================================
//  Der Regeltext in einfacher Sprache — de / en / fa
// ============================================================================
//  WARUM EINE EIGENE DATEI und nicht i18n.js:
//    Das hier ist INHALT, keine Bedienoberflaeche, und nur regeln.html braucht
//    es. In i18n.js gelegt, wuerde es mit jedem Dashboard-Aufruf mitgeladen.
//
//  WAS HIER NICHT STEHT: Zahlen. Keine Prozentsaetze, keine Euro-Betraege, kein
//    "an" oder "aus". Die holt die Seite aus /state, also aus dem laufenden EA.
//    Grund: docs/RULES-PLAIN.md rechnet durchgehend mit einem 20.000-Euro-Konto
//    und nennt darum "50 Euro Risiko pro Trade" — auf einem 10.000-Euro-Konto
//    ist jede dieser Zahlen falsch. Und ein aufgeschriebener Wert veraltet in
//    dem Moment, in dem jemand eine Eingabe im EA aendert.
//
//  WOHER DIE BESCHREIBUNGEN STAMMEN: aus dem QUELLTEXT, geprueft Regel fuer
//    Regel. Dabei kamen vier Fehler meines ersten Entwurfs heraus:
//      - R10 und R11 waren vertauscht (R10 ist "Kein Aushebeln", R11 das
//        Tagebuch). docs/RULES-PLAIN.md zaehlt ab seiner Regel 5 durchgehend um
//        eins verschoben, weil es die zwei Stufen des Max-Verlusts zusammenzieht.
//      - R8 wuerde nicht den Einstieg pruefen, sondern einen LAUFENDEN Trade
//        schliessen, dessen Ziel zu nah am Stop liegt.
//      - R9 ist keine doppelte Bestaetigung, sondern eine BEDENKZEIT.
//      - R17: bei 0,25 % je Trade passen drei solche Trades hinein, nicht zwei.
//    docs/RULES-PLAIN.md kennt R23 ausserdem ueberhaupt nicht — dabei ist das
//    die Regel, die man am haeufigsten spuert, weil sie jede Woche neu blockiert.
//
//  DER WICHTIGSTE UNTERSCHIED, der ueberall durchgehalten wird:
//    "nimmt keinen neuen Trade an"  !=  "schliesst offene Positionen".
//    Verwechselt man das, klingt eine Einstiegsbremse wie eine Notbremse.
//    Schliessen tun: Tagesverlust, Max-Verlust (harte Stufe), Wochenlimit,
//    Verlustserie-Schluss, Tageshoch-Rueckfall, Stop-Pflicht, Nur-Panel.
//    Nur blockieren tun: Idee, Tagesbudget, Pause, Tagesziel, Gesamtrisiko
//    (beim Eroeffnen), Korrelation, Handelszeit, Wochenrisiko.
// ============================================================================

// Reihenfolge: erst was bei JEDEM Trade greift, dann die Bremsen, dann Serien
//   und Pausen, dann Streuung, dann der Rahmen, zuletzt das Abgeschaltete.
//   Nicht nach Nummer — die Nummern sind historisch gewachsen.
var REGEL_FOLGE = [
  'R1', 'R2', 'R7', 'R22',
  'R3', 'R4', 'R4b', 'R18',
  'R5', 'R6', 'R13',
  'R12', 'R17', 'R16', 'R23',
  'R10', 'R11',
  'R8', 'R9', 'R14', 'R15', 'R19', 'R25',
];

// Vorgabe-Zustand. Der LIVE gemeldete `disabled`-Stand des EA schlaegt das
//   jederzeit — diese Liste gilt nur, solange keine Verbindung steht.
var REGEL_ZUSTAND = {
  R8: 'aus', R9: 'aus', R14: 'aus', R15: 'aus', R19: 'aus', R25: 'aus',
  R16: 'optional',
};

// Die Zeile mit dem aktuellen Wert. Leer = diese Regel hat keine Zahl.
//   r(), eur() und decSep() kommen aus regeln.html bzw. i18napply.js und sind
//   zur AUFRUFZEIT da, auch wenn diese Datei frueher geladen wird.
function _pz(v) { return v == null ? '—' : String(v).replace('.', decSep()) + ' %'; }
function _wert(pct) { var e = eur(pct); return _pz(pct) + (e ? ' · ' + e : ''); }

var REGEL_WERT = {
  R1:  function (s) { return s ? r('wert.jeTrade').replace('{x}', _wert(s.riskPerTrade)) : ''; },
  R2:  function (s) { return s ? r('wert.jeIdee').replace('{x}', _wert(s.ideaCap)) : ''; },
  R3:  function (s) { return s ? r('wert.jeTag').replace('{x}', _wert(s.dayBudget)) : ''; },
  R4:  function (s) { return s ? r('wert.grenze').replace('{x}', _wert(s.dailyLimit)) : ''; },
  R4b: function (s) { return s ? r('wert.zweiStufen')
         .replace('{a}', _wert(s.maxLossWarn)).replace('{b}', _wert(s.maxLoss)) : ''; },
  R18: function (s) { return s ? r('wert.grenze').replace('{x}', _wert(s.weekLimit)) : ''; },
  R5:  function (s) { return s ? r('wert.cooldown')
         .replace('{n}', s.cooldownAfter).replace('{min}', s.cooldownMin) : ''; },
  R6:  function (s) { return s ? r('wert.nachN').replace('{n}', s.lockAfter) : ''; },
  R13: function (s) { return s ? r('wert.ziel').replace('{x}', _wert(s.targetPct)) : ''; },
  R12: function (s) { return s ? r('wert.zusammen').replace('{x}', _wert(s.heatCap)) : ''; },
};

window.MAMAL_REGELN = {

 // ==========================================================================
 //  DEUTSCH — die Quellfassung. Englisch und Persisch sind daraus uebersetzt.
 // ==========================================================================
 "de": {
  "regeln.pageTitle": "Mamal-Trading · Die Regeln",
  "regeln.h1": "Die Regeln in einfacher Sprache",
  "regeln.lead": "Kein Fachwissen nötig. Stell dir das Werkzeug als ruhigen, strengen Trainer neben dir vor: Es sagt dir nie, WAS du handeln sollst — das bleibt deine Entscheidung. Es passt nur auf, dass du dich nicht selbst ruinierst.",
  "regeln.h2.alle": "Jede Regel einzeln",
  "regeln.h2.grenzen": "Was das Werkzeug nicht kann",

  "konfig.zeile": "So ist dein Werkzeug gerade eingestellt — Konto {konto}, Profil {profil}. Diese Zahlen kommen aus dem laufenden Expert Advisor, sie sind nicht hier aufgeschrieben.",
  "konfig.offline": "Gerade keine Verbindung zum Cockpit — die Regeltexte unten gelten trotzdem, nur die aktuellen Zahlen fehlen.",
  "konfig.risiko": "Risiko je Trade",
  "konfig.tag": "Tagesverlust-Grenze",
  "konfig.max": "Max-Verlust",
  "konfig.woche": "Wochenlimit",
  "konfig.ziel": "Tagesziel",
  "konfig.gesamt": "Gesamtrisiko",

  "zustand.an": "aktiv",
  "zustand.aus": "abgeschaltet",
  "zustand.optional": "optional",

  "wert.rund": "rund {x}",
  "wert.jeTrade": "Je Trade eingestellt: {x}",
  "wert.jeIdee": "Je Idee eingestellt: {x}",
  "wert.jeTag": "Am Tag eingestellt: {x}",
  "wert.grenze": "Eingestellt: {x}",
  "wert.zweiStufen": "Frühwarnung ab {a} · harte Sperre ab {b}",
  "wert.cooldown": "Nach {n} Verlusten in Folge · {min} Minuten Pause",
  "wert.nachN": "Nach {n} Verlusten in Folge",
  "wert.ziel": "Tagesziel: {x}",
  "wert.zusammen": "Für alle offenen Trades zusammen: {x}",

  "grenzen.lead": "Ehrlich gesagt — das hier kann es nicht:",
  "grenzen.anzahl": "6",
  "grenzen.1": "Es reagiert <b>sehr schnell, aber nicht in null Sekunden</b> (etwa eine halbe Sekunde). Was in dieser Zeit passieren kann, fangen die Tages- und die Gesamtbremse ab.",
  "grenzen.2": "Es kann einen Trade, den du am Panel vorbei öffnest, nicht <b>verhindern</b> — nur <b>rückgängig machen</b>. Für die Sekunde dazwischen warst du wirklich im Markt: Spread bezahlt, der Kurs kann sich bewegt haben. Die Regel schützt dein Regelwerk, nicht deinen Cent.",
  "grenzen.3": "Die wirklich harte Grenze ist die deiner Prop-Firma, und die sitzt auf deren Server. Dieses Werkzeug sorgt dafür, dass du dort gar nicht erst ankommst — es ersetzt sie aber nicht.",
  "grenzen.4": "Es schützt nur, solange <b>MetaTrader läuft und AutoTrading an ist</b>. Ist AutoTrading aus, ist der Schutz aus — darum die orange Warnung „SCHUTZ AUS“.",
  "grenzen.5": "Es zählt nur, was es selbst <b>betreut</b>. Trades eines anderen Handelsprogramms erkennt es an deren Kennung und lässt sie in Ruhe.",
  "grenzen.6": "Es ist <b>keine Gelddruckmaschine</b>. Es findet keine Trades für dich. Es ist dein Disziplin-Trainer, mehr nicht.",

  // ---- Bei jedem Trade ---------------------------------------------------
  "r.R1.name": "Automatische Positionsgröße",
  "r.R1.was": "Du legst fest, wo dein Stop stehen soll — das Werkzeug rechnet daraus selbst aus, wie groß die Position sein darf, damit du höchstens den eingestellten Anteil deines Kontos verlierst. Du musst nie selbst rechnen.",
  "r.R1.bsp": "Stop 20 Punkte entfernt → kleinere Position. Nur 10 Punkte entfernt → doppelt so große. <b>In beiden Fällen riskierst du gleich viel.</b> Die Order geht nie größer heraus als gerechnet; läge die Größe unter dem Mindestwert deines Brokers, kommt gar keine Order zustande. Ziehst du den Stop später <b>weiter weg</b>, steigt dein Risiko — dann schließt das Werkzeug genau diese Position. Näher heran ist immer erlaubt.",

  "r.R2.name": "Eine Idee, ein Budget",
  "r.R2.was": "Mehrere Positionen im selben Markt in dieselbe Richtung zählen als <b>eine Idee</b>. Ihr Risiko darf zusammen die Ideen-Obergrenze nicht überschreiten.",
  "r.R2.bsp": "Gold kaufen, noch einmal Gold kaufen → zusammen voll. Der nächste Kauf wird <b>nicht gesetzt</b>, mit Hinweis im Chart und Eintrag im Tagebuch. Gold <b>verkaufen</b> oder ein anderer Markt geht weiter. Offene Positionen rührt die Regel nicht an — sie blockiert nur den Einstieg.",

  "r.R7.name": "Stop und Ziel sind Pflicht",
  "r.R7.was": "Jede betreute Position braucht eine Stop- <b>und</b> eine Ziel-Marke. Fehlt eine, bleiben dir vier Sekunden zum Nachtragen — danach wird die Position geschlossen.",
  "r.R7.bsp": "Nimmst du nach zwei Stunden den Stop weg, ist die Position vier Sekunden später zu. Die Frist läuft ab dem Moment, in dem die Marke <b>fehlt</b>, nicht ab der Eröffnung, und sie merkt sich das je Position: MetaTrader neu starten setzt sie <b>nicht</b> zurück. Wichtig: geschlossen wird nur die <b>Position</b> — MetaTrader läuft weiter.",

  "r.R22.name": "Nur Trades über das Panel",
  "r.R22.was": "Alle anderen Regeln hängen am Panel. Was du daneben öffnest — direkt im Chart, in der Marktübersicht, unterwegs mit der Handy-App —, läuft durch <b>keine</b> davon. Darum nimmt das Werkzeug solche Trades wieder zurück.",
  "r.R22.bsp": "Jeder Trade über den Kauf- oder Verkaufsknopf bekommt eine unsichtbare Kennnummer. Was ohne Kennnummer auftaucht, wird geschlossen; vorgemerkte Aufträge werden gelöscht. Das gilt auf <b>allen</b> Märkten des Kontos. <b>Ehrlich dazu:</b> es verhindert den Trade nicht, es macht ihn rückgängig — den Spread hast du bezahlt. Trades eines anderen Handelsprogramms tragen deren eigene Kennung und bleiben unangetastet.",

  // ---- Die Bremsen -------------------------------------------------------
  "r.R3.name": "Tagesbudget",
  "r.R3.was": "Über den Tag zählt das Werkzeug zusammen, wie viel Risiko es mit eigenen Trades <b>eröffnet</b> hat. Gewinner zählen mit — zurückgegeben wird nichts. Ist das Budget aufgebraucht, nimmt es keinen Einstieg mehr an.",
  "r.R3.bsp": "Du eröffnest acht Trades → der neunte wird abgewiesen, <b>auch wenn alle acht im Gewinn liegen</b>. Offene Positionen laufen weiter. Morgen beginnt das Budget wieder bei null.",

  "r.R4.name": "Tagesverlust-Bremse",
  "r.R4.was": "Steht dein Kapital im laufenden Handelstag um die eingestellte Grenze unter der Tagesbasis, ist Schluss. Gemessen wird das Kapital <b>einschließlich</b> der schwebenden Gewinne und Verluste offener Positionen, nicht nur der abgerechnete Kontostand.",
  "r.R4.bsp": "Die Sperre gilt sofort für alle Charts: kein neuer Einstieg mehr — weder am Panel noch aus dem Browser — und <b>alle betreuten Positionen werden geschlossen</b>, vorgemerkte Aufträge gelöscht. Das ist die Notbremse, damit du die Grenze deiner Prop-Firma gar nicht erst erreichst.",

  "r.R4b.name": "Max-Verlust-Schild",
  "r.R4b.was": "Der Schutz für das <b>ganze Konto</b>, gemessen gegen die Startbilanz der Challenge und fortlaufend geprüft. Zwei Stufen, die sich deutlich unterscheiden.",
  "r.R4b.bsp": "<b>Frühwarnung:</b> jeder neue Einstieg wird abgelehnt — das ist die einzige Wirkung. Offene Positionen bleiben offen, werden weiter betreut und können jederzeit von Hand geschlossen werden. <b>Harte Stufe:</b> dauerhaft Schluss. Das ist dein Sicherheitsabstand zur Grenze der Prop-Firma.",

  "r.R18.name": "Wochenlimit",
  "r.R18.was": "Liegt dein Kapital — offene Positionen mitgerechnet — um die eingestellte Grenze unter dem Stand vom Wochenbeginn, ist die Woche zu Ende.",
  "r.R18.bsp": "Wie bei der Tagessperre: <b>alle betreuten Positionen werden geschlossen</b> und vorgemerkte Aufträge gelöscht, danach keine neuen Einstiege bis zum Wochenwechsel. Deckelt eine schlechte Woche, bevor daraus ein schlechter Monat wird.",

  // ---- Serien und Pausen -------------------------------------------------
  "r.R5.name": "Pause nach Verlustserie",
  "r.R5.was": "Mehrere Verlust-Trades hintereinander am selben Handelstag → eine Zwangspause. Gewertet wird das <b>Netto</b>-Ergebnis einer Position, also einschließlich Gebühren und Finanzierungskosten.",
  "r.R5.bsp": "Stop, Stop, Stop → Pause. Das Werkzeug nimmt keinen neuen Trade an und nennt dir die Restzeit. <b>Positionen, die schon laufen, bleiben offen</b> — die Pause bremst den Einstieg, nicht den Ausstieg. Statt frustriert weiterzumachen, holst du erst Luft.",

  "r.R6.name": "Schluss nach Verlustserie",
  "r.R6.was": "Noch mehr Verluste hintereinander am selben Tag → der Tag ist beendet.",
  "r.R6.bsp": "Anders als die Pause macht diese Regel <b>reinen Tisch</b>: alle betreuten Positionen werden geschlossen, und gesperrt ist bis zum eingestellten Tagesbeginn — in der Werkseinstellung Mitternacht Serverzeit, nicht bis morgen Abend. Deckelt die wirklich schlechten Tage.",

  "r.R13.name": "Tagesziel und Tageshoch",
  "r.R13.was": "Zwei Dinge in einer Regel. <b>Ziel erreicht:</b> steht dein Kapital — offene Positionen mitgerechnet — um das eingestellte Ziel über dem Tagesstart, nimmt das Werkzeug keinen neuen Einstieg mehr an. <b>Tageshoch verteidigen:</b> warst du am Tag schon deutlich im Plus und gibst davon zu viel wieder ab, wird der Tag gesperrt.",
  "r.R13.bsp": "Beim erreichten Ziel laufen offene Positionen <b>weiter</b>, es kommt nur nichts Neues dazu. Beim Rückfall vom Tageshoch ist es strenger: <b>alles wird geschlossen</b> und der Tag ist zu — damit aus Grün nicht Rot wird. Der Rückfallschutz wird erst scharf, nachdem du am Tag überhaupt im Plus warst.",

  // ---- Streuung und Rahmen -----------------------------------------------
  "r.R12.name": "Gesamtrisiko",
  "r.R12.was": "Egal wie viele Positionen offen sind — <b>zusammen</b> nie mehr als die eingestellte Grenze. Das Werkzeug rechnet beim Eröffnen das Risiko aller offenen Positionen zusammen und addiert das der neuen.",
  "r.R12.bsp": "Zwei verschiedene Folgen, die man nicht verwechseln darf. <b>Beim Eröffnen:</b> der Trade wird gar nicht erst an den Broker geschickt. <b>Später,</b> wenn das Gesamtrisiko trotzdem über die Grenze steigt: das Werkzeug schließt die <b>jüngste</b> Position.",

  "r.R17.name": "Nicht zu viel in einer Währung",
  "r.R17.was": "Das Werkzeug zerlegt jede Position in ihre beiden Währungen — ein Kauf von EUR/USD ist zugleich eine Wette auf einen starken Euro und einen schwachen Dollar — und zählt zusammen, wie stark du auf <b>eine</b> Währung setzt.",
  "r.R17.bsp": "Du kaufst EUR/USD <b>und</b> GBP/USD: beides ist „Dollar schwach“. Ist die Grenze für eine einzelne Währung voll, wird der nächste solche Einstieg abgelehnt. Gegenläufige Positionen heben sich auf. Bereits offene rührt die Regel nicht an. <b>Warum:</b> damit nicht <b>eine</b> Währungsbewegung alle deine Trades gleichzeitig trifft.",

  "r.R16.name": "Handelszeiten und News",
  "r.R16.was": "Zwei getrennte Schalter mit derselben Wirkung: ein erlaubtes Zeitfenster, und eine Nachrichtensperre, die du selbst setzt. Beide sind einzeln abschaltbar — darum steht hier „optional“.",
  "r.R16.bsp": "In einem gesperrten Fenster kommt kein neuer Trade zustande, vorgemerkte Aufträge werden gelöscht, und eine Position, die außerhalb der erlaubten Zeit entstanden ist, wird wieder geschlossen. Gerechnet wird mit der Uhrzeit <b>deines Brokers</b>, nicht mit deiner eigenen.",

  "r.R23.name": "Wochenrisiko bestätigen",
  "r.R23.was": "Vor der ersten Order einer Woche musst du dein <b>Risiko je Trade</b> im Panel eintippen und mit SETZEN bestätigen. Solange das fehlt, wird kein Trade eröffnet — weder per Klick noch aus dem Browser.",
  "r.R23.bsp": "Die Kauf- und Verkaufsknöpfe sind grau, bis du bestätigt hast. Das wiederholt sich mit <b>jedem Wochenwechsel</b>. Der Sinn: eine bewusste Entscheidung am Wochenanfang statt einer Reihe von Bauchentscheidungen im Lauf der Woche. Offene Positionen laufen weiter und dürfen verwaltet werden.",

  "r.R10.name": "Kein Aushebeln",
  "r.R10.was": "Es gibt <b>keinen</b> Knopf, der eine Sperre vorzeitig aufhebt. Sperren überleben einen Neustart des Programms und sogar einen Rechnerausfall.",
  "r.R10.bsp": "Du bist gesperrt und startest MetaTrader neu — die Sperre bleibt. Eine gelöschte oder beschädigte Sperrdatei führt zur <b>Tagessperre</b>, nicht zur Freigabe. Eine Verlustgrenze <b>enger</b> zu stellen wirkt sofort, sie <b>weiter</b> zu stellen erst ab dem nächsten Tageswechsel. <b>Ehrlich:</b> wirklich unumgehbar ist das erst auf einem abgeriegelten Server, zu dem nur du Zugang hast.",

  "r.R11.name": "Tagebuch",
  "r.R11.was": "Jede Eröffnung, jede Schließung, jedes Verschieben von Stop oder Ziel, jeder abgewiesene Versuch und jede Sperre bekommt eine Zeile mit <b>Begründung</b> — mit Zeitpunkt, Kurs, Größe, Risiko und Regelkennung.",
  "r.R11.bsp": "Später liest du nach, warum etwas nicht ging. Gut für die eigene Nachbereitung und als Nachweis gegenüber der Prop-Firma. Zu dieser Regel gehören auch die <b>Bildschirmfotos</b>, die das Werkzeug bei jeder Handlung ablegt. Aufgezeichnet wird, was das Werkzeug betreut — nicht, was daneben passiert.",

  // ---- Abgeschaltet ------------------------------------------------------
  "r.R8.name": "Mindestabstand zum Ziel",
  "r.R8.was": "Würde eine <b>laufende</b> Position schließen, deren Ziel im Verhältnis zum Stop zu nah liegt — sie prüft also nicht den Einstieg, sondern greift danach ein. <b>Auf deinen Wunsch abgeschaltet.</b>",
  "r.R8.bsp": "Das automatische Ziel deiner Panel-Trades liegt weiterhin beim Doppelten des Risikos — aber als Vorschlag, nicht als Bedingung.",

  "r.R9.name": "Bedenkzeit vor dem Trade",
  "r.R9.was": "Würde nach dem Klick auf Kaufen oder Verkaufen eine kurze Wartezeit einlegen, bevor die Order herausgeht. <b>Auf deinen Wunsch abgeschaltet</b> — der Klick geht sofort weiter.",
  "r.R9.bsp": "Ungeprüft ist er deshalb nicht: danach entscheiden wie immer Sperren, Wochenrisiko, Stop-Pflicht, Tagesbudget und alle übrigen Regeln.",

  "r.R14.name": "Mindestpause zwischen Trades",
  "r.R14.was": "Würde verlangen, dass zwischen zwei Einstiegen eine Mindestzeit vergeht — kontoweit, nicht je Markt. <b>Auf deinen Wunsch abgeschaltet.</b>",
  "r.R14.bsp": "Eingeschaltet würde nur der neue Einstieg abgelehnt; offene Positionen blieben unberührt.",

  "r.R15.name": "Mindestabstand des Stops",
  "r.R15.was": "Würde einen Mindestabstand zwischen Kurs und Stop verlangen und sehr kleine Positionsgrößen ablehnen. <b>Abgeschaltet</b>, weil Scalping auf kurzen Zeiteinheiten enge Stops braucht.",
  "r.R15.bsp": "Was dich weiterhin schützt: der harte Mindestabstand deines Brokers und die automatische Positionsgröße. <b>Ehrliche Einschränkung:</b> der Extremfall „winziger Stop, dann reißt eine Kurslücke mehr weg als geplant“ ist damit nicht mehr abgedeckt.",

  "r.R19.name": "Risiko senken nach Verlusten",
  "r.R19.was": "Würde dein Risiko je Trade verkleinern, sobald am laufenden Tag mehrere Verluste in Folge auf dem Zähler stehen. <b>Auf deinen Wunsch abgeschaltet.</b>",
  "r.R19.bsp": "Eingeschaltet würde nur die <b>Größe</b> sinken — nichts gesperrt, keine offene Position angetastet. Dein Risiko bleibt so konstant.",

  "r.R25.name": "Kein Rache-Trade",
  "r.R25.was": "Würde einen Gegen-Trade unmittelbar nach einem Verlust blockieren — allerdings nur, wenn der Verlust dir zugerechnet wird: weil du selbst geschlossen hast oder das Werkzeug wegen eines Regelbruchs schließen musste. <b>Auf deinen Wunsch abgeschaltet.</b>",
  "r.R25.bsp": "Die Disziplin übernehmen hier die harten Grenzen: Tages-, Gesamt- und Wochenbremse, dazu die Pause und der Schluss nach einer Verlustserie."
 },

 // ==========================================================================
 "en": {
  "regeln.pageTitle": "Mamal-Trading · The rules",
  "regeln.h1": "The rules in plain language",
  "regeln.lead": "No technical knowledge needed. Think of the tool as a calm, strict coach sitting next to you: it never tells you WHAT to trade — that stays your decision. It only makes sure you do not ruin yourself.",
  "regeln.h2.alle": "Every rule in detail",
  "regeln.h2.grenzen": "What the tool cannot do",

  "konfig.zeile": "How your tool is set right now — account {konto}, profile {profil}. These numbers come from the running Expert Advisor; they are not written down on this page.",
  "konfig.offline": "No connection to the cockpit right now — the rule texts below still apply, only the current numbers are missing.",
  "konfig.risiko": "Risk per trade",
  "konfig.tag": "Daily loss limit",
  "konfig.max": "Max loss",
  "konfig.woche": "Weekly limit",
  "konfig.ziel": "Daily target",
  "konfig.gesamt": "Total risk",

  "zustand.an": "active",
  "zustand.aus": "switched off",
  "zustand.optional": "optional",

  "wert.rund": "about {x}",
  "wert.jeTrade": "Set per trade: {x}",
  "wert.jeIdee": "Set per idea: {x}",
  "wert.jeTag": "Set per day: {x}",
  "wert.grenze": "Set to: {x}",
  "wert.zweiStufen": "Early warning from {a} · hard lock from {b}",
  "wert.cooldown": "After {n} losses in a row · {min} minutes break",
  "wert.nachN": "After {n} losses in a row",
  "wert.ziel": "Daily target: {x}",
  "wert.zusammen": "For all open trades together: {x}",

  "grenzen.lead": "Being honest — here is what it cannot do:",
  "grenzen.anzahl": "6",
  "grenzen.1": "It reacts <b>very fast, but not in zero seconds</b> (about half a second). Whatever can happen in that time is caught by the daily and total brakes.",
  "grenzen.2": "It cannot <b>prevent</b> a trade you open past the panel — only <b>undo</b> it. For that one second you really were in the market: spread paid, the price may have moved. The rule protects your rulebook, not your cent.",
  "grenzen.3": "The genuinely hard limit is your prop firm's, and it sits on their server. This tool makes sure you never get there in the first place — it does not replace it.",
  "grenzen.4": "It only protects while <b>MetaTrader is running and auto trading is on</b>. With auto trading off the protection is off — hence the orange warning “SCHUTZ AUS” (protection off).",
  "grenzen.5": "It only counts what it <b>supervises</b> itself. Trades from another trading program carry their own identifier and are left alone.",
  "grenzen.6": "It is <b>not a money printing machine</b>. It does not find trades for you. It is your discipline coach, nothing more.",

  "r.R1.name": "Automatic position size",
  "r.R1.was": "You decide where your stop goes — the tool works out from that how large the position may be so that you lose at most the configured share of your account. You never have to do the maths.",
  "r.R1.bsp": "Stop 20 points away → smaller position. Only 10 points away → twice the size. <b>In both cases you risk the same.</b> The order never goes out larger than calculated; if the size would fall below your broker's minimum, no order is placed at all. If you later drag the stop <b>further away</b>, your risk rises — then the tool closes exactly that position. Moving it closer is always allowed.",

  "r.R2.name": "One idea, one budget",
  "r.R2.was": "Several positions in the same market in the same direction count as <b>one idea</b>. Together their risk may not exceed the idea cap.",
  "r.R2.bsp": "Buy gold, buy gold again → full together. The next buy is <b>not placed</b>, with a note on the chart and an entry in the journal. Selling gold or a different market still works. The rule does not touch open positions — it only blocks the entry.",

  "r.R7.name": "Stop and target are mandatory",
  "r.R7.was": "Every supervised position needs a stop <b>and</b> a target. If one is missing you have four seconds to add it — after that the position is closed.",
  "r.R7.bsp": "Remove the stop after two hours and the position is gone four seconds later. The clock starts the moment the marker is <b>missing</b>, not at opening, and it remembers this per position: restarting MetaTrader does <b>not</b> reset it. Important: only the <b>position</b> is closed — MetaTrader keeps running.",

  "r.R22.name": "Panel trades only",
  "r.R22.was": "Every other rule hangs off the panel. Whatever you open beside it — straight in the chart, in the market watch, from the phone app while you are out — runs through <b>none</b> of them. So the tool takes such trades back.",
  "r.R22.bsp": "Every trade from the buy or sell button gets an invisible identifier. Anything that shows up without one is closed; pending orders are deleted. This applies across <b>all</b> markets on the account. <b>Honestly:</b> it does not prevent the trade, it undoes it — you paid the spread. Trades from another trading program carry their own identifier and are left untouched.",

  "r.R3.name": "Daily budget",
  "r.R3.was": "Over the day the tool adds up how much risk it has <b>opened</b> with its own trades. Winners count too — nothing is given back. Once the budget is used up, it accepts no further entry.",
  "r.R3.bsp": "You open eight trades → the ninth is refused, <b>even if all eight are in profit</b>. Open positions keep running. Tomorrow the budget starts at zero again.",

  "r.R4.name": "Daily loss brake",
  "r.R4.was": "If your capital during the trading day sits the configured amount below the day's base, that is it. What is measured is your capital <b>including</b> the floating profit and loss of open positions, not just the settled balance.",
  "r.R4.bsp": "The lock applies at once across all charts: no new entry — neither from the panel nor from the browser — and <b>all supervised positions are closed</b>, pending orders deleted. This is the emergency brake that keeps you from ever reaching your prop firm's limit.",

  "r.R4b.name": "Max loss shield",
  "r.R4b.was": "Protection for the <b>whole account</b>, measured against the challenge's starting balance and checked continuously. Two stages that differ sharply.",
  "r.R4b.bsp": "<b>Early warning:</b> every new entry is refused — that is the only effect. Open positions stay open, keep being supervised, and can be closed by hand at any time. <b>Hard stage:</b> permanently done. This is your safety margin to the prop firm's limit.",

  "r.R18.name": "Weekly limit",
  "r.R18.was": "If your capital — open positions included — sits the configured amount below the level at the start of the week, the week is over.",
  "r.R18.bsp": "Just like the daily lock: <b>all supervised positions are closed</b> and pending orders deleted, then no new entries until the week turns. Caps a bad week before it becomes a bad month.",

  "r.R5.name": "Break after a losing streak",
  "r.R5.was": "Several losing trades in a row on the same trading day → a forced break. What counts is the <b>net</b> result of a position, so including fees and financing costs.",
  "r.R5.bsp": "Stop, stop, stop → break. The tool accepts no new trade and tells you the time remaining. <b>Positions already running stay open</b> — the break slows the entry, not the exit. Instead of carrying on in frustration, you catch your breath first.",

  "r.R6.name": "Done after a losing streak",
  "r.R6.was": "More losses in a row on the same day → the day is over.",
  "r.R6.bsp": "Unlike the break, this rule <b>clears the table</b>: all supervised positions are closed, and the lock runs until the configured start of day — by default midnight server time, not until tomorrow evening. Caps the genuinely bad days.",

  "r.R13.name": "Daily target and daily high",
  "r.R13.was": "Two things in one rule. <b>Target reached:</b> if your capital — open positions included — sits the configured target above the day's start, the tool accepts no new entry. <b>Defending the daily high:</b> if you were clearly up on the day and give back too much of it, the day is locked.",
  "r.R13.bsp": "With the target reached, open positions <b>keep running</b>, only nothing new is added. The giveback is stricter: <b>everything is closed</b> and the day is done — so that green does not turn red. The giveback protection only arms once you have actually been up on the day.",

  "r.R12.name": "Total risk",
  "r.R12.was": "No matter how many positions are open — <b>together</b> never more than the configured limit. On opening, the tool adds up the risk of all open positions and the new one.",
  "r.R12.bsp": "Two different consequences that must not be confused. <b>On opening:</b> the trade is never sent to the broker at all. <b>Later,</b> if total risk climbs over the limit anyway: the tool closes the <b>newest</b> position.",

  "r.R17.name": "Not too much of one currency",
  "r.R17.was": "The tool splits every position into its two currencies — buying EUR/USD is a bet on a strong euro and a weak dollar at once — and adds up how heavily you are betting on <b>one</b> currency.",
  "r.R17.bsp": "You buy EUR/USD <b>and</b> GBP/USD: both are “weak dollar”. Once the limit for a single currency is full, the next such entry is refused. Opposing positions cancel each other out. The rule does not touch ones already open. <b>Why:</b> so that <b>one</b> currency move does not hit all your trades at once.",

  "r.R16.name": "Trading hours and news",
  "r.R16.was": "Two separate switches with the same effect: a permitted time window, and a news lock you set yourself. Both can be switched off individually — hence “optional” here.",
  "r.R16.bsp": "Inside a locked window no new trade comes about, pending orders are deleted, and a position that arose outside the permitted time is closed again. The clock used is <b>your broker's</b>, not your own.",

  "r.R23.name": "Confirm the weekly risk",
  "r.R23.was": "Before the first order of a week you must type your <b>risk per trade</b> into the panel and confirm it with SET. Until that is done, no trade is opened — neither by click nor from the browser.",
  "r.R23.bsp": "The buy and sell buttons stay grey until you confirm. This repeats with <b>every change of week</b>. The point: one deliberate decision at the start of the week instead of a series of gut calls during it. Open positions keep running and may be managed.",

  "r.R10.name": "No overriding",
  "r.R10.was": "There is <b>no</b> button that lifts a lock early. Locks survive a restart of the program and even a machine failure.",
  "r.R10.bsp": "You are locked and restart MetaTrader — the lock stays. A deleted or damaged lock file leads to a <b>day lock</b>, not to release. Tightening a loss limit takes effect at once; loosening one only from the next change of day. <b>Honestly:</b> this becomes genuinely un-bypassable only on a locked-down server that only you can reach.",

  "r.R11.name": "Journal",
  "r.R11.was": "Every opening, every close, every move of a stop or target, every refused attempt and every lock gets a line with a <b>reason</b> — with time, price, size, risk and the rule's identifier.",
  "r.R11.bsp": "Later you can read why something did not go through. Good for your own review and as evidence towards the prop firm. The <b>screenshots</b> the tool files on every action belong to this rule too. What is recorded is what the tool supervises — not what happens beside it.",

  "r.R8.name": "Minimum distance to the target",
  "r.R8.was": "Would close a <b>running</b> position whose target sits too close relative to the stop — so it does not check the entry, it steps in afterwards. <b>Switched off at your request.</b>",
  "r.R8.bsp": "The automatic target of your panel trades is still twice the risk — as a suggestion, not as a condition.",

  "r.R9.name": "Cooling-off before the trade",
  "r.R9.was": "Would insert a short wait after you click Buy or Sell, before the order goes out. <b>Switched off at your request</b> — the click goes straight through.",
  "r.R9.bsp": "That does not make it unchecked: afterwards the locks, the weekly risk, the stop requirement, the daily budget and all the other rules decide as usual.",

  "r.R14.name": "Minimum gap between trades",
  "r.R14.was": "Would require a minimum time between two entries — account-wide, not per market. <b>Switched off at your request.</b>",
  "r.R14.bsp": "Switched on, only the new entry would be refused; open positions would be left untouched.",

  "r.R15.name": "Minimum stop distance",
  "r.R15.was": "Would require a minimum distance between price and stop and refuse very small position sizes. <b>Switched off</b>, because scalping on short timeframes needs tight stops.",
  "r.R15.bsp": "What still protects you: your broker's hard minimum distance and the automatic position size. <b>Honest limitation:</b> the extreme case “tiny stop, then a gap tears away more than planned” is no longer covered.",

  "r.R19.name": "Reduce risk after losses",
  "r.R19.was": "Would shrink your risk per trade once several losses in a row stand on the counter for the current day. <b>Switched off at your request.</b>",
  "r.R19.bsp": "Switched on, only the <b>size</b> would fall — nothing locked, no open position touched. This way your risk stays constant.",

  "r.R25.name": "No revenge trade",
  "r.R25.was": "Would block a counter-trade straight after a loss — but only where the loss is attributed to you: because you closed it yourself, or the tool had to close it over a rule breach. <b>Switched off at your request.</b>",
  "r.R25.bsp": "Discipline here is carried by the hard limits: daily, total and weekly brake, plus the break and the stop after a losing streak."
 },

 // ==========================================================================
 "fa": {
  "regeln.pageTitle": "Mamal-Trading · قوانین",
  "regeln.h1": "قوانین به زبان ساده",
  "regeln.lead": "به دانش فنی نیازی نیست. این ابزار را مثل مربی‌ای آرام و سخت‌گیر کنار خودت تصور کن: هرگز نمی‌گوید چه چیزی معامله کنی — آن تصمیم خودت است. فقط مراقب است که خودت را نابود نکنی.",
  "regeln.h2.alle": "هر قانون به‌تفکیک",
  "regeln.h2.grenzen": "کاری که این ابزار نمی‌تواند بکند",

  "konfig.zeile": "تنظیم فعلی ابزار تو — حساب {konto}، پروفایل {profil}. این اعداد از Expert Advisor در حال اجرا می‌آیند و در این صفحه نوشته نشده‌اند.",
  "konfig.offline": "الان ارتباطی با کاکپیت نیست — متن قوانین پایین همچنان معتبر است، فقط اعداد روز نیستند.",
  "konfig.risiko": "ریسک هر معامله",
  "konfig.tag": "مرز ضرر روزانه",
  "konfig.max": "حداکثر ضرر",
  "konfig.woche": "سقف هفتگی",
  "konfig.ziel": "هدف روزانه",
  "konfig.gesamt": "ریسک کل",

  "zustand.an": "فعال",
  "zustand.aus": "خاموش",
  "zustand.optional": "اختیاری",

  "wert.rund": "حدود {x}",
  "wert.jeTrade": "تنظیم برای هر معامله: {x}",
  "wert.jeIdee": "تنظیم برای هر ایده: {x}",
  "wert.jeTag": "تنظیم برای هر روز: {x}",
  "wert.grenze": "تنظیم‌شده: {x}",
  "wert.zweiStufen": "هشدار زودهنگام از {a} · قفل سخت از {b}",
  "wert.cooldown": "پس از {n} ضرر پیاپی · {min} دقیقه وقفه",
  "wert.nachN": "پس از {n} ضرر پیاپی",
  "wert.ziel": "هدف روزانه: {x}",
  "wert.zusammen": "برای همهٔ معاملات باز روی هم: {x}",

  "grenzen.lead": "رک بگویم — این کارها از آن برنمی‌آید:",
  "grenzen.anzahl": "6",
  "grenzen.1": "<b>خیلی سریع واکنش می‌دهد، اما نه در صفر ثانیه</b> (حدود نیم ثانیه). آنچه در این فاصله ممکن است رخ دهد را ترمز روزانه و ترمز کل می‌گیرند.",
  "grenzen.2": "معامله‌ای را که بیرون از پنل باز کنی <b>نمی‌تواند جلویش را بگیرد</b> — فقط <b>برمی‌گرداند</b>. در آن یک ثانیه واقعاً در بازار بودی: اسپرد را پرداختی و قیمت ممکن است جابجا شده باشد. این قانون از قاعده‌ات محافظت می‌کند، نه از سِنتَت.",
  "grenzen.3": "مرز واقعاً سخت، مرز پراپ‌فرم توست و روی سرور آن‌ها قرار دارد. این ابزار کاری می‌کند که اصلاً به آنجا نرسی — جایگزینش نمی‌شود.",
  "grenzen.4": "فقط تا وقتی محافظت می‌کند که <b>متاتریدر باز باشد و AutoTrading روشن</b>. با خاموش بودن AutoTrading محافظت هم خاموش است — به همین دلیل آن هشدار نارنجی «SCHUTZ AUS».",
  "grenzen.5": "فقط آنچه را می‌شمارد که خودش <b>سرپرستی</b> می‌کند. معاملات برنامهٔ معاملاتی دیگر شناسهٔ خودشان را دارند و دست‌نخورده می‌مانند.",
  "grenzen.6": "<b>دستگاه چاپ پول نیست.</b> برایت معامله پیدا نمی‌کند. مربی انضباط توست، همین.",

  "r.R1.name": "حجم خودکار معامله",
  "r.R1.was": "تو تعیین می‌کنی حد ضرر کجا باشد — ابزار از روی همان حساب می‌کند که حجم چقدر باشد تا بیش از سهم تنظیم‌شدهٔ حسابت از دست نرود. هرگز لازم نیست خودت حساب کنی.",
  "r.R1.bsp": "حد ضرر ۲۰ پوینت دورتر ← حجم کمتر. فقط ۱۰ پوینت ← دو برابر. <b>در هر دو حالت ریسکت یکسان است.</b> سفارش هرگز بزرگ‌تر از محاسبه بیرون نمی‌رود؛ اگر حجم از حداقل کارگزار کمتر شود، اصلاً سفارشی ثبت نمی‌شود. اگر بعداً حد ضرر را <b>دورتر</b> بکشی ریسکت بالا می‌رود — آنگاه ابزار دقیقاً همان معامله را می‌بندد. نزدیک‌تر کشیدن همیشه مجاز است.",

  "r.R2.name": "یک ایده، یک بودجه",
  "r.R2.was": "چند معامله در یک بازار و یک جهت، <b>یک ایده</b> شمرده می‌شوند. ریسکشان روی هم نباید از سقف ایده بگذرد.",
  "r.R2.bsp": "خرید طلا، باز هم خرید طلا ← روی هم پر. خرید بعدی <b>ثبت نمی‌شود</b>، با پیامی روی چارت و ثبتی در دفترچه. فروش طلا یا بازاری دیگر همچنان ممکن است. این قانون به معاملات باز کاری ندارد — فقط ورود را می‌بندد.",

  "r.R7.name": "حد ضرر و هدف اجباری‌اند",
  "r.R7.was": "هر معاملهٔ تحت سرپرستی به حد ضرر <b>و</b> هدف نیاز دارد. اگر یکی نباشد، چهار ثانیه فرصت داری اضافه‌اش کنی — پس از آن معامله بسته می‌شود.",
  "r.R7.bsp": "اگر بعد از دو ساعت حد ضرر را برداری، چهار ثانیه بعد معامله بسته است. شمارش از لحظه‌ای شروع می‌شود که نشانه <b>غایب</b> است، نه از زمان باز شدن، و برای هر معامله جداگانه به‌خاطر سپرده می‌شود: راه‌اندازی دوبارهٔ متاتریدر آن را <b>صفر نمی‌کند</b>. مهم: فقط <b>معامله</b> بسته می‌شود — متاتریدر به کارش ادامه می‌دهد.",

  "r.R22.name": "فقط معامله از پنل",
  "r.R22.was": "همهٔ قوانین دیگر به پنل وصل‌اند. آنچه بیرون از آن باز کنی — مستقیم روی چارت، در پنجرهٔ بازار، با اپ موبایل در راه — از <b>هیچ‌کدام</b> رد نمی‌شود. برای همین ابزار چنین معامله‌ای را پس می‌گیرد.",
  "r.R22.bsp": "هر معامله‌ای که از دکمهٔ خرید یا فروش بیاید شناسه‌ای نامرئی می‌گیرد. هر چه بدون شناسه ظاهر شود بسته می‌شود؛ سفارش‌های در انتظار حذف می‌شوند. این روی <b>همهٔ</b> بازارهای حساب اعمال می‌شود. <b>رک بگویم:</b> جلوی معامله را نمی‌گیرد، آن را برمی‌گرداند — اسپرد را پرداخته‌ای. معاملات برنامهٔ دیگر شناسهٔ خودشان را دارند و دست‌نخورده می‌مانند.",

  "r.R3.name": "بودجهٔ روزانه",
  "r.R3.was": "در طول روز ابزار جمع می‌زند چقدر ریسک با معاملات خودش <b>باز کرده</b> است. بردها هم حساب می‌شوند — چیزی پس داده نمی‌شود. با پر شدن بودجه، ورود تازه‌ای نمی‌پذیرد.",
  "r.R3.bsp": "هشت معامله باز می‌کنی ← نهمی رد می‌شود، <b>حتی اگر هر هشت در سود باشند</b>. معاملات باز به کارشان ادامه می‌دهند. فردا بودجه از صفر شروع می‌شود.",

  "r.R4.name": "ترمز ضرر روزانه",
  "r.R4.was": "اگر سرمایه‌ات در روز معاملاتی به اندازهٔ مرز تنظیم‌شده زیر پایهٔ آن روز بایستد، کار تمام است. آنچه سنجیده می‌شود سرمایه است <b>به‌همراه</b> سود و زیان شناور معاملات باز، نه فقط موجودی تسویه‌شده.",
  "r.R4.bsp": "قفل بی‌درنگ روی همهٔ چارت‌ها اعمال می‌شود: نه ورود تازه‌ای — نه از پنل نه از مرورگر — و <b>همهٔ معاملات تحت سرپرستی بسته می‌شوند</b>، سفارش‌های در انتظار حذف. این ترمز اضطراری است تا اصلاً به مرز پراپ‌فرم نرسی.",

  "r.R4b.name": "سپر حداکثر ضرر",
  "r.R4b.was": "محافظت از <b>کل حساب</b>، سنجیده در برابر موجودی آغازین Challenge و به‌طور پیوسته بررسی‌شده. دو پله که تفاوتشان مهم است.",
  "r.R4b.bsp": "<b>هشدار زودهنگام:</b> هر ورود تازه رد می‌شود — تنها اثرش همین است. معاملات باز، باز می‌مانند، سرپرستی می‌شوند و هر وقت بخواهی دستی بسته می‌شوند. <b>پلهٔ سخت:</b> پایان دائمی. این فاصلهٔ ایمنی تو تا مرز پراپ‌فرم است.",

  "r.R18.name": "سقف هفتگی",
  "r.R18.was": "اگر سرمایه‌ات — با احتساب معاملات باز — به اندازهٔ مرز تنظیم‌شده زیر سطح آغاز هفته بایستد، هفته تمام است.",
  "r.R18.bsp": "درست مثل قفل روزانه: <b>همهٔ معاملات تحت سرپرستی بسته می‌شوند</b> و سفارش‌های در انتظار حذف، سپس تا چرخش هفته ورودی در کار نیست. یک هفتهٔ بد را سقف می‌زند پیش از آنکه ماه بدی شود.",

  "r.R5.name": "وقفه پس از زنجیرهٔ ضرر",
  "r.R5.was": "چند معاملهٔ زیان‌ده پیاپی در یک روز معاملاتی ← وقفهٔ اجباری. آنچه شمرده می‌شود نتیجهٔ <b>خالص</b> معامله است، یعنی با احتساب کارمزد و هزینهٔ شبانه.",
  "r.R5.bsp": "ضرر، ضرر، ضرر ← وقفه. ابزار معاملهٔ تازه نمی‌پذیرد و زمان باقی‌مانده را می‌گوید. <b>معاملاتی که از پیش باز بوده‌اند باز می‌مانند</b> — وقفه ورود را کُند می‌کند، نه خروج را. به‌جای ادامه دادن با عصبانیت، اول نفسی تازه می‌کنی.",

  "r.R6.name": "پایان پس از زنجیرهٔ ضرر",
  "r.R6.was": "ضررهای پیاپی بیشتر در همان روز ← روز تمام است.",
  "r.R6.bsp": "برخلاف وقفه، این قانون <b>میز را جمع می‌کند</b>: همهٔ معاملات تحت سرپرستی بسته می‌شوند و قفل تا آغاز روزِ تنظیم‌شده ادامه دارد — در حالت پیش‌فرض نیمه‌شب به وقت سرور، نه تا فردا شب. روزهای واقعاً بد را سقف می‌زند.",

  "r.R13.name": "هدف روزانه و سقف روز",
  "r.R13.was": "دو چیز در یک قانون. <b>هدف محقق شد:</b> اگر سرمایه‌ات — با احتساب معاملات باز — به اندازهٔ هدف تنظیم‌شده بالای شروع روز بایستد، ابزار ورود تازه نمی‌پذیرد. <b>دفاع از سقف روز:</b> اگر در روز به‌روشنی در سود بوده‌ای و زیادی از آن را پس بدهی، روز قفل می‌شود.",
  "r.R13.bsp": "با تحقق هدف، معاملات باز <b>ادامه می‌یابند</b> و فقط چیز تازه‌ای افزوده نمی‌شود. پس‌دادن سخت‌گیرانه‌تر است: <b>همه‌چیز بسته می‌شود</b> و روز تمام — تا سبز به قرمز بدل نشود. این محافظت تنها وقتی مسلح می‌شود که واقعاً در آن روز در سود بوده باشی.",

  "r.R12.name": "ریسک کل",
  "r.R12.was": "هر چند معامله که باز باشد — <b>روی هم</b> هرگز بیش از مرز تنظیم‌شده. هنگام باز کردن، ابزار ریسک همهٔ معاملات باز را جمع می‌زند و ریسک معاملهٔ تازه را به آن می‌افزاید.",
  "r.R12.bsp": "دو پیامد متفاوت که نباید اشتباه گرفته شوند. <b>هنگام باز کردن:</b> معامله اصلاً به کارگزار فرستاده نمی‌شود. <b>بعداً،</b> اگر ریسک کل با این حال از مرز بگذرد: ابزار <b>تازه‌ترین</b> معامله را می‌بندد.",

  "r.R17.name": "نه بیش از حد روی یک ارز",
  "r.R17.was": "ابزار هر معامله را به دو ارزش تجزیه می‌کند — خرید EUR/USD هم‌زمان شرط‌بندی روی یورو قوی و دلار ضعیف است — و جمع می‌زند چقدر روی <b>یک</b> ارز شرط بسته‌ای.",
  "r.R17.bsp": "EUR/USD <b>و</b> GBP/USD می‌خری: هر دو «دلار ضعیف»اند. وقتی مرز یک ارز پر شد، ورود بعدی از همان دست رد می‌شود. معاملات مخالف یکدیگر را خنثی می‌کنند. قانون به آنچه از پیش باز است کاری ندارد. <b>چرا:</b> تا یک حرکت ارزی همهٔ معاملاتت را هم‌زمان نزند.",

  "r.R16.name": "ساعت معاملاتی و اخبار",
  "r.R16.was": "دو کلید جداگانه با یک اثر: یک بازهٔ زمانی مجاز، و قفل خبری که خودت می‌گذاری. هر دو جداگانه خاموش‌شدنی‌اند — به همین دلیل اینجا «اختیاری» نوشته شده.",
  "r.R16.bsp": "در بازهٔ قفل‌شده معاملهٔ تازه‌ای شکل نمی‌گیرد، سفارش‌های در انتظار حذف می‌شوند، و معامله‌ای که بیرون از زمان مجاز پدید آمده دوباره بسته می‌شود. ساعتِ ملاک، ساعت <b>کارگزار</b> توست، نه ساعت خودت.",

  "r.R23.name": "تأیید ریسک هفتگی",
  "r.R23.was": "پیش از نخستین سفارش هر هفته باید <b>ریسک هر معامله</b> را در پنل وارد کنی و با SETZEN تأیید. تا وقتی این کار نشده، هیچ معامله‌ای باز نمی‌شود — نه با کلیک، نه از مرورگر.",
  "r.R23.bsp": "دکمه‌های خرید و فروش تا تأیید تو خاکستری می‌مانند. این با <b>هر چرخش هفته</b> تکرار می‌شود. فلسفه‌اش: یک تصمیم آگاهانه در آغاز هفته به‌جای زنجیره‌ای از تصمیم‌های لحظه‌ای در طول آن. معاملات باز ادامه می‌یابند و قابل مدیریت‌اند.",

  "r.R10.name": "بی‌اثر کردن ممکن نیست",
  "r.R10.was": "<b>هیچ</b> دکمه‌ای نیست که قفل را زودتر بردارد. قفل‌ها از راه‌اندازی دوبارهٔ برنامه و حتی از کار افتادن رایانه جان سالم به در می‌برند.",
  "r.R10.bsp": "قفل هستی و متاتریدر را دوباره راه می‌اندازی — قفل سر جایش می‌ماند. پروندهٔ قفلِ حذف‌شده یا آسیب‌دیده به <b>قفل روزانه</b> می‌انجامد، نه به آزادی. <b>سخت‌تر</b> کردن یک مرز ضرر بی‌درنگ اثر می‌کند، <b>شُل‌تر</b> کردنش تازه از چرخش روز بعد. <b>رک بگویم:</b> این تنها روی سروری قفل‌شده که فقط تو به آن دسترسی داری واقعاً دورزدنی نیست.",

  "r.R11.name": "دفترچه",
  "r.R11.was": "هر باز کردن، هر بستن، هر جابجایی حد ضرر یا هدف، هر تلاش ردشده و هر قفل، سطری با <b>دلیل</b> می‌گیرد — با زمان، قیمت، حجم، ریسک و شناسهٔ قانون.",
  "r.R11.bsp": "بعداً می‌خوانی چرا چیزی انجام نشد. هم برای مرور خودت خوب است و هم به‌عنوان سند در برابر پراپ‌فرم. <b>تصویرهای صفحه</b> که ابزار در هر اقدام ذخیره می‌کند هم به این قانون تعلق دارند. آنچه ثبت می‌شود همان است که ابزار سرپرستی می‌کند — نه آنچه بیرون از آن می‌گذرد.",

  "r.R8.name": "حداقل فاصله تا هدف",
  "r.R8.was": "معامله‌ای <b>در جریان</b> را می‌بست که هدفش نسبت به حد ضرر زیادی نزدیک باشد — یعنی ورود را بررسی نمی‌کند، بلکه پس از آن وارد عمل می‌شود. <b>به خواست تو خاموش است.</b>",
  "r.R8.bsp": "هدف خودکار معاملات پنل همچنان دو برابر ریسک است — اما به‌عنوان پیشنهاد، نه شرط.",

  "r.R9.name": "مکث پیش از معامله",
  "r.R9.was": "پس از کلیک روی خرید یا فروش مکثی کوتاه می‌گذاشت، پیش از آنکه سفارش بیرون برود. <b>به خواست تو خاموش است</b> — کلیک بی‌درنگ پیش می‌رود.",
  "r.R9.bsp": "این به معنای بررسی‌نشدن نیست: پس از آن مثل همیشه قفل‌ها، ریسک هفتگی، اجبار حد ضرر، بودجهٔ روزانه و بقیهٔ قوانین تصمیم می‌گیرند.",

  "r.R14.name": "حداقل فاصله میان معاملات",
  "r.R14.was": "گذشتن زمانی حداقلی میان دو ورود را لازم می‌کرد — در سطح کل حساب، نه هر بازار. <b>به خواست تو خاموش است.</b>",
  "r.R14.bsp": "اگر روشن بود فقط ورود تازه رد می‌شد؛ معاملات باز دست‌نخورده می‌ماندند.",

  "r.R15.name": "حداقل فاصلهٔ حد ضرر",
  "r.R15.was": "فاصله‌ای حداقلی میان قیمت و حد ضرر می‌خواست و حجم‌های بسیار کوچک را رد می‌کرد. <b>خاموش است</b>، چون اسکالپ در تایم‌فریم کوتاه به حد ضرر تنگ نیاز دارد.",
  "r.R15.bsp": "آنچه همچنان از تو محافظت می‌کند: حداقل فاصلهٔ سخت کارگزارت و حجم خودکار معامله. <b>محدودیت صادقانه:</b> حالت حدی «حد ضرر بسیار کوچک و سپس یک گپ که بیش از برنامه را می‌برد» دیگر پوشش داده نمی‌شود.",

  "r.R19.name": "کاهش ریسک پس از ضرر",
  "r.R19.was": "ریسک هر معامله را کوچک می‌کرد به‌محض اینکه در روز جاری چند ضرر پیاپی روی شمارنده بنشیند. <b>به خواست تو خاموش است.</b>",
  "r.R19.bsp": "اگر روشن بود فقط <b>حجم</b> پایین می‌آمد — نه قفلی، نه دست زدن به معاملهٔ باز. به این شکل ریسک تو ثابت می‌ماند.",

  "r.R25.name": "بدون معاملهٔ انتقامی",
  "r.R25.was": "معاملهٔ مخالف را بلافاصله پس از یک ضرر می‌بست — اما فقط آنجا که ضرر به تو نسبت داده شود: چون خودت بسته‌ای، یا ابزار به‌خاطر نقض قانون ناچار به بستن شده. <b>به خواست تو خاموش است.</b>",
  "r.R25.bsp": "انضباط اینجا بر دوش مرزهای سخت است: ترمز روزانه، کل و هفتگی، به‌علاوهٔ وقفه و پایان پس از زنجیرهٔ ضرر."
 }

};
