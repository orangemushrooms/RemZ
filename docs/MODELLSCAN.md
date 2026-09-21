# Modellscan und realistische Spielobjekte

Stand: 21. September 2026. Geprüft wurden die aktiven Godot-Skripte, Szenen, Modellkataloge und sichtbaren primitiven Ersatzobjekte. Der alte Browser-Prototyp in `src/` ist nicht das aktuelle Spiel.

## Ergänzte Modelle

| Objekt | Einbindung |
| --- | --- |
| Eule | Eigenes texturiertes Modell mit Schulter- und Flügelspitzengelenken; bestehende Nachtflüge und Flügelschlagkurven |
| Standardturm | Doppelläufige Waffenbaugruppe, auf bestehende Mündung und Drehachse ausgerichtet |
| Sandsack | Sechs modellierte Stoffbeutel je Turm |
| Waldschlüssel | Messingschlüssel mit Anhänger im entfernbaren Sammelobjekt |
| Geldbündel | Sichtbares Modell für abgeworfene Punkte |
| Hüttentürblatt | Texturierte Holz-/Eisentüren an den bestehenden beweglichen Scharnieren; gleiche Kollisionsmasse |
| Teichtrog | Tatsächlich hohles Holzmodell mit eigener Wasserschicht |
| Acht Pilzsorten | Pfifferling, Morchel, Maronenröhrling, Parasol, Reizker, Tintenpilz, Violetter Rötelritterling, Krause Glucke; auch neue Inventarbilder |

Die neuen GLBs behalten 2K-PBR-Texturen inklusive Normalmaps. Originaldateien und Meshy-Belege liegen in `meshy_output/`; die importierten Spielmodelle in `godot/assets/models/`. `missing.SOURCES.md` in diesem Ordner dokumentiert die einzelnen Aufträge und Kosten.

Bei den organischen Pilzformen und Stoffbeuteln wurden harte Facetten der generierten Vertexnormalen geglättet. UVs, Normalmaps und Silhouetten bleiben erhalten; Godot erzeugt die passenden Tangenten und Mesh-LODs beim Import. Die Wasserfläche im neuen Trog liegt innerhalb der Ränder und verwendet den vorhandenen animierten Wassershader.

## Bereits vorhandene Modelle jetzt zusätzlich verwendet

- Granaten-Drops verwenden das vorhandene Granatenmodell.
- Maislabyrinth-Verstecke verwenden die vorhandene Munitionskiste.
- Schlüsselunterlagen und Trogstützen verwenden das vorhandene Baumstumpfmodell.
- Die Teichufer-Steine verwenden das vorhandene Felsenmodell.
- Holzstapel im Holzlager verwenden das vorhandene Holzstapelmodell, passend in die bisherigen Ablageflächen eingepasst.
- Die Waffenmodellnamen von Messer und Axt verweisen direkt auf die vorhandenen realistischen GLBs.

## Bewusst konstruierte Geometrie

Nicht jede `BoxMesh`-/`CylinderMesh`-Stelle ist ein fehlendes Modell. Gelände, Strassen, reale Gebäudegrundrisse, Dachflächen, Fenster, Schilder mit lesbarer Schrift, Zäune, Palisaden, Turmplattformen, Leitern und Ausbauplatten bleiben massgenau konstruiert. Ebenso bleiben Wasser, Schuss-/Explosionseffekte und unsichtbare Kollisionskörper prozedural. Vegetation verwendet bestehende windanimierte Meshes, Fotos und räumliche Instanzierung. Bereits vorhandene Figuren, Waffen und Ausrüstung werden weiterverwendet. Rein symbolische Menüwerte und Waffenboni benötigen kein zusätzliches Weltobjekt.

`tools/audit_models.py` schreibt den wiederholbaren Dateiscan nach `artifacts/model-audit/scan.json`, einschliesslich verbleibender primitiver Stellen zur weiteren Sichtprüfung. Der Scan prüft wörtliche Ressourcenpfade und Modellkataloge; dynamisch zusammengesetzte Pfade werden zusätzlich durch die Godot-Prüfungen und Sichtkontrolle abgedeckt.

## Reproduktion

1. `python tools/meshy_missing.py` setzt vorhandene Aufträge fort; benötigt den lokal konfigurierten Meshy-Zugang.
2. `node tools/prepare_missing.mjs` normalisiert die heruntergeladenen Modelle und erstellt das Eulenrig.
3. Godot-Import: `Godot.exe --headless --path godot --editor --quit`.
4. `--suite=missing_models` über `res://tests/run.gd` prüft Modellimport, Texturen, Masse, Scharniere, Sammelobjekte und Flügelanimation.
5. `--suite=missing_visuals` rendert die Modelle nach `artifacts/model-audit/`; `--suite=render_item_icons --missing-only` erstellt die Inventarbilder.

## Ergebnis der Prüfung

- Dateiscan: 97 GLBs im Modellordner; keine fehlenden wörtlichen Modellressourcen oder Modellkatalog-Einträge. Alle 15 Einträge des neuen Generierungskatalogs vorhanden.
- `missing_models`: 70 Prüfungen, 0 Fehler.
- `towers`: 107 Prüfungen, 0 Fehler.
- `doors_keys`: 112 Prüfungen, 0 Fehler.
- `cornfield`: 28 Prüfungen, 0 Fehler.
- Gerenderte Modellübersicht: `artifacts/model-audit/gallery.png`. Spielansichten liegen daneben unter `world-*.png`; Tür-/Schlüsselansichten unter `artifacts/doors-keys/`.
- Der Türtest verwendet gezielt verfügbare Schlüssel, prüft die tatsächlichen Schlüsselbeschriftungen statt einer überholten festen Inventargrösse und isoliert Tür-gegen-Spieler-Angriffe von der separaten Hüttenbelagerung.
- Bekannte Meldungen der eingeschränkten Testumgebung zu Zertifikatsspeicher und Editor-Einstellungen bleiben bestehen; die genannten Prüfungen enthalten keine Skriptfehler.

Meshy-Kosten: **525 Credits**, verbleibendes Guthaben nach dem Lauf: **2'423 Credits**. Ein interner Meshy-Fehler bei der Krausen Glucke wurde mit bestätigten 0 Kosten erneut versucht; der zweite Auftrag war erfolgreich.
