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
| E | Nahe Barrikade verwalten / Gegenstand aufnehmen / Tor öffnen |
| V | Barrikaden-Bauplanung mit Vorschau aller vier Zugänge |
| B | Inventar |
| F | Taschenlampe |
| Tab | Fähigkeiten und Waffen kaufen |
| Escape | Pause / fortsetzen |
| F11 | Vollbild umschalten |

Beide Hände folgen der jeweiligen Waffe beim Zielen, Rückstoß und Nachladen. Die Minimap unten rechts bildet die tatsächlichen Kartendaten ab. Norden bleibt auf der Karte oben; der Spielerpfeil und die Windrose reagieren auf die Blickrichtung. Rote Punkte zeigen Gegner. Sperrlinien sind rot (ungebaut), grün (gebaut) oder gelb (stark beschädigt).

Die Barrikaden-Bauplanung pausiert das Spiel und zeigt den gewählten Zugang aus einer Übersichtskamera. Rot markiert die komplette geplante Linie samt Modellen und Geländeumriss. **Ein Klick baut beide zusammenhängenden Segmente für insgesamt 50 Punkte**. Jede weitere Stufe kostet 50 Punkte, erhöht die Haltbarkeit um 150 TP und repariert die Linie; maximal sind 450 TP möglich. Eine separate vollständige Reparatur kostet 25 Punkte. Material und Kollision folgen dem Gelände, die Segmente überlappen leicht an den Verbindungen. Bauaktionen sind bis 6 m Abstand von jedem Teil der Linie möglich; Spieler oder Gegner in der Baufläche verhindern den Neubau ohne Punkteabzug. Im Menü wählen 1–4 den Zugang, R repariert, V/Escape kehrt zurück. Entfernte Bauplätze lassen sich ansehen, aber nicht aus der Ferne bebauen.

Die Hände verwenden modellierte Handschuhe mit Fingerskelett und Normalmaps. Die Ärmel stammen aus einer Meshy-Generierung mit 4K-PBR-Materialien und werden an die Griffpositionen jeder Waffe angepasst. Waffen und Arme werden separat in voller Fensterauflösung mit Kantenglättung gerendert, unabhängig von der 3D-Skalierung der Karte. Quellen und Lizenzhinweise: `assets/viewmodel/SOURCES.md` und `assets/viewmodel/VALVE-LICENSE.txt`.

Jede Waffe hat einen eigenen kurzen Mündungsblitz, Licht auf Händen und Umgebung sowie auslaufenden Pulverdampf. Der Rauch steigt auf und bleibt beim Umsehen in der Welt zurück. Rückstoß hebt die Waffe an, drückt sie zurück und federt gedämpft aus; beim Zielen ist er schwächer. Die Ärmel reagieren mit leichter Stoffbewegung auf Schüsse und Schritte, während die Bündchen an den Händen bleiben. Rauch nutzt einen gemeinsamen Pool mit maximal 48 Instanzen in einem MultiMesh; für die Stoffbewegung werden keine Meshes pro Bild neu aufgebaut. Alle Effekte pausieren mit dem Spiel.

Die Rückstoßabstimmung wurde nach dem Spieltest verstärkt: 60–100 % mehr Grundimpuls nach oben, stärkere Rückwärtsbewegung und langsamere Erholung. Zielen reduziert den Impuls um 25 %; bei Dauerfeuer steigt der Hochschlag weiter an. Der vertikale Kamerawinkel bleibt begrenzt.

## Grafik und Leistung

Jede Welle beginnt um **06:00 Uhr**. Die Ortszeit steht oben rechts; Morgen, Tag, Abend und Nacht gehen weich ineinander über. Der Faktor **10×** bedeutet sechs echte Minuten pro Spielstunde und 144 Minuten pro vollständigem Tag. Von 06:00 bis 18:00 vergehen 72 echte Minuten. Kurze Wellen bleiben deshalb morgens; der Tageswechsel ist nicht künstlich an die Zahl der verbleibenden Gegner gekoppelt. Pause, Inventar, Skills, Barrikadenplanung und Spielende halten die Uhr an.

Sonnenstand, Himmelsfarben, Bergpanorama, Nebel und die Beleuchtung von Händen/Waffen folgen der Uhr. Nachts werden Feuer und die vorhandenen Hütten-/Laternenlichter stärker, die Umgebung wird dunkler. Die Taschenlampe bleibt mit **F** steuerbar. Die vorhandenen Schatten- und Volumennebelbudgets bleiben erhalten. Lichtwerte werden mit 10 Hz aktualisiert, Himmelsreflexionen alle 30 Spielsekunden mit einer kleinen, über mehrere Bilder verteilten Berechnung.

Die parallel entwickelte Variante bleibt optional verfügbar: `RemZ.exe -- --continuous-day-night` startet einen durchgehenden Tag von 15 echten Minuten (96×), ohne Rücksetzung bei Wellenwechseln. Ohne diesen Parameter gilt weiterhin 10× mit Morgenstart je Welle.

Der Kartenhorizont verwendet ein echtes Schweizer Alpenpanorama von Andreas Mischok / Poly Haven (CC0), mit entfernter Bergkette und Dunst über den Tälern. Der Wald hat dichteren, kühleren Entfernungsnebel. Berge und Tageshimmel werden im vorhandenen Himmelspass gezeichnet: keine zusätzlichen Bergmodelle, Partikel, Schatten oder Viewports. Die 4K-HDR-Textur benötigt mit BC6H und Mipmaps rund 10,7 MiB GPU-Speicher. Quellen: `assets/sky/SOURCES.md`.

