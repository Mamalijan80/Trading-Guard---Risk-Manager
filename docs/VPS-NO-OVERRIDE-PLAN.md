# VPS / „No-Override" — Plan & ehrliche Grenzen

**Stand: 2026-07-08.** Recherchiert (Mehr-Agenten-Workflow) + zentrale Fakten direkt bei FTMO verifiziert. Frage war: *„Wie erreichen wir, dass das Konto die Limits hat und der Nutzer sie nicht durch AutoTrading-aus umgeht?"*

---

## 0. Kernbefund (der alles entscheidet)

FTMOs **Forbidden Trading Practices** verbieten **wörtlich**:

> „You must not allow any **third party to access or otherwise use your FTMO Account** or your FTMO Challenge/Verification account."
> „…nor **engage or cooperate with any third party** in order to have such a third party perform simulated trades for you or in coordination with you."
> — Quelle (2026-07 verifiziert): <https://ftmo.com/en/forbidden-trading-practices/>

**Echtes „No-Override" verlangt zwingend, dass jemand/etwas AUSSER dir die Durchsetzung kontrolliert** (Accountability-Partner hält VPS-Admin + Broker-Passwort; oder ein externer Dienst greift aufs Konto zu). **Genau das verbietet FTMO.**

➡️ **Auf einem FTMO-Konto ist echtes No-Override regelkonform NICHT möglich** — nicht wegen unseres Tools, sondern weil FTMO fordert, dass **nur du** Zugriff hast. Wer allein Zugriff hat, kann sich auch immer selbst entsperren (AutoTrading aus). Das ist eine direkte Folge der FTMO-Regeln, kein Bug.

**Der einzige wirklich unumgehbare Konto-Boden auf FTMO ist FTMOs eigenes Server-Limit (5 % Tag / 10 % gesamt).** Deine engeren Limits (2 %/6 %) können auf FTMO nur eine **selbst auferlegte Disziplin-Hilfe** sein — von dir umgehbar.

---

## 1. Was auf FTMO ERLAUBT ist (verifiziert)

