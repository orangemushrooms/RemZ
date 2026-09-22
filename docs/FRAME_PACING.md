# Gleichmaessige Bildzeiten – 22.09.2026

Die Untersuchung betrachtet reale Abstaende zwischen einzelnen Bildern,
einschliesslich der ersten Verwendung von Effekten. Durchschnittliche FPS allein
verdecken die gefundenen Unterbrechungen von 100 bis 300 ms.

## Behobene Ursachen

- Alle Varianten der Kampf-, Schritt-, Titan- und Feuerwerkstoene werden beim
  Laden vorbereitet. Begrenzte Tonquellen werden wiederverwendet; ein Ereignis
  kann pro Bild hoechstens drei gleiche Stimmen starten. Die bisherige Grenze
  von drei gleichzeitig aktiven Stimmen je Sound bleibt erhalten.
- Ein separater Viewport rendert waehrend des Ladens die Turm-, Feuer-, Frost-,
  Granaten-, Beute- und Feuerwerksvarianten. Er bleibt danach deaktiviert erhalten,
  damit Godot die vorbereiteten Materialien und Render-Pipelines behalten kann.
  Alle Zombie-Skins werden auch mit der Frostauflage vorbereitet. Die vier
  Titanvarianten werden als vollstaendige, inaktive Akteure einschliesslich
  Warnring initialisiert; dabei entstehen keine Ankunftsrufe oder Kampfeffekte.
- Turmgeometrie, Einschlagtextur und Tracermesh werden geteilt. Einschlag-Decals
  werden im vorhandenen Ringpuffer wiederverwendet. Bewegte Elementartracer
  veraendern ihre Transformation statt in jedem Bild neue Geometrie zu erzeugen.
- Die Navigation liest die grosse statische Karte einmal beim Laden. Beim
  Palisadenbau werden nur die vier vorbereiteten Abschnittsgeometrien kombiniert.
  Datenkopie und Backen laufen in einem Worker; bis zur Veroeffentlichung bleibt
  das bestehende Wegnetz aktiv. Weitere Aenderungen loesen einen Folgeauftrag aus.
  Worker-Auftraege werden auch beim Neustart/Beenden sauber abgeschlossen.
- Die exakte Trefferpruefung untersucht zuerst die naechsten moeglichen Gegner.
  Sobald ein Treffer feststeht, entfallen weiter dahinter liegende Knochentests.
  Trefferzonen und Durchschlagsregeln bleiben erhalten.
- Punkte- und Serienanzeigen werden einmal pro Bild aktualisiert. Die sechs
  sichtbaren Punkte-Popups werden wiederverwendet. Punkte und Belohnungen werden
  weiterhin sofort berechnet. Erfolge schreiben nur neue dauerhafte Freischaltungen
  und speichern sie geordnet im Hintergrund.
- Unveraenderte Statusbeschriftungen werden nicht mehr in jedem Physikschritt neu
  gesetzt. Vollstaendig gewachsene Blutlachen benoetigen keine Groessenupdates mehr.
- Die lokale Kamera interpoliert die Bewegung zwischen Physikschritten; Mausblick
  bleibt unmittelbar. Teleports, Tod und Turmbedienung setzen den Versatz zurueck.

Die Grafikprofile, Vegetationsdichte, Physikfrequenz und bestehenden Gegnerlimits
wurden nicht reduziert. Vorladen verlagert Arbeit in die Ladephase und behaelt
zusaetzliche Ressourcen im Speicher. Ein ruhender Warmup-Viewport fuegt einige
hundert deaktivierte Knoten hinzu.

## Vergleichbare Messung

Godot 4.7.2, Vulkan Forward+, i7-11700, RTX 3060 Ti, 1600 x 900,
Profil `Fluessig`, Render-Skalierung 0,85, volle Vegetation. Im Benchmark sind
FPS-Limit und VSync deaktiviert. Basis: `logs/frame-pacing-before.json`;
Abschlussstand: `logs/frame-pacing-verified.json`. Es lief jeweils nur eine
Spielinstanz. Bei der Basismessung war der Editor zusaetzlich offen; beim
Abschlusslauf war er geschlossen. Zufallsverbrauch durch das Vorladen und
individuelle Gegnerbewegungen koennen zwischen den Laeufen variieren.

