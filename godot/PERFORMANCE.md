# Prüfung vom 17. September 2026

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

- Räumliche MultiMesh-Gruppen und Sichtweiten für Vegetation, Dekoration und wiederholte Modelle; Physikkollision bleibt erhalten.
- Jolt, zeitlich verteilte Pfadberechnung, begrenzte gleichzeitige Gegnerzahl und wiederverwendete Trefferpartikel.
- Keine Modell-Neuerzeugung pro Barrikadentreffer; vorab geladene Gegner und Sounds.
- Pausen frieren Kampf, Physik und Granaten ein; Grafik-, Audio- und Eingabeeinstellungen werden gespeichert.
- Minimap zeichnet Gelände und Wege einmal; bewegliche Markierungen werden zehnmal pro Sekunde aktualisiert.
- Die neuen Hände verwenden zwei modellierte, skelettierte Handschuhe und zwei Meshy-Ärmel je sichtbarer Waffe. Ein eigener transparenter Viewport zeichnet Waffen und Arme in voller Fensterauflösung mit 2× MSAA.
- 72 Oberflächentexturen auf GPU-Kompression und Mipmaps umgestellt: Desktop-Importdateien zusammen 64,3 MiB inklusive Mipmaps, gegenüber 246 MiB unkomprimierter RGBA-Basisbildgröße.
