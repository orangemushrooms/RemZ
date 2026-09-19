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
| Q | Nahkampf: Kolbenschlag mit Rückstoss, auch beim Nachladen |
| Enter | Wartezeit überspringen, nächste Welle sofort starten |
| E | Nahe Barrikade verwalten / Gegenstand aufnehmen / Tür öffnen und schliessen |
| V | Barrikaden-Bauplanung mit Vorschau aller vier Zugänge |
| B | Inventar |
| F | Taschenlampe |
| Tab | Fähigkeiten und Waffen kaufen |
| Escape | Pause / fortsetzen |
| F11 | Vollbild umschalten |

**Spielablauf.** Vor dem Start wählt man im Hauptmenü einen von vier Schwierigkeitsgraden (Leicht, Normal, Schwer, Albtraum: Lebenspunkte, Schaden, Wellengrösse, Tempo, Vorräte, Regeneration und Punktefaktor der Zombies). Jede fünfte Welle ist eine Bosswelle mit zusätzlichen Brocken. Gefallene Zombies lassen Munition für die aktuelle Waffe, Granaten oder Verbandspäckli fallen, die man durch Hindurchlaufen aufnimmt. Abschüsse in schneller Folge (4 s) bauen eine Serie auf, ab dem dritten gibt jeder weitere 10 % mehr Punkte (maximal +100 %); Kopfschüsse zählen das 1,5-Fache. Punkte erscheinen als Einblendung neben dem Fadenkreuz, Treffer auf den Spieler zeigen einen roten Richtungsbogen. Unter 35 % Leben pulsiert eine rote Vignette und der Herzschlag wird hörbar. Schritte klingen je nach Untergrund: Auf Asphalt und Beton laufen die drei Aufnahmen footstep1.mp3 bis footstep3 roh, auf Kies leicht gedämpft mit feinem Knirschen, auf der Wiese dumpfer mit Gras-Rascheln, auf Waldboden am dumpfsten mit Laub-Knistern, im Obergeschoss der Hütte mit hohlem Holzklang (je ein Tiefpass-Bus plus eine prozedurale Texturschicht, `Sfx.footstep`). Gegner werden auf jede Distanz getroffen; ab der Nennreichweite der Waffe fällt der Schaden sanft bis auf 55 % ab.mp3 mit zufälligem Wechsel ohne direkte Wiederholung. Beim Sprinten folgen sie schneller und lauter; Landungen klingen tiefer. Nach dem Tod zeigt die Bilanz Abschüsse, Kopfschüsse, Treffgenauigkeit, beste Serie, Granaten, Barrikaden und Spielzeit; die zehn besten Runden landen dauerhaft in der Bestenliste (`user://highscores.json`). Das Menü (Start, Pause, Spielende) hat Reiter für Briefing, Schwierigkeit, Steuerung, Einstellungen, Bestenliste und Erfolge; aus der Pause führt ein Knopf zurück ins Hauptmenü.

Beide Hände folgen der jeweiligen Waffe beim Zielen, Rückstoß und Nachladen. Die Minimap unten rechts bildet die tatsächlichen Kartendaten ab. Norden bleibt auf der Karte oben; der Spielerpfeil und die Windrose reagieren auf die Blickrichtung. Rote Punkte zeigen Gegner. Sperrlinien sind rot (ungebaut), grün (gebaut) oder gelb (stark beschädigt).

Die Barrikaden-Bauplanung pausiert das Spiel und zeigt den gewählten Zugang aus einer Übersichtskamera. Rot markiert die komplette geplante Linie samt Modellen und Geländeumriss. **Ein Klick baut beide zusammenhängenden Segmente für insgesamt 50 Punkte**. Jede weitere Stufe kostet 50 Punkte, erhöht die Haltbarkeit um 150 TP und repariert die Linie; maximal sind 450 TP möglich. Eine separate vollständige Reparatur kostet 25 Punkte. Material und Kollision folgen dem Gelände, die Segmente überlappen leicht an den Verbindungen. Bauaktionen sind bis 6 m Abstand von jedem Teil der Linie möglich; Spieler oder Gegner in der Baufläche verhindern den Neubau ohne Punkteabzug. Im Menü wählen 1–4 den Zugang, R repariert, V/Escape kehrt zurück. Entfernte Bauplätze lassen sich ansehen, aber nicht aus der Ferne bebauen.