| Ereignis | Laengstes Bild vorher | Laengstes Bild nachher |
| --- | ---: | ---: |
| Erste Schritte auf mehreren Boeden | 53,76 ms | 5,66 ms |
| Erster Standardturm | 253,99 ms | 12,57 ms |
| Erster Flammenturm | 128,49 ms | 13,81 ms |
| Erster Teslaturm | 102,96 ms | 14,57 ms |
| Erste Brandmunition | 299,04 ms | 16,36 ms |
| Erste Frostmunition | 96,35 ms | 17,19 ms |
| Alle Palisaden im Gefecht bauen | 200,92 ms | 25,03 ms |
| Alle Palisaden im Gefecht zerstoeren | 203,65 ms | 24,92 ms |
| Gleichzeitiger Tod von 72 Gegnern | 99,01 ms | 23,45 ms |

72 bewegte Gegner: 180,2 → 161,7 FPS. 72 Gegner plus fuenf Tuerme und Dauerfeuer:
122,1 → 123,7 FPS, P99 13,60 → 13,85 ms. Die Verbesserung betrifft vor allem
die grossen Einzelspitzen; eine generelle Steigerung der Durchschnitts-FPS wurde
nicht gemessen. Brandmunition erreichte 112,9 FPS, P95 13,08 ms.
Die reine Aktionszeit fuer den Tod von 72 Gegnern sank von 79,76 auf 9,23 ms.
Aktionszeit ist nicht mit der gesamten Bildzeit gleichzusetzen.

Der erweiterte Lauf umfasst 37 Phasen mit allen Waffen, Granaten, Titanen,
Feuerwerk und mehreren Kartenblicken. Ein Zwischenlauf
(`logs/frame-pacing-final.json`) fand beim ersten Titan noch 111,71 ms.
Nach Vorbereitung der vollstaendigen Titanvarianten sank diese Spitze auf
8,82 ms, davon 2,40 ms fuer die Erzeugung. Granaten erreichten maximal 14,96 ms,
die drei Feuerwerkstypen hoechstens 9,01 ms.
Insgesamt wurden 25.208 Bilder in den 37 Phasen gemessen: keines ueber 33,33 ms,
Maximum 25,029 ms. Auch dieser erfolgreiche Lauf enthaelt einzelne Bilder ueber
dem 16,67-ms-Budget fuer durchgaengige 60 FPS.

Ein frueherer erweiterter Lauf (`logs/frame-pacing-extended.json`) lief parallel
zu einem zweiten Spiel und enthielt laenger anhaltende Einbrueche bis 246,53 ms.
Er wird nicht als isolierter Vorher-nachher-Vergleich verwendet. Die genaue
Ursache dieser Einbrueche wurde darin nicht isoliert.

## Reproduktion

Nur eine Spielinstanz ausfuehren, keine gleichzeitigen Exporte oder weiteren
Lasttests. Fuer vergleichbare GPU-Werte das Testfenster sichtbar halten.

```powershell
& C:/Users/miche/Desktop/Godot.exe --path godot --script res://tests/run.gd -- --suite=frame_pacing --smoke-test --no-intro --no-music --profile-navigation --pacing-report=current --pacing-extended
```

Der Bericht enthaelt Mittelwert, P95, P99, Maximum sowie die Anzahl der Bilder
ueber 33,33 und 50 ms. Die Ereignisphase beginnt vor der Aktion; kalte erste
Bilder werden nicht aus der Statistik entfernt.

```powershell
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=frame_pacing_guards
```

17 gezielte Pruefungen decken Kamerabewegung/Teleports, begrenzte wiederverwendete
Tonquellen, vorbereitete Schritte, korrekte Tracer-Endpunkte sowie geordnete
ueberlappende Speichervorgaenge ab.

## Funktionale Pruefungen

Die folgenden Suiten meldeten insgesamt 836 bestandene Einzelpruefungen:

