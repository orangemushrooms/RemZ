# Drohnenkontrollzentrum

Die neue Konsole steht im Obergeschoss der Waldhütte, mit drei Radarbildschirmen, Tastatur und Steuerknüppeln. Die vorhandene Hütte samt Türen, Reparatur und Vorräten bleibt erhalten.

An der Station **E** drücken, eine Drohne auswählen und **Ready to fly** anklicken. Voraussetzung sind der Hüttenschlüssel und die jeweilige bereits gestartete Welle:

| Drohne | Ab Welle | Hülle | Schaden pro Schuss | Schüsse/s | Tempo | Reichweite |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kestrel-Aufklärer | 5 | 100 | 24 | 5,6 | 9 m/s | 65 m |
| Viper-Kampfdrohne | 10 | 180 | 42 | 8,3 | 11 m/s | 85 m |
| Tempest-Sturmdrohne | 15 | 280 | 62 | 11,8 | 12 m/s | 110 m |

**WASD** fliegt horizontal relativ zur Blickrichtung, **Maus** richtet Blick und Waffe aus, **Leertaste/Strg** steigt/sinkt. **Linksklick** feuert. **R/Escape** ruft die Drohne zurück und gibt die normale Kamera zurück. **M** öffnet die Karte; Drohnen sind türkis markiert. Die Flughöhe ist auf 45 m über dem Gelände begrenzt, der Kartenrand bleibt geschlossen.

Der Körper bleibt an der Station und kann angegriffen werden. Persönliche Waffen, Granaten und Bewegung sind während des Flugs gesperrt. Drohnen besitzen eigene Waffen ohne Verbrauch der Spielermunition; Dauerfeuer überhitzt sie. Mündungsfeuer, Licht, Rauch, Hülsen, Leuchtspur und räumliches Schussgeräusch begleiten Schüsse. Rotorgeräusche und Bewegung zeigen den Flug; beschädigte Drohnen rauchen.

An Hindernissen verursacht ein genügend schneller Aufprall 2–8 Hüllenschaden mit 0,65 s Schutz gegen Mehrfachkontakte desselben Stosses. Echte Zombie-Nahkampftreffer verursachen mindestens 30 Schaden beziehungsweise das 2,5-Fache ihres normalen Schadens. Titanenschläge treffen Drohnen in ihrem Wirkungsbereich, soweit keine Deckung schützt. Waffen treffen echte Gegnerhitboxen; Deckung blockiert auch zwischen Drohnenkörper und Mündung.

Die Dächer von Waldhütte und Holzlager sind für Drohnen fest: Eine eigene Kollisionsebene (Layer 128) füllt den Raum unter jeder Dachfläche, sonst sank eine Drohne durch das Dach ins Obergeschoss. Kugeln, Granaten, Türme und das Wegnetz bemerken davon nichts. Drohnen liegen selbst auf Layer 64, damit Kugeln der Mitspieler und die Sichtlinien der Türme durch befreundete Drohnen hindurchgehen. Der Blick folgt der Maus in jedem Bild, Modell und Kamera werden zwischen den Physikschritten interpoliert; die Steuerbefehle gehen weiterhin 20-mal pro Sekunde an den Host. Die Feuerraten der Tabelle werden genau eingehalten. Die Fluganzeige steht unten in der Mitte, damit Boss-Leiste und Hüttenalarm frei bleiben. Ein Menü über dem Flug (Inventar, Cheat-Menü) behält seine Tasten und Klicks. Die drei Modelle werden beim Laden vorgewärmt, der erste Start ruckelt nicht mehr.

Jedes Modell kann einmal gleichzeitig im Team fliegen, ein Spieler steuert höchstens eine Drohne. Start und Wiederaufbereitung kosten keine Rem Dollars. Nach Rückruf dauert die Wiederaufbereitung 10 s, nach Zerstörung 30 s; die Meldung dazu erreicht auch Koop-Clients. Bei Tod oder Verbindungsabbruch des Piloten wird seine Drohne freigegeben, ohne Meldung über dem Todes- oder Game-Over-Bildschirm. Andere Piloten bleiben unbeeinträchtigt. In Koop pausieren Menüs die Welt nicht.

