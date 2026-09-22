# Horden-Performance

Aktueller Nachtrag vom 22.09.2026: [Bildzeiten und Lagspikes](FRAME_PACING.md).
Die folgenden Messwerte dokumentieren den vorherigen Stand vom 21.09.2026.

Die Optimierung vom 21.09.2026 senkt CPU- und Spawnkosten. Grafikprofile,
Texturen, Mesh-Details, Schattenreichweiten und Physiktakt bleiben unveraendert.
Die bestehenden Grenzen gleichzeitig aktiver Wellengegner bleiben ebenfalls
bestehen; der Stresstest erzeugt zusaetzlich bis zu 300 gleichzeitige Gegner.

## Umsetzung

- Die gewichteten, konvexen Trefferzonen aller zwoelf Zombie-Modelle werden beim
  Laden vorbereitet. 262 vorberechnete Hulls ersetzen die staendig bewegten
  BoneAttachment-/Area-/CollisionShape-Knoten. Schuesse pruefen die aktuelle
  Animation inklusive Kopf und Gliedmassen bei Bedarf. Bewegungskapseln bleiben
  getrennt; Weltgeometrie, Tiere und neue Modelle verwenden weiter Godot-Physik.
- Der Hash der Ausgangsvertices validiert jeden vorberechneten Hull. Ein
  geaendertes Modell faellt automatisch auf seine nativen Trefferzonen zurueck.
- Zombiezielwahl erfolgt versetzt etwa alle 0,16 bis 0,22 Sekunden. Bewegung,
  Animation, Reichweite und Schadenszeitpunkte behalten ihren bisherigen Takt.
  Zerstoerte Ziele und wechselnde Spieleraggression werden sofort beruecksichtigt.
- Auf flachem Hoehenfeld pruefen Bodenstrahlen die Auflage und ein Capsule-Sweep
  alle weiteren Hindernisse. Treppen, Plattformen, steile Haenge, Fallen,
  Titanen und Kollisionen verwenden den nativen Bewegungsloeser. Ruhende Gegner
  pruefen ihren Bodenkontakt versetzt; entfernte Plattformen geben sie wieder frei.
- Schattenzustand und Mesh-Verweise werden zwischengespeichert. Turmsuchen
  beginnen beim naechsten Kandidaten und sind zeitlich versetzt. Verdeckt die
  Welt bereits das Ziel selbst, entfaellt die Suche nach weiteren verdeckenden
  Gegnern. Bounds und inverse Matrizen werden bei unveraenderten Posen geteilt.
- Ein separater, unsichtbarer Render-Viewport bereitet die skinned Zombie-
  Materialien/GPU-Daten vor Freigabe des Ladebildschirms vor. Headless-Server
  ueberspringen diesen Schritt.
- Tesla-Hauptblitz und Kettenspruenge teilen einen wiederverwendbaren dynamischen
  Vertexpuffer und ein Material. Segmentdichte, Zacken, Breite, Leuchten und
  Ausblendzeit bleiben erhalten; pro Schuss entfallen Mesh-/Material-Neuanlagen.
- Konstante Knochenlaengen mit Export-Rundungsrauschen werden einmal am Rig
  gespeichert, statt dieselben Positionskanaele pro Frame erneut zu mischen.
  Bewegte Kanaele und Rotationen bleiben erhalten. Die Pose-Pruefung vergleicht
  alle Clips aller Modelle mit den Originalen (Abweichung unter 0,01 mm in der
  urspruenglichen Modellgroesse).

## Reproduzierbarer Stresstest

```powershell
& C:/Users/miche/Desktop/Godot.exe --path godot --script res://tests/run.gd -- --suite=horde_performance --smoke-test --no-intro --no-music --horde-report=current --horde-combat --horde-late-wave
```

1600 x 900, vorhandenes Standardprofil `Fluessig`, Render-Skalierung 0,85,
volle Vegetation. Populationen 0/72/150/300, jeweils zwei Sekunden Vorlauf und
fuenf Sekunden Messung. Optional folgt zwoelf Sekunden Dauerfeuer mit sechs
gemischten Tuermen und einem MG; Gegner haben erhoehte Lebenspunkte, damit
die Population bestehen bleibt. `--horde-late-wave` prueft anschliessend das
bisherige aktive Limit mit 72 lebenden Gegnern, allen 228 Leichen, deren Beute
und sechs schiessenden Tuermen. Messung verwendet reale Frame-Zeitabstaende,
inklusive 95./99. Perzentil, Maximum, CPU-Spawnkosten und kompletten Spawnframes,
und speichert JSON unter
`logs/horde-performance-<Name>.json`. `--quality=1` bzw. `--quality=2` testet
die anderen vorhandenen Grafikprofile. `--horde-capture` legt Kontrollbilder
unter `artifacts/horde` ab. `meets_60fps_p95` zeigt ausdruecklich, ob die jeweilige
Messphase ihr 16,67-ms-Ziel fuer mindestens 95 Prozent der Frames erreicht.