| Suite | Pruefungen |
| --- | ---: |
| Frame-Pacing-Schutzpruefungen | 17 |
| Spielstart und Neustart (Smoke) | 66 |
| Palisaden und Wegnetz | 26 |
| Armeewellen | 61 |
| Turmeffekte | 66 |
| Titanen | 50 |
| Erfolge | 89 |
| Feuerwerk | 31 |
| Ducken | 13 |
| Zielen | 17 |
| Muendungsausrichtung | 18 |
| Exakte Hordentreffer | 64 |
| Audioereignisse | 32 |
| Einschlaege | 9 |
| Durchschuesse | 41 |
| Spezialmunition und seltener Haendler | 71 |
| Koop: Host und drei Clients | 165 |

Protokolle: `logs/pacing-*.log`; Koop-Abschluss:
`logs/pacing-multiplayer.log` und `artifacts/multiplayer/result.json`.
Der erste Koop-Lauf schlug bei einer erneuten Turmplatzierung fehl. Ein separater
Wiederholungslauf ohne parallelen Export bestand alle 165 Pruefungen. Die Ursache
des ersten Fehlers ist nicht nachgewiesen; der Test liefert jetzt beim Fehlschlag
die Platzierungsdiagnose statt danach auf ein fehlendes Arrayelement zuzugreifen.

Der Windows-Export wurde erstellt und mit der normalen exportierten Startszene
gestartet. Ein automatischer Rundgang erzeugte neun Kartenbilder unter
`builds/shots` und endete mit Exitcode 0. Ansichten von Huette, Lagerfeuer und
Waldweg wurden visuell kontrolliert.
Der abschliessend aktualisierte Build liegt unter `builds/windows/RemZ.exe`
mit `RemZ.pck` daneben (22.09.2026, 19:25 Uhr). Auch dieser Export und sein
anschliessender Starttest endeten mit Exitcode 0; Protokolle:
`logs/pacing-export-final.log`, `logs/pacing-packaged-final.log` und
`builds/windows/logs/coop-15232.log`. Die System-Zertifikatstore-Meldung trat auch
vor den Aenderungen in dieser Testumgebung auf; Scriptfehler wurden separat geprueft.

## Grenzen

Die bestehenden Wellen halten maximal 72 Gegner gleichzeitig aktiv und reduzieren
unter Last den Nachschub. Der zusaetzlich abgeschlossene, gerenderte Hordentest
(`logs/horde-performance-pacing-verified.json`, Exitcode 0) liefert:

| Lastfall | FPS | P95 / P99 | Maximum |
| --- | ---: | ---: | ---: |
| 72 aktive Gegner | 176,2 | 7,78 / 8,85 ms | 9,08 ms |
| 150 aktive Gegner | 92,2 | 15,17 / 16,85 ms | 18,72 ms |
| 300 aktive Gegner | 43,9 | 32,34 / 37,43 ms | 38,87 ms |
| 300 aktive Gegner, sechs Tuerme, Dauerfeuer | 20,8 | 66,28 / 78,64 ms | 81,95 ms |
| 72 aktive Gegner, 228 Leichen, sechs Tuerme | 78,8 | 16,96 / 20,70 ms | 38,05 ms |

300 aktive Gegner ueberschreiten das regulaere Limit. Auch die 228 gleichzeitig
behaltenen Leichen ueberschreiten die regulaere Aufraeumgrenze von 24. Der
300er-Gefechtsfall hatte vorher 19,4 FPS und maximal 144,88 ms; die Spitzen wurden
kleiner, dieser kuenstliche Extremfall ist weiterhin nicht fluessig. Die spaete
Welle mit absichtlich deaktiviertem Aufraeumen verfehlte ebenfalls das Ziel,
95 Prozent der Bilder unter 16,67 ms zu halten. Diese Ergebnisse werden nicht
als erfolgreicher Nachweis ruckelfreier Wiedergabe gewertet.

Auch ein 60-FPS-Ziel fuer jedes Bild, jede Kartenposition, hoehere Grafikprofile,
andere Hardware oder mehrstuendige Runden ist durch diese Messungen nicht belegt.

Die Pause zwischen abgeschlossenen Wellen betraegt jetzt 180 statt 120 Sekunden.