## Quests beim Mechanic

Die Questreihe **Drohneneinsätze** beginnt mit dem Start von Welle 5, ohne Voraussetzung einer anderen Questreihe. Jede weitere Stufe setzt die Abgabe der vorherigen voraus:

| Quest | Ab Welle | Teamziel mit dem jeweiligen Modell | Belohnung |
| --- | ---: | --- | ---: |
| Erster Flug | 5 | Kestrel: 150 m fliegen, 5 Zombies besiegen | 150 R |
| Bewaffnete Patrouille | 10 | Viper: 400 m fliegen, 15 Zombies besiegen | 250 R |
| Schwere Luftunterstützung | 15 | Tempest: 600 m fliegen, 30 Zombies besiegen | 400 R |

Frühere Flüge derselben Runde zählen mit. Flugstrecke misst tatsächliche Bewegung; Schweben, Startposition und Netzwerkinterpolation zählen nicht. Annahme und einmalige Belohnung erfolgen pro Spieler beim Mechanic. Teamfortschritt erscheint im Questjournal, bei Benachrichtigungen und auch nach spätem Koop-Beitritt. Der Hüttenschlüssel bleibt zum Fliegen erforderlich.

## Flugsound

Der räumliche Flugsound stammt aus `godot/assets/audio/sfx/drone_flying.mp3`. `tools/prepare_drone_audio.py` erstellt daraus die Spielkopie: 1,18 s stiller Vorlauf entfernt, Startgeräusch einmalig, danach Flugschleife ab 2,32 s mit 150 ms Überblendung am Schleifenende. Das Original bleibt erhalten. Die Drehzahl verändert den Flugklang sanft erst nach dem Anlaufen. Pause hält die Wiedergabe an; Rückruf und Zerstörung entfernen den Sound mit der Drohne. Koop überträgt das Soundalter, sodass ein späterer Beitritt kein erneutes Startgeräusch auslöst.

## Meshy-Modelle

Alle drei Flugkörper wurden eigens mit Meshy 7.1 erzeugt: je 30.000 Zielpolygone und PBR-Texturierung mit 4K-Ausgabe. Die Spielkopien behalten 2K-PBR-Texturen. Originale, Prompts, Vorschaubilder und Task-Belege liegen unter `meshy_output/`; die Reproduktionsskripte sind `tools/meshy_drones.py` und `tools/prepare_drones.mjs`. Drei Preview-Aufträge zu 25 Credits und drei Texturierungen zu 10 Credits ergeben **105 Credits**. Rotorbewegung, lenkbare Waffenaufbauten und Effekte entstehen im Spiel.

## Tests

- `drones`: Zugang, Stockwerk, Sichtlinie, Wellen 4/5, 9/10 und 14/15, Startplatzblockaden, Menü, Kamera, Pilotensperren, Flugtempo, Kartengrenzen, Kollisionen, Abkühlung, ungültige Befehle, Schüsse, Deckung, Effekte, echte Zombieangriffe, Tod, Rückruf und Replica-Zustand, dazu Blick pro Bild, Durchschuss befreundeter Drohnen, Menüs über dem Flug, Landung auf dem Hüttendach und die Feuerrate der Tempest (82 Prüfungen).
- `drone_coop`: drei echte Godot-Prozesse über ENet, mit Fernsteuerung, autoritativen Treffern, späterem Beitritt, Tod des Hosts bei weiterfliegendem Client, Zerstörung und Disconnect. Ausführen mit `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_drone_coop.ps1`.
- `drone_visuals`: gerenderte Stations-, Menü-, Detail- und Flugansichten unter `logs/drone-*.png`.
- Regressionen: `roof_defences`, `towers`, `hut_health`, `hut_restock`, `defence`, `aiming` sowie der vollständige Vier-Spieler-Test `multiplayer`.

Beispiel für die funktionalen Prüfungen:

```powershell
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=drones --smoke-test --no-intro --no-music --no-foliage
```
