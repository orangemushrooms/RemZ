# Charakterklassen und dauerhafter Fortschritt

Im Hauptmenü zeigt das Überlebenden-Dossier die gewählte Klasse, ihr Level und den XP-Fortschritt. **Klasse wechseln** öffnet eine Galerie mit fünf Klassenkarten. **Klassen-Skills** und **Klassenfortschritt** zeigen die Klassenauswahl mit Dossier links und Talentkarten beziehungsweise Statistiken rechts. Eigene Klassensiegel, Barlow-Schriften, dezente Höhenlinien und Waldsilhouetten prägen die Oberfläche. Gesperrte Talente bleiben anklickbar: Ein Hinweis nennt das benötigte Klassenlevel und die exakt fehlenden XP. Die Talentwahl selbst verbraucht keine XP.

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

## Assassin: Teleport ab Level 15

Unter **Klassen-Skills** wählst du zusätzlich genau eine Teleport-Variante für die nächste Runde. Die sechs passiven Talentpaare bleiben erhalten. Bestehende Profile behalten sämtliche XP und Talente; der neue Teleport muss bewusst gewählt werden.

| Variante | Bedienung | Reichweite | Abklingzeit |
| --- | --- | --- | --- |
| Vorwärts | J | Bis zu 8 Meter in Blickrichtung, stoppt vor Wänden | 12 Sekunden |
| Karte | J, dann Linksklick auf einen freien Kartenpunkt | 40 Meter | 30 Sekunden |

Esc, Rechtsklick, J oder Abbrechen schliessen die Zielkarte ohne Abklingzeit. Während der Zielwahl läuft die Runde weiter. Blockierte, besetzte, zu steile oder unerreichbare Landepunkte sind ausgeschlossen; Feldprüfungsgrenzen gelten weiter. Während des Intros, am Boden, als Zuschauer, im Geschützturm oder beim Drohnenflug ist Teleport gesperrt. Die HUD-Anzeige nennt die gewählte Variante und die restliche Abklingzeit. Im Koop prüft der Host jeden Teleport. Alle Mitspieler benötigen den gleichen Build.

## Profile

Die Profil-Schaltfläche unten im Dossier öffnet die Auswahl und das Erstellen weiterer lokaler Profile. Der Anzeigename ist vom Dateinamen getrennt: neue Profile erhalten eine stabile zufällige ID. Ein anderer Multiplayer-Anzeigename verändert das aktive Profil nicht.

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

Die benötigten XP steigen von 1100 für Level 1 → 2 bis 55.000 für Level 29 → 30. Gegenüber der ersten Fassung sind sämtliche Levelkosten um lediglich 10 % erhöht; alle XP-Belohnungen bleiben gleich. Bestehende Profile werden beim Laden einmalig auf Format 2 umgestellt: Ihre XP werden im selben Verhältnis angepasst, sodass Level, freigeschaltete Talente und anteiliger Level-Fortschritt erhalten bleiben (Rundung unter 1 XP). Die vorherige Datei bleibt als Sicherung erhalten. Ab Level 30 werden Gesamt-XP weiterhin gezählt, ohne zusätzliche Talentstufen.

Profilformat 3 ergänzt die Teleport-Auswahl. Profile im Format 2 behalten ihre XP und passiven Talente unverändert; die neue aktive Fähigkeit ist zunächst nicht gewählt.

## Mehrspieler

Im Multiplayer-Menü kann die Klasse gewählt, aber kein Talent geändert werden. **Klasse bestätigen** sperrt die Auswahl. Namen, Klassen, Klassenlevel, Bestätigung und Ladezustand werden für das gesamte Team angezeigt. Der Host kann erst starten, wenn alle Spieler fertig geladen und ihre Klasse bestätigt haben. Bei einem späteren Beitritt muss die Klasse ebenfalls bestätigt werden, bevor der Spieler aktiv wird.

Beim Beitritt werden die fünf vorbereiteten Builds übertragen. Der Host akzeptiert nur bekannte Klassen, Level 1–30 und freigeschaltete Talententscheidungen. Nach dem Sperren akzeptiert er keine Klassenwechsel oder neue Talententscheidungen. Treffer, passive Kampfeffekte und XP-Ereignisse werden vom Host berechnet. Persönliche Belohnungen werden zuverlässig an den betreffenden Client geschickt; Teamziele gehen an die bestätigten Teilnehmer. Wiederholte Quest-, Wellen- und Belohnungsereignisse werden abgefangen.

Profile sind lokale Spielstände, keine zentral zertifizierten Onlinekonten. Die Validierung begrenzt Klassen und Talente auf gültige Werte; sie ist kein Schutz vor absichtlich bearbeiteten lokalen Spielständen. Netzwerkprotokoll 5 verlangt auf allen Rechnern denselben neuen Build.

Für automatisierte Starts gibt es ausdrücklich `--class-auto-lock`. `--character-profile=<ID>` wählt ein vorhandenes lokales Profil anhand seines Dateinamens ohne `.json`. Reguläre Spieler bestätigen ihre Klasse im Menü.

`tools/start_local_coop.ps1` öffnet zwei Spielfenster mit getrennten Profilen `local_host` und `local_client`, damit lokale Koop-Tests keine gemeinsame Profildatei überschreiben.

## Code und Prüfungen

- `character_classes.gd`: Klassen, alle Talentbeschreibungen, XP-Kurve und Profilerfolge.
- `character_profile.gd`: Autoload für lokale Identitäten, Statistik und robuste Speicherung.
- `class_combat.gd`: Ein eingefrorener Build und eigene Effektzustände pro Spieler.
- `class_progression.gd`: Verbindung zu Kills, Quests, Erfolgen, Wellen und Koop-Belohnungen.
- `character_menu.gd`, `character_style.gd`, `character_surface.gd`, `character_hud.gd`, `class_icon.gd`: Dossier, Typografie, prozedurale Hintergründe, HUD und skalierbare Klassensiegel.

```powershell
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=class_system
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=class_integration --smoke-test --no-intro --no-music --no-foliage
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_class_coop.ps1
```

`class_system` prüft XP-Grenzen, Levelcap, Profile, beschädigte Dateien, die einmalige Migration alter Spielstände und Talentbedingungen. `class_integration` prüft das vollständige Spiel mit echten Mausklicks auf Talentkarten, Hinweisen, realen Nachlade- und Magazinwerten, Kills, Belohnungen und Lobby-Sperren. Mit `--class-visual` entstehen gerenderte Bilder auf Deutsch und Englisch unter `artifacts/classes`; der Lauf prüft auch die Bedienung bei 1280 × 720. `class_coop` startet zwei getrennte Prozesse und prüft persönliche Belohnungen, einmalige Erfolge, Host-Validierung und gemeinsame Missionsabschlüsse. Die Sprachprüfung erfasst Galerie, Talentanforderungen, Profile und Fortschrittsansicht.
