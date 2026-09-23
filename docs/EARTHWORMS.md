# Erdwurmwellen

Ab Welle 12 erscheint alle vier Wellen ein grabender Riesenwurm auf den offenen
suedlichen Feldern. Welle 24 fuehrt den Grabmahr ein; ab Welle 40 kommen drei
Wuermer nacheinander. Die Koerper sind 14 beziehungsweise 19 Meter lang, mit
einem im Boden verankerten Schwanz. Es werden zwei eigene Meshy-Modelle verwendet.

## Kampfablauf

- Ankunft: 3 Sekunden gelber Erdring und einer der gelieferten Earthworm-Sounds.
- Auftauchen: 1,8 Sekunden, Erdklumpen und Kamerabeben; kein unangekuendigter Schaden.
- Offen: 7 Sekunden Zeit zum Beschiessen, danach 2,6 Sekunden feste rote Angriffsflaeche.
- Schlag: Radius 4,8 / 6 Meter, anschliessend 3,5 Sekunden Erholung.
- Abtauchen: 1,8 Sekunden. Unterirdische Bewegung maximal 9 Sekunden, sichtbar an
  einer wandernden Erdspur. Vor dem naechsten Auftauchen wieder 3 Sekunden Warnung.

Nur freiliegende Koerper nehmen Schaden. Geschuetze zielen auf die animierte
Koerpermitte und ignorieren eingegrabene Wuermer. Kopftreffer und die bestehenden
Anti-Titan-Waffenboni funktionieren. Automatisches Feuer kann einen Wurm nicht
dauerhaft festhalten. Feuer/Frost, Beute, Killwertung, Leichen und Wellenabschluss
verwenden die vorhandenen Systeme.

Eine Boden-/Hindernispruefung schuetzt Huetten und den gesamten Palisadenbereich
vor Auftauchen und unterirdischen Abkuerzungen. Wuermer greifen von aussen an.
Spielerschaden prueft Sichtschutz vom Wurm aus, ein Angriff hinter einer Wand
trifft den Spieler nicht durch die Wand. Tore werden als Teil der Palisade getroffen.
Die drei Originaldateien `Earthworm_1.mp3` bis `Earthworm_3.mp3` werden beim
Erscheinen und danach alle 24–35 Sekunden variiert; pro Wurm nur eine Stimme.
Spaeter Beitretende hoeren keine bereits vergangenen Sounds erneut.

## Gemeinsames Balancing

`encounter_balance.gd` enthaelt die Begegnungsplanung und Obergrenzen. Wurmwellen
haben Vorrang vor Feldtitanen. Jede fuenfte Welle bleibt eine Brockenwelle;
bei Ueberschneidung begleiten deren wenige Brocken die Wuermer. Kleinere Titanen
stehen auf eigenen Wellen statt zusaetzlich zu allen schweren Gegnern zu erscheinen.

| Gegner | Basis-HP | Basisschaden | Groesse |
| --- | ---: | ---: | ---: |
| Erdwurm | 2600 | 48 | 14 m |
| Grabmahr | 3800 | 62 | 19 m |
| Jagdtitan | 1700 | 45 | 8 m |
| Belagerungstitan | 3600 | 80 | 14 m |
| Aschetitan | 3000 | 60 | 19 m |
| Feldtitan | 4200 | 70 | 27 m |

Schwierigkeit multipliziert HP/Schaden wie bisher. Boss-HP wachsen ab ihrer
Einfuehrung um 4,5 Prozentpunkte je Welle bis maximal Faktor 2,6; pro weiterem
Koop-Spieler kommen 50 Prozent hinzu, maximal vier Spieler. Schaden waechst um
1,2 Prozentpunkte bis Faktor 1,4. Bossbewegung ist auf Faktor 1,25 begrenzt.
Die normalen Horde-Gegner wachsen bis Faktor 2,2 (vor Schwierigkeit).

Die Begleithorde nutzt 68 % des Budgets bei Wuermern, 72 % bei Feldtitanen, 82 %
bei Brockenwellen und 88 % bei kleineren Titanen. Armeewachstum beginnt ab Welle
8 mit 12 Prozentpunkten pro Welle, maximal Faktor 2,5. Schwere Verstaerkungen
haben 16 Sekunden Abstand, ab Welle 24 noch 12 Sekunden. Hoechstens zwei schwere
Gegner sind gleichzeitig aktiv, ab Welle 24 drei. Wurm-/Feldtitanwellen begrenzen
die gesamte aktive Population auf 40, ab Welle 24 auf 52. Das allgemeine Limit 72
und die bestehende Anpassung an langsame Frames bleiben erhalten.

Diese Werte sind eine nachvollziehbare Ausgangsabstimmung mit technischen
Regressionstests. Subjektive Schwierigkeit und Langzeitbalance benoetigen weiterhin
Spielrunden mit unterschiedlichen Waffen, Ausbauten und Spielergruppen.

## Assets und Reproduktion

1. `python tools/meshy_earthworm_quality.py design`: zwei Meshy-Bildvorlagen.
   Vorlagen zuerst ansehen; `design_straight zombie_earthworm_ancient` enthaelt
   den korrigierten zweiten Entwurf. Danach `python tools/meshy_earthworm_quality.py model`.
   Fortsetzbare Auftraege, Schluessel ausschliesslich aus lokaler Konfiguration.
