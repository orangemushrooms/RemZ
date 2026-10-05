# Historischer Prüfbericht: Expeditionen

Stand: **5. Oktober 2026**, Windows, **Godot 4.7.2 stable**
(`ed1daf0bf`). Dieser Bericht dokumentiert die damalige Expedition-Veröffentlichung
mit Buildkennung `remz-dev-20261005-expeditions` und Menüversion
**Co-op 2026.10.05-E**. Seine Ergebnisse sind historische Nachweise und keine
Freigabe späterer Änderungen.

Die nachfolgende Überarbeitung von Einstieg, Tastaturbelegung, Feldbuch, HUD und
weiteren Spielfehlern wird separat im
[aktuellen Bericht zur Bedienungsüberarbeitung](PLAYER_EXPERIENCE_VALIDATION.md)
geprüft. Die [Funktionsliste und Regeln](EXPEDITIONS.md) beschreiben den aktuellen
Quellstand und können deshalb von der hier geprüften Veröffentlichung abweichen.

## Ergebnisse

| Prüfung | Umfang | Ergebnis |
| --- | --- | --- |
| Kompilierung | 376 Spiel- und Testskripte | 0 defekte Skripte |
| Bestehende Regressionen | 34 Suiten, 2998 Assertions | 34/34 bestanden |
| Erweiterte Expeditionssuite, Englisch, gerendert | 460 Assertions, beide Maps | 0 Fehler |
| Erweiterte Expeditionssuite, Deutsch, gerendert | 459 Assertions, beide Maps | 0 Fehler |
| Forest, zwei verbundene ENet-Prozesse | Host 24 / Client 10 Assertions | 0 Fehler |
| Planes, zwei verbundene ENet-Prozesse | Host 28 / Client 13 Assertions | 0 Fehler |
| Netzwerk-Kompatibilität, drei ENet-Prozesspaare | 36 Assertions | 0 Fehler |
| Offline-Prüfung der Online-Lobby | 44 Assertions, Kennung und Paketgrössen | 0 Fehler |
| Spielstand nach Prozessneustart | Forest 1+7 / Planes 1+5 Assertions | 0 Fehler |
| Deutscher Katalog | 2498 Einträge und Platzhalter | 0 Probleme |
| Windows-Release-Export | EXE, PCK, EOS- und Audio-Bibliotheken | Export bestanden |
| Nativer Release-Start | Forest und Planes bis zur spielbereiten Map | Beide bestanden |
| Funktionen aus der tatsächlichen Release-PCK | Forest 9 / Planes 9 Assertions | 0 Fehler |

Die englische Expeditionssuite enthält zusätzlich die nachträglich ergänzte Prüfung
von `StringName`-Schlüsseln in Spielständen. Die übrigen Prüfungen stimmen mit dem
deutschen Lauf überein. Die Zahlen zählen Assertions je Testlauf; gemeinsame Regeln
werden unter verschiedenen Maps und Sprachen erneut geprüft.

Logs, Screenshots und maschinenlesbare Ergebnisse liegen unter
`artifacts/expansion-tests/`. `regressions.json` enthält den letzten ausgewerteten
Lauf jeder Bestandssuite; gezielte Wiederholungen ersetzen deren vorheriges Ergebnis.
`restarts.json` dokumentiert die getrennten Schreib- und Leseprozesse.
`network-compatibility.json` enthält die drei echten Handshake-Prüfungen:
Protokoll 7 wird trotz aktuellem Fingerprint abgewiesen; ein falscher Fingerprint
wird bei aktuellem Protokoll abgewiesen; passende Clients erhalten Begrüssung,
Initialzustand und Bereitschaftsbestätigung. EOS-Lobbykennung und Handshake verwenden
Protokoll 8 sowie `remz-dev-20261005-expeditions`. Nach dieser Versionskorrektur wurden
beide vollständigen Koop-Suiten, Export und Paketprüfungen erneut ausgeführt.

## Geprüfte Abläufe

- Code-Rundreise für beide Maps, sämtliche Herausforderungen und Schwierigkeiten,
  Randwerte der Startwerte sowie manipulierte und beschädigte Codes.
- Wiederholbare Wellenplanung, Wetterabläufe, Angriffsprofile und unterschiedliche
  Augmentangebote; doppelte Auswahlanfragen und Belohnungsereignisse.
- Klassenaktionen mit echten Gegnern: Schaden der Schockwelle, Sichtprüfung der
  Markierung, verstärkter Schaden im Schadenspfad, Verlangsamung durch Treffer,
  Ablauf von Buffs und Abklingzeiten.
- Froststatus, tatsächliche Turmfeuerrate und Wärme, Waffenwechselbonus, gesperrtes
  Gewehr im Pistolenmodus, vier echte Türme im Turmlimit-Modus und fehlende Welle 11
  im kurzen Angriff.
