# Charakterklassen und dauerhafter Fortschritt

Im Hauptmenü zeigt die rechte Karte die gewählte Klasse, ihr Level und den XP-Fortschritt. **Klasse wechseln**, **Klassen-Skills** und **Klassenfortschritt** öffnen die Klassenansicht. Links stehen alle fünf Klassen, in der Mitte das Klassensymbol und rechts die Talente beziehungsweise Statistiken. Gesperrte Talente bleiben sichtbar.

Jede Klasse besitzt eigene XP und Level 1–30. Auf Level 5, 10, 15, 20, 25 und 30 wird jeweils ein Talentpaar freigeschaltet. Ein Talent muss bewusst gewählt werden; pro Paar wirkt höchstens eines. Änderungen sind im Hauptmenü kostenlos. Während eines Matches bleibt der gewählte Build fest, auch bei einem Levelaufstieg. Sämtliche Waffen bleiben für jede Klasse verwendbar.

| Klasse | Spezialisierung im vorhandenen Waffenbestand |
| --- | --- |
| Revolverheld | Pistole, Revolver, Desert Eagle, Leuchtpistole |
| Sturmschütze | AK-47 und MG-60 |
| Brecher | Schrotflinte und Nightbreaker 12 |
| Marksman | Ranger .308, Lever Action, Plasma Rifle und Titanenbrecher |
| Assassin | Alle Waffen; Vorteile durch Tempo, Tarnung und Positionierung |

Alle 60 Talente haben Kampfeffekte. Dazu gehören echte Nachlade-, Magazin-, Streuungs-, Rückstoss-, Durchschlags- und Bewegungseffekte sowie bedingte Schadensboni. Waffenwechsel benötigen regulär 0,25 Sekunden; passende Talente verkürzen die Zeit. Händlertraining, Mods, Pilze und Talismane kombinieren sich mit Klassenboni. Magazinvergrösserungen erzeugen keine kostenlose Munition.

Die Tarnung des Assassin reduziert die unmittelbare Spielerpriorität gewöhnlicher Gegner und ihre Wahrnehmungsdistanz. Ein verborgener Spieler zieht die gewöhnlichen Zombies nicht weiter direkt an; sie bewegen sich weiter zur Hütte. Schüsse verraten den Spieler kurzzeitig, markierte Spieler bleiben sichtbar. Elitegegner und Bosse sind davon ausgenommen. Positionierungsboni sind bedingt und ersetzen keine dauerhafte Waffenspezialisierung.

## Profile

Die rechte Hauptmenükarte enthält eine Profilauswahl und ein Feld zum Erstellen weiterer lokaler Profile. Der Anzeigename ist vom Dateinamen getrennt: neue Profile erhalten eine stabile zufällige ID. Ein anderer Multiplayer-Anzeigename verändert das aktive Profil nicht.

Gespeichert wird im Ordner `profiles` neben der exportierten EXE, im Editor im Repository unter `profiles`. Kann der Ordner nicht erstellt werden, wird `user://profiles` verwendet. Die Profilauswahl liegt in `user://character.cfg`. Beim Übertragen auf einen anderen Rechner den Profilordner mitnehmen.

Ein Profil enthält XP und Talentwahl aller fünf Klassen, persönliche Kills, Kopfschüsse, Kopfschuss-Kills, Tode, Bosskills, beste Abschussserie, Wellen, Missionsabschlüsse, Spielzeit, Mehrspielerstatistiken, abgeschlossene Quests, einmalige Erfolge und kosmetische Freischaltungen. Die bevorzugte Klasse wird aus der Spielzeit bestimmt. Bereits gekaufte Lackierungen können in späteren Matches erneut kostenlos beim passenden Händler aufgetragen werden, sobald die Waffe vorhanden ist.

Das Spiel speichert bei Levelaufstiegen, Quests, Erfolgen, Talent- und Klassenänderungen, Wellen- und Matchende, Szenenwechseln und beim Beenden. Zusätzlich werden Änderungen spätestens alle 15 Sekunden gespeichert. Zuerst wird eine temporäre Datei geschrieben, dann die gültige vorherige Version als `.bak` gesichert und die neue Datei eingesetzt. Eine beschädigte Hauptdatei wird aus der Sicherung geladen; beschädigte oder neuere unbekannte Dateiformate werden nicht durch ein leeres Profil überschrieben. Speicherfehler werden auf der Profilkarte angezeigt.

Automatische Testläufe verwenden ein eigenes Profil im Arbeitsspeicher. Die Speichertests schreiben ausschliesslich nach `artifacts/class-profile-test`.

## XP und Erfolge

