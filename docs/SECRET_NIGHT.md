# Secret Nacht · Wave 5

Vor dem ersten Start von Wave 5 pausiert die normale Wellenfolge. Die vierte Welle bleibt abgeschlossen; die fünfte Kampf- und Bosswelle beginnt erst nach der Sidequest. Enter und der Wellen-Cheat können die Quest nicht überspringen.

„Euer Team hat zu viele Pilze gegessen. Ihr hört aus der Ferne einen Klang. Folgt ihm …“

Der Wald wird zur verregneten Nacht. Am nördlichen Waldweg Richtung Oberer Sorchen liegt die Goa-Party, rund 220 Meter von der Feuerstelle entfernt. Leuchtpilze, räumlicher Bass und der GOA-Marker führen zum aktuellen Ziel.

1. Party erreichen.
2. Die Klangtotems in der Reihenfolge Türkis, Pink, Violett mit E aktivieren.
3. An der Nebelbar mit E den fiktiven Klarer-Kopf-Trank holen. Bierflaschen und Pilze gehören zur Partydekoration.
4. Gemeinsam 16 Sekunden im Tanzkreis bleiben; die Zeit pausiert, wenn ein lebender Mitspieler fehlt. Niedergeschlagene Mitspieler blockieren das Finale nicht. Der DJ kündigt den letzten Tanz an (Texteinblendung).
5. Ein 18-sekündiger Abschied folgt: zunächst vier Sekunden für den letzten Beat, danach blenden Musik, Discolichter und Gäste gemeinsam aus. Regen und Pilzverzerrung legen sich. Die Musik stoppt vollständig. Auf der Bühne bleibt „Bis zum nächsten Traum“ zurück; die Leuchtpilze am Weg bleiben zur Orientierung an.
6. **Abschlussauftrag „Das Echo der Nacht“:** Vor dem DJ-Pult bleibt ein kleines, schwebendes Klangtotem zurück. Der ECHO-Marker führt hin. Mit E aufnehmen; danach gehört das Echo dem ganzen Team, unabhängig von Inventarplatz, Tod oder Verbindungsabbruch. Ohne das Echo ist der Abschluss am Lager gesperrt.
7. Dem Heimweg-Marker zur Feuerstelle folgen. Erst wenn alle lebenden Mitspieler im Umkreis von 14 Metern versammelt sind, legt E das Echo ins Feuer. Die normale Welle bleibt bis dahin gesperrt.
8. Acht Sekunden gemeinsam am Feuer durchatmen, während das Totem im warmen Licht verglüht und verschwindet. Ein warmer Bildübergang begleitet die Rückkehr der ursprünglichen Tageszeit. Geht jemand weg, wartet der Fortschritt. Danach erhält jeder verbundene Spieler einmalig 150 Rem Dollars. Alle Party-Effekte verschwinden, die normale Musik kehrt zurück und 20 Sekunden Vorbereitungszeit führen in den regulären Kampf von Wave 5.

Die Quest ist pro Runde einmalig. Fortschritt, Abschiedszeit und Aufwachzeit werden vom Host verwaltet und über den vorhandenen Welt-Snapshot an Clients und später beitretende Spieler übertragen. Wer während des Heimwegs beitritt, hört keine neu gestartete Party. Die Belohnung wird ausschliesslich vom Host vergeben und lässt sich durch wiederholtes E oder Snapshots nicht verdoppeln. Interaktionen benötigen Nähe zum aktuellen Ziel. Bei Spielende werden die Effekte ohne Belohnung abgeräumt. Die Kamerasteuerung bleibt unverändert; die Solo-Pause hält auch den Abschied an.

## Ablauf in der langen Fassung (25. September 2026)

1. **Der ferne Klang** – dem Bass und den leuchtenden Pilzen zum Oberen Schorchen folgen.
2. **Klangtotems** – Türkis, Pink, Violett in dieser Reihenfolge mit E wecken.
3. **Leuchternte** – drei leuchtende Pilze rund um die Tanzfläche pflücken (E), der Barkeeper will sie.
4. **Der Pilz des DJ** – an der Bar essen: das ganze Team halluziniert 18 Sekunden (die Sicht schwimmt, Farben verschieben sich).
5. **Farbenlauf** – vier Runden: der DJ ruft eine Farbe, das Totem blitzt, das Team muss es innerhalb von zehn Sekunden erreichen. Zu langsam heisst von vorn.
6. **Klarkopf** – der Drink an der Bar beendet den Rausch.
7. **Ein letzter Tanz** – 16 Sekunden mit allen Lebenden im leuchtenden Kreis.
8. **Ungebetene Gäste** – der Bass weckt acht Tote rund um die Tanzfläche; die Fläche muss geräumt werden.
9. **Letzter Track**, **Echo der Nacht**, **Der Weg nach Hause**, **Zurück in die Realität** wie bisher. Belohnung 250 R pro Spieler.

Der Tanzkreis liegt bei (-108, -192), drei Meter vor der Bühnenkante; die Tänzer standen vorher im DJ-Pult.

## Song einsetzen

Der eingebundene Song ist `godot/assets/audio/music/Goa_Party_Sidequest.mp3` und wird geloopt. Nur bei fehlender Datei greift der selbst erzeugte Guide `secret_goa_placeholder.wav`. Nach einem Austausch den Windows-Build erneut exportieren. Die Lichtbewegung hat derzeit ein festes Tempo von 140 BPM.

Der räumliche Player steht an der Bühne. Jeder Spieler hört seinen eigenen Entfernungs-Mix: bis zwölf Meter voller Klang bei −7 dB, ab 280 Metern ein ferner Beat bei −35 dB und 1,1 kHz Tiefpass. Dazwischen steigen Lautstärke und Höhen weich an; beim Weggehen nehmen sie wieder ab. Bereits vor dem ersten Ton wird die Startentfernung angewendet. Ein eigener Audio-Bus filtert ausschliesslich den Goa-Track und wird beim Verlassen der Szene entfernt. Die globale Lautstärkeeinstellung bleibt wirksam.

## Assets und Nachweise

Meshy erzeugt Bühne inklusive Lautsprechern und DJ-Pult, Nebelbar sowie Klangtotem. `tools/meshy_secret_night.py` kann die Generierung anhand ihrer gespeicherten Task-IDs wiederaufnehmen. Originale, Thumbnails und Task-Belege liegen unter `meshy_output/raven_melee/goa_stage`, `goa_bar`, `goa_totem`; eingebundene GLBs unter `godot/assets/models/`. Gäste, DJ und Barkeeper verwenden vorhandene Meshy-NPCs. Regen, bewegte Lichter und die leichte Bildschirmverzerrung werden in Godot erzeugt.

## Prüfen

`Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=secret_night --no-intro --no-music`

Mit `--visual` ohne `--headless` schreibt dieselbe Suite zusätzlich `artifacts/secret-night-farewell.png` und `artifacts/secret-night-echo.png`. Sie prüft Sperre und Wiederaufnahme der Wellen, Reihenfolge und Entfernung der Interaktionen, Team-Präsenz, Distanz-Audio, tatsächliches Ende von Musik/Regen/Lichtern, Solo-Pause, späten Beitritt, gemeinsames Aufnehmen und Zurückbringen des Echos, einmalige Belohnung und Wiederherstellung der Uhrzeit.