2. `node tools/prepare_earthworms.mjs`: Achsenausrichtung, quellaufgeloeste PBR-Texturen
   (4K Farbe/Normalen, verlustfreies WebP), 22 verbundene Gelenke, Skinning und sieben
   Clips (`walk`, `burrow`, `emerge`, `attack`, `recovery`, `dive`, `death`).
   Die Knochenkette behaelt ihre Laengen; Maul und Zaehne bleiben formstabil.
   Angriff und Erholung schliessen mit identischer Pose aneinander an.
3. Godot headless importieren; danach Suite `export_zombie_hit_shapes` und
   `python tools/bake_zombie_hit_shapes.py` fuer die exakten Trefferkoerper.

Aktuelle Originale, Vorlagen und Auftragsbelege: `meshy_output/earthworm_quality/`.
Die Bildvorlagen steuern Anatomie, breites tiefes Maul, unregelmaessige Hautfalten
und matte, verwitterte Haut. Die beiden Image-to-3D-Auftraege verwenden Meshy 7.1
mit 4K-Geometriepass und Zielwerten von 60.000 / 70.000 Dreiecken. Tatsaechliche
Geometrie- und Texturwerte stehen in `artifacts/earthworm-mesh-quality.json`.
Diese Ueberarbeitung kostet 97 Credits: drei Vorlagen zu 9 und zwei Modelle zu 35.
Task-IDs stehen neben den GLBs in `.SOURCES.md`. Die frueheren Text-to-3D-Entwuerfe
(105 Credits) bleiben zu Dokumentationszwecken unter `meshy_output/raven_melee/`.

Die Modelle und PBR-Texturen kommen von Meshy. Das Wurmskelett und die Animationen
sind lokal erstellt: Die [oeffentliche Meshy-Rigging-API](https://docs.meshy.ai/en/api/rigging)
unterstuetzt diese gliedmassenlose Anatomie nicht verlaesslich. Es werden keine
lokalen Animationen als Meshy-Ausgabe ausgegeben.

## Pruefung

Godot-Aufruf: `Godot.exe --headless --path godot --script res://tests/run.gd --
--suite=earthworms --smoke-test --no-intro --no-music --no-foliage --difficulty=1`.
Unter Windows bei eingeschraenkten Rechten zusaetzlich `--log-file` mit einem
absoluten Pfad im Workspace vor `--` angeben.

Ohne `--headless`, mit `--render-worms`, entstehen Aufnahmen unter
`artifacts/earthworms-field.png` und `artifacts/earthworms-attack.png`.
Der Test schreibt ausserdem `artifacts/earthworm-balance.json` fuer Welle 1–40.

`powershell -File tools/test_earthworm_coop.ps1` prueft drei echte ENet-Prozesse:
Host, Client und Spaetbeitritt waehrend eines laufenden Angriffs. Pruefungen
umfassen Animation, Groesse, Trefferfreigabe, Soundzaehler, Graben und Tod.
Weitere Regressionen: `army_waves`, `titan_variants`, `titan_siege_gate`,
`spawn_safety`, `defence`, `horde_hit_precision`, `cheat_menu`.

Die Suite `earthworm_mesh_quality` prueft beide importierten Modelle direkt in
Godot: UVs/Normalen, alle Skin-Gewichte, 4K-Texturen, Knochenhierarchie, unveraenderte
Knochenlaengen in allen sieben Clips und den Uebergang vom Schlag zur Erholung.

Stand nach der Modellueberarbeitung am 23. September 2026: 30 Modell-/Animations-,
48 Kampf- und 41 Koop-Pruefungen bestanden. Die 89 Trefferpraezisionspruefungen
bestanden im zweiten Durchlauf. Im ersten Durchlauf lag eine native/baked
Oberflaechenabweichung beim unveraenderten Farmer-Modell bei 19,9 mm; der Test nutzt
zufaellige Erscheinungsvarianten, die genaue Ursache ist offen. Die Toleranz wurde
nicht gelockert.
Alle Wurm-Trefferpruefungen bestanden in beiden Durchlaeufen. Die 306 Trefferhuellen
aller 14 Modelle wurden neu gebacken. Gerenderte Nah- und Feldaufnahmen bestaetigen
Modellorientierung, Bodenkontakt und die Angriffsverformung. Windows-Release neu
exportiert und bis `MAP_READY` gestartet (Exit 0). Nicht mehr verwendete Texturen
der alten Modelle wurden aus dem Projekt entfernt; Originale bleiben archiviert.

Startbare Windows-Version: `builds/earthworms/RemZ.exe`; die danebenliegende
`RemZ.pck` muss im selben Verzeichnis bleiben. Modelle lassen sich separat mit
der Suite `earthworm_gallery` pruefen; Aufnahmen unter
`artifacts/earthworm-models.png` und `artifacts/earthworm-models-attack.png`.
Detailaufnahmen: `artifacts/earthworm-closeup-0.png` und `artifacts/earthworm-closeup-1.png`.
Die kompatible Koop-Buildkennung lautete fuer diesen Zwischenstand `remz-dev-20260923-earthworm-quality`; der Gesamtbuild mit Tuermen, Zielfernrohr und Wuermern traegt `remz-dev-20260923-komplett`.
