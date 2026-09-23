# Automatisierter RemZ-Trailer

Die Aufnahme-Regie liegt in `godot/cinematics/trailer_director.gd`, die editierbare
Szenenliste in `godot/cinematics/trailer.json`. `tools/trailer.py` startet die
Prozesse, überwacht Fehler und baut aus den markierten Einstellungen die MP4.
Die volle Schnittfolge hat **35 Einstellungen und genau 300 Sekunden** bei 30 oder
60 Bildern pro Sekunde. Ohne Modusangabe wird ausschließlich die Szenenliste ausgegeben.

## Vorbereiten und prüfen

Im Repository-Verzeichnis:

```powershell
python tools/trailer.py
python tools/trailer.py check
python tools/trailer.py verify --quality 0
python -m unittest discover -s tools/tests -p test_trailer.py
```

Die optionale Prüfung des Godot-Aufnahmewegs rendert nur Farbflächen und einen
Testton in einem eigenen Mini-Projekt, kein Gameplay:

```powershell
$env:REMZ_TEST_MOVIE_CLOCK = '1'
python -m unittest discover -s tools/tests -p test_trailer.py
Remove-Item Env:REMZ_TEST_MOVIE_CLOCK
```

Sie prüft zusätzlich, dass Godots OGV-Ausgabe die in der Schnittliste verwendeten
Engine-Framenummern trifft und eine Tonspur enthält.

- `plan` (Standard): zeigt Schnittfolge und Zeiten; startet kein Spiel.
- `check`: lädt und prüft die GDScript-Regie und die Szenendefinitionen; baut keine Map.
- `verify`: führt die Szenen mit einem echten ENet-Host und drei separaten,
  verbundenen Clients ohne Fenster und ohne Bild-/Tonaufnahme aus. Geprüft werden
  unter anderem Bewegung, Waffenfeuer aller Beteiligten, echte Questannahme,
  Pilzaufnahme, legaler Towerbau, Besteigen/Schießen, Feuerwerksverbrauch sowie
  bestätigte Clientbefehle und empfangene Weltsnapshots.
- Der Python-Test prüft den Schnitt zusätzlich mit **künstlich erzeugten
  Farbflächen und einem Testton**: Ladebereich entfernen, Bildfolge, Framezahl,
  Dauer und Tonspur der tatsächlich exportierten MP4.

Godot wird standardmäßig unter `C:/Users/miche/Desktop/Godot.exe` gesucht.
Mit `--godot <Pfad>` lässt sich ein anderer Godot-4.7-Editor angeben. Für die
Aufnahme muss das importierte Godot-Projekt einschließlich seiner Assets vorhanden
sein; `RemZ.exe` ist kein Ersatz für die Editor-Binary.

## Aufnahme und automatischen Schnitt starten

**Erst `record` zeichnet Spielbild und Spielton auf.**

```powershell
python tools/trailer.py record
```

Vorgabe: Fensteranforderung 1920 × 1080, 30 FPS, Grafikprofil 2. Godot bestimmt
die tatsächliche Filmgröße aus dem Viewport; die erste Probe wurde mit 1600 × 900
aufgenommen. Die tatsächlichen Abmessungen stehen in `export-report.json`.
Beispiele:

```powershell
python tools/trailer.py record --fps 60 --resolution 1920x1080
python tools/trailer.py verify --shots tower_placement,tower_operator,team_titan
python tools/trailer.py record --shots studio,wake_on_road
```

Jeder Aufruf erhält einen neuen Ordner unter `artifacts/trailer/`. Es werden nur die
von diesem Aufruf gestarteten Prozesse beendet. Normale Spielstände, Erfolge und
Einstellungen werden nicht gespeichert; auch die einmalige Migration alter
Spielstände wird im Trailer-Modus ausgelassen. Das normale Spiel startet ohne
Trailer-Regie. Es werden keine Spielpakete veröffentlicht oder neu exportiert.

Die Aufnahme schreibt `raw.ogv` mit Godots Movie Maker, einschließlich Spielton.
`edit.json` markiert die behaltenen Framebereiche; Laden, Umbauen und Warten auf
Clients liegen außerhalb dieser Bereiche. FFmpeg schneidet diese Bereiche,
verbindet sie und erzeugt `edit-<Zeitstempel>/RemZ-Trailer.mp4` (H.264/AAC).
Zwischenclips behalten unkomprimierten Ton, damit sich keine AAC-Verzögerung pro
Schnitt aufsummiert. Schlussbild und Ton blenden am Ende aus. Das Rohmaterial bleibt
für weitere Schnitte erhalten.

FFmpeg und FFprobe müssen installiert sein. Das Werkzeug sucht im PATH,
`tools/bin` und einer vorhandenen Overwolf-Installation. Alternativ explizit:

