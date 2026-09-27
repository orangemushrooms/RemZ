# Feldkämpfe und Waldgeheimnisse

Vor den Wellen 10, 15 und 20 unterbrechen verpflichtende Titanenkämpfe den normalen Ablauf. Das Team wird gemeinsam auf das südliche Feld versetzt, bekommt Munition aufgefüllt und acht Sekunden Vorbereitung. Gestorbene oder niedergeschlagene Mitspieler kehren mit 65 % Leben zurück. Erst nach dem letzten Boss öffnet sich die Feldgrenze. Die nächste reguläre Welle beginnt nach 30 Sekunden Vorbereitung.

| Vor Welle | Gegner | Belohnung pro Spieler |
| --- | --- | --- |
| 10 | Jagdtitan und Feldtitan | 350 R |
| 15 | Jagd-, Belagerungs-, Asche- und Feldtitan | 525 R |
| 20 | Alle fünf Titanen einschließlich Urtitan, Erdwurm und Grave Wyrm | 700 R |

Alle Kämpfe beginnen morgens um 06:42. Die goldene Feldgrenze ist auch auf der Karte sichtbar. Wald und Hütte bleiben bis zum Abschluss unzugänglich. Später beitretende Mitspieler werden ebenfalls auf das Feld gebracht. Der Host verwaltet Gegner, Fortschritt, Begrenzung und Belohnung.

Zwei optionale Geheimquests warten an unscheinbaren Steinen im Wald: **Der stille Hain** nach Welle 6 und **Das Gedächtnis der Wurzeln** nach Welle 12. Entdeckt und lest den Stein während einer Wellenpause, opfert drei Goldschafgarben beziehungsweise drei Violettglöckchen, besiegt die herbeigerufenen Gegner und kehrt zum Stein zurück. Belohnungen: 350/700 R sowie zwei Wiesenläufer-/Winterblüte-Tränke pro Spieler. Angenommene Quests pausieren den Wellenbeginn und markieren ihren Stein auf der Karte. Jeder Stein lässt sich einmal pro Runde abschließen.

**Strg + Shift + D → Zwischenevent / Geheimquest überspringen** überspringt jedes aktive Goa-Stadium, jeden Feldkampf und jede angenommene Waldquest. Nur Solo/Host; keine Questbelohnungen oder künstlichen Abschüsse. Zugehörige Gegner verschwinden, Musik und Begrenzungen werden zurückgesetzt, anschließend läuft die Vorbereitung weiter. Ein normaler Wellen-Skip überspringt auch ein gerade aktives Zwischenereignis.

## Weitere Änderungen

- Titanen: dreifache Basis-LP (5100 / 10800 / 9000 / 12600); Urtitan: 18000 LP. Schwierigkeit, Wellenfortschritt und Teamgröße skalieren zusätzlich. Der Forest Spirit hat 6600 Basis-LP.
- Kriechende Titanen haben einen eigenen bodennahen Schlag mit dem verbleibenden Arm; keine stehenden Angriffe, Würfe oder Todesanimationen. Schritte erschüttern den Boden stärker und weiter entfernt; die Einstellung für Kamerabeben bleibt wirksam.
- Würmer: fließende Körperwellen, zusammenhängender Angriff/Rückzug, sanftes Auf-/Abtauchen und Beschleunigen im Erdreich. Der Blitz-Aufhelleffekt läuft wieder korrekt ab.
- Rehe, Hirsche und Zombiehirsche besitzen nun ein Skelett mit 15 Gelenken und getrennten Schritt-/Laufphasen. Bewegungstempo steuert die Schritte; Bodenkontakt wird nicht mehr irrtümlich als Hindernis gewertet. Koop-Tiere interpolieren ihre Positionen.
- Sandsäcke: Stufen mit 450 / 1000 / 2000 LP, 20 / 30 / 40 % Schadensminderung. Ausbauten kosten 140 / 260 R, Reparaturen 40 / 65 / 100 R. Zusätzliche Sandsackreihen zeigen den Ausbau; die Übersteighöhe bleibt erhalten.
- Blumen: ungefähr zwei Drittel weniger Kandidaten, größerer Mindestabstand, kleinere Pflanzen, matte Materialien ohne Eigenleuchten.
- Turmplanung: eigener Spieler als Überlebendenmodell mit gut sichtbarer Positionsbeschriftung.
- Glücksräder: größere Scheiben, platzangepasste deutsche/englische Beschriftungen, Blumenbündel, alle acht Tränke und Geldgewinne bis 1000 R. Etwas höhere Gesamtgewinnchance; Waffenwahrscheinlichkeiten bleiben nach Kaufpreis gestaffelt. Volle Trankvorräte erstatten den Einsatz.

