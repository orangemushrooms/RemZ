# Feedback-Sounds

Die Dateien in `godot/assets/audio/sfx` werden in `Sfx.FILES` logischen Ereignissen zugeordnet. Originaldateinamen bleiben erhalten.

| Ereignis | Datei |
| --- | --- |
| Gegenstand, Munition, Vorrat oder Lieferung aufgenommen | `key_Pickup.mp3` |
| Schlüssel aufgenommen | `key_Pickup.mp3` |
| Neue Waffe beim Händler erhalten | `gun_pick_up.mp3` |
| Auftrag angenommen | `acceppt_1.mp3` / `acceppt_2.mp3` |
| Auftrag abgeschlossen und Belohnung abgeholt | `quest_aaccept_Finish.mp3` |
| Training, Lackierung oder Turmausbau bestätigt | `acceppt_1.mp3` / `acceppt_2.mp3` |

Die beiden Bestätigungen wechseln ohne direkte Wiederholung. Feedback spielt in Originaltonhöhe, mit je Ereignis abgesenkter Lautstärke und auch im pausierten Solo-Handelsmenü. Fehlgeschlagene Transaktionen und doppelte Quest-Abgaben lösen keinen Erfolgssound aus. Weltkisten liefern weiterhin Munition; sie lösen deshalb keinen Waffenerhalt-Sound aus.

Im Koop bestätigt der Host die Aktion und sendet das Soundereignis ausschließlich an den betroffenen Spieler. Replizierte Weltzustände lösen die Sounds nicht erneut aus.

Prüfungen: `--script res://tests/run.gd -- --suite=audio_events` und `--script res://tests/run.gd -- --suite=progression --smoke-test --no-intro --no-music`.