```powershell
python tools/trailer.py record --ffmpeg C:/Tools/ffmpeg.exe --ffprobe C:/Tools/ffprobe.exe
python tools/trailer.py edit --take artifacts/trailer/record-<Zeitstempel>
```

Die drei Clients laufen ohne Grafikfenster. Der Host rendert die Aufnahme.
Die Aufnahmedauer auf dem Rechner darf länger als fünf Minuten sein: Movie Maker
berechnet feste Zeitschritte, unabhängig von der tatsächlichen Rendergeschwindigkeit.
Die Standard-Zeitgrenze beträgt zwei Stunden (`--timeout` in Sekunden).

## Inszenierung und Multiplayer

| Abschnitt | Inhalt |
| --- | --- |
| 0:00–0:39 | KONM-Intro, originales Aufwachen am Weg, Straße, Lager, Vendor/Quest |
| 0:39–1:22 | Pilze, Wald, erste Kämpfe mit Pistole, Schrotflinte, AK und Präzisionswaffe |
| 1:22–2:05 | Krähen, Maisfeld/Labyrinth, Hinterhalt, Waldteich |
| 2:05–3:15 | Team-Reveal, gemeinsame Erkundung, verschiedene Waffen, Towers |
| 3:15–4:09 | Weitere NPCs, Abendstimmung, Titanen und gemeinsamer Titanenkampf |
| 4:09–5:00 | Böller, Raketen, Batterien, gemeinsames Feuerwerk, letzter Kampf, Endbild |

Der Spielstart verwendet `Intro.START` aus dem Spiel. Die Studio-Einstellung benutzt
das vorhandene KONM-Logo und den Original-Introtrack. Ab dem Aufwachen ist auch die
im Spiel sonst weiterlaufende Intro-Musik stumm. Sämtliche Gameplay-Musik einschließlich
Boss- und Hordenmusik wird auf einen stummgeschalteten eigenen Bus geroutet.
Schritte, NPCs, Waffen, Gegner, Explosionen, Feuerwerk und Umgebung bleiben aktiv.
Es gibt keine hinzugefügte Gameplay-Musik oder Sprecherstimme.

Die Figuren erhalten Ausrüstung, Vorräte, Tageszeit und Ausgangspositionen für die
jeweilige Szene. Die ersten Abschnitte zeigen die Perspektive eines einzelnen
Spielers; die drei verbundenen Mitspieler bleiben dort außerhalb des Bilds und
inaktiv. In den Koop-Szenen bewegen sich die aktiven Figuren mit Kollisionen auf
dem Host. Die Clients empfangen den gemeinsamen Weltzustand und senden die
vorgegebenen Aktionen über die regulären `NetSession.command`-RPCs zurück. Die
normalen Regeln entscheiden über Treffer, Munition, Interaktionen, Bau und Zündung.
Die Regie erzeugt keine bloßen Attrappen von Multiplayer-Spielern.

Diese Trennung verhindert, dass Clients bei einer langsamen Offline-Aufnahme der
Filmzeit davonlaufen. Maze-Routen werden aus den tatsächlich begehbaren Zellen
berechnet. Kameraeinstellungen wechseln zwischen Spielerperspektive, Detail,
Seitenansicht, Verfolgung und Übersicht.

## Stand der Probeaufnahme

Die Probe vom 23.09.2026 liegt unter `artifacts/trailer/RemZ-Probeaufnahme-51s.mp4`:
51 Sekunden, 1600 × 900, 30 FPS, H.264 und Stereo-AAC. Sie enthält Studio-Intro,
Aufwachen am Weg, gemeinsames Waffenfeuer, Titanenkampf und Feuerwerk. Der Host
und drei getrennte Clients haben alle Szenen bestanden; 525 Clientaktionen wurden
bestätigt. Gameplay-Musik blieb stumm. Die zugehörige JSON-Datei nennt Rohaufnahme
und Prüfstand.

Die Bildprüfung erfolgte anhand von 20 Standbildern und zusätzlichen großen
Szenenbildern. Danach wurden die Ego-Waffe in Außenkameras ausgeblendet, das
Licht beim Team-Titanen angepasst und die Feuerwerkskamera neu ausgerichtet.
Tonspur, Szenenpegel und Spitzenpegel wurden technisch geprüft; eine Abhörprüfung
fand nicht statt. Insbesondere die Spieleraufstellung beim Titanen und die dunklen
Figuren unter dem Feuerwerk können für den endgültigen Trailer weiter verbessert
werden. Die übrigen Einstellungen des Fünf-Minuten-Trailers wurden bisher ohne
Grafikausgabe geprüft. Einzelne Einstellungen lassen sich mit `--shots` wiederholen.

Technische Grundlage: [Godot Movie Maker](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)
und [MovieWriter](https://docs.godotengine.org/en/stable/classes/class_moviewriter.html).