- Drohnenbergung, Funkverteidigung und Eskorte durch ihre vollständigen Zustände;
  vollständige Verstärkungsbudgets und Schutz vor wiederholter Auszahlung.
- Aussenposten inklusive Gegnern, gesamter Haltezeit, einmaliger Versorgung und
  Rückgabe einer Lieferkiste am richtigen Ziel.
- Signalreihenfolge und einmalige Beute; geeignete Fernkampf-Elitekills,
  Ablehnung von zu nahen Kills und falschen Waffen, einmalige Auftragsbelohnung.
- Windrichtung, aktives Feuer, Löschen, verbrannte Pflanzen und begrenzter Rauchpool.
- Tatsächliche Gegnerverfolgung auf freiem Gelände, begrenzte Beschleunigung und
  Rücknahme des Bonus bei geringer Entfernung; reguläre Helme bei Welle 10.
- Schiessstandreihenfolge, abgelehnte falsche Ziele, getrennte Wettbewerbsergebnisse
  und zuverlässige persönliche Rekorde auf Host und Client.
- Physische Tore, freie Öffnung nach Benutzung, verweigertes Schliessen durch einen
  Spieler, Schiessscharten, Reparatur und Wiederaufbau aus einem Netzwerksnapshot.
- Begehbare Plattform: ein echter `Player` läuft mit `move_and_slide` vom Gelände
  über die Rampe auf das Deck, ohne zu springen.
- Beide Schlussverteidigungen mit allen vorgesehenen Verstärkungen und gesamter
  Haltezeit; Aufenthalt ausserhalb des Ziels, Niederlage bei zerstörtem Ziel,
  Sonnenaufgang, Rundenbilanz und Kampagnenfortschritt.
- Tatsächlicher Übergang von der letzten Welle ins Finale: vorzeitiger Kampagnensieg
  ist auf Host und Client ausgeschlossen. Auch zehn Wellen können nach einem
  erfolgreichen Finale ihre Map sichern.
- Koop: echte ENet-Verbindung zweier Prozesse, persönliche Augmente, doppelte
  Clientanfragen, Heilung, Munitions-, Verbands- und Drinkübertragung ohne
  Duplizierung, Reichweitengrenze, Hostrechte, Spielstände und Client-Torkollision.
- Koop-Finale durch sämtliche Zustände bis zum Sieg und Abschluss beider Prozesse;
  vier getrennte Inventarslots und deren Snapshot mit zwei zusätzlichen Testakteuren.
- Spielstände mit Geld, Gesundheit, Klassen, Inventar, Augmenten, Wellen, Aufträgen,
  Beute, Requisiten und Waffenwärme. Laden nach einem vollständigen Neustart sowie
  erneuter Beitritt mit geänderter Netzwerk-ID und gleichem Spielernamen.
- Beschädigte Dateien und falsche Datenformen vor jeder Mutation; Wiederherstellung
  einer zerbrochenen Scheibe, eines zerstörten Kürbisses und verschobener Beute.
- Solo-Pause und Koop-Steuerung beim Feldbuch, sichtbare deutsche/englische
  Oberfläche, alle fünf Feldbuchseiten auf einer 720p-Zeichenfläche und Ergebnisbilder.
- Unabhängige Leistungswertung trotz Geldausgaben, Profilmigration, kosmetische
  Meisterschaft ohne weitere Kampfstärke und nicht sinkende persönliche Rekorde.

## Bestandssuiten

| Suite | Assertions |
| --- | ---: |
| smoke | 94 |
| class_system | 560 |
| class_integration | 33 |
| class_balance | 13 |
| class_weapons | 327 |
| weapon_mods | 52 |
| new_weapons | 254 |
| network_packets | 14 |
| coop_snapshot_cost | 6 |
| menu_flow | 11 |
| language | 104 |
| team_purse | 29 |
| boss_music | 37 |
| secret_night | 70 |
| field_update | 82 |
| planes | 31 |
| planes_survival | 43 |
| range_steps | 23 |
| planes_atmosphere | 19 |
| planes_parity | 57 |
| towers | 363 |
| tower_batch | 166 |
| tower_planner | 27 |
| roof_defences | 115 |
| forest_finds | 56 |
| doors_keys | 112 |
| brewing | 41 |
| downed | 24 |
| assassin_teleport | 37 |
| army_waves | 55 |
| hut_health | 40 |
| barricades | 44 |
| aggro | 17 |
| campaign_map | 42 |

Die Snapshot-Messung mit vier Akteurslots und voller Forest-Horde lag bei
**2,92 ms im Mittel**, **3,44 ms im schlechtesten Sample**. Bei 10 Hz entspricht das
etwa 2,9 % einer CPU-Sekunde. Dies misst Snapshot-Erstellung, Serialisierung und
Komprimierung; daraus folgt keine Aussage zur Grafikleistung anderer Rechner.

