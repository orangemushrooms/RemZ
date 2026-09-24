# Dachverteidigung der Waldhütte

An der Waldhütte öffnet **T** das Baumenü mit sechs Dachplätzen und der bisherigen Bodenplatzierung. Dachplatz und Waffe auswählen; die Kamera richtet sich auf die Vorschau. **R/Mausrad** dreht den Schusssektor, **E** bestätigt, **T/Escape** bricht kostenlos ab. Die Plätze verteilen sich auf beide Dachseiten. Belegte Plätze können im selben Menü repariert (35 R) und neu ausgerichtet werden.

| Meshy-Modell | Preis | Freischaltung nach Welle | Funktion |
| --- | ---: | ---: | --- |
| Sentinel | 120 R | sofort | Präzise MG-Salven |
| Flammenwerfer | 260 R | 2 | Feuerkegel gegen Gruppen |
| Mörser | 380 R | 4 | Steilfeuer mit Flächenschaden |
| Schweres MG | 450 R | 6 | Hohe Feuerrate, Überhitzung |
| Tesla-Spule | 600 R | 8 | Kettenblitze |

Alle fünf Modelle stammen aus den vorhandenen Meshy-Generierungen; Nachweise stehen in `godot/assets/models/towers.SOURCES.md` und `missing.SOURCES.md`. Es wurden keine neuen kostenpflichtigen Generierungen gestartet.

Dachtürme arbeiten automatisch. Ihre kompakten Sockel ersetzen ausschließlich das Gestell der neuen Dachaufbauten. Das Hüttengebäude, seine Türen, Vorräte, Lebenspunkte und Reparatur bleiben unverändert. Boden- und Dachtürme teilen das bestehende Limit von sechs Türmen pro Team. Aufwerten und Verkaufen bleiben beim Mechanic. Der Host prüft Bauplatz, Entfernung zur Hütte, Belegung, Freischaltung und Bezahlung; die bestehenden Koop-Snapshots enthalten auch die Dachaufbauten.

## Prüfung

Die neue Suite `roof_defences` prüft Vorschau, Menüaktionen, alle fünf Modelle, Kosten, Doppelbelegung, ungültige Koordinaten/Ausrichtung, Entfernung, tote Spieler, zerstörte Hütte, Freischaltungen, Limit, Reparatur, Ausrichtung, Rekonstruktion für spät beitretende Clients und automatische Angriffe auf echte Gegner vom Dach. `roof_visuals` erzeugt gerenderte Ansichten unter `logs/roof-*.png`.

```powershell
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=roof_defences --smoke-test --no-intro --no-music --no-foliage
```

Zusätzliche bestehende Regressionstests: `towers`, `tower_progression`, `tower_effects`, `hut_health`, `hut_restock`, `defence`. Die Snapshot-Prüfung läuft lokal; sie ersetzt keinen vollständigen Mehrrechner-Netzwerktest.
