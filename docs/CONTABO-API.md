# Contabo-API — verbinden und abfragen

**Stand: 15.11.2026.** Alles hier stammt aus `openapi.json` (Contabo API 1.0.0, 105 Endpunkte,
`https://api.contabo.com`) bzw. aus Contabos eigener Dokumentation. Wo etwas nicht belegt ist,
steht es dabei.

---

## 0. Zuerst: zwei Dinge, die leicht verwechselt werden

| | Contabo-API | RDP + Cockpit |
|---|---|---|
| Zeigt | **die Maschine von außen** | **was drinnen passiert** |
| Also | Läuft sie? Welche IP? Snapshots, Neustart, Aufrüstung | Konten, Equity, Regeln, Trades |
| Brauchst du für | Überwachung, Notfall, Automatisierung | den täglichen Betrieb |

**Die API sieht deine Handelsdaten nicht.** Sie weiß nicht, ob MetaTrader läuft oder ob der EA
etwas blockiert hat — nur ob der Server an ist. Für die Handelsdaten brauchst du RDP bzw. das
Cockpit im Browser; das steht in der Umzugsanleitung (nicht veröffentlicht) und
[../cockpit/REMOTE-ACCESS.md](../cockpit/REMOTE-ACCESS.md).

Beides zusammen ergibt aber Sinn: Die API beantwortet „ist die Maschine überhaupt wach?", das
Cockpit „tut sie, was sie soll?".

---

## 1. Zugangsdaten holen

Im Kundenbereich: **<https://my.contabo.com/api/details>**

Dort stehen `client_id` und `client_secret`, und dort setzt du auch das **API-Passwort** (das ist
*nicht* dein Panel-Passwort und *nicht* das Windows-Passwort — ein eigenes, drittes).

Du brauchst vier Werte:

| Wert | Woher |
|---|---|
| `client_id` | my.contabo.com/api/details |
| `client_secret` | ebenda |
| `username` | die E-Mail-Adresse deines API-Benutzers |
| `password` | das API-Passwort, das du dort setzt |

> **Diese vier Werte sind Zugangsdaten.** Nicht ins Repo, nicht in eine Datei im Projektordner,
> nicht in eine Chat-Nachricht. Wer sie hat, kann deinen Server neu starten, neu aufsetzen und
> löschen.

## 2. Einmal pro Sitzung in Umgebungsvariablen legen

So stehen sie nirgends in einer Datei. PowerShell:

```powershell
$env:CNTB_CLIENT_ID     = "<deine client_id>"
$env:CNTB_CLIENT_SECRET = "<dein client_secret>"
$env:CNTB_USER          = "<deine API-E-Mail>"
$env:CNTB_PASS          = "<dein API-Passwort>"
```

Beim Schließen des Fensters sind sie wieder weg. Genau so soll es sein.

## 3. Token holen

```powershell
$body = @{
  client_id     = $env:CNTB_CLIENT_ID
  client_secret = $env:CNTB_CLIENT_SECRET
  username      = $env:CNTB_USER
  password      = $env:CNTB_PASS
  grant_type    = "password"
}
$tok = (Invoke-RestMethod -Method Post -Body $body -Uri "https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token").access_token
```

Das Token läuft nach einigen Minuten ab — dann diesen Block einfach erneut ausführen.

## 4. Eine Hilfsfunktion, die den Pflicht-Header mitbringt

Jeder Aufruf braucht **zwei** Header: `Authorization: Bearer …` und ein **`x-request-id`**, und
das muss eine **frische UUID bei jedem einzelnen Aufruf** sein. Darum eine kleine Funktion statt
dem Header von Hand:

```powershell
function cntb($pfad) {
  $h = @{ Authorization = "Bearer $tok"; "x-request-id" = [guid]::NewGuid().ToString() }
  Invoke-RestMethod -Uri "https://api.contabo.com$pfad" -Headers $h
}
```

## 5. Die Abfragen, die du wirklich brauchst

**Alle Instanzen auflisten — Name, Status, IP:**
```powershell
(cntb "/v1/compute/instances").data | Select-Object instanceId, displayName, status, @{n='ip';e={$_.ipConfig.v4.ip}}, productId, region
```

