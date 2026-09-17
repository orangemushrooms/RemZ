# Prüfung vom 17. September 2026

## Ergänzung: Hüttentüren und Waldschlüssel

`../logs/doors-keys-final-render.log`: **85 Prüfungen, 0 fehlgeschlagene Prüfungen**, inklusive acht reproduzierbarer Fundort-Auswahlen, Sichtlinie/Reichweite, drei echten Türdurchgängen mit Spieler-Kapsel, Öffnen und Schliessen, Pause, Einklemmschutz, tatsächlichem Gegnerangriff auf eine Tür und vollständigem Spielneustart. Elf Ansichten bei 1280 × 720 liegen unter `../artifacts/doors-keys/`.

Die beiden Schlüssel verwenden kleine wiederverwendete Materialien und keine zusätzlichen Lichtquellen oder Partikeleffekte. Die erreichbaren Fundorte werden einmal beim Laden gegen die fertige Navigation und Weltkollision geprüft. Während des Spiels werden nur zwei Entfernungen mit 10 Hz geprüft; der sichtbare Richtungspfeil folgt der Kamera. Türabfragen laufen bei Interaktion und während der Bewegung; Gegner prüfen drei Türflächen zusätzlich. Bewegliche Türteile werden von statischen Render-Batches ausgeschlossen. Dies ist eine Funktionsprüfung, kein neuer FPS-Benchmark. Die bestehenden zwei Navigationskanten-Warnungen und die Sandbox-Meldungen zum Shadercache traten auch in diesem Lauf auf.

## Ergänzung: Tag-Nacht-Zyklus

Die folgenden Tag-Nacht-Messungen dokumentieren den damaligen Stand. Der parallele Worker hat den Standard danach auf einen durchgehenden 15-Minuten-Tag (96×) umgestellt; dieser aktuelle Standard ist im Export mit den Hüttenschlüsseln erhalten.

Die Uhr läuft mit 10×, setzt jede Welle auf 06:00 zurück und pausiert mit dem Spiel. Vorhandene Sonne, Fülllicht, Feuer und fünf Hütten-/Laternenlichter werden weiterverwendet. Es gibt keine zusätzlichen Lichtquellen, Schattenkarten, Nebelpartikel oder Himmelspässe. Die Lichtwerte aktualisieren sich mit 10 Hz. Der Himmel erhält alle 30 Spielsekunden neue Werte (alle drei echten Sekunden bei 10×); seine Reflexionen verwenden eine inkrementelle 128-Pixel-Cubemap. Die Waffenansicht besitzt eine statische Reflexionsumgebung ohne Abhängigkeit von den veränderlichen Lichtquellen.

Der Vergleich stehende–laufende–laufende–stehende Uhr ergab GPU-Mediane von **11,833 / 12,437 / 11,666 / 59,760 ms**, jeweils **606 Zeichenaufrufe**. Die große Abweichung zwischen den beiden Kontrollmessungen macht eine zuverlässige Angabe des zusätzlichen Zeitaufwands unmöglich. Ein weiteres Spiel und der Editor liefen gleichzeitig; eine Stichprobe zeigte 99 % GPU-Auslastung bei 84 °C. Diese Anwendungen wurden nicht beendet. Der Lauf ist weder ein Nachweis von null FPS-Verlust noch des 100-FPS-Ziels.

Rohdaten dieses Vergleichs vor der letzten Anpassung der Nachtfarben: `../artifacts/day-night/benchmark-concurrent.json`, `../logs/day-night-verified-render.log`. Der abschließende Funktions-/Sichttest und die Bilder werden separat in `../artifacts/day-night/report.json` und `../logs/day-night-release-render.log` geführt. Geprüft werden Wellenstart, Zeittempo bei 30/60/144 FPS, Mitternacht, sämtliche Pausenmenüs, Lichtverhältnisse, drei Grafikprofile und die Uhr bei 1280 × 720.

**56 Prüfungen im gerenderten Lauf bestanden**, darunter elf Screenshot-Prüfungen. Nach der Integration beider Zeitmodi bestanden zusätzlich jeweils **40 Funktionsprüfungen** für den Standard (10×, Morgen je Welle) und den optionalen durchgehenden 15-Minuten-Tag: `day-night-default-headless.log` und `day-night-continuous-headless.log`. Die zuletzt bereinigte Himmelsmaske wurde separat zu vier Tageszeiten gerendert (`day-night-sky-preview.log`). Im schnellen optionalen Modus bleibt die Himmelsaktualisierung auf höchstens einmal pro echter Sekunde begrenzt.