Der frühere Vergleich des statischen Alpenhimmels an drei festen Blickpunkten ergab 0,001–0,039 ms zusätzliche GPU-Zeit (unter 1 %) und identische Zeichenaufrufe. Diese Messung stammt vor dem Tag-Nacht-Zyklus. Sie ist keine Garantie für unveränderte FPS auf jeder Hardware oder für 100 FPS im Kampf. Details stehen in `PERFORMANCE.md`.

Im Start- und Pausenmenü stehen drei Grafikprofile, Bildratenlimit, VSync, FPS-Anzeige, Mausempfindlichkeit und Lautstärke zur Verfügung. Änderungen werden lokal gespeichert. Das Profil **Flüssig** verwendet reduzierte Effekt- und Sichtweiten sowie 85 % 3D-Auflösung mit FSR; die Oberfläche bleibt scharf. Die Standardbegrenzung beträgt 144 FPS.

Die Physik verwendet Jolt. Vegetation und wiederholte Objekte werden räumlich gruppiert und außerhalb der Sichtweite ausgeblendet. Gegner berechnen ihre Wege zeitlich versetzt. Maximal 48 lebende Gegner bleiben gleichzeitig aktiv; weitere Spawns warten in der Welle.

Die 72 separaten Oberflächentexturen verwenden jetzt GPU-Kompression und Mipmaps. Ihre Desktop-Importdateien belegen zusammen etwa 64 MiB einschließlich Mipmaps; die unkomprimierten RGBA-Basisbilder entsprechen etwa 246 MiB. Farbkarten verwenden BC7, Normalmaps die passende Normalmap-Kompression.

## Prüfen und exportieren

Aus dem übergeordneten Projektordner in PowerShell:

```powershell
./tools/check-game.ps1 -Mode Smoke
./tools/check-game.ps1 -Mode WeaponEffects
./tools/check-game.ps1 -Mode Barricades
./tools/check-game.ps1 -Mode Atmosphere
./tools/check-game.ps1 -Mode DayNight
./tools/check-game.ps1 -Mode Benchmark -Quality 0
./tools/check-game.ps1 -Mode ExportWindows
```

Bei anderem Installationsort zusätzlich `-Godot 'C:/Pfad/Godot.exe'` angeben. Für den Export sind passende offizielle Windows-Templates erforderlich; das Preset verweist auf `../builds/templates/`. Benchmark mit geschlossenem weiteren Spielfenster durchführen. Der Benchmark verändert keine gespeicherten Einstellungen.

Die 48 automatisierten Prüfungen decken Start, Navigation, Grafikprofile, Minimap-Ausrichtung, Hände und Kamerafreiraum für alle fünf Waffen, unabhängige Handdarstellung und Mündungsfeuer, Munition, Feuerrate bei 30/60/144 FPS, Barrikaden, Nahkampfsichtlinie, Wellen, Granaten, Pause, Fähigkeiten und Neustart ab. Visuelle Prüfungen aller Waffen: `--script res://tests/visual.gd -- --smoke-test`.

`WeaponEffects` prüft zusätzlich alle fünf Waffen beim Schießen, Rauchabbau, Rückstoßrichtung und Rückkehr, Dauerfeuer, leere Magazine, Nachladen, Waffenwechsel, Stoffbewegung beim Laufen, Pause, langsame Frames und Zielen. Der gerenderte Lauf umfasst 50 Funktionsprüfungen und 11 Screenshot-Prüfungen. Bilder: `../artifacts/weapon-effects/`.

`Barricades` umfasst 54 Prüfungen einschließlich gerenderter Ansichten: vollständige Linien, Kosten, Vorschau, Kollision an den Verbindungen, Upgrades, Reparatur, Zerstörung und Wiederaufbau, blockierte Bauflächen, Reichweite sowie Kamera-/Menürückkehr. Ansichten aller vier Zugänge und des Menüs bei 1280×720 liegen in `../artifacts/barricades/`.

`Atmosphere` prüft Himmel, Nebel und die drei Grafikprofile. Es erstellt elf Vergleichs-/Himmelsansichten und misst den alten und neuen Himmel in der Reihenfolge vorher–nachher–nachher–vorher aus drei unveränderten Kamerapositionen. Aufwärmen und Screenshots liegen außerhalb der Messintervalle. Bilder und Messdaten: `../artifacts/atmosphere/`.

`DayNight` prüft Zeittempo bei 30/60/144 FPS, Mitternacht, Wellenneustarts, alle Pausenmenüs, Nachtbeleuchtung und Grafikprofile. Es erstellt Ansichten von Morgen, Mittag, Abend, Nacht und Taschenlampe sowie einen Vergleich mit stehender/laufender Uhr. Bilder und Messdaten: `../artifacts/day-night/`. Ohne Fenster kann die Funktionsprüfung mit `--headless --script res://tests/day_night.gd -- --smoke-test --no-music` ausgeführt werden.

## Stand der Freigabe

Dies ist ein spielbarer Entwicklungsstand mit Windows-Export, keine bestätigte Verkaufsfreigabe. Dauerhaft 100 FPS sind für den neuesten Kartenstand noch nicht unter störungsfreien Bedingungen nachgewiesen. Asset-Nutzungsrechte, längere Spieltests und Tests auf weiterer Hardware stehen vor einem Verkauf aus. Die vorhandenen Musik- und Sounddateien stammen laut ihren Skripten aus der Bibliothek des Nutzers; Lizenzbelege liegen hier nicht vor.
