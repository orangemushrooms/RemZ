# The Planes – Remetschwil

### Multiplayer

The Planes shares Forest's four-player ENet/EOS transport, movement validation,
combat replication, revives, spectating and reliable class-XP rewards. A host can
select The Planes from the existing co-op campaign screen; the whole lobby loads
the region together. The Planes pause menu also opens a fresh co-op lobby.
Clients joining a Planes host from Forest automatically load the correct scene.
Late joins receive existing towers, field fortifications, harvested plants,
weather, clock and wave state. Rematches reset the world while retaining profiles.

The host validates all field trades, harvesting and placement. Kit inventories,
quest acceptance, progress and rewards belong to individual players. Construction
uses the same terrain, distance, merchant-clearance and collision rules as solo;
replicated wall IDs keep upgrades stable when other walls break. Wave counts use
Forest's 55% increase per additional player, retaining the Planes active-enemy cap.
Pausing opens only the local menu during co-op. Protocol 6 requires matching builds.

Run `tools/test_planes_coop.ps1` for the two-process economy/combat/rematch suite,
add `-Online` for actual EOS accounts/transport, or `-LateJoin` for a four-process
Forest-to-Planes lobby transfer, late joins and disconnect handling. All test
profiles and save files are isolated. Push and publication remain on hold.

### Forest atmosphere and HUD

The survival mode now uses Forest music (day/night, combat, boss and game-over),
the shared day-night sky and clock, and the ten-slot Forest quickbar (1-9, 0).
Weather dims the shared lighting instead of overriding it with daytime values.
Q toggles the quest tracker, J opens the field journal, and I opens equipment
assignment. The clock pauses with gameplay; music continues as in Forest.
`--suite=planes_atmosphere` covers these integrations; `--render-atmosphere`
also saves noon and night screenshots.

Class progression uses Forest's `class_progression.gd`, `character_hud.gd` and
the existing `CharacterProfile` save. Kills, completed waves, mission completion,
deaths and claimed field quests update the same selected class; field quest IDs
use a `planes:` prefix. Retry resets reward guards, not the profile. Exploration
stops the class session. `--suite=planes_xp` verifies leveling, duplicate reward
guards, retry, isolated disk persistence and returning to Forest.

### Wild plants and eastern access

Ordinary meadow flowers and woodland mushrooms can now be gathered with E within
2.5 m, as well as the marked quest bundles. Gathering removes the existing plant
instance and counts towards the corresponding quest; a plant cannot be gathered
twice in the same run. Retry restores it. An 8 m spatial index restricts proximity
queries to nearby cells; no individual plant physics bodies or frame callbacks
are added, and the existing MultiMesh batches are retained.

The eastern boundary extends uphill through (300,-290), (370,-235), (395,-205),
(440,-182) to x=515. Fence, player confinement, minimap, construction and navigation
use this same outline. Residential buildings still have at least 10 m clearance.
The navigation check additionally verifies a route into the new uphill area.

### Sennhofstrasse surface correction

The user confirmed the northern village-edge Sennhofstrasse, separate from the
gravel track through the fields. Its cached OSM tertiary sections now use a
6 m two-way asphalt carriageway (authored width; the source has no width tag).
Terrain, crop exclusion and minimap share the widened road mask/data. Existing
asphalt albedo and normal textures replace the former flat soil-tinted surface,
with a restrained wet-weather response and no extra road meshes/draw calls.
The field tracks retain gravel. Three trees in the widened eastern roadside are
removed; all retained foreground tree positions and terrain heights are preserved.
Rendered dry/wet views are in `artifacts/planes/road/`. Simultaneous gameplay in
another RemZ process prevents a reliable FPS comparison for this small correction.

## Survival release, 28 September 2026

Publication is now explicitly authorised. The historical publication holds below
are superseded by the request for the complete survival release.

Survive 25 waves anywhere within the field boundary; there is no hut health or
fixed defence objective. Vendor, Mechanic and campfire occupy the grassy fork;
the Secret Vendor is in the central woodland. E interacts, B opens carried wall
kits, R rotates a placement, E confirms, T opens the shared tower planner and J
shows accepted quests. Esc closes the current panel before opening pause.

Start with a pistol, three grenades and 150 R. Palisades cost 50 R, sandbags 60 R;
valid placements alone consume kits. Forty carried/placed fortifications are
allowed. Terrain, boundary, slope, collisions, reach and merchant access are
validated. Structures use Forest health, armour, repair and upgrade definitions.
Turrets can be purchased in T away from merchants; upgrades require Mechanic.
Training and weapon modifications use the shared catalogues and prices.