## Ergänzung: Alpenhorizont und dichterer Nebel

Die folgenden Zahlen stammen vom statischen Alpenhimmel **vor** dem Tag-Nacht-Zyklus.

Die neue Atmosphäre wurde mit der vorherigen Himmel-/Nebelkonfiguration im selben Spielprozess verglichen. NVIDIA RTX 3060 Ti, 1600 × 900 Fenster, Profil **Flüssig**, 85 % 3D-Auflösung. Pro Blickpunkt vier Messungen in der Reihenfolge vorher–nachher–nachher–vorher, jeweils 2,2 s nach Aufwärmen. Die Tabelle zeigt den Mittelwert der beiden GPU-Mediane pro Variante. Spiel, Gegner und Waffenansicht waren eingefroren/ausgeblendet; diese Werte messen den Grafikaufwand der Atmosphäre, nicht die Bildrate einer vollständigen Spielrunde.

| Blickpunkt | GPU vorher | GPU nachher | Differenz | Zeichenaufrufe vorher / nachher |
| --- | ---: | ---: | ---: | ---: |
| Wiese, Osten | 1,909 ms | 1,917 ms | +0,008 ms / +0,39 % | 287 / 287 |
| Alpen, Südwesten | 1,550 ms | 1,551 ms | +0,001 ms / +0,06 % | 39 / 39 |
| Waldweg | 5,560 ms | 5,599 ms | +0,039 ms / +0,69 % | 588 / 588 |

Auch die Zahl gerenderter Primitive blieb pro Blickpunkt identisch. Der Hintergrund nutzt eine Texturabfrage im bestehenden Himmelspass; die 4096 × 2048 HDR-Textur ist mit BC6H und Mipmaps komprimiert (11.184.900 Bytes Importdatei, rund 10,7 MiB). Es gibt keine zusätzlichen Schatten, Bergmodelle oder Nebelpartikel. Die vorhandenen volumetrischen Budgets der Grafikprofile bleiben unverändert. Sky-Radiance wird statisch mit 256 Pixeln Auflösung vorgefiltert.

**21 Prüfungen bestanden**, einschließlich elf Bildern und der drei Grafikprofile. Quelle: `../logs/atmosphere-comparison-render.log`; Rohdaten und Vorher-/Nachher-Ansichten: `../artifacts/atmosphere/comparison.json`. Der parallele Editor/Worker lief weiter. Während einer Stichprobe meldete die GPU 71 °C und keine thermische Drosselung. Unterschiede unter 1 % erlauben keine Zusage von exakt null FPS-Verlust auf jeder Hardware. Der frühere vollständige Spielbenchmark unten bleibt davon getrennt.

Die Sandbox konnte den Windows-Zertifikatsspeicher nicht lesen und den Shadercache nicht speichern; der Shader wurde dennoch gerendert. Der aktuelle, parallel überarbeitete Kartenstand meldete zwei Navigation-Kantenwarnungen. Die Atmosphärenprüfung endete ohne fehlgeschlagene Prüfung; diese Navigation-Warnungen werden durch den statischen Himmel nicht verändert.

## Früherer vollständiger Spielbenchmark

Godot 4.7.2, Windows, NVIDIA RTX 3060 Ti, Jolt Physics. Fenster 1920 × 1080, logischer Viewport 1600 × 900, Profil **Flüssig**, 3D-Skalierung 0,85, VSync aus, Bildrate unbegrenzt. Pro Blickpunkt zwei Sekunden Aufwärmen und fünf Sekunden Messung. Screenshot-Erfassung erfolgt außerhalb der Messintervalle.

## Aktueller Messlauf mit Händen und Minimap

Während dieses Laufs waren zusätzlich der Editor und das daraus gestartete Spiel aktiv. Die GPU meldete 100 % Auslastung, 83 °C und aktive thermische Drosselung (NVIDIA: SW Thermal Slowdown). Diagnose: `../logs/benchmark-gpu-state.txt`. Die starken Einbrüche sind hier dokumentiert; ihr genauer Anteil durch Spiel, konkurrierende Last und Drosselung ist mit diesem Lauf nicht getrennt bestimmt. Der parallele Karten-Worker blieb aktiv. Die Werte sind kein isolierter Leistungsnachweis.