Die Hände verwenden modellierte Handschuhe mit Fingerskelett und Normalmaps. Die Ärmel stammen aus einer Meshy-Generierung mit 4K-PBR-Materialien und werden an die Griffpositionen jeder Waffe angepasst. Waffen und Arme werden separat in voller Fensterauflösung mit Kantenglättung gerendert, unabhängig von der 3D-Skalierung der Karte. Quellen und Lizenzhinweise: `assets/viewmodel/SOURCES.md` und `assets/viewmodel/VALVE-LICENSE.txt`.

Jede Waffe hat einen eigenen kurzen Mündungsblitz, Licht auf Händen und Umgebung sowie auslaufenden Pulverdampf. Der Rauch steigt auf und bleibt beim Umsehen in der Welt zurück. Rückstoß hebt die Waffe an, drückt sie zurück und federt gedämpft aus; beim Zielen ist er schwächer. Die Ärmel reagieren mit leichter Stoffbewegung auf Schüsse und Schritte, während die Bündchen an den Händen bleiben. Rauch nutzt einen gemeinsamen Pool mit maximal 48 Instanzen in einem MultiMesh; für die Stoffbewegung werden keine Meshes pro Bild neu aufgebaut. Alle Effekte pausieren mit dem Spiel.

Die Rückstoßabstimmung wurde nach dem Spieltest verstärkt: 60–100 % mehr Grundimpuls nach oben, stärkere Rückwärtsbewegung und langsamere Erholung. Zielen reduziert den Impuls um 25 %; bei Dauerfeuer steigt der Hochschlag weiter an. Der vertikale Kamerawinkel bleibt begrenzt.

## Hüttenschlüssel und Türen

Waldhütte und Holzlager haben je einen eigenen Schlüssel. Beide liegen bei jedem neuen Spiel an anderen, geprüften Waldstellen in Wegnähe. Im Umkreis von 16 m erscheinen ein Hinweis, die Entfernung und ein Richtungspfeil; der Schlüssel liegt auf einem niedrigen Baumstumpf. Nahe herangehen und **E** drücken. Wände verhindern die Aufnahme durch Hindernisse.

Gefundene Schlüssel bleiben für das gesamte Spiel im Inventar (**B**), auch über Wellenwechsel hinweg. Der Waldhüttenschlüssel passt zum Garagentor und zur oberen Hüttentür, der zweite zum Holzlagertor. **E** öffnet und schliesst die Türen wiederholt. Beim Öffnen schwingen die Flügel vom Spieler weg, auch wenn er direkt vor der Tür steht. Andere Personen im Schwenkbereich blockieren die Bewegung; beim Schliessen bleibt der Einklemmschutz aktiv. Bereits aufgeschlossene Türen halten Gegner kurz auf, können unter anhaltenden Angriffen aber aufgedrückt werden. Das vergitterte Holzlagerfenster verhindert den Zugang ohne Schlüssel.

## Grafik und Leistung

Der Waldboden trägt eine dichte, niedrige Schicht aus Gräsern und Farnen bis entlang des Wegs zur Hütte. Unregelmäßige Gruppen, unterschiedliche Wuchshöhen und gedämpfte Grün-/Brauntöne lassen Laub zwischen den Pflanzen sichtbar. Wege, Gebäude, Lichtung und Teich bleiben frei. Der Bewuchs folgt dem Gelände und nutzt die Grassichtweite des gewählten Grafikprofils sowie räumliche Instanzgruppen ohne zusätzliche Schatten oder Kollisionen.

Die Felder tragen im Nahbereich eine dichte Grasschicht mit rund 13 Büscheln pro Quadratmeter. Ein leicht versetztes Raster verhindert grosse kahle Lücken; Höhe und Ausrichtung variieren und folgen dem Hang. Der Bewuchs reicht auch über die westlichen Wiesen und etwas über den spielbaren Rand hinaus. Wege, Gebäude und Teich bleiben frei. In der Ferne werden die Büschel allmählich ausgedünnt; die bestehenden Sichtweiten und räumlichen Instanzgruppen begrenzen den Zeichenaufwand.

Strassen und Wege folgen dem triangulierten Gelände mit fein unterteilten Flächen. Unter dem Asphalt liegt durchgehend texturierter Kiesboden, sodass an den Rändern keine blau-grauen Fehlstellen entstehen und an Kreuzungen kein Gelände durch die Fahrbahn ragt.