Die lokalen Modelle werden mit `node tools/rig_quadrupeds.mjs` reproduziert. `tools/refine_worm_motion.mjs` bearbeitet ausschließlich die vorhandenen Wurm-Animationsspuren. Beide benötigen keine externen Generierungsdienste.

## Prüfungen

`tools/run-field-checks.ps1` führt die Funktionsprüfungen aus. `tools/test_field_coop.ps1` prüft einen echten ENet-Host, einen Client und einen später beitretenden Client. Gerenderte Prüfungen: `field_visual`, `quadruped_visual`, `fortune_wheels --render-fortune` und `tower_planner --render-planner` über `res://tests/run.gd`. Messwerte und Screenshots liegen in `artifacts/`.

Stand 27.09.2026: 972 bestandene Funktions- und Sprachprüfungen (Deutsch und Englisch), zusätzlich 22 Netzwerkprüfungen mit drei Prozessen sowohl aus dem Projekt als auch aus dem exportierten Windows-Testpaket. Geprüft wurden insbesondere alle drei Feldkämpfe, beide Waldquests, Goa-Abbruch bei Ankunft, Kampf, Rückweg und Abschluss, genau einmal ausgezahlte Belohnungen, blockierte Fluchtversuche, spätes Beitreten, Sandsackstufen, Sprachwechsel am Glücksrad und stillstehende tote Tiere. Der Skript-Compile-Check umfasst 285 Skripte ohne Fehler.

Die Windows-Testumgebung meldet einen fehlenden System-Zertifikatsspeicher. Der Godot-Dummy-Renderer meldet beim Freigeben einzelner Materialien zusätzliche Diagnosen; der Cheat-Menü-Test wurde deshalb ebenfalls mit dem echten Vulkan-Renderer durchgeführt und bestand ohne Materialfehler. Diese Prüfungen verwenden eine lokale ENet-Verbindung; ein Internet-Match über EOS ist damit nicht abgedeckt.

Belastungstest mit allen fünf Titanen und beiden Würmern, vollständiger Vegetation, 1920 × 1080, Profil „Smooth“ (85 % Renderauflösung), RTX 3060 Ti / i7-11700. Nach drei Sekunden Aufwärmen wurden je 30 Sekunden gemessen:

| Kampfphase | Durchschnitt | 99%-Bildzeit | längstes Bild |
| --- | --- | --- | --- |
| Sieben aktive Bosse | 146,6 FPS | 11,96 ms | 18,38 ms |
| Fünf kriechende Titanen und beide Würmer | 140,8 FPS | 12,32 ms | 20,22 ms |

Eine frühere Wiederholung enthielt einzelne Wartezeiten bis 527 ms. Die Ursache ließ sich nicht sicher zuordnen; der folgende Diagnose-Lauf und der verlängerte Test reproduzierten sie nicht. Auch dieser Lauf bleibt unter `artifacts/field-performance-second.json` dokumentiert. Die Messungen belegen das Verhalten auf diesem Rechner, keine allgemeine Garantie für jede Hardware oder Hintergrundlast.
