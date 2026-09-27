# Feldblumen und Lagerfeuer-Brauerei

Auf den begehbaren Wiesen und Feldern wachsen 250 einzeln sammelbare Blumen in kleinen Gruppen. Alle sechs gelieferten Modelle werden verwendet: Leichenblüte, Glutlilie, Goldschafgarbe, Dämmerdistel, Purpurrose und Veilchenglocke. **E** sammelt eine Pflanze einmal pro Runde. Wege, Gebäude, Mais, Wasser und steile Hänge bleiben frei.

Am Hauptlagerfeuer und kleinen Waldlager öffnet **C** die Brauerei. Der bestehende Grill bleibt über **E** erreichbar. Rezepte zeigen vorhandene und benötigte Zutaten, Wirkung und Flaschenbestand. Eine Zubereitung dauert vier Sekunden, reserviert die Zutaten sofort und legt eine Flasche ins Inventar. Pro Spieler läuft eine Zubereitung; bis zu acht Flaschen je Sorte können getragen werden. Im Einzelspiel pausiert das Menü den Kampf, während der Drink fertig wird; im Koop läuft die Welt weiter. Schließen des Menüs unterbricht das Brauen nicht.

| Drink | Zutaten | Wirkung |
| --- | --- | --- |
| Wiesentee | 2 Goldschafgarben | +45 Leben; bei voller Gesundheit kein Verbrauch |
| Rosenschild-Tonikum | 2 Purpurrosen | +20 Leben, 45 s weniger Schaden (−20 %) |
| Wiesenläufer | 2 Veilchenglocken + 1 Goldschafgarbe | 45 s Lauftempo +35 % |
| Glutherz | 1 Glutlilie + 1 Reizker | 25 s Schaden +25 %; alle 3 s brennende Gegner innerhalb 6 m |
| Winterblüte | 2 Veilchenglocken + 1 Parasol | 25 s erlittener Schaden −20 %; alle 3 s Verlangsamung innerhalb 7 m |
| Mondblütentraum | 1 Leichenblüte + 1 Kahlkopf | 35 s Schaden +65 % und Tempo +20 %; 12 s farbige Visionen |
| Ruhige Hand | 1 Dämmerdistel + 1 Morchel | 45 s Nachladezeit −35 % und Streuung −40 % |
| Frühlingsherz | 1 Purpurrose + 1 Goldschafgarbe + 1 Steinpilz | +60 Leben; 45 s Regeneration ×3 |

Drinks mit **I** im Inventar anklicken oder per Rechtsklick auf einen Schnellzugriffsplatz legen. Gleiche Effekte erneuern ihre Dauer; Pilze und Drinks verwenden je Attribut den stärksten Bonus. Feuer- und Frostauren benötigen freie Sicht und betreffen nur Zombies. Bosse widerstehen dem Frost stärker. Farbige Wellen, Funken, Kesseldampf und die vorhandenen Feuer-/Frostmaterialien zeigen die Wirkung. Effekte und Restdauer stehen im HUD und Inventar.

Der Host verwaltet Sammeln, Vorräte, Zutatenverbrauch, Brauzeiten, Heilung und Auren. Snapshots enthalten getrennte Vorräte, laufende Zubereitungen und verbleibende Weltfunde; eine neue Runde beginnt mit frischen Beständen.

## Modelle und Pflege

Die Originale `godot/assets/models/Flower_*.glb` bleiben unverändert und sind vom Windows-Export ausgenommen. `node tools/prepare_flowers.mjs` erzeugt die sechs `field_flower_*.glb`: vereinfachte Geometrie, 1024er WebP-Texturen, nichtmetallische Blütenmaterialien. UV-Nähte bleiben erhalten, deshalb liegen die tatsächlichen Modelle zwischen 6500 und 96055 Dreiecken. Godot erzeugt weitere LODs; Pflanzen werfen keine Schatten und verschwinden nach 65 m. Keine zusätzlichen Kollisionen oder Navigationshindernisse.

Prüfung: Godot mit `--headless --path godot --script res://tests/run.gd -- --suite=brewing --smoke-test --no-intro --no-music --no-foliage`. Mit `--render-brewing` und ohne `--headless` entstehen Ansichten in `artifacts/brewing/`. Die Suite prüft Verteilung, Sammeln, Transaktionen, Menüsteuerung, Schnellzugriff, echte Schadensmodifikatoren, Auren mit Hindernissen sowie Host-Befehle und Snapshots.
