' ============================================================================
'  Mamal-Trading Cockpit - Autostart (unsichtbar, kein Fenster)
' ============================================================================
'  WOHIN DAMIT: NICHT diese Datei in den Autostart-Ordner kopieren, sondern
'  eine VERKNUEPFUNG darauf. Dann bleibt die Datei hier im Repo die einzige
'  Fassung, und eine Korrektur wirkt ueberall.
'
'    Autostart-Ordner oeffnen:  Windows+R  ->  shell:startup
'    Rechtsklick auf diese Datei -> Verknuepfung erstellen -> dorthin ziehen.
'
'  WARUM NICHT KOPIEREN: Die bisherige Fassung lag NUR im Autostart-Ordner
'  und nicht im Repo - mit fest eingetragenem Pfad auf einen bestimmten PC.
'  Beim Umzug auf den VPS waere sie weggeblieben, und niemand haette es
'  bemerkt, bis nach dem ersten Neustart kein Schutz mehr lief. Dasselbe
'  Muster wie bei jscheck.py, das in einem Sitzungsordner lag und weg war,
'  als es gebraucht wurde.
'
'  Diese Fassung findet server.js neben sich selbst - sie laeuft also auf
'  jedem Rechner, ohne dass ein Pfad angepasst werden muss.
'
'  AUTOSTART ENTFERNEN: die Verknuepfung im Autostart-Ordner loeschen.
'
'  WICHTIG ZUM ERWARTUNGSRAHMEN: Autostart heisst "startet nach dem Anmelden".
'  Startet die Maschine neu und es meldet sich NIEMAND an, laeuft weder
'  MetaTrader noch dieses Cockpit - der Schutz ist dann aus, ohne Warnung.
'  Auf einem Server gehoert darum eine automatische Anmeldung dazu.
' ============================================================================

On Error Resume Next
Dim sh, fso, dir, srv, i
Set sh  = CreateObject("Wscript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Der eigene Ordner - aufgeloest ueber den Pfad DIESER Datei, nicht ueber die
'   Verknuepfung, die auf sie zeigt. Damit ist der Pfad nirgends eingetragen.
dir = fso.GetParentFolderName(WScript.ScriptFullName)
srv = fso.BuildPath(dir, "server.js")

' Liegt das Projekt in OneDrive, ist der Ordner beim Anmelden womoeglich noch
'   nicht eingehaengt. Bis zu zwei Minuten warten. Auf einem Server ohne
'   OneDrive ist die Datei sofort da und die Schleife endet beim ersten Durchlauf.
For i = 1 To 24
  If fso.FileExists(srv) Then Exit For
  WScript.Sleep 5000
Next

If fso.FileExists(srv) Then
  ' Kein Browser-Fenster beim Anmelden. Der Klick-Ausloeser im EA-Panel
  '   oeffnet das Cockpit weiterhin, wenn man es braucht.
  sh.Environment("PROCESS")("MAMAL_QUIETSTART") = "1"
  sh.CurrentDirectory = dir
  sh.Run "cmd /c node server.js", 0, False
End If