Die Bauernhäuser und Dorfgebäude in der Ferne besitzen unterschiedliche Putz- und Holzfassaden, Ziegel- oder dunkle Dächer mit Überständen, Fensterläden, Scheunentore, Kamine und Steinsockel. Lage und Ausrichtung folgen weiterhin den Kartendaten. Die Bauteile werden pro Material in räumlichen Gruppen zusammengefasst; Fassaden und Dächer bleiben auch im Grafikprofil «Flüssig» gemeinsam sichtbar.

Der Waldteich mit seinem speisenden Holzbrunnen liegt am östlichen Ende des schmalen nördlichen Fußwegs. Der Weg endet am Westufer; Mulde, Wasserstand und Uferbewuchs folgen der neuen Position. Die frühere Teichstelle westlich der Weggabelung ist wieder Waldboden.

Der Lagerfeuerrauch steigt langsam auf und driftet mit schwachem Wind. Gedämpfte Wirbel, begrenzte Geschwindigkeit und über zehn Sekunden wachsende, weich ausblendende Rauchwolken ersetzen die schnelle Bewegung. Der Rauch reagiert auf die Beleuchtung und blendet an nahen Oberflächen weich aus.

Der Grillplatz ist nach den Standortfotos eine ebene Kiesfläche (das Gelände wird dort auf eine Ebene gezogen): Feuerstelle mit vier Rundholzbänken auf Kies, der Picknicktisch drei Meter westlich auf Laub, der ausgehöhlte graue Holzbrunnen mit dickem Stammpfosten und Eisenrohr am Westrand des Platzes, der weisse Abfalleimer auf einem Pfosten dazwischen, Infotafel und Wegweiser am Eingang des Waldwegs. Die Waldhütte hat ein Satteldach mit Ost-West-First: der Giebel mit weitem Vordach auf Pfetten und Kopfbändern zeigt zum Weg im Westen, die Aussentreppe aus Betonblöcken führt ohne Geländer der Nordseite entlang zur oberen Tür, in der Westwand sitzen zwei Kellerfenster. Das Holzlager steht mit 14 Grad Drehung wie im Luftbild, mit hellem Faserzementdach und weitem Vordach auf Streben zur Strasse; das grosse Tor liegt nahe der Südostecke. Entlang des Wegs zur Hütte gibt es wie auf den Fotos keinen Zaun, nur den Drahtzaun östlich der Sennhofstrasse. Brunnen, Abfalleimer, Wegweiser, Infotafel, Feuerstelle mit Schwenkgrill, Bänke, Picknicktisch, der liegende Baumstamm, die Werkbank in der Garage sowie Munitionskisten, Munitionspakete und Verbandspäckli sind Meshy-PBR-Modelle (2K-Texturen); fehlt ein Modell, baut das Spiel die alte Box-Version. Die Zugänge zum Garagentor und zur Aussentreppe bleiben frei. Gesammelte Steinpilze und Fliegenpilze verschwinden sofort vollständig und werden genau einmal im Inventar verbucht. Ihre Modelle bleiben auch nach der Kartenoptimierung mit dem Sammelobjekt verbunden.

Der aktuelle Standard startet um **06:00 Uhr** und lässt die Zeit über Wellenwechsel hinweg weiterlaufen. Ein vollständiger Tag dauert **15 echte Minuten (96×)**. Die Ortszeit steht oben rechts; Morgen, Tag, Abend und Nacht gehen weich ineinander über. Pause, Inventar, Skills, Barrikadenplanung und Spielende halten die Uhr an.

Sonnenstand, Himmelsfarben, Bergpanorama, Nebel und die Beleuchtung von Händen/Waffen folgen der Uhr. Nachts werden Feuer und die vorhandenen Hütten-/Laternenlichter stärker, die Umgebung wird dunkler. Die Taschenlampe bleibt mit **F** steuerbar. Die vorhandenen Schatten- und Volumennebelbudgets bleiben erhalten. Lichtwerte werden mit 10 Hz aktualisiert, Himmelsreflexionen alle 30 Spielsekunden mit einer kleinen, über mehrere Bilder verteilten Berechnung.