Nine independent quests cover construction, flowers, mushrooms, kills, headshots,
repairs, brutes and survival. Rewards are claimed once at their quest giver.
Collectible markers appear after acceptance; all run state resets on retry.
Advanced weapons retain wave gates but do not require Forest quest completion.
The six class weapons of 30 Sep 2026 (SIG P226, Nighthawk .45, AR-15, Tommy gun, SPAS-12,
sawed-off) come through the same `Progression.GOODS` table, so they are on sale here at the
Vendor from waves 1-4 at Forest prices; `--suite=class_weapons` covers the catalogue.

Waves use difficulty-scaled counts of 10 + 4 × wave, increasingly mixed enemies
and brutes every fifth wave. Initial preparation lasts 90 seconds, breaks 60;
Enter starts early. Intermission pays 50 + 5 × wave R, heals 20 HP and grants
one grenade every third wave, respecting pouch upgrades. Ammunition is purchased
or collected. At most 24 enemies are active (16 under sustained slow frames),
with 12 retained corpses. First-use turret and wall resources are warmed while
loading. One redundant Recast detail face is removed before publishing navigation;
the resulting mesh has no multiply owned edges.

Validation: 345 scripts compile; 35 survival checks exercise all 25 accelerated
wave transitions, death/retry and return to Forest; Forest defence passes 99
checks. The gameplay suite passes 39 checks in the project and exported pack, covering purchases, actual zombie attacks on placed
walls, repairs, quests, mods, training, sandbags, planner and reset. Rendered
camp/shop captures and benchmark JSON are in `artifacts/planes/gameplay/`.

On the test RTX 3060 Ti at 1920 × 1009, the fixed-view uncapped benchmark measured
109.1 FPS without combat, 83.3 FPS with 40 towers, 40 walls and 24 enemies, and
78.4 FPS with that load in a storm (p95 frame times 9.93 / 14.81 / 16.30 ms).
These are measured scenarios, not a guarantee for every PC or every playthrough.
The known Windows root certificate warning also appears in otherwise clean runs.

In der Gebietsauswahl **The Planes starten** wählen. Die Region startet nach dem Laden direkt als 25-Wellen-Survival mit Pistole, Feldmesser und 150 R. Das Mausrad wechselt wie in Forest zwischen freigeschalteten Waffen. Das Esc-Menü bietet weiterhin den optionalen Erkundungsmodus. Im Koop ist Planes gesperrt.

WASD bewegt den Spieler; Shift sprintet, Leertaste springt, Strg duckt sich. M vergrössert die nordorientierte Karte wie in Forest und stellt sie beim nächsten Druck wieder kompakt dar. Escape öffnet ein Menü mit Fortsetzen, Survivalstart, drei Referenzblickrichtungen und Rückkehr zur Gebietsauswahl. Im Kampf pausiert dieses Menü auch Zombies, Wetter und Granaten; die Foto-Teleports sind dort gesperrt. Die Fotoansichten lassen sich damit ohne erneuten Fussmarsch vergleichen.

## Geografische Grundlage