| Aktion | Klassen-XP |
| --- | ---: |
| Gewöhnlicher Zombie oder Läufer | 15 |
| Spezialgegner oder gepanzerter Zombie | 100 |
| Boss | 500 |
| Quest | mindestens 500, sonst das Doppelte der Rem-Dollar-Belohnung |
| Überstandene Welle | 200 + 20 × Wellennummer |
| Abgeschlossene Mission | 2000 |
| Secret Night | 1000 |
| Feldprüfung / versteckte Waldprüfung | mindestens 750, sonst das Doppelte der Rem-Dollar-Belohnung |
| Bisheriger Welterfolg, erstmals im Charakterprofil | mindestens 250, sonst das Doppelte seiner Rem-Dollar-Belohnung |

Die persönlichen Profilerfolge **First Blood**, **Exterminator**, **Perfect Aim**, **Veteran**, **Master of Arms** und **Untouchable** geben einmalig 250 / 5000 / 1000 / 2500 / 5000 / 2000 XP. Perfect Aim zählt Kopfschüsse auch dann, wenn das Ziel überlebt. Untouchable verlangt eine gesamte schwere oder Albtraum-Mission ohne erlittenen Schaden; ein später Matchbeitritt reicht dafür nicht.

Die benötigten XP steigen von 1000 für Level 1 → 2 bis 50.000 für Level 29 → 30. Die vorgegebenen Zwischenwerte 3000 / 7000 / 13.000 / 21.000 / 32.000 sind enthalten. Ab Level 30 werden Gesamt-XP weiterhin gezählt, ohne zusätzliche Talentstufen. Die Werte sind eine erste spielbare Abstimmung und zentral anpassbar.

## Mehrspieler

Im Multiplayer-Menü kann die Klasse gewählt, aber kein Talent geändert werden. **Klasse bestätigen** sperrt die Auswahl. Namen, Klassen, Klassenlevel, Bestätigung und Ladezustand werden für das gesamte Team angezeigt. Der Host kann erst starten, wenn alle Spieler fertig geladen und ihre Klasse bestätigt haben. Bei einem späteren Beitritt muss die Klasse ebenfalls bestätigt werden, bevor der Spieler aktiv wird.

Beim Beitritt werden die fünf vorbereiteten Builds übertragen. Der Host akzeptiert nur bekannte Klassen, Level 1–30 und freigeschaltete Talententscheidungen. Nach dem Sperren akzeptiert er keine Klassenwechsel oder neue Talententscheidungen. Treffer, passive Kampfeffekte und XP-Ereignisse werden vom Host berechnet. Persönliche Belohnungen werden zuverlässig an den betreffenden Client geschickt; Teamziele gehen an die bestätigten Teilnehmer. Wiederholte Quest-, Wellen- und Belohnungsereignisse werden abgefangen.

Profile sind lokale Spielstände, keine zentral zertifizierten Onlinekonten. Die Validierung begrenzt Klassen und Talente auf gültige Werte; sie ist kein Schutz vor absichtlich bearbeiteten lokalen Spielständen. Netzwerkprotokoll 4 verlangt auf allen Rechnern denselben neuen Build.

Für automatisierte Starts gibt es ausdrücklich `--class-auto-lock`. `--character-profile=<ID>` wählt ein vorhandenes lokales Profil anhand seines Dateinamens ohne `.json`. Reguläre Spieler bestätigen ihre Klasse im Menü.

`tools/start_local_coop.ps1` öffnet zwei Spielfenster mit getrennten Profilen `local_host` und `local_client`, damit lokale Koop-Tests keine gemeinsame Profildatei überschreiben.

## Code und Prüfungen

- `character_classes.gd`: Klassen, alle Talentbeschreibungen, XP-Kurve und Profilerfolge.
- `character_profile.gd`: Autoload für lokale Identitäten, Statistik und robuste Speicherung.
- `class_combat.gd`: Ein eingefrorener Build und eigene Effektzustände pro Spieler.
- `class_progression.gd`: Verbindung zu Kills, Quests, Erfolgen, Wellen und Koop-Belohnungen.
- `character_menu.gd`, `character_hud.gd`, `class_icon.gd`: Menüs, HUD und skalierbare Klassensymbole.

```powershell
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=class_system
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=class_integration --smoke-test --no-intro --no-music --no-foliage
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_class_coop.ps1
```

`class_system` prüft XP-Grenzen, Levelcap, Profile, beschädigte Dateien und Talentbedingungen. `class_integration` prüft das vollständige Spiel mit Menüs, realen Nachlade- und Magazinwerten, Kills, Belohnungen und Lobby-Sperren. Mit `--class-visual` in einem gerenderten Lauf entstehen Bilder unter `artifacts/classes`. `class_coop` startet zwei getrennte Prozesse und prüft persönliche Belohnungen, einmalige Erfolge, Host-Validierung und gemeinsame Missionsabschlüsse.
