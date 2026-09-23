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