- Referenzpunkt: **47.404384449011665, 8.335047115511859** ([Google Maps](https://www.google.com/maps?q=47.404384449011665,8.335047115511859)). Der interaktive Google-Viewer war beim Aufbau nicht auslesbar; die fünf vom Nutzer bereitgestellten Bilder bilden die visuelle Referenz.
- Lokales Koordinatensystem: LV95, X ostwärts, Z südwärts, Y relativ zum Referenzpunkt. Eine Spieleinheit entspricht einem Meter. Der geografische Ursprung liegt bei LV95 E 2667663.52 / N 1250782.42 (swisstopo-Polynomumrechnung).
- [swissALTI3D](https://www.swisstopo.admin.ch/de/hoehenmodell-swissalti3d): 0,5-m-Ausgangsraster des verfügbaren Jahrgangs 2021, auf ein 1-m-Spielraster abgetastet. Der Hintergrund verwendet 2-m-Quelldaten und ein 10-m-Spielraster. Die Daten werden nicht in der Höhe skaliert oder für Wege künstlich eingeebnet.
- Referenzhöhe 570,72 m ü. M.; Weggabelung Rigiweg etwa 557,4 m; Anschluss Richtung Sennhof etwa 655,2 m. Der Gelände-Ausschnitt misst 890 × 700 m. Die begehbare Grenze liegt acht Meter innerhalb des Terrainrasters.
- [OpenStreetMap](https://www.openstreetmap.org/copyright): Wege und Gebäudegrundrisse aus einem Umkreis von 1200 m. Hauptweg OSM 54857308, Rigiweg 56070837, südlicher Feldweg 118083377. Die grosse Fotogabelung liegt rund 115 m westlich des gesetzten Referenzpunkts.
- [SWISSIMAGE / swisstopo](https://www.swisstopo.admin.ch/de/orthobilder-swissimage-10): Luftbildabgleich für Parzellen und Gehölzstreifen. Das Luftbild wird nur als Baugrundlage verwendet, nicht als flache Spieltextur.

Quellen-URLs, Rasterauflösungen und SHA-256-Prüfsummen stehen in `godot/assets/planes/sources.json`. Bezug am 28. September 2026. © swisstopo; © OpenStreetMap-Mitwirkende, ODbL.

## Bildrekonstruktion und Grenzen

Die sommerliche Mais-/Getreidebelegung folgt den Fotos; sie ist keine Aussage zur heutigen Fruchtfolge. Parzellengrenzen, die Baumreihe westlich am Rigiweg und die beiden Gehölzgruppen wurden mit dem Luftbild abgeglichen. Baumhöhen, Kronenformen und Gebäudefassaden sind angenähert. Die Dorfkulisse nutzt vorhandene Fassadenbausteine auf OSM-Grundrissen. Die kleinen Markierungen an der Maisecke sind geometrisch angedeutet; unlesbare Beschriftungen wurden nicht erfunden. Eine vermessene, fotogrammetrische 1:1-Reproduktion sämtlicher sichtbarer Objekte ist damit nicht erreicht.

Mais verwendet unverändert die vorhandenen `assets/cornfield/corn_*.res` mit Wind und drei Detailstufen. Diese vorhandenen Maisressourcen sind im Projekt erzeugte Meshes. Raben/Eulen verwenden die vorhandenen Meshy-Modelle `raven_real.glb` / `owl_real.glb`, bestehende Animationen und Rufe; Eulen bleiben in der sommerlichen Mittagsansicht verborgen. Gehölze verwenden inzwischen das bestehende Meshy-Astgerüst `tree_birch.glb` mit kleinen Blattgruppen aus dem vorhandenen Buchenatlas; die früheren geschlossenen Kronen aus `tree_autumn_a/b.glb` werden in Planes nicht mehr verwendet. Die Originalmodelle bleiben unverändert. Gras nutzt den vorhandenen Atlas. Da kein Getreidemodell vorhanden ist, ergänzt ein natives, instanziertes Halmen-/Ährenmesh die Bibliothek. Es wurden keine neuen Meshy-Generierungen beauftragt.

Terrain, Pflanzen und Weltkoordinaten verwenden dieselben Höhen. Pflanzen sind räumlich gebündelt; Nah-/Fernmeshes werden kameranah gewechselt. Wege bleiben frei. Bäume besitzen Stammkollision, Häuser blockierende Grundrisskörper, Gelände einen Höhenfeld-Collider. Die Erkundung verwendet den bestehenden Spielercontroller einschliesslich Schritten auf Kies, Gras und Mais.

## Reproduzieren und prüfen

```powershell
python tools/planes_geo.py
python tools/build_planes.py
# Anschliessend Godot-Import ausführen.
Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=planes --smoke-test
Godot.exe --path godot --windowed --resolution 1600x900 --script res://tests/run.gd -- --suite=planes --smoke-test --render-planes --quality=2
```

`--planes-roundtrip --no-intro --no-music` ergänzt den tatsächlichen Rückweg in die Forest-Gebietsauswahl. Die Suite prüft Regionsdatenwechsel, friedlichen Einstieg, Höhen, Terrainkollision, freie Wege, vorhandene Modelle, tatsächliche Bewegung und Menübedienung. Referenzbilder und Luftbildüberlagerung entstehen unter `artifacts/planes/`. Zusätzlich die bestehenden Suiten `compile_all` und `campaign_map` ausführen. Tests sollten mit isoliertem `APPDATA` unter `.test-user` laufen.

Der Windows-Export enthält die eigenen JSON-/Höhenraster durch die ergänzte Export-Inklusion. Der Einstieg kann für eine direkte Ortsprüfung auch mit `--path godot res://scenes/planes.tscn` erfolgen. Die fertige EXE unterstützt `RemZ.exe -- --explore-planes`; der normale Einstieg bleibt die Gebietsauswahl.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Rendered -RoundTrip
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Packaged
```

## Landschaft und Leistung, 28. September 2026

Die Gebietsauswahl öffnet ohne vorgewähltes Gebiet. Gras wurde von rund einer auf zwei instanzierte Büschel pro Quadratmeter erhöht. 401 statt 308 Bäume, vorhandene fotografische Blattkarten, Rindendetails und 7004 Unterwuchsbüschel verdichten die Gehölze. Ein eigenes Laub-/Bodenmaterial ersetzt den zu hellen Waldboden; Kies bleibt auf der Wegmaske.

Die Dorfhäuser folgen nun den tatsächlichen OSM-Polygonen mit einzelnen Dachflächen. Überlappende gedrehte Begrenzungsboxen und gestapelte Dachplatten verursachten vorher Tiefenkonflikte. Auch Kollisionen und Navigationshindernisse folgen den zerlegten Grundrissen.

24-m-Baumzellen, vereinfachte Schattenmeshes aus den bestehenden Meshy-Modellen und ausgedünnte entfernte Mais-/Getreideinstanzen sparen Geometrie. Die zufällige Instanzreihenfolge hält auch die reduzierten Felder flächig bedeckt. `tools/planes_tree_lods.mjs` reproduziert die Schattenmodelle.

Grafikvergleich: RTX 3060 Ti, High quality, 1920 × 1009, VSync/Limit aus, dieselben fünf Kamerapositionen, je 3 s Aufwärmen und 200 gemessene Frames. Erkundung vor/nach der Landschaftsänderung:

| Ansicht | Vorher FPS | Nachher FPS | Nachher p95 ms |
|---|---:|---:|---:|
| Sennhof | 42.58 | 91.80 | 11.27 |
| Gabelung | 45.17 | 102.26 | 10.14 |
| Core | 73.48 | 105.79 | 9.86 |
| Gehölz | 55.97 | 126.47 | 8.29 |
| Dorf | 140.90 | 167.88 | 6.38 |

Messdaten und Bilder: `artifacts/planes/performance/before.json` und `graphics3.json`. Das sind Messungen auf dieser Maschine, keine Garantie für unveränderte FPS auf jeder Hardware.

Zusätzlicher Belastungstest mit 24 aktiven Gegnern aus Welle 25 und sichtbarer Waffe: 74–127 FPS bei klarem Wetter, 74–127 FPS im Gewitter, p95 zwischen 8.49 und 13.70 ms. Gemessen separat ohne parallele Testprozesse (`combat-clear.json`, `combat-storm.json`). Gegner, Waffen und Wetter haben zusätzliche Renderkosten gegenüber der verbesserten leeren Erkundungsmap; ein pauschaler FPS-Gleichstand für jede Situation wird nicht behauptet.

## Survival-Grundlage

Exploration startet ohne Gegner. **Esc → Start 25-wave survival** lädt die Navigation und gemeinsamen Zombie-/Waffenmodelle hinter dem Ladebildschirm. 1/2/3 wechseln Pistole/AK-47/Schrotflinte; R lädt nach, G wirft eine Granate, H schlägt, rechte Maustaste zielt. Enter überspringt die Start-/Zwischenpause. Bei jedem dritten Abschuss fällt ein vorhandenes Munitionspaket. Nach jeder Welle werden Gesundheit, Munition und drei Granaten aufgefüllt; E erlaubt einmal pro Welle die Selbstwiederbelebung.

Der Gegnerplan wächst über 25 Wellen, mit Läufern, Krankenschwestern, Soldaten und jeder fünften Welle Brutes. Höchstens 24 lebende Gegner gleichzeitig (bei hoher gemessener Framezeit 16), höchstens zwölf Leichen. Spawns werden auf Erreichbarkeit, Abstand und freie Kollision geprüft. Erst wenn Warteschlange und lebende Gegner leer sind, zählt eine Welle. Runde 25 speichert den Planes-Kampagnenabschluss; danach folgen Neustart, Erkundung oder Kartenauswahl.

Das Sommerwetter wechselt innerhalb eines 16-Minuten-Zyklus zwischen klar, Nebel, Regen und Gewitter. Es verwendet die vorhandenen Regen-/Nässe-/Blitz-/Donnersysteme mit Distanznebel. Quests, Barrikaden, Türme und NPCs sind nicht Bestandteil dieser Map. Die spätere besondere Spielmechanik bleibt offen.

Zusätzliche Tests: `--suite=planes_navigation`, `--suite=planes_survival`, `--suite=planes_perf --planes-perf=label`. Für den Belastungstest ergänzt `--planes-combat-perf` eine volle 24er-Horde aus Welle 25; `--planes-storm-perf` aktiviert Gewitter. Der Survivaltest beschleunigt die Wellenfolge und prüft alle 25 Zustandsübergänge mit echten Gegnern; er ist kein vollständig ausgespielter 25-Wellen-Durchlauf.

Geprüft: 333 Skripte kompiliert; 42 Kampagnenprüfungen; 24 Erkundungs-/Regionswechselprüfungen; 33 Survivalprüfungen mit Renderer und 34 im abschliessenden Test inklusive Szenenwechsel mit noch laufenden Effekten; 146 Waffenprüfungen in Forest. Der vorhandene Waffeneffekttest musste vor seinem Schuss die inzwischen eingeführte Wechselverzögerung abwarten. Deutsche Texte: 1992 Einträge ohne fehlende Übersetzungen oder Platzhalterfehler. Der tatsächliche Windows-Release erreicht sowohl `PLANES_READY` als auch `PLANES_SURVIVAL_READY` ohne Spiel-/Skriptfehler.

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_planes.ps1 -Survival` prüft den Kampfbetrieb samt Rückkehr. `-Packaged -Survival` prüft den tatsächlichen Windows-Release inklusive Navigation und Laden der Gegner/Waffen; `-Packaged` prüft den friedlichen Einstieg.

Die isolierte Testumgebung meldet beim Start einen nicht lesbaren Windows-Zertifikatsspeicher. Die Prüfung toleriert ausschliesslich diese Umgebungsfehlermeldung; andere Engine- und Skriptfehler lassen sie scheitern. Die Map bleibt Einzelspiel.

## Fassaden und natürlicher Unterwuchs

Nachbesserung vom 28. September: OSM-Grundrisse haben unterschiedliche Umlaufrichtungen. Dadurch lagen vorher bei 429 von 585 Gebäuden Fenster und Läden innen. Die Grundrisse werden jetzt vor dem Bau einheitlich ausgerichtet. Fensterläden, Eingänge, Dachgeschossfenster, Kamine, Sockel, Dachränder und Holzpartien unterscheiden wieder Wohnhäuser, Bauernhäuser, Scheunen und Schuppen. Diese architektonischen Details sind Annäherungen aus dem vorhandenen Baukastensystem; vermessen bleiben Grundrisse und Gelände. Dächer besitzen weiterhin genau eine Dachhaut. Die Texturkoordinaten folgen jeder Oberfläche, wodurch Dachziegel und Holz nicht mehr auf eine Linie gestaucht werden. Fenster verwenden weniger verdeckte Geometrie als zuvor.

Der Wald erhält **18’921 Farne und 22’042 zusätzliche Grasbüschel** statt 7004 gleichmässig gesetzter Farne. Kontinuierliche Zufallspositionen, unterschiedliche Breiten/Höhen/Drehungen und über Zellgrenzen hinweg wechselnde Pflanzendichte ersetzen das 1,5-m-Raster. Eine feste Zufallsfolge hält die Landschaft bei jedem Besuch stabil. Die vorhandenen Gras-/Farntexturen werden weiterverwendet; Wege und Anbauflächen bleiben frei. Distanzabhängige Ausdünnung begrenzt die Renderkosten.

Vergleich direkt mit der vorher veröffentlichten Version, ohne zweite laufende Spielinstanz; gleiche Hardware, Auflösung und Messmethode wie oben (`detail-baseline.json`, `detail-after.json`):

| Ansicht | Vorher FPS | Nachher FPS | Nachher p95 ms |
|---|---:|---:|---:|
| Sennhof | 83.27 | 90.11 | 11.53 |
| Gabelung | 95.51 | 102.63 | 10.21 |
| Core | 100.87 | 108.59 | 9.69 |
| Gehölz | 116.55 | 121.08 | 8.78 |
| Dorf | 160.92 | 169.84 | 6.42 |

In diesen fünf Ansichten kein gemessener FPS-Rückgang. `--suite=planes_buildings` prüft die tatsächlich erzeugten Fensterflächen und Dach-UVs an einem konkaven Grundriss in beiden Umlaufrichtungen. Die Erkundungssuite prüft zusätzlich Vegetationsdichte, Abstand vom früheren Raster sowie freie Wege und Felder. `--planes-detail-views` ergänzt im Grafiktest Nahansichten von Wald und Häusern.

Aktueller Belastungstest mit 24 Gegnern aus Welle 25 und Gewitter: 77–127 FPS in den fünf Vergleichsansichten, p95 8,83–13,27 ms (`detail-storm.json`). Die zusätzliche Wald-Nahansicht erreicht 94 FPS. 334 Skripte kompilieren; vier Geometrieprüfungen und 26 Erkundungs-/Regionswechselprüfungen bestehen.

## Offene Baumkronen, dichtere Wiesen und Forest-Minimap

Die nächste Überarbeitung vom 28. September ersetzt die geschlossenen, kantigen Kronenvolumen durch das vorhandene Meshy-Astgerüst mit neun unregelmässigen Blattgruppen pro Baum. 420 kleine Blattkarten ersetzen die massiven Kronenflächen. Lokale Mipmaps stabilisieren entfernte Blätter, separate reduzierte Schattenkarten begrenzen die Schattenkosten. Astgerüste wechseln zwischen 3486 und 663 Dreiecken; `node tools/planes_branch_lods.mjs` erzeugt beide Modelle reproduzierbar aus `tree_birch.glb`. Alle 401 Standorte und die Stammkollisionen bleiben erhalten.

In der Nähe ersetzen vier versetzte, gemeinsam zufällig gedrehte Kleinbüschel jede bisherige Wieseninstanz. Jede Karte wiederholt das vorhandene Grasbild mit schmaleren Halmen. Die Gesamtzahl der Instanzen und Draw Calls steigt dadurch nicht. Ab 30 m Zellabstand genügt eine vereinfachte gekreuzte Karte; distanzabhängige Ausdünnung bleibt aktiv. Ein eigenes Grasmaterial verhindert schwarze Rückseiten. Es verändert weder den Atlas noch die Forest-Materialien.

Die Planes-Minimap erbt Layout, Massstab, Kompass und M-Vergrösserung von Forest. Sie zeigt Höhen-Schattierung, Gehölze, Felder, Strassen und reale Gebäudegrundrisse, dazu Ortsnamen, Blickkegel, einen deutlichen Spielerpfeil und Gegner im Survival. Die statische Karte wird einmal in einer Textur gerendert; nur dynamische Symbole aktualisieren sich zehnmal pro Sekunde. Sie bleibt beim Vergrössern innerhalb des Fensters und kann während des Gehens benutzt werden. Die Legende ist auch deutsch verfügbar.

Geprüft: 334 Skripte kompilieren, 1993 Übersetzungseinträge ohne Fehler. Der gerenderte Erkundungstest einschliesslich tatsächlicher M-Tastendrücke, 720p-Layout, sichtbarem Kartencache und Rückkehr nach Forest besteht mit **33 Prüfungen**. Die Grafikprüfung umfasst nun zusätzlich Nahansichten der Baumkronen und einer Wiese. Die tatsächliche Windows-EXE erreicht sowohl `PLANES_READY` als auch `PLANES_SURVIVAL_READY`.

Zusätzliche Einsparungen: 48-m-Baumgruppen verringern die Zahl der Draw Calls; lokal erzeugte Gras-Mipmaps stabilisieren feine Halme. Der Boden-Shader liest nur Texturen von tatsächlich beteiligten Materialschichten, ohne die Maskenübergänge zu verändern. Ein Rendervergleich des bisherigen und optimierten Bodenmaterials an drei Positionen, jeweils trocken und nass, besteht in allen sechs Fällen. Explizite Texturgradienten erhalten die Filterung auch an Maskenkanten. Die Prüfung isoliert den Boden und deaktiviert bewegte Schatten sowie zeitliches Antialiasing; Kontrollaufnahmen ohne Shaderwechsel sind identisch. Unter 0,011 % der Farbkanäle unterscheiden sich um mehr als zwei 8-Bit-Stufen (`logs/planes-terrain-parity.log`).

Abschliessender Vergleich mit dem veröffentlichten Commit `fc7b26b763ea`, auf derselben RTX 3060 Ti bei High, 1920 × 1009, ohne FPS-Limit und ohne zweite Spielinstanz. Die alte Fassung wurde zum Gegencheck erneut gemessen; ihre vier Landschafts-/UI-Skripte wurden dabei als temporäres Ressourcenpaket geladen. Unveränderte Quelldaten und Modelle sowie dieselben Kameras, drei Sekunden Aufwärmzeit und 200 Frames pro Ansicht sorgen für Vergleichbarkeit. Messdaten: `canopy-baseline-repeat.json` / `canopy-verified.json` in `artifacts/planes/performance/`.

| Ansicht | Vorher FPS | Nachher FPS | Nachher p95 ms |
|---|---:|---:|---:|
| Sennhof | 90.44 | 90.95 | 11.47 |
| Gabelung | 102.35 | 101.35 | 10.29 |
| Core | 110.19 | 109.38 | 9.63 |
| Gehölz | 122.24 | 162.70 | 6.60 |
| Dorf | 169.45 | 169.93 | 6.35 |
| Wald nah | 110.78 | 148.47 | 7.13 |
| Wiese nah | 120.48 | 133.87 | 7.89 |

Die Waldansichten gewinnen rund 33–34 %, die dichtere Wiesen-Nahansicht rund 11 %. Die übrigen Ansichten liegen innerhalb von ±1 % des Ausgangsniveaus. Dies sind Stichproben auf dieser Maschine, keine Garantie absolut identischer FPS in jeder Situation. Ein separater Test dieser Überarbeitung mit 24 Gegnern aus Welle 25 und Gewitter erreichte 77–129 FPS (`canopy-storm.json`, vor den abschliessenden Boden-/Mipmap-Optimierungen).

## Scheibenstand am südlichen Feld

Der vom Nutzer identifizierte Grundriss OSM 1558294553 bei lokal (176,2 / 218,3) ist die Zielanlage des Schützenhauses an der Hauptstrasse (OSM 118083383). Die bisherige Ableitung als generisches Gebäude war falsch; die Quelle enthält zusätzlich `layer=-1`. `annotate_target_stand()` in `tools/build_planes.py` erhält die Korrektur auch bei einem erneuten Datenaufbau.

An derselben Stelle steht jetzt ein niedriger Betonstand mit sechs Scheiben und rückwärtigen Schutzplatten. Die Ausrichtung folgt dem Grundriss des Schützenhauses hangabwärts. Die [SG Remetschwil](https://sgremetschwil.ch/startseite/ueber-den-verein/schiessanlage-anfahrt/) bestätigt sechs Ziele und 300 m Schiessdistanz; ihre Fotos dienen als zusätzliche Referenz. Bauhöhe (maximal 2,3 m über dem örtlichen Bezugsboden) und kleine Bauteile sind angenähert. Die Minimap zeigt ein Scheibensymbol; der hohe ehemalige Gebäudekörper blockiert weder Bewegung noch Schüsse oberhalb des neuen Standes. Der Ort erhält damit keine eigene Spielmechanik.

Der Stand verwendet vorhandene Materialien und statisch zusammengefasste Geometrie: 348 statt 358 Dreiecke und nur zwei Materialgruppen. `planes_buildings` prüft Klassifizierung, sechs korrekt ausgerichtete Scheiben, Bauhöhe und Geometriebudget zusätzlich zu den Fassadenprüfungen (8/8 bestanden). `planes` prüft reale Raycast-Kollisionen an allen Scheiben und freien Raum über dem Stand (32/32 im gerenderten Durchlauf bestanden); `--render-targets` speichert eine Nahansicht und den Blick vom Feldweg unter `artifacts/planes/`.

## Gemeinsame Menüs und Naturdetails (lokaler Arbeitsstand)

Escape verwendet jetzt denselben Pausenmenü-Aufbau wie Forest: Weiter, Briefing, Schwierigkeit, Steuerung, Einstellungen und Hauptmenü. Einstellungen wirken sofort; die Schwierigkeit ist während einer laufenden Survival-Runde gesperrt. Die Gebietsauswahl und der Wechsel zwischen Erkunden und Survival stehen im Briefing. Das separate Menü mit Fotostandpunkt-Teleports entfällt. Die Menüs passen auch in 1280 × 720.

Ctrl+Shift+D öffnet das gemeinsame Cheat-Menü auch beim Erkunden: Geld, sämtliche Waffen mit Munition, Wetter und Gegner-Spawns; im Survival-Modus zusätzlich Wellen überspringen. Navigation und Waffen werden bei Bedarf geladen. Ziele der Waldhüttenkarte (Hüttenschlüssel, Händler, Geheimquests) werden hier nicht angeboten. Die beiden HUD-Build-Hooks in `hud.gd` lassen Forest seine vorhandenen Multiplayer- und Charakteransichten behalten.

`planes_nature.gd` platziert 14'655 Blumen und 504 Pilzgruppen auf geeignetem Untergrund, mit vorhandenen Meshy-Modellen und zufälligen Gruppen, Grössen und Drehungen. Bewirtschaftete Felder, Wege und Gebäude bleiben frei. Statische MultiMeshes teilen sich Geometrie und Materialien, gruppiert in 48-m-Zellen; Sichtweiten sind 58 m für Blumen und 38 m für Pilze, ohne zusätzliche Schattenwürfe. Die Pflanzen sind Landschaftsdetails. Die 14 vorhandenen Raben/Eulen verteilen sich auf mehrere Weg- und Waldränder. Sechs Rehe und zwei Hirsche übernehmen Forests Skelettanimationen sowie Weiden und Flucht; jenseits von 180 m pausiert die Tiersimulation.

`node tools/planes_plant_lods.mjs` erzeugt elf Landschaftsvarianten aus den vorhandenen Meshy-Modellen. Farben stammen aus deren eigenen Texturen; doppelte Flächen und UV-Nähte werden vor der Reduktion bereinigt. Die Blumen benötigen 1154–1198 Dreiecke statt bis zu 96'055, die Pilze 666–700. Zusammen belegen die abgeleiteten GLBs rund 340 kB. Die detaillierten Forest-/Inventarmodelle bleiben unverändert. Konstante Wetterwerte lösen keine unnötige Neuberechnung des Himmels mehr aus.

`planes_life` prüft Geländezuordnung, Wildtiere, echte Menü-Tastatureingaben, Waffen-/Wetter-/Gegner-Cheats, Wellenwechsel und die Rückkehr zum Erkunden. `--render-life` legt Nahansichten und Menübilder unter `artifacts/planes/life/` ab. `planes_cleanup` prüft wiederholtes Entfernen gepanzerter Gegner: ihre Geometrie wird gelöst, solange die instanzbezogenen Materialien noch leben, um ungültige Materialreferenzen im Godot-Renderer zu verhindern.

Bestanden: 337 Skripte kompilieren, 32 Erkundungsprüfungen, 25 Natur-/Menüprüfungen, 34 Survivalprüfungen einschliesslich aller 25 beschleunigten Wellenübergänge und 60 Cheat-Menüprüfungen der Waldhüttenkarte. Die drei Prüfungen der Gegnerbereinigung bestehen sowohl headless als auch mit Vulkan; die gemeinsame Korrektur in `Zombie._exit_tree()` deckt auch Forest und normale Leichenentfernung ab. Die Übersetzungsprüfung meldet 1995 Einträge ohne Fehler. Nach der Modell- und Wetteroptimierung wurden Natur-/Menü- und Survivalprüfung erneut erfolgreich ausgeführt und die Pflanzenfarben in Nahaufnahmen kontrolliert.

Leistungsvergleich mit dem veröffentlichten Commit `9502472d5ef3`, RTX 3060 Ti, High, 1920 × 1009, ohne zweite Spielinstanz, gleiche Kameras und je 200 Messframes nach drei Sekunden Aufwärmen: `artifacts/planes/performance/life-baseline-clean.json` / `life-final.json`. Die bisherigen Skripte wurden aus dem Commit als temporäres Ressourcenpaket geladen. Der frühere Versuch `life-before` mit gleichzeitig laufender RemZ-Instanz wird verworfen.

| Ansicht | Vorher FPS | Nachher FPS | Nachher p95 ms |
|---|---:|---:|---:|
| Sennhof | 89.68 | 90.31 | 11.56 |
| Gabelung | 101.65 | 102.53 | 10.13 |
| Core | 108.36 | 107.26 | 9.75 |
| Gehölz | 161.31 | 160.03 | 6.77 |
| Dorf | 169.44 | 167.16 | 6.47 |
| Wald nah | 144.66 | 143.52 | 7.46 |
| Häuser nah | 332.20 | 329.98 | 3.60 |
| Baumkronen nah | 157.76 | 158.38 | 6.77 |
| Wiese nah | 132.58 | 130.14 | 8.18 |

Alle Ansichten liegen innerhalb von rund ±2 % des bisherigen Stands. Das ist eine Stichprobe auf dieser Maschine, keine Garantie identischer FPS in jeder Situation. Auf Nutzerwunsch bleibt die Überarbeitung bis zur ausdrücklichen Veröffentlichungsfreigabe lokal.

## Durchgehender Grasstreifen am Rigiweg

Die Wiesenmaske der fotografierten Baumreihe reicht jetzt bis an die vermessene Wegmittellinie. Dadurch entf?llt der verbliebene schmale Weizenstreifen zwischen Wiese und Kiesweg (51 m? Maskenfl?che). `RIGIWEG_VERGE` in `tools/build_planes.py` erh?lt die Korrektur bei einem Neuaufbau. Der Rastervergleich best?tigt: Nur Weizen wurde entfernt; Mais- und Strassenmasken sind unver?ndert. Die Spielansicht Richtung Core wurde nach dem Neuimport kontrolliert (`artifacts/planes/verge/core.png`). Der aktuelle Aufbau enth?lt 14'628 Blumen und 503 Pilzgruppen; die Pflanzenverteilung folgt der korrigierten Feldmaske. Auch diese Korrektur bleibt bis zur Freigabe lokal.


### Northern skyline correction (local, awaiting publication approval)

The isolated generic house north of Sennhof (OSM 36785520) is omitted from
Planes at the user's request. The actual Forest map and its hut are unchanged.
Building appearance indices are retained explicitly so removing this footprint
does not change the facades of the remaining 584 buildings. Source OSM text is
now read as UTF-8, correcting previously garbled road names on Windows.

The photo-directed northeast backdrop contains 204 deterministically scattered
16?24 m trees beyond the playable boundary, grounded on the existing DEM skirt.
These are visual estimates, not surveyed individual tree locations. Existing
Meshy distance meshes are instanced in 128 m cells, without collision, processing
or shadow passes. Their LOD bias avoids a second destructive simplification of
the already reduced meshes. All foreground tree, crop and nature counts remain
unchanged. Data comparison verifies the removed footprint and retained appearance
indices; the Vulkan northeast view is checked in `artifacts/planes/north/view.png`.
No release or push is authorised yet.

The close northern test view holds the configured 144 FPS. An uncapped same-scene
A/B probe (two 180-frame samples each) measured 1.75 ms with / 1.61 ms without
the backdrop; 19 additional visible draw calls and 33,286 reported primitives.
This is a small measurable render cost, not a claim of zero GPU overhead. Final
runtime log: `logs/planes-north-lod.log`, no script/render errors (only the known
Windows root certificate warning).


### Playable field boundary (local, awaiting publication approval)

`planes_boundary.gd` owns the field outline. Residential buildings remain scenery
outside it, with at least 10 m clearance from their footprint vertices. The
shooting target stand, junction and central fields remain inside. The shared
outline drives the visible pasture fence, cached golden minimap line, player
confinement, navigation source triangles and accepted enemy spawn positions.
The nearby map warning supports English and German.

The Planes player applies confinement after normal movement at any elevation,
removing only outward horizontal velocity so movement along the edge still works.
This covers sprinting, jumping, knockback and teleports; Forest's controller and
boundary remain unchanged. The fence is scenery, not a buildable barricade. Two
static MultiMeshes without shadow passes draw its posts and wire; there are no
per-post physics bodies or frame callbacks.

Validation: `--suite=planes_boundary --render-boundary` checks excluded homes,
clearance, retained destinations, the real player controller at three elevations,
continuous sprinting into the fence, outside cheat spawns and corner overshoots.
Screenshots are in `artifacts/planes/boundary/`. The existing survival suite checks
navigation and all 25 accelerated wave transitions against the reduced area.
No publish or push.