## Behobene Fehler

- Wellenvorschau vor der Initialisierung einer Map dereferenzierte den fehlenden Spielknoten.
- Eskorte erkannte eine kurze Ankunftsroute nicht zuverlässig und konnte ihren Auftrag zu früh abschliessen.
- Ein vorheriges Halteziel blockierte den anschliessenden Waldritual-Ablauf.
- Planes-Erkundung konnte den inzwischen entfernten Wellencontroller abfragen.
- Schlussziel-Niederlagen beendeten den Durchlauf nicht durchgängig.
- Welle 25 konnte die Kampagnenmap vor dem Finale sichern; zehn erfolgreiche Wellen wurden nicht als Gebietssieg vermerkt.
- Waffen-Kühlung wurde vor der abgeschlossenen Nachladephase ausgewertet; Spielstände verloren den Kühlzustand beim Waffenwechsel während des Ladens.
- Sichere Godot-`StringName`-Schlüssel wurden als ungeeignete Speicherdaten abgewiesen.
- Kollisionslose Bäume hinterliessen unbenutzte Physikknoten; verzögertes Verlassen einer Sitzung erhielt einen bereits freigegebenen Spielknoten.
- Die bisherige Netzwerkkennung hätte ältere Clients in die veränderte Expedition-Sitzung gelassen; Protokoll und Buildkennung trennen diese Version nun eindeutig.

Bestehende Tests wurden an die neuen zufallsabhängigen Ziele, das Finale und die
bereits vorhandene 65-Prozent-Wiederbelebung angepasst. Physische Trefferflächen
werden mit ihrer tatsächlichen Kollisionsmaske geprüft. Fehler und fehlende
Abschlussmarker führen weiterhin zu einem fehlgeschlagenen Lauf.

## Wiederholen

Aus dem Repository-Stamm mit Python und `C:/Users/miche/Desktop/Godot.exe`:

```powershell
python tools/test_expansion.py compile_all
python tools/test_expansion_batch.py --parallel 2
python tools/test_expansion.py expedition --render --lang en
python tools/test_expansion.py expedition --render --lang de
python tools/test_expansion_coop.py forest
python tools/test_expansion_coop.py planes
python tools/test_network_compatibility.py
python tools/test_expansion.py online_lobby --label release
python tools/test_expansion_restart.py
python tools/test_expansion_pack.py
python -X utf8 tools/i18n.py check --quiet
git diff --check
```

Bei einem anderen Engine-Pfad die Umgebungsvariable `GODOT` setzen. Die Koop-Läufe
benötigen den lokalen Testport UDP 24783. Auf dem verwendeten Rechner mit 16 GB RAM
werden höchstens drei vollständige Spielwelten gleichzeitig getestet. Die Paketsuite
benötigt den aktuellen lokalen Windows-Export.

Der native Release-Start wird an den Spielbereitschaftsmarkern geprüft. Da die
Release-Vorlage `--script` ignoriert, lädt der funktionale Pakettentest dieselbe PCK
mit dem Godot-Skriptstarter. Eine Dateiverknüpfung verwendet exakt die exportierten
PCK-Daten. Die dafür erforderliche Debug-EOS-Bibliothek liegt ausschliesslich im
isolierten Prüfverzeichnis. Testskripte sind aus der auslieferbaren PCK ausgeschlossen.

## Grenzen der Prüfung

Die Tests prüfen reale Szenen, Kollisionen und Netzwerkprozesse. Einige lang laufende
Zustandsabläufe werden beschleunigt: Gegner werden nach dem tatsächlichen Spawn
entfernt, damit die vollständigen Missions- und Finalzustände geprüft werden können.
Schaden, Waffen, Treffer und gegnerische Bewegung werden zusätzlich separat geprüft.
Dies ersetzt keine lange, von Spielern durchgespielte Balance-Erprobung.

Zwei vollständige Koop-Prozesse wurden verbunden. Vier Slots wurden zusätzlich über
Testakteure geprüft; vier gleichzeitig verbundene vollständige Clients sind damit
nicht nachgewiesen. Internet-Lobbys über EOS, NAT-Verhalten und andere Rechner/Grafikkarten
sind nicht Bestandteil dieses lokalen Nachweises. Die Paketsuite prüft Funktionen
und nativen Start, keinen vernetzten Release-Durchlauf.

Die eingeschränkte Windows-Testumgebung meldet auch im ursprünglichen Projekt
`Failed to read the root certificate store`. Nur diese bekannte Engine-Meldung wird
von den Prüfwerkzeugen ausgenommen. Alle GDScript- und übrigen Engine-Fehler bleiben
Fehlerkriterien. Eine absolute Fehlerfreiheit lässt sich durch diese Prüfungen nicht
garantieren.
