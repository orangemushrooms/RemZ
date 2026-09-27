# Kampagnenkarte

„Spiel starten“ öffnet die animierte Karte aus `godot/assets/Map.png`. Forest ist spielbar und startet die bestehende Waldhütte inklusive Intro, Schwierigkeit, Händlern und Zwischenereignissen. North End, Core, East End, The Planes und Suburbs & Lake sind entsättigt, reagieren mit grauer Hervorhebung auf die Maus und bleiben als „Under construction“ gesperrt. Alle Gebiete sind auch über die linke Liste per Tastatur erreichbar. Escape führt zurück.

Karte und Hauptmenü verwenden bewegte, prozedurale Nebelschichten und drei kleine Vogelschwärme. Interaktive Flächen und Umrisse werden gemeinsam mit der Originalgrafik skaliert; die Auswahl zeigt das vollständige Bild auch auf breiten Bildschirmen. Die Effekte laufen im pausierten Menü weiter und stoppen, sobald das Menü verdeckt ist.

Jedes Gebiet umfasst **25 Runden**. Erst wenn die Spawnwarteschlange und alle lebenden Gegner von Runde 25 erledigt sind, erscheint „Gebiet gesichert“. Es gibt keine Runde 26. Der Sieg landet in der Bestenliste und dauerhaft unter `user://campaign.json`; die Karte zeigt Beststand, Abschluss und den Gesamtstand über sechs Gebiete. Wiederholungen löschen keinen Abschluss. Nach dem Sieg führt „Kartenauswahl“ zurück zur Karte. Niederlagen behalten den bisherigen direkten Neustart. Die alten Erfolgs-IDs für Runde 30/40 bleiben erhalten, ihre Ziele liegen nun bei Runde 24/25.

Im Koop wählt der Host Forest vor dem gemeinsamen Start. Zwischenstände und Sieg werden vom Host repliziert; jeder verbundene Spieler speichert seinen eigenen Kampagnenfortschritt. Der neue Build-Fingerabdruck verhindert Sitzungen mit inkompatiblen älteren Versionen.

## Weitere Gebiete ergänzen

`scripts/campaign.gd` definiert stabile IDs, Titel, Verfügbarkeit, Szenenreferenzen, Markierungen und Polygonumrisse im Koordinatensystem des Originalbilds (1312 × 1199). Neue Level müssen zunächst mit dem Spielaufbau und dem Koop-Ladevorgang verbunden werden; danach lässt sich das betreffende Gebiet freischalten. Aktuell führt ausschließlich Forest zum vorhandenen Level. Die IDs im Speicherformat bleiben auch bei neuen Karten unverändert. Das gemeinsame Rundenlimit steht in `Campaign.ROUNDS`.

## Prüfungen

- `campaign_map`: Auswahl, gesperrte/ungültige Regionen, Trefferflächen, Fortschritt und atomare Speicherersetzung, Rückkehr, reguläre Runde 24, vollständiger Gegnerplan für Runde 25, Sieg erst nach letzter Welle, keine Runde 26, Koop-Snapshot.
- `campaign_visual`: englische/deutsche Ansicht, graues Hover, Abschlussmarkierung, 720p/Ultrawide und laufende Animation. Bilder unter `artifacts/campaign/`.
- `tools/test_campaign_coop.ps1`: zwei echte ENet-Prozesse, Host-Auswahl, synchronisierter Start, Zwischenstand und Sieg auf dem Client.
- Bestehende Suiten: `compile_all`, `menu_flow`, `smoke`, `achievements`, `boss_music`, `field_update`, `language`.

Testläufe mit `--suite=…`, `--smoke-test`, `--autotest` oder `--benchmark` ändern keine persönlichen Kampagnendaten.
