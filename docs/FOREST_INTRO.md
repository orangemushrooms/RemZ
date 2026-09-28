# Forest: Einstieg und Auslöser für Welle 1

Die bisherige Fünf-Meter-Zone um den Hüttenweg konnte bei einem direkten Weg über das Feld zur Hütte vollständig verpasst werden. Der Einstieg verwendet deshalb zusätzlich eine unsichtbare Linie quer zur Richtung vom Startpunkt zur Hütte, 50 Meter vom Start in Richtung Hütte. Geprüft wird die gesamte Zielseite der Linie: Auch ein grosser Bewegungsschritt oder eine versetzte Ankunft an der Hütte kann den Auslöser nicht überspringen. Die bisherige Wegzone bleibt gültig. Am Start und beim Weglaufen in Gegenrichtung beginnt keine Welle.

`Intro.reached_approach()` wird sowohl vom lokalen Intro als auch vom Host in `CoopWorld.tick()` verwendet. Im Koop genügt ein lebender Mitspieler; Logo-Sperrzeit und Host-Autorität bleiben erhalten. Die erste Welle startet nur einmal. Beginnt sie durch einen Mitspieler, aktualisiert sich auch das Briefing der wartenden Spieler.

Ein goldener Ring mit Raute markiert den nächsten Wegpunkt direkt im Bild, unabhängig von der Sichtweite im Nebel. Die Beschriftung benennt den Hüttenweg und dessen Entfernung. Der grössere Richtungspfeil zeigt ebenfalls die Entfernung zum nächsten Wegpunkt statt zur noch weiter entfernten Hütte. Abkürzungen führen nicht zurück zur bereits passierten Kreuzung; auf der Strasse bleibt die Kreuzung das Ziel, bis sie erreicht ist. Das Pausenmenü verbirgt die Hinweise, die Ankunft an der Hütte entfernt sie. Die Darstellung besteht aus einfachen Canvas-Elementen ohne zusätzliche 3D-Geometrie oder Lichter und ist nur während des Einstiegs aktiv.

Prüfung: `--suite=intro_guidance --smoke-test --no-music --no-foliage` umfasst 23 Checks für Strasse, zwei Feldwege, Rückweg, mehrfaches Überqueren, Sprung direkt zur Hütte, tatsächlichen Wellenstart, Zielentfernung, Menüs und den Host-Tick mit einem abkürzenden Mitspieler. `--render-guidance` ergänzt eine Aufnahme unter `artifacts/intro/gold-marker.png`. 338 Skripte kompilieren; 1997 Übersetzungseinträge werden ohne Fehler geprüft.

Die Änderung bleibt bis zur ausdrücklichen Freigabe des Nutzers lokal; keine Veröffentlichung.
