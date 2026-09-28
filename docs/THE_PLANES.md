# The Planes – Remetschwil

In der Gebietsauswahl **The Planes erkunden** wählen. Diese Region ist vorerst eine eigenständige Erkundungsmap im Einzelspiel, ohne Wellen oder Kampagnenabschluss. Forest behält seinen Survivalablauf. Im Koop ist der Erkundungsstart gesperrt.

WASD bewegt den Spieler; Shift sprintet, Leertaste springt, Strg duckt sich. M blendet die nordorientierte Karte ein oder aus. Escape öffnet ein Menü mit Fortsetzen, drei Referenzblickrichtungen und Rückkehr zur Gebietsauswahl. Die Fotoansichten lassen sich damit ohne erneuten Fussmarsch vergleichen.

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

Mais verwendet unverändert die vorhandenen `assets/cornfield/corn_*.res` mit Wind und drei Detailstufen. Diese vorhandenen Maisressourcen sind im Projekt erzeugte Meshes. Raben/Eulen verwenden die vorhandenen Meshy-Modelle `raven_real.glb` / `owl_real.glb`, bestehende Animationen und Rufe; Eulen bleiben in der sommerlichen Mittagsansicht verborgen. Gehölze nutzen das vorhandene Meshy-Modell `tree_autumn_a.glb` mit einem eigenen sommergrünen Material; das Original bleibt unverändert. Gras nutzt den vorhandenen Atlas. Da kein Getreidemodell vorhanden ist, ergänzt ein natives, instanziertes Halmen-/Ährenmesh die Bibliothek. Es wurden keine neuen Meshy-Generierungen beauftragt.

Terrain, Pflanzen und Weltkoordinaten verwenden dieselben Höhen. Pflanzen sind räumlich gebündelt; Nah-/Fernmeshes werden kameranah gewechselt. Wege bleiben frei. Bäume besitzen Stammkollision, Häuser blockierende Grundrisskörper, Gelände einen Höhenfeld-Collider. Die Erkundung verwendet den bestehenden Spielercontroller einschliesslich Schritten auf Kies, Gras und Mais.

## Reproduzieren und prüfen

```powershell
python tools/planes_geo.py
python tools/build_planes.py
# Anschliessend Godot-Import ausführen.
Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=planes --smoke-test
Godot.exe --path godot --windowed --resolution 1600x900 --script res://tests/run.gd -- --suite=planes --smoke-test --render-planes --quality=2
```

`--planes-roundtrip --no-intro --no-music` ergänzt den tatsächlichen Rückweg in die Forest-Gebietsauswahl. Die Suite prüft Regionsdatenwechsel, Fortschrittsschutz, Höhen, Terrainkollision, freie Wege, vorhandene Modelle, tatsächliche Bewegung und Menübedienung. Referenzbilder und Luftbildüberlagerung entstehen unter `artifacts/planes/`. Zusätzlich die bestehenden Suiten `compile_all` und `campaign_map` ausführen. Tests sollten mit isoliertem `APPDATA` unter `.test-user` laufen.

Der Windows-Export enthält die eigenen JSON-/Höhenraster durch die ergänzte Export-Inklusion. Der Einstieg kann für eine direkte Ortsprüfung auch mit `--path godot res://scenes/planes.tscn` erfolgen. Die fertige EXE unterstützt `RemZ.exe -- --explore-planes`; der normale Einstieg bleibt die Gebietsauswahl.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Rendered -RoundTrip
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Packaged
```

## Geprüfter Stand, 28. September 2026

- `compile_all`: 324 Skripte, keine Kompilierungsfehler.
- `campaign_map`: 41 Prüfungen bestanden, einschliesslich Forest-Auswahl und Kampagnenfortschritt.
- `planes`, gerendert mit Rückweg und erneutem Einstieg über die tatsächliche Gebietsauswahl: 21 Prüfungen bestanden. Kollisionen, Laufbewegung, freie Wege, Höhenraster, Modelle und Menüs geprüft.
- Windows-Release: EXE mit den ausgelieferten DLLs und dem PCK direkt gestartet; `PLANES_READY` erreicht, anschliessend regulär beendet. Dieser Pakettest ist ein Starttest; die 21 Funktionsprüfungen laufen im Projekt.
- Drei gerenderte Referenzblicke und das Menü unter `artifacts/planes/` visuell geprüft. Die drei Momentaufnahmen meldeten 42, 44 und 72 FPS auf der vorhandenen RTX 3060 Ti; dies ist kein dauerhafter Leistungsbenchmark.

Die Testumgebung meldet beim Start einen nicht lesbaren Windows-Zertifikatsspeicher. Die Prüfung toleriert ausschliesslich diese Umgebungsfehlermeldung; andere Engine- und Skriptfehler lassen sie scheitern. Live-Koop wurde für diese Solo-Erkundungsmap nicht erneut geprüft.
