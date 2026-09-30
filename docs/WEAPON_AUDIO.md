# Waffenaufnahmen vom 23. September 2026

Die acht Schussgeraeusche verwenden die neu gelieferten MP3s aus
`godot/assets/audio/sfx/`. Die Originaldateien bleiben unveraendert.

| Waffe | Aufnahme |
| --- | --- |
| Desert Eagle .50 | `Desert Eagle.mp3` |
| Leuchtpistole | `Flaregun.mp3` |
| MAC-10 SD | `Mac10.mp3` |
| Kryo-MP C7 | `Kryo_MP.mp3` |
| Plasmabuechse | `Plasma_Gunshot.mp3` |
| Unterhebler .45-70 | `Unterhebler_shot.mp3` |
| Minigun M134 | `Minigun_Shots_long.mp3` |
| Graviton-Kanone | `Graviton_Gunshot.mp3` |

`python tools/build_weapon_audio.py --recordings-only` erzeugt die verwendeten
44,1-kHz-Mono-WAVs unter `sfx/weapons/`: Stille vor dem Schuss entfernen, natuerlichen
Ausklang erhalten, PCM-Spitzen auf 0,82 normalisieren. Keine neuen Synthesizer- oder
EQ-Schichten auf den gelieferten Schuessen. Herkunft, SHA-256 der Originaldateien,
Schnittbeginn und Laufzeit stehen in `sfx/weapons/sources.json`.
Auch ein vollstaendiger Aufruf des Builders verwendet diese Aufnahmen.

Die Minigun-Aufnahme wird am Schleifenuebergang 60 ms ueberblendet. Jeder Schuetze
hat eine eigene Stimme; Folgeschuesse verlaengern deren Wiedergabe, statt die
achtsekundige Datei erneut zu starten. Loslassen und Nachladen blenden binnen
40 ms aus, Wechsel und inaktive/tote Schuetzen stoppen sofort. Bei entfernten
Schuetzen endet die Wiedergabe automatisch, wenn keine weiteren Schussereignisse
eintreffen. Der 210-ms-Puffer deckt langsame Anlaufschuesse und Netzwerkschwankungen
ab. Die vorhandenen Motor-/Mechanikgeraeusche bleiben separate Effekte.

Der bisherige Graviton-Einschlag heisst jetzt `graviton_impact`. Der neue Schuss
wird ausschliesslich an der Muendung abgespielt, nicht erneut beim Einschlag.

Pruefungen: `weapon_recordings` (36), `new_weapons` (254), `weapon_specials` (60),
alle bestanden. Zusaetzlich wurden Quellpruefsummen, PCM-Pegel und die ersten
hoerbaren Samples geprueft: Schussbeginn innerhalb von 2 ms nach Clipstart.
Windows-Version mit den aktualisierten Sounds: `builds/earthworms/RemZ.exe`.

Der erste Sentinel-Turm (Waechter, `standard`) verwendet ebenfalls die neue
`Sentinel_Tower.mp3`. `python tools/prepare_tower_audio.py` erzeugt daraus
`sfx/towers/sentinel_shot.wav`: 61 ms Vorlauf entfernen, leisen Ausklang ausblenden,
Pegel an die anderen Turmaufnahmen angleichen. Ein Positionslautsprecher an der
Muendung mit maximal drei Stimmen spielt den Schuss bei automatischem Feuer,
manueller Bedienung und neuen Koop-Schussereignissen. Der bisherige SMG-Sound
entfaellt. Die bestehenden Suiten `towers` (144 Pruefungen) und `tower_effects`
(73 Pruefungen) bestehen einschliesslich stummer historischer und wiederholter
Netzwerk-Snapshots.

## Klassenwaffen vom 30. September 2026

Acht weitere eigene Aufnahmen liegen als Rohdateien unter `input/audio/weapons/` (nicht im Godot-Projekt,
damit sie weder importiert noch exportiert werden). `python tools/build_class_weapon_audio.py` bakt daraus
`sfx/weapons/{mp5,tommy_gun,ar15,sig_p226,nighthawk,titanbreaker,spas12,sawed_off}.wav` und ergänzt
`sources.json` (Quelle, SHA-256, Schnitt, empfohlener `sfx_db`):

| Waffe | Aufnahme | Verarbeitung |
| --- | --- | --- |
| MP5 (ersetzt `smg.mp3`) | `MP5.mp3`, Salve von 6 Schuss bei 888 rpm | zweiter Schuss vom Tal davor bis zum Tal danach geschnitten (85 ms), Ausklang der Salve angehängt, kurzer synthetischer Raumhall |
| Tommy Gun | `Tommy_Gun.mp3`, Salve von 7 Schuss | gleich, 69 ms |
| AR-15 | `AR_15.mp3` | Einzelschuss, Vorlauf ab, Ausklang bis 54 dB unter Spitze, höchstens 1,4 s |
| SIG P226 | `SIG P226.mp3` | Einzelschuss (57 ms Raumrauschen davor entfernt) |
| Nighthawk .45 | `Nighthawk.mp3` | Einzelschuss (144 ms Stille davor entfernt) |
| Titanbreaker .50 (ersetzt den tiefgestimmten Revolver) | `Titan_Breaker.mp3` | Einzelschuss |
| SPAS-12 | `Spas 12.mp3`, leise Fernaufnahme ohne Anschlag | synthetischer Mündungsknall und Subbass-Schlag davor, Aufnahme als Körper und Ausklang |
| Abgesägte Flinte | `Sawed_Off_Shotgun.mp3`, ebenso | gleich |

Der Pegel jeder neuen Datei wird an die alte Aufnahme derselben Waffenfamilie angeglichen (lauteste 120 ms,
plus deren `sfx_db`), das Skript druckt den empfohlenen `sfx_db` für `Weapons.DEFS`. Vollautomatisch feuern
alle neuen Waffen ausser Pistolen und Flinten; der Einzelschuss stapelt sich im Dauerfeuer wieder zur Salve
(höchstens drei Stimmen je Sound). `--suite=class_weapons` prüft, dass jede Waffe ihre WAV lädt und beim Schuss
abspielt.
