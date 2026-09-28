# The Planes – Remetschwil

In der Gebietsauswahl **The Planes erkunden** wählen. Die Region startet als eigenständige Erkundungsmap im Einzelspiel. Im Esc-Menü lässt sich zusätzlich ein Survival-Durchlauf mit 25 Wellen starten. Forest behält seinen Survivalablauf. Im Koop ist der Erkundungsstart gesperrt.

WASD bewegt den Spieler; Shift sprintet, Leertaste springt, Strg duckt sich. M blendet die nordorientierte Karte ein oder aus. Escape öffnet ein Menü mit Fortsetzen, Survivalstart, drei Referenzblickrichtungen und Rückkehr zur Gebietsauswahl. Im Kampf pausiert dieses Menü auch Zombies, Wetter und Granaten; die Foto-Teleports sind dort gesperrt. Die Fotoansichten lassen sich damit ohne erneuten Fussmarsch vergleichen.

## Geografische Grundlage

- Referenzpunkt: **47.404384449011665, 8.335047115511859** ([Google Maps](https://www.google.com/maps?q=47.404384449011665,8.335047115511859)). Der interaktive Google-Viewer war beim Aufbau nicht auslesbar; die fünf vom Nutzer bereitgestellten Bilder bilden die visuelle Referenz.
- Lokales Koordinatensystem: LV95, X ostwärts, Z südwärts, Y relativ zum Referenzpunkt. Eine Spieleinheit entspricht einem Meter. Der geografische Ursprung liegt bei LV95 E 2667663.52 / N 1250782.42 (swisstopo-Polynomumrechnung).
- [swissALTI3D](https://www.swisstopo.admin.ch/de/hoehenmodell-swissalti3d): 0,5-m-Ausgangsraster des verfügbaren Jahrgangs 2021, auf ein 1-m-Spielraster abgetastet. Der Hintergrund verwendet 2-m-Quelldaten und ein 10-m-Spielraster. Die Daten werden nicht in der Höhe skaliert oder für Wege künstlich eingeebnet.
- Referenzhöhe 570,72 m ü. M.; Weggabelung Rigiweg etwa 557,4 m; Anschluss Richtung Sennhof etwa 655,2 m. Der Gelände-Ausschnitt misst 890 × 700 m. Die begehbare Grenze liegt acht Meter innerhalb des Terrainrasters.
- [OpenStreetMap](https://www.openstreetmap.org/copyright): Wege und Gebäudegrundrisse aus einem Umkreis von 1200 m. Hauptweg OSM 54857308, Rigiweg 56070837, südlicher Feldweg 118083377. Die grosse Fotogabelung liegt rund 115 m westlich des gesetzten Referenzpunkts.
- [SWISSIMAGE / swisstopo](https://www.swisstopo.admin.ch/de/orthobilder-swissimage-10): Luftbildabgleich für Parzellen und Gehölzstreifen. Das Luftbild wird nur als Baugrundlage verwendet, nicht als flache Spieltextur.

Quellen-URLs, Rasterauflösungen und SHA-256-Prüfsummen stehen in `godot/assets/planes/sources.json`. Bezug am 28. September 2026. © swisstopo; © OpenStreetMap-Mitwirkende, ODbL.

## Bildrekonstruktion und Grenzen

Die sommerliche Mais-/Getreidebelegung folgt den Fotos; sie ist keine Aussage zur heutigen Fruchtfolge. Parzellengrenzen, die Baumreihe westlich am Rigiweg und die beiden Gehölzgruppen wurden mit dem Luftbild abgeglichen. Baumhöhen, Kronenformen und Gebäudefassaden sind angenähert. Die Dorfkulisse nutzt vorhandene Fassadenbausteine auf OSM-Grundrissen. Die kleinen Markierungen an der Maisecke sind geometrisch angedeutet; unlesbare Beschriftungen wurden nicht erfunden. Eine vermessene, fotogrammetrische 1:1-Reproduktion sämtlicher sichtbarer Objekte ist damit nicht erreicht.

Mais verwendet unverändert die vorhandenen `assets/cornfield/corn_*.res` mit Wind und drei Detailstufen. Diese vorhandenen Maisressourcen sind im Projekt erzeugte Meshes. Raben/Eulen verwenden die vorhandenen Meshy-Modelle `raven_real.glb` / `owl_real.glb`, bestehende Animationen und Rufe; Eulen bleiben in der sommerlichen Mittagsansicht verborgen. Gehölze nutzen die vorhandenen Meshy-Modelle `tree_autumn_a.glb` und `tree_autumn_b.glb` mit einem eigenen sommergrünen Material; das Original bleibt unverändert. Gras nutzt den vorhandenen Atlas. Da kein Getreidemodell vorhanden ist, ergänzt ein natives, instanziertes Halmen-/Ährenmesh die Bibliothek. Es wurden keine neuen Meshy-Generierungen beauftragt.

Terrain, Pflanzen und Weltkoordinaten verwenden dieselben Höhen. Pflanzen sind räumlich gebündelt; Nah-/Fernmeshes werden kameranah gewechselt. Wege bleiben frei. Bäume besitzen Stammkollision, Häuser blockierende Grundrisskörper, Gelände einen Höhenfeld-Collider. Die Erkundung verwendet den bestehenden Spielercontroller einschliesslich Schritten auf Kies, Gras und Mais.

## Reproduzieren und prüfen

```powershell
python tools/planes_geo.py
python tools/build_planes.py
# Anschliessend Godot-Import ausführen.
Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=planes --smoke-test
Godot.exe --path godot --windowed --resolution 1600x900 --script res://tests/run.gd -- --suite=planes --smoke-test --render-planes --quality=2
```

`--planes-roundtrip --no-intro --no-music` ergänzt den tatsächlichen Rückweg in die Forest-Gebietsauswahl. Die Suite prüft Regionsdatenwechsel, friedlichen Einstieg, Höhen, Terrainkollision, freie Wege, vorhandene Modelle, tatsächliche Bewegung und Menübedienung. Referenzbilder und Luftbildüberlagerung entstehen unter `artifacts/planes/`. Zusätzlich die bestehenden Suiten `compile_all` und `campaign_map` ausführen. Tests sollten mit isoliertem `APPDATA` unter `.test-user` laufen.

Der Windows-Export enthält die eigenen JSON-/Höhenraster durch die ergänzte Export-Inklusion. Der Einstieg kann für eine direkte Ortsprüfung auch mit `--path godot res://scenes/planes.tscn` erfolgen. Die fertige EXE unterstützt `RemZ.exe -- --explore-planes`; der normale Einstieg bleibt die Gebietsauswahl.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Rendered -RoundTrip
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Packaged
```

## Landschaft und Leistung, 28. September 2026

Die Gebietsauswahl öffnet ohne vorgewähltes Gebiet. Gras wurde von rund einer auf zwei instanzierte Büschel pro Quadratmeter erhöht. 401 statt 308 Bäume, vorhandene fotografische Blattkarten, Rindendetails und 7004 Unterwuchsbüschel verdichten die Gehölze. Ein eigenes Laub-/Bodenmaterial ersetzt den zu hellen Waldboden; Kies bleibt auf der Wegmaske.

Die Dorfhäuser folgen nun den tatsächlichen OSM-Polygonen mit einzelnen Dachflächen. Überlappende gedrehte Begrenzungsboxen und gestapelte Dachplatten verursachten vorher Tiefenkonflikte. Auch Kollisionen und Navigationshindernisse folgen den zerlegten Grundrissen.

24-m-Baumzellen, vereinfachte Schattenmeshes aus den bestehenden Meshy-Modellen und ausgedünnte entfernte Mais-/Getreideinstanzen sparen Geometrie. Die zufällige Instanzreihenfolge hält auch die reduzierten Felder flächig bedeckt. `tools/planes_tree_lods.mjs` reproduziert die Schattenmodelle.

Grafikvergleich: RTX 3060 Ti, High quality, 1920 × 1009, VSync/Limit aus, dieselben fünf Kamerapositionen, je 3 s Aufwärmen und 200 gemessene Frames. Erkundung vor/nach der Landschaftsänderung:

| Ansicht | Vorher FPS | Nachher FPS | Nachher p95 ms |
|---|---:|---:|---:|
| Sennhof | 42.58 | 91.80 | 11.27 |
| Gabelung | 45.17 | 102.26 | 10.14 |
| Core | 73.48 | 105.79 | 9.86 |
| Gehölz | 55.97 | 126.47 | 8.29 |
| Dorf | 140.90 | 167.88 | 6.38 |

Messdaten und Bilder: `artifacts/planes/performance/before.json` und `graphics3.json`. Das sind Messungen auf dieser Maschine, keine Garantie für unveränderte FPS auf jeder Hardware.

Zusätzlicher Belastungstest mit 24 aktiven Gegnern aus Welle 25 und sichtbarer Waffe: 74–127 FPS bei klarem Wetter, 74–127 FPS im Gewitter, p95 zwischen 8.49 und 13.70 ms. Gemessen separat ohne parallele Testprozesse (`combat-clear.json`, `combat-storm.json`). Gegner, Waffen und Wetter haben zusätzliche Renderkosten gegenüber der verbesserten leeren Erkundungsmap; ein pauschaler FPS-Gleichstand für jede Situation wird nicht behauptet.

## Survival-Grundlage

Exploration startet ohne Gegner. **Esc → Start 25-wave survival** lädt die Navigation und gemeinsamen Zombie-/Waffenmodelle hinter dem Ladebildschirm. 1/2/3 wechseln Pistole/AK-47/Schrotflinte; R lädt nach, G wirft eine Granate, H schlägt, rechte Maustaste zielt. Enter überspringt die Start-/Zwischenpause. Bei jedem dritten Abschuss fällt ein vorhandenes Munitionspaket. Nach jeder Welle werden Gesundheit, Munition und drei Granaten aufgefüllt; E erlaubt einmal pro Welle die Selbstwiederbelebung.

Der Gegnerplan wächst über 25 Wellen, mit Läufern, Krankenschwestern, Soldaten und jeder fünften Welle Brutes. Höchstens 24 lebende Gegner gleichzeitig (bei hoher gemessener Framezeit 16), höchstens zwölf Leichen. Spawns werden auf Erreichbarkeit, Abstand und freie Kollision geprüft. Erst wenn Warteschlange und lebende Gegner leer sind, zählt eine Welle. Runde 25 speichert den Planes-Kampagnenabschluss; danach folgen Neustart, Erkundung oder Kartenauswahl.

Das Sommerwetter wechselt innerhalb eines 16-Minuten-Zyklus zwischen klar, Nebel, Regen und Gewitter. Es verwendet die vorhandenen Regen-/Nässe-/Blitz-/Donnersysteme mit Distanznebel. Quests, Barrikaden, Türme und NPCs sind nicht Bestandteil dieser Map. Die spätere besondere Spielmechanik bleibt offen.

Zusätzliche Tests: `--suite=planes_navigation`, `--suite=planes_survival`, `--suite=planes_perf --planes-perf=label`. Für den Belastungstest ergänzt `--planes-combat-perf` eine volle 24er-Horde aus Welle 25; `--planes-storm-perf` aktiviert Gewitter. Der Survivaltest beschleunigt die Wellenfolge und prüft alle 25 Zustandsübergänge mit echten Gegnern; er ist kein vollständig ausgespielter 25-Wellen-Durchlauf.

Geprüft: 333 Skripte kompiliert; 42 Kampagnenprüfungen; 24 Erkundungs-/Regionswechselprüfungen; 33 Survivalprüfungen mit Renderer und 34 im abschliessenden Test inklusive Szenenwechsel mit noch laufenden Effekten; 146 Waffenprüfungen in Forest. Der vorhandene Waffeneffekttest musste vor seinem Schuss die inzwischen eingeführte Wechselverzögerung abwarten. Deutsche Texte: 1992 Einträge ohne fehlende Übersetzungen oder Platzhalterfehler. Der tatsächliche Windows-Release erreicht sowohl `PLANES_READY` als auch `PLANES_SURVIVAL_READY` ohne Spiel-/Skriptfehler.

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Survival` prüft den Kampfbetrieb samt Rückkehr. `-Packaged -Survival` prüft den tatsächlichen Windows-Release inklusive Navigation und Laden der Gegner/Waffen; `-Packaged` prüft den friedlichen Einstieg.

Die isolierte Testumgebung meldet beim Start einen nicht lesbaren Windows-Zertifikatsspeicher. Die Prüfung toleriert ausschliesslich diese Umgebungsfehlermeldung; andere Engine- und Skriptfehler lassen sie scheitern. Die Map bleibt Einzelspiel.