Die Messungen stammen aus dem Editor-Lauf auf i7-11700 / RTX 3060 Ti. Sie sind
keine Garantie fuer jede Szene, Grafikeinstellung, Hardware oder lange Runde.
Es wurde kein neuer Windows-Build exportiert.

## Messstand

Vorher: `logs/horde-performance-before.json`. Optimierter Vergleich:
`logs/horde-performance-late-wave.json` (vollstaendiger Durchlauf).

| Gleichzeitig lebend | Vorher FPS | Nachher FPS | Nachher P95 / P99 |
| --- | ---: | ---: | ---: |
| 72 | 72,6 | 171,7 | 8,29 / 10,05 ms |
| 150 | 7,2 | 104,1 | 12,87 / 13,52 ms |
| 300 | 3,5 | 49,6 | 27,83 / 29,85 ms |

Die spaete Welle mit **72 lebenden + 228 toten Gegnern, Beute und sechs Tuermen**
erreicht **85,0 FPS**, P95 15,56 ms, P99 17,13 ms, Maximum 19,13 ms.
Der ueber das normale aktive Limit hinausgehende Extremtest mit **300 lebenden
Gegnern plus sechs Tuermen unter Dauerfeuer** erreicht nur **22,0 FPS**:
das Ziel dauerhaft fluessiger 300 *gleichzeitiger* Gegner ist noch nicht erreicht.
Ein 300er-Wellenumfang und 300 gleichzeitig aktive Gegner sind unterschiedliche
Lastfaelle. Es werden keine Gegner/Leichen fuer die Messung ausgeblendet.

Zusaetzlicher Vergleich (`verified` / `prewarmed`): erster Spawnframe maximal
1037,81 / 14,45 ms; maximaler gemessener Tesla-Physiktick 124,25 / 5,97 ms.
Der vollstaendige Wiederholungslauf `late-wave` hat 13,28 ms als laengsten
Spawnframe beim Aufbau der ersten 72 Gegner. CPU-Instanziierung liegt bei rund
2 bis 3 ms. Die laengeren Frames des 300er-Stresstests entstehen weiterhin
waehrend der dichten laufenden Simulation.

15 Gameplay-/Geometrie-/Effektsuiten: 937 erfolgreiche Einzelpruefungen.
Host plus drei Clients: 165 erfolgreiche Pruefungen. Zusammen 1102; dazu die
gerenderten Lasttests. Die 66 Turmeffekt-Pruefungen wurden auch mit Vulkan
wiederholt; der Tesla-Blitz wurde im Kontrollbild visuell geprueft.
Bestandene Funktionspruefungen ersetzen kein erreichtes
Frame-Zeit-Ziel; die Grenzen des Extremtests sind oben ausgewiesen.

## Regressionen und Pflege

Neue Suiten: `horde_ground` (native/optimierte Bewegung, Haenge, Kuppen,
Hindernisse aller Bewegungslayer, entfernter Boden), `horde_hit_precision`
(native/preparierte Treffer, Kopfzonen, alle Skins/Posen, Durchschuesse,
Hash-Fallback), `horde_animation` (Original-/optimierte Posen).
Bestehende Suiten: `zombie_hitboxes`, `piercing`, `aggro`, `defence`, `towers`,
`melee_weapons`, `spawn_safety`, `titan_variants`, `hut_health`, `army_waves`.
`tower_effects` prueft zusaetzlich Blitzpuffer-Wiederverwendung, volle Reichweite,
fuenf Kettenspruenge, Ausblendzeit und replizierte Effekte.
Koop: `tools/test_multiplayer.ps1` mit Host und drei Clients.

Nach dem Austausch eines Zombie-Modells die Trefferbibliothek erneuern:

```powershell
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=export_zombie_hit_shapes --smoke-test
python tools/bake_zombie_hit_shapes.py
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=horde_hit_precision --smoke-test
```

Der Bake benoetigt NumPy/SciPy nur auf dem Entwicklungsrechner. Das Spiel
benoetigt lediglich `assets/data/zombie_hit_volumes.tres`; das bestehende
Exportpreset nimmt diese Ressource mit auf. Neue Schussabfragen muessen
`Zombie.cast_ray()` verwenden, damit vorberechnete und native Trefferzonen
gemeinsam beruecksichtigt werden. Reine Welt-/Bausichtabfragen bleiben nativ.

`horde_cpu` ist ausschliesslich ein Diagnosewerkzeug. Es veraendert fuer die
Kostenaufteilung voruebergehend Kollisionsmasken/Animation und begrenzt dort
nachgeholte Physikschritte; seine Framewerte sind keine Spiel-FPS-Messung.
`--dense-combat` ergaenzt sechs Tuerme und 25 Sekunden Vorlauf, um die dichte
Nahkampfsituation zu untersuchen. Mehr RVO-Nachbarn brachten im gerenderten
Vergleich keine Verbesserung; der bisherige Produktionswert bleibt erhalten.