| Thema | Status | Quelle |
|---|---|---|
| Eigener **VPS** | erlaubt (nicht verboten, FTMO ist VPS-freundlich) | — |
| Eigene **EA/Automation** (deine eigene Strategie) | erlaubt, **solange < 2.000 Server-Requests/Tag** (keine „hyperaktiven" EAs) — unser EA liegt normal weit darunter | ftmo.com/forbidden-trading-practices |
| **Dritt-Zugriff** aufs Konto / koordiniertes Handeln | **VERBOTEN** | ftmo.com/forbidden-trading-practices |
| „Unfair-Vorteil"-Software | verboten (betrifft uns nicht — Risiko-Tool, kein Vorteil) | dito |

➡️ Ein **eigener VPS mit deiner eigenen Risiko-EA** ist erlaubt und sinnvoll (Stabilität + „immer an" behebt die Wine-Crashes **und** die FTMO-Mitternachts-Basis-Anforderung). Was *nicht* geht: dass ein Partner/Dienst das Konto kontrolliert.

---

## 2. Wo echtes No-Override SEHR WOHL geht

Auf einem **eigenen Broker-Konto oder einer Demo, die dir gehört** (kein Prop-Challenge) gilt die Dritt-Zugriff-Regel nicht. Dort kannst du den vollen **„Ulysses-Vertrag"** bauen. **Ideal, um die Disziplin-Gewohnheit zu trainieren** — parallel/vor FTMO.

---

## 3. Technische Bausteine (recherchiert — greifen nur auf Eigen-/Demo-Konto als echtes No-Override)

- **MT4 headless als Windows-Dienst** (Session-0-Isolation, GUI für keinen Nutzer sichtbar; z. B. AlwaysUp). Einen AutoTrading-Knopf, den du nicht siehst, kannst du nicht ausschalten. **Kehrseite:** durch diese MT4 kannst du dann auch nicht mehr manuell handeln → Order-Eingabe muss über einen separaten Kanal (das Cockpit). Quelle: coretechnologies.com (MT4 as a Service).
- **Windows-Kiosk (Assigned Access)** geht bei MT4 NICHT (nur UWP/Edge) und **nicht über RDP**; nur „Shell Launcher" (Windows Enterprise/Education) — und selbst der stoppt nicht das Umschalten *innerhalb* einer laufenden MT4. → Der praktikable Lockdown ist **headless-Dienst + Nicht-Admin-Konto + NTFS-ACLs**, nicht Kiosk. Quelle: learn.microsoft.com.
- **DLL-freie Datei-Brücke** (DWX-Connect-Muster — passt exakt zu unserer bestehenden `MQL4/Files`-JSON-Brücke): Cockpit schreibt Order-Kommando-Datei → EA liest + `OrderSend` **mit SL/TP zusammen**. Kein DLL nötig. (ZeroMQ wäre schneller, braucht aber `libzmq/libsodium`-DLLs = Compliance-/Sicherheits-Risiko.) Quelle: github.com/darwinex/dwxconnect.
- **Investor-Passwort** (read-only, **server-erzwungen**): du siehst dein Konto (Charts/Positionen), kannst außerhalb des Cockpits nichts platzieren/schließen. Quelle: ea-coder.com.
- **Master-Passwort = der ganze Hebel:** MT4 erlaubt dasselbe Konto in mehreren Terminals gleichzeitig → wer das Master-Passwort hat, öffnet ein 2. Terminal und umgeht alles. No-Override reduziert sich damit auf **Master-Passwort-Geheimhaltung** (nur auf dem VPS, nie bei dir). **Genau das ist auf FTMO verboten, auf Eigen-Konto erlaubt.** Quelle: ea-coder.com.
- **Pre-Execution-Block** muss im Cockpit/Relay sitzen (nicht nur im EA), weil ein EA nur Orders sieht, die durch *sein* Terminal laufen. SL/TP bei Market-Orders ist nicht immer atomar → „Fill ohne Stop" = Notfall-Close nötig. Quelle: docs.mql4.com/trading/ordersend.

---

## 4. Empfehlung (für dich: solo, FTMO-Ziel, Mac)

1. **Realität akzeptieren:** Auf FTMO ist das Tool eine **Disziplin-Hilfe** (selbst auferlegt, selbst widerrufbar). Harter Boden = FTMOs 5 %/10 %. Intern darunter puffern (2 %/6 %).
2. **Accountability-/Alarm-Schicht bauen (REGELKONFORM):** Der EA meldet sofort, wenn du den Schutz abschaltest/entfernst → Cockpit-Banner „SCHUTZ AUS seit …" + Alarm an einen Partner (Telegram/E-Mail). Der Partner **empfängt nur Alarme, greift NIE aufs Konto zu** → kein Dritt-Zugriff → **erlaubt**. Das ist der wirksamste *erlaubte* Hebel (soziale Bindung statt technischer Zwang).
3. **Eigener VPS für Stabilität** (behebt Wine-Crash **und** liefert die durchlaufende Mitternachts-Basis) — erlaubt.
4. **Voller No-Override nur auf Demo/Eigen-Konto** — dort trainierst du „ich kann mich nicht selbst austricksen" ohne FTMO-Regeln zu verletzen.

---

## 5. Vor JEDER Umsetzung schriftlich bei FTMO klären

- Darf ein Accountability-Partner das Master-Passwort / VPS-Admin halten? *(Wortlaut sagt: nein — schriftlich bestätigen lassen.)*
- Sind externe Order-Bridges (MetaApi/MTsocketAPI etc.) erlaubt oder „Dritt-Zugriff/automatisiert"?
- Sind DLL-EAs (libzmq) erlaubt, oder nur die DLL-freie Datei-Brücke?
- Gibt FTMO ein **Investor-Passwort** für MT4 aus (server-abhängig)?
- Ist ein „Cockpit-gated, kein manueller Override"-Relay akzeptabel, oder gilt das Vorfiltern deiner eigenen Orders als koordiniert/Dritt?

---

## 6. Fazit in einem Satz

**„Das Konto hat die Limits und ich komme nicht ran" ist auf FTMO strukturell unmöglich** (ihre Regeln fordern Allein-Zugriff). Erreichbar & regelkonform: **FTMOs Server-Limit als Boden + Alarm-Accountability + eigener VPS für Stabilität**. Den echten Selbst-Aussperr-Mechanismus baust du auf einem **eigenen/Demo-Konto**.
