# RemZ – Remetschwil Sennhof

Das aktuelle Spiel ist das Godot-Projekt in diesem Ordner. Der Three.js-Code im übergeordneten `src/` ist der ältere Browser-Prototyp.

## Starten

`project.godot` mit Godot 4.7.2 öffnen und F6/F5 drücken. Der Startknopf wird freigegeben, sobald das begehbare Wegnetz fertig ist.

Der Windows-Export liegt unter `../builds/windows/RemZ.exe`. Zum Weitergeben den gesamten Ordner `windows` verwenden: Die EXE benötigt die benachbarte `RemZ.pck`.

## Steuerung

| Eingabe | Aktion |
| --- | --- |
| WASD / Maus | Bewegen / umsehen |
| Shift | Sprinten |
| Linke / rechte Maustaste | Schießen / zielen |
| R | Nachladen |
| 1–5 | Freigeschaltete Waffe wählen |
| G | Granate |
| E | Barrikade bauen oder reparieren |
| F | Taschenlampe |
| Tab | Fähigkeiten und Waffen kaufen |
| Escape | Pause / fortsetzen |
| F11 | Vollbild umschalten |

Beide Hände folgen der jeweiligen Waffe beim Zielen, Rückstoß und Nachladen. Die Minimap unten rechts bildet die tatsächlichen Kartendaten ab. Norden bleibt oben; der Spielerpfeil dreht sich mit. Rote Punkte zeigen Gegner, Rauten die Barrikaden.

Die Hände verwenden modellierte Handschuhe mit Fingerskelett und Normalmaps. Die Ärmel stammen aus einer Meshy-Generierung mit 4K-PBR-Materialien und werden an die Griffpositionen jeder Waffe angepasst. Waffen und Arme werden separat in voller Fensterauflösung mit Kantenglättung gerendert, unabhängig von der 3D-Skalierung der Karte. Quellen und Lizenzhinweise: `assets/viewmodel/SOURCES.md` und `assets/viewmodel/VALVE-LICENSE.txt`.

## Grafik und Leistung

Im Start- und Pausenmenü stehen drei Grafikprofile, Bildratenlimit, VSync, FPS-Anzeige, Mausempfindlichkeit und Lautstärke zur Verfügung. Änderungen werden lokal gespeichert. Das Profil **Flüssig** verwendet reduzierte Effekt- und Sichtweiten sowie 85 % 3D-Auflösung mit FSR; die Oberfläche bleibt scharf. Die Standardbegrenzung beträgt 144 FPS.

Die Physik verwendet Jolt. Vegetation und wiederholte Objekte werden räumlich gruppiert und außerhalb der Sichtweite ausgeblendet. Gegner berechnen ihre Wege zeitlich versetzt. Maximal 48 lebende Gegner bleiben gleichzeitig aktiv; weitere Spawns warten in der Welle.

Die 72 separaten Oberflächentexturen verwenden jetzt GPU-Kompression und Mipmaps. Ihre Desktop-Importdateien belegen zusammen etwa 64 MiB einschließlich Mipmaps; die unkomprimierten RGBA-Basisbilder entsprechen etwa 246 MiB. Farbkarten verwenden BC7, Normalmaps die passende Normalmap-Kompression.

## Prüfen und exportieren

Aus dem übergeordneten Projektordner in PowerShell:

```powershell
./tools/check-game.ps1 -Mode Smoke
./tools/check-game.ps1 -Mode Benchmark -Quality 0
./tools/check-game.ps1 -Mode ExportWindows
```

Bei anderem Installationsort zusätzlich `-Godot 'C:/Pfad/Godot.exe'` angeben. Für den Export sind passende offizielle Windows-Templates erforderlich; das Preset verweist auf `../builds/templates/`. Benchmark mit geschlossenem weiteren Spielfenster durchführen. Der Benchmark verändert keine gespeicherten Einstellungen.

Die 48 automatisierten Prüfungen decken Start, Navigation, Grafikprofile, Minimap-Ausrichtung, Hände und Kamerafreiraum für alle fünf Waffen, unabhängige Handdarstellung und Mündungsfeuer, Munition, Feuerrate bei 30/60/144 FPS, Barrikaden, Nahkampfsichtlinie, Wellen, Granaten, Pause, Fähigkeiten und Neustart ab. Visuelle Prüfungen aller Waffen: `--script res://tests/visual.gd -- --smoke-test`.

## Stand der Freigabe

Dies ist ein spielbarer Entwicklungsstand mit Windows-Export, keine bestätigte Verkaufsfreigabe. Dauerhaft 100 FPS sind für den neuesten Kartenstand noch nicht unter störungsfreien Bedingungen nachgewiesen. Asset-Nutzungsrechte, längere Spieltests und Tests auf weiterer Hardware stehen vor einem Verkauf aus. Die vorhandenen Musik- und Sounddateien stammen laut ihren Skripten aus der Bibliothek des Nutzers; Lizenzbelege liegen hier nicht vor.
