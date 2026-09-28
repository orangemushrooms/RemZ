# Kampagnenkarte

„Spiel starten“ öffnet die animierte Karte aus `godot/assets/Map.png`. Forest startet die bestehende Waldhütte inklusive Intro, Schwierigkeit, Händlern und Zwischenereignissen. **The Planes** öffnet eine eigene, frei begehbare Erkundungsmap in Remetschwil (vorerst nur Einzelspiel, keine Wellen und kein Kampagnenabschluss). [Geodaten, Steuerung und Prüfungen](THE_PLANES.md). North End, Core, East End und Suburbs & Lake bleiben als „Under construction“ gesperrt. Alle Gebiete sind auch über die linke Liste per Tastatur erreichbar. Escape führt zurück.

Karte und Hauptmenü verwenden gegenläufige Nebelschichten mit langsam verformten Schwaden und drei kleine Vogelschwärme. Die Auswahl füllt die verfügbare Kartenfläche ohne Seitenlücken; Trefferflächen und Umrisse folgen derselben Skalierung. Der deckende Hintergrund verdeckt auch die Hüttenanzeige in der Spielwelt. Die kompaktere Seitenleiste hält den Startknopf sichtbar und lässt sich bei kleinen Fenstern per Maus oder Tastatur scrollen.

Solange eine Karte sichtbar ist, spielen in zufälligen Abständen leise Krähenrufe aus den vorhandenen Aufnahmen. Sie folgen der Gesamtlautstärke, laufen auch im pausierten Menü und stoppen beim Ausblenden beziehungsweise Spielstart. Es entstehen keine übereinanderliegenden Karten-Audiospuren.

Jedes Gebiet umfasst **25 Runden**. Erst wenn die Spawnwarteschlange und alle lebenden Gegner von Runde 25 erledigt sind, erscheint „Gebiet gesichert“. Es gibt keine Runde 26. Der Sieg landet in der Bestenliste und dauerhaft unter `user://campaign.json`; die Karte zeigt Beststand, Abschluss und den Gesamtstand über sechs Gebiete. Wiederholungen löschen keinen Abschluss. Nach dem Sieg führt „Kartenauswahl“ zurück zur Karte. Niederlagen behalten den bisherigen direkten Neustart. Die alten Erfolgs-IDs für Runde 30/40 bleiben erhalten, ihre Ziele liegen nun bei Runde 24/25.

Im Koop wählt der Host Forest vor dem gemeinsamen Start. Zwischenstände und Sieg werden vom Host repliziert; jeder verbundene Spieler speichert seinen eigenen Kampagnenfortschritt. Der neue Build-Fingerabdruck verhindert Sitzungen mit inkompatiblen älteren Versionen.

## Weitere Gebiete ergänzen

`scripts/campaign.gd` definiert stabile IDs, Titel, Verfügbarkeit, Szenenreferenzen, Markierungen und Polygonumrisse im Koordinatensystem des Originalbilds (1312 × 1199). `exploration: true` kennzeichnet die eigenständige Planes-Erkundung und verhindert Wellenfortschritt. Neue Survival-Level müssen mit Spielaufbau und Koop-Ladevorgang verbunden werden. Die IDs im Speicherformat bleiben auch bei neuen Karten unverändert. Das gemeinsame Survival-Rundenlimit steht in `Campaign.ROUNDS`.

## Prüfungen

- `campaign_map`: Auswahl, deckender Hintergrund, flächenfüllende Karte, erreichbarer Startknopf, Krähen-Wiedergabe und Stopp, gesperrte/ungültige Regionen, Trefferflächen, Fortschritt und atomare Speicherersetzung, Rückkehr, reguläre Runde 24, vollständiger Gegnerplan für Runde 25, Sieg erst nach letzter Welle, keine Runde 26, Koop-Snapshot.
- `campaign_visual`: englische/deutsche Ansicht, graues Hover, Abschlussmarkierung, 720p/Ultrawide und laufende Animation. Bilder unter `artifacts/campaign/`.
- `tools/test_campaign_coop.ps1`: zwei echte ENet-Prozesse, Host-Auswahl, synchronisierter Start, Zwischenstand, vollständiger Titanentod nach der Kriechphase und Sieg auf dem Client. Mit `-Online -ForceRelay` derselbe Ablauf über EOS und Epic-Relay.
- `titan_phases` / `titan_collapse`: Der letzte Treffer lässt den kriechenden Titanen aus seiner aktuellen Haltung vollständig auf den Boden fallen. Fehlende Gliedmaßen bleiben entfernt. Die Tests prüfen Host, Replik und alle fünf Titanenvarianten, einschließlich Tod während des Armschlags. Mit `--render-collapse` entstehen Vergleichsbilder unter `artifacts/titan-collapse/`.
- Bestehende Suiten: `compile_all`, `menu_flow`, `smoke`, `achievements`, `boss_music`, `field_update`, `language`.

Testläufe mit `--suite=…`, `--smoke-test`, `--autotest` oder `--benchmark` ändern keine persönlichen Kampagnendaten.