**Eine Instanz im Detail** (`<ID>` aus der Liste oben):
```powershell
(cntb "/v1/compute/instances/<ID>").data | Format-List
```

**Nur der Status — die Frage „läuft sie?":**
```powershell
(cntb "/v1/compute/instances").data | ForEach-Object { "$($_.displayName): $($_.status)" }
```

**Snapshots ansehen:**
```powershell
(cntb "/v1/compute/instances/<ID>/snapshots").data | Select-Object snapshotId, name, createdDate
```

**Was in letzter Zeit mit dem Server gemacht wurde** (nützlich nach einem unerwarteten Neustart):
```powershell
(cntb "/v1/compute/instances/actions/audits").data | Select-Object -First 10 changedBy, action, requestedAt
```

---

## 6. Der Weg zurück, wenn das Windows-Passwort weg ist

**Korrektur zu dem, was ich dir vorher gesagt habe.** Ich hatte behauptet, Contabo könne ein
Windows-Administrator-Passwort nicht zurücksetzen und du hättest nur diesen einen Schlüssel.
Über das **Panel** stimmt das — über die **API nicht**. Die Spezifikation sagt zum Feld
`rootPassword` wörtlich:

> *„secretId of the password for the defaultUser with administrator/root privileges.
> For Linux/BSD please use SSH, **for Windows RDP**."*

Es geht in zwei Schritten, weil das Passwort nicht direkt übergeben wird, sondern erst als
*Secret* hinterlegt werden muss:

**Schritt 1 — Passwort als Secret anlegen:**
```powershell
$h = @{ Authorization = "Bearer $tok"; "x-request-id" = [guid]::NewGuid().ToString(); "Content-Type" = "application/json" }
$neu = @{ name = "vps-admin-neu"; value = "<neues starkes Passwort>"; type = "password" } | ConvertTo-Json
$sec = Invoke-RestMethod -Method Post -Uri "https://api.contabo.com/v1/secrets" -Headers $h -Body $neu
$sec.data.secretId
```

**Schritt 2 — zurücksetzen:**
```powershell
$h = @{ Authorization = "Bearer $tok"; "x-request-id" = [guid]::NewGuid().ToString(); "Content-Type" = "application/json" }
$req = @{ rootPassword = <secretId aus Schritt 1> } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://api.contabo.com/v1/compute/instances/<ID>/actions/resetPassword" -Headers $h -Body $req
```

> **Ungetestet.** Ich habe das nicht ausgeführt — dafür bräuchte ich deine Zugangsdaten, und die
> fasse ich nicht an. Probiere es **nicht** zum Spaß an einem laufenden Produktivserver aus; es
> ist der Notfallweg, nicht der Alltagsweg. Das Passwort gehört weiterhin in den Passwortmanager.

---

## 7. Was du über die API NICHT machen solltest

Die API kann auch `reinstall`, `cancel` und `rollback` auf einen Snapshot. Das sind Befehle, die
deinen Handelsrechner in Sekunden leeren.

- **`reinstall`** löscht alles auf der Maschine.
- **`rollback`** setzt sie auf einen Snapshot zurück — alle Journaleinträge und Equity-Punkte seit
  dem Snapshot sind dann weg.
- **`cancel`** kündigt den Vertrag.

Diese drei gehören nicht in ein Skript, das irgendwann aus Versehen läuft. Wenn du sie brauchst,
klick sie bewusst im Kundenbereich.

---

## 8. Sinnvolle Verwendung im Alltag

Die eine Abfrage, die wirklich etwas bringt, ist der Status — zusammen mit dem Cockpit:

```powershell
# läuft die Maschine?
(cntb "/v1/compute/instances").data | ForEach-Object { "$($_.displayName): $($_.status)" }
```

```powershell
# ...und tut sie auch etwas? (Cockpit über deinen VPN-Zugang)
(Invoke-RestMethod "http://<vps>:8730/state?acct=<Kontonummer>").state | Select-Object account, status, equity, posCount
```

Die erste Zeile beantwortet „ist der Rechner an", die zweite „läuft der Schutz". **Beide braucht
man** — eine laufende Maschine mit ausgeschaltetem AutoTrading sieht in der API tadellos aus.

---

*Verwandt: [../cockpit/REMOTE-ACCESS.md](../cockpit/REMOTE-ACCESS.md)*