| Szene | Durchschnitt FPS | 99. Perzentil der Framezeit |
| --- | ---: | ---: |
| Lichtung | 4,8 | 314,31 ms |
| Waldhütte | 32,4 | 265,52 ms |
| Weggabelung | 66,1 | 17,71 ms |
| Weg zur Hütte | 72,4 | 16,52 ms |
| Sennhofstraße | 91,8 | 13,65 ms |
| Kampf mit 36 Gegnern | 45,3 | 27,00 ms |
| Kampf mit 48 Gegnern | 5,3 | 256,13 ms |

Rohdaten: `../logs/benchmark-quality-0.json`; Ablauf: `tests/benchmark.gd`. Der Test enthält Bewegung/Navigation der Gegner, aber kein dauerhaftes Feuern und keine vollständige Spielrunde. Dieser Lauf enthält die neuen Handschuhe, Meshy-Ärmel, separate Waffenansicht und komprimierte Oberflächentexturen. Er erreicht das 100-FPS-Ziel unter den genannten Bedingungen nicht. Der Export ist ein geprüfter Zwischenstand; der parallele Worker verändert die Karte weiterhin.

Ein früherer Lauf vor der Verdichtung der Baumkronen und vor Händen/Minimap erreichte 143,6–253,2 FPS im Durchschnitt; dieser Wert lässt sich nicht als Ergebnis des heutigen Endstands ausgeben. Dauerhaft mindestens 100 FPS sind noch nicht nachgewiesen. Für einen vergleichbaren neuen Lauf weitere Spielfenster schließen und `../tools/check-game.ps1 -Mode Benchmark` ausführen.

## Funktionsprüfung

`../logs/check-smoke.log`: **48 Prüfungen, 0 Fehler**. Alle fünf Waffen mit beiden Händen sowie Kameraabstand beim Zielen geprüft. Zusätzlich unabhängige Handdarstellung und Mündungsfeuer, Munitionserhaltung, Feuerrate bei verschiedenen Bildraten, Barrikaden, Nahkampf durch Wände, Wellenabschluss, Granatenpause, Fähigkeiten, Tod und Neustart. Sichtprüfung von Hüftanschlag und Zielen aller fünf Waffen sowie Nachladen und Menüs: `../artifacts/viewmodel/`.

## Technische Änderungen

Die nachfolgend ergänzten Schusseffekte wurden funktional und gerendert geprüft (`../logs/check-weaponeffects.log`: 61 Prüfungen, 0 Fehler, einschließlich 11 Screenshot-Prüfungen). Der obige FPS-Messlauf stammt vor dieser Ergänzung und vor weiteren Änderungen des parallelen Karten-Workers.

- Räumliche MultiMesh-Gruppen und Sichtweiten für Vegetation, Dekoration und wiederholte Modelle; Physikkollision bleibt erhalten.
- Jolt, zeitlich verteilte Pfadberechnung, begrenzte gleichzeitige Gegnerzahl und wiederverwendete Trefferpartikel.
- Keine Modell-Neuerzeugung pro Barrikadentreffer; vorab geladene Gegner und Sounds.
- Pausen frieren Kampf, Physik und Granaten ein; Grafik-, Audio- und Eingabeeinstellungen werden gespeichert.
- Minimap zeichnet Gelände und Wege einmal; bewegliche Markierungen werden zehnmal pro Sekunde aktualisiert.
- Die neuen Hände verwenden zwei modellierte, skelettierte Handschuhe und zwei Meshy-Ärmel je sichtbarer Waffe. Ein eigener transparenter Viewport zeichnet Waffen und Arme in voller Fensterauflösung mit 2× MSAA.
- 72 Oberflächentexturen auf GPU-Kompression und Mipmaps umgestellt: Desktop-Importdateien zusammen 64,3 MiB inklusive Mipmaps, gegenüber 246 MiB unkomprimierter RGBA-Basisbildgröße.
- Waffenfeuer: drei kurze Flash-Flächen und zwei schattenlose Lichtimpulse; Rauch wird über einen begrenzten MultiMesh-Pool gezeichnet. Die Ärmel verformen sich auf der GPU mit am Handgelenk fixierten Vertices. Waffenrückstoß verwendet eine zeitbasierte gedämpfte Feder.