Die parallel entwickelte Variante mit durchgehendem 15-Minuten-Tag ist inzwischen Standard. `RemZ.exe -- --continuous-day-night` wählt diesen Modus weiterhin ausdrücklich. Die frühere Einstellung mit 10× und Morgenstart je Welle lässt sich im `DayNightCycle` über `time_scale = 10.0` und `reset_each_wave = true` wiederherstellen.

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
./tools/check-game.ps1 -Mode DoorsKeys
./tools/check-game.ps1 -Mode CampsitePickups
./tools/check-game.ps1 -Mode Benchmark -Quality 0
./tools/check-game.ps1 -Mode ExportWindows
```

Bei anderem Installationsort zusätzlich `-Godot 'C:/Pfad/Godot.exe'` angeben. Für den Export sind passende offizielle Windows-Templates erforderlich; das Preset verweist auf `../builds/templates/`. Benchmark mit geschlossenem weiteren Spielfenster durchführen. Der Benchmark verändert keine gespeicherten Einstellungen.

Die 48 automatisierten Prüfungen decken Start, Navigation, Grafikprofile, Minimap-Ausrichtung, Hände und Kamerafreiraum für alle fünf Waffen, unabhängige Handdarstellung und Mündungsfeuer, Munition, Feuerrate bei 30/60/144 FPS, Barrikaden, Nahkampfsichtlinie, Wellen, Granaten, Pause, Fähigkeiten und Neustart ab. Visuelle Prüfungen aller Waffen: `--script res://tests/visual.gd -- --smoke-test`.

`WeaponEffects` prüft zusätzlich alle fünf Waffen beim Schießen, Rauchabbau, Rückstoßrichtung und Rückkehr, Dauerfeuer, leere Magazine, Nachladen, Waffenwechsel, Stoffbewegung beim Laufen, Pause, langsame Frames und Zielen. Der gerenderte Lauf umfasst 50 Funktionsprüfungen und 11 Screenshot-Prüfungen. Bilder: `../artifacts/weapon-effects/`.

`Barricades` umfasst 54 Prüfungen einschließlich gerenderter Ansichten: vollständige Linien, Kosten, Vorschau, Kollision an den Verbindungen, Upgrades, Reparatur, Zerstörung und Wiederaufbau, blockierte Bauflächen, Reichweite sowie Kamera-/Menürückkehr. Ansichten aller vier Zugänge und des Menüs bei 1280×720 liegen in `../artifacts/barricades/`.

`Atmosphere` prüft Himmel, Nebel und die drei Grafikprofile. Es erstellt elf Vergleichs-/Himmelsansichten und misst den alten und neuen Himmel in der Reihenfolge vorher–nachher–nachher–vorher aus drei unveränderten Kamerapositionen. Aufwärmen und Screenshots liegen außerhalb der Messintervalle. Bilder und Messdaten: `../artifacts/atmosphere/`.

`DayNight` prüft Zeittempo bei 30/60/144 FPS, Mitternacht, Wellenneustarts, alle Pausenmenüs, Nachtbeleuchtung und Grafikprofile. Es erstellt Ansichten von Morgen, Mittag, Abend, Nacht und Taschenlampe sowie einen Vergleich mit stehender/laufender Uhr. Bilder und Messdaten: `../artifacts/day-night/`. Ohne Fenster kann die Funktionsprüfung mit `--headless --script res://tests/day_night.gd -- --smoke-test --no-music` ausgeführt werden.

`DoorsKeys` prüft zufällige erreichbare Fundorte, Entfernung und Sichtlinie bei der Aufnahme, Schlüsselbesitz, Türdurchgänge, Öffnen/Schliessen, Pause, Einklemmschutz, Gegnerdruck und Inventar. Zusätzlich werden alle drei Türen aus 0,5 m Entfernung von beiden Seiten über die tatsächliche E-Interaktion geöffnet und geschlossen; ein anderer Akteur hinter dem Tor muss die Öffnung weiterhin blockieren. Bilder: `../artifacts/doors-keys/`. Reproduzierbare Fundorte sind mit `--key-seed=17` möglich; ohne Parameter werden sie bei jedem Spielstart neu ausgewählt.

`CampsitePickups` prüft beide Pilzarten nach der Kartenoptimierung: sofortiges Ausblenden, vollständiges Entfernen des Modells, einmalige Inventarbuchung und unveränderte übrige Pilze. Ansichten von Feuerstelle, Brunnen und Pilzen vor/nach dem Sammeln: `../artifacts/campsite-pickups/`.

## Stand der Freigabe

Dies ist ein spielbarer Entwicklungsstand mit Windows-Export, keine bestätigte Verkaufsfreigabe. Dauerhaft 100 FPS sind für den neuesten Kartenstand noch nicht unter störungsfreien Bedingungen nachgewiesen. Asset-Nutzungsrechte, längere Spieltests und Tests auf weiterer Hardware stehen vor einem Verkauf aus. Die vorhandenen Musik- und Sounddateien stammen laut ihren Skripten aus der Bibliothek des Nutzers; Lizenzbelege liegen hier nicht vor.
